// SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
// Copyright (c) 2026 Carlos Bravo
// Marga, the Atari816 video chip (first called the NVC): desktop framebuffer, palette,
// pointer, and from REV $0B fine scrolling and 16 sprites.
//
// 640x360 shown 2x on the 1280x720 output. The raster (1572x760 at 71.72 MHz, one Atari frame
// long) is made by the scandoubler; this block supplies pixels when NV_CTRL.ENABLE is set.
// The framebuffer is read from main RAM one line ahead of the beam, into a two-line buffer,
// through the 65C816's own low-priority SDRAM port: this block sits between a816_sys and the
// arbiter and takes that port first when it needs it. Its other clients are Lau (the sample
// player), the CPU and Ali (the blitter). The arbiter and the Atari's memory
// timing do not change. The pointer is merged into the line as it is fetched (and flagged, so
// that it stays in front of the sprites). Sprites are drawn into a second two-line buffer
// during the same line period and merged on the pixel clock side: line buffer + sprite
// buffer -> palette -> output mux.
//
// Registers ($00:D900, the register spec is the reference; differences marked *):
//   $D900 NV_CTRL    RW  0 ENABLE, 2:1 MODE (0 = 640x360x8, 1 = 640x360x4, 2 = 320x180x8), 3 POINTER_EN
//   $D901-03 NV_BASE RW  framebuffer address (low byte ignored); taken at the fetch of line 0
//   $D904-05 NV_STRIDE RW bytes per line, reset 640.                    * must be a multiple of 8
//   $D906-07 NV_LINE R   raster line on screen (beam events, below), 0-359; 360-365 in
//                        vertical blank. Reading $D906 latches $D907.
//   $D908-09 NV_LINE_CMP RW  LINE interrupt when NV_LINE becomes this value; also the split line
//   $D90C-0D NV_FRAME R  frames since the CPU was released (+1 at VBLANK); reading $D90C latches $D90D
//   Beam events: line n begins at the horizontal blank after the last output line of line n-1
//   (for n = 0: before the first visible output line). The event is the fetch trigger of line n
//   delayed by EV_DELAY clk_core cycles (1572 + 1280 pixel clocks = 1140.8 cycles, less the
//   trigger's synchroniser), so it lands at hx ~1282 of output line V_TOP - 1 + 2n. At the event
//   NV_LINE = n, LINE fires if n == NV_LINE_CMP, VBLANK and NV_FRAME + 1 if n == 360.
//   $D90A NV_STATUS  R   0 IN_VBLANK, 1 BASE_PENDING
//   While the classic machine is frozen (SV_CTRL.FREEZE_REQ) lines are fetched in 16-byte
//   bursts, which is what makes 640x360x8 fit; NV_STRIDE must then be a multiple of 16.
//   With the classic machine running, bursts stay 8 bytes (its memory timing is untouched)
//   and only the 4 bpp and half-resolution modes are fetched in time.
//   $D90B NV_LATE    R/W * lines whose fetch was not finished in time (saturates; any write clears)
//   $D910 PAL_IDX RW, $D911 PAL_R, $D912 PAL_G, $D913 PAL_B (write commits, PAL_IDX + 1)
//                                                                       * R/G/B read back the last value written
//   $D920-21 PTR_X, $D922-23 PTR_Y, $D924 PTR_HOT, $D925-27 PTR_IMG (* 8-byte aligned), $D928-2A PTR_C1-C3
//   REV $0B, fine scrolling (all taken at the fetch of line 0, with NV_BASE):
//   $D930-31 NV_SCROLLX RW  pixels (of the mode) skipped at the start of each line, 0-4095
//   $D932-33 NV_SCROLLY RW  row of the bitmap shown on line 0, 0-1023
//   $D934-35 NV_SCROLLX2, $D936-37 NV_SCROLLY2 RW  the same, used from the split line on
//   $D938-39 NV_VHEIGHT RW  rows of the virtual bitmap: row VHEIGHT-1 is followed by row 0 (0 = no wrap)
//   $D93A NV_SCROLL_CTRL RW 0 HWRAP (a line that runs past NV_STRIDE bytes continues at the
//                          start of its row), 1 SPLIT (from line L = NV_LINE_CMP as it was at line 0,
//                          L >= 1, the second set: line L shows row SCROLLY2)
//   REV $0B, sprites:
//   $D940 NV_SPR_CTRL RW 0 SPR_EN
//   $D941 NV_SPR_COMMIT W any value: copy the 16 records to the set in use, in the next vertical
//                          blank (at once if in it). R: 0 PENDING (until the copy has been made)
//   $D942 NV_SPR_STATUS R/W1C 0 OVERFLOW (a visible sprite was left out of a line), 1 LATE
//   $D943 NV_SPR_PEEK  RW  W: index 0-255 of a record byte to read (0-127 the records as
//                          written, 128-255 the set in use); R: the index
//   $D944 NV_SPR_PEEKD R   that byte (ready by the CPU's next access)
//   $D980 + 8i, i = 0-15: sprite records, write only (NV_SPR_PEEK reads them):
//     +0,+1 X (signed, bits 10:0)  +2,+3 Y (signed, bits 9:0)
//     +4 bits 7:4 image address bits 7:4, bits 3:0 PAL   +5,+6 image address bits 23:8
//     +7 CTRL: 0 EN, 1 HFLIP, 2 VFLIP, 3 MAG (2x2), 4 WIDE (32 px, 4 bpp only), 5 TALL (32
//        lines), 6 BPP4 (else 8 bpp), 7 BEHIND (behind bitmap pixels that are not colour 0)
//   Line limit: on each line the sprites visible on it are taken in index order while the sum
//   of their widths on screen (16 << (WIDE + MAG)) stays within 512; the others are left out of
//   that line and set OVERFLOW. They are drawn lowest priority first (index 15 at the back).
// In 320x180 mode the pointer, sprites and scrolling are in those larger pixels too.
`default_nettype none

module a816_nvc #(
    parameter int AW = 23,
    parameter logic [9:0] V_TOP = 10'd30          // first active output line (scandoubler V_PIC_TOP)
) (
    input  wire          clk,          // clk_core
    input  wire          reset_n,      // hardware reset
    input  wire          run,          // 0 = 65C816 held in reset: registers return to reset values

    // register bus from a816_sys ($00:D9xx)
    input  wire          xio_wr,
    input  wire          xio_rd,       // 1-cycle strobe: the CPU reads $00:D9xx (for the latches)
    input  wire [7:0]    xio_addr,
    input  wire [7:0]    xio_wdata,
    output reg  [7:0]    xio_rdata,
    output reg           irq_vblank,   // 1-cycle pulses
    output reg           irq_line,

    // SDRAM port, CPU side (a816_sys)
    input  wire          c_req,
    input  wire          c_we,
    input  wire [AW-1:0] c_addr,
    input  wire [7:0]    c_wdata,
    output wire          c_done,
    // SDRAM port, blitter side (lowest priority; b_* are free again once b_gnt has been seen)
    input  wire          b_req,
    input  wire          b_we,         // 1 = word write with b_wmask, 0 = burst read
    input  wire [AW-1:0] b_addr,
    input  wire [31:0]   b_wdata,
    input  wire [3:0]    b_wmask,
    input  wire          b_long,
    output wire          b_gnt,
    output wire          b_done,
    // SDRAM port, sample player (8-byte burst reads; after the CPU, before the blitter)
    input  wire          a_req,        // held until a_done
    input  wire [AW-1:0] a_addr,
    output wire          a_done,
    // SDRAM port, arbiter side
    output reg           sd_req,
    output reg           sd_we,
    output reg  [AW-1:0] sd_addr,
    output reg  [31:0]   sd_wdata,     // write: one 32-bit word ...
    output reg  [3:0]    sd_wmask,     // ... with a byte mask (CPU: one byte)
    output reg           sd_long,      // with a read: 16-byte burst
    input  wire          sd_done,
    input  wire [127:0]  sd_rdata,
    input  wire          long_ok,      // 1 = 16-byte bursts allowed (classic machine frozen)

    // raster (clk_pix)
    input  wire          clk_pix,
    input  wire [10:0]   hx,           // 0..1571, active 0..1279
    input  wire [9:0]    vy,           // output line, active V_TOP..V_TOP+719
    output reg           nv_on,        // 1 = show the desktop
    output wire [7:0]    nv_r, nv_g, nv_b   // pixel for (hx, vy), two clk_pix cycles later
);

// ── registers ────────────────────────────────────────────────────────────────
reg  [3:0]  ctrl;
reg  [15:0] base_pend, base_act;       // address bits 23:8
reg         base_pending;
reg  [15:0] stride;
reg  [8:0]  line_cmp;
reg  [8:0]  nv_line;
reg         line_hi;                   // NV_LINE bit 8 latched by a read of $D906
reg  [15:0] frame;
reg  [7:0]  frame_hi;                  // NV_FRAME bits 15:8 latched by a read of $D90C
reg  [10:0] ev_cnt;                    // beam event delay
reg         ev_pend;
reg  [8:0]  ev_n;
localparam logic [10:0] EV_DELAY = 11'd1139;
reg  [7:0]  late;
reg  [7:0]  pal_idx, pal_r, pal_g;
reg  [9:0]  ptr_x;
reg  [8:0]  ptr_y;
reg  [7:0]  ptr_hot;
reg  [23:0] ptr_img;
reg  [7:0]  ptr_c [1:3];
// scrolling: written (_p), taken at line 0 (_a)
reg  [11:0] scx_p, scx2_p, scx_a, scx2_a;
reg  [9:0]  scy_p, scy2_p, scy2_a;
reg  [9:0]  vh_p, vh_a;
reg  [1:0]  sctl_p, sctl_a;            // 0 HWRAP, 1 SPLIT
reg  [8:0]  split_l;                   // NV_LINE_CMP taken at line 0
reg         reg2;                      // this line belongs to the second scroll set
// sprites, registers
reg         spr_en;
reg         cm_req;                    // COMMIT written, copy not started
reg         spr_ovf, spr_late;
reg  [7:0]  pk_a, pk_d;                // NV_SPR_PEEK index and byte
reg         pk_req, pk_rdv;

wire        enable   = ctrl[0];
wire [1:0]  mode     = ctrl[2:1];
wire        wide     = (mode != 2'd0);          // 320 bytes per line
wire        m4       = (mode == 2'd1);          // 4 bpp: two pixels per byte
wire        in_vbl   = (nv_line >= 9'd360);
reg         cp_busy;                   // the record copy is running

always_comb begin
    case (xio_addr)
        8'h00: xio_rdata = {4'd0, ctrl};
        8'h01: xio_rdata = 8'h00;
        8'h02: xio_rdata = base_pend[7:0];
        8'h03: xio_rdata = base_pend[15:8];
        8'h04: xio_rdata = stride[7:0];
        8'h05: xio_rdata = stride[15:8];
        8'h06: xio_rdata = nv_line[7:0];
        8'h07: xio_rdata = {7'd0, line_hi};
        8'h08: xio_rdata = line_cmp[7:0];
        8'h09: xio_rdata = {7'd0, line_cmp[8]};
        8'h0A: xio_rdata = {6'd0, base_pending, in_vbl};
        8'h0B: xio_rdata = late;
        8'h0C: xio_rdata = frame[7:0];
        8'h0D: xio_rdata = frame_hi;
        8'h10: xio_rdata = pal_idx;
        8'h11: xio_rdata = pal_r;
        8'h12: xio_rdata = pal_g;
        8'h20: xio_rdata = ptr_x[7:0];
        8'h21: xio_rdata = {6'd0, ptr_x[9:8]};
        8'h22: xio_rdata = ptr_y[7:0];
        8'h23: xio_rdata = {7'd0, ptr_y[8]};
        8'h24: xio_rdata = ptr_hot;
        8'h25: xio_rdata = ptr_img[7:0];
        8'h26: xio_rdata = ptr_img[15:8];
        8'h27: xio_rdata = ptr_img[23:16];
        8'h28: xio_rdata = ptr_c[1];
        8'h29: xio_rdata = ptr_c[2];
        8'h2A: xio_rdata = ptr_c[3];
        8'h30: xio_rdata = scx_p[7:0];
        8'h31: xio_rdata = {4'd0, scx_p[11:8]};
        8'h32: xio_rdata = scy_p[7:0];
        8'h33: xio_rdata = {6'd0, scy_p[9:8]};
        8'h34: xio_rdata = scx2_p[7:0];
        8'h35: xio_rdata = {4'd0, scx2_p[11:8]};
        8'h36: xio_rdata = scy2_p[7:0];
        8'h37: xio_rdata = {6'd0, scy2_p[9:8]};
        8'h38: xio_rdata = vh_p[7:0];
        8'h39: xio_rdata = {6'd0, vh_p[9:8]};
        8'h3A: xio_rdata = {6'd0, sctl_p};
        8'h40: xio_rdata = {7'd0, spr_en};
        8'h41: xio_rdata = {7'd0, cm_req | cp_busy};
        8'h42: xio_rdata = {6'd0, spr_late, spr_ovf};
        8'h43: xio_rdata = pk_a;
        8'h44: xio_rdata = pk_d;
        default: xio_rdata = 8'h00;
    endcase
end

// ── palette: written here, read on the pixel clock ───────────────────────────
reg [23:0] pal [0:255];
initial $readmemh("nvc_palette.hex", pal);       // GTIA NTSC palette
// CPU register writes are taken one clk later, from registers: the strobe comes from the
// 65C816's microcode through the I/O decode, and fanning it straight out to every register's
// enable was the longest clk_core path (step 17). A CPU access takes two clks, so a read in the
// CPU's next access already sees the write. Reads stay combinational.
reg       w_en = 1'b0;
reg [7:0] w_a = 8'h00, w_d = 8'h00;
always_ff @(posedge clk) begin w_en <= xio_wr; w_a <= xio_addr; w_d <= xio_wdata; end

wire pal_we = w_en && (w_a == 8'h13);
always_ff @(posedge clk) if (pal_we) pal[pal_idx] <= {pal_r, pal_g, w_d};

// ── raster -> fetch trigger (clk_pix), one per two output lines ──────────────
// Line n is fetched while line n-1 is on screen, so the trigger for n fires two output
// lines before n's first one. n runs 0..365; 360 and above is vertical blank.
wire [9:0] t_rel = vy - (V_TOP - 10'd2);
reg        trig_tog = 1'b0;
reg  [8:0] trig_n   = 9'd0;
always_ff @(posedge clk_pix) begin
    if (hx == 11'd0 && vy >= (V_TOP - 10'd2) && !t_rel[0]) begin
        trig_n   <= t_rel[9:1];
        trig_tog <= ~trig_tog;
    end
end
reg [2:0] trig_s = 3'd0;
always_ff @(posedge clk) trig_s <= {trig_s[1:0], trig_tog};
wire trig = trig_s[2] ^ trig_s[1];               // trig_n has been stable for two cycles

// ── SDRAM port mux: line fetch, sample player, sprite fetch, CPU, blitter ─────────────────
// A request is taken only while the port is idle. The sample player (at most 8 short reads
// per 48 kHz sample) goes before the sprite fetch, which has the most slack of the real-time
// clients (REV $0B; before, it came after the CPU). The CPU waits for at most one access in
// flight plus the others; its own requests leave a gap of two cycles between them, which the
// blitter uses, so a busy CPU still lets the blitter have every other access.
localparam logic [2:0] O_CPU = 3'd0, O_FET = 3'd1, O_BLT = 3'd2, O_AUD = 3'd3, O_SPR = 3'd4;
reg           f_req;
reg  [AW-1:0] f_addr;
reg           s_req;                   // sprite row fetch
reg  [AW-1:0] s_addr;
reg           s_long;
reg           busy;
reg  [2:0]    owner;
assign c_done = sd_done && busy && (owner == O_CPU);
wire   f_done = sd_done && busy && (owner == O_FET);
wire   s_done = sd_done && busy && (owner == O_SPR);
assign b_done = sd_done && busy && (owner == O_BLT);
assign a_done = sd_done && busy && (owner == O_AUD);
assign b_gnt  = !busy && !f_req && !a_req && !s_req && !c_req && b_req;
always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        busy <= 1'b0; owner <= O_CPU; sd_req <= 1'b0; sd_we <= 1'b0; sd_addr <= '0; sd_wdata <= 32'd0;
        sd_wmask <= 4'd0; sd_long <= 1'b0;
    end else if (!busy) begin
        if (f_req) begin
            busy <= 1'b1; owner <= O_FET; sd_req <= 1'b1; sd_we <= 1'b0; sd_addr <= f_addr;
            sd_long <= f_long && (fst == F_PIX);
        end else if (a_req) begin
            busy <= 1'b1; owner <= O_AUD; sd_req <= 1'b1; sd_we <= 1'b0; sd_addr <= a_addr;
            sd_long <= 1'b0;
        end else if (s_req) begin
            busy <= 1'b1; owner <= O_SPR; sd_req <= 1'b1; sd_we <= 1'b0; sd_addr <= s_addr;
            sd_long <= s_long;
        end else if (c_req) begin
            busy <= 1'b1; owner <= O_CPU; sd_req <= 1'b1; sd_we <= c_we; sd_addr <= c_addr;
            sd_wdata <= {4{c_wdata}}; sd_wmask <= 4'b0001 << c_addr[1:0];
            sd_long <= 1'b0;
        end else if (b_req) begin
            busy <= 1'b1; owner <= O_BLT; sd_req <= 1'b1; sd_we <= b_we; sd_addr <= b_addr;
            sd_wdata <= b_wdata; sd_wmask <= b_wmask;
            sd_long <= b_long && !b_we;
        end
    end else if (sd_done) begin
        busy <= 1'b0; sd_req <= 1'b0;
    end
end

// ── line fetcher ─────────────────────────────────────────────────────────────
typedef enum logic [1:0] { F_IDLE, F_PTR, F_PIX0, F_PIX } fst_t;
fst_t        fst;
reg  [23:0]  row_addr;                 // start of the bitmap row of the line being fetched
reg  [9:0]   rl;                       // its row number (for NV_VHEIGHT)
reg  [15:0]  hc;                       // byte offset of the next burst in the row (HWRAP)
reg  [6:0]   left;                     // bursts still to request
reg          drop;                     // the request in flight belongs to an abandoned line
reg  [127:0] h_data;  reg h_valid;     // one burst waiting for the unpacker
reg  [127:0] u_data;  reg [4:0] u_cnt; // bytes being written to the line buffer
reg          u_ph;                     // 4 bpp: 1 = the right pixel of the byte is next
reg  [4:0]   u_skip;                   // pixels still to drop at the start of the line (SCROLLX)
reg          f_long;                   // this line is fetched in 16-byte bursts
reg  [10:0]  wptr;                     // {buffer half, column}
reg  [63:0]  ptr_row;                  // this line's 32 pointer pixels
reg          ptr_here;
reg  [10:0]  ptr_left;                 // signed: column of pointer pixel 0

// pointer geometry for the line about to be fetched
wire [8:0]  f_line   = (mode == 2'd2) ? {1'b0, trig_n[8:1]} : trig_n;
wire [9:0]  ptr_top  = {1'b0, ptr_y} - {5'd0, ptr_hot[7:4], 1'b0};
wire [9:0]  ptr_dy   = {1'b0, f_line} - ptr_top;
wire        ptr_hit  = ctrl[3] && (ptr_dy < 10'd32);
wire        new_row  = (mode != 2'd2) || !trig_n[0];

// rows: line 0 (and the split line) start at NV_BASE + SCROLLY * NV_STRIDE. The product is
// formed one cycle ahead from trig_n, which is stable for two cycles before the trigger.
reg  [25:0] prod_r;
reg  [9:0]  prod_y;                    // the SCROLLY in prod_r
wire [9:0]  mul_y    = (trig_n == 9'd0) ? scy_p : scy2_a;
always_ff @(posedge clk) begin prod_r <= mul_y * stride; prod_y <= mul_y; end
wire        split_hit = sctl_a[1] && (trig_n == split_l) && (trig_n != 9'd0);
wire [23:0] row_base  = {(trig_n == 9'd0) ? base_pend : base_act, 8'h00};
wire [23:0] row_top   = row_base + prod_r[23:0];
wire        vwrap     = (vh_a != 10'd0) && (rl + 10'd1 == vh_a);
wire [23:0] row_step  = vwrap ? {base_act, 8'h00} : row_addr + {8'd0, stride};

// the start of a line's pixels: SCROLLX in bytes, rounded down to the burst; the rest skipped
wire [11:0] x_now    = reg2 ? scx2_a : scx_a;
wire [11:0] x_bytes  = m4 ? {1'b0, x_now[11:1]} : x_now;
wire [11:0] x_col0   = f_long ? {x_bytes[11:4], 4'd0} : {x_bytes[11:3], 3'd0};
wire [4:0]  x_skip   = f_long ? (m4 ? x_now[4:0] : {1'b0, x_bytes[3:0]})
                              : (m4 ? {1'b0, x_now[3:0]} : {2'b0, x_bytes[2:0]});
wire [15:0] hc_next  = hc + (f_long ? 16'd16 : 16'd8);
wire        hwrap    = sctl_a[0] && (hc_next == stride);

// pointer pixel lookup: 2 bits for pointer column p (0..31), leftmost pixel in bits 7:6
function automatic [1:0] ptr_px(input [63:0] row, input [4:0] p);
    ptr_px = row[{p[4:2], 3'b000} + {2'd0, ~p[1:0], 1'b0} +: 2];
endfunction
// one pixel per line buffer entry in every mode (4 bpp: the left pixel first); bit 8 marks
// the pointer, which the sprites stay behind
wire [7:0]  u_px     = m4 ? {4'd0, u_ph ? u_data[3:0] : u_data[7:4]} : u_data[7:0];
wire [10:0] col      = {1'b0, wptr[9:0]};
wire [10:0] dx8      = col - ptr_left;
wire [1:0]  code8    = (ptr_here && dx8 < 11'd32) ? ptr_px(ptr_row, dx8[4:0]) : 2'd0;
wire [7:0]  ptr_col  = m4 ? {4'd0, ptr_c[code8][3:0]} : ptr_c[code8];
wire [8:0]  wbyte    = (code8 != 2'd0) ? {1'b1, ptr_col} : {1'b0, u_px};
wire        lb_we    = (u_cnt != 5'd0) && (u_skip == 5'd0);

always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        ctrl <= 4'd0; base_pend <= 16'd0; base_act <= 16'd0; base_pending <= 1'b0;
        stride <= 16'd640; line_cmp <= 9'd511; nv_line <= 9'd360; late <= 8'd0;
        pal_idx <= 8'd0; pal_r <= 8'd0; pal_g <= 8'd0;
        ptr_x <= 10'd0; ptr_y <= 9'd0; ptr_hot <= 8'd0; ptr_img <= 24'd0;
        ptr_c[1] <= 8'h00; ptr_c[2] <= 8'h0F; ptr_c[3] <= 8'h08;
        irq_vblank <= 1'b0; irq_line <= 1'b0;
        line_hi <= 1'b0; frame <= 16'd0; frame_hi <= 8'd0; ev_cnt <= 11'd0; ev_pend <= 1'b0; ev_n <= 9'd0;
        fst <= F_IDLE; f_req <= 1'b0; f_addr <= '0; row_addr <= 24'd0; rl <= 10'd0; hc <= 16'd0;
        left <= 7'd0; drop <= 1'b0;
        h_data <= 128'd0; h_valid <= 1'b0; u_data <= 128'd0; u_cnt <= 5'd0; u_ph <= 1'b0; u_skip <= 5'd0;
        wptr <= 11'd0; f_long <= 1'b0;
        ptr_row <= 64'd0; ptr_here <= 1'b0; ptr_left <= 11'd0;
        scx_p <= 12'd0; scx2_p <= 12'd0; scy_p <= 10'd0; scy2_p <= 10'd0; vh_p <= 10'd0; sctl_p <= 2'd0;
        scx_a <= 12'd0; scx2_a <= 12'd0; scy2_a <= 10'd0; vh_a <= 10'd0; sctl_a <= 2'd0;
        split_l <= 9'd0; reg2 <= 1'b0;
    end else begin
        irq_vblank <= 1'b0;
        irq_line   <= 1'b0;

        // unpack one burst into the line buffer, a pixel per cycle
        if (u_cnt != 5'd0) begin
            u_ph <= m4 && !u_ph;
            if (!m4 || u_ph) begin
                u_data <= {8'h00, u_data[127:8]};
                u_cnt  <= u_cnt - 5'd1;
            end
            if (u_skip != 5'd0) u_skip <= u_skip - 5'd1;
            else                wptr   <= wptr + 11'd1;
        end else if (h_valid) begin
            u_data  <= h_data;
            u_cnt   <= f_long ? 5'd16 : 5'd8;
            u_ph    <= 1'b0;
            h_valid <= 1'b0;
        end

        // requests
        if (f_done) begin
            f_req <= 1'b0;
            if (drop) drop <= 1'b0;
            else if (fst == F_PTR) begin
                ptr_row <= sd_rdata[63:0];
                fst     <= F_PIX0;
            end else begin
                h_data  <= sd_rdata;
                h_valid <= 1'b1;
                f_addr  <= hwrap ? AW'(row_addr) : f_addr + (f_long ? AW'(16) : AW'(8));
                hc      <= hwrap ? 16'd0 : hc_next;
                left    <= left - 7'd1;
                if (left == 7'd1) fst <= F_IDLE;
            end
        end else if (!f_req && !drop && !h_valid) begin
            if (fst == F_PTR) begin
                f_req  <= 1'b1;
            end else if (fst == F_PIX && left != 7'd0) begin
                f_req  <= 1'b1;
            end
        end
        // the first pixel burst of the line, from SCROLLX
        if (fst == F_PIX0) begin
            fst    <= F_PIX;
            f_addr <= AW'(row_addr + {12'd0, x_col0});
            hc     <= {4'd0, x_col0};
            u_skip <= x_skip;
            left   <= (f_long ? (wide ? 7'd20 : 7'd40) : (wide ? 7'd40 : 7'd80)) + {6'd0, x_skip != 5'd0};
        end

        // beam event: the fetch trigger of line n, EV_DELAY cycles later
        if (ev_pend) begin
            if (ev_cnt == 11'd0) begin
                ev_pend <= 1'b0;
                nv_line <= ev_n;
                if (ev_n == 9'd360)   begin irq_vblank <= 1'b1; frame <= frame + 16'd1; end
                if (ev_n == line_cmp) irq_line   <= 1'b1;
            end else ev_cnt <= ev_cnt - 11'd1;
        end

        // a new line (this wins over the above)
        if (trig) begin
            ev_pend <= 1'b1;
            ev_cnt  <= EV_DELAY;
            ev_n    <= trig_n;
            if (fst != F_IDLE || h_valid || u_cnt != 5'd0) begin
                if (late != 8'hFF) late <= late + 8'd1;
            end
            h_valid <= 1'b0;
            u_cnt   <= 5'd0;
            u_skip  <= 5'd0;
            if (f_req && !f_done) drop <= 1'b1;
            f_req   <= f_req && !f_done;         // a request in flight cannot be recalled
            fst     <= F_IDLE;
            if (trig_n == 9'd0) begin
                base_act     <= base_pend;
                base_pending <= 1'b0;
                scx_a <= scx_p; scx2_a <= scx2_p; scy2_a <= scy2_p; vh_a <= vh_p; sctl_a <= sctl_p;
                split_l      <= line_cmp;
                reg2         <= 1'b0;
                row_addr     <= row_top;
                rl           <= prod_y;
            end else if (split_hit) begin
                reg2         <= 1'b1;
                row_addr     <= row_top;
                rl           <= prod_y;
            end else if (new_row) begin
                row_addr     <= row_step;
                rl           <= vwrap ? 10'd0 : rl + 10'd1;
            end
            if (enable && trig_n < 9'd360) begin
                f_long   <= long_ok;
                wptr     <= {trig_n[0], 10'd0};
                ptr_here <= ptr_hit;
                ptr_left <= {1'b0, ptr_x} - {6'd0, ptr_hot[3:0], 1'b0};
                if (ptr_hit) begin
                    fst    <= F_PTR;
                    f_addr <= AW'({ptr_img[23:3], 3'b000}) + AW'({ptr_dy[4:0], 3'b000});
                end else begin
                    fst    <= F_PIX0;
                end
            end
        end

        // read latches
        if (xio_rd && xio_addr == 8'h06) line_hi  <= nv_line[8];
        if (xio_rd && xio_addr == 8'h0C) frame_hi <= frame[15:8];

        // register writes
        if (!run) begin
            ctrl <= 4'd0; stride <= 16'd640; line_cmp <= 9'd511; base_pending <= 1'b0; frame <= 16'd0;
            scx_p <= 12'd0; scx2_p <= 12'd0; scy_p <= 10'd0; scy2_p <= 10'd0; vh_p <= 10'd0; sctl_p <= 2'd0;
        end else if (w_en) begin
            case (w_a)
                8'h00: ctrl <= w_d[3:0];
                8'h02: begin base_pend[7:0]  <= w_d; base_pending <= 1'b1; end
                8'h03: begin base_pend[15:8] <= w_d; base_pending <= 1'b1; end
                8'h04: stride[7:0]   <= w_d;
                8'h05: stride[15:8]  <= w_d;
                8'h08: line_cmp[7:0] <= w_d;
                8'h09: line_cmp[8]   <= w_d[0];
                8'h0B: late          <= 8'd0;
                8'h10: pal_idx       <= w_d;
                8'h11: pal_r         <= w_d;
                8'h12: pal_g         <= w_d;
                8'h13: pal_idx       <= pal_idx + 8'd1;
                8'h20: ptr_x[7:0]    <= w_d;
                8'h21: ptr_x[9:8]    <= w_d[1:0];
                8'h22: ptr_y[7:0]    <= w_d;
                8'h23: ptr_y[8]      <= w_d[0];
                8'h24: ptr_hot       <= w_d;
                8'h25: ptr_img[7:0]  <= w_d;
                8'h26: ptr_img[15:8] <= w_d;
                8'h27: ptr_img[23:16] <= w_d;
                8'h28: ptr_c[1]      <= w_d;
                8'h29: ptr_c[2]      <= w_d;
                8'h2A: ptr_c[3]      <= w_d;
                8'h30: scx_p[7:0]    <= w_d;
                8'h31: scx_p[11:8]   <= w_d[3:0];
                8'h32: scy_p[7:0]    <= w_d;
                8'h33: scy_p[9:8]    <= w_d[1:0];
                8'h34: scx2_p[7:0]   <= w_d;
                8'h35: scx2_p[11:8]  <= w_d[3:0];
                8'h36: scy2_p[7:0]   <= w_d;
                8'h37: scy2_p[9:8]   <= w_d[1:0];
                8'h38: vh_p[7:0]     <= w_d;
                8'h39: vh_p[9:8]     <= w_d[1:0];
                8'h3A: sctl_p        <= w_d[1:0];
                default: ;
            endcase
        end
    end
end

// ── two-line buffer (clk write, clk_pix read) ────────────────────────────────
reg [8:0] lbuf [0:2047];
always_ff @(posedge clk) if (lb_we) lbuf[wptr] <= wbyte;

// ── sprites ──────────────────────────────────────────────────────────────────
// One dual-port block RAM, 2048 x 9 ("SLB"): the sprite line buffer, two halves of 640 pixels
// at $000 and $400 ({BEHIND, palette index}; 0 = transparent), and the records at $300 (as
// written) and $380 (the set in use). Port A (clk_core) draws pixels and reads/writes records;
// port B (clk_pix) reads the line on screen and clears each pixel after its last read.
//
// Per line, at the fetch trigger: EVAL reads Y and CTRL of all 16 records and marks the ones
// to draw (index order, width budget 512); then the fetch unit takes them from 15 down to 0:
// it reads the record, fetches the sprite's row (one 16-byte burst, or two of 8 bytes while
// the classic machine runs, or one of 8 for a 16-pixel 4 bpp row) into s_nxt, and the painter
// writes it from s_cur into the buffer, a pixel per cycle, while the next one is fetched.
// Port A goes, in this order of priority, to: CPU record writes, a PEEK read, the copy, the
// engine's record reads, the painter. All of them are registered, so nothing from the CPU's
// address decode reaches the engine's enables in the same cycle.
/* verilator lint_off MULTIDRIVEN */
reg  [8:0]  slb [0:2047];
/* verilator lint_on MULTIDRIVEN */
reg  [8:0]  pa_q;
reg         pa_we;
reg  [10:0] pa_a;
reg  [8:0]  pa_d;
always_ff @(posedge clk) begin
    if (pa_we) slb[pa_a] <= pa_d;
    else       pa_q <= slb[pa_a];
end

// copy of the records (COMMIT) and their clearing while the CPU is held in reset
reg  [6:0]  cp_k;
reg  [1:0]  cp_ph;                     // 0 read $300+k, 1 capture, 2 write $380+k
reg  [7:0]  cp_d;
reg  [7:0]  cl_k;
reg         vbl_win;                   // between the fetch triggers of lines 360 and 0

// line engine
reg         ev_run;                    // EVAL issuing reads
reg  [3:0]  ev_i;
reg  [1:0]  ev_b;                      // 0 Y low, 1 Y high, 2 CTRL
reg  [7:0]  ev_ylo;
reg  [1:0]  ev_yhi;
reg  [15:0] mask;
reg  [6:0]  units;                     // width taken on this line, in 16-pixel units
reg  [8:0]  e_y;                       // picture line (mode 2: n / 2)
reg         e_half, e_w320;
reg         rd_v, rd_ev;               // a record byte arrives in pa_q this cycle
reg  [3:0]  rd_i;
reg  [2:0]  rd_b;
typedef enum logic [2:0] { U_IDLE, U_SCAN, U_RD, U_CALC, U_REQ, U_FULL } ust_t;
ust_t       ust;
reg  [3:0]  u_i;
reg  [2:0]  u_b;
reg         u_rdall;                   // all 8 reads of the record issued
reg  [10:0] a_x;
reg  [9:0]  a_y;
reg  [19:0] a_img;                     // address bits 23:4
reg  [3:0]  a_pal;
reg  [7:0]  a_ctl;
reg         s_two, s_hi, s_drop;       // two 8-byte bursts; the second one is next; dropped
reg  [127:0] s_nxt, s_cur;
reg         s_nxt_v;
reg         p_busy;
reg  [5:0]  p_d, p_last;
reg  [10:0] p_x;
reg         p_mag, p_hf, p_b4, p_wd, p_bh;
reg  [3:0]  p_pal;
reg         pw_v;                      // painter write slot
reg  [9:0]  pw_col;
reg  [8:0]  pw_d;

// port A arbitration (all requests are registers)
wire        g_cpu = run && w_en && w_a[7];
wire        g_pk  = run && !g_cpu && pk_req;
wire        cp_rw = cp_busy && (cp_ph != 2'd1);
wire        g_cp  = run && !g_cpu && !g_pk && cp_rw;
wire        ev_is = ev_run;
wire        u_is  = (ust == U_RD) && !u_rdall;
wire        g_rd  = run && !g_cpu && !g_pk && !cp_busy && (ev_is || u_is);
wire        g_pw  = run && !g_cpu && !g_pk && !cp_busy && !ev_is && !u_is && pw_v;
wire [2:0]  ev_off = (ev_b == 2'd0) ? 3'd2 : (ev_b == 2'd1) ? 3'd3 : 3'd7;
always_comb begin
    pa_we = 1'b0; pa_d = 9'd0;
    pa_a  = {e_half, pw_col};
    if (!run) begin
        pa_we = 1'b1; pa_a = {3'b011, cl_k};
    end else if (g_cpu) begin
        pa_we = 1'b1; pa_a = {4'b0110, w_a[6:0]}; pa_d = {1'b0, w_d};
    end else if (g_pk) begin
        pa_a = {3'b011, pk_a};
    end else if (g_cp) begin
        pa_we = (cp_ph == 2'd2); pa_a = {3'b011, cp_ph == 2'd2, cp_k}; pa_d = {1'b0, cp_d};
    end else if (g_rd) begin
        pa_a = ev_is ? {4'b0111, ev_i, ev_off} : {4'b0111, u_i, u_b};
    end else if (g_pw) begin
        pa_we = 1'b1; pa_d = pw_d;
    end
end

// EVAL: is sprite rd_i on this line, and what does it cost
wire [9:0]  ev_yv   = {ev_yhi, ev_ylo};
wire [10:0] ev_dy   = {2'b00, e_y} - {ev_yv[9], ev_yv};
wire [1:0]  ev_sh   = {1'b0, pa_q[5]} + {1'b0, pa_q[3]};      // TALL + MAG (CTRL in pa_q)
wire        ev_vis  = pa_q[0] && !ev_dy[10] &&
                      ((ev_sh == 2'd0) ? (ev_dy[9:4] == 6'd0) :
                       (ev_sh == 2'd1) ? (ev_dy[9:5] == 5'd0) : (ev_dy[9:6] == 4'd0));
wire [1:0]  ev_csh  = {1'b0, pa_q[4] & pa_q[6]} + {1'b0, pa_q[3]};   // WIDE (4 bpp) + MAG
wire [6:0]  ev_cost = 7'd1 << ev_csh;
wire [6:0]  ev_sum  = units + ev_cost;

// the fetch unit's row address
wire [10:0] u_dy    = {2'b00, e_y} - {a_y[9], a_y};
wire [4:0]  u_r     = a_ctl[3] ? u_dy[5:1] : u_dy[4:0];
wire [4:0]  u_rv    = a_ctl[2] ? ((a_ctl[5] ? 5'd31 : 5'd15) - u_r) : u_r;
wire        u_8b    = a_ctl[6] && !a_ctl[4];                   // 16-pixel 4 bpp row: 8 bytes
wire [23:0] u_row   = {a_img, 4'd0} + (u_8b ? {16'd0, u_rv, 3'd0} : {15'd0, u_rv, 4'd0});

// the painter: pixel p_d of the sprite on screen
wire [5:0]  pj      = p_mag ? {1'b0, p_d[5:1]} : p_d;
wire [4:0]  pjj     = p_hf ? ((p_wd ? 5'd31 : 5'd15) - pj[4:0]) : pj[4:0];
wire [3:0]  pbi     = p_b4 ? pjj[4:1] : pjj[3:0];
wire [7:0]  pbyte   = s_cur[{pbi, 3'b000} +: 8];
wire [3:0]  pnib    = pjj[0] ? pbyte[3:0] : pbyte[7:4];
wire [7:0]  ppix    = p_b4 ? {p_pal, pnib} : pbyte;
wire        popq    = p_b4 ? (pnib != 4'd0) : (pbyte != 8'd0);
wire [10:0] pcol    = p_x + {5'd0, p_d};
wire        pin     = !pcol[10] && (pcol[9:0] < (e_w320 ? 10'd320 : 10'd640));
wire        p_step  = p_busy && (!pw_v || g_pw);
wire        e_busy  = ev_run || rd_v || (ust != U_IDLE) || p_busy || pw_v || s_nxt_v;

always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        spr_en <= 1'b0; cm_req <= 1'b0; spr_ovf <= 1'b0; spr_late <= 1'b0;
        pk_a <= 8'd0; pk_d <= 8'd0; pk_req <= 1'b0; pk_rdv <= 1'b0;
        cp_busy <= 1'b0; cp_k <= 7'd0; cp_ph <= 2'd0; cp_d <= 8'd0; cl_k <= 8'd0; vbl_win <= 1'b0;
        ev_run <= 1'b0; ev_i <= 4'd0; ev_b <= 2'd0; ev_ylo <= 8'd0; ev_yhi <= 2'd0; mask <= 16'd0; units <= 7'd0;
        e_y <= 9'd0; e_half <= 1'b0; e_w320 <= 1'b0;
        rd_v <= 1'b0; rd_ev <= 1'b0; rd_i <= 4'd0; rd_b <= 3'd0;
        ust <= U_IDLE; u_i <= 4'd0; u_b <= 3'd0; u_rdall <= 1'b0;
        a_x <= 11'd0; a_y <= 10'd0; a_img <= 20'd0; a_pal <= 4'd0; a_ctl <= 8'd0;
        s_req <= 1'b0; s_addr <= '0; s_long <= 1'b0; s_two <= 1'b0; s_hi <= 1'b0; s_drop <= 1'b0;
        s_nxt <= 128'd0; s_cur <= 128'd0; s_nxt_v <= 1'b0;
        p_busy <= 1'b0; p_d <= 6'd0; p_last <= 6'd0; p_x <= 11'd0;
        p_mag <= 1'b0; p_hf <= 1'b0; p_b4 <= 1'b0; p_wd <= 1'b0; p_bh <= 1'b0; p_pal <= 4'd0;
        pw_v <= 1'b0; pw_col <= 10'd0; pw_d <= 9'd0;
    end else begin
        cl_k <= cl_k + 8'd1;

        // registers
        if (!run) begin
            spr_en <= 1'b0; cm_req <= 1'b0; spr_ovf <= 1'b0; spr_late <= 1'b0;
            pk_a <= 8'd0; pk_req <= 1'b0; cp_busy <= 1'b0;
        end else if (w_en) begin
            case (w_a)
                8'h40: spr_en <= w_d[0];
                8'h41: cm_req <= 1'b1;
                8'h42: begin if (w_d[0]) spr_ovf <= 1'b0; if (w_d[1]) spr_late <= 1'b0; end
                8'h43: begin pk_a <= w_d; pk_req <= 1'b1; end
                default: ;
            endcase
        end

        // PEEK
        pk_rdv <= g_pk;
        if (g_pk) pk_req <= 1'b0;
        if (pk_rdv) pk_d <= pa_q[7:0];

        // COMMIT: copy $300-$37F to $380-$3FF in vertical blank
        if (trig) vbl_win <= (trig_n >= 9'd360);
        if (run && !cp_busy && cm_req && vbl_win) begin
            cp_busy <= 1'b1; cm_req <= 1'b0; cp_k <= 7'd0; cp_ph <= 2'd0;
        end
        if (cp_busy) begin
            if (cp_ph == 2'd1) begin cp_d <= pa_q[7:0]; cp_ph <= 2'd2; end
            else if (g_cp) begin
                if (cp_ph == 2'd0) cp_ph <= 2'd1;
                else begin
                    cp_ph <= 2'd0; cp_k <= cp_k + 7'd1;
                    if (cp_k == 7'd127) cp_busy <= 1'b0;
                end
            end
        end

        // record reads: the byte arrives a cycle after the read
        rd_v <= g_rd;
        if (g_rd) begin
            rd_ev <= ev_is;
            rd_i  <= ev_is ? ev_i : u_i;
            rd_b  <= ev_is ? {1'b0, ev_b} : u_b;
        end

        // EVAL
        if (g_rd && ev_is) begin
            if (ev_b == 2'd2) begin
                ev_b <= 2'd0; ev_i <= ev_i + 4'd1;
                if (ev_i == 4'd15) ev_run <= 1'b0;
            end else ev_b <= ev_b + 2'd1;
        end
        if (rd_v && rd_ev) begin
            case (rd_b[1:0])
                2'd0: ev_ylo <= pa_q[7:0];
                2'd1: ev_yhi <= pa_q[1:0];
                default: begin
                    if (ev_vis) begin
                        if (ev_sum <= 7'd32) begin mask[rd_i] <= 1'b1; units <= ev_sum; end
                        else spr_ovf <= 1'b1;
                    end
                    if (rd_i == 4'd15) begin ust <= U_SCAN; u_i <= 4'd15; end
                end
            endcase
        end

        // fetch unit
        case (ust)
            U_SCAN: begin
                if (mask[u_i]) begin ust <= U_RD; u_b <= 3'd0; u_rdall <= 1'b0; end
                else if (u_i == 4'd0) ust <= U_IDLE;
                else u_i <= u_i - 4'd1;
            end
            U_RD: begin
                if (g_rd && !ev_is) begin
                    u_b <= u_b + 3'd1;
                    if (u_b == 3'd7) u_rdall <= 1'b1;
                end
                if (rd_v && !rd_ev) begin
                    case (rd_b)
                        3'd0: a_x[7:0]   <= pa_q[7:0];
                        3'd1: a_x[10:8]  <= pa_q[2:0];
                        3'd2: a_y[7:0]   <= pa_q[7:0];
                        3'd3: a_y[9:8]   <= pa_q[1:0];
                        3'd4: begin a_pal <= pa_q[3:0]; a_img[3:0] <= pa_q[7:4]; end
                        3'd5: a_img[11:4]  <= pa_q[7:0];
                        3'd6: a_img[19:12] <= pa_q[7:0];
                        default: begin a_ctl <= pa_q[7:0]; ust <= U_CALC; end
                    endcase
                end
            end
            U_CALC: if (!s_drop) begin
                s_req  <= 1'b1;
                s_addr <= AW'(u_row);
                s_two  <= !u_8b && !long_ok;
                s_long <= !u_8b && long_ok;
                s_hi   <= 1'b0;
                ust    <= U_REQ;
            end
            U_REQ: if (s_done) begin
                if (s_two && !s_hi) begin
                    s_nxt[63:0] <= sd_rdata[63:0];
                    s_hi   <= 1'b1;
                    s_addr <= s_addr + AW'(8);
                end else begin
                    if (s_hi) s_nxt[127:64] <= sd_rdata[63:0];
                    else      s_nxt <= sd_rdata;
                    s_req   <= 1'b0;
                    s_nxt_v <= 1'b1;
                    ust     <= U_FULL;
                end
            end
            U_FULL: if (!p_busy) begin
                if (u_i == 4'd0) ust <= U_IDLE;
                else begin u_i <= u_i - 4'd1; ust <= U_SCAN; end
            end
            default: ;
        endcase
        if (s_done && s_drop) begin s_drop <= 1'b0; s_req <= 1'b0; end

        // painter
        if (!p_busy && s_nxt_v) begin
            s_cur   <= s_nxt;
            s_nxt_v <= 1'b0;
            p_busy  <= 1'b1;
            p_d     <= 6'd0;
            p_last  <= (6'd16 << ({1'b0, a_ctl[4] & a_ctl[6]} + {1'b0, a_ctl[3]})) - 6'd1;
            p_x     <= a_x;
            p_mag   <= a_ctl[3]; p_hf <= a_ctl[1]; p_b4 <= a_ctl[6]; p_wd <= a_ctl[4] & a_ctl[6];
            p_bh    <= a_ctl[7]; p_pal <= a_pal;
        end
        if (p_step) begin
            pw_v   <= popq && pin;
            pw_col <= pcol[9:0];
            pw_d   <= {p_bh, ppix};
            p_d    <= p_d + 6'd1;
            if (p_d == p_last) p_busy <= 1'b0;
        end else if (g_pw) pw_v <= 1'b0;

        // a new line: whatever is left of the last one is abandoned
        if (trig) begin
            if (e_busy) spr_late <= 1'b1;
            ev_run <= 1'b0; rd_v <= 1'b0; ust <= U_IDLE; p_busy <= 1'b0; pw_v <= 1'b0; s_nxt_v <= 1'b0;
            if (s_req && !s_done) s_drop <= 1'b1;
            else                  s_req  <= 1'b0;
            if (enable && spr_en && run && trig_n < 9'd360) begin
                ev_run <= 1'b1; ev_i <= 4'd0; ev_b <= 2'd0; mask <= 16'd0; units <= 7'd0;
                e_y    <= (mode == 2'd2) ? {1'b0, trig_n[8:1]} : trig_n;
                e_half <= trig_n[0];
                e_w320 <= (mode == 2'd2);
            end
        end
    end
end

// ── pixel side ───────────────────────────────────────────────────────────────
reg [3:0] ctrl_p1, ctrl_p2;
always_ff @(posedge clk_pix) begin ctrl_p1 <= ctrl; ctrl_p2 <= ctrl_p1; nv_on <= ctrl_p2[0]; end
wire        m2_p   = (ctrl_p2[2:1] == 2'd2);
wire [9:0]  y_rel  = vy - V_TOP;                           // 0..719 when active
wire [10:0] raddr  = {y_rel[1], m2_p ? {1'b0, hx[10:2]} : hx[10:1]};
// a sprite pixel is cleared after its last read: on the second output line of the line, at
// the last pixel clock of the pixel (the output keeps the value read before). In 320x180 mode
// the spare pixel clock 1 of each pixel also clears pixel x + 320, which that mode never shows
// but a line drawn just before a switch from a 640 mode may have left there.
wire        pb_hi  = m2_p && (hx[1:0] == 2'd1) && y_rel[0];   // (a clear cycle: the read is skipped)
wire [10:0] pb_a   = pb_hi ? {y_rel[1], {1'b0, hx[10:2]} + 10'd320} : raddr;
wire        pb_clr = (y_rel < 10'd720) && (hx < 11'd1280) && y_rel[0] && hx[0];
reg  [8:0]  lb_q, sp_q;
always_ff @(posedge clk_pix) lb_q <= lbuf[raddr];
always_ff @(posedge clk_pix) begin
    if (pb_clr) slb[pb_a] <= 9'd0;
    else        sp_q <= slb[pb_a];
end
wire        sp_show = (sp_q[7:0] != 8'd0) && !lb_q[8] && !(sp_q[8] && lb_q[7:0] != 8'd0);
wire [7:0]  pidx   = sp_show ? sp_q[7:0] : lb_q[7:0];
reg  [23:0] pal_q;
always_ff @(posedge clk_pix) pal_q <= pal[pidx];
assign {nv_r, nv_g, nv_b} = pal_q;

endmodule
`default_nettype wire
