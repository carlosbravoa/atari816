// SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
// Copyright (c) 2026 Carlos Bravo
//
// hdmi_diag.sv - sticky event counters for the HDMI output (the "lost picture" hunt,
// 2026-11-24). Everything runs on sys_clk (the 27 MHz pin: it keeps running whatever the
// PLLs do) and is cleared only by the power-on timer and S1 (rst_n), never by hdmi_rst_n.
// Read by the I/O processor at $0200_00EC..$0200_00FC (iosys_picorv32.v), so the PC reads
// them with `atari.py hdmidiag` (FWPEEK) without any 65C816 software; the LEDs show the
// sticky flags (tang_top.sv, HDMI_DIAG_LEDS).
//
// Counted (8-bit counters saturate at 255, 16-bit at 65535):
//   hlock  falling edges of the HDMI PLL's LOCK (rpll_287m)        - async-set catcher
//   clock  falling edges of the core PLL's LOCK (rpll_108m)        - async-set catcher
//   hrst   low pulses of hdmi_rst_n (= hw_reset_n && pll_locked)  - async-set catcher
//   bad    frames whose length (VS rise to VS rise, measured in sys_clk) is not the
//          nominal 1572 x 760 pixel clocks = 449,776.9 sys_clk cycles (+-TOL)
//   jump   genlock jumps that changed vy (scandoubler_480p.sv: a toggle from clk_pix)
// A catcher is a flop set asynchronously by the signal going low (so a glitch of a few ns,
// shorter than a sys_clk cycle, that could reset the CLKDIV / OSER10 is still caught),
// cleared synchronously once the event is counted and the signal is high again.
// Nothing is counted until both PLLs have been locked for ARM_CYCLES after the reset (the
// locks are low at power-on).
//
// Also here (used only with `define FIX_LOCK_FILTER in tang_top.sv): lock_ok_filt, the HDMI
// PLL's lock with drops shorter than FILT_CYCLES ignored; a longer loss still gives the
// HDMI side its reset (held until the lock has been back for RELOCK_CYCLES).
module hdmi_diag #(
    parameter int NOM        = 449777,  // sys_clk cycles a frame (1194720 * 32 / 85)
    parameter int TOL        = 4,       // +- (sampling of VS: +-1, the 0.94 fraction)
    parameter int ARM_CYCLES = 2097152, // 78 ms of both locks before counting
    parameter int FILT_CYCLES   = 2700, // FIX_LOCK_FILTER: drops up to 100 us ignored
    parameter int RELOCK_CYCLES = 27000 // FIX_LOCK_FILTER: 1 ms of lock before release
) (
    input  logic        sys_clk,
    input  logic        rst_n,          // power-on timer and S1 only
    input  logic        hlock,          // rpll_287m LOCK (async)
    input  logic        clock,          // rpll_108m LOCK (async)
    input  logic        hdmi_rst_n,     // the HDMI side's reset (async)
    input  logic        vs_pix,         // VS as sent to hdmi_audio_out (clk_pix register)
    input  logic        jump_tog_pix,   // scandoubler: toggles at each genlock jump
    input  logic        hw_reset_n,     // for the filter: the machine's reset
    output logic [31:0] reg_frames,     // $EC: frames measured since armed
    output logic [31:0] reg_a,          // $F0: {flags, hrst, clock, hlock}
    output logic [31:0] reg_b,          // $F4: {jump, 8'h00, bad[15:0]}
    output logic [31:0] reg_c,          // $F8: {12'h0, the last bad frame's length}
    output logic [31:0] reg_d,          // $FC: {12'h0, the last frame's length}
    output logic [3:0]  sticky,         // {jump, bad, clock, hlock} seen at least once
    output logic        lock_ok_filt    // FIX_LOCK_FILTER: 1 = keep the HDMI side running
);

    // ---- synchronised levels (sys_clk)
    logic [1:0] hl_s = 2'b00, cl_s = 2'b00, vs_s = 2'b00;
    logic [2:0] jt_s = 3'b000;
    always_ff @(posedge sys_clk) begin
        hl_s <= {hl_s[0], hlock};
        cl_s <= {cl_s[0], clock};
        vs_s <= {vs_s[0], vs_pix};
        jt_s <= {jt_s[1:0], jump_tog_pix};
    end
    wire hl = hl_s[1], cl = cl_s[1];

    // ---- armed: both locks steady for ARM_CYCLES since the reset
    logic [21:0] armc = '0;
    logic        armed = 1'b0;
    always_ff @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            armc <= '0;
            armed <= 1'b0;
        end else if (!armed) begin
            if (!(hl && cl))                      armc <= '0;
            else if (armc == 22'(ARM_CYCLES - 1)) armed <= 1'b1;
            else                                  armc <= armc + 22'd1;
        end
    end

    // ---- the catchers: set by the signal low (async), cleared once counted and high again
    logic clr_h = 1'b1, clr_c = 1'b1, clr_r = 1'b1;
    logic seen_h, seen_c, seen_r;
    always_ff @(posedge sys_clk or negedge hlock)
        if (!hlock) seen_h <= 1'b1; else if (clr_h) seen_h <= 1'b0;
    always_ff @(posedge sys_clk or negedge clock)
        if (!clock) seen_c <= 1'b1; else if (clr_c) seen_c <= 1'b0;
    always_ff @(posedge sys_clk or negedge hdmi_rst_n)
        if (!hdmi_rst_n) seen_r <= 1'b1; else if (clr_r) seen_r <= 1'b0;
    logic [1:0] sh_s = 2'b00, sc_s = 2'b00, sr_s = 2'b00;
    always_ff @(posedge sys_clk) begin
        sh_s <= {sh_s[0], seen_h};
        sc_s <= {sc_s[0], seen_c};
        sr_s <= {sr_s[0], seen_r};
    end

    logic [7:0]  n_h, n_c, n_r, n_j;
    logic [15:0] n_bad;
    logic        st_h, st_c, st_r, st_bad;
    // one event: count it (saturating) and ask for the catcher's clear; the clear stays
    // until the synchronised catcher reads 0 (the signal came back and the clear took)
    always_ff @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            n_h <= '0; n_c <= '0; n_r <= '0;
            clr_h <= 1'b1; clr_c <= 1'b1; clr_r <= 1'b1;
            st_h <= 1'b0; st_c <= 1'b0; st_r <= 1'b0;
        end else if (!armed) begin
            clr_h <= 1'b1; clr_c <= 1'b1; clr_r <= 1'b1;
        end else begin
            if (sh_s[1] && !clr_h) begin
                if (n_h != 8'hFF) n_h <= n_h + 8'd1;
                st_h <= 1'b1;
                clr_h <= 1'b1;
            end else if (!sh_s[1]) clr_h <= 1'b0;
            if (sc_s[1] && !clr_c) begin
                if (n_c != 8'hFF) n_c <= n_c + 8'd1;
                st_c <= 1'b1;
                clr_c <= 1'b1;
            end else if (!sc_s[1]) clr_c <= 1'b0;
            if (sr_s[1] && !clr_r) begin
                if (n_r != 8'hFF) n_r <= n_r + 8'd1;
                st_r <= 1'b1;
                clr_r <= 1'b1;
            end else if (!sr_s[1]) clr_r <= 1'b0;
        end
    end

    // ---- frame length: sys_clk cycles between VS rising edges
    logic [19:0] per, last, lastbad;
    logic        have;                  // a VS rise seen since armed (a period runs)
    logic [31:0] frames;
    logic        vs_d;
    always_ff @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            per <= '0; last <= '0; lastbad <= '0; have <= 1'b0; vs_d <= 1'b0;
            n_bad <= '0; frames <= '0; st_bad <= 1'b0;
        end else begin
            vs_d <= vs_s[1];
            if (per != 20'hFFFFF) per <= per + 20'd1;
            if (!armed) begin
                have <= 1'b0;
            end else if (vs_s[1] && !vs_d) begin            // VS rises
                per <= 20'd1;
                have <= 1'b1;
                if (have) begin
                    last <= per;
                    frames <= frames + 32'd1;
                    if (per < 20'(NOM - TOL) || per > 20'(NOM + TOL)) begin
                        lastbad <= per;
                        if (n_bad != 16'hFFFF) n_bad <= n_bad + 16'd1;
                        st_bad <= 1'b1;
                    end
                end
            end else if (have && per == 20'hFFFFF) begin    // no VS for 39 ms: count it once
                lastbad <= per;
                if (n_bad != 16'hFFFF) n_bad <= n_bad + 16'd1;
                st_bad <= 1'b1;
                have <= 1'b0;
            end
        end
    end

    // ---- genlock jumps: edges of the clk_pix toggle
    logic jflag;
    always_ff @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            n_j <= '0; jflag <= 1'b0;
        end else if (armed && (jt_s[2] ^ jt_s[1])) begin
            if (n_j != 8'hFF) n_j <= n_j + 8'd1;
            jflag <= 1'b1;
        end
    end

    // flags byte: bit0 HDMI lock lost, 1 core lock lost, 2 hdmi_rst_n pulse, 3 bad frame,
    // 4 genlock jump, 5 armed, 6 HDMI PLL locked now, 7 VS running now (a VS rise within
    // the last 2 frames)
    wire vs_running = have && per < 20'(2 * NOM);
    assign reg_a = {{vs_running, hl, armed, jflag, st_bad, st_r, st_c, st_h}, n_r, n_c, n_h};
    assign reg_b = {n_j, 8'h00, n_bad};
    assign reg_c = {12'h000, lastbad};
    assign reg_d = {12'h000, last};
    assign reg_frames = frames;
    assign sticky = {jflag, st_bad, st_c, st_h};

    // ---- FIX_LOCK_FILTER: the HDMI PLL's lock with short drops ignored
    logic [15:0] lostc;
    logic [15:0] okc;
    logic        filt;
    always_ff @(posedge sys_clk or negedge hw_reset_n) begin
        if (!hw_reset_n) begin
            filt <= 1'b0;                   // reset until the first lock (as before)
            lostc <= '0;
            okc <= '0;
        end else if (!hl) begin
            okc <= '0;
            if (lostc != 16'hFFFF) lostc <= lostc + 16'd1;
            if (lostc >= 16'(FILT_CYCLES)) filt <= 1'b0;   // a real loss: reset the HDMI side
        end else begin
            lostc <= '0;
            if (!filt) begin
                if (okc == 16'(RELOCK_CYCLES)) filt <= 1'b1;
                else okc <= okc + 16'd1;
            end
        end
    end
    assign lock_ok_filt = filt;

endmodule
