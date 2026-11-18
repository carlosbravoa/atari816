// SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
// Copyright (c) 2026 Carlos Bravo
// a816_sys — Atari816: 65C816 + direct-mapped cache + FREDDIE II (native side) + system I/O.
//
// Clocking: everything runs on clk (clk_core, 28.6875 MHz). The CPU gets a clock enable at
// most every 2nd cycle (14.34 MHz spec speed); a cache miss or a write stretches the cycle.
//
// Bus cycle:
//   S_A  the CPU's (combinational) address is stable; the cache RAM and the protection
//        table read.
//   S_B  tag compare and protection check. Hit / I/O / internal / refused -> CE.
//        Read miss -> S_FILL.  Write -> S_WR.
//   S_FILL  one BL2 burst (8 bytes, the HW-proven half-rate burst) fills the line, back to S_A.
//   S_WR    single masked byte write to SDRAM (write-through; a hit also updates the line).
//
// Cache: 512 lines of 8 bytes (4 KB), line word = {tag, 64 data}. There is no valid bit:
// the tag is the 4 KB page number, and page $00D (the I/O page, never cached) marks an
// empty line. Block RAM has no bulk clear, so the lines are swept empty whenever the CPU
// is held in reset (run = 0).
// Whoever writes 816 memory behind the cache (the I/O processor) must do it with run = 0.
// Classic-machine memory is visible in the native map but the 6502 side writes it behind
// the cache, so native reads of it can be stale (to be solved with the classic map).
//
// FREDDIE II, native side (register spec v0.1, $00:D800-$00:D809):
//   - flat map: AW address bits of RAM, higher banks read $00
//   - bank 0 window: $00:0000-$00:7FFF -> bank B0WIN when B0WIN_EN
//   - user/supervisor mode, 256-entry bank table, ABORT on a refused access
//   Mode is kept on an 8-deep stack: a vector pull pushes the current mode and enters
//   supervisor; an RTI executed in supervisor mode pops it. FR_CTRL.USER_ARM is the top of
//   that stack ("the mode the next RTI returns to"), so nested interrupts and NMIs need no
//   software bookkeeping. This refines rule 2 of the spec.
//   A refused opcode fetch runs as a NOP; a refused access never reaches memory or an I/O
//   register, its data is discarded with the register restore, and it blocks every later write of
//   the same instruction. ABORT_ADDR / ABORT_CAUSE describe the first refused access.
//   A refused push inside an interrupt sequence does not nest: the push is dropped, the
//   sequence goes on, and ABORT_CAUSE is left set for the handler to find.
//
// System I/O (everything else in $00:D000-$00:DFFF reads 0):
//   $00:DE00 SYS_ID     R   $81
//   $00:DE01 SYS_REV    R   REV parameter
//   $00:DE02 SYS_SPEED  R   0 (14.3 MHz)
//   $00:DE08 IRQ_STATUS R/W1C  0 VBLANK, 1 LINE, 2 TIMER0, 3 TIMER1, 4 BLITTER, 5 AUDIO (level), 6 IOP
//   $00:DE09 IRQ_EN     RW  IRQ is asserted while any enabled status bit is set
//   $00:DE0A NMI_STATUS R/W1C  0 SYSTEM_KEY, 1 WATCHDOG. NMI is held while any bit is set, so
//                           a handler must clear what it handled and look again before RTI.
//   $00:DE10-12 TM0_RELOAD RW  microseconds     $00:DE13 TM0_CTRL  0 RUN, 1 REPEAT
//   $00:DE14-16 TM1_RELOAD RW                   $00:DE17 TM1_CTRL
//   $00:DE18-1B UPTIME  R   32-bit microseconds, reading $DE18 latches the other three
//   $00:DE1C WATCHDOG   W   $5A arms a WDOG_US watchdog, $A5 restarts it; expiry = NMI
//   $00:DE20 KB_ROUTE   RW  0 = keys go to Horizon as mailbox events, 1 = to the classic
//                           keyboard. Resets to 1 here (spec says 0) so the classic machine
//                           has its keyboard until Horizon takes it.
//   $00:DE21 JOY_PORT   R   bits 0-3 stick 1 (up, down, left, right), 4-7 stick 2; 1 = pressed
//   $00:DE22 JOY_TRIG   R   bit 0 trigger 1, bit 1 trigger 2
//   $00:DEF0 DBG_OUT    W   bring-up only: byte to the I/O processor log
//
// I/O processor mailbox ($00:DD00-$00:DD0A, register spec): ring positions only; the rings
// live in main RAM. The I/O processor writes responses and buffers behind the cache, so
// the cache is swept empty (18 us, CPU paused) every time it publishes a new MB_RSP_HEAD,
// before the 65C816 can see the new value.
//   $00:D80A CACHE_FLUSH W  (not in spec v0.1) any write sweeps the cache: use before
//                           reading memory that something else writes (classic RAM).
//   $00:DEF1 DBG_STAT   R   bring-up only: bit 7 = DBG_OUT busy

module a816_sys #(
    parameter int AW    = 23,         // RAM-backed native address bits (23 -> 8 MB)
    parameter logic [7:0] REV = 8'h0B,
    parameter int WDOG_US = 2_000_000
) (
    input  wire         clk,
    input  wire         reset_n,
    input  wire         run,          // 1 = CPU released (already synchronous to clk)
    input  wire         sys_key,      // 1-cycle pulse: system key (F12) pressed
    output reg          kb_route,     // 1 = keyboard belongs to the classic machine
    output reg          sv_freeze,    // 1 = classic machine frozen (SV_CTRL.FREEZE_REQ)
    input  wire [9:0]   joy_n_a,      // async, active low: {stick 2 [4:0], stick 1 [4:0]}, bit 4 = trigger

    // I/O processor mailbox. Outputs are quasi-static (clk); inputs are asynchronous.
    output reg  [23:0]  mb_req_base,
    output reg  [7:0]   mb_req_head,
    output reg  [23:0]  mb_rsp_base,
    output reg  [7:0]   mb_rsp_tail,
    input  wire [7:0]   mb_req_tail_a,
    input  wire [7:0]   mb_rsp_head_a,
    input  wire [1:0]   mb_status_a,

    // register bus for blocks outside this module ($00:D9xx = NVC, $00:DAxx = blitter)
    output wire         snd_wr,       // write to $00:DB00-$DB1F (native sound, data on xio_wdata, address on xio_addr[4:0])
    output wire         xio_wr,       // write to $00:D9xx
    output wire         xio_rd,       // 1-cycle strobe: a read of $00:D9xx completes (for read latches)
    output wire         blt_wr,       // write to $00:DAxx
    output wire [7:0]   xio_addr,
    output wire [7:0]   xio_wdata,
    input  wire [7:0]   xio_rdata,    // $00:D9xx read data (combinational from xio_addr)
    input  wire [7:0]   blt_rdata,    // $00:DAxx read data
    output wire         aud_wr,       // write to $00:DBxx (sample player; $DB00-$DB1F also snd_wr)
    output wire         aud_rd,       // read strobe $00:DBxx
    input  wire [7:0]   aud_rdata,    // $00:DBxx read data
    input  wire         irq_audio,    // level -> IRQ_STATUS bit 5 (AUDIO)
    input  wire         irq_vblank,   // 1-cycle pulses -> IRQ_STATUS bits 0, 1 and 4
    input  wire         irq_line,
    input  wire         irq_blit,

    // SDRAM client (arbiter side, same clock)
    output reg          sd_req,       // held until sd_done
    output reg          sd_we,        // 1 = byte write, 0 = 8-byte burst read
    output reg  [AW-1:0] sd_addr,     // native RAM address, after the bank 0 window (burst: 8-byte aligned)
    output reg  [7:0]   sd_wdata,
    input  wire         sd_done,      // 1-cycle pulse; sd_rdata valid in that cycle
    input  wire [63:0]  sd_rdata,

    // debug byte port to the I/O processor (two-toggle handshake)
    output reg  [7:0]   dbg_data,
    output reg          dbg_tgl,
    input  wire         dbg_ack_tgl   // toggles to match dbg_tgl when consumed (async)
);

localparam int IDXW  = 9;                       // 512 lines x 8 bytes: index + offset = one 4 KB page
localparam int TAGW  = AW - 12;                 // tag = 4 KB page number
localparam int LINEW = 64 + TAGW;
localparam logic [TAGW-1:0] TAG_EMPTY = TAGW'(12'h00D);   // $00:Dxxx = I/O, never cached

// ── CPU ──────────────────────────────────────────────────────────────────────
wire [23:0] cpu_a;
wire [7:0]  cpu_do;
reg  [7:0]  cpu_di;
wire        cpu_we_n, cpu_vpa, cpu_vda, cpu_vpb, cpu_step, cpu_int_seq;
reg         cpu_ce;
wire        abort_n, irq_n, nmi_n;
reg         cpu_rst_n = 1'b0;

P65C816 cpu (
    .CLK(clk), .RST_N(cpu_rst_n), .CE(cpu_ce),
    .RDY_IN(1'b1), .NMI_N(nmi_n), .IRQ_N(irq_n), .ABORT_N(abort_n),
    .D_IN(cpu_di), .D_OUT(cpu_do), .A_OUT(cpu_a),
    .WE_N(cpu_we_n), .RDY_OUT(cpu_step), .VPA(cpu_vpa), .VDA(cpu_vda), .MLB(), .VPB(cpu_vpb), .INT_SEQ(cpu_int_seq),
    .BRK_OUT(), .DBG_REG(8'h00), .DBG_DAT_IN(8'h00), .DBG_DAT_OUT(), .DBG_DAT_WR(1'b0)
);

wire        valid_addr = cpu_vpa | cpu_vda;
wire        is_write   = ~cpu_we_n;
wire        is_io      = (cpu_a[23:12] == 12'h00D);          // $00:D000-$00:DFFF
wire        no_ram     = |cpu_a[23:AW];                      // above the installed RAM

// ── FREDDIE II state ─────────────────────────────────────────────────────────
reg         fr_prot_en, fr_b0win_en, fr_wp_vec;
reg  [7:0]  pt_index, b0win;
reg  [5:0]  cur_task;
reg  [23:0] abort_addr;
reg  [4:0]  abort_cause;
reg         mode_user;                 // current mode
reg  [7:0]  mstack;                    // mode stack, [0] = top = FR_CTRL.USER_ARM
reg         rti_seen, in_pull, wr_block;

// bank 0 window
wire        b0_hit   = fr_b0win_en && (cpu_a[23:15] == 9'd0);
wire [7:0]  eff_bank = b0_hit ? b0win : cpu_a[23:16];
wire [AW-1:0] eff_a  = {eff_bank[AW-17:0], cpu_a[15:0]};
wire [IDXW-1:0] a_idx  = cpu_a[IDXW+2:3];
wire [TAGW-1:0] a_tag  = eff_a[AW-1:IDXW+3];

// protection table: one block RAM, read with the cache line in S_A
reg  [7:0]  pt [0:255];
reg  [7:0]  pt_q;
reg         pt_we;
wire [7:0]  pt_raddr = is_io ? pt_index : cpu_a[23:16];
always_ff @(posedge clk) begin
    if (pt_we) pt[pt_index] <= cpu_do;
    pt_q <= pt[pt_raddr];
end

// mode for the current cycle
wire        sync     = cpu_vpa & cpu_vda;                    // opcode fetch
// A BRK/COP whose push was refused is being aborted: its own vector pull must not enter
// supervisor mode, or the ABORT sequence that follows would push to a stack pointer the
// task chose with kernel rights.
wire        vpull    = ~cpu_vpb && !(wr_block && !cpu_int_seq);   // vector pull that counts
wire        pop      = sync & rti_seen;                      // first fetch after an RTI
wire        user_eff = vpull ? 1'b0 : (pop ? mstack[0] : mode_user);

// access check (valid in S_B)
wire        own_ok   = (pt_q[5:0] == cur_task) || (pt_q[5:0] == 6'd63);
wire        in_table = !b0_hit && !is_io;                    // the window is always the task's own
wire        u_io     = user_eff && is_io;
wire        u_nvalid = user_eff && in_table && !pt_q[7];
wire        u_nowner = user_eff && in_table &&  pt_q[7] && !own_ok;
wire        u_ro     = user_eff && in_table &&  pt_q[7] &&  own_ok && is_write && !pt_q[6];
wire        s_wpvec  = !user_eff && fr_wp_vec && is_write && (cpu_a[23:13] == 11'b0000_0000_111);
// The reads of an interrupt sequence are its two discarded fetches and the vector pull;
// they are not checked (after a refused opcode fetch they would hit the same address
// again). Its pushes are.
wire        refuse   = valid_addr && !(cpu_int_seq && !is_write) &&
                       ((fr_prot_en && (u_io | u_nvalid | u_nowner | u_ro)) | s_wpvec);
wire        blocked  = refuse || (wr_block && is_write);     // this access must not happen

// ── Cache RAM (inferred block RAM, one write port, one registered read port) ──
reg  [LINEW-1:0] cmem [0:(1<<IDXW)-1];
reg  [LINEW-1:0] line_q;
reg              c_we;
reg  [IDXW-1:0]  c_waddr;
reg  [LINEW-1:0] c_wdata;

always_ff @(posedge clk) begin
    if (c_we) cmem[c_waddr] <= c_wdata;
    line_q <= cmem[a_idx];
end

wire [TAGW-1:0]  l_tag   = line_q[64 +: TAGW];
wire [63:0]      l_data  = line_q[63:0];
wire             hit     = (l_tag == a_tag);          // only meaningful when !is_io
wire [7:0]       l_byte  = l_data[{cpu_a[2:0], 3'b000} +: 8];

// ── Microsecond clock: 28.6875 MHz = 459/16 cycles per microsecond ────────────
reg  [8:0]  us_acc = 9'd0;
reg  [31:0] uptime = 32'd0;
reg  [23:0] uptime_lat;
wire        us_tick = (us_acc >= 9'd443);

// interrupts, timers, watchdog (registers written in the block at the end of the file)
reg  [7:0]  irq_status, irq_en;
reg  [1:0]  nmi_status;
reg  [23:0] tm_reload [0:1];
reg  [23:0] tm_count  [0:1];
reg  [1:0]  tm_run, tm_rep;
reg  [20:0] wd_count;
reg         wd_armed;
// mailbox: synchronised copies of the I/O processor's side
reg  [17:0] mb_s1, mb_s2, mb_st;        // {status, rsp_head, req_tail}
reg  [9:0]  joy_s1, joy_s2;
reg  [7:0]  rsp_head_vis, rsp_head_tgt;
reg         flush_req;
wire        iop_pending = (rsp_head_vis != mb_rsp_tail);
wire [7:0]  irq_now = irq_status | {1'b0, iop_pending, irq_audio, 5'd0};
assign irq_n = ~|(irq_now & irq_en);
// NMI is held from an entry out of user mode until the kernel writes FR_CTRL: the first
// kernel instructions still run on the task's stack pointer, and an NMI there would push
// to an address the task chose, with kernel rights.
reg         nmi_hold;
assign nmi_n = ~(|nmi_status && !nmi_hold);
always_ff @(posedge clk) begin
    if (!cpu_rst_n) begin
        us_acc <= 9'd0;
        uptime <= 32'd0;
    end else if (us_tick) begin
        us_acc <= us_acc - 9'd443;          // +16 -459
        uptime <= uptime + 32'd1;
    end else begin
        us_acc <= us_acc + 9'd16;
    end
end

// ── I/O read mux ─────────────────────────────────────────────────────────────
reg  ack_s1 = 1'b0, ack_s2 = 1'b0;
always_ff @(posedge clk) begin ack_s1 <= dbg_ack_tgl; ack_s2 <= ack_s1; end
wire dbg_busy = dbg_tgl ^ ack_s2;

reg [7:0] io_rd;
always_comb begin
    case (cpu_a[11:0])
        12'h800: io_rd = {mode_user, 3'b000, fr_wp_vec, fr_b0win_en, mstack[0], fr_prot_en};
        12'h801: io_rd = pt_index;
        12'h802: io_rd = pt_q;
        12'h803: io_rd = {2'b00, cur_task};
        12'h804: io_rd = abort_addr[7:0];
        12'h805: io_rd = abort_addr[15:8];
        12'h806: io_rd = abort_addr[23:16];
        12'h807: io_rd = {3'b000, abort_cause};
        12'h808: io_rd = b0win;
        12'h809: io_rd = 8'((1 << (AW - 16)) - 1);
        12'hE00: io_rd = 8'h81;
        12'hE01: io_rd = REV;
        12'hD00: io_rd = mb_req_base[7:0];
        12'hD01: io_rd = mb_req_base[15:8];
        12'hD02: io_rd = mb_req_base[23:16];
        12'hD03: io_rd = mb_req_head;
        12'hD04: io_rd = mb_st[7:0];
        12'hD05: io_rd = mb_rsp_base[7:0];
        12'hD06: io_rd = mb_rsp_base[15:8];
        12'hD07: io_rd = mb_rsp_base[23:16];
        12'hD08: io_rd = rsp_head_vis;
        12'hD09: io_rd = mb_rsp_tail;
        12'hD0A: io_rd = {6'd0, mb_st[17:16]};
        12'hE08: io_rd = irq_now;
        12'hE09: io_rd = irq_en;
        12'hE0A: io_rd = {6'd0, nmi_status};
        12'hE10: io_rd = tm_reload[0][7:0];
        12'hE11: io_rd = tm_reload[0][15:8];
        12'hE12: io_rd = tm_reload[0][23:16];
        12'hE13: io_rd = {6'd0, tm_rep[0], tm_run[0]};
        12'hE14: io_rd = tm_reload[1][7:0];
        12'hE15: io_rd = tm_reload[1][15:8];
        12'hE16: io_rd = tm_reload[1][23:16];
        12'hE17: io_rd = {6'd0, tm_rep[1], tm_run[1]};
        12'hC00: io_rd = {5'd0, sv_freeze, 2'b01};      // SV_CTRL: 0 RUN (always 1), 2 FREEZE_REQ
        12'hC01: io_rd = {7'd0, sv_freeze};             // SV_STATUS: 0 FROZEN
        12'hE20: io_rd = {7'd0, kb_route};
        12'hE21: io_rd = ~{joy_s2[8:5], joy_s2[3:0]};
        12'hE22: io_rd = {6'd0, ~joy_s2[9], ~joy_s2[4]};
        12'hE18: io_rd = uptime[7:0];
        12'hE19: io_rd = uptime_lat[7:0];
        12'hE1A: io_rd = uptime_lat[15:8];
        12'hE1B: io_rd = uptime_lat[23:16];
        12'hEF1: io_rd = {dbg_busy, 7'd0};
        default: io_rd = (cpu_a[11:8] == 4'h9) ? xio_rdata :
                         (cpu_a[11:8] == 4'hA) ? blt_rdata :
                         (cpu_a[11:8] == 4'hB) ? aud_rdata : 8'h00;
    endcase
end
assign xio_wr    = io_wr && (cpu_a[11:8] == 4'h9);
assign xio_rd    = io_rd_stb && (cpu_a[11:8] == 4'h9);
assign aud_wr    = io_wr && (cpu_a[11:8] == 4'hB);
assign aud_rd    = io_rd_stb && (cpu_a[11:8] == 4'hB);
assign blt_wr    = io_wr && (cpu_a[11:8] == 4'hA);
assign snd_wr    = io_wr && (cpu_a[11:5] == 7'b1011_000);
assign xio_addr  = cpu_a[7:0];
assign xio_wdata = cpu_do;

// ── Bus FSM ──────────────────────────────────────────────────────────────────
typedef enum logic [2:0] { S_SWEEP, S_A, S_B, S_FILL, S_WR } st_t;
st_t st = S_SWEEP;
reg [IDXW:0] sweep = '0;               // MSB set = one full pass done

// sd_addr / sd_wdata are registered with sd_req: they cross into the 2x SDRAM clock, so
// they must not hang off the CPU's combinational address and data outputs.

// line with the written byte replaced (write hit)
reg [63:0] l_data_wr;
always_comb begin
    l_data_wr = l_data;
    l_data_wr[{cpu_a[2:0], 3'b000} +: 8] = cpu_do;
end

wire fast = !valid_addr || is_io || no_ram || blocked || (!is_write && hit);   // cycle completes in S_B
wire io_wr = (st == S_B) && cpu_step && valid_addr && is_io && is_write && !blocked;
wire io_rd_stb = (st == S_B) && cpu_step && valid_addr && is_io && !is_write && !refuse;
assign abort_n = ~((st == S_B) && refuse);

always_comb begin
    cpu_di  = no_ram ? 8'h00 : is_io ? io_rd : l_byte;   // a refused read's value is never kept
    pt_we   = io_wr && (cpu_a[11:0] == 12'h802);
    cpu_ce  = 1'b0;
    c_we    = 1'b0;
    c_waddr = a_idx;
    c_wdata = {a_tag, sd_rdata};
    case (st)
        S_SWEEP: begin c_we = 1'b1; c_waddr = sweep[IDXW-1:0]; c_wdata = {TAG_EMPTY, 64'd0}; end
        S_B: begin
            cpu_ce = fast;
            if (valid_addr && !is_io && !no_ram && !blocked && is_write && hit) begin
                c_we    = 1'b1;
                c_wdata = {a_tag, l_data_wr};
            end
        end
        S_FILL: c_we = sd_done;
        S_WR:   cpu_ce = sd_done;
        default: ;
    endcase
end

always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        st        <= S_SWEEP;
        sweep     <= '0;
        cpu_rst_n <= 1'b0;
        sd_req    <= 1'b0;
        sd_we     <= 1'b0;
        sd_addr   <= '0;
        sd_wdata  <= 8'h00;
        dbg_tgl   <= 1'b0;
        dbg_data  <= 8'h00;
        uptime_lat <= 24'd0;
    end else begin
        case (st)
            S_SWEEP: begin
                if (!run) cpu_rst_n <= 1'b0;                 // a flush sweep leaves the CPU alone
                if (!sweep[IDXW]) sweep <= sweep + 1'b1;     // one full pass, then park
                else if (run) begin
                    cpu_rst_n <= 1'b1;
                    st        <= S_A;
                end
            end
            S_A: begin
                if (!run || flush_req) begin
                    st    <= S_SWEEP;
                    sweep <= '0;
                end else st <= S_B;
            end
            S_B: begin
                if (fast) begin
                    st <= S_A;
                    if (io_wr && cpu_a[11:0] == 12'hEF0 && !dbg_busy) begin
                        dbg_data <= cpu_do;
                        dbg_tgl  <= ~dbg_tgl;
                    end
                    if (cpu_step && valid_addr && is_io && !is_write && !refuse && cpu_a[11:0] == 12'hE18)
                        uptime_lat <= uptime[31:8];
                end else begin
                    sd_req   <= 1'b1;
                    sd_we    <= is_write;
                    sd_addr  <= is_write ? eff_a : {eff_a[AW-1:3], 3'b000};
                    sd_wdata <= cpu_do;
                    st     <= is_write ? S_WR : S_FILL;
                end
            end
            S_FILL: if (sd_done) begin sd_req <= 1'b0; st <= S_A; end
            S_WR:   if (sd_done) begin sd_req <= 1'b0; st <= S_A; end
            default: st <= S_SWEEP;
        endcase
    end
end

// ── FREDDIE II registers and mode ────────────────────────────────────────────
always_ff @(posedge clk) begin
    if (!cpu_rst_n) begin
        fr_prot_en <= 1'b0;  fr_b0win_en <= 1'b0;  fr_wp_vec <= 1'b0;
        pt_index   <= 8'h00; b0win <= 8'h00;       cur_task  <= 6'd0;
        abort_addr <= 24'd0; abort_cause <= 5'd0;
        mode_user  <= 1'b0;  mstack <= 8'h00;
        rti_seen   <= 1'b0;  in_pull <= 1'b0;      wr_block  <= 1'b0;
        nmi_hold   <= 1'b0;
    end else begin
        // mode tracking, once per CPU cycle
        if (cpu_step) begin
            if (vpull) begin
                if (!in_pull) mstack <= {mstack[6:0], mode_user};
                if (!in_pull && mode_user) nmi_hold <= 1'b1;
                mode_user <= 1'b0;
                in_pull   <= 1'b1;
                rti_seen  <= 1'b0;
            end else begin
                in_pull <= 1'b0;
                if (sync) begin
                    if (pop) begin
                        mode_user <= mstack[0];
                        mstack    <= {1'b0, mstack[7:1]};
                    end
                    rti_seen <= (cpu_di == 8'h40) && !user_eff && !cpu_int_seq && !refuse;
                end
            end
        end

        // refused access: record the first one of the instruction, block its later writes
        // (wr_block ends at the next opcode fetch, so the ABORT sequence's own pushes go through)
        if (cpu_step && sync) wr_block <= 1'b0;
        if (st == S_B && refuse && cpu_step) begin
            wr_block <= 1'b1;
            if (!wr_block) begin
                abort_addr  <= cpu_a;
                abort_cause <= abort_cause | {s_wpvec, u_io, u_nvalid, u_nowner, is_write};
            end
        end

        // register writes
        if (io_wr) begin
            case (cpu_a[11:0])
                12'h800: begin
                    nmi_hold    <= 1'b0;
                    fr_prot_en  <= cpu_do[0];
                    mstack[0]   <= cpu_do[1];
                    fr_b0win_en <= cpu_do[2];
                    fr_wp_vec   <= cpu_do[3];
                end
                12'h801: pt_index    <= cpu_do;
                12'h803: cur_task    <= cpu_do[5:0];
                12'h807: abort_cause <= abort_cause & ~cpu_do[4:0];
                12'h808: b0win       <= cpu_do;
                default: ;
            endcase
        end
    end
end

// mailbox input synchroniser: two flops, and a value is taken only when two samples agree
always_ff @(posedge clk) begin
    joy_s1 <= joy_n_a; joy_s2 <= joy_s1;
    mb_s1 <= {mb_status_a, mb_rsp_head_a, mb_req_tail_a};
    mb_s2 <= mb_s1;
    if (mb_s1 == mb_s2) mb_st <= mb_s2;
end

// ── System block: interrupts, timers, watchdog, mailbox registers ────────────
always_ff @(posedge clk) begin
    if (!cpu_rst_n) begin
        irq_status <= 8'h00; irq_en <= 8'h00; nmi_status <= 2'b00;
        tm_run <= 2'b00; tm_rep <= 2'b00;
        tm_reload[0] <= 24'd0; tm_reload[1] <= 24'd0;
        tm_count[0]  <= 24'd0; tm_count[1]  <= 24'd0;
        wd_armed <= 1'b0; wd_count <= 21'd0;
        mb_req_base <= 24'd0; mb_req_head <= 8'd0; mb_rsp_base <= 24'd0; mb_rsp_tail <= 8'd0;
        rsp_head_vis <= 8'd0; rsp_head_tgt <= 8'd0; flush_req <= 1'b0;
        kb_route <= 1'b1;
        sv_freeze <= 1'b0;
    end else begin
        for (int t = 0; t < 2; t++) begin
            if (us_tick && tm_run[t]) begin
                if (tm_count[t] <= 24'd1) begin
                    irq_status[2 + t] <= 1'b1;
                    tm_count[t] <= tm_reload[t];
                    if (!tm_rep[t]) tm_run[t] <= 1'b0;
                end else tm_count[t] <= tm_count[t] - 24'd1;
            end
        end
        if (irq_vblank) irq_status[0] <= 1'b1;
        if (irq_line)   irq_status[1] <= 1'b1;
        if (irq_blit)   irq_status[4] <= 1'b1;
        if (us_tick && wd_armed) begin
            if (wd_count == 21'd0) begin
                nmi_status[1] <= 1'b1;
                wd_armed <= 1'b0;
            end else wd_count <= wd_count - 21'd1;
        end
        if (sys_key) nmi_status[0] <= 1'b1;

        // mailbox: take a new MB_RSP_HEAD only after the cache has been swept
        if (mb_st[15:8] != rsp_head_tgt && !flush_req) begin
            rsp_head_tgt <= mb_st[15:8];
            flush_req    <= 1'b1;
        end
        if (io_wr && cpu_a[11:0] == 12'h80A) flush_req <= 1'b1;
        if (st == S_SWEEP && sweep[IDXW]) begin
            flush_req    <= 1'b0;
            rsp_head_vis <= rsp_head_tgt;
        end

        if (io_wr) begin
            case (cpu_a[11:0])
                12'hE08: irq_status <= irq_status & ~cpu_do;      // a source firing in this very cycle is lost; timers re-fire
                12'hD00: mb_req_base[7:0]   <= cpu_do;
                12'hD01: mb_req_base[15:8]  <= cpu_do;
                12'hD02: mb_req_base[23:16] <= cpu_do;
                12'hD03: mb_req_head        <= cpu_do;
                12'hD05: mb_rsp_base[7:0]   <= cpu_do;
                12'hD06: mb_rsp_base[15:8]  <= cpu_do;
                12'hD07: mb_rsp_base[23:16] <= cpu_do;
                12'hD09: mb_rsp_tail        <= cpu_do;
                12'hE09: irq_en     <= cpu_do;
                12'hE20: kb_route   <= cpu_do[0];
                12'hC00: sv_freeze <= cpu_do[2];
                12'hE0A: nmi_status <= nmi_status & ~cpu_do[1:0];
                12'hE10: tm_reload[0][7:0]   <= cpu_do;
                12'hE11: tm_reload[0][15:8]  <= cpu_do;
                12'hE12: tm_reload[0][23:16] <= cpu_do;
                12'hE13: begin
                    tm_rep[0] <= cpu_do[1]; tm_run[0] <= cpu_do[0];
                    if (cpu_do[0] && !tm_run[0]) tm_count[0] <= tm_reload[0];
                end
                12'hE14: tm_reload[1][7:0]   <= cpu_do;
                12'hE15: tm_reload[1][15:8]  <= cpu_do;
                12'hE16: tm_reload[1][23:16] <= cpu_do;
                12'hE17: begin
                    tm_rep[1] <= cpu_do[1]; tm_run[1] <= cpu_do[0];
                    if (cpu_do[0] && !tm_run[1]) tm_count[1] <= tm_reload[1];
                end
                12'hE1C: begin
                    if (cpu_do == 8'h5A) wd_armed <= 1'b1;
                    if (cpu_do == 8'h5A || (cpu_do == 8'hA5 && wd_armed)) wd_count <= 21'(WDOG_US - 1);
                end
                default: ;
            endcase
        end
    end
end

endmodule
