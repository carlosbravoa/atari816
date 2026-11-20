// SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
// Copyright (c) 2026 Carlos Bravo
// a816_opl — YM3812 (OPL2) wrapper for Atari816 (REV $0C) using JTOPL (GPL-3.0).
//
// Registers ($00:DB30-$00:DB33):
//   $DB30  W: OPL_ADDR   (select OPL2 register)
//          R: OPL_STAT   ({IRQ, T1, T2, 5'b00110} = $06 idle)
//   $DB31  W: OPL_DATA   (write selected OPL2 register)
//   $DB32  R: OPL_OUT_LO (current signed 16-bit sample, low byte)
//   $DB33  R: OPL_OUT_HI (current signed 16-bit sample, high byte)
//
// Clocking: clk = clk_core (28.6875 MHz); cen = clk/8 (3.5859 MHz, +0.18% of 3.5795 MHz).
// CPU writes and reads are registered once so JTOPL never enters the 65C816 critical path.
`default_nettype none

module a816_opl (
    input  wire               clk,       // clk_core (28.6875 MHz)
    input  wire               reset_n,
    input  wire               run,       // 0 = 65C816 held in reset (held >= 512 clk -> >= 64 cen)

    input  wire               xio_wr,    // write strobe for $00:DBxx
    input  wire [7:0]         xio_addr,
    input  wire [7:0]         xio_wdata,
    output reg  [7:0]         xio_rdata, // non-zero only for $30/$32/$33 (ORed with Lau's rdata)
    output wire               irq,       // active-high level (Timer A / Timer B overflow)

    output wire signed [15:0] snd
);

reg [2:0] div = 3'd0;
reg       cen = 1'b0;
always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        div <= 3'd0;
        cen <= 1'b0;
    end else begin
        div <= div + 3'd1;
        cen <= (div == 3'd7);
    end
end

wire opl_rst = !reset_n || !run;

// Registered CPU write (1 clk_core later, off the 65C816 critical path)
reg       wr_r   = 1'b0;
reg       addr_r = 1'b0;
reg [7:0] data_r = 8'h00;
always_ff @(posedge clk) begin
    if (opl_rst) begin
        wr_r   <= 1'b0;
        addr_r <= 1'b0;
        data_r <= 8'h00;
    end else begin
        wr_r   <= xio_wr && (xio_addr[7:1] == 7'b0011_000);   // $DB30-$DB31
        addr_r <= xio_addr[0];
        data_r <= xio_wdata;
    end
end

wire [7:0] opl_dout;
wire       opl_irq_n;
wire       opl_sample;

jtopl2 u_opl2 (
    .rst    (opl_rst),
    .clk    (clk),
    .cen    (cen),
    .din    (data_r),
    .addr   (addr_r),
    .cs_n   (~wr_r),
    .wr_n   (~wr_r),
    .dout   (opl_dout),
    .irq_n  (opl_irq_n),
    .snd    (snd),
    .sample (opl_sample)
);

assign irq = ~opl_irq_n;

// Registered read data (a816_sys holds xio_addr across S_A -> S_B)
always_ff @(posedge clk) begin
    case (xio_addr)
        8'h30:   xio_rdata <= opl_dout;
        8'h32:   xio_rdata <= snd[7:0];
        8'h33:   xio_rdata <= snd[15:8];
        default: xio_rdata <= 8'h00;
    endcase
end

endmodule
`default_nettype wire
