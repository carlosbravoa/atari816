// SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
// Copyright (c) 2026 Carlos Bravo
// Ali, the Atari816 blitter: FILL, COPY, COPY_KEY, EXPAND, EXPAND_KEY on 8 bpp rectangles in main RAM,
// and (REV $0D) TABLE, COPY_REMAP and COPY_KEY_REMAP through the colour remap table.
//
// Registers ($00:DA00-$DA13, register spec "Ali (blitter)"):
//   $DA00-02 BL_SRC   $DA03-04 BL_SRC_STRIDE   $DA05-07 BL_DST   $DA08-09 BL_DST_STRIDE
//   $DA0A-0B BL_WIDTH $DA0C-0D BL_HEIGHT       $DA0E BL_FG  $DA0F BL_BG  $DA10 BL_KEY
//   $DA11 BL_OP (0 FILL, 1 COPY, 2 COPY_KEY, 3 EXPAND, 4 EXPAND_KEY; REV $0D: 5 TABLE, 6 COPY_REMAP,
//         7 COPY_KEY_REMAP)
//   $DA12 BL_FLAGS (0 BACKWARDS, 6:4 SRC_BIT)
//   $DA13 BL_CTRL  write: 0 START, 1 IRQ_EN, 2 LIST, 3 ABORT
//                  read:  0 BUSY, 1 IRQ_EN, 2 LIST (running), 3 WAITING (for VBLANK), 4 DONE, 5 ABORTED
//   $DA14-16 BL_LIST  next command record (8-byte aligned)   $DA17-18 BL_COUNT records still to run
// Command lists (REV $09): records of 24 bytes in RAM, bytes 0-18 laid out like $DA00-$DA12,
// byte 19 bit 0 WAIT_VBL. Each record is read as three 8-byte bursts through the blitter's
// port and written byte by byte into the register file (the same write port as the CPU's),
// then the blit runs as after START. BUSY covers the whole list; the interrupt comes once at
// its end. ABORT stops a list or a blit after the access in flight; no interrupt then.
// Behaviour where the spec is open follows the emulator (emu/blitter.c):
//   - WIDTH or HEIGHT 0, or OP above 7, does nothing; WIDTH / HEIGHT above 4096 count as 4096.
//     Every START still ends with the BLITTER interrupt when IRQ_EN is set.
//   - BACKWARDS: lines from the last to the first, pixels right to left; BL_SRC / BL_DST still
//     name the top-left byte. Copies give the emulator's result whenever the direction suits the
//     overlap (forward when the destination starts below the source address, else BACKWARDS).
//   - EXPAND: line y starts at BL_SRC + y * BL_SRC_STRIDE, bit SRC_BIT (7 = leftmost), and the
//     bit position runs on into the following bytes.
// Hardware rules (not in the emulator, which completes a blit inside the START write):
//   - $DA00-$DA12 are used while the blit runs: writes to them (and to $DA14-$DA18) are
//     ignored while BUSY = 1. START / LIST while BUSY are ignored. IRQ_EN and ABORT may be
//     written at any time.
//   - Addresses wrap at the installed RAM (AW bits).
//   - The blitter writes behind the 65C816's cache: write CACHE_FLUSH ($00:D80A) before the CPU
//     reads memory the blitter has written.
//
// Datapath. The destination is written in aligned 32-bit words with a byte mask (FILL needs no
// reads; the keyed ops only clear mask bits, so nothing is read back). Lines are independent:
// per line a short setup computes the first destination word, the first and last word masks,
// and the source position of the first destination byte, as a word address and an offset in
// "units" (bytes for COPY, bits for EXPAND). Source words come from 8- or 16-byte bursts into
// sbuf and are moved one per cycle into a two-word window {hi, lo}; a destination word takes
// 32 bits (COPY, byte offset 0-3) or 4 bits (EXPAND, bit offset 0-31) from the window.
// BACKWARDS runs the very same pipeline in mirrored address space: source words are taken in
// descending order and byte-reversed, the produced word is byte-reversed back, and the masks
// and start offsets are mirrored in the line setup.
// Pipeline: P1 produces the next word's raw pixels and edge mask into the stage (xq, xm),
// P2 turns the stage into the request registers b_* (data, key / bit mask). The request
// registers are free again the cycle after the port mux has taken them (b_gnt; only b_req
// depends on it combinationally), so the next write waits in b_* while the previous one runs.
// Requests leave in order, and a source read is only placed when no produced word is waiting
// (REV $0D: or one is in the lanes), so every read follows the writes of the words before it
// (but that one). Source data is read ahead of its
// use (up to a burst plus the window); in between it can only be overwritten by writes of
// earlier destination words, which cannot reach source bytes still to be used when the copy
// direction suits the overlap. The window takes words while a write runs, so a read is
// placed as soon as the previous write has been taken.
//
// Colour remap (REV $0D). A 256 x 8 table in one block RAM. TABLE (OP 5) is a COPY whose
// destination is the table instead of RAM: destination byte addresses count modulo 256 (the
// table entry), so SRC = 256 bytes, DST = 0, WIDTH 256, HEIGHT 1 loads a whole table; nothing is
// written to RAM. COPY_REMAP (6) and COPY_KEY_REMAP (7) are COPY and COPY_KEY writing table[src]
// for every source pixel; the key is tested on the source pixel, before the table. All three use
// the "lanes", a
// small sequencer on the stage (xq): when a produced word needs them (lane), P2 waits for xr
// while the four bytes go through the table one a cycle (the block RAM's read is registered):
// lc 0-3 present byte lc (a lookup, or a table write for TABLE), lc 1-4 take the lookup of byte
// lc - 1 back into xq; at lc 0 the key clears the edge mask bits of the key's pixels (so P2 does
// not test the remapped values). Five cycles a word, while the word before it is written: the
// SDRAM's write takes longer, so a remapped copy runs at nearly the speed of a plain one.
`default_nettype none

module a816_blit #(
    parameter int AW = 23
) (
    input  wire          clk,          // clk_core
    input  wire          reset_n,
    input  wire          run,          // 0 = 65C816 held in reset: registers return to reset values

    // register bus from a816_sys ($00:DAxx)
    input  wire          xio_wr,
    input  wire [7:0]    xio_addr,
    input  wire [7:0]    xio_wdata,
    output reg  [7:0]    xio_rdata,
    output reg           irq,          // 1-cycle pulse: blit (or list) done with IRQ_EN
    input  wire          vbl,          // 1-cycle pulse: VBLANK event (for WAIT_VBL records)

    // SDRAM port, through the mux in a816_nvc (lowest priority)
    output reg           b_req,        // b_* hold a request
    input  wire          b_gnt,        // the mux takes it in this cycle
    output reg           b_we,         // 1 = 32-bit word write with b_wmask, 0 = burst read
    output reg  [AW-1:0] b_addr,
    output reg  [31:0]   b_wdata,
    output reg  [3:0]    b_wmask,
    output reg           b_long,       // read: 16 bytes (else 8)
    input  wire          b_done,       // 1-cycle pulse at the end of the access
    input  wire [127:0]  b_rdata,      // burst data, valid with b_done
    input  wire          long_ok       // 16-byte bursts allowed
);

localparam int WA = AW - 2;            // word address bits
localparam int XW = AW + 3;            // source position in units (bits for EXPAND)

// ── registers ────────────────────────────────────────────────────────────────
reg [23:0] r_src, r_dst;
reg [15:0] r_sstr, r_dstr, r_w, r_h;
reg [7:0]  r_fg, r_bg, r_key, r_op, r_flags;
reg        r_irqen;
reg [23:3] r_list;                     // next record, in 8-byte units
reg [15:0] r_cnt;
reg        r_wvbl;                     // the loaded record's WAIT_VBL
reg        f_done, f_abrt;             // DONE, ABORTED

wire       back    = r_flags[0];
wire [2:0] sbit    = r_flags[6:4];
wire       is_fill = (r_op[2:0] == 3'd0);              // r_op < 8 is checked at START
wire       is_exp  = (r_op[2:0] == 3'd3) || (r_op[2:0] == 3'd4);
wire       keyed   = (r_op[2:0] == 3'd2) || (r_op[2:0] == 3'd4) || (r_op[2:0] == 3'd7);
wire       is_tbl  = (r_op[2:0] == 3'd5);              // TABLE: a COPY into the remap table
wire       remap   = (r_op[2:0] == 3'd6) || (r_op[2:0] == 3'd7);   // COPY(_KEY)_REMAP
wire       lane    = is_tbl || remap;                   // produced words go through the lanes
wire       kq      = keyed && !remap;                   // P2 tests the key (remap: the lanes did)

typedef enum logic [2:0] { S_IDLE, S_PRE, S_LS0, S_LS1, S_LS2, S_RUN, S_LEND, S_FIN } st_t;
st_t st;
// list sequencer: read a burst, load its bytes, (wait for VBLANK,) run the blit, next record
typedef enum logic [2:0] { L_IDLE, L_RD, L_WT, L_LD, L_CHK, L_VBL, L_GO, L_RUN } lst_t;
lst_t lst;
reg  [4:0] lk;                         // record byte being loaded, 0..19
reg        infl, infl_rd;              // an access is running in the mux; it is a read
wire busy = (st != S_IDLE) || (lst != L_IDLE) || infl || b_req;

always_comb begin
    case (xio_addr)
        8'h00: xio_rdata = r_src[7:0];
        8'h01: xio_rdata = r_src[15:8];
        8'h02: xio_rdata = r_src[23:16];
        8'h03: xio_rdata = r_sstr[7:0];
        8'h04: xio_rdata = r_sstr[15:8];
        8'h05: xio_rdata = r_dst[7:0];
        8'h06: xio_rdata = r_dst[15:8];
        8'h07: xio_rdata = r_dst[23:16];
        8'h08: xio_rdata = r_dstr[7:0];
        8'h09: xio_rdata = r_dstr[15:8];
        8'h0A: xio_rdata = r_w[7:0];
        8'h0B: xio_rdata = r_w[15:8];
        8'h0C: xio_rdata = r_h[7:0];
        8'h0D: xio_rdata = r_h[15:8];
        8'h0E: xio_rdata = r_fg;
        8'h0F: xio_rdata = r_bg;
        8'h10: xio_rdata = r_key;
        8'h11: xio_rdata = r_op;
        8'h12: xio_rdata = r_flags;
        8'h13: xio_rdata = {2'd0, f_abrt, f_done, lst == L_VBL, lst != L_IDLE, r_irqen, busy};
        8'h14: xio_rdata = {r_list[7:3], 3'b000};
        8'h15: xio_rdata = r_list[15:8];
        8'h16: xio_rdata = r_list[23:16];
        8'h17: xio_rdata = r_cnt[7:0];
        8'h18: xio_rdata = r_cnt[15:8];
        default: xio_rdata = 8'h00;
    endcase
end

// ── working state ────────────────────────────────────────────────────────────
reg  [AW-1:0] sl, dl;                  // first byte of the current source / destination line
reg  [11:0]   yc, hm1, wm1;            // line counter, HEIGHT - 1, WIDTH - 1
reg  [10:0]   kl, nwl;                 // words in the line - 1, words still to produce - 1
reg  [3:0]    fmask, emask;            // byte masks of the first / last produced word
reg  [XW-1:0] xs;                      // line setup: source position in units
reg  [WA-1:0] swa, dwa;                // next source word to take, next destination word
reg  [4:0]    o;                       // window offset in bits (COPY: multiple of 8)
reg  [1:0]    n;                       // valid words in the window: lo, then hi
reg  [31:0]   lo, hi;
reg           first;
reg  [127:0]  sbuf;                    // last burst
reg           sbv, sb_long;            // sbuf holds the group of swa; it is 16 bytes
reg           rd_wait;                 // a read has been placed and its data is not in yet
reg  [31:0]   xq;                      // stage: COPY bytes, or EXPAND bits in [3:0]
reg  [3:0]    xm;                      // stage: edge mask
reg           xv;
reg           xr;                      // the stage may leave (P2): set with xv, or by the lanes
reg  [2:0]    lc;                      // the lanes' step, 0-4

// line stepping: forward, and also for the pre-pass that finds the last line of a BACKWARDS blit
wire          sub   = back && (st != S_PRE);
wire [AW-1:0] sl_nx = sub ? sl - AW'(r_sstr) : sl + AW'(r_sstr);
wire [AW-1:0] dl_nx = sub ? dl - AW'(r_dstr) : dl + AW'(r_dstr);

// line setup
wire [1:0]    dl2   = dl[1:0];
wire [12:0]   t13   = {1'b0, wm1} + {11'd0, dl2};          // offset of the last pixel from the first word
wire [1:0]    dr    = t13[1:0];
wire [1:0]    f_pos = back ? ~dr  : dl2;                    // first produced word: bytes >= f_pos
wire [1:0]    e_pos = back ? ~dl2 : dr;                     // last produced word: bytes <= e_pos
wire [4:0]    off1  = (is_exp ? {2'b00, ~sbit} : 5'd0) - {3'd0, dl2};   // -3..7 units
wire [XW-1:0] xbase = is_exp ? {sl, 3'b000} : {3'b000, sl};
wire [4:0]    o_ls  = (is_exp ? xs[4:0] : {xs[1:0], 3'b000}) ^ (back ? (is_exp ? 5'h1F : 5'h18) : 5'h00);

// source words
function automatic [31:0] byterev(input [31:0] w);
    byterev = {w[7:0], w[15:8], w[23:16], w[31:24]};
endfunction
function automatic [31:0] bitrev8(input [31:0] w);         // leftmost pixel bit first, per byte
    for (int i = 0; i < 32; i++) bitrev8[i] = w[{i[4:3], ~i[2:0]}];
endfunction
wire [1:0]  widx  = sb_long ? swa[1:0] : {1'b0, swa[0]};
wire [31:0] sw    = sbuf[{widx, 5'd0} +: 32];
wire [31:0] sw_t  = back ? byterev(sw) : (is_exp ? bitrev8(sw) : sw);
wire        g_end = back ? (sb_long ? (swa[1:0] == 2'd0) : !swa[0])
                         : (sb_long ? (swa[1:0] == 2'd3) :  swa[0]);

// producer (P1)
wire [63:0] win    = {hi, lo};
wire        need2  = is_exp ? (o > 5'd28) : (o != 5'd0);   // the word reaches into hi
wire        ready  = need2 ? (n == 2'd2) : (n != 2'd0);
wire        wrap   = is_exp ? (o > 5'd27) : 1'b1;          // lo is used up after this word
wire [31:0] x_copy = win[{1'b0, o[4:3], 3'b000} +: 32];
wire [3:0]  x_exp  = win[{1'b0, o} +: 4];
wire        p_last = (nwl == 11'd0);

// request stage (P2)
wire        slot_free = !b_req;
wire        p2        = xr && slot_free;            // (xr implies xv)
wire        p1_free   = !xv || p2;
reg  [31:0] d_out;
reg  [3:0]  m_out;
always_comb begin
    for (int i = 0; i < 4; i++) begin
        if (is_fill) begin
            d_out[i*8 +: 8] = r_fg;
            m_out[i]        = xm[i];
        end else if (is_exp) begin
            d_out[i*8 +: 8] = xq[i] ? r_fg : r_bg;
            m_out[i]        = xm[i] && (xq[i] || !keyed);
        end else begin
            d_out[i*8 +: 8] = xq[i*8 +: 8];
            m_out[i]        = xm[i] && !is_tbl && (xq[i*8 +: 8] != r_key || !kq);
        end
    end
    if (back) begin
        d_out = byterev(d_out);
        m_out = {m_out[0], m_out[1], m_out[2], m_out[3]};
    end
end

// the remap table (one block RAM: SDPB 256 x 8, registered read)
wire        lane_on = xv && !xr;                    // a word in the lanes (only when lane)
wire [7:0]  lb      = xq[{lc[1:0], 3'b000} +: 8];   // its byte lc: the lookup, or TABLE's data
wire        tbl_we  = lane_on && is_tbl && !lc[2] && xm[lc[1:0]];
wire [7:0]  tbl_wa  = {dwa[5:0], lc[1:0] ^ {2{back}}};   // (BACKWARDS: xq's bytes mirrored)
(* syn_ramstyle = "block_ram" *) reg [7:0] tbl [0:255];
reg  [7:0]  tbl_q;
always_ff @(posedge clk) begin
    if (tbl_we) tbl[tbl_wa] <= lb;
    tbl_q <= tbl[lb];
end
wire [1:0]  lp      = lc[1:0] - 2'd1;               // lc 1-4: the byte whose lookup is in

// CPU register writes are taken one clk later, from registers: the strobe comes from the
// 65C816's microcode through the I/O decode, and fanning it straight out to every register's
// enable was the longest clk_core path (step 17). A CPU access takes two clks, so a read in the
// CPU's next access already sees the write. Reads stay combinational.
reg       w_en = 1'b0;
reg [7:0] w_a = 8'h00, w_d = 8'h00;
always_ff @(posedge clk) begin w_en <= xio_wr; w_a <= xio_addr; w_d <= xio_wdata; end

// ── control ──────────────────────────────────────────────────────────────────
wire ctl_wr  = w_en && (w_a == 8'h13);
wire start_c = ctl_wr && w_d[0] && !w_d[2] && !busy;   // START from the CPU
wire start_l = ctl_wr && w_d[2] && !busy;                    // LIST
wire abort   = ctl_wr && w_d[3] && busy;
wire start   = start_c || (lst == L_GO);
// register file write port: the CPU (only while idle) or the list loader (one byte a cycle)
wire       l_ld   = (lst == L_LD);
wire       rw_en  = l_ld ? (lk < 5'd19) : (w_en && !busy && w_a < 8'h13);
wire [4:0] rw_a   = l_ld ? lk : w_a[4:0];
wire [7:0] rw_d   = l_ld ? sbuf[{lk[2:0], 3'b000} +: 8] : w_d;

always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        r_src <= 24'd0; r_dst <= 24'd0; r_sstr <= 16'd0; r_dstr <= 16'd0; r_w <= 16'd0; r_h <= 16'd0;
        r_fg <= 8'd0; r_bg <= 8'd0; r_key <= 8'd0; r_op <= 8'd0; r_flags <= 8'd0; r_irqen <= 1'b0;
        r_list <= 21'd0; r_cnt <= 16'd0; r_wvbl <= 1'b0; f_done <= 1'b0; f_abrt <= 1'b0;
        lst <= L_IDLE; lk <= 5'd0;
        st <= S_IDLE; irq <= 1'b0;
        b_req <= 1'b0; b_we <= 1'b0; b_addr <= '0; b_wdata <= 32'd0; b_wmask <= 4'd0; b_long <= 1'b0;
        sl <= '0; dl <= '0; yc <= 12'd0; hm1 <= 12'd0; wm1 <= 12'd0; kl <= 11'd0; nwl <= 11'd0;
        fmask <= 4'd0; emask <= 4'd0; xs <= '0; swa <= '0; dwa <= '0; o <= 5'd0; n <= 2'd0;
        lo <= 32'd0; hi <= 32'd0; first <= 1'b0; sbuf <= 128'd0; sbv <= 1'b0; sb_long <= 1'b0;
        rd_wait <= 1'b0; infl <= 1'b0; infl_rd <= 1'b0; xq <= 32'd0; xm <= 4'd0; xv <= 1'b0;
        xr <= 1'b0; lc <= 3'd0;
    end else begin
        irq <= 1'b0;

        // the port
        if (b_gnt)  begin infl <= 1'b1; infl_rd <= !b_we; end
        if (b_done) begin
            infl <= 1'b0;
            if (infl_rd) begin sbuf <= b_rdata; sbv <= 1'b1; rd_wait <= 1'b0; end
        end

        // P2: stage -> request registers (a word with nothing to write is dropped)
        if (p2) begin
            b_req   <= |m_out;
            b_we    <= 1'b1;
            b_addr  <= {dwa, 2'b00};
            b_wdata <= d_out;
            b_wmask <= m_out;
            dwa     <= back ? dwa - WA'(1) : dwa + WA'(1);
            xv      <= 1'b0;
            xr      <= 1'b0;
        end else if (b_gnt) b_req <= 1'b0;

        // the lanes (REMAP, TABLE): byte lc looked up / written, the lookup of byte lc - 1 back
        if (lane_on) begin
            if (lc == 3'd0) begin
                for (int i = 0; i < 4; i++)         // the key, on the source pixels
                    if (keyed && xq[i*8 +: 8] == r_key) xm[i] <= 1'b0;
            end else if (!is_tbl) xq[{lp, 3'b000} +: 8] <= tbl_q;
            if (lc == 3'd4) begin lc <= 3'd0; xr <= 1'b1; end
            else lc <= lc + 3'd1;
        end

        case (st)
            S_IDLE: if (start) begin
                lc <= 3'd0;
                if (r_w == 16'd0 || r_h == 16'd0 || r_op > 8'd7) st <= S_FIN;
                else begin
                    wm1 <= |r_w[15:12] ? 12'hFFF : r_w[11:0] - 12'd1;
                    hm1 <= |r_h[15:12] ? 12'hFFF : r_h[11:0] - 12'd1;
                    yc  <= back ? 12'd0 : (|r_h[15:12] ? 12'hFFF : r_h[11:0] - 12'd1);
                    sl  <= r_src[AW-1:0];
                    dl  <= r_dst[AW-1:0];
                    st  <= back ? S_PRE : S_LS0;
                end
            end
            S_PRE: begin                       // BACKWARDS: step to the last line
                if (yc == hm1) st <= S_LS0;
                else begin
                    yc <= yc + 12'd1;
                    sl <= sl_nx;
                    dl <= dl_nx;
                end
            end
            S_LS0: begin
                kl    <= t13[12:2];
                fmask <= 4'b1111 << f_pos;
                emask <= 4'b1111 >> ~e_pos;
                dwa   <= WA'((dl + (back ? AW'(wm1) : AW'(0))) >> 2);
                xs    <= xbase + {{(XW-5){off1[4]}}, off1};
                st    <= back ? S_LS1 : S_LS2;
            end
            S_LS1: begin                       // BACKWARDS: source of the last byte of the last word
                xs <= xs + XW'({kl, 2'b11});
                st <= S_LS2;
            end
            S_LS2: begin
                swa   <= is_exp ? WA'(xs[XW-1:5]) : WA'(xs[AW-1:2]);
                o     <= o_ls;
                n     <= 2'd0;
                sbv   <= 1'b0;
                nwl   <= kl;
                first <= 1'b1;
                st    <= S_RUN;
            end
            S_RUN: begin
                if (is_fill || ready) begin
                    if (p1_free) begin         // P1: produce one destination word
                        xq    <= is_exp ? {28'd0, x_exp} : x_copy;
                        xm    <= (first ? fmask : 4'hF) & (p_last ? emask : 4'hF);
                        xv    <= 1'b1;
                        xr    <= !lane;     // (the lanes first: xr when they are done)
                        first <= 1'b0;
                        nwl   <= nwl - 11'd1;
                        if (p_last) st <= S_LEND;
                        if (!is_fill) begin
                            o <= o + (is_exp ? 5'd4 : 5'd0);
                            if (wrap) begin lo <= hi; n <= n - 2'd1; end
                        end
                    end
                end else if (sbv) begin        // take a source word into the window
                    if (n == 2'd0) lo <= sw_t; else hi <= sw_t;
                    n   <= n + 2'd1;
                    swa <= back ? swa - WA'(1) : swa + WA'(1);
                    if (g_end) sbv <= 1'b0;
                end else if (!rd_wait && (!xv || !xr) && slot_free) begin   // fetch the burst holding swa
                    // (also while a word is in the lanes: its write then follows this read,
                    // which is safe: the words still to be read are never ones the words
                    // before them write when the direction suits the overlap; P2 waits for xr)
                    b_req   <= 1'b1;
                    b_we    <= 1'b0;
                    b_addr  <= long_ok ? {swa[WA-1:2], 4'b0000} : {swa[WA-1:1], 3'b000};
                    b_long  <= long_ok;
                    sb_long <= long_ok;
                    rd_wait <= 1'b1;
                end
            end
            S_LEND: if (!xv) begin
                if (yc == 12'd0) st <= S_FIN;
                else begin
                    yc <= yc - 12'd1;
                    sl <= sl_nx;
                    dl <= dl_nx;
                    st <= S_LS0;
                end
            end
            S_FIN: if (!b_req && !infl) begin
                if (lst == L_IDLE && !f_abrt) begin   // a single blit (a list's end is in L_RUN)
                    irq    <= r_irqen;
                    f_done <= 1'b1;
                end
                st  <= S_IDLE;
            end
            default: st <= S_IDLE;
        endcase

        // list sequencer
        case (lst)
            L_IDLE: if (start_l) lst <= (r_cnt == 16'd0) ? L_RUN : L_RD;
            L_RD: if (!b_req) begin                // read the burst holding byte lk of the record
                b_req   <= 1'b1;
                b_we    <= 1'b0;
                b_addr  <= AW'({r_list, 3'b000});
                b_long  <= 1'b0;
                rd_wait <= 1'b1;
                lst     <= L_WT;
            end
            L_WT: if (!rd_wait) lst <= L_LD;    // sbuf holds the burst
            L_LD: begin
                lk <= lk + 5'd1;
                if (lk == 5'd19) r_wvbl <= rw_d[0];
                if (lk[2:0] == 3'd7 || lk == 5'd19) begin
                    r_list <= r_list + 21'd1;
                    lst    <= (lk == 5'd19) ? L_CHK : L_RD;
                end
            end
            L_CHK: begin                           // (bytes 20-23 came with the third burst)
                r_cnt  <= r_cnt - 16'd1;
                lst    <= r_wvbl ? L_VBL : L_GO;
            end
            L_VBL: if (vbl) lst <= L_GO;
            L_GO:  lst <= L_RUN;                   // start = 1 in this cycle: the blit leaves S_IDLE
            L_RUN: if (st == S_IDLE) begin
                lk <= 5'd0;
                if (r_cnt == 16'd0) begin
                    irq    <= r_irqen;
                    f_done <= 1'b1;
                    lst    <= L_IDLE;
                end else lst <= L_RD;
            end
            default: lst <= L_IDLE;
        endcase
        if (start_c || start_l) begin f_done <= 1'b0; f_abrt <= 1'b0; lk <= 5'd0; end

        // ABORT: drop what has not been granted yet; S_FIN waits for the access in flight
        if (abort) begin
            lst     <= L_IDLE;
            f_abrt  <= 1'b1;
            xv      <= 1'b0;
            xr      <= 1'b0;
            lc      <= 3'd0;
            b_req   <= 1'b0;
            rd_wait <= 1'b0;
            if (st != S_IDLE) st <= S_FIN;
        end

        // register writes
        if (!run) begin
            r_src <= 24'd0; r_dst <= 24'd0; r_sstr <= 16'd0; r_dstr <= 16'd0; r_w <= 16'd0; r_h <= 16'd0;
            r_fg <= 8'd0; r_bg <= 8'd0; r_key <= 8'd0; r_op <= 8'd0; r_flags <= 8'd0; r_irqen <= 1'b0;
            r_list <= 21'd0; r_cnt <= 16'd0; f_done <= 1'b0; f_abrt <= 1'b0;
            st <= S_IDLE; lst <= L_IDLE; b_req <= 1'b0; xv <= 1'b0; xr <= 1'b0; lc <= 3'd0;
            rd_wait <= 1'b0;
        end else begin
            if (rw_en) begin
                case (rw_a)
                    5'h00: r_src[7:0]   <= rw_d;
                    5'h01: r_src[15:8]  <= rw_d;
                    5'h02: r_src[23:16] <= rw_d;
                    5'h03: r_sstr[7:0]  <= rw_d;
                    5'h04: r_sstr[15:8] <= rw_d;
                    5'h05: r_dst[7:0]   <= rw_d;
                    5'h06: r_dst[15:8]  <= rw_d;
                    5'h07: r_dst[23:16] <= rw_d;
                    5'h08: r_dstr[7:0]  <= rw_d;
                    5'h09: r_dstr[15:8] <= rw_d;
                    5'h0A: r_w[7:0]     <= rw_d;
                    5'h0B: r_w[15:8]    <= rw_d;
                    5'h0C: r_h[7:0]     <= rw_d;
                    5'h0D: r_h[15:8]    <= rw_d;
                    5'h0E: r_fg         <= rw_d;
                    5'h0F: r_bg         <= rw_d;
                    5'h10: r_key        <= rw_d;
                    5'h11: r_op         <= rw_d;
                    5'h12: r_flags      <= rw_d;
                    default: ;
                endcase
            end
            if (w_en && !busy) begin
                case (w_a)
                    8'h14: r_list[7:3]   <= w_d[7:3];
                    8'h15: r_list[15:8]  <= w_d;
                    8'h16: r_list[23:16] <= w_d;
                    8'h17: r_cnt[7:0]    <= w_d;
                    8'h18: r_cnt[15:8]   <= w_d;
                    default: ;
                endcase
            end
            if (ctl_wr) r_irqen <= w_d[1];
        end
    end
end

endmodule
`default_nettype wire
