// SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
// Copyright (c) 2026 Carlos Bravo
// Atari 800 — Tang Nano 20K top-level
// HDMI: Open-source unencrypted hdmi_audio_out transmitter.
// Clocks: 54 MHz core (rpll_54m); 371.25 MHz HDMI 5x; 74.25 MHz HDMI pixel; 12 MHz USB.
// cycle_length=32 at 54 MHz → 32 SDRAM cycles per Atari bus cycle (budget fix for video garble).
// Atari CPU speed stays 54/32 = 1.6875 MHz (same as 27/16). SDRC state machine runs 2× faster
// in wall time so transactions complete within the 32-cycle window (shared_enable.vhdl only works
// with power-of-2 cycle_lengths; 30 triggers an index-out-of-range error).

module tang_top (
    input  wire        sys_clk,       // 27 MHz onboard oscillator

    // Buttons (active HIGH, PULL_MODE=DOWN): S1 = reset, S2 = read by the firmware (no menu now)
    // btn_n[x] = 0 when unpressed (pulled low), 1 when pressed (drives VCC)
    input  wire [1:0]  btn_n,

    // HDMI TMDS — driven by ELVDS_OBUF inside hdmi_out
    output wire [2:0]  tmds_p,
    output wire [2:0]  tmds_n,
    output wire        tmds_clk_p,
    output wire        tmds_clk_n,

    // SD card (SPI mode)
    output wire        sd_clk,
    output wire        sd_mosi,
    input  wire        sd_miso,
    output wire        sd_cs,

    // USB HID host (low-speed USB keyboard/mouse/gamepad)
    inout  wire        usb_dm,        // D- — pin 49 (IOR49A); 15 kΩ to GND
    inout  wire        usb_dp,        // D+ — pin 51 (IOR45A); 15 kΩ to GND

    // Joystick ports (Atari DB9 pinout, active low)
    input  wire [4:0]  joy1_n,
    input  wire [4:0]  joy2_n,

    // (Analog GPIO audio removed — pins 25/26 reused for Joystick 1 L/R. HDMI audio
    // is unaffected; audio_l_out/audio_r_out below still feed the HDMI audio islands.)

    // Status LEDs (active low on Tang Nano 20K) — pins 17-20 only.
    // Pins 15/16 (leds_n[5]/[0] on schematic) are LPLL2 feedback pads; never drive them.
    output wire [4:1]  leds_n,

    // Onboard SPI Flash (as user GPIO for PicoRV32)
    output wire        flash_spi_cs_n,
    input  wire        flash_spi_miso,
    output wire        flash_spi_mosi,
    output wire        flash_spi_clk,
    output wire        flash_spi_wp_n,
    output wire        flash_spi_hold_n,

    // BL616 UART bridge (PC serial over the onboard USB-C; BL616 CDC <-> UART)
    input  wire        bl616_uart_rx,  // pin 70 (BL616 -> FPGA), per SNESTang
    output wire        bl616_uart_tx,  // pin 69 (FPGA -> BL616); idles high (mark)

    // Embedded SDRAM (GW2AR-18 on-chip)
    output wire        O_sdram_clk,
    output wire        O_sdram_cke,
    output wire        O_sdram_cs_n,
    output wire        O_sdram_ras_n,
    output wire        O_sdram_cas_n,
    output wire        O_sdram_wen_n,
    output wire [1:0]  O_sdram_ba,
    output wire [10:0] O_sdram_addr,
    output wire [3:0]  O_sdram_dqm,
    inout  wire [31:0] IO_sdram_dq
);

// Explicitly disable the Global Set/Reset (GSR) network to prevent auto-inference
// and avoid routing/reset loops on the custom startup delay circuit.
GSR GSR_INST (.GSRI(1'b1));

// ── Clocks & reset ─────────────────────────────────────────────────────────
// Phase A "720-line" genlocked scandoubler, FREQUENCY-LOCKED: HDMI pixel = 2*clk_core =
// 57.375 MHz, derived (like clk_core) from clk_108m so the output is locked to the Atari frame
// (custom 1216x786 = 955776 = 2*477888 pixel cycles = exactly one Atari frame at the 2x pixel
// rate -> integer lines -> no jitter; active 1056x720 = integer 3x of the Atari 352x240 frame).
// clk_5x = 5x pixel = 286.875 MHz from rpll_287m, CASCADED off clk_108m (×5/2).
wire clk_5x;               // 286.875 MHz — HDMI OSER10 5x clock
wire clk_pix;              // 57.375 MHz  — HDMI pixel clock (286.875 ÷ 5 = 2*clk_core)
wire clk_usb;              // 12 MHz     — USB HID host (rpll_108m CLKOUTD ÷18)
wire clk_108m;             // 114.75 MHz — intermediate (rpll_108m CLKOUT)
wire clk_core;             // 28.6875 MHz — Atari core (clk_108m ÷ 4; cl=16 → 1.7898 MHz exact NTSC)
wire clk_mem;              // 57.375 MHz — SDRAM controller (clk_108m ÷ 2; 2:1 synchronous w/ clk_core)
wire pll_locked, pll_core_locked;

// Phase A: HDMI serializer clock 286.875 MHz, CASCADED off clk_108m (114.75 × 5/2) so the
// pixel clock (286.875/5 = 57.375 = 2*clk_core) is frequency-locked to the Atari frame.
// clk_108m is driven by rpll_108m below (structural — instantiation order is irrelevant).
rpll_287m pll (
    .clk_in  (clk_108m),
    .clk_287m(clk_5x),
    .locked  (pll_locked)
);

// rpll_108m replaces both rpll_12m and rpll_54m within the 2-PLL device limit:
// CLKOUT=216 MHz feeds CLKDIV÷4 → clk_core=54 MHz; CLKOUTD(÷18)=12 MHz → clk_usb.
rpll_108m pll_core_inst (
    .clk_in  (sys_clk),
    .clk_108m(clk_108m),
    .clk_12m (clk_usb),
    .locked  (pll_core_locked)
);

// clk_core = 216 ÷ 4 = 54 MHz (Atari machine speed 54/32 = 1.6875 MHz).
// (The 43.2 MHz ÷5 was only a Stage-1 reliability test; timing was never the bug —
// the deadlock was rv_rdata corruption + SDRAM contention, now fixed otherwise.)
//
// CRITICAL: both CLKDIVs must be released on the SAME clk_108m edge. pll_core_locked is
// asynchronous; if each divider samples the release on a different edge, the clk_core↔
// clk_mem phase flips for the whole power-on session, halving the SDRAM-crossing transfer
// window (17.4 → 8.7 ns) and producing the per-boot "green ghost" lottery (stable pixel
// corruption whose probability/severity depends on per-build routing). Synchronising the
// release makes the phase deterministic and aligned — matching the generated-clock SDC
// model so P&R actually closes the crossing.
// Phase experiment results (2026-06-10): same-edge release = Atari boots (crossing meets
// timing; this is the phase the generated-clock SDC models). +1-cycle offset on the core
// divider = opposite phase, 8.7 ns crossing window → ROM load corrupted, no boot. So the
// same-edge release below is REQUIRED; do not skew the two RESETNs.
reg [1:0] clkdiv_rstn_sync = 2'b00;
always @(posedge clk_108m or negedge pll_core_locked) begin
    if (!pll_core_locked) clkdiv_rstn_sync <= 2'b00;
    else                  clkdiv_rstn_sync <= {clkdiv_rstn_sync[0], 1'b1};
end
wire clkdiv_rstn_mem  = clkdiv_rstn_sync[1];
wire clkdiv_rstn_core = clkdiv_rstn_sync[1];   // SAME edge as mem — required phase

CLKDIV #(
    .DIV_MODE ("4"),
    .GSREN    ("false")
) clkdiv_core (
    .CLKOUT (clk_core),
    .HCLKIN (clk_108m),
    .RESETN (clkdiv_rstn_core),
    .CALIB  (1'b1)
);

// clk_mem = 114.75 ÷ 2 = 57.375 MHz — SDRAM controller clock (Path B). 2:1 synchronous with
// clk_core (both divide clk_108m), so the SDRAM↔arbiter crossing is related-clock, not async.
CLKDIV #(
    .DIV_MODE ("2"),
    .GSREN    ("false")
) clkdiv_mem (
    .CLKOUT (clk_mem),
    .HCLKIN (clk_108m),
    .RESETN (clkdiv_rstn_mem),
    .CALIB  (1'b1)
);

// Power-on reset timer: guaranteed to release after 1.2 ms (32768 / 27 MHz)
// S1 (btn_n[0]) is active-HIGH: pressing it drives pin HIGH, which restarts the timer.
// hw_reset_n stays low while the timer hasn't expired (power-on) OR while S1 is pressed.
reg [15:0] rst_timer = 16'd0;
wire       timer_done = rst_timer[15];
always_ff @(posedge sys_clk) begin
    if (btn_n[0]) begin          // S1 pressed → hold reset (timer held at 0)
        rst_timer <= 16'd0;
    end else if (!timer_done) begin
        rst_timer <= rst_timer + 16'd1;
    end
end

// hw_reset_n: released after power-on delay, PLLs locked, and S1 not pressed.
wire hw_reset_n  = timer_done && !btn_n[0] && pll_core_locked;
wire usb_host_enable;   // iosys register bit; unused since the USB-HID host was removed
wire joystick_mode;   // OSD-toggled: arrow keys → Joystick 1, Left-Alt = fire, arrows suppressed from kbd

// hdmi_rst_n: gate HDMI logic on PLL lock so OSER10 RESET is held until clk_pix is stable.
wire hdmi_rst_n = hw_reset_n && pll_locked;

// 371.25 MHz ÷ 5 = 74.25 MHz HDMI pixel clock.
// Hold CLKDIV in reset until PLL locks and system reset is released so clk_pix starts cleanly with stable FCLK in sync with OSER10.
CLKDIV #(
    .DIV_MODE ("5"),
    .GSREN    ("false")
) clkdiv_hdmi (
    .CLKOUT (clk_pix),
    .HCLKIN (clk_5x),
    .RESETN (hdmi_rst_n),
    .CALIB  (1'b1)
);

// Core reset held until ROMs are loaded by PicoRV32.
reg roms_loaded = 1'b0;
reg rom_loading_r = 1'b0;
wire rom_loading;

always_ff @(posedge sys_clk or negedge hw_reset_n) begin
    if (!hw_reset_n) begin
        roms_loaded   <= 1'b0;
        rom_loading_r <= 1'b0;
    end else begin
        rom_loading_r <= rom_loading;
        if (rom_loading) begin
            roms_loaded <= 1'b0;
        end else if (rom_loading_r && !rom_loading) begin
            roms_loaded <= 1'b1;
        end
    end
end

// Core reset release synchroniser (INVESTIGATE #21 root-cause candidate). roms_loaded is a
// sys_clk register; using it directly as the core's asynchronous RESET_N releases the 6502
// at an arbitrary point of a clk_core cycle. Assert asynchronously, release synchronously:
// two flops on clk_core, so every process in the core leaves reset on the same edge.
wire core_reset_n_raw = hw_reset_n && roms_loaded;
reg  core_rst_s1 = 1'b0, core_rst_s2 = 1'b0;
always_ff @(posedge clk_core or negedge core_reset_n_raw) begin
    if (!core_reset_n_raw) begin
        core_rst_s1 <= 1'b0;
        core_rst_s2 <= 1'b0;
    end else begin
        core_rst_s1 <= 1'b1;
        core_rst_s2 <= core_rst_s1;
    end
end
wire core_reset_n = core_rst_s2;
wire dbg_sd_ready;

// ── Keyboard ───────────────────────────────────────────────────────────────
wire [5:0]  keyboard_scan;
wire [1:0]  keyboard_response;
wire        consol_start;
wire        consol_select;
wire        consol_option;

// ── Video ──────────────────────────────────────────────────────────────────
wire        video_vs, video_hs;
wire [7:0]  video_r, video_g, video_b;
wire        video_blank;
wire        video_pixce;
wire        video_sof;        // VIDEO_START_OF_FIELD — genlock marker for the scandoubler


// ── Audio ──────────────────────────────────────────────────────────────────
wire [15:0] audio_l_pcm, audio_r_pcm;
// HDMI audio = classic mix + 16384 + Atari816 sample player (Lau) + OPL2 (YM3812), saturated.
// The classic mix sits at -32768 when silent (POKEY only reaches about 0), so it is moved up by
// a quarter of the range to leave room for Lau and OPL2.
wire signed [15:0] snd_l, snd_r;         // sample player (a816_snd)
wire signed [15:0] opl_snd;              // OPL2 FM synth (a816_opl)
wire               hdmi_smp_tgl;         // HDMI audio sample clock (toggle, clk_pix)
function automatic [15:0] mix_sat(input [15:0] cl, input signed [15:0] nv, input signed [15:0] fm);
    reg signed [18:0] t;
    // (the OPL2 times 3: one FM voice peaks at an eighth of full scale; MIDI songs were
    // 6 to 15 dB below MODs)
    t = $signed({{3{cl[15]}}, cl}) + 19'sd16384 + {{3{nv[15]}}, nv} + {{3{fm[15]}}, fm}
        + {{2{fm[15]}}, fm, 1'b0};
    mix_sat = (t > 19'sd32767) ? 16'h7FFF : (t < -19'sd32768) ? 16'h8000 : t[15:0];
endfunction
// Build switch: the sample player (a816_snd) is in the default build (bring-up log, step 17).
// Define A816_NO_SAMPLER to leave it out (REV $09, about 1,000 cells less). REV $0C adds OPL2,
// REV $0D the blitter's colour remap (a816_blit.sv: TABLE, COPY_REMAP, COPY_KEY_REMAP; it is in
// both builds, the NO_SAMPLER one still reports $09).
// `define A816_NO_SAMPLER
`ifndef A816_NO_SAMPLER
localparam logic [7:0] A816_REV = 8'h0D;
reg  [15:0] audio_l_out = 16'h0000, audio_r_out = 16'h0000;   // feed HDMI audio
// The HDMI transmitter samples these 16-bit words in clk_pix. They change only just after it
// has taken a sample (a few clk_core after hdmi_smp_tgl toggles), so it never catches a word
// half changed: the OPL2 and POKEY change at any time, and a torn word is a click.
reg  [2:0]  smp_s = 3'd0;
always @(posedge clk_core) begin
    smp_s <= {smp_s[1:0], hdmi_smp_tgl};
    if (smp_s[2] ^ smp_s[1]) begin
        audio_l_out <= mix_sat(audio_l_pcm, snd_l, opl_snd);
        audio_r_out <= mix_sat(audio_r_pcm, snd_r, opl_snd);
    end
end
`else
localparam logic [7:0] A816_REV = 8'h09;
wire [15:0] audio_l_out = audio_l_pcm, audio_r_out = audio_r_pcm;
`endif

// ── SIO — stubbed until Stage 6 ───────────────────────────────────────────
wire sio_command, sio_txd, sio_motor;

// ── SDRAM logical bus from Atari core ─────────────────────────────────────
wire        core_sdram_req;
wire        core_sdram_req_complete;
wire        core_sdram_read_en;
wire        core_sdram_write_en;
wire [24:0] core_sdram_addr;
wire [31:0] core_sdram_data_to_core;
wire [31:0] core_sdram_data_from_core;
wire        core_sdram_32bit_we;
wire        core_sdram_16bit_we;
wire        core_sdram_8bit_we;
wire        core_sdram_refresh;

// PicoRV32 client wires
wire        rv_valid;
wire        rv_ready;
wire [22:0] rv_addr;
wire [31:0] rv_wdata;
wire [3:0]  rv_wstrb;
wire [31:0] rv_rdata;
wire        sdram_ready;

// ── Frame buffer REMOVED (2026-06-19) ────────────────────────────────────────
// Video is now the genlocked scandoubler line buffer (no SDRAM). The SDRAM
// frame-buffer writer/reader and their two arbiter clients have been removed, so
// the Atari core and PicoRV32 are the only SDRAM clients (freeing the video
// write+read bandwidth the dead clients were still consuming).
wire [255:0] sdram_burst_dout;     // controller burst output (no burst clients now)

// 2-client SDRAM owner encoding (strict priority Atari > PicoRV32).
localparam [1:0] OWN_ATARI = 2'd0, OWN_RV = 2'd1, OWN_A816 = 2'd2;

// ── Atari816: 65C816 SDRAM client (lowest priority: Atari > PicoRV32 > 65C816) ──
wire        a816_req;            // level, held until a816_done
wire        a816_we;             // 1 = 32-bit word write with a816_wmask, 0 = burst read (8 bytes)
wire [22:0] a816_addr;           // native RAM address (8 MB)
wire [31:0] a816_wdata;          // CPU byte writes come replicated with a one-byte mask
wire [3:0]  a816_wmask;
wire        a816_long;           // with a burst read: 16 bytes (NVC, classic machine frozen)
wire        a816_sv_freeze;      // 1 = classic machine frozen by Horizon (SV_CTRL)
wire        a816_snd_wr;         // native sound register write ($00:DB00-$DB1F; REV $0C: only $DB00-$DB0F do anything)
// Registered copy for POKEY's native bank (REV $0C; POKEY 2 and the DACs before): the write
// reaches it one clk_core later. Without this register the 65C816's microcode -> RDY_OUT ->
// io_wr -> POKEY -> MMU -> 6502 chain was the clk_core critical path (34.8 ns of 34.86).
reg         a816_snd_wr_r = 1'b0;
reg  [4:0]  a816_snd_addr_r = 5'd0;
reg  [7:0]  a816_snd_data_r = 8'd0;
// Native -> physical: address bits 21:20 are inverted, so native $00:0000-$0F:FFFF is
// physical 0x300000-0x3FFFFF (free), which the I/O processor sees at 0x100000. The rest of
// the 8 MB follows from that:
//   native $10-$1F  physical 0x200000  I/O processor (cold firmware in native bank $11)
//   native $20-$3F  physical 0x000000  classic machine: RAM, extended RAM, OS and BASIC
//   native $40-$7F  physical 0x400000-0x7FFFFF in swapped 1 MB blocks ($70 = 0x400000):
//                   cartridge images
wire [24:0] a816_physical_addr = {2'b00, a816_addr[22], ~a816_addr[21:20], a816_addr[19:0]};

// ── PicoRV32 ↔ SDRAM arbiter CDC ─────────────────────────────────────────────
// iosys_picorv32 stays on sys_clk (27 MHz) so its firmware-compiled SPI timing
// (SD card init ≤400 kHz) is preserved.  The SDRAM arbiter runs at clk_core
// (54 MHz) alongside the Atari core and SDRAM IP.
//
// rv_valid (27 MHz → 54 MHz): level, held until acked — 2-FF synchronizer.
reg [1:0] rv_valid_sync_r = 2'b00;
always_ff @(posedge clk_core or negedge hw_reset_n) begin
    if (!hw_reset_n) rv_valid_sync_r <= 2'b00;
    else             rv_valid_sync_r <= {rv_valid_sync_r[0], rv_valid};
end
wire rv_valid_core = rv_valid_sync_r[1];

// rv_ready (54 MHz → 27 MHz): 1-cycle clk_core pulse — toggle synchronizer.
// Toggle rv_done_toggle_r once per completed PicoRV32 transaction.  A 3-stage
// sync chain in sys_clk domain plus XOR edge-detect produces a reliable
// 1-cycle sys_clk rv_ready pulse.
reg       rv_done_toggle_r  = 1'b0;
reg [2:0] rv_done_sys_r     = 3'b000;
wire      rv_ready_sync     = rv_done_sys_r[2] ^ rv_done_sys_r[1];

// rv_hold: prevents phantom transactions.  After a PicoRV32 transaction
// completes, the arbiter must not launch another one until rv_valid_core
// deasserts (i.e. until PicoRV32 has acknowledged rv_ready and the
// deassert has propagated through the 2-FF sync).  Without this, the arbiter
// re-launches in the very next clk_core cycle, producing extra toggles that
// corrupt the toggle-sync and leave PicoRV32 with 0 or 2 rv_ready pulses.
reg rv_hold = 1'b0;

// PicoRV32 SDRAM requests are ungated: the firmware runs entirely from BSRAM, so
// its SDRAM traffic is rare and explicit (ROM loads — with the core in reset — and
// the occasional COLDST poke). The arbiter's strict Atari-first priority protects
// the bus. The historical overlay/wake-latch gating (from the firmware-in-SDRAM
// era, when fetches contended with ANTIC) is gone — and so is HALT-on-menu: the
// menu is now a pure pixel overlay over the live, running Atari (see .HALT below).
wire rv_req = rv_valid_core && !rv_hold;

// ── Dual-Client SDRAM Arbiter & Adapter ──────────────────────────────────────
wire        sdram_complete;
reg         sdram_complete_r = 1'b0;
reg  [1:0]  sdram_owner = OWN_ATARI; // OWN_ATARI / OWN_RV

assign sdram_complete = sdram_complete_r;
assign core_sdram_req_complete = sdram_complete && (sdram_owner == OWN_ATARI);
assign rv_ready                = rv_ready_sync;

wire [31:0] sdram_rd_data_wire;
wire        sdram_ready_wire;

assign core_sdram_data_to_core = sdram_rd_data_wire >> {core_sdram_addr[1:0], 3'b000};
// rv_rdata reads from a latch captured at PicoRV32 transaction completion (see the
// SA_BUSY completion block) so Atari reads can't overwrite it before the CPU samples it.
reg [31:0] rv_rdata_hold = 32'd0;
assign rv_rdata                = rv_rdata_hold;
assign sdram_ready             = sdram_ready_wire;

// Address translation for PicoRV32: Virtual-to-Physical Bank mapping
// Virtual Bank 0 (0x000000-0x1FFFFF) -> Physical Bank 1
// Virtual Bank 1 (0x200000-0x3FFFFF) -> Physical Bank 0
// Virtual Bank 2 (0x400000-0x5FFFFF) -> Physical Bank 2
// Virtual Bank 3 (0x600000-0x7FFFFF) -> Physical Bank 3
wire [24:0] rv_physical_addr = { 2'b00, (rv_addr[22:21] == 2'b00) ? 2'b01 : ((rv_addr[22:21] == 2'b01) ? 2'b00 : rv_addr[22:21]), rv_addr[20:0] };

// ── Custom Dual-Client SDRAM Arbiter ─────────────────────────────────────────
// Reconstruct the 4-bit write mask for the Atari core from its we signals and address:
wire [3:0] core_sdram_wmask = core_sdram_32bit_we ? 4'b1111 :
                              core_sdram_16bit_we ? (core_sdram_addr[1] ? 4'b1100 : 4'b0011) :
                              core_sdram_8bit_we  ? (
                                  (core_sdram_addr[1:0] == 2'b00) ? 4'b0001 :
                                  (core_sdram_addr[1:0] == 2'b01) ? 4'b0010 :
                                  (core_sdram_addr[1:0] == 2'b10) ? 4'b0100 : 4'b1000
                              ) : 4'b0000;

wire actual_core_sdram_req = core_sdram_req && core_reset_n;

// The address_decoder asserts SDRAM_REQUEST for exactly ONE clock cycle (only in state_idle).
// If the SDRAM is busy (PicoRV32 transaction) or in tRP/tWR wait when that pulse arrives,
// the request is silently lost, deadlocking the 6502.  Latch the pulse until the SDRAM
// controller can accept it.
reg actual_core_sdram_req_r = 1'b0;
always_ff @(posedge clk_core or negedge hw_reset_n) begin
    if (!hw_reset_n) begin
        actual_core_sdram_req_r <= 1'b0;
    end else begin
        actual_core_sdram_req_r <= actual_core_sdram_req;
    end
end

wire atari_req_rise = actual_core_sdram_req && !actual_core_sdram_req_r;

reg atari_req_pending = 1'b0;
always_ff @(posedge clk_core or negedge hw_reset_n) begin
    if (!hw_reset_n) begin
        atari_req_pending <= 1'b0;
    end else begin
        if (atari_req_rise) begin
            atari_req_pending <= 1'b1;
        end else if (sadap_st == SA_BUSY && sdram_owner == OWN_ATARI && sdram_complete_wire) begin
            atari_req_pending <= 1'b0;
        end
    end
end

// Arbitration policy: STRICT ATARI PRIORITY.
// The Atari core must always get the SDRAM the moment it has a pending request,
// or its access misses the cycle_length=32 bus window and ANTIC DMA corrupts /
// the machine fails to boot.  PicoRV32 uses only genuinely idle cycles.
//
// The previous design used `rv_slot` to force PicoRV32 a guaranteed slot after
// every Atari access (round-robin), to keep the UART keyboard / OSD responsive.
// That reason is now OBSOLETE:
//   - the keyboard is decoded in hardware (SDRAM-independent), and
//   - the OSD only runs while the Atari core is HALTed (overlay → .HALT), so the
//     Atari isn't requesting SDRAM then and PicoRV32 gets the bus anyway.
// Forced fairness pushed the Atari past its window and prevented boot, so it is
// removed.  See memory: project-firmware-off-sdram (the real long-term fix is
// moving firmware off SDRAM; do NOT re-add softcore priority here).
reg rv_slot = 1'b0;  // retained (assigned but unused) to minimise churn; always 0 in policy

// Strict priority: Atari first, then the frame-buffer writer (fills idle cycles
// without ever preempting the Atari), then PicoRV32.  The writer is a clk_core,
// write-only client — no CDC, the simplest of the three.
wire [1:0] next_owner = atari_req_pending             ? OWN_ATARI :
                        (rv_req && !sdram_complete_r) ? OWN_RV    :
                        a816_req                      ? OWN_A816  : OWN_ATARI;

wire next_req = atari_req_pending || (rv_req && !sdram_complete_r) || a816_req;

wire [1:0] current_owner = (sadap_st == SA_BUSY) ? sdram_owner : next_owner;
// During SA_BUSY keep the persistent request of the active owner (rv_valid_core,
// not rv_req, so an in-progress PicoRV32 transaction is not dropped mid-flight if
// rv_hold happens to be set).
// SA_WAIT forces req low for one clk_core cycle (= 2 clk_mem cycles) after each access so the
// clk_mem SDRAM wrapper sees a clean req-deassert boundary between back-to-back accesses
// (4-phase handshake across the 2:1 clk_core↔clk_mem crossing).
wire sdram_ctrl_req = (sadap_st == SA_WAIT) ? 1'b0 :
                      (sadap_st == SA_BUSY) ?
                          ((sdram_owner == OWN_RV)   ? rv_valid_core :
                           (sdram_owner == OWN_A816) ? a816_req      : atari_req_pending)
                          : next_req;
wire        lp_is_816    = (sadap_st == SA_BUSY) ? (sdram_owner == OWN_A816)
                                                 : !(rv_req && !sdram_complete_r);
wire        sel_atari    = (sadap_st == SA_BUSY) ? (sdram_owner == OWN_ATARI)
                                                 : (atari_req_pending || !(rv_req && !sdram_complete_r) && !a816_req);
// Cartridge address remap: the core places emulated-cart accesses at SDRAM offset
// 8 MB+ (addr[24:22] = 3'b010, fine on MiSTer's 32 MB part). The core's
// SDRAM_CART_ADDR uses a full 22-bit (4 MB) emu_cart_address. Our embedded SDRAM is
// exactly 8 MB and gw2ar_sdram ignores addr[24:23], so without remapping carts would
// alias onto Atari RAM at 0x000000. Remap them into the 4 MB window at
// 0x400000-0x7FFFFF (RAM reaches 0x04FFFF at 320 KB, the largest size left; BASIC/OS relocated to
// the TOP of bank 0 at 0x1F0000/0x1F4000 — above RAM, below this window — and the old
// frame buffer is gone, so the whole upper 4 MB is free for carts; freezer disabled).
// Supports carts up to 4 MB (MegaCart 4 MB / .car type 63). The!Cart 32/64/128 MB
// still cannot fit the 8 MB part and are rejected by the firmware loader.
wire        core_addr_is_cart   = (core_sdram_addr[24:22] == 3'b010);
wire [24:0] core_sdram_addr_eff = core_addr_is_cart ? {3'b001, core_sdram_addr[21:0]}
                                                    : core_sdram_addr;

// The Atari's address/data/mask are combinational from ANTIC/CPU state through the MMU and
// had 0.0 ns slack into the clk_mem controller in v3.4. The address decoder holds them
// from the request cycle until completion, and the controller cannot latch them earlier
// than two clk_core edges after the request (atari_req_pending is itself one cycle late),
// so they are registered here once: the long MMU path now ends at a clk_core flop and only
// a short registered mux crosses into clk_mem. The two low-priority clients merge first.
reg  [24:0] core_addr_r  = 25'd0;
reg  [7:0]  core_wdata_r = 8'd0;
reg  [3:0]  core_wmask_r = 4'd0;
reg         core_rd_r = 1'b0, core_wr_r = 1'b0;
always_ff @(posedge clk_core) begin
    core_addr_r  <= core_sdram_addr_eff;
    core_wdata_r <= core_sdram_data_from_core[7:0];
    core_wmask_r <= core_sdram_wmask;
    core_rd_r    <= core_sdram_read_en;
    core_wr_r    <= core_sdram_write_en;
end
wire        sdram_ctrl_read_en  = sel_atari ? core_rd_r : (lp_is_816 ? ~a816_we : (~|rv_wstrb));
wire        sdram_ctrl_write_en = sel_atari ? core_wr_r : (lp_is_816 ?  a816_we : (|rv_wstrb));
wire [24:0] lp_addr      = lp_is_816 ? a816_physical_addr : rv_physical_addr;
wire [31:0] lp_wdata     = lp_is_816 ? a816_wdata         : rv_wdata;
wire [3:0]  lp_wmask     = lp_is_816 ? a816_wmask         : rv_wstrb;
wire [24:0] sdram_ctrl_addr     = sel_atari ? core_addr_r : lp_addr;
wire [31:0] sdram_ctrl_wdata    = sel_atari ? {4{core_wdata_r}} : lp_wdata;
wire [3:0]  sdram_ctrl_wmask    = sel_atari ? core_wmask_r : lp_wmask;
// While the classic machine is frozen ANTIC no longer asks for SDRAM refresh, so a timer
// does: one refresh every 448 clk_core cycles (15.6 us).
reg  [8:0]  frz_ref_cnt = 9'd0;
always_ff @(posedge clk_core) frz_ref_cnt <= (frz_ref_cnt == 9'd447) ? 9'd0 : frz_ref_cnt + 9'd1;
wire        sdram_ctrl_refresh  = a816_sv_freeze ? (frz_ref_cnt == 9'd0) : core_sdram_refresh;

// The 65C816 port is the only burst client (cache fills, NVC line fetch, blitter source reads).
wire   sdram_ctrl_burst = !sel_atari && lp_is_816 && !a816_we;
wire   a816_done        = sdram_complete_r && (sdram_owner == OWN_A816);

wire        sdram_complete_wire;

typedef enum logic [1:0] { SA_IDLE, SA_BUSY, SA_WAIT } sadap_t;
sadap_t sadap_st = SA_IDLE;

always_ff @(posedge clk_core or negedge hw_reset_n) begin
    if (!hw_reset_n) begin
        sdram_complete_r <= 1'b0;
        sadap_st         <= SA_IDLE;
        sdram_owner      <= OWN_ATARI;
        rv_slot          <= 1'b0;
        rv_done_toggle_r <= 1'b0;
        rv_hold          <= 1'b0;
    end else begin
        sdram_complete_r <= 1'b0;

        // rv_hold: set when a PicoRV32 transaction completes; cleared when
        // rv_valid_core deasserts.  Prevents phantom re-launches while waiting
        // for the rv_ready toggle-sync pulse to reach iosys (≈8 clk_core cycles).
        if (sdram_complete_r && sdram_owner == OWN_RV) rv_hold <= 1'b1;
        if (!rv_valid_core)                            rv_hold <= 1'b0;

        case (sadap_st)
            SA_IDLE: begin
                if (sdram_ready_wire) begin
                    // Strict priority Atari > PicoRV32: the Atari wins whenever it has a
                    // pending request; PicoRV32 is served only when the Atari is idle.
                    if (atari_req_pending) begin
                        sdram_owner <= OWN_ATARI;
                        sadap_st    <= SA_BUSY;
                    end else if (rv_req && !sdram_complete_r) begin
                        sdram_owner <= OWN_RV;
                        sadap_st    <= SA_BUSY;
                    end else if (a816_req) begin
                        sdram_owner <= OWN_A816;
                        sadap_st    <= SA_BUSY;
                    end
                end
            end
            SA_BUSY: begin
                if (sdram_complete_wire) begin
                    sdram_complete_r <= 1'b1;
                    sadap_st         <= SA_WAIT;   // one req-low cycle before the next access
                    // (rv_slot forced-fairness removed — strict Atari priority now.)
                    rv_slot <= 1'b0;
                    // Pulse the toggle-sync for iosys rv_ready, and CAPTURE the
                    // read data NOW.  sdram_rd_data_wire is the controller's single
                    // shared rdata register; if we left rv_rdata combinational, an
                    // Atari read in the ~3-cycle window before PicoRV32 captures it
                    // (completion toggle crossing clk_core→sys_clk) would overwrite
                    // it → PicoRV32 latches Atari data → corrupted firmware word →
                    // wild jump → undecoded-address hang.  Latching here prevents it.
                    if (sdram_owner == OWN_RV) begin
                        rv_done_toggle_r <= ~rv_done_toggle_r;
                        rv_rdata_hold    <= sdram_rd_data_wire;
                    end
                end
            end
            SA_WAIT: sadap_st <= SA_IDLE;   // req held low here; wrapper sees the boundary
            default: sadap_st <= SA_IDLE;
        endcase
    end
end

// Synchronise rv_done_toggle_r (clk_core) into sys_clk for iosys rv_ready
always_ff @(posedge sys_clk or negedge hw_reset_n) begin
    if (!hw_reset_n) rv_done_sys_r <= 3'b000;
    else             rv_done_sys_r <= {rv_done_sys_r[1:0], rv_done_toggle_r};
end

// ── Atari816 bring-up 1: 65C816 + cache + minimal native I/O page ────────────
wire       a816_run_sys;                 // iosys (sys_clk): 1 = release the 65C816
wire [7:0] a816_dbg_data;
wire       a816_dbg_tgl, a816_dbg_ack_tgl;
wire [23:0] a816_mb_req_base, a816_mb_rsp_base;
wire [7:0]  a816_mb_req_head, a816_mb_rsp_tail;
wire [17:0] a816_mb_iop;             // sys_clk: {status, rsp_head, req_tail}
wire        a816_kb_route;           // 1 = keyboard belongs to the classic machine
wire        kb_to_horizon;           // assigned below, after a816_run_sync is declared
reg  [2:0]  a816_f12_s = 3'b000;     // F12 = system key (NMI)
always @(posedge clk_core) a816_f12_s <= {a816_f12_s[1:0], key_f12};
reg  [1:0] a816_run_sync = 2'b00;
always_ff @(posedge clk_core or negedge hw_reset_n) begin
    if (!hw_reset_n) a816_run_sync <= 2'b00;
    else             a816_run_sync <= {a816_run_sync[0], a816_run_sys};
end
assign kb_to_horizon = a816_run_sync[1] & ~a816_kb_route;

// Marga, the Atari816 video chip (a816_nvc). It sits between the 65C816 and the arbiter's 65C816 port, and
// its port mux also serves Ali, the blitter (priority: line fetch, CPU, blitter).
wire        nvc_xio_wr, nvc_xio_rd, blt_xio_wr, blt_irq;
wire        aud_xio_wr, aud_xio_rd, aud_irq, opl_irq, aud_req, aud_done;
wire [7:0]  aud_xio_rdata, opl_xio_rdata;
wire [22:0] aud_addr;
wire [7:0]  blt_xio_rdata;
wire        blt_req, blt_gnt, blt_we, blt_long, blt_done;
wire [22:0] blt_addr;
wire [31:0] blt_wdata;
wire [3:0]  blt_wmask;
wire [7:0]  nvc_xio_addr, nvc_xio_wdata, nvc_xio_rdata;
wire        nvc_irq_vblank, nvc_irq_line;
wire        cpu816_req, cpu816_we, cpu816_done;
wire [22:0] cpu816_addr;
wire [7:0]  cpu816_wdata;
wire        nvc_on;
wire [7:0]  nvc_r, nvc_g, nvc_b;
wire [10:0] nvc_hx;
wire [9:0]  nvc_vy;
a816_sys #(.AW(23), .REV(A816_REV)) a816 (
    .clk        (clk_core),
    .reset_n    (hw_reset_n),
    .run        (a816_run_sync[1]),
    .sys_key    (a816_f12_s[1] & ~a816_f12_s[2]),
    .kb_route   (a816_kb_route),
    .sv_freeze  (a816_sv_freeze),
    .snd_wr     (a816_snd_wr),
    .joy_n_a    ({joy2_n, joy1_n}),
    .mb_req_base(a816_mb_req_base), .mb_req_head(a816_mb_req_head),
    .mb_rsp_base(a816_mb_rsp_base), .mb_rsp_tail(a816_mb_rsp_tail),
    .mb_req_tail_a(a816_mb_iop[7:0]), .mb_rsp_head_a(a816_mb_iop[15:8]), .mb_status_a(a816_mb_iop[17:16]),
    .xio_wr(nvc_xio_wr), .xio_rd(nvc_xio_rd), .xio_addr(nvc_xio_addr), .xio_wdata(nvc_xio_wdata), .xio_rdata(nvc_xio_rdata),
    .blt_wr(blt_xio_wr), .blt_rdata(blt_xio_rdata),
    .aud_wr(aud_xio_wr), .aud_rd(aud_xio_rd), .aud_rdata(aud_xio_rdata | opl_xio_rdata), .irq_audio(aud_irq | opl_irq),
    .irq_vblank(nvc_irq_vblank), .irq_line(nvc_irq_line), .irq_blit(blt_irq),
    .sd_req     (cpu816_req),
    .sd_we      (cpu816_we),
    .sd_addr    (cpu816_addr),
    .sd_wdata   (cpu816_wdata),
    .sd_done    (cpu816_done),
    .sd_rdata   (sdram_burst_dout[63:0]),
    .dbg_data   (a816_dbg_data),
    .dbg_tgl    (a816_dbg_tgl),
    .dbg_ack_tgl(a816_dbg_ack_tgl)
);

always_ff @(posedge clk_core) begin
    a816_snd_wr_r   <= a816_snd_wr;
    a816_snd_addr_r <= nvc_xio_addr[4:0];
    a816_snd_data_r <= nvc_xio_wdata;
end

a816_nvc #(.AW(23)) nvc (
    .clk(clk_core), .reset_n(hw_reset_n), .run(a816_run_sync[1]),
    .xio_wr(nvc_xio_wr), .xio_rd(nvc_xio_rd), .xio_addr(nvc_xio_addr), .xio_wdata(nvc_xio_wdata), .xio_rdata(nvc_xio_rdata),
    .irq_vblank(nvc_irq_vblank), .irq_line(nvc_irq_line),
    .c_req(cpu816_req), .c_we(cpu816_we), .c_addr(cpu816_addr), .c_wdata(cpu816_wdata), .c_done(cpu816_done),
    .b_req(blt_req), .b_we(blt_we), .b_addr(blt_addr), .b_wdata(blt_wdata), .b_wmask(blt_wmask),
    .b_long(blt_long), .b_gnt(blt_gnt), .b_done(blt_done),
    .a_req(aud_req), .a_addr(aud_addr), .a_done(aud_done),
    .sd_req(a816_req), .sd_we(a816_we), .sd_addr(a816_addr), .sd_wdata(a816_wdata), .sd_wmask(a816_wmask),
    .sd_done(a816_done), .sd_rdata(sdram_burst_dout[127:0]), .sd_long(a816_long), .long_ok(a816_sv_freeze),
    .clk_pix(clk_pix), .hx(nvc_hx), .vy(nvc_vy),
    .nv_on(nvc_on), .nv_r(nvc_r), .nv_g(nvc_g), .nv_b(nvc_b)
);

a816_blit #(.AW(23)) blit (
    .clk(clk_core), .reset_n(hw_reset_n), .run(a816_run_sync[1]),
    .xio_wr(blt_xio_wr), .xio_addr(nvc_xio_addr), .xio_wdata(nvc_xio_wdata), .xio_rdata(blt_xio_rdata),
    .irq(blt_irq), .vbl(nvc_irq_vblank),
    .b_req(blt_req), .b_gnt(blt_gnt), .b_we(blt_we), .b_addr(blt_addr), .b_wdata(blt_wdata),
    .b_wmask(blt_wmask), .b_long(blt_long), .b_done(blt_done), .b_rdata(sdram_burst_dout[127:0]),
    .long_ok(a816_sv_freeze)
);

a816_opl opl (
    .clk(clk_core), .reset_n(hw_reset_n), .run(a816_run_sync[1]),
    .xio_wr(aud_xio_wr), .xio_addr(nvc_xio_addr), .xio_wdata(nvc_xio_wdata),
    .xio_rdata(opl_xio_rdata), .irq(opl_irq),
    .snd(opl_snd)
);

`ifndef A816_NO_SAMPLER
a816_snd #(.AW(23)) snd (
    .clk(clk_core), .reset_n(hw_reset_n), .run(a816_run_sync[1]),
    .xio_wr(aud_xio_wr), .xio_addr(nvc_xio_addr), .xio_wdata(nvc_xio_wdata),
    .xio_rdata(aud_xio_rdata), .irq(aud_irq), .smp_tgl_a(hdmi_smp_tgl),
    .a_req(aud_req), .a_addr(aud_addr), .a_done(aud_done), .a_rdata(sdram_burst_dout[63:0]),
    .out_l(snd_l), .out_r(snd_r)
);
`else
assign aud_xio_rdata = 8'h00; assign aud_irq = 1'b0; assign aud_req = 1'b0; assign aud_addr = 23'd0;
assign snd_l = 16'sd0; assign snd_r = 16'sd0;
`endif

gw2ar_sdram sdram_ip (
    .clk          (clk_core),
    .clk_mem      (clk_mem),
    .reset_n      (hw_reset_n),

    // User interface
    .req          (sdram_ctrl_req),
    .req_complete (sdram_complete_wire),
    .read_en      (sdram_ctrl_read_en),
    .write_en     (sdram_ctrl_write_en),
    .burst        (sdram_ctrl_burst),
    .burst_long   (sdram_ctrl_burst && a816_long),
    .addr         (sdram_ctrl_addr),
    .rdata        (sdram_rd_data_wire),
    .burst_rdata  (sdram_burst_dout),
    .wdata        (sdram_ctrl_wdata),
    .wmask        (sdram_ctrl_wmask),
    .refresh      (sdram_ctrl_refresh),

    // Physical embedded SDRAM connections
    .O_sdram_clk  (O_sdram_clk),
    .O_sdram_cke  (O_sdram_cke),
    .O_sdram_cs_n (O_sdram_cs_n),
    .O_sdram_ras_n(O_sdram_ras_n),
    .O_sdram_cas_n(O_sdram_cas_n),
    .O_sdram_wen_n(O_sdram_wen_n),
    .O_sdram_ba   (O_sdram_ba),
    .O_sdram_addr (O_sdram_addr),
    .O_sdram_dqm  (O_sdram_dqm),
    .IO_sdram_dq  (IO_sdram_dq),

    .sdram_ready  (sdram_ready_wire)
);

// (Frame-buffer writer removed — the scandoubler reads Atari video directly.)

// ─────────────────────────────────────────────────────────────────────────────
// PicoRV32 Softcore MCU & SIO Disk Handler
// ─────────────────────────────────────────────────────────────────────────────

// Virtual Keyboard wires from PicoRV32 softcore
wire [7:0] virt_kbd_mod;
wire [7:0] virt_kbd_key1;
wire [7:0] virt_kbd_key2;
wire [7:0] virt_kbd_key3;
wire [7:0] virt_kbd_key4;
wire [7:0] cart_mode_sys;       // iosys (sys_clk) cartridge mapper select
// CDC to clk_core: quasi-static (firmware only changes it while the Atari core is
// held in reset around a cold boot), 2-FF per bit is sufficient.
reg [7:0] cart_mode_m = 8'h00, cart_mode_core = 8'h00;
always_ff @(posedge clk_core) begin
    cart_mode_m    <= cart_mode_sys;
    cart_mode_core <= cart_mode_m;
end

// Keyboard comes from PicoRV32's hot BSRAM CH9350 parser (uart_keyboard_poll -> virt_kbd_*).
// The duplicate hardware uart_kbd_ch9350 decoder (left over from the SDRAM-firmware era) is
// removed to save ~180 LUTs / ~240 FFs for OPL2.
wire [7:0] combined_key_mod = virt_kbd_mod;
wire [7:0] combined_key1    = virt_kbd_key1;
wire [7:0] combined_key2    = virt_kbd_key2;
wire [7:0] combined_key3    = virt_kbd_key3;
wire [7:0] combined_key4    = virt_kbd_key4;

// OSD navigation: driven by BOTH real USB keyboard and virtual UART keyboard.
wire key_up    = (combined_key1 == 8'h52) || (combined_key2 == 8'h52) || (combined_key3 == 8'h52) || (combined_key4 == 8'h52); // Up Arrow
wire key_down  = (combined_key1 == 8'h51) || (combined_key2 == 8'h51) || (combined_key3 == 8'h51) || (combined_key4 == 8'h51); // Down Arrow
wire key_left  = (combined_key1 == 8'h50) || (combined_key2 == 8'h50) || (combined_key3 == 8'h50) || (combined_key4 == 8'h50); // Left Arrow
wire key_right = (combined_key1 == 8'h4F) || (combined_key2 == 8'h4F) || (combined_key3 == 8'h4F) || (combined_key4 == 8'h4F); // Right Arrow
wire key_enter = (combined_key1 == 8'h28) || (combined_key2 == 8'h28) || (combined_key3 == 8'h28) || (combined_key4 == 8'h28); // Enter
wire key_esc   = (combined_key1 == 8'h29) || (combined_key2 == 8'h29) || (combined_key3 == 8'h29) || (combined_key4 == 8'h29); // Escape
wire key_f12   = (combined_key1 == 8'h45) || (combined_key2 == 8'h45) || (combined_key3 == 8'h45) || (combined_key4 == 8'h45); // F12
wire key_f9    = (combined_key1 == 8'h42) || (combined_key2 == 8'h42) || (combined_key3 == 8'h42) || (combined_key4 == 8'h42); // F9 (soft reset hotkey)
wire key_f11   = (combined_key1 == 8'h44) || (combined_key2 == 8'h44) || (combined_key3 == 8'h44) || (combined_key4 == 8'h44); // F11 (arrows<->joystick live toggle)

// ── Arrow-keys-as-Joystick mode (OSD-toggled via joystick_mode) ──────────────
// Left-Alt = fire. When on, the arrow keys + Left-Alt drive Joystick 1 (OR'd
// with the physical DB9 stick) and are suppressed from the Atari keyboard matrix
// so they don't also type. JOY1_n is active-low: bit0=up,1=down,2=left,3=right,4=fire.
wire key_lalt = combined_key_mod[2];   // HID Left-Alt modifier
// Opposite directions are made exclusive on the KEYBOARD path only: two overlapping key
// presses (left+right, up+down) would present a stick value a mechanical joystick can never
// produce, and games that index tables by the raw STICK nibble crash on it (Tiger Attack
// froze within seconds of keyboard play; a DB9 stick never did — INVESTIGATE #22). Both
// pressed = neither, i.e. the stick passing through centre. The DB9 path is untouched.
wire kj_up    = key_up    & ~key_down;
wire kj_down  = key_down  & ~key_up;
wire kj_left  = key_left  & ~key_right;
wire kj_right = key_right & ~key_left;
wire [4:0] joy1_kbd_n = joystick_mode ? ~{key_lalt, kj_right, kj_left, kj_down, kj_up}
                                      : 5'b11111;
// (The on-screen menu and its input mask are gone: Atari816.)
wire [4:0] joy1_to_core = joy1_n & joy1_kbd_n;
wire [4:0] joy2_to_core = joy2_n;

// Keyboard-matrix keys with the joystick keys (arrows 0x4F-0x52, Left-Alt) removed
// while joystick_mode is on, so they only move the stick and don't type.
// All keys masked while the keyboard belongs to Horizon.
wire [7:0] mtx_key1 = kb_to_horizon ? 8'h00 : ((joystick_mode && combined_key1 >= 8'h4F && combined_key1 <= 8'h52) ? 8'h00 : combined_key1);
wire [7:0] mtx_key2 = kb_to_horizon ? 8'h00 : ((joystick_mode && combined_key2 >= 8'h4F && combined_key2 <= 8'h52) ? 8'h00 : combined_key2);
wire [7:0] mtx_key3 = kb_to_horizon ? 8'h00 : ((joystick_mode && combined_key3 >= 8'h4F && combined_key3 <= 8'h52) ? 8'h00 : combined_key3);
wire [7:0] mtx_key4 = kb_to_horizon ? 8'h00 : ((joystick_mode && combined_key4 >= 8'h4F && combined_key4 <= 8'h52) ? 8'h00 : combined_key4);
wire [7:0] mtx_mod  = kb_to_horizon ? 8'h00 : (joystick_mode ? (combined_key_mod & ~8'h04) : combined_key_mod); // drop Left-Alt

// Combine USB keyboard keys and physical DB9 Joystick 1 (active low, so ~joy1_n)
wire joy_up    = key_up    || ~joy1_n[0];
wire joy_down  = key_down  || ~joy1_n[1];
wire joy_left  = key_left  || ~joy1_n[2];
wire joy_right = key_right || ~joy1_n[3];
wire joy_fire  = key_enter || ~joy1_n[4];

// S2 (btn_n[1]) is active-HIGH: 0 when unpressed (PULL_MODE=DOWN), 1 when pressed.
// Map directly (no inversion) to bit 9 (X) in rv_joy1 so firmware sees 1 only when pressed.
wire osd_toggle = btn_n[1];

wire [11:0] rv_joy1 = {
    joy_right,                         // 11: R
    key_f11,                           // 10: F11 — arrows<->joystick live toggle (firmware
                                       //     edge-detects; bit 10 was a redundant joy_left dup)
    osd_toggle,                        //  9: X (S2 button)
    1'b0,                              //  8: A (free; joy_choice treats it as confirm)
    joy_right,                         //  7: RT — right arrow/stick = page forward in menus
    joy_left,                          //  6: LT — left arrow/stick = page back in menus
    joy_down,                          //  5: DN
    joy_up,                            //  4: UP
    key_f12,                           //  3: START
    key_f9,                            //  2: SELECT slot — F9 soft-reset hotkey
    key_esc,                           //  1: Y
    joy_fire                           //  0: B
};
wire [11:0] rv_joy2 = 12'b0;


// SIO register interface wires
wire        sio_reg_sel;
wire [4:0]  sio_reg_addr;
wire [7:0]  sio_reg_wdata;
wire        sio_reg_wr;
wire [15:0] sio_reg_rdata;
wire        sio_reg_en;

// Phase B: hardware SIO command-frame capture (sio_handler ↔ iosys)
wire [39:0] siocmd_bytes;
wire [7:0]  siocmd_status;
wire [7:0]  siocmd_seq;
wire        siocmd_ack;

// Video options (OSD-toggled)
wire [1:0]  scanline_level;
wire [7:0]  h_offset;

wire        kbd_pc_layout;   // OSD "Keyboard: PC" (sys_clk, same domain as the keyboard module)

// Atari RAM size (OSD-selected): quasi-static config from iosys (sys_clk). The
// firmware only changes it across a cold boot, so a plain 2-FF sync into clk_core
// is safe (settles long before the core leaves reset). Default 3'b001 = 128 KB.
wire [2:0]  ram_select_opt;
// The classic machine's PBI disk (core/README.md, "Fast disk"): enable from the firmware, request bit to it
wire        pbi_en_opt, pbi_req_core;
reg         pbi_en_s1 = 1'b0, pbi_en_core = 1'b0;
always @(posedge clk_core) begin pbi_en_s1 <= pbi_en_opt; pbi_en_core <= pbi_en_s1; end
reg  [2:0]  ram_sel_s1 = 3'b001, ram_select_core = 3'b001;
always @(posedge clk_core) begin ram_sel_s1 <= ram_select_opt; ram_select_core <= ram_sel_s1; end

wire        sio_rx_data_in;
wire        sio_clk_out;
wire        enable_179_early;

assign dbg_sd_ready = roms_loaded;

// (The frame-rate counters and the SIO response-line meter, both debug aids the firmware
// no longer reads, were removed: Atari816.)

// PicoRV32 IO subsystem module
// iosys_picorv32 stays on sys_clk (27 MHz): firmware compiled for that frequency.
// Its SPI/SD timing is correct only at 27 MHz; CDC to the 54 MHz arbiter is
// handled by rv_valid_core (2-FF sync) + rv_ready toggle-sync + rv_hold gate.
iosys_picorv32 #(
    .FREQ(27_000_000),
    .COLOR_LOGO(15'b00000_10101_00000),
    .CORE_ID(16'd3) // 3 for Atari
) mcu (
    .clk(sys_clk),
    .resetn(hw_reset_n),

    .joy1(rv_joy1),
    .joy2(rv_joy2),

    // ROM loading interface
    .rom_loading(rom_loading),
    .rom_do(),
    .rom_do_valid(),

    // 32-bit wide memory interface for RISC-V softcore
    .rv_valid(rv_valid),
    .rv_ready(rv_ready),
    .rv_addr(rv_addr),
    .rv_wdata(rv_wdata),
    .rv_wstrb(rv_wstrb),
    .rv_rdata(rv_rdata),

    // Atari816 bring-up
    .a816_run(a816_run_sys),
    .a816_mb_req({a816_mb_req_head, a816_mb_req_base}),
    .a816_mb_rsp({a816_mb_rsp_tail, a816_mb_rsp_base}),
    .a816_mb_iop(a816_mb_iop),
    .a816_keys({combined_key4, combined_key3, combined_key2, combined_key1}),
    .a816_keymod({a816_sv_freeze, kb_to_horizon, combined_key_mod}),
    .a816_dbg_data(a816_dbg_data),
    .a816_dbg_tgl(a816_dbg_tgl),
    .a816_dbg_ack_tgl(a816_dbg_ack_tgl),

    .ram_busy(~sdram_ready),

    // SPI Flash
    .flash_spi_cs_n(flash_spi_cs_n),
    .flash_spi_miso(flash_spi_miso),
    .flash_spi_mosi(flash_spi_mosi),
    .flash_spi_clk(flash_spi_clk),
    .flash_spi_wp_n(flash_spi_wp_n),
    .flash_spi_hold_n(flash_spi_hold_n),

    // UART RX is mapped to pin 53 (usb_dp) — keyboard frames (SW decode path).
    // UART TX goes to the BL616 (USB-C CDC serial) = live firmware logs on the PC.
    .uart_rx(usb_dp),
    .uart_tx(bl616_uart_tx),
    .bl616_rx(bl616_uart_rx),

    // Virtual Keyboard outputs (usb_host_enable_out is no longer used)
    .virt_kbd_mod_out(virt_kbd_mod),
    .virt_kbd_key1_out(virt_kbd_key1),
    .virt_kbd_key2_out(virt_kbd_key2),
    .virt_kbd_key3_out(virt_kbd_key3),
    .virt_kbd_key4_out(virt_kbd_key4),
    .cart_mode_out(cart_mode_sys),
    .usb_host_enable_out(usb_host_enable),
    .joystick_mode_out(joystick_mode),

    // SD Card (SPI mode)
    .sd_clk(sd_clk),
    .sd_cmd(sd_mosi),
    .sd_dat0(sd_miso),
    .sd_dat1(),
    .sd_dat2(),
    .sd_dat3(sd_cs),

    // SIO register interface
    .sio_reg_sel(sio_reg_sel),
    .sio_reg_addr(sio_reg_addr),
    .sio_reg_wdata(sio_reg_wdata),
    .sio_reg_wr(sio_reg_wr),
    .sio_reg_rdata(sio_reg_rdata),
    .sio_reg_en(sio_reg_en),

    // Phase B: SIO command-frame capture registers
    .siocmd_bytes(siocmd_bytes),
    .siocmd_status(siocmd_status),
    .siocmd_seq(siocmd_seq),
    .siocmd_ack(siocmd_ack),

    // Video options
    .scanline_level_out(scanline_level),
    .h_offset_out(h_offset),
    .kbd_pc_layout_out(kbd_pc_layout),
    .ram_select_out(ram_select_opt),
    .pbi_en_out(pbi_en_opt),
    .pbi_req(pbi_req_core)
);

// Clock Domain Crossing (CDC) Synchronization for SIO Handler
// POKEY_ENABLE toggle synchronizer (from 54 MHz clk_core to 27 MHz sys_clk)
// Use hw_reset_n to avoid CDC reset timing issues.
reg enable_179_early_toggle = 1'b0;
always_ff @(posedge clk_core or negedge hw_reset_n) begin
    if (!hw_reset_n)
        enable_179_early_toggle <= 1'b0;
    else if (enable_179_early)
        enable_179_early_toggle <= ~enable_179_early_toggle;
end

reg [2:0] enable_179_early_sync = 3'b0;
always_ff @(posedge sys_clk or negedge hw_reset_n) begin
    if (!hw_reset_n)
        enable_179_early_sync <= 3'b0;
    else
        enable_179_early_sync <= {enable_179_early_sync[1:0], enable_179_early_toggle};
end
wire enable_179_early_sys = enable_179_early_sync[2] ^ enable_179_early_sync[1];

// Double synchronizers for asynchronous SIO input lines (Atari outputs to sys_clk)
reg [1:0] SIO_COMMAND_sync = 2'b11;
reg [1:0] SIO_TXD_sync     = 2'b11;
reg [1:0] SIO_CLOCK_sync   = 2'b11;

always_ff @(posedge sys_clk or negedge hw_reset_n) begin
    if (!hw_reset_n) begin
        SIO_COMMAND_sync <= 2'b11;
        SIO_TXD_sync     <= 2'b11;
        SIO_CLOCK_sync   <= 2'b11;
    end else begin
        SIO_COMMAND_sync <= {SIO_COMMAND_sync[0], sio_command};
        SIO_TXD_sync     <= {SIO_TXD_sync[0], sio_txd};
        SIO_CLOCK_sync   <= {SIO_CLOCK_sync[0], sio_clk_out};
    end
end

wire sio_command_sys = SIO_COMMAND_sync[1];
wire sio_txd_sys     = SIO_TXD_sync[1];
wire sio_clk_out_sys = SIO_CLOCK_sync[1];

// VHDL SIO Disk Handler
sio_handler sio_inst (
    .CLK(sys_clk),
    .ADDR(sio_reg_addr),
    .CPU_DATA_IN(sio_reg_wdata),
    .EN(sio_reg_en),
    .WR_EN(sio_reg_wr),
    .RESET_N(hw_reset_n),
    .POKEY_ENABLE(enable_179_early_sys),
    .SIO_DATA_IN(sio_rx_data_in),
    .SIO_COMMAND(sio_command_sys),
    .SIO_DATA_OUT(sio_txd_sys),
    .SIO_CLK_OUT(sio_clk_out_sys),
    .DATA_OUT(sio_reg_rdata),
    // Phase B: command-frame capture
    .SIO_CMD_BYTES(siocmd_bytes),
    .SIO_CMD_STATUS(siocmd_status),
    .SIO_CMD_SEQ(siocmd_seq),
    .SIO_CMD_ACK(siocmd_ack)
);

// ─────────────────────────────────────────────────────────────────────────────
// Atari 800 core
// ─────────────────────────────────────────────────────────────────────────────
atari800core_simple_sdram #(
    .cycle_length               (16),
    .video_bits                 (8),
    .palette                    (0),    // Phase A: 0 = raw GTIA colour code on VIDEO_B
                                        // (Altirra palette applied on readout in scandoubler_480p)
    .internal_rom               (0),    // ROMs in SDRAM
    .internal_ram               (0),
    .low_memory                 (0),
    .covox                      (0)
) core (
    .CLK                        (clk_core),
    .RESET_N                    (core_reset_n),

    // Video
    .VIDEO_VS                   (video_vs),
    .VIDEO_HS                   (video_hs),
    .VIDEO_B                    (video_b),
    .VIDEO_G                    (video_g),
    .VIDEO_R                    (video_r),
    .VIDEO_BLANK                (video_blank),
    .VIDEO_PIXCE                (video_pixce),
    .VIDEO_BURST                (),
    .VIDEO_START_OF_FIELD       (video_sof),
    .VIDEO_ODD_LINE             (),
    .interlace_field            (),
    .interlace                  (),
    .interlace_enable           (1'b0),
    .HBLANK                     (),
    .VBLANK                     (),

    // Audio (mono POKEY 1; POKEY 2 removed for OPL2)
    .STEREO                     (1'b0),
    .AUDIO_L                    (audio_l_pcm),
    .AUDIO_R                    (audio_r_pcm),

    // Joysticks
    .JOY1_n                     (joy1_to_core),
    .JOY2_n                     (joy2_to_core),
    .JOY3_n                     (5'b11111),
    .JOY4_n                     (5'b11111),

    // Keyboard matrix
    .KEYBOARD_RESPONSE          (keyboard_response),
    .KEYBOARD_SCAN              (keyboard_scan),

    // SIO
    .SIO_COMMAND                (sio_command),
    .SIO_RXD                    (sio_rx_data_in),
    .SIO_TXD                    (sio_txd),
    .SIO_CLOCK                  (sio_clk_out),
    .SIO_CLOCK_IN               (1'b1),
    .SIO_PROC                   (1'b1),
    .SIO_IRQ                    (1'b1),
    .SIO_MOTOR                  (sio_motor),
    .TAPE_AUDIO                 (8'h00),
    .ENABLE_179_EARLY           (enable_179_early),
    .PORTA_OUT_EXP              (),

    // Console keys
    .CONSOL_START               (consol_start),
    .CONSOL_SELECT              (consol_select),
    .CONSOL_OPTION              (consol_option),

    // SDRAM bus
    .SDRAM_REQUEST              (core_sdram_req),
    .SDRAM_REQUEST_COMPLETE     (core_sdram_req_complete),
    .SDRAM_READ_ENABLE          (core_sdram_read_en),
    .SDRAM_WRITE_ENABLE         (core_sdram_write_en),
    .SDRAM_ADDR                 (core_sdram_addr),
    .SDRAM_DO                   (core_sdram_data_to_core),
    .SDRAM_DI                   (core_sdram_data_from_core),
    .SDRAM_32BIT_WRITE_ENABLE   (core_sdram_32bit_we),
    .SDRAM_16BIT_WRITE_ENABLE   (core_sdram_16bit_we),
    .SDRAM_8BIT_WRITE_ENABLE    (core_sdram_8bit_we),
    .SDRAM_REFRESH              (core_sdram_refresh),

    // DMA port — tied off (ROMs loaded via direct SDRAM write)
    .DMA_FETCH                  (1'b0),
    .DMA_READ_ENABLE            (1'b0),
    .DMA_32BIT_WRITE_ENABLE     (1'b0),
    .DMA_16BIT_WRITE_ENABLE     (1'b0),
    .DMA_8BIT_WRITE_ENABLE      (1'b0),
    .DMA_ADDR                   (26'd0),
    .DMA_WRITE_DATA             (32'd0),
    .MEMORY_READY_DMA           (),
    .DMA_MEMORY_DATA            (),

    // Config
    .RAM_SELECT                 (ram_select_core),  // /atari.ini RAM size: 128 KB or 320 KB; BASIC/OS at top of bank 0
    .PAL                        (1'b0),     // NTSC
    .CLIP_SIDES                 (1'b0),
    .RESET_RNMI                 (1'b0),
    .ATARI800MODE               (1'b0),     // XL/XE mode
    .PBI_ROM_MODE               (pbi_en_core),      // the PBI disk (firmware option)
    .PBI_DISK_REQ               (pbi_req_core),
    .XEX_LOADER_MODE            (1'b0),
    .RTC                        (65'd0),
    .VBXE_SWITCH                (1'b0),
    .VBXE_REG_BASE              (1'b0),
    .VBXE_NTSC_FIX              (1'b0),
    .VBXE_PALETTE_RGB           (3'd0),
    .VBXE_PALETTE_INDEX         (8'd0),
    .VBXE_PALETTE_COLOR         (7'd0),
    // HALT is permanently deasserted. It maps to PAUSE_6502, which freezes ONLY the
    // 6502 while ANTIC/POKEY/GTIA keep running — that half-pause during the OSD menu
    // desynchronized games (missed VBIs/DLIs → corrupted background, garbled sprites
    // on resume). The menu is now a pure overlay: the Atari runs live behind it, and
    // keyboard/joystick inputs are masked from the core while the overlay is up.
    .A816_SND                   (a816_sv_freeze),   // frozen: POKEY 1 plays its native register bank ($00:DB00-$DB0F)
    .A816_SND_WR                (a816_snd_wr_r),
    .A816_SND_ADDR              (a816_snd_addr_r),
    .A816_SND_DATA              (a816_snd_data_r),
    .HALT                       (a816_sv_freeze),   // Atari816: now a whole-machine freeze (shared_enable)
    // 0 = true 1x 6502 speed (CPU runs only on enable_179, locked to ANTIC/POKEY).
    // The speed-shift logic ADDS a CPU enable per set throttle bit, so 6'd31 was
    // 6 enables/machine-cycle => ~6x too fast (boot/loop 6x, SIO windows 6x narrow).
    // The core's "standard speed is cycle_length-1" comment is misleading here.
    .THROTTLE_COUNT_6502        (6'd0),
    .emulated_cartridge_select  (cart_mode_core),
    .emulated_cartridge2_select (8'd0),
    .EMU_FLASH_REQUEST          (),
    .EMU_FLASH_SLAVE            (),
    .freezer_enable             (1'b0),
    .freezer_activate           (1'b0)
);

// ─────────────────────────────────────────────────────────────────────────────
// USB pins: usb_dp is the CH9350 UART input (uart_kbd and the iosys UART RX); usb_dm is
// unused. The direct USB-HID host that drove them was removed (Atari816).
// ─────────────────────────────────────────────────────────────────────────────
assign usb_dm = 1'bz;
assign usb_dp = 1'bz;


usb_to_atari800 keyboard (
    .clk              (sys_clk),
    .reset_n          (core_reset_n),
    .key_modifiers    (mtx_mod),
    .key1             (mtx_key1),
    .key2             (mtx_key2),
    .key3             (mtx_key3),
    .key4             (mtx_key4),
    .pc_layout        (kbd_pc_layout),
    .keyboard_scan    (keyboard_scan),
    .keyboard_response(keyboard_response),
    .consol_start     (consol_start),
    .consol_select    (consol_select),
    .consol_option    (consol_option)
);

// ─────────────────────────────────────────────────────────────────────────────
// HDMI video source: genlocked scandoubler line buffer (no SDRAM, ~1-2 line latency)
// ─────────────────────────────────────────────────────────────────────────────
wire [7:0] hdmi_r, hdmi_g, hdmi_b;
wire       hdmi_hs, hdmi_vs, hdmi_de;
// (The SDRAM frame-buffer reader was removed — the scandoubler below reads Atari video
//  directly. The Atari core and PicoRV32 are now the only SDRAM clients.)

// Genlocked scandoubler: Atari video (clk_core) -> 4-line ring -> standard 480p59.94
// (clk_pix=27 MHz), 2x2 upscale + pillarbox, Altirra palette on readout.
// Capture-side SIO activity inputs — declared here (the source flags are defined further
// down); assigned just after sio_data_act below. Explicit wires avoid the implicit-net
// forward-reference (a phantom 1-bit net shadowing the 22-bit sio_cmd_stretch reg).
wire sio_ind_data, sio_ind_cmd;
scandoubler_480p scandoubler (
    .clk_core  (clk_core),
    .rst_n     (hdmi_rst_n),
    .colour_in (video_b),        // GTIA colour code (palette=0)
    .de_in     (~video_blank),
    .sof_in    (video_sof),
    .pixce     (video_pixce),
    .sio_act_in(sio_ind_data),       // capture-side SIO activity blocks (clk_core domain)
    .sio_cmd_in(sio_ind_cmd),
    .clk_pix   (clk_pix),
    .scanline_level(scanline_level),
    .h_offset(h_offset),
    .nv_on(nvc_on), .nv_r(nvc_r), .nv_g(nvc_g), .nv_b(nvc_b), .hx_out(nvc_hx), .vy_out(nvc_vy),
    .r_out(hdmi_r), .g_out(hdmi_g), .b_out(hdmi_b),
    .hs_out(hdmi_hs), .vs_out(hdmi_vs), .de_out(hdmi_de)
);

// (OSD overlay mixer removed, Atari816.) The output register stage is kept so the
// pixel/sync alignment and the TMDS path timing stay as they were.
wire [7:0] mixed_r = hdmi_r;
wire [7:0] mixed_g = hdmi_g;
wire [7:0] mixed_b = hdmi_b;

reg [7:0] mixed_r_reg = 8'd0;
reg [7:0] mixed_g_reg = 8'd0;
reg [7:0] mixed_b_reg = 8'd0;
reg       hdmi_hs_reg = 1'b0;
reg       hdmi_vs_reg = 1'b0;
reg       hdmi_de_reg = 1'b0;

always_ff @(posedge clk_pix) begin
    mixed_r_reg <= mixed_r;
    mixed_g_reg <= mixed_g;
    mixed_b_reg <= mixed_b;
    hdmi_hs_reg <= hdmi_hs;
    hdmi_vs_reg <= hdmi_vs;
    hdmi_de_reg <= hdmi_de;
end

// `define USE_TEST_PATTERN

`ifdef USE_TEST_PATTERN
wire [7:0] tp_r, tp_g, tp_b;
wire       tp_hs, tp_vs, tp_de;
test_pattern_720p tp (
    .clk_pixel(clk_pix),
    .rst_n    (hdmi_rst_n),
    .r_out    (tp_r),
    .g_out    (tp_g),
    .b_out    (tp_b),
    .hs_out   (tp_hs),
    .vs_out   (tp_vs),
    .de_out   (tp_de)
);
`endif

// ─────────────────────────────────────────────────────────────────────────────
// HDMI output (video + audio data islands)
// ─────────────────────────────────────────────────────────────────────────────
hdmi_audio_out #(
    .DVI_OUTPUT(1'b0),
    .NO_DATA_ISLANDS(1'b0)
) hdmi (
    .clk_pix    (clk_pix),
    .clk_5x     (clk_5x),
    .rst_n      (hdmi_rst_n),
`ifdef USE_TEST_PATTERN
    .r          (tp_r),
    .g          (tp_g),
    .b          (tp_b),
    .hs         (tp_hs),
    .vs         (tp_vs),
    .de         (tp_de),
`else
    .r          (mixed_r_reg),
    .g          (mixed_g_reg),
    .b          (mixed_b_reg),
    .hs         (hdmi_hs_reg),
    .vs         (hdmi_vs_reg),
    .de         (hdmi_de_reg),
`endif
    .audio_l    (audio_l_out),
    .audio_r    (audio_r_out),
    .smp_tgl    (hdmi_smp_tgl),
    .tmds_p     (tmds_p),
    .tmds_n     (tmds_n),
    .tmds_clk_p (tmds_clk_p),
    .tmds_clk_n (tmds_clk_n)
);

/*
DVI_TX_Top hdmi (
    .I_rst_n       (hdmi_rst_n),
    .I_serial_clk  (clk_5x),
    .I_rgb_clk     (clk_pix),
`ifdef USE_TEST_PATTERN
    .I_rgb_vs      (tp_vs), 
    .I_rgb_hs      (tp_hs),    
    .I_rgb_de      (tp_de), 
    .I_rgb_r       (tp_r),  
    .I_rgb_g       (tp_g),  
    .I_rgb_b       (tp_b),  
`else
    .I_rgb_vs      (hdmi_vs_reg), 
    .I_rgb_hs      (hdmi_hs_reg),    
    .I_rgb_de      (hdmi_de_reg), 
    .I_rgb_r       (mixed_r_reg),  
    .I_rgb_g       (mixed_g_reg),  
    .I_rgb_b       (mixed_b_reg),  
`endif
    .O_tmds_clk_p  (tmds_clk_p),
    .O_tmds_clk_n  (tmds_clk_n),
    .O_tmds_data_p (tmds_p),
    .O_tmds_data_n (tmds_n)
);
*/

// Pulse-stretch SIO line activity to ~19 ms so the eye can see it.
localparam [21:0] SIO_STRETCH = 22'h07FFFF; // 2^19-1 @ 27 MHz ≈ 19 ms
reg [21:0] sio_tx_stretch  = 22'd0; // our drive -> Atari activity
reg [21:0] sio_rx_stretch  = 22'd0; // Atari -> drive activity
reg [21:0] sio_cmd_stretch = 22'd0; // SIO command frame (active-low line)
always_ff @(posedge sys_clk) begin
    if (!sio_rx_data_in)    sio_tx_stretch <= SIO_STRETCH;
    else if (sio_tx_stretch) sio_tx_stretch <= sio_tx_stretch - 1'b1;

    if (!sio_txd_sys)       sio_rx_stretch <= SIO_STRETCH;
    else if (sio_rx_stretch) sio_rx_stretch <= sio_rx_stretch - 1'b1;

    if (!sio_command_sys)    sio_cmd_stretch <= SIO_STRETCH;
    else if (sio_cmd_stretch) sio_cmd_stretch <= sio_cmd_stretch - 1'b1;
end

// ── PRODUCTION LEDs ──────────────────────────────────────────────────────────
// (active low; leds_n[4:1] → pins 17,18,19,20 → physical LED2,LED3,LED4,LED5)
//   LED2 (leds_n[1]) = SIO data activity : flickers while disk bytes move (either
//                      direction, ~155 ms stretch). During a load this stays busy;
//                      if it goes dark mid-load while LED4 keeps flashing, the
//                      handler is stuck.
//   LED3 (leds_n[2]) = roms_loaded : ON once the Atari has booted
//   LED4 (leds_n[3]) = SIO command frames : flashes once per drive request
//   LED5 (leds_n[4]) = sysblink : ~0.8 Hz free-run heartbeat (FPGA alive baseline)
reg [24:0] sysblink = 25'd0;
always_ff @(posedge sys_clk) sysblink <= sysblink + 25'd1;
wire sio_data_act = (sio_tx_stretch != 0) || (sio_rx_stretch != 0);
// Feed the capture-side indicator (declared up at the scandoubler instantiation).
assign sio_ind_data = sio_data_act;
assign sio_ind_cmd  = (sio_cmd_stretch != 0);

assign leds_n = ~{ sysblink[24], (sio_cmd_stretch != 0), roms_loaded, sio_data_act };


endmodule
