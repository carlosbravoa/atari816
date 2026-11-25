# Known issues

## OPEN: the picture is lost now and then (the monitor shows "no signal", then its HDMI banner)

Reported 2026-11-24, "it has always happened": while playing, in FreeCell, and once seen with
the Desktop idle and nobody using the serial link. Right after a loss the board responds to
ping, `shot816` shows the framebuffer intact and Horizon's uptime runs on: the machine is fine,
the HDMI output drops for the monitor and comes back.

What the RTL does (read 2026-11-24):
- The output is a custom raster sent as 720p60 (the AVI infoframe carries VIC 4): 1572 x 760 at
  71.71875 MHz (27 x 17/4 x 25/8 / 5), HFP/HS/HBP 72/80/140, VFP/VS/VBP 10/5/25, +/+ sync,
  60.03 Hz, 45.62 kHz lines (CEA: 1650 x 750 at 74.25 MHz, 110/40/220, 5/5/20, 60.00 Hz).
  The HDMI pins are LVDS25 outputs (`constraints/tang_nano_20k.cst`), as on every Tang Nano.
- No register write changes the raster: hx free-runs; vy is changed only by the genlock
  (`scandoubler_480p.sv`, `if (sof_pix) vy <= V_LOCK`), which jumps only when the classic
  machine's frame start comes at another moment (after its freeze is lifted, a reset). The
  classic machine is frozen while the desktop is shown.
- `hdmi_rst_n = hw_reset_n && pll_locked` (`tang_top.sv`): the HDMI PLL's raw LOCK resets
  the clk_pix CLKDIV, the OSER10s and the raster; `hw_reset_n` has only the power-on timer, S1
  and the *core* PLL's lock. A glitch of the HDMI PLL's LOCK (that PLL is fed by the core
  PLL's output) drops the picture and nothing else: the leading suspect.

The diagnostic bitstream (`src/hdmi_diag.sv`; sticky counters on sys_clk, cleared only by
power-on and S1, counting once both PLLs have been locked for 78 ms):
- LEDs (with `HDMI_DIAG_LEDS`, on in `tang_top.sv`; lit = it happened at least once):
  LED2 (pin 17) the HDMI PLL lost its lock, LED3 (pin 18) the core PLL lost its lock, LED4
  (pin 19) a frame of the wrong length was sent, LED5 the heartbeat as before. (The SIO
  activity, "ROMs loaded" and SIO command LEDs are gone in this build.)
- `python3 core/tools/atari.py hdmidiag` (FWPEEK of the I/O processor's registers, no 65C816
  software): HDMI PLL lock drops, core PLL lock drops, hdmi_rst_n low pulses, frames whose
  length is not 449,777 +- 4 sys_clk cycles (and the last bad length: -592 is one line short),
  genlock jumps that moved vy, frames measured. `--watch 5` prints a timestamped line at each
  change: note the time of a loss and compare.
- Registers (I/O processor, read-only, 32-bit little-endian): $0200_00EC frames measured;
  $0200_00F0 byte 0 HDMI PLL lock drops, 1 core PLL lock drops, 2 hdmi_rst_n pulses, 3 flags
  (bit 0 HDMI lock lost, 1 core lock lost, 2 hdmi_rst_n pulse, 3 bad frame, 4 genlock jump,
  5 armed, 6 HDMI PLL locked now, 7 VS running now); $0200_00F4 bits 0-15 bad frames, 24-31
  genlock jumps; $0200_00F8 the last bad frame's length, $0200_00FC the last frame's length
  (sys_clk cycles). 8-bit counts stop at 255, 16-bit at 65535.
- Test: `core/sim_a816/run_hdmi_diag.sh` (Verilator; forced lock glitches of 5 ns and 100 ns,
  a frame one line short, a genlock jump, S1, the filter below).

Reading a loss: HDMI PLL lock drops went up -> the PLL (fix candidate 1); nothing went up and
the frame lengths are all nominal -> the raster and the reset are innocent: signalling (cable,
monitor, LVDS levels) or the data islands (candidate 2); bad frames or genlock jumps without a
lock drop -> the genlock.

A/B builds (each one change in `src/tang_top.sv`):
1. `define FIX_LOCK_FILTER` (commented out next to `HDMI_DIAG_LEDS`): drops of the HDMI PLL's
   lock up to 100 us no longer reset the HDMI side; a longer loss still does (the serializer
   and its CLKDIV must be restarted together after a real loss, or the 10-bit words can stay
   misaligned), released after 1 ms of lock. The counters still count every drop.
2. The `hdmi_audio_out #(.DVI_OUTPUT(1'b0), .NO_DATA_ISLANDS(1'b0))` instance: `NO_DATA_ISLANDS`
   1 sends HDMI without packets (no infoframes, no audio over HDMI); `DVI_OUTPUT` 1 plain DVI
   (no packets, no guard bands; no HDMI audio). If the losses stop, the packets are the cause.

## OPEN: Horizon without keyboard and mouse after F12 during an ATR load

Reported 2026-11-21 (REV $0C, Horizon 0.27, but older than both): F12 pressed while the classic
Atari loads a disk image returns to a desktop that takes no input. Not reproduced with keys
injected over the PC link (30 tries on `acid800.atr` and `DOS25.atr`, single density). One
cause was found by reading and is fixed in the firmware, not yet confirmed as *the* cause: the
SIO transmitter is clocked by the classic POKEY tick, which stops with the freeze, and
`sio_tx_byte` waited without a bound for room in its 256-byte FIFO. A reply longer than the
FIFO (a 256-byte sector: 259 bytes) sent to a machine that has just been frozen hung the
firmware, and Horizon's keyboard and mouse come through the firmware. It now stops waiting after
5 ms. Since the fast disk (bring-up log, step 26) the OS's sector reads no longer use the
serial port at all, so only writes and programs with their own serial routines are still
exposed. If it happens again: does `core/tools/atari.py status` still return a status line (firmware running or
not), and which disk image was it?

## OPEN: Horizon restarted by itself when a second disk was attached (seen once)

Seen once, 2026-11-21, on the board (v0.27.1 bitstream, Horizon 0.27, `fastdisk=1`,
`basic=0`). Steps: a disk attached, it did not boot, F12 back to Horizon, "Attach disk..."
with another disk: the whole Horizon start-up ran again. The firmware did not restart (its
uptime went on), so the 65C816 was reset or jumped to its start. The same steps with the
same disk worked afterwards. Ruled out by reading: the fast disk's ROM (physical 0x1F2000 =
bank $2F) is inside the banks Horizon reserves ($20-$3F). Not known: the cause. If it comes
back: note the two files, whether the first was started with "Restart Atari" or only F12,
and try `fastdisk=0`.

## ROADMAP: freeze at a cycle or frame boundary

Horizon's freeze (SV\_CTRL.FREEZE\_REQ) stops the classic machine at whatever clock it arrives.
Two consequences: a POKEY write of the 6502 in the very clock where the freeze begins is lost
(REV $0C routes POKEY's inputs to the native side in that clock), and a disk transfer is cut
in the middle of a frame (the OS's retries recover it). The freeze should take effect at the
end of a 6502 cycle and, better, between SIO frames; FROZEN would then show Horizon when it took effect.

## ROADMAP: "With BASIC / Without BASIC" in the Atari window

Asked 2026-11-21. The Atari window of the Desktop (where disks are attached and ejected)
should also offer the disk-boot choice that Settings has (`basic` in `/atari.ini`), so it
can be changed where the disk is attached.

## FIXED (v3.2): about one reset in fifteen left the machine stalled

Any reset path (power-on, Hard Reset, Boot OS/BASIC, cartridge attach, F9/Soft, PC Link
reset) occasionally released the 6502 into a stall: black or stale screen, no keyboard, jiffy
clock frozen, firmware still running. Measured over 90 mixed resets in v3.1.2: 2 to 3 stalls per
30. Root cause: the core's asynchronous reset was released straight from a register in the
firmware's 27 MHz clock domain, so the release landed at an arbitrary point of a core clock
cycle. v3.2 releases it synchronously in the core clock (two flops): 90 mixed resets, zero
stalls. As a safety net the firmware also runs a boot watchdog: it plants a sentinel in RTCLOK
before releasing the core and, if the OS has not overwritten it 2.5 s later, repeats the same
reset (bounded, logged as `boot: watchdog retry N`, counted in the status line's `br:` field).

## RESET (F9 / Soft Reset) inside a multi-game cartridge lands in BASIC or Self Test

This is faithful, not a bug. The XL/XE cartridge port has no reset line, so a cartridge
cannot detect the RESET key; a multicart that switched itself off to run a game (Atarimax
compilations do this) is still off after RESET, and the XL OS then boots BASIC (or Self Test if
BASIC is disabled). Altirra does exactly the same on F5. Use **Hard Reset** instead: since v3.0
it power-cycles the emulated cartridge (bank 0, enabled) and brings the multicart menu back,
like a real power cycle (Altirra Shift+F5).

## F12 (OSD menu) can be unresponsive while a PC serial session is engaged

With the PC Link actively engaged (v2.5+; e.g. a live keyboard session or app
connection), the F12 menu key on the physical keyboard sometimes doesn't open the
OSD. Workaround: the S2 button on the board always works, and closing the PC
session restores F12 immediately. Under investigation.


## FIXED (v2.4): unreliable disk writes (ERROR 139, corrupted disks, damage to the SD card)

Writing to mounted disks (SAVE from DOS/BASIC, formatting) was broken in several
stacked ways: writes to D2: failed with ERROR 139, "successful" writes could leave the
disk image's filesystem inconsistent, and, worst, long write sessions could corrupt
the **SD card's own FAT filesystem** (in extreme cases wiping it). Root causes, all
fixed in v2.4 and verified on hardware + a host-side FatFs test suite (`test/fatfs_host/`,
removed in Horizon 0.24: the firmware functions it tested, the OSD's "New blank disk" and the H:
device, are gone; `test/fdisk_host/` tests the folder disk on the same kind of image):

- the SIO write handler performed the slow SD write *before* sending the data-frame ACK,
  blowing the OS's ACK window → retry storms and half-applied multi-sector operations;
- a read-only mounted image failed writes with a bare NAK instead of reporting
  write-protect (now: auto-clear of PC-inherited read-only attributes, "(RO)" marker,
  status write-protect bit, error 144);
- mounting the same image on both drives created two write handles on one file
  (illegal in FatFs, can corrupt the volume; now the second mount is forced read-only);
- an out-of-range sector number made the firmware allocate the gap on the SD card
  (one bad sector number grew a 92 KB ATR to 8+ MB; now rejected as a real drive rejects it);
- a firmware stack overflow could corrupt filesystem state during deep menu operations
  (stack usage reduced; a canary now flags it on the OSD debug line).

If your SD card was damaged by an earlier version: reformat it (full FAT32) and recopy
your files. v2.4 also adds DOS FORMAT support and OSD "New blank disk" creation.

## FIXED: mode-8 fine scrolling stuttered (Ninja Commando / Draconus marquees)

Big-letter marquee scrollers (ANTIC mode 8 / GRAPHICS 3 with horizontal fine scroll)
moved in coarse 4-colour-clock jumps instead of moving smoothly. On photos this showed
as per-scanline "shear" of the moving band. Root cause: an upstream Atari800_MiSTer
ANTIC bug: HSCROL bit 1 was applied twice in the mode-8 pixel path (DMA fetch timing
*and* an extra shifter phase-select), summing to one full pixel period, i.e. no visible
effect. Fixed here (one line in `antic.vhdl`, `enable_shift` slow-shift case) and
hardware-verified 2026-07-04: Ninja Commando's title marquee now scrolls smoothly.
Only display lists using mode 8 *with* horizontal scrolling are affected by the change;
all other modes are bit-identical. (Current MiSTer still has this bug.)

## FIXED (v3.1.2): games froze when played with the keyboard as joystick (impossible stick values)

Found 2026-09-20 with Tiger Attack (freezes within seconds of keyboard play, never with a DB9
stick, never on MiSTer/Altirra). Root cause: the arrow-keys-as-joystick mode passed two
overlapping key presses straight through, so left+right or up+down for a few milliseconds
presented a STICK value a mechanical joystick can never produce. Games that index tables by
the raw stick nibble run off the end of their table and crash (Tiger Attack ends up executing
zero page and hitting a JAM opcode; the stack wraps). Fix: on the keyboard path opposite
directions cancel (both pressed = centre); the DB9 path is untouched. The earlier "PAL
title" and "core timing" theories for this game were wrong.

## Some PAL vertical-scrolling games glitch (this is an NTSC-only machine)

A few demanding titles show garbled sprites, a jumpy/jittery image, or freezes **during
play**:

- **Tiger Attack** (Atari UK, 1988): minor image tearing while scrolling; plays fine otherwise
  (the freezes once blamed on it were the keyboard-joystick bug, fixed in v3.1.2).
- **Astro Droid** (Red Rat Software, 1987): vertical jitter; sprites garbled / wrong colours.

**Most likely cause: these are PAL games, and this build is NTSC-only.** Both are PAL
British budget titles built around **PAL ANTIC timing** (312 lines / 50 Hz) and aggressive
**per-frame vertical fine scrolling** (writing `VSCROL` mid-frame, often from display-list
interrupts). Run that on an **NTSC** machine (262 lines / 60 Hz) and the scroll regions,
DLI line targets and sprite vertical positions no longer line up → exactly these symptoms.
A real Atari (or MiSTer) set to **NTSC** would behave the same way.

It is **not a loading problem** (Astro Droid runs from cartridge; the issue is gameplay) and
**not a memory/video-path bug** on our side: the SDRAM crossing is synchronous and the core
stalls on a completion handshake, so the CPU and ANTIC never receive wrong data. Slow SDRAM only
slows the machine and does not corrupt it.

**Why other scrollers are fine:** games like **River Raid** are NTSC-friendly and use *coarse*
scrolling (one LMS-pointer update during VBLANK), which is not timing-sensitive, so they are unaffected.

### Status: PAL support is not planned
Switching the core to PAL is **not a simple flag**: it changes the machine clock (1.7734 vs
1.7898 MHz), which cascades through `clk_mem`/SDRAM, `clk_pix`/`clk_5x` and the **genlocked
scandoubler** (whose HDMI mode is hard-tuned to NTSC framing: 1216×786 = 3 × 262 lines; PAL's
312 lines would be 936 output lines = a different video mode and PLL). It's effectively a
second complete clock + video configuration. Given these are obscure PAL titles on an NTSC
reference machine, PAL support is **deferred / not planned**.

**To confirm the diagnosis:** run the same games on MiSTer (or a real Atari) **set to NTSC**.
If they glitch the same way → confirmed PAL/NTSC mismatch (nothing to fix here). If they run
clean on NTSC hardware → reopen as a core/wrapper investigation.

## VBXE is not supported (and cannot be on this board)

The upstream MiSTer core ships a VBXE implementation (by Wojciech Mostowski, 2025). This
tree does not include it: the VBXE outputs inside `atari800core.vhd` are tied to their
"no VBXE" values. The Tang Nano 20K does not have the resources for it:

- **VRAM.** VBXE needs 512 KB of video RAM, which MiSTer keeps in FPGA block RAM. The
  GW2AR-18 has about 103 KB of block RAM in total and this design already uses 92% of it.
  Moving the VRAM to SDRAM would mean a new arbiter client streaming one byte per hi-res
  pixel for the overlay plus XDL fetches plus blitter traffic, concurrent with the CPU and
  ANTIC: the same bandwidth and arbitration limit that ended the SDRAM frame-buffer attempt.
- **Video path.** With VBXE on, the core emits 24-bit RGB with per-pixel palette selection
  and up to 640-pixel-wide overlays. Our scandoubler ring stores an 8-bit GTIA colour code
  at 352 pixels per line and scales by an integer 3×. Supporting VBXE output means a wider,
  deeper ring, the VBXE palette moved to the pixel-clock side and non-integer scaling,
  all new logic on the HDMI path, which has no headroom left.
- **Logic.** The VBXE engine is roughly 2300 lines of VHDL on a chip at 88% logic usage.

### Status: WONTFIX on the Tang Nano 20K
There is no useful partial VBXE (every feature software uses depends on the 512 KB VRAM).
On this board, the Atari816's own video chip (Marga) provides extended graphics instead.

## FIXED IN THE PC TOOL (confirmed on the board, 2026-11-22): `shot816` showed a black picture for Xargon

2026-11-22. Xargon on the board plays correctly (picture, OPL2 music, speed: seen on the
monitor), but `atari.py shot816` returned an all-black 320x180 picture while it runs (video
state: mode 2, base $480000, stride 512). Digger and the Desktop were captured correctly.

**Cause** (found in the emulator, not on the board): not the palette, not the page flip as
such. Xargon shows its pages through Marga's scroll registers (REV $0B fine scrolling,
Horizon's `fs_scroll`): its framebuffer holds both pages (880 rows of 512 bytes from
$480000), and the picture is the rows from `y` = page + 120 + 11 (rows wrapping as rings,
`x` the playfield's horizontal scroll), then from the split line the status bar's rows
(400 or 840). The kernel's video-state block ($01:F000, version 1) holds NV_BASE and
NV_STRIDE but not the scroll set, so `a816_screen.py` read rows 0-179 from the base:
rows above the view that Xargon never draws, black. Digger also enters full screen with a
split, but its scroll set leaves every row where it is (y 0, the split's y2 = the split line),
so reading from the base happened to be right.

**Fix** (`core/tools/a816_screen.py`): the kernel's own copy of the scroll set (`fs_scr`,
with `fs_act` and `k_rev`) is found by the code that uses it in the kernel's second segment
($00:E100: `fs_regs`, `fs_noscroll`; one match each in today's kernel), and the picture is
made row by row as Marga walks the rows (`emu/nvc.c`'s rules: the row of line 0, the
pixels skipped with the horizontal wrap, the split's second set, the vertical wrap). Where
the code is not found it falls back to the rows from the base. Checked against emu816's
own pictures with `emu816 --dump-ram` and `emu/tests/shot816.py`: Xargon at 12, 33 and 42 s
of its test game (title and level 1: `scroll=y131,x0,hwrap,split280:y400`, `y623,x32...`,
`y245,x216...`) identical pixel for pixel (without the fix 46,001-57,585 of 57,600 pixels
differ); Digger, the Desktop and the text console identical too. `emu/tests/run_tests.sh`
keeps the Desktop and console checks. A cleaner fix later: the scroll set in the
video-state block (a version 2, a kernel change of a few bytes).

**To confirm on the board**: run Xargon, play into level 1, then `python3 core/tools/atari.py
shot816 x.png --scale 2`; the line it prints has `scroll=y...,x...,hwrap,split280:y...`
and the picture is the game. `--no-scroll` gives the old reading (black) for comparison.
