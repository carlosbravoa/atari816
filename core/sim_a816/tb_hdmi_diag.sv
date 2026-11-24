// SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
// Copyright (c) 2026 Carlos Bravo
//
// tb_hdmi_diag.sv - the HDMI diagnostic counters (src/hdmi_diag.sv) against forced events:
// lock glitches shorter than a sys_clk cycle and longer, a core-PLL drop, the HDMI side's
// raster restarted by hdmi_rst_n (a frame of the wrong length), a frame one line short, a
// genlock jump toggle, S1, and the FIX_LOCK_FILTER output. run_hdmi_diag.sh runs it.
// The clocks keep the board's exact ratio: clk_pix / sys_clk = 85 / 32 (13952 / 37060 ps).
`timescale 1ps/1ps
module tb_hdmi_diag;
    localparam int SYS_P = 37060, PIX_P = 13952;
    localparam int H_TOT = 1572, V_TOT = 760;

    logic sys_clk = 0, clk_pix = 0;
    always #(SYS_P / 2) sys_clk = ~sys_clk;
    always #(PIX_P / 2) clk_pix = ~clk_pix;

    logic rst_n = 0;             // power-on timer / S1
    logic hlock = 0, clock = 0;  // the PLLs' LOCK
    wire  hw_reset_n = rst_n && clock;
    wire  hdmi_rst_n = hw_reset_n && hlock;
    logic jump_tog = 0;
    logic short_line = 0;        // the next frame one line short (a genlock-like jump)

    // the pixel side's raster as scandoubler_480p makes it: reset by hdmi_rst_n
    logic [10:0] hx;
    logic [9:0]  vy;
    always_ff @(posedge clk_pix or negedge hdmi_rst_n) begin
        if (!hdmi_rst_n) begin
            hx <= 0; vy <= 0;
        end else begin
            hx <= (hx == H_TOT - 1) ? 0 : hx + 1;
            if (hx == H_TOT - 1) begin
                if (short_line && vy == 100) begin vy <= 102; short_line <= 0; end
                else vy <= (vy >= V_TOT - 1) ? 0 : vy + 1;
            end
        end
    end
    logic vs_reg;
    always_ff @(posedge clk_pix) vs_reg <= (vy < 5);

    logic [31:0] rf, ra, rb, rc, rd;
    logic [3:0]  sticky;
    logic        filt;
    hdmi_diag #(.ARM_CYCLES(2000)) dut (
        .sys_clk(sys_clk), .rst_n(rst_n), .hlock(hlock), .clock(clock),
        .hdmi_rst_n(hdmi_rst_n), .vs_pix(vs_reg), .jump_tog_pix(jump_tog),
        .hw_reset_n(hw_reset_n),
        .reg_frames(rf), .reg_a(ra), .reg_b(rb), .reg_c(rc), .reg_d(rd),
        .sticky(sticky), .lock_ok_filt(filt));

    localparam longint FRAME = longint'(H_TOT) * V_TOT * PIX_P;   // ps

    int fails = 0;
    task automatic check(string what, logic [31:0] got, logic [31:0] want);
        if (got !== want) begin
            $display("FAIL %s: got %0d ($%08x), want %0d", what, got, got, want);
            fails++;
        end else
            $display("ok   %s = %0d", what, got);
    endtask
    task automatic show(string when);
        $display("-- %s: frames %0d  hlock %0d clock %0d hrst %0d flags %02x  bad %0d jump %0d  lastbad %0d last %0d  filt %0d",
                 when, rf, ra[7:0], ra[15:8], ra[23:16], ra[31:24], rb[15:0], rb[31:24], rc, rd, filt);
    endtask

    initial begin
        // power-on: the timer runs, then the PLLs lock (the locks are low first: not counted)
        #(10 * SYS_P) rst_n = 1;
        #(2_000_000) clock = 1;
        #(1_000_000) hlock = 1;
        #(3 * FRAME);
        show("after 3 frames");
        check("nothing counted at power-on (hlock)", ra[7:0], 0);
        check("nothing counted at power-on (hrst)", ra[23:16], 0);
        check("no bad frame", rb[15:0], 0);
        check("armed", ra[29], 1);
        check("frame length (nominal 449777 +-1)", (rd >= 449776 && rd <= 449778), 1);
        check("filter released after the lock", filt, 1);

        // 1. a 5 ns glitch of the HDMI PLL's lock (shorter than a sys_clk cycle)
        #(FRAME / 3);                       // mid-frame: the restart shortens it
        hlock = 0; #5000; hlock = 1;
        #(2 * FRAME);
        show("after a 5 ns HDMI lock glitch");
        check("hlock drops", ra[7:0], 1);
        check("hdmi_rst_n pulses", ra[23:16], 1);
        check("core lock drops", ra[15:8], 0);
        check("bad frames (the raster restarted)", rb[15:0] >= 1, 1);
        check("sticky {jump,bad,clock,hlock}", sticky, 4'b0101);
        check("filter ignored the glitch", filt, 1);

        // 2. the core PLL drops for 100 ns (hw_reset_n -> hdmi_rst_n too)
        #(FRAME / 5);
        clock = 0; #100_000; clock = 1;
        #(2 * FRAME);
        show("after a 100 ns core lock drop");
        check("core lock drops", ra[15:8], 1);
        check("hdmi_rst_n pulses", ra[23:16], 2);
        check("hlock drops unchanged", ra[7:0], 1);
        check("bad frames now >= 2", rb[15:0] >= 2, 1);

        // 3. a frame one line short (what a genlock jump does to the raster) and a jump toggle
        begin
            logic [15:0] b0;
            b0 = rb[15:0];
            @(posedge clk_pix) short_line = 1;
            jump_tog = ~jump_tog;
            #(3 * FRAME);
            show("after a short frame and a genlock jump");
            check("one more bad frame", rb[15:0], 32'(b0) + 1);
            check("last bad length = a frame less a line (449777 - 592 +-2)",
                   (rc >= 449183 && rc <= 449187), 1);
            check("genlock jumps", rb[31:24], 1);
            check("sticky", sticky, 4'b1111);
        end

        // 4. FIX_LOCK_FILTER: a 50 us drop is ignored, a 200 us one resets the HDMI side,
        //    released 1 ms after the lock is back
        hlock = 0; #50_000_000; hlock = 1;
        #1_000_000;
        check("filter: 50 us drop ignored", filt, 1);
        hlock = 0; #200_000_000;
        check("filter: 200 us drop -> reset", filt, 0);
        hlock = 1; #500_000_000;
        check("filter: still in reset 0.5 ms after", filt, 0);
        #700_000_000;
        check("filter: released after 1 ms of lock", filt, 1);
        check("hlock drops counted", ra[7:0], 3);

        // 5. S1: everything cleared, counting again only once armed
        rst_n = 0; #(10 * SYS_P); rst_n = 1;
        #(10 * SYS_P);
        show("after S1");
        check("cleared hlock", ra[7:0], 0);
        check("cleared bad", rb[15:0], 0);
        check("cleared sticky", sticky, 0);
        check("not armed yet", ra[29], 0);
        #(3 * FRAME);
        check("bad frames after S1", rb[15:0], 0);

        if (fails) $display("tb_hdmi_diag: %0d FAILED", fails);
        else       $display("tb_hdmi_diag: PASS");
        $finish;
    end
endmodule
