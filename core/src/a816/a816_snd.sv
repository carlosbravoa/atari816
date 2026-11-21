// SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
// Copyright (c) 2026 Carlos Bravo
// Lau, the Atari816 sample player (REV $0A): 8 voices of signed 8- or 16-bit PCM from main RAM, mixed
// at the HDMI audio rate (48 kHz). Register spec "Native audio / Lau (sample player)".
//
//   $DB20 AU_KEYON W   $DB21 AU_KEYOFF W   $DB22 AU_PLAYING R   $DB23 AU_END R/W1C
//   $DB24 AU_IRQ_EN    $DB25 AU_MASTER (reset $C0)   $DB26 AU_LATE (any write clears)
//   $DB27 AU_SEL       $DB28-2A AU_POS (not latched)   $DB2C-2F AU_OUT_L, AU_OUT_R
//   $DB80 + 16n: voice n, write only: +0 START(3) +3 LEN(3) +6 LOOP(3) +9 PITCH(2, 2.14)
//                +B VOL_L +C VOL_R +D CTRL (0 LOOP, 1 SIXTEEN)
//
// One time-multiplexed engine steps the 8 voices one after the other (about 18 cycles each,
// plus a memory read when a voice enters a new 8-byte block) and pushes the mixed (L, R) into
// a 4-entry FIFO; the FIFO is popped at each HDMI sample clock (smp_tgl_a toggles there), so
// the output changes a few cycles after the HDMI transmitter has sampled it. A sample that is
// not ready then is counted in AU_LATE (the output holds).
// CPU writes are registered once before they reach anything (the CPU's address decode is on
// the clk_core critical path). Block RAMs (2 total): voice registers (pram, 128x8) and one
// shared 64x32 SDPB (sram) packing voice state (3 words/voice), 8-byte sample blocks (2
// words/voice) and the 4-entry output FIFO.
`default_nettype none

module a816_snd #(
    parameter int AW = 23
) (
    input  wire          clk,          // clk_core
    input  wire          reset_n,
    input  wire          run,          // 0 = 65C816 held in reset: registers to reset values, voices stop

    input  wire          xio_wr,       // write to $00:DBxx
    input  wire [7:0]    xio_addr,
    input  wire [7:0]    xio_wdata,
    output reg  [7:0]    xio_rdata,
    output wire          irq,          // level: AU_END & AU_IRQ_EN

    input  wire          smp_tgl_a,    // async: toggles at each HDMI audio sample

    // memory port (through the mux in a816_nvc): 8-byte burst reads
    output reg           a_req,        // held until a_done
    output wire [AW-1:0] a_addr,
    input  wire          a_done,
    input  wire [63:0]   a_rdata,

    output reg  signed [15:0] out_l,
    output reg  signed [15:0] out_r
);

// ── registers ────────────────────────────────────────────────────────────────
reg [7:0]  playing, keyon, au_end, irq_en, master, late;
reg [2:0]  sel;
reg [23:0] pos_live;
reg        primed;
assign irq = |(au_end & irq_en);

// Read data is registered: a816_sys holds the address for a whole cycle (S_A) before it takes
// the data (S_B). A combinational mux here made synthesis restructure the CPU's data input
// (+490 LUTs inside the 65C816 core).
always_ff @(posedge clk) begin
    case (xio_addr)
        8'h22: xio_rdata <= playing;
        8'h23: xio_rdata <= au_end;
        8'h24: xio_rdata <= irq_en;
        8'h25: xio_rdata <= master;
        8'h26: xio_rdata <= late;
        8'h27: xio_rdata <= {5'd0, sel};
        8'h28: xio_rdata <= pos_live[7:0];
        8'h29: xio_rdata <= pos_live[15:8];
        8'h2A: xio_rdata <= pos_live[23:16];
        8'h2C: xio_rdata <= out_l[7:0];
        8'h2D: xio_rdata <= out_l[15:8];
        8'h2E: xio_rdata <= out_r[7:0];
        8'h2F: xio_rdata <= out_r[15:8];
        default: xio_rdata <= 8'h00;
    endcase
end

// CPU writes, one clk_core later
reg        rw_en;
reg [7:0]  rw_a, rw_d;
always_ff @(posedge clk) begin
    rw_en <= xio_wr;
    rw_a  <= xio_addr;
    rw_d  <= xio_wdata;
end

// voice registers: written by the CPU, read by the engine one byte a cycle
(* syn_ramstyle = "block_ram" *) reg [7:0] pram [0:127];
reg [6:0]  pr_a;
reg [7:0]  pr_q;
always_ff @(posedge clk) begin
    if (rw_en && rw_a[7]) pram[rw_a[6:0]] <= rw_d;
    pr_q <= pram[pr_a];
end

// ── engine ───────────────────────────────────────────────────────────────────
typedef enum logic [4:0] {
    E_IDLE, E_V0, E_V1, E_V2, E_V3, E_V4, E_V5, E_V6, E_V7, E_V8, E_V9, E_V10, E_V11, E_V12,
    E_V13, E_V14, E_F0, E_F1, E_F2, E_RD, E_VOL, E_WB, E_WB1, E_WB2, E_NEXT, E_OUT
} est_t;
est_t st;

reg  [2:0]  v;
reg  [23:0] pos, B;
reg  [13:0] frac;
reg  [19:0] tag;
reg         force_ld, wrap;
reg  [2:0]  c;                         // whole samples stepped this time
reg  [1:0]  ctl;                       // LOOP, SIXTEEN
reg  [7:0]  tmp8, voll, volr;
reg  [31:0] blk_hi_tmp;                // upper 32 bits of SDRAM burst, written in E_F1
reg  signed [15:0] s_cur;
reg  signed [17:0] acc_l, acc_r;
reg  [1:0]  wptr, rptr;
reg  [2:0]  cnt;                       // FIFO entries
reg         pop_pend, pop_rd;
logic [7:0] pl_n, ko_n, end_set;       // next PLAYING / key-on pending, AU_END bits to set

// Shared 64x32 BSRAM (1 SDPB) packing vs, blk and fifo:
//   00_vvv_0 : vs0[v] = {2'd0, frac[13:0], s_cur[15:0]}
//   00_vvv_1 : vs1[v] = {8'd0, pos[23:0]}
//   01_vvv_0 : vs2[v] = {12'd0, tag[19:0]}
//   10_vvv_0 : blk[v][31:0]  (B[2] = 0)
//   10_vvv_1 : blk[v][63:32] (B[2] = 1)
//   11_00_pp : fifo[pp] = {out_l, out_r}
(* syn_ramstyle = "block_ram" *) reg [31:0] sram [0:63];
reg  [31:0] sram_q;
logic       sr_we;
logic [5:0] sr_wa, sr_ra;
logic [31:0] sr_wd;

// one adder for the position: pos + c, pos - LEN, pos + LOOP
wire        p_sub = (st == E_V7);
wire [23:0] p_op  = (st == E_V3) ? {21'd0, c} : B;
wire [24:0] p_sum = {1'b0, pos} + {1'b0, p_sub ? ~p_op : p_op} + {24'd0, p_sub};   // [24] = no borrow
wire [15:0] pitch_w = {pr_q, tmp8};
wire [16:0] fsum  = {3'b000, frac} + {1'b0, pitch_w};
wire [23:0] pos_sh = ctl[1] ? {pos[22:0], 1'b0} : pos;
assign a_addr = {B[AW-1:3], 3'b000};

// sample from the selected 32-bit half of the 8-byte block (little-endian)
wire [15:0] half  = B[1] ? sram_q[31:16] : sram_q[15:0];
wire [7:0]  byte8 = B[0] ? half[15:8] : half[7:0];
wire signed [15:0] s_new = ctl[1] ? half : {byte8, 8'h00};

// multipliers (DSP)
wire signed [24:0] vp_l = s_cur * $signed({1'b0, voll});
wire signed [24:0] vp_r = s_cur * $signed({1'b0, volr});
function automatic signed [15:0] mastered(input signed [17:0] a, input [7:0] m);
    reg signed [26:0] p;
    reg signed [18:0] q;
    p = a * $signed({1'b0, m});
    q = p[26:8];
    mastered = (q > 19'sd32767) ? 16'sh7FFF : (q < -19'sd32768) ? -16'sh8000 : q[15:0];
endfunction

// HDMI sample clock
reg [2:0] tk_s = 3'd0;
always_ff @(posedge clk) tk_s <= {tk_s[1:0], smp_tgl_a};
wire tick = tk_s[2] ^ tk_s[1];

wire eng_sram_rd = (st == E_V0) || (st == E_V1) || (st == E_V2) || (st == E_V14) || (st == E_F2);
wire pop_grant   = pop_pend && !pop_rd && !eng_sram_rd;

always_comb begin
    sr_we = 1'b0;
    sr_wa = 6'd0;
    sr_wd = 32'd0;
    case (st)
        E_F0:  if (a_done) begin sr_we = 1'b1; sr_wa = {2'b10, v, 1'b0}; sr_wd = a_rdata[31:0]; end
        E_F1:  begin sr_we = 1'b1; sr_wa = {2'b10, v, 1'b1}; sr_wd = blk_hi_tmp; end
        E_WB:  begin sr_we = 1'b1; sr_wa = {2'b00, v, 1'b0}; sr_wd = {2'd0, frac, s_cur}; end
        E_WB1: begin sr_we = 1'b1; sr_wa = {2'b00, v, 1'b1}; sr_wd = {8'd0, pos}; end
        E_WB2: begin sr_we = 1'b1; sr_wa = {2'b01, v, 1'b0}; sr_wd = {12'd0, tag}; end
        E_OUT: begin sr_we = 1'b1; sr_wa = {4'b1100, wptr};  sr_wd = {mastered(acc_l, master), mastered(acc_r, master)}; end
        default: ;
    endcase

    case (st)
        E_V0:    sr_ra = {2'b00, v, 1'b0};
        E_V1:    sr_ra = {2'b00, v, 1'b1};
        E_V2:    sr_ra = {2'b01, v, 1'b0};
        E_V14,
        E_F2:    sr_ra = {2'b10, v, B[2]};
        default: sr_ra = {4'b1100, rptr};
    endcase
end

always_ff @(posedge clk) begin
    if (sr_we) sram[sr_wa] <= sr_wd;
    sram_q <= sram[sr_ra];
end

// voice register byte for each state (the data is in pr_q one state later)
always_comb begin
    case (st)
        E_V0:    pr_a = {v, 4'h9};     // PITCH low
        E_V1:    pr_a = {v, 4'hA};     // PITCH high
        E_V2:    pr_a = {v, 4'hD};     // CTRL
        E_V3:    pr_a = {v, 4'h3};     // LEN
        E_V4:    pr_a = {v, 4'h4};
        E_V5:    pr_a = {v, 4'h5};
        E_V6:    pr_a = {v, 4'h6};     // LOOP
        E_V7:    pr_a = {v, 4'h7};
        E_V8:    pr_a = {v, 4'h8};
        E_V9:    pr_a = {v, 4'h0};     // START
        E_V10:   pr_a = {v, 4'h1};
        E_V11:   pr_a = {v, 4'h2};
        E_V12:   pr_a = {v, 4'hB};     // VOL_L
        default: pr_a = {v, 4'hC};     // VOL_R (E_V13)
    endcase
end

wire w_keyon  = rw_en && rw_a == 8'h20;
wire w_keyoff = rw_en && rw_a == 8'h21;

always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        playing <= 8'd0; keyon <= 8'd0; au_end <= 8'd0; irq_en <= 8'd0; master <= 8'hC0; late <= 8'd0;
        sel <= 3'd0; pos_live <= 24'd0; primed <= 1'b0;
        st <= E_IDLE; v <= 3'd0; pos <= 24'd0; B <= 24'd0; frac <= 14'd0; tag <= 20'd0;
        force_ld <= 1'b0; wrap <= 1'b0; c <= 3'd0; ctl <= 2'd0; tmp8 <= 8'd0; voll <= 8'd0; volr <= 8'd0;
        blk_hi_tmp <= 32'd0;
        s_cur <= 16'sd0; acc_l <= 18'sd0; acc_r <= 18'sd0;
        wptr <= 2'd0; rptr <= 2'd0; cnt <= 3'd0; pop_pend <= 1'b0; pop_rd <= 1'b0;
        a_req <= 1'b0; out_l <= 16'sd0; out_r <= 16'sd0;
    end else begin
        pl_n = playing; ko_n = keyon; end_set = 8'd0;

        // FIFO -> output after the HDMI sample clock (borrows sram read port when idle)
        pop_rd <= 1'b0;
        if (pop_grant) begin                   // sram_q holds fifo[rptr] in the next cycle
            pop_rd   <= 1'b1;
            pop_pend <= 1'b0;
        end
        if (pop_rd) begin
            {out_l, out_r} <= sram_q;
            rptr <= rptr + 2'd1;
        end
        if (tick) begin
            if (pop_pend || pop_rd || cnt == 3'd0) begin
                if (primed && late != 8'hFF) late <= late + 8'd1;
            end else pop_pend <= 1'b1;
        end
        cnt <= cnt + ((st == E_OUT) ? 3'd1 : 3'd0) - (pop_rd ? 3'd1 : 3'd0);
        if (st == E_OUT && cnt == 3'd3) primed <= 1'b1;

        case (st)
            E_IDLE: if (cnt < 3'd4) begin
                v     <= 3'd0;
                acc_l <= 18'sd0;
                acc_r <= 18'sd0;
                st    <= E_V0;
            end
            E_V0: st <= E_V1;
            E_V1: begin
                {frac, s_cur} <= sram_q[29:0];
                tmp8 <= pr_q;
                st   <= E_V2;
            end
            E_V2: begin
                if (!playing[v]) st <= E_NEXT;
                else begin
                    st <= E_V3;
                    if (keyon[v]) begin
                        ko_n[v]  = 1'b0;
                        pos      <= 24'd0;
                        frac     <= 14'd0;
                        s_cur    <= 16'sd0;
                        c        <= 3'd0;
                        force_ld <= 1'b1;
                    end else begin
                        pos      <= sram_q[23:0];
                        frac     <= fsum[13:0];
                        c        <= fsum[16:14];
                        force_ld <= 1'b0;
                    end
                end
            end
            E_V3: begin tag <= sram_q[19:0]; ctl <= pr_q[1:0]; pos <= p_sum[23:0]; wrap <= 1'b0; st <= E_V4; end
            E_V4: begin B <= {pr_q, B[23:8]}; st <= E_V5; end
            E_V5: begin B <= {pr_q, B[23:8]}; st <= E_V6; end
            E_V6: begin B <= {pr_q, B[23:8]}; st <= E_V7; end
            E_V7: begin                        // B = LEN; p_sum = pos - LEN
                B  <= {pr_q, B[23:8]};
                st <= E_V8;
                if (p_sum[24]) begin           // pos >= LEN
                    end_set[v] = 1'b1;
                    if (ctl[0]) begin pos <= p_sum[23:0]; wrap <= 1'b1; end
                    else begin
                        if (!keyon[v]) pl_n[v] = 1'b0;
                        st <= E_NEXT;
                    end
                end
            end
            E_V8:  begin B <= {pr_q, B[23:8]}; st <= E_V9; end
            E_V9:  begin B <= {pr_q, B[23:8]}; st <= E_V10; end
            E_V10: begin                       // B = LOOP; p_sum = pos + LOOP
                if (wrap) pos <= p_sum[23:0];
                B  <= {pr_q, B[23:8]};
                st <= E_V11;
            end
            E_V11: begin B <= {pr_q, B[23:8]}; st <= E_V12; end
            E_V12: begin B <= {pr_q, B[23:8]}; st <= E_V13; end
            E_V13: begin                       // B = START
                voll <= pr_q;
                B    <= B + pos_sh;            // sample address
                st   <= E_V14;
            end
            E_V14: begin
                volr <= pr_q;
                if (!force_ld && c == 3'd0) st <= E_VOL;
                else if (!force_ld && tag == B[22:3]) st <= E_RD;
                else begin
                    a_req <= 1'b1;
                    st    <= E_F0;
                end
            end
            E_F0: if (a_done) begin            // low 32 bits written in this cycle
                a_req      <= 1'b0;
                blk_hi_tmp <= a_rdata[63:32];
                tag        <= B[22:3];
                st         <= E_F1;
            end
            E_F1: st <= E_F2;                  // high 32 bits written in this cycle
            E_F2: st <= E_RD;                  // read the selected 32-bit half
            E_RD: begin s_cur <= s_new; st <= E_VOL; end
            E_VOL: begin
                acc_l <= acc_l + 18'(vp_l >>> 9);
                acc_r <= acc_r + 18'(vp_r >>> 9);
                st    <= E_WB;
            end
            E_WB: begin
                if (v == sel) pos_live <= pos;
                st <= E_WB1;
            end
            E_WB1: st <= E_WB2;
            E_WB2: st <= E_NEXT;
            E_NEXT: begin
                v  <= v + 3'd1;
                st <= (v == 3'd7) ? E_OUT : E_V0;
            end
            E_OUT: begin                       // the FIFO entry is written in this cycle
                wptr <= wptr + 2'd1;
                st   <= E_IDLE;
            end
            default: st <= E_IDLE;
        endcase

        // CPU registers
        if (w_keyon)  begin pl_n = pl_n | rw_d;  ko_n = ko_n | rw_d;  end
        if (w_keyoff) begin pl_n = pl_n & ~rw_d; ko_n = ko_n & ~rw_d; end
        playing <= pl_n;
        keyon   <= ko_n;
        au_end  <= (au_end & ~((rw_en && rw_a == 8'h23) ? rw_d : 8'd0)) | end_set;
        if (rw_en) begin
            case (rw_a)
                8'h24: irq_en <= rw_d;
                8'h25: master <= rw_d;
                8'h26: late   <= 8'd0;
                8'h27: sel    <= rw_d[2:0];
                default: ;
            endcase
        end
        if (!run) begin
            playing <= 8'd0; keyon <= 8'd0; au_end <= 8'd0; irq_en <= 8'd0; master <= 8'hC0;
            late <= 8'd0; sel <= 3'd0;
        end
    end
end

endmodule
`default_nettype wire
