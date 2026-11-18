// SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
// Copyright (c) 2026 Carlos Bravo
// Testbench: a816_sys + behavioural SDRAM client model + debug-port consumer.
`timescale 1ns/1ps
module tb_a816;
    localparam AW = 23;
    reg clk = 0; always #17.43 clk = ~clk;
    reg reset_n = 0, run = 0;
    wire sd_req, sd_we; wire [AW-1:0] sd_addr; wire [31:0] sd_wdata; wire [3:0] sd_wmask;
    reg sd_done = 0; reg [127:0] sd_rdata; wire sd_long; wire sv_freeze; wire snd_wr; wire long_ok = sv_freeze;
    wire [7:0] dbg_data; wire dbg_tgl; reg dbg_ack = 0;

    wire [23:0] mb_req_base, mb_rsp_base; wire [7:0] mb_req_head, mb_rsp_tail;
    reg  [7:0]  mb_req_tail_a = 0, mb_rsp_head_a = 0; reg [1:0] mb_status_a = 0;
    wire c_req, c_we, c_done; wire [AW-1:0] c_addr; wire [7:0] c_wdata;
    wire xio_wr, xio_rd; wire [7:0] xio_addr, xio_wdata, xio_rdata; wire irq_vblank, irq_line;
    wire blt_wr, irq_blit; wire [7:0] blt_rdata;
    wire aud_wr, aud_rd, irq_audio; wire [7:0] aud_rdata;
    wire a_req, a_done; wire [AW-1:0] a_addr; wire signed [15:0] out_l, out_r;
    wire b_req, b_gnt, b_we, b_long, b_done; wire [AW-1:0] b_addr; wire [31:0] b_wdata; wire [3:0] b_wmask;
    a816_sys #(.AW(AW), .WDOG_US(20000)) dut (.*, .sys_key(1'b0), .kb_route(), .joy_n_a(10'h3FF), .dbg_ack_tgl(dbg_ack),
        .sd_req(c_req), .sd_we(c_we), .sd_addr(c_addr), .sd_wdata(c_wdata), .sd_done(c_done), .sd_rdata(sd_rdata[63:0]));

    // NVC with a free-running raster like the scandoubler's (1572 x 760, active from line 30)
    reg clk_pix = 0; always #6.9715 clk_pix = ~clk_pix;
    reg [10:0] hx = 0; reg [9:0] vy = 0;
    always @(posedge clk_pix) begin
        hx <= (hx == 1571) ? 11'd0 : hx + 11'd1;
        if (hx == 1571) vy <= (vy == 759) ? 10'd0 : vy + 10'd1;
    end
    wire nv_on; wire [7:0] nv_r, nv_g, nv_b;
    // HDMI audio sample clock: 48 kHz from clk_pix, as in hdmi_audio_out
    reg [13:0] smp_acc = 0; reg smp_tgl = 0;
    always @(posedge clk_pix) begin
        if (smp_acc + 14'd8 >= 14'd11953) begin smp_acc <= smp_acc + 14'd8 - 14'd11953; smp_tgl <= ~smp_tgl; end
        else smp_acc <= smp_acc + 14'd8;
    end
    a816_snd #(.AW(AW)) snd (.clk, .reset_n, .run, .xio_wr(aud_wr), .xio_addr, .xio_wdata,
        .xio_rdata(aud_rdata), .irq(irq_audio), .smp_tgl_a(smp_tgl), .a_req, .a_addr, .a_done,
        .a_rdata(sd_rdata[63:0]), .out_l, .out_r);
    a816_nvc #(.AW(AW)) nvc (.*);
    a816_blit #(.AW(AW)) blit (.clk, .reset_n, .run, .xio_wr(blt_wr), .xio_addr, .xio_wdata, .xio_rdata(blt_rdata),
        .irq(irq_blit), .vbl(irq_vblank), .b_req, .b_gnt, .b_we, .b_addr, .b_wdata, .b_wmask, .b_long, .b_done, .b_rdata(sd_rdata), .long_ok);

    // blitter statistics: cycles per blit (printed for blits of 1024 pixels and more), and the
    // CPU's waits for the port: cycles from its request to the grant, and blitter accesses
    // granted while it waited
    longint bl_t0 = 0; integer bl_px, cw = 0, cw_b = 0, cw_max = 0, cwb_max = 0, cw_max_blt = 0, nbacc = 0, ncacc = 0;
    reg bl_busy_d = 0, bl_seen = 0, bcnt = 0;
    always @(posedge clk) begin
        bl_busy_d <= blit.busy;
        if (blit.busy && !bl_busy_d) begin bl_t0 = ncyc; bl_px = blit.r_w * blit.r_h; bl_seen = 1; end
        if (!blit.busy && bl_busy_d && bl_px >= 1024)
            $display("BLIT op %0d flags %02x %0dx%0d src %06x dst %06x long_ok %0d: %0d cycles, %.2f cycles/pixel",
                     blit.r_op, blit.r_flags, blit.r_w, blit.r_h, blit.r_src, blit.r_dst, long_ok, ncyc - bl_t0,
                     real'(ncyc - bl_t0) / real'(bl_px));
        if (b_gnt) nbacc++;
        if (c_req && !(nvc.busy && nvc.owner == 2'd0)) begin
            cw++;
            if (nvc.busy && nvc.owner == 2'd2 && !bcnt) begin cw_b++; bcnt = 1; end
        end
        if (!(nvc.busy && nvc.owner == 2'd2)) bcnt = 0;
        if (c_done) begin
            ncacc++;
            if (cw > cw_max) cw_max = cw;
            if (cw_b > cwb_max) cwb_max = cw_b;
            if (cw_b > 0 && cw > cw_max_blt) cw_max_blt = cw;
            cw = 0; cw_b = 0; bcnt = 0;
        end
    end
    // sample player: longest time for one output sample (E_IDLE -> FIFO write), lowest FIFO level
    // seen at the HDMI sample clock once primed
    longint sp_t0 = 0, sp_max = 0; integer sp_minf = 9, sp_n = 0, sp_over = 0;
    always @(posedge clk) begin
        if (snd.st == snd.E_V0 && snd.v == 0) sp_t0 = ncyc;
        if (snd.st == snd.E_OUT) begin
            sp_n++; if (ncyc - sp_t0 > sp_max) sp_max = ncyc - sp_t0;
            if (ncyc - sp_t0 > 597) begin
                sp_over++;
                if (sp_over <= 5) $display("sample player: %0d cycles for a sample at clk %0d (fetch line %0d, sprite engine %0d)",
                                           ncyc - sp_t0, ncyc, nvc.trig_n, nvc.e_busy);
            end
        end
        if (snd.tick && snd.primed && snd.cnt < sp_minf) sp_minf = snd.cnt;
    end

    // raster events (REV $09): LINE / VBLANK must come in the horizontal blank (hx 1280-1571)
    // at the end of output line V_TOP - 1 + 2n, n = NV_LINE
    integer nev = 0, nbadev = 0;
    always @(posedge clk) if (irq_line || irq_vblank) begin
        nev++;
        if (hx < 1280 || vy != 10'd29 + 2 * nvc.nv_line || (irq_vblank && nvc.nv_line != 360)) begin
            nbadev++;
            $display("FAIL raster event at hx %0d vy %0d, NV_LINE %0d", hx, vy, nvc.nv_line);
        end
    end

    // ── reference model of Marga's picture (REV $0B): bitmap with scrolling, pointer, sprites ──
    // Kept apart from the RTL on purpose: the scroll and sprite registers are taken from the
    // CPU's register writes (snooped one clk after the bus, as the RTL takes them) and latched
    // here by the rules of the register spec; the line is built at each fetch trigger from
    // memory and compared with the HDMI output pixel by pixel (palette of the moment shown).
    reg [7:0]  m_sh [0:127];               // records as written
    reg [7:0]  m_ac [0:127];               // records in use
    reg        m_cm = 0, m_win = 0;        // COMMIT pending; in the copy window (vertical blank)
    reg [11:0] m_scx_p = 0, m_scx2_p = 0, m_scx_a = 0, m_scx2_a = 0;
    reg [9:0]  m_scy_p = 0, m_scy2_p = 0, m_scy2_a = 0, m_vh_p = 0, m_vh_a = 0, m_rl = 0;
    reg [1:0]  m_sctl_p = 0, m_sctl_a = 0;
    reg [8:0]  m_split = 0;
    reg        m_reg2 = 0;
    reg [23:0] m_row = 0;
    reg [7:0]  m_line [0:1][0:639];        // expected palette index per picture pixel
    reg        m_lv [0:1];                 // that half was modelled
    reg [1:0]  m_lmode [0:1];
    integer    m_novf = 0;                 // sprites the model left out of a line (budget)
    integer    m_nspr = 0, m_nptr = 0, m_nbeh = 0, m_nsl = 0;   // modelled pixels: sprite, pointer, sprite behind; sprite lines
    initial begin for (int q = 0; q < 128; q++) begin m_sh[q] = 0; m_ac[q] = 0; end m_lv[0] = 0; m_lv[1] = 0; end
    always @(posedge clk) begin
        if (!run) begin
            for (int q = 0; q < 128; q++) begin m_sh[q] = 0; m_ac[q] = 0; end
            m_cm = 0; m_scx_p = 0; m_scx2_p = 0; m_scy_p = 0; m_scy2_p = 0; m_vh_p = 0; m_sctl_p = 0;
        end else if (nvc.w_en) begin
            if (nvc.w_a[7]) m_sh[nvc.w_a[6:0]] = nvc.w_d;
            case (nvc.w_a)
                8'h30: m_scx_p[7:0] = nvc.w_d;   8'h31: m_scx_p[11:8] = nvc.w_d[3:0];
                8'h32: m_scy_p[7:0] = nvc.w_d;   8'h33: m_scy_p[9:8] = nvc.w_d[1:0];
                8'h34: m_scx2_p[7:0] = nvc.w_d;  8'h35: m_scx2_p[11:8] = nvc.w_d[3:0];
                8'h36: m_scy2_p[7:0] = nvc.w_d;  8'h37: m_scy2_p[9:8] = nvc.w_d[1:0];
                8'h38: m_vh_p[7:0] = nvc.w_d;    8'h39: m_vh_p[9:8] = nvc.w_d[1:0];
                8'h3A: m_sctl_p = nvc.w_d[1:0];
                8'h41: m_cm = 1;
                default: ;
            endcase
        end
        if (m_cm && m_win) begin for (int q = 0; q < 128; q++) m_ac[q] = m_sh[q]; m_cm = 0; end
        if (nvc.trig) model_line(nvc.trig_n);
    end

    task automatic model_line(input [8:0] n);
        int mode, w, ly, used, b, off, px, hf, sel [0:15];
        reg [8:0] spr [0:639];
        reg [7:0] bm;
        reg [1:0] pc;
        mode = nvc.ctrl[2:1];
        m_win = (n >= 360);
        if (n == 0) begin
            m_scx_a = m_scx_p; m_scx2_a = m_scx2_p; m_scy2_a = m_scy2_p; m_vh_a = m_vh_p; m_sctl_a = m_sctl_p;
            m_split = nvc.line_cmp; m_reg2 = 0;
            m_row = {nvc.base_pend, 8'h00} + m_scy_p * nvc.stride; m_rl = m_scy_p;
        end else if (m_sctl_a[1] && n == m_split) begin
            m_reg2 = 1; m_row = {nvc.base_act, 8'h00} + m_scy2_a * nvc.stride; m_rl = m_scy2_a;
        end else if (mode != 2 || !n[0]) begin
            if (m_vh_a != 0 && m_rl + 10'd1 == m_vh_a) begin m_rl = 0; m_row = {nvc.base_act, 8'h00}; end
            else begin m_rl = m_rl + 10'd1; m_row = m_row + nvc.stride; end
        end
        if (n >= 360) return;
        m_lv[n[0]] = nvc.ctrl[0];
        m_lmode[n[0]] = mode;
        if (!nvc.ctrl[0]) return;
        w  = (mode == 2) ? 320 : 640;
        ly = (mode == 2) ? n / 2 : n;
        // sprites: choose in index order within the width budget, draw from 15 down to 0
        for (int x = 0; x < 640; x++) spr[x] = 0;
        if (nvc.spr_en) begin
            used = 0;
            for (int i = 0; i < 16; i++) begin
                int yy, dy, hd, wd, en;
                yy = $signed({m_ac[8*i+3][1:0], m_ac[8*i+2]});
                en = m_ac[8*i+7][0];
                hd = (16 << m_ac[8*i+7][5]) << m_ac[8*i+7][3];
                wd = (16 << (m_ac[8*i+7][4] & m_ac[8*i+7][6])) << m_ac[8*i+7][3];
                dy = ly - yy;
                sel[i] = 0;
                if (en && dy >= 0 && dy < hd) begin
                    if (used + wd / 16 <= 32) begin sel[i] = 1; used += wd / 16; end
                    else m_novf++;
                end
            end
            if (used != 0) m_nsl++;
            for (int i = 15; i >= 0; i--) if (sel[i]) begin
                int xx, yy, dy, r, hh, ww, mag, b4, wide, rb, img, c;
                reg [7:0] ct, pix, by;
                ct   = m_ac[8*i+7];
                xx   = $signed({m_ac[8*i+1][2:0], m_ac[8*i]});
                yy   = $signed({m_ac[8*i+3][1:0], m_ac[8*i+2]});
                mag  = ct[3]; b4 = ct[6]; wide = ct[4] & ct[6];
                hh   = 16 << ct[5]; ww = 16 << wide;
                img  = {m_ac[8*i+6], m_ac[8*i+5], m_ac[8*i+4][7:4], 4'h0};
                dy   = ly - yy; r = dy >> mag; if (ct[2]) r = hh - 1 - r;
                rb   = b4 ? (wide ? 16 : 8) : 16;
                for (int d = 0; d < (ww << mag); d++) begin
                    int j;
                    j = d >> mag; if (ct[1]) j = ww - 1 - j;
                    if (b4) begin
                        by  = mem[(img + r * rb + j / 2) & ((1 << AW) - 1)];
                        pix = (j & 1) ? by[3:0] : by[7:4];
                        if (pix != 0) pix = {m_ac[8*i+4][3:0], pix[3:0]};
                    end else pix = mem[(img + r * rb + j) & ((1 << AW) - 1)];
                    c = xx + d;
                    if (pix != 0 && c >= 0 && c < w) spr[c] = {ct[7], pix};
                end
            end
        end
        // bitmap, pointer and the merge
        for (int x = 0; x < w; x++) begin
            int dx;
            px  = (m_reg2 ? m_scx2_a : m_scx_a) + x;
            b   = (mode == 1) ? px / 2 : px;
            off = (m_sctl_a[0] && nvc.stride != 0) ? b % nvc.stride : b;
            bm  = mem[(m_row + off) & ((1 << AW) - 1)];
            if (mode == 1) bm = (px & 1) ? {4'd0, bm[3:0]} : {4'd0, bm[7:4]};
            pc = 0;
            if (nvc.ptr_hit) begin
                dx = x - $signed({1'b0, nvc.ptr_x} - {6'd0, nvc.ptr_hot[3:0], 1'b0});
                if (dx >= 0 && dx < 32)
                    pc = mem[(({nvc.ptr_img[23:3], 3'b000} + nvc.ptr_dy[4:0] * 8) + dx / 4) & ((1 << AW) - 1)] >> (6 - 2 * (dx % 4));
            end
            if (pc != 0) begin m_line[n[0]][x] = (mode == 1) ? {4'd0, nvc.ptr_c[pc][3:0]} : nvc.ptr_c[pc]; m_nptr++; end
            else if (spr[x][7:0] != 0 && !(spr[x][8] && bm != 0)) begin m_line[n[0]][x] = spr[x][7:0]; m_nspr++; if (spr[x][8]) m_nbeh++; end
            else m_line[n[0]][x] = bm;
        end
    endtask

    // sprite engine: cycles from the fetch trigger until all of the line is drawn
    longint se_t0 = 0, se_max = 0; reg se_on = 0; integer se_n = 0;
    always @(posedge clk) begin
        if (nvc.trig) begin se_t0 = ncyc; se_on = nvc.enable && nvc.spr_en && nvc.trig_n < 360; end
        else if (se_on && !nvc.e_busy && !nvc.ev_run) begin
            se_on = 0; se_n++;
            if (ncyc - se_t0 > se_max) se_max = ncyc - se_t0;
        end
    end

    // check every desktop pixel against the model, and dump frames (+ppm)
    reg [10:0] hx1, hx2; reg [9:0] vy1, vy2; integer npix = 0, nbadpix = 0, nframe = 0, ppm = 0;
    reg [23:0] expc; reg [7:0] eidx; integer ln, lx; bit dumpppm = 0;
    bit dumpppm2 = 0;
    initial begin dumpppm = $test$plusargs("ppm"); dumpppm2 = $test$plusargs("ppm2"); end
    always @(posedge clk_pix) begin
        hx1 <= hx; hx2 <= hx1; vy1 <= vy; vy2 <= vy1;
        if (hx2 == 0 && vy2 == 0) begin
            if (ppm) begin $fclose(ppm); ppm = 0; end
            if (nv_on) begin
                nframe++;
                // +ppm: every frame to nv_frameN.ppm; +ppm2: alternately to nv_frame0/1.ppm
                if (nframe >= 2 && (dumpppm || dumpppm2)) begin
                    ppm = $fopen($sformatf("nv_frame%0d.ppm", dumpppm2 ? nframe % 2 : nframe), "wb");
                    $fwrite(ppm, "P6\n1280 720\n255\n");
                end
            end
        end
        if (nv_on && nframe >= 2 && hx2 < 1280 && vy2 >= 30 && vy2 < 750) begin
            if (ppm) $fwrite(ppm, "%c%c%c", nv_r, nv_g, nv_b);
            ln = (vy2 - 30) >> 1;
            if (m_lv[ln & 1] && m_lmode[ln & 1] == nvc.ctrl_p2[2:1]) begin
                lx   = (m_lmode[ln & 1] == 2) ? hx2 >> 2 : hx2 >> 1;
                eidx = m_line[ln & 1][lx];
                expc = nvc.pal[eidx];
                npix++;
                if ({nv_r, nv_g, nv_b} !== expc) begin
                    nbadpix++;
                    if (nbadpix < 10) $display("NVC bad pixel x%0d y%0d got %h want %h (index %02x)", hx2, vy2 - 30, {nv_r, nv_g, nv_b}, expc, eidx);
                end
            end
        end
    end

    reg [7:0] mem [0:(1<<AW)-1];
    integer fd, n, i, seed = 1, lat, lat_v, nfill = 0, nwr = 0, fixlat = 0, tmo_ms = 400;
    reg req_d = 0;
    longint ncyc = 0, nce = 0;
    string line = "", all = "", prog = "a816_sim.bin", exp_s = "";
    bit bad;

    // SDRAM model: random latency 6..13 cycles (single ~6 clk_core, burst ~8, plus contention).
    // +fixlat: 6 cycles for a write, 7 for an 8-byte and 9 for a 16-byte burst, about what the
    // controller takes with no Atari traffic (for speed measurements).
    always @(posedge clk) begin
        sd_done <= 0;
        req_d <= sd_req;
        if (sd_req && !sd_done) begin
            lat_v = (fixlat && !req_d) ? (sd_we ? 5 : sd_long ? 8 : 6) : lat;
            if (lat_v == 0) begin
                sd_done <= 1;
                if (sd_we) begin
                    for (i = 0; i < 4; i++) if (sd_wmask[i]) mem[{sd_addr[AW-1:2], 2'(i)}] <= sd_wdata[i*8 +: 8];
                    nwr++;
                end
                else begin
                    if (sd_addr[2:0] != 0) begin $display("FAIL unaligned burst %h", sd_addr); $finish; end
                    if (sd_long && sd_addr[3:0] != 0) begin $display("FAIL unaligned long burst %h", sd_addr); $finish; end
                    for (i = 0; i < 16; i++) sd_rdata[i*8 +: 8] <= (i < 8 || sd_long) ? mem[sd_addr + i] : 8'hxx;
                    nfill++;
                end
                lat <= 6 + ($urandom(seed) % 8);
            end else lat <= lat_v - 1;
        end
        if (dut.cpu_rst_n) begin ncyc++; if (dut.cpu_ce) nce++; end
    end

    // I/O processor model: just enough of the mailbox for the self test (one fake file)
    reg [7:0] file [0:1023]; integer flen = 0, fexists = 0, k;
    reg [7:0] m [0:15]; reg [31:0] mres, mval; reg [23:0] mbuf, marg0; reg [15:0] mlen;
    always @(posedge clk) begin
        if (mb_req_base == 0 || mb_rsp_base == 0) begin mb_status_a <= 0; mb_req_tail_a <= 0; mb_rsp_head_a <= 0; end
        else if (!mb_status_a[0]) mb_status_a <= 1;
        else if (mb_req_head != mb_req_tail_a) begin
            repeat (300) @(posedge clk);
            for (k = 0; k < 16; k++) m[k] = mem[mb_req_base + mb_req_tail_a * 16 + k];
            mlen = {m[3], m[2]}; mbuf = {m[6], m[5], m[4]}; marg0 = {m[10], m[9], m[8]};
            mres = 0; mval = 0;
            case (m[0])
                8'h01: if (m[7] == 2) begin fexists = 1; flen = 0; end else if (!fexists) mres = 4;
                8'h04: begin for (k = 0; k < mlen; k++) file[k] = mem[mbuf + k]; flen = mlen; mval = mlen; end
                8'h03: begin mval = (mlen < flen) ? mlen : flen; for (k = 0; k < mval; k++) mem[mbuf + k] = file[k]; end
                8'h02: ;
                8'h06: if (!fexists) mres = 4; else begin mem[mbuf] = flen[7:0]; mem[mbuf+1] = flen[15:8]; mem[mbuf+2] = 0; mem[mbuf+3] = 0; end
                8'h09: fexists = 0;
                8'h10: begin for (k = 0; k < 256; k++) mem[marg0 + k] = mem['h10000 + k]; mval = 256; end
                8'h07: mval = 5;
                default: mres = 'h82;
            endcase
            m[0] = m[0] | 8'h80;
            {m[11], m[10], m[9], m[8]} = mres; {m[15], m[14], m[13], m[12]} = mval;
            for (k = 0; k < 16; k++) mem[mb_rsp_base + mb_rsp_head_a * 16 + k] = m[k];
            repeat (50) @(posedge clk);
            mb_rsp_head_a <= mb_rsp_head_a + 1; mb_req_tail_a <= mb_req_tail_a + 1;
            @(posedge clk);
        end
    end

    // +trace: one line per CPU cycle
    bit trace = 0; integer tn = 0;
    initial trace = $test$plusargs("trace");
    always @(posedge clk) if (trace && dut.cpu_step) begin
        $display("%s%s %06x %s %02x  st%0d ir%02x u%0d ab%0d c%02x", dut.cpu_vpa ? "P" : "-", dut.cpu_vda ? "D" : "-", dut.cpu_a,
                 dut.cpu_we_n ? "r" : "W", dut.cpu_we_n ? dut.cpu_di : dut.cpu_do, dut.cpu.STATE, dut.cpu.IR,
                 dut.user_eff, !dut.abort_n, dut.abort_cause);
    end

    // debug consumer (slow, like the firmware poll)
    always @(posedge clk) if (dbg_tgl != dbg_ack) begin
        repeat (20 + $urandom(seed) % 40) @(posedge clk);
        if (dbg_data == 10) begin $display("816> %s", line); all = {all, line, "|"}; line = ""; end
        else line = {line, string'(dbg_data)};
        dbg_ack <= dbg_tgl;
        if (all.len() > 5 && all.substr(all.len()-5, all.len()-1) == "DONE|") begin
            $display("cpu cycles %0d, clk %0d (%.2f clk/cycle), line fills %0d, writes %0d",
                     nce, ncyc, real'(ncyc)/real'(nce), nfill, nwr);
            bad = 0;
            for (i = 0; i + 4 <= all.len(); i++) if (all.substr(i, i+3) == "FAIL") bad = 1;
            exp_s = $sformatf("ATARI816 BRING-UP 1|ID 81 REV %02x BANKS-1 7F|RAM ERRORS 0000|", dut.REV);
            if (prog == "bringup1_sim.bin" &&     // the REV printed must be the core's current one (%x is lower case)
                all.substr(0, exp_s.len() - 1).toupper() != exp_s.toupper()) bad = 1;
            if (npix != 0) $display("NVC pixels checked %0d, bad %0d, late %0d", npix, nbadpix, nvc.late);
            if (m_nsl != 0) $display("model: %0d lines with sprites, %0d sprite pixels (%0d BEHIND), %0d pointer pixels, %0d sprites left out by the budget",
                                     m_nsl, m_nspr, m_nbeh, m_nptr, m_novf);
            if (se_n != 0) $display("sprite engine: %0d lines, longest %0d cycles from the fetch trigger (1257 available), SPR_STATUS %0d",
                                    se_n, se_max, {nvc.spr_late, nvc.spr_ovf});
            $display("raster events %0d, misplaced %0d", nev, nbadev);
            if (dumpppm2) $display("last complete frame: nv_frame%0d.ppm (frame %0d)", (nframe - 1) % 2, nframe - 1);
            if (sp_n > 0) $display("sample player: %0d samples, longest %0d cycles per sample (597 available, %0d took longer), lowest FIFO level %0d, AU_LATE %0d",
                                   sp_n, sp_max, sp_over, sp_minf, snd.late);
            if (nbadev != 0) bad = 1;
            if (bl_seen) $display("blitter accesses %0d; CPU accesses %0d, worst wait %0d cycles, worst wait with a blitter access %0d cycles, most blitter accesses in one wait %0d",
                                  nbacc, ncacc, cw_max, cw_max_blt, cwb_max);
            if (cwb_max > 1) bad = 1;
            if (nbadpix != 0 || (prog == "nvtest_sim.bin" && npix < 900000)) bad = 1;
            if (bad) $display("FAIL output: %s", all); else $display("PASS");
            $finish;
        end
    end

    initial begin
        lat = 7;
        for (i = 0; i < (1<<AW); i++) mem[i] = 8'hEA ^ i[7:0];      // junk, not zero
        // reset stub: CLC, XCE, JML $010000 at $00:FF00; all vectors -> STP at $FF10
        mem['hFF00] = 8'h18; mem['hFF01] = 8'hFB; mem['hFF02] = 8'h5C;
        mem['hFF03] = 8'h00; mem['hFF04] = 8'h00; mem['hFF05] = 8'h01;
        mem['hFF10] = 8'hDB;
        for (i = 'hFFE0; i < 'h10000; i += 2) begin mem[i] = 8'h10; mem[i+1] = 8'hFF; end
        mem['hFFFC] = 8'h00;
        void'($value$plusargs("prog=%s", prog));
        fixlat = $test$plusargs("fixlat");
        fd = $fopen({"../sw/a816/", prog}, "rb");
        if (fd == 0) begin $display("no program"); $finish; end
        n = $fread(mem, fd, 'h10000, 'h8000);
        $display("loaded %0d bytes", n);
        repeat (5) @(posedge clk); reset_n = 1;
        repeat (700) @(posedge clk); run = 1;
        if (prog == "BLITTEST.BIN") tmo_ms = 20000;   // every blitter op against the CPU: ~10 s simulated
        if (prog == "blitlist_sim.bin") tmo_ms = 3000;  // the SPEED part runs past 400 ms
        void'($value$plusargs("timeout_ms=%d", tmo_ms));
        #(longint'(tmo_ms) * 1_000_000) $display("FAIL timeout: %s / %s", all, line); $finish;
    end
endmodule
