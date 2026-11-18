// Gowin rPLL: 27 MHz → 135 MHz (HDMI TMDS serialiser clock)
//
// Formula (UG286E v2.0.2E): FOUT = FCLKIN*(FBDIV_SEL+1)/(IDIV_SEL+1) = 27*5/1 = 135 MHz
// VCO  = FCLKIN*(FBDIV_SEL+1)*ODIV_SEL/(IDIV_SEL+1) = 27*5*8 = 1080 MHz (500-1250 MHz ✓)
// CLKIN must be on pin 4 (LPLL1_T_in, Bank 7) — NOT pin 10 (GCLKT_6). Pin 10 adds GCLK buffer
// jitter that prevents PLL lock. Bank 7 VCCIO is 1.8V per toolchain; use IO_TYPE=LVCMOS18.
//
// CRITICAL: rPLL maps to LPLL2. Do NOT drive LPLL2_T_fb (pin15) or LPLL2_C_fb (pin16)
// as GPIO outputs — even with CLKFB_SEL="internal" this prevents the PLL from locking.
//
// DEVICE="GW2AR-18C": confirmed valid; "GW2AR-18" triggers EX0206.

module rpll_135m (
    input  wire clk_in,
    output wire clk_135m,
    output wire locked
);

wire clkoutp_nc, clkoutd_nc, clkoutd3_nc;
wire gnd = 1'b0;

rPLL rpll_inst (
    .CLKIN    (clk_in),
    .CLKFB    (gnd),
    .RESET    (gnd),
    .RESET_P  (gnd),
    .FBDSEL   ({gnd,gnd,gnd,gnd,gnd,gnd}),
    .IDSEL    ({gnd,gnd,gnd,gnd,gnd,gnd}),
    .ODSEL    ({gnd,gnd,gnd,gnd,gnd,gnd}),
    .PSDA     ({gnd,gnd,gnd,gnd}),
    .DUTYDA   ({gnd,gnd,gnd,gnd}),
    .FDLY     ({gnd,gnd,gnd,gnd}),
    .LOCK     (locked),
    .CLKOUT   (clk_135m),
    .CLKOUTP  (clkoutp_nc),
    .CLKOUTD  (clkoutd_nc),
    .CLKOUTD3 (clkoutd3_nc)
);

defparam rpll_inst.FCLKIN          = "27";
defparam rpll_inst.DYN_IDIV_SEL    = "false";
defparam rpll_inst.IDIV_SEL        = 0;
defparam rpll_inst.DYN_FBDIV_SEL   = "false";
defparam rpll_inst.FBDIV_SEL       = 4;
defparam rpll_inst.DYN_ODIV_SEL    = "false";
defparam rpll_inst.ODIV_SEL        = 8;
defparam rpll_inst.PSDA_SEL        = "0000";
defparam rpll_inst.DYN_DA_EN       = "true";
defparam rpll_inst.DUTYDA_SEL      = "1000";
defparam rpll_inst.CLKOUT_FT_DIR   = 1'b1;
defparam rpll_inst.CLKOUTP_FT_DIR  = 1'b1;
defparam rpll_inst.CLKOUT_DLY_STEP = 0;
defparam rpll_inst.CLKOUTP_DLY_STEP = 0;
defparam rpll_inst.CLKFB_SEL       = "internal";
defparam rpll_inst.CLKOUT_BYPASS   = "false";
defparam rpll_inst.CLKOUTP_BYPASS  = "false";
defparam rpll_inst.CLKOUTD_BYPASS  = "false";
defparam rpll_inst.DYN_SDIV_SEL    = 2;
defparam rpll_inst.CLKOUTD_SRC     = "CLKOUT";
defparam rpll_inst.CLKOUTD3_SRC    = "CLKOUT";
defparam rpll_inst.DEVICE          = "GW2AR-18C";

endmodule
