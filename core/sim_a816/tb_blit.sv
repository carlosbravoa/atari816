// SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
// Copyright (c) 2026 Carlos Bravo
// Randomised blitter test: a816_blit behind the real port mux (a816_nvc, video off), a random
// CPU-like client competing for the port, and a reference model of emu/blitter.c.
//   ./run_blit.sh [+n=3000] [+seed=1] [+cpu=0..100 (request rate, percent)] [+long=0|1|2 (2 = random)]
`timescale 1ns/1ps
module tb_blit;
    localparam AW = 23;
    localparam int WIN = 'h10000, WBASE = 'h3F000;      // test window: crosses the $04:0000 bank
    reg clk = 0; always #5 clk = ~clk;
    reg reset_n = 0, run = 0;
    reg xio_wr = 0; reg [7:0] xio_addr = 0, xio_wdata = 0; wire [7:0] xio_rdata; wire irq;
    wire b_req, b_gnt, b_we, b_long, b_done; wire [AW-1:0] b_addr; wire [31:0] b_wdata; wire [3:0] b_wmask;
    reg c_req = 0, c_we = 0; reg [AW-1:0] c_addr = 0; reg [7:0] c_wdata = 0; wire c_done;
    wire sd_req, sd_we, sd_long; wire [AW-1:0] sd_addr; wire [31:0] sd_wdata; wire [3:0] sd_wmask;
    reg sd_done = 0; reg [127:0] sd_rdata = 0;
    reg long_ok = 0;

    a816_nvc #(.AW(AW)) nvc (.clk, .reset_n, .run, .xio_wr(1'b0), .xio_rd(1'b0), .xio_addr(8'h00), .xio_wdata(8'h00), .xio_rdata(),
        .irq_vblank(), .irq_line(), .c_req, .c_we, .c_addr, .c_wdata, .c_done,
        .b_req, .b_we, .b_addr, .b_wdata, .b_wmask, .b_long, .b_gnt, .b_done,
        .a_req(1'b0), .a_addr('0), .a_done(),
        .sd_req, .sd_we, .sd_addr, .sd_wdata, .sd_wmask, .sd_long, .sd_done, .sd_rdata, .long_ok,
        .clk_pix(1'b0), .hx(11'd0), .vy(10'd0), .nv_on(), .nv_r(), .nv_g(), .nv_b());
    a816_blit #(.AW(AW)) dut (.clk, .reset_n, .run, .xio_wr, .xio_addr, .xio_wdata, .xio_rdata, .irq, .vbl(1'b0),
        .b_req, .b_gnt, .b_we, .b_addr, .b_wdata, .b_wmask, .b_long, .b_done, .b_rdata(sd_rdata), .long_ok);

    reg [7:0] mem [0:(1<<AW)-1];
    reg [7:0] rf  [0:WIN-1];
    integer lat = 5, seed = 1, i, cpu_rate = 30, nerr = 0;

    // SDRAM model, random latency
    always @(posedge clk) begin
        sd_done <= 0;
        if (sd_req && !sd_done) begin
            if (lat == 0) begin
                sd_done <= 1;
                if (sd_we) begin
                    for (i = 0; i < 4; i++) if (sd_wmask[i]) mem[{sd_addr[AW-1:2], 2'(i)}] <= sd_wdata[i*8 +: 8];
                end else begin
                    if (sd_addr[2:0] != 0 || (sd_long && sd_addr[3:0] != 0)) begin $display("FAIL unaligned burst %h", sd_addr); $finish; end
                    for (i = 0; i < 16; i++) sd_rdata[i*8 +: 8] <= (i < 8 || sd_long) ? mem[sd_addr + i] : 8'hxx;
                end
                lat <= 3 + ($urandom % 10);
            end else lat <= lat - 1;
        end
    end

    // CPU-like client: byte writes to $60:0000-$60:FFFF (checked against a shadow) and 8-byte reads
    reg [7:0] shadow [0:'hFFFF]; reg [15:0] cofs; reg cwe;
    integer cw = 0, cw_b = 0, cwb_max = 0, cw_max = 0, ncpu = 0; reg bcnt = 0;
    always @(posedge clk) begin
        if (run && !c_req && ($urandom % 100) < cpu_rate) begin
            cwe     = $urandom % 2;
            cofs    = $urandom;
            c_req  <= 1;
            c_we   <= cwe;
            c_addr <= 'h600000 + (cwe ? cofs : {cofs[15:3], 3'b000});
            c_wdata <= cofs[7:0] ^ cofs[15:8];
        end else if (c_done) begin
            c_req <= 0; ncpu++;
            if (c_we) shadow[c_addr[15:0]] = c_wdata;
            if (cw > cw_max) cw_max = cw;
            if (cw_b > cwb_max) cwb_max = cw_b;
            cw = 0; cw_b = 0; bcnt = 0;
        end
        if (c_req && !(nvc.busy && nvc.owner == 2'd0)) begin
            cw++;
            if (nvc.busy && nvc.owner == 2'd2 && !bcnt) begin cw_b++; bcnt = 1; end
        end
        if (!(nvc.busy && nvc.owner == 2'd2)) bcnt = 0;
    end

    task automatic wr(input [7:0] a, input [7:0] d);
        @(posedge clk); xio_wr <= 1; xio_addr <= a; xio_wdata <= d;
        @(posedge clk); xio_wr <= 0;
        @(posedge clk);             // a CPU access takes two clks; the blitter takes writes one clk late
    endtask
    task automatic wr16(input [7:0] a, input [15:0] d); wr(a, d[7:0]); wr(a + 1, d[15:8]); endtask
    task automatic wr24(input [7:0] a, input [23:0] d); wr(a, d[7:0]); wr(a + 1, d[15:8]); wr(a + 2, d[23:16]); endtask

    // reference: emu/blitter.c on rf (offsets relative to WBASE)
    function automatic int rofs(input longint a); return int'(a - WBASE); endfunction
    task automatic refblit(input int op, input int fl, input longint src, input int sstr, input longint dst, input int dstr,
                           input int w, input int h, input [7:0] fg, input [7:0] bg, input [7:0] key);
        int back, sb, y, x, bitn; longint s, d; reg [7:0] c;
        back = fl & 1; sb = (fl >> 4) & 7;
        if (op > 4) return;
        for (int yy = 0; yy < h; yy++) begin
            y = back ? h - 1 - yy : yy;
            s = src + y * sstr; d = dst + y * dstr;
            for (int xx = 0; xx < w; xx++) begin
                x = back ? w - 1 - xx : xx;
                case (op)
                    0: rf[rofs(d + x)] = fg;
                    1: rf[rofs(d + x)] = rf[rofs(s + x)];
                    2: begin c = rf[rofs(s + x)]; if (c != key) rf[rofs(d + x)] = c; end
                    default: begin
                        bitn = (7 - sb) + x;
                        c = rf[rofs(s + bitn / 8)];
                        if (c[7 - (bitn & 7)]) rf[rofs(d + x)] = fg;
                        else if (op == 3) rf[rofs(d + x)] = bg;
                    end
                endcase
            end
        end
    endtask

    integer ntest = 3000, t, op, fl, sstr, dstr, w, h, pm, ov, delta, lmode = 2, irqs, ncyc;
    longint src, dst, npx = 0, tcyc = 0;
    reg [7:0] fg, bg, key, v;
    initial begin
        void'($value$plusargs("n=%d", ntest));
        void'($value$plusargs("seed=%d", seed));
        void'($value$plusargs("cpu=%d", cpu_rate));
        void'($value$plusargs("long=%d", lmode));
        void'($urandom(seed));                         // seeds this thread; the others keep their own
        for (i = 0; i < 'h10000; i++) begin shadow[i] = 8'hEE; mem['h600000 + i] = 8'hEE; end
        repeat (3) @(posedge clk); reset_n = 1; run = 1;
        for (t = 0; t < ntest; t++) begin
            long_ok = (lmode == 2) ? $urandom % 2 : lmode;
            op = $urandom % 21; op = (op == 20) ? 5 : op % 5;
            pm = ($urandom % 3 == 0) ? 3 : 255;
            key = $urandom % 4; fg = $urandom; bg = $urandom;
            case ($urandom % 4)
                0: w = 1 + $urandom % 8;
                1: w = 1 + $urandom % 40;
                2: w = 1 + $urandom % 300;
                default: w = ($urandom % 30 == 0) ? 0 : 1 + $urandom % 70;
            endcase
            h = ($urandom % 40 == 0) ? 0 : 1 + $urandom % 6;
            fl = ($urandom % 2) | (($urandom % 8) << 4);
            ov = (op == 1 || op == 2) && ($urandom % 3 == 0);
            if (ov) begin                  // overlapping copy, same stride, direction to suit
                sstr = 1 + $urandom % 300; dstr = sstr;
                delta = int'($urandom % (3 * sstr + 8)) - (3 * sstr + 8) / 2;
                src = WBASE + 'h4000 + $urandom % 'h4000;
                dst = src + delta;
                fl = (fl & ~1) | (delta > 0 ? 1 : 0);
            end else begin
                sstr = $urandom % 400; dstr = $urandom % 400;
                if ($urandom % 8 == 0) dstr = 0;
                src = WBASE + $urandom % 'h6000;
                dst = WBASE + 'h8000 + $urandom % 'h6000;
            end
            for (i = 0; i < WIN; i++) begin v = $urandom & pm; mem[WBASE + i] = v; rf[i] = v; end
            wr24(8'h00, src[23:0]); wr16(8'h03, sstr[15:0]); wr24(8'h05, dst[23:0]); wr16(8'h08, dstr[15:0]);
            wr16(8'h0A, w[15:0]); wr16(8'h0C, h[15:0]); wr(8'h0E, fg); wr(8'h0F, bg); wr(8'h10, key);
            wr(8'h11, op[7:0]); wr(8'h12, fl[7:0]);
            irqs = 0; ncyc = 0;
            wr(8'h13, 8'h03);
            while (dut.busy) begin @(posedge clk); ncyc++; if (irq) irqs++; end
            repeat (2) @(posedge clk); if (irq) irqs++;
            refblit(op, fl, src, sstr, dst, dstr, w, h, fg, bg, key);
            npx += w * h; tcyc += ncyc;
            if (irqs != 1) begin nerr++; $display("FAIL test %0d: %0d interrupts", t, irqs); end
            for (i = 0; i < WIN; i++) if (mem[WBASE + i] !== rf[i]) begin
                nerr++;
                $display("FAIL test %0d op %0d fl %02x src %h sstr %0d dst %h dstr %0d w %0d h %0d long %0d: at %h got %h want %h",
                         t, op, fl, src, sstr, dst, dstr, w, h, long_ok, WBASE + i, mem[WBASE + i], rf[i]);
                break;
            end
            if (nerr > 10) break;
        end
        repeat (40) @(posedge clk);
        for (i = 0; i < 'h10000; i++) if (mem['h600000 + i] !== shadow[i]) begin
            nerr++; $display("FAIL CPU write lost at %h", 'h600000 + i); break;
        end
        $display("%0d blits, %0d pixels, %.2f cycles/pixel; CPU accesses %0d, worst wait %0d cycles, most blitter accesses in one wait %0d",
                 t, npx, real'(tcyc) / real'(npx), ncpu, cw_max, cwb_max);
        if (cwb_max > 1) nerr++;
        if (nerr) $display("FAIL"); else $display("PASS");
        $finish;
    end
endmodule
