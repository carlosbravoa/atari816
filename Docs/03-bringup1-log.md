# Atari816: bring-up 1 log

2026-11-16. Work is in `core/` (a clone of `atari800_tang_nano20k`), branch `atari816/bringup1`, nothing committed or pushed yet.

## Status

| Step | State |
|---|---|
| 1. Fresh resource count | Done (below) |
| 2. Branch | Done |
| 3. 65C816 core | Done, simulated |
| 4. Cache + arbiter client | Done, simulated; BL2 bursts, not BL4 (see deviations) |
| 5. I/O page, loader, reset stub | Done |
| 6. Output on the PC Link log | Done, seen on hardware |
| 7. Regression on hardware | Atari boots to BASIC with the 65C816 running. **ACID800, games and HDMI cold start still to do.** |

Flashed 2026-11-16 (commit `76429ae`, payload e6bd0bbf).

## Hardware result (2026-11-16)

```
816: ATARI 816 BRING-UP 1
816: ID 81 REV 01 BANKS-1 0F
816: RAM ERRORS 0000
816: LOOP US 00005946
816: READ US 000085D4
816: MVN US 00006654
816: DONE
```

| Test | Measured | At a flat 14.34 MHz | Effective speed |
|---|---|---|---|
| RAM test, 14 banks x 64 KB, Atari running | 0 errors | | |
| Tight loop, 327,680 cycles | 22,854 us | 22,856 us | 100% |
| Sequential read, 32 KB | 34,260 us | 31,990 us | 93% |
| MVN copy, 32 KB | 26,196 us | 15,995 us | 61% |

To see the log again without pressing S1: start `tools/atari.py log`, then `openFPGALoader -b tangnano20k --reset`.

## Resource count

| | v3.4 main (baseline) | bring-up 1 |
|---|---|---|
| Logic (LUT+ALU) | 13,859 / 20,736 (67%) | 13,560 (66%) |
| CLS | 88% | 85% |
| Block RAM | 42 / 46 | **46 / 46** |
| Worst slack (HDMI canary, want ≥ 0.5 ns) | 3.351 ns | 1.302 ns |
| Atari → SDRAM crossing slack | 0.000 ns | 10.7 ns |
| clk_core Fmax (needs 28.69) | — | 29.7 MHz |

The design doc assumed 11.3 K LUTs in use; the real baseline was 13.9 K.

What the new blocks cost: 65C816 about 1,750 LUT+ALU and 2 block RAMs; cache, bus logic and I/O page about 430 LUT and 2 block RAMs.

## Findings

1. **Block RAM is the go/no-go item for the Tang Nano 20K, not logic.** All 46 are now used. The firmware RAM takes 32 of them. The NVC and the classic frame buffer need line buffers, and a full 8 MB cache tag needs a third cache block. Nothing more fits until the firmware RAM shrinks or something else gives blocks back.
2. **The 65C816 is small** (design estimate was 3 to 5 K LUTs). Its microcode ROM was 6 block RAMs; `src/a816/mcode_pack.py` repacks it to 2 (only 273 distinct microinstructions). Checked entry by entry and by identical cycle counts in simulation.
3. **This 65C816 core has no ABORT.** `IsABORTInterrupt` is tied to 0. FREDDIE II protection (the next milestone) needs that added to the core.
4. **Turbo (28.7 MHz) is not available with this structure.** The cache lookup takes the second clk_core cycle of each CPU cycle, and clk_core closes at 29.7 MHz with almost no margin.
5. **Speed in simulation** (SDRAM latency modelled, not measured): tight loop exactly 14.34 MHz; sequential reads about 10% slower; MVN copy about half speed, because every write goes through to SDRAM.

## Deviations from the plan (need Carlos's OK)

- **BL2, not BL4.** The base repo's notes say BL4 at half rate starved ANTIC on hardware and full-rate bursts corrupt data; BL2 half-rate is the proven one and the controller still has it. So cache lines are 8 bytes. `docs/framebuffer_feasibility.md` predates that finding. This also matters for decision 10: the same notes record the SDRAM frame buffer as tried for several days and abandoned.
- **Ultimate-1MB RTC removed from the Atari core** (`rtl/common/a8core/atari800core.vhd`): 1.9 K LUTs, and this board ties its time input to zero. $D3E2 now reads $FF. Easy to put back, but then the build is at 90% CLS and failed timing.
- **The Atari's SDRAM address, data and mask are now registered once** in `tang_top.sv` before the controller. That path had 0.0 ns slack in v3.4 and failed by 7 ns once the arbiter grew a third client. This touches the Atari's proven memory path, so ACID800 on hardware is the real test.
- **1 MB window for now:** native $00:0000–$0F:FFFF sits at physical 0x300000 (firmware address 0x100000 + native). Bank 0 of a flat map would land on the Atari's RAM; FREDDIE II fixes that properly.
- **Debug port** at $00:DEF0 (data) and $00:DEF1 (bit 7 busy). Not in the register spec; bring-up only.
- Arbiter priority is Atari > PicoRV32 > 65C816.

## How to test on the board

```
cd core
make -C sw/a816                         # builds sw/a816/A816.BIN
# copy A816.BIN to the SD card root, then flash:
openFPGALoader -b tangnano20k impl/atari800_tn20k/impl/pnr/atari800_tn20k.fs
python3 tools/atari.py log
```

Expected in the log after boot (times will differ):

```
816: loaded 467 bytes, run
816: ATARI 816 BRING-UP 1
816: ID 81 REV 01 BANKS-1 0F
816: RAM ERRORS 0000
816: LOOP US 00005948
816: READ US ...
816: MVN US ...
816: DONE
```

`LOOP US` should be $5948 (22,856 µs = 14.34 MHz). Without `/A816.BIN` the 65C816 stays in reset and the machine should behave as v3.4. Then: ACID800, a few games, HDMI cold start.

Simulation: `core/sim_a816/run.sh` (Verilator).

## Open questions, updated

- Cache size: 4 KB, fixed by block RAM. Hit-rate numbers need hardware.
- Turbo: no (finding 4).
- New: where the next block RAMs come from (finding 1).
- New: a write buffer for the 65C816 would roughly double stack-heavy and copy speed.

## Step 2: block RAM freed (2026-11-16, commits `8019a44`, `14b8b90`)

Block RAM is now **30 / 46** (was 46 / 46). Logic 13,887 (67%), HDMI canary 2.1 ns.

No firmware feature was removed. Cutting features alone could not reach 32 KB without losing both the OSD and H:, so the firmware is split instead:

| Part | Size | Where it runs | Contents |
|---|---|---|---|
| Hot | 21.4 KB of 28.7 KB usable | 32 KB block RAM | Boot, cold loader, SIO, SD, FatFs I/O, H:, PC Link poll, all data and stack |
| Cold | 19.0 KB | SDRAM at firmware address 0x10000 | OSD menus, mounting, cartridges, options, the rest |

- The cold part is stored in SPI flash at 0x500000 and copied to SDRAM at boot. The hot image carries the cold image's CRC-32, so a stale copy is refused with a message on screen and on the serial log.
- **Flashing is now two files:** `flash_it.sh` writes `firmware/cold.bin` and the bitstream. They must come from the same build.
- To move a function into block RAM, add its name to the hot list in `firmware/baremetal.ld`.
- Firmware is now rv32ic (PicoRV32 `COMPRESSED_ISA`, +390 LUTs) with `FF_FS_TINY`. LTO is off.

Bugs found on the way, both latent in the base core:
- `fw_bram` acknowledged back-to-back transfers with stale data. Only compressed-instruction fetches do that.
- `spiflash` never reached its register mode because the old auto-load was tied off.

Checked on hardware (RAM load): boots, ROMs load, 65C816 test passes. **Not checked: OSD menus, disk mounts, H:, cartridges, games.** Cold code runs about 4 times slower, so the OSD may feel different.

`openFPGALoader` RAM loads fail if `atari.py log` has the serial port open at the same time.

## Step 3: FREDDIE II, native side (2026-11-16, commit on `atari816/bringup1`)

Done and passing in simulation and on the board (RAM load):

```
816: ATARI 816 FREDDIE II TEST
816: REV 02 BANKS-1 7F
816: WPVEC OK
816: MODE OK
816: FAULTS OK
816: MEMORY OK
816: WINDOW OK
816: DONE
```

The test (`sw/a816/freddie2.s`) runs a small kernel that drops to user mode and has the user code try 11 forbidden things: write a read-only bank, read and write another task's bank, an invalid bank, the I/O page, kernel bank 0, a read-modify-write, a block move, a jump into a foreign bank, and one fault the kernel fixes so the instruction re-runs. It checks cause and address of every fault, that no refused write landed, and that registers came back intact.

Cost: logic 14,099 (68%), block RAM 32 / 46, clk_core 29.13 MHz (needs 28.69, so this is the tight one now), HDMI canary 1.2 ns.

What was built:
- **ABORT in the 65C816 core.** Registers are saved at each opcode fetch and restored when an aborted instruction ends, so the stacked PC is the faulting instruction and it can be re-run.
- **8 MB native map.** `RAM_BANKS` reads $7F.
- **Registers $00:D800 to $00:D809** as in the spec, bank table in one block RAM.
- **Bank 0 window.**

Native map on this board (physical SDRAM is shared, so not all 8 MB is free yet):

| Native banks | Contents |
|---|---|
| $00 to $0F | Free RAM (kernel area) |
| $10 to $1F | Free, except $11 (I/O processor cold firmware) |
| $20 to $3F | Classic machine: RAM, extended RAM, OS, BASIC |
| $40 to $7F | Cartridge images (free when no cartridge is loaded) |

Differences from the register spec (need Carlos's OK, spec not edited):
- **Mode is a stack, not a single armed flag.** A vector pull pushes the current mode; an RTI in supervisor mode pops it; USER_ARM is the top of the stack. The single flag in rule 2 breaks if an NMI lands between arming and the RTI. Eight levels deep.
- **ABORT_ADDR and ABORT_CAUSE describe the first refused access of the instruction**, not the last.
- **A refused read returns $EA** and a refused access blocks all later writes of the same instruction.
- **A refused push during interrupt entry does not nest.** The push is dropped and ABORT_CAUSE stays set; the handler must check it.
- WP_VEC works without PROT_EN.

Not done yet: the classic map (CM_ registers in the Atari's address decoder), native reads of classic memory can be stale (the 6502 writes behind the cache), interrupt controller, write buffer.

## Step 4: system block, mailbox, input, emulator (2026-11-16, commits `63a898e`, `eb42a19`, `7cf2bee`)

All verified on the board with the self test (`A816.BIN`: 10 OK lines) and `KBTEST.BIN`.
Cost so far: logic 14,924 (72%), block RAM 32 / 46, clk_core 28.87 MHz (needs 28.69: tight), HDMI canary 2.7 ns.

What was built:
- **System block:** IRQ_STATUS / IRQ_EN / NMI_STATUS, both timers, watchdog (2 s), UPTIME.
- **Mailbox** ($00:DD00): OPEN, CLOSE, READ, WRITE, SEEK, STAT, READDIR, MKDIR, DELETE, RENAME, LOAD. Four open files.
- **Input:** key events on the response ring, KB_ROUTE, JOY_PORT / JOY_TRIG, F12 = SYSTEM_KEY NMI.
- **Boot:** the I/O processor loads `/SYSTEM/HORIZON.SYS`, else `/A816.BIN`, to $01:0000.
- **Dev loop:** `tools/atari.py run816 FILE` sends a program over PC Link, restarts the 65C816 and shows its log.
- **Emulator** in `emu/` (`make test`: 15 of 15). CPU checked against 508,400 SingleStepTests cases; FREDDIE II checked against the RTL trace. About 7x real speed.

Bugs found by the emulator work, fixed and checked on the board:
- A task could make the kernel write 4 bytes into kernel memory (COP with the stack pointer aimed at kernel RAM). A BRK/COP whose push was refused no longer enters supervisor mode.
- Emulation-mode IRQ/NMI pushed B = 1. Now B = 0, like the real chip.
- Firmware address translation was wrong for banks $40 to $7F.

Additions and differences from the register spec (need Carlos's OK, spec not edited):
- **KB_ROUTE resets to 1** (classic machine has the keyboard) so the Atari core works before Horizon runs.
- **CACHE_FLUSH at $00:D80A** (new register): drops the 65C816's cache after the I/O processor wrote RAM. The mailbox does this by itself before a response becomes visible.
- **IRQ_STATUS bit 6 (IOP) is a live level** (response ring not empty), not a latched bit.
- **STAT** returns {u32 size, u8 attr, u32 time}. **READDIR** ARG0 = entries to skip; entries are {u32 size, u8 attr, u8 namelen, name}.
- **KEY event:** ARG0 = HID usage, ARG1 low = modifiers, bit 8 = down. Modifier keys are also sent as usages $E0 to $E7.
- **Result codes:** 0, FatFs codes, $80 bad handle, $81 bad address, $82 unsupported.
- Bank $10 cannot be reached by the I/O processor.

Testing note: programs must wait for DBG_STAT bit 7 = 0 before each DBG_OUT byte, and the log must be read while keys are injected, or output is lost.

## Decision (Carlos, 2026-11-16): desktop video

The desktop is **528x360, shown 2x in the current 1056x720 raster**. No pixel clock change, no second raster. Reason: the Atari's CPU/video memory timing and the HDMI timing were hard to reach and must not be disturbed.

## Step 5: Horizon, video, timing (2026-11-16, commits `ba3dbfe`, `c4ab543`, `74f2eaf`)

- **Horizon 0.1** (`horizon/`, written by an Opus agent from my design) runs on the board: tasks, preemption, memory protection, files, ports, keyboard, o65 programs, a shell. Its test run on the board matches the emulator.
- **NVC** (`core/src/a816/a816_nvc.sv`): 528x360 desktop at 2x in the current raster, modes 8 bpp / 4 bpp / 264x180, palette, pointer. It reads RAM through the 65C816's SDRAM port, one line ahead; the arbiter and the raster are unchanged. On the board no line was fetched late in any mode with the Atari running. **The picture itself has not been seen by anyone yet** (`NVTEST.BIN` shows a test picture for about 30 s).
- **Timing:** microcode-to-register paths in the 65C816 are two-cycle paths and are now constrained as such. clk_core 29.3 MHz with the NVC in (needs 28.69). clk_pix is the tight one now: slack 0.26 ns on the OSD mix path (this already includes the 1 ns margin in the constraints).
- **NMI hold** (REV 04): after an entry from user mode NMI is held until the kernel writes FR_CTRL. Note for kernel writers: if NMI_STATUS is still set when the hold is released, a second NMI is taken.
- **F12:** while Horizon is alive F12 is its system key; the old menu then opens with Shift+F12 or the S2 button.
- **Mouse events** ($E1) are implemented in the firmware and can be injected over PC Link. The USB mouse frame parsing is untested (no mouse was connected).

More differences from the register spec (need Carlos's OK):
- Desktop is 528x360, so NV_STRIDE resets to 528, PTR_X is 0 to 527, modes are 528x360x8, 528x360x4, 264x180x8.
- NV_STRIDE must be a multiple of 8 and PTR_IMG 8-byte aligned. NV_LINE is not latched and runs 0 to 365. New NV_LATE at $00:D90B counts lines fetched too late. Palette registers read back the last value written, not the stored entry.
- Cost: logic 15,773 (77%), block RAM 34 / 46.

## Step 6: one raster for both machines, 640x360 desktop (2026-11-16)

This replaces the "desktop video 528x360" decision above. Reason: the 816 is the product, so the picture is designed for the desktop and the classic machine fits into it.

- **Raster:** 1572 x 760 total, 1280 x 720 active, pixel clock 71.72 MHz (2.5 x core clock), 59.92 Hz. One raster frame is exactly one Atari frame, so there is no mode switch and no resync between desktop and Atari.
- **Desktop:** 640 x 360, shown 2x. **Atari:** shown 3x, centred, with black bars left and right.
- **Fallback kept:** a version that switches the pixel clock between two modes is in the git stash "dynamic-pll-720p-switch".
- **Classic machine freeze (REV $06):** SV_CTRL ($00:DC00) bit 2 freezes the whole Atari (CPU, video, sound) and resumes it exactly where it was. Horizon freezes it whenever the desktop is shown.
- **256 colours at 640 wide** needs the Atari frozen: the video fetch then reads 16 bytes per memory access. With the Atari running, only 16 colours or 320 x 180 are fetched in time (NV_LATE counts late lines).
- **Timing:** pixel clock 73.6 MHz reached (71.7 needed), core clock 29.8 MHz (28.7 needed). Logic 76%.

Measured on the board and the owner's monitor:

- The monitor accepts the raster; no sparkles or dropouts.
- Self test 10 of 10; video test reports no late lines in all modes with the Atari frozen.
- Horizon runs on the screen at 78 x 44 characters with a border (the first column was at the bezel without it); `atari` and F12 switch both ways.

Deviations from the register spec, to be approved: only bits 0 and 2 of SV_CTRL and bit 0 of SV_STATUS exist; freeze is immediate (it does not wait for vertical blank or an instruction boundary); NV modes are 640x360x8, 640x360x4 and 320x180x8.

**Open: clicks from the speakers in Horizon.** The owner hears clicks when text changes or scrolls in Horizon, also with the Atari frozen (so it is not Atari sound). Three listening tests (`sw/a816/sndtest*.s`) gave no clicks for: palette changes, hidden memory writes, NV_BASE jumps (all at 640x360x8), and continuous debug log output. Not yet tested: the 16-colour mode Horizon uses, keyboard events, the cursor.

## Step 7: Atari software loaded from Horizon (2026-11-16)

- Firmware mailbox services $18 mount, $19 eject, $1A cold boot (layout in the comment block in `firmware.c`); Horizon syscalls $61 to $63 and shell commands `mount`, `eject`, `boot`, `run FILE`.
- On the board: `run gyruss.xex` and `run river.xex` load and play; F12 returns to Horizon and freezes the game, `atari` resumes it. River Raid collisions work. The Gyruss file has no collisions, which looks like the file (a trainer version), not the machine. Cartridge and disk images are not yet tried on the board.
- Console font is now 8x12 (78 x 29 characters); the owner found the 8x8 lowercase unreadable.
- The emulator reports REV $06, knows the freeze register and stubs the three services.

## Step 8: native sound from the idle Atari chips (2026-11-16, REV $07)

While the classic machine is frozen, the 65C816 owns the second POKEY at $00:DB00 to $00:DB0F (write only) and four 8-bit DACs at $00:DB10 to $00:DB13 (0 and 1 left, 2 and 3 right). They run from a 1.79 MHz tick that does not stop with the freeze; the frozen first POKEY is left out of the mix. Horizon must silence them before resuming the Atari. Heard on the board by the owner: tone, three-voice chord, DAC left only, DAC right only (`sw/a816/sndnat.s`).

This is an interim deviation from the register spec, which puts an 8-channel sample player at $00:DB00. It costs almost no logic. The sample player, MIDI and possibly OPL2 are candidates once logic is reclaimed from the old Atari-side extras.

## Step 9: blitter and desktop (2026-11-17, REV $08)

- **Blitter** as in the register spec ($00:DA00): fill, copy, keyed copy, 1 bpp expand, backwards copy. Writes go four pixels per memory access. Its self-checking test (`sw/a816/blittest.s`) passes in simulation, in the emulator and on the board. Build: core clock 29.06 MHz reached (28.69 needed), logic 82%, placement cells 92%.
- Rules the spec did not state: wait for BUSY = 0 before writing any blitter register; write CACHE_FLUSH before the CPU reads blitted memory; an overlapping copy in the wrong direction is undefined.
- **Horizon desktop**: windows with their own bitmaps, a compositor, menu bar, Desktop, Files and Terminal windows, About, beeps. It boots into the desktop; a file `/SYSTEM/NODESK` selects the text mode.
- **Measured on the board** (window benchmark): moving a 302 x 187 window one step takes 14 ms with the blitter against 176 ms on the CPU; drawing a 60-character line 3.5 ms against 24 ms.
- The emulator runs CPU-only drawing about 2.3 times faster than the board; its memory timing model is too optimistic.

## Step 10: Horizon 0.11, the first native programs

- Shared controls library (button, scroll bar, text field, list, alert, file dialog).
- Edit (text editor, up to about 768 KB, clipboard, two fonts), Paint (320x200x256, saves .PIC and BMP),
  Settings (desktop colour, mouse speed, key repeat, beep volume; saved in /SYSTEM/CONFIG).
- Files: several windows, drag and drop moves, copy/paste, new folder, rename, delete. Desktop icons.
- Kernel: clipboard, drag and drop between programs, key repeat, modal dialogs, pointer shapes (syscalls $80-$89).
- Emulator tests pass with and without the blitter. On the board: boots to the desktop as "Horizon 0.11";
  Edit opened README.TXT, typed a line, ctrl-S, and the file read back changed (110 -> 126 bytes).
- Not yet seen by eye on the board: Paint, Settings, Files drag and drop, icons.

## Step 11: board screenshots and BASIC

- PC link command PEEK816 reads 816 memory; `tools/atari.py shot816 OUT.png` captures the native screen
  (about 6 s). Firmware only, no logic change. Used to check Settings, Terminal and Paint on the board.
- Horizon BASIC 1.0 (BASIC.PRG): line-numbered, 32-bit integers and strings, graphics window, sound, mouse.
  Reference in horizon/BASIC.md, examples in /programs. Empty FOR loop of 100,000: 2.4 s in the emulator.
  On the board: `basic -r /programs/demo.bas` from the Terminal draws the demo picture.
- Kernel fix: without the blitter, win_draw blits were never repainted.

## Step 12: Horizon 0.12

- Pointer position without a button (syscall $8A, hover events), copy inside a window (win_draw op 9),
  video-state block at $01:F000 for the screenshot tool, Programs menu, .PIC opens in Paint,
  BASIC accepts file names without quotes.
- Board against emulator, BASIC: self test 3.7 s / 2.0 s, sieve 89 s / 45 s, empty FOR 100,000: 4.0 s / 2.4 s.
  The emulator is about 2x too fast on CPU work. BASIC self test: 16 groups pass on the board.
- Scrolling one line with the blitter (emulator): BASIC console 67 ms, Edit 55 ms. Still slow; most of it
  is the copy done twice (in the window, then to the screen).

## Step 13: old logic removed, USB mouse working

- Removed: on-screen menu and overlay, the dead USB host, debug meters; firmware: network/modem, H:, printer.
  Keyboard matrix rewritten smaller. Logic 82% -> 77%, firmware 67% -> 47%. Atari settings now only in /atari.ini.
- USB mouse (first test with a real one): two faults. The firmware UART kept one byte and dropped most of
  each frame (now a 64-byte FIFO in simpleuart.v), and the frame checksum included the type byte (it does not).
  Measured frame: 57 AB 88 07 20 btn dx dy wheel serial sum. Keyboard frames have type 11 on this keyboard.
- Timing: clk_core 28.73 MHz (needs 28.69): thin.
- On the board: desktop, real keyboard and real mouse work. Still to check on this build: classic
  machine (executable, cartridge, disk), classic keyboard matrix, self test, sound.
- Horizon (emulator tests pass, not yet on the board): Sheet, Edit undo/find/replace/wrap, direct drawing.

## Step 14: firmware SYS_RESTART / SYS_SYNC, clk_core margin (2026-11-17)

- **Mailbox $1B SYS_RESTART** (ARG0 0 = reload Horizon and restart the 65C816, 1 = full restart: options back to default, /atari.ini read again, classic images ejected, classic machine cold booted, Horizon reloaded). The OK reply is written first; the 65C816 is held in reset as soon as it has moved MB_RSP_TAIL past the reply (500 ms at most). Horizon should take the reply and then spin. Errors (no restart): $83 bad ARG0, 4 no HORIZON.SYS/A816.BIN. Horizon runs again after about 0.2 s (mode 0) or 1 s (mode 1).
- **Mailbox $1C SYS_SYNC**: closes every mailbox file, closes classic disk images and the virtual executable disk, unmounts the card. Reply ARG1 = handles that were open. Afterwards the card may be removed or the power cut. Until the next restart every op below $1B answers **$86**; PC link transfers fail. SYS_RESTART (or the PC link's restart816) mounts the card again.
- Layout in the comment block in `core/firmware/firmware.c`; table in `02-register-spec.md`.
- **When data reaches the card today:** WRITE sends whole 512-byte sectors to the card at once; a partial last sector and FAT changes wait in FatFs's one sector buffer until the next card access or CLOSE; the file's directory entry (size) is written only at CLOSE, MKDIR/DELETE/RENAME, or SYS_SYNC. Classic disk images are synced after every sector. So a clean shutdown matters only for files open for writing: power off with such a file open and it keeps its old size (plus lost clusters). SYS_SYNC before power-off covers it.
- Test `sw/a816/systest.s` (SYSTEST.BIN mode 0, SYSTEST1.BIN mode 1) on the board: a file written and left open survives SYNC with its full size (checked on the next run, after the remount), file ops answer $86 after SYNC, Horizon comes back after both restarts; mode 1 logged `key=scanlines` from a temporary /atari.ini and the ROM reload / HDD.ATR mount.
- **Timing:** clk_core 28.73 -> **30.93 MHz** (needs 28.69). Two changes: the 65C816's native sound write to POKEY 2 / DACs is registered in `tang_top.sv` (one clk_core later; it was the critical path: microcode -> RDY_OUT -> io_wr -> POKEY 2 -> MMU -> 6502), and the two-cycle multicycle constraints now also start at the CPU's own registers (AddrGen AAL/AAH/AB/DL/DH, A/X/Y/P/T/D/DBR/PBR/SP/IR/STATE) and cover D/DR/DBR/PBR/SP/AA*/DL/DH as ends; same reasoning as before (all written only on the CPU enable, never in two consecutive cycles). clk_pix 92.4 MHz, sys_clk 31.0 MHz. Logic 15,871 (77%), CLS 9,203 (89%).
- Simulation testbench checks the current REV; BLITTEST gets a 20 s default timeout (it needs about 4.5 s simulated). All simulations pass; on the board: self test 10 OK + DONE, BLITTER PASS, desktop after restart816.

## Step 15: blitter command lists, raster events (2026-11-17, REV $09)

Purpose: the hardware does the repetitive work, the CPU only gives orders. Spec: "Blitter / Command lists" and "NVC / Raster events" in `02-register-spec.md`.

- **Command lists** (`a816_blit.sv`): BL_LIST ($DA14-16), BL_COUNT ($DA17-18), BL_CTRL write bit 2 LIST, bit 3 ABORT; read bit 2 LIST, 3 WAITING, 4 DONE, 5 ABORTED. 24-byte records (bytes 0-18 = $DA00-$DA12, byte 19 bit 0 WAIT_VBL), read as three 8-byte bursts through the blitter's own port (same priority: video fetch > CPU > blitter) and loaded byte by byte through the CPU's register write port. BUSY covers the whole list, one interrupt at its end, ABORT stops within one memory access. From REV $09 register writes while BUSY are ignored (the hardware enforces the old rule).
- **Raster events** (`a816_nvc.sv`): NV_LINE, the LINE and VBLANK interrupts now come at the beam: in the horizontal blank just before line n is drawn (the fetch trigger of line n delayed by 1,139 clk_core cycles), instead of at the fetch, 40 µs earlier while line n-1 was still on screen. New NV_FRAME ($D90C-0D, +1 at VBLANK). Reading $D906 / $D90C latches the high byte (new read strobe from `a816_sys`). Lines are the 360 lines of the 640x360 picture in all modes; the events run with the NVC off too. No interrupt bits were added: VBLANK and LINE already existed in IRQ_STATUS.
- BLITTEST's interrupt check now masks BL_CTRL to bits 0-1 (bit 4 DONE is set after a blit).
- **Cost** (step 1 + 2 together): logic 15,871 -> 16,049 (+178), CLS 9,203 -> 9,224 (89%), block RAM 35 / 46 unchanged. Timing: clk_core 31.10 MHz (needs 28.69), clk_pix 92.26, sys_clk 30.53.
- **Simulation:** `sim_a816/run.sh +prog=blitlist_sim.bin` PASS; the testbench now checks that every LINE / VBLANK event falls in the horizontal blank at the end of output line 29 + 2n (32 events, 0 misplaced). Self test, bring-up 1 and the random blitter test (`run_blit.sh`) pass.
- **Board** (`sw/a816/BLITLIST.BIN`, self-checking): LIST (15 mixed records as a list against the same records one by one: identical 16 KB), EMPTY, ABORT (BUSY drops within 20 reads, no interrupt, registers unchanged by writes while BUSY), VBL WAIT (3 WAIT_VBL records = 3 frames, last blit at line 360), RASTER: all OK, BLITLIST PASS. 60 frames = 999,505 µs: **60.03 Hz** (the raster is 1572 x 760 at 71.72 MHz; the 59.92 Hz in step 6 was wrong). Self test 10 OK + DONE (REV 09), BLITTEST PASS, Horizon restarts to the desktop.
- **Speed, 100 keyed 16x16 copies** (board, classic machine frozen): one by one from the CPU (only DST and START written per blit, the fastest CPU loop) 2,726 µs; as one list 2,319 µs (15% less), and the CPU is free for all of it. The blits themselves dominate (about 23 µs each); the list adds about 1.7 µs per record (3 bursts + 20 load cycles).
- **Palette split** (`sw/a816/SPLIT.BIN`, for the eye: blue / red from line 120 / green from line 240 on stripes, written by LINE and VBLANK handlers): every second 60 VBLANK and 120 LINE interrupts, NV_LINE read in the handler always the compare value (0 bad in 11 s). Whether the edges are clean on the monitor is for the owner to look at (the screenshot tool reads RAM, not the raster).
- Emulator: REV $09 model (list timing: 30 CPU cycles per record + the blit; ABORT drops BUSY at once), beam events, NV_FRAME, latches; `make test` 21 of 21, also with `EMUFLAGS="--rev 8"` and `--rev 7` (tests of missing hardware skipped); Horizon `make test` passes with the default, `--rev 8` and `--rev 7`.

## Step 16: sample player (2026-11-17, REV $0A, not in the default build)

Spec: "Native audio / Sample player" in `02-register-spec.md`. Module `core/src/a816/a816_snd.sv`; it is switched off in the default build (`A816_NO_SAMPLER` in `tang_top.sv`), which stays REV $09.

- **Design:** 8 voices, signed 8- or 16-bit PCM anywhere in RAM; per voice START, LEN, LOOP (loop start; loop end = LEN), PITCH (2.14, $4000 = one sample per output sample), VOL_L, VOL_R, CTRL (LOOP, SIXTEEN); KEYON / KEYOFF / PLAYING / END (W1C) / IRQ_EN (AUDIO = IRQ_STATUS bit 5, a level) / MASTER / LATE / SEL + POS / OUT_L, OUT_R at $DB20-$DB2F, voices at $DB80 + 16n (the old plan put them at $DB00, which POKEY 2 and the DACs use since REV $07). One engine steps the voices in turn (about 18 cycles each) at the HDMI audio rate, 48 kHz, taken from the HDMI transmitter's own sample clock (deviation from the ~32 kHz target: the HDMI output is 48 kHz, so any other rate would be resampled by sample-and-hold; the old spec also said 48 kHz). Each voice keeps its last 8-byte block, so at pitch $4000 it reads RAM once every 8 (8-bit) or 4 (16-bit) samples; reads go through the blitter's port mux, now video fetch > CPU > sample player > blitter. A 4-sample FIFO decouples the engine from the output clock; a sample not ready counts in AU_LATE. The classic mix is shifted by +16384 (its silence was at -32768) and the sum saturated.
- **Left out for cost:** linear interpolation (it cost about 90 cells, a multiplier and a second stored sample per voice), ADPCM, the AU_POS read latch.
- **Starvation analysis:** the worst case is all 8 voices needing a new block every output sample (16-bit at pitch near 4): 8 port accesses per 597 clk_core cycles. Each wait is at most one video burst plus one CPU access plus the access in flight (the CPU leaves gaps, the video fetcher drops its request for at least a cycle after each burst, the blitter is below the player). Simulation of exactly that case (8 voices 16-bit at $FFFF, a 20-record list of 640x180 copies, NVC 640x360x8): longest engine time 422 of 597 cycles per sample, the FIFO never below 4 entries, AU_LATE 0. At pitch $4000 the load is 1 / 8 of that.
- **Simulation:** `sim_a816/run.sh +prog=sampler_sim.bin` PASS (the testbench now has the sample player and a 48 kHz tick). Emulator: bit-exact model `emu/audio.c` (`--rev 10`, and `--wav FILE` writes its output); SAMPLER passes there.
- **Board** (a REV $0A build, `impl/rev0a_try/`, clk_core 29.02 MHz): SAMPLER.BIN all OK, SAMPLER PASS: AU_POS advances 48 / 24 samples per ms with the classic machine frozen and running, the end interrupt after 4,167 µs ± 150, a loop of 48 samples wraps 18-22 times in 10 ms with AU_POS always 16-63, OUT_L / OUT_R equal the spec formula, AU_LATE 0 and NV_LATE 0 for 438 ms of list blitting with 8 voices refetching every sample. Self test 10 OK (REV 0A), BLITTEST PASS, BLITLIST PASS. PLAYDEMO.BIN ran (noise burst end after 341,344 µs, AU_LATE 00); nobody has listened to it yet. Its emulator output was checked by FFT: chord 261.7 / 329.6 / 392.2 Hz, pan left to right, the A3 note, all 8 scale notes.
- **Cost, and why it is off:** logic 16,049 (REV 09) -> 17,131 (+1,082), CLS 89% -> 92%, block RAM 35 -> 42 (voice registers 1, voice state 3, sample blocks 2, FIFO 1), DSP +4 multipliers. Timing: clk_core 28.81 MHz (needs 28.69, the rule is 29.7; a different placement seed gave the same); the earlier, larger version gave 29.49 and 29.02. With the player in, the critical paths are the 65C816's microcode to I/O registers (blitter, sample player), i.e. placement density, not the player's own logic. Synthesis also grew the 65C816 core by 300-490 LUTs when the player's read data joined the CPU's data input; registering that read data (the bus holds the address for a cycle first) took back 130. The first version (with interpolation, registered RAM writes) cost +1,236 and failed the margin too.
- **To turn it on:** delete the `define A816_NO_SAMPLER` line in `tang_top.sv` (REV becomes $0A). Getting the margin back needs about 300-500 cells removed elsewhere; candidates, all the owner's call: the PicoRV32 compressed-instruction option (+390 cells, see step 2; the hot firmware would need to fit uncompressed), the classic cartridge bank-switching schemes nobody uses, RAMBO above 320 KB.
- **Default build from the final tree** (sample player off, REV $09): logic 16,480 (80%), CLS 9,238 (90%), block RAM 35 / 46, clk_core 30.36 MHz, clk_pix 90.48, sys_clk 35.41. On the board: self test 11 lines OK (REV 09), BLITLIST PASS, BLITTER PASS, Horizon back on the desktop. This is what the board runs now (loaded to RAM; the flash still holds the earlier bitstream). The same REV $09 design built at 16,049 an hour earlier: the 65C816 core's own logic varied between 1,603 and 2,091 LUTs across this session's builds with almost identical netlists around it, so every cost figure above carries a few hundred cells of synthesis noise.
- **To listen to the sample player:** `openFPGALoader -b tangnano20k core/impl/rev0a_try/atari800_tn20k.fs`, then `python3 tools/atari.py run816 sw/a816/PLAYDEMO.BIN --seconds 22` (17 s: chord, pan sweep, looped 16-bit note, noise burst, 8-voice scale; each part is announced in the log). Restart Horizon afterwards. In the emulator: `emu816 --rev 10 --wav out.wav core/sw/a816/PLAYDEMO.BIN`.

## Step 17: room for the sample player, REV $0A is the default (2026-11-17)

The sample player is now in the default build: **REV $0A**. Timing rule held on two placements of the final tree: clk\_core 30.86 MHz (place\_option 1) and 30.61 MHz (place\_option 0), needs 28.69, rule 29.7.

**Cost table** (sample player on in every row; one change per build, in this order; "Logic" and CLS from the place-and-route report, CLS out of 10,368; block RAM 42 / 46 and DSP 3 in all rows):

| Build | Change | Logic | CLS | clk\_core | clk\_pix | sys\_clk |
|---|---|---|---|---|---|---|
| b0 | Baseline: step 16 tree with the sample player on | 17,131 | 9,538 (92%) | 28.81 | 95.90 | 29.36 |
| c1 | PicoRV32 without COMPRESSED\_ISA, firmware RV32I | 16,506 | 9,286 | 29.46 | 94.81 | 44.46 |
| c2 | Classic extended RAM capped at 320 KB | 16,600 | 9,356 | 28.76 | 83.16 | 36.23 |
| c3 | Paddle simulators removed | 16,502 | 9,258 | 31.38 | 92.43 | 40.88 |
| c3' | Same tree, place\_option 0 | 16,502 | 9,389 | 29.47 | 86.05 | 41.46 |
| c4 | Cartridge schemes reduced, flash-cart emulation removed | 15,555 | 9,060 (87%) | 29.53 | 85.48 | 39.92 |
| c5 | Blitter and NVC take CPU register writes one clk late | 15,850 | 9,215 | 29.85 | 91.68 | 41.18 |
| c6 | Interrupt flags of the 65C816 added to the two-cycle constraint | 15,850 | 9,196 | 30.86 | 81.44 | 38.07 |
| f1 | Final tree (comments, unused files), place\_option 1 | 15,850 | 9,196 (89%) | 30.86 | 81.44 | 38.07 |
| f2 | Final tree, place\_option 0 | 15,850 | 9,271 | 30.61 | 82.20 | 38.01 |

Module view from synthesis (LUT + ALU), which is less noisy than the totals: PicoRV32 1,603 -> 1,223 (-380); classic address decoder outside the cartridge logic -39 and 7 registers (RAM cap); paddles -137; cartridge logic 574 -> 95 and the decoder around it a further -164 (c4, -677 in the classic core). The c5 total rose by about 300 with almost no change in any module: synthesis noise, as in step 16. Timing moved by up to 2.6 MHz between placements of one netlist, so only the last two rows count for the margin.

**What was removed, and what the classic machine lost:**

- **PicoRV32 compressed instructions** (firmware now `-march=rv32i`). Nothing visible. Hot firmware (text + data + bss) 17,632 -> 22,664 bytes of the 28,672 allowed below the stack (6.0 KB left), cold image 14,416 -> 18,220 bytes (SPI flash, 64 KB window). SD speed is unchanged (`sw/a816/FSBENCH.BIN`, 512 KB through the mailbox in 32 KB requests: read 3.09 s before, 3.06-3.07 s after, 167 KB/s; LOAD 3.07 / 3.05 s; write 4.8-4.9 s before, 4.6-5.3 s after, the card's write latency varies more than that). PC link send of 128 KB: 15.7 s before, 15.0-15.2 s after.
- **Classic RAM above 320 KB:** only 128 KB (130XE) and 320 KB (RAMBO) remain; the 400/800 RAM sizes, Axlon, Compy Shop 320/576 KB and RAMBO 576/1088 KB schemes and the Axlon bank register are gone. `/atari.ini`: `ram=128` or `ram=320`; no key = 128; any other value gives 320 KB and the log line `ram=1088 not supported, using 320`. Checked on the board with a BASIC program that writes 16 PORTB banks: 12 aliases at 128 KB, 0 at 320 KB and with `ram=1088`. Horizon's Settings program still offers 576 and 1088 (horizon/user/settings.s); they now give 320.
- **Paddles:** the eight paddle simulators. POKEY's pot lines are now held low, so POT0-7 read 228, which is what they read before (the simulators were fed the "nothing connected" value). No visible change.
- **Cartridges:** `cart_logic.vhd` keeps standard 8/16 KB, raw 2/4 KB, OSS (three variants), XEGS 32 KB-1 MB, switchable XEGS, Atarimax 1 Mbit and 8 Mbit (old and new), SIC 128/256/512 KB and MegaCart 16 KB-4 MB. Removed: flash write emulation (Atarimax, SIC, MegaCart 4 MB, J(atari)cart, DCart: they now read as ROM, programs that save to the cartridge flash cannot), SpartaDOS X 64/128 KB, Diamond, Express, Atrax (three), Williams, Blizzard, Phoenix, AST, Turbosoft, Ultracart, aDawliah, JRC, SDX side2/U1MB, Corina, Bounty Bob, DB, XE Multicart, SIC 1 MB, MegaMax, right-slot 4/8 KB, the 8-15-bank XEGS variant, the RTC and pass-through modes. The firmware's CAR table matches; other types are refused with "unsupported CAR type" (mailbox $84). Checked on the board with three synthetic cartridges that switch through every bank (XEGS 32 KB: 4 banks, Atarimax 1 Mbit: 16, SIC 128 KB: 8, all read back correctly), a 16 KB raw ROM, and a refused type 22.
- **Not logic, removed as unused:** the VBXE stub (its outputs are now constants in `atari800core.vhd`), `ultime.vhdl`, `tape_handler.vhdl`, `fifo_tape.vhd`, `pot_from_signed.vhdl`, `vbxe_blitter.vhdl`, the original `rtl/.../address_decoder.vhdl` (the build uses `src/address_decoder.vhdl`) and the files the old `build_syn.tcl` kept (licence clean-up). `freezer_logic.vhd` and `pbi_rom.vhdl` stay: they are instantiated but fold to zero cells (their enables are tied off).

**The timing fixes** (rows c5, c6): with the logic down to 15,555 cells clk\_core was still 29.5, because the critical path was not density. It was the 65C816's microcode output -> I/O address decode -> the clock enables of about 100 blitter registers (33.8 ns). The blitter and the NVC now register the write strobe, address and data and apply the write one clk\_core later (the sample player already did); a CPU access takes two clk\_core cycles, so the CPU's next access sees the write, and register reads stay combinational. Nothing changes for software. Then the worst path was `IsIRQInterrupt` -> P / PCr inside the CPU: the interrupt flags (`IsReset/IsNMI/IsIRQ/IsABORTInterrupt`, `GotInterrupt`) are written only under `RDY_IN & CE`, like the registers already in the two-cycle constraint, so they were added to its start points (`constraints/tang_nano_20k.sdc`).

**Tests on the final build** (f1, loaded to SRAM, its `cold.bin` in flash): self test 10 OK + DONE (REV 0A), BLITTER PASS, BLITLIST PASS, SAMPLER PASS, PLAYDEMO (AU\_LATE 00), SPLIT (0 bad in 15 s), FSBENCH PASS, PC link send; classic machine: BASIC READY, XL self test (BYE), `RIVER.XEX` (170 sectors), `CAVERNS.ATR` (99 sectors, 0 errors), the cartridges above; Horizon back on the desktop after a full restart (screenshot). Simulations: all pass (`run.sh` with the self test, bring-up 1, NVTEST, BLITLIST, SAMPLER, BLITTEST; `run_blit.sh`). Two testbench fixes: Verilator prints `%X` in lower case, so the bring-up 1 REV check failed at REV $0A ($09 has no letters); and `tb_blit` now spends two clocks per register write like the CPU (it checked BUSY on the clock right after START). BLITLIST in simulation needs a 3 s timeout (it ran out at 400 ms with the sample player in the testbench). Emulator: default REV $0A, `make test` 22 / 21 / 20 / 18 passed at default / `--rev 9` / 8 / 7; Horizon `make test` passes at the default and at `--rev 9`.

**Room left:** about 15,850 of 20,736 logic (76%), CLS 89%, block RAM 42 / 46. Sprites and fine scrolling (about 1,000 cells) should fit by count; whether clk\_core keeps 29.7 depends on where their register writes land (use the same registered-write pattern). Next candidates, not done: the keyboard translator (`usb_to_atari800.sv`, 586 cells: four parallel copies of the HID tables, one time-shared copy would save about 300 with no visible change; the PC-symbol layout option is part of it), the POKEY output low-pass filters (168, audible), POKEY 2's keyboard scanner (31), the classic covox write path at $D600 (the four DACs themselves are used by the native sound), the scandoubler's scanline and position options (about 50), the CH9350 hardware keyboard decoder (131) if the firmware decodes the frames alone, and PicoRV32 options (below).

**PicoRV32 options, current setting and cost/benefit** (not changed except C): BARREL\_SHIFTER 0 and TWO\_STAGE\_SHIFT 0 (shifts take one cycle per bit; a barrel shifter costs about 100-200 cells, FatFs and the SD driver use few large shifts, little gain); ENABLE\_MUL / ENABLE\_DIV 0 (libgcc does them in software; hardware multiply costs several hundred cells or a DSP, nothing in the SD path multiplies in a loop); ENABLE\_COUNTERS 0 (the firmware uses its own cycle register); ENABLE\_IRQ 0 (polled design); CATCH\_MISALIGN / CATCH\_ILLINSN 0; ENABLE\_REGS\_DUALPORT 1 (the register file is in block RAM; 0 would make every instruction a cycle slower to save little logic); ENABLE\_REGS\_16\_31 1 (RV32E would save nothing measurable, the registers are in block RAM). sys\_clk has 11 MHz of margin, so TWO\_CYCLE\_ALU is not needed.

**Board state:** the f1 bitstream is loaded to SRAM, its `cold.bin` is in flash at 0x500000; the flash still holds an older bitstream, whose hot firmware will refuse this `cold.bin` after a power cycle. Files: `core/impl/rev0a_default/` (this build), `core/impl/fallback_rev09/` (the step 16 default and its `cold.bin`).

## Step 18: names (2026-11-17, no hardware change)

The product is written **Atari816**, one word, in every document, comment and string that names it (the earlier steps above keep the spelling of their time, and the banners of the bring-up and self-test programs, which the testbench and the emulator's tests compare, still print `ATARI 816`). The custom chips get names, used the way Atari's manuals used ANTIC and POKEY: **Marga**, the video chip (the NVC above, `a816_nvc.sv`, registers NV\_\*); **Ali**, the blitter (`a816_blit.sv`, BL\_\*); **Lau**, the 8-voice sample player (`a816_snd.sv`, AU\_\*). FREDDIE II and POKEY 2 keep their names. Module, file, signal and register names do not change, so the bitstream is the same; the register spec has a line saying which prefix belongs to which chip. Horizon 0.16 shows the names in its About box.

## Step 19: sprites and fine scrolling in Marga (2026-11-17, REV $0B)

REV $0B is the default build. Spec: "Fine scrolling (REV $0B)" and "Sprites (REV $0B)" in `02-register-spec.md`. Module `core/src/a816/a816_nvc.sv`; nothing outside Marga changed except the REV (tang\_top, a816\_sys default) and the I/O processor firmware is untouched (the flash still holds REV $0A with its `cold.bin`, which this bitstream accepts: same firmware).

**Design as built.**

- **Sprites:** 16, records of 8 bytes at $D980 + 8n (X 11 bits signed, Y 10 bits signed, 16-byte aligned image address with the 4 bpp palette bank PAL in its low nibble, CTRL: EN, HFLIP, VFLIP, MAG, WIDE, TALL, BPP4, BEHIND). Sizes 16x16 and 16x32 at 8 bpp, 16 or 32 wide x 16 or 32 tall at 4 bpp, all magnifiable to 2x (up to 64x64). Colour 0 transparent. Priority by index (0 in front), BEHIND hides a sprite's pixels behind non-zero bitmap pixels, the pointer always on top. Records are a shadow written by the CPU (write-only, read back through NV\_SPR\_PEEK/PEEKD); NV\_SPR\_COMMIT copies them to the set in use in vertical blank (at once if written between the fetch of line 360 and the fetch of line 0), PENDING until done. Status: OVERFLOW, LATE (W1C).
- **How it works:** one more block RAM (2048 x 9, true dual port) holds a second two-line buffer for sprite pixels ({BEHIND, index}) and both record sets. At each line's fetch trigger an evaluator reads Y and CTRL of the 16 records (48 cycles) and picks the sprites of that line in index order within a width budget of 512 on-screen pixels; a fetch unit then reads each picked record (8 cycles), fetches its row (one 16-byte burst; two 8-byte bursts while the classic machine runs; one 8-byte burst for a 16-pixel 4 bpp row) and a painter writes it into the buffer at one pixel per cycle, from sprite 15 down to 0, while the next row is fetched (two 128-bit registers). The pixel clock side reads the sprite buffer next to the bitmap line buffer, merges (sprite if opaque, not under the pointer, not BEHIND a non-zero bitmap pixel) and clears each sprite pixel after its last read, so the clk\_core side never clears. The bitmap line buffer is now 9 bits wide: bit 8 marks pointer pixels, and the 4 bpp mode is unpacked to one pixel per entry (the pointer merge became simpler; the picture is unchanged, checked against the old emulator pictures).
- **Fine scrolling:** NV\_SCROLLX/Y (pixel offsets), NV\_SCROLLX2/Y2 (second set for a split), NV\_VHEIGHT (vertical wrap), NV\_SCROLL\_CTRL (HWRAP: rows wrap at NV\_STRIDE; SPLIT: from line L = NV\_LINE\_CMP the second set). All taken at the fetch of line 0 with NV\_BASE. Line 0's row is NV\_BASE + SCROLLY x STRIDE (one DSP multiplier, computed a cycle ahead); the sub-burst part of SCROLLX is dropped while unpacking, at the cost of one more burst per line. What NV\_BASE alone gave before: steps of 256 bytes, i.e. two lines at stride 640, one line at stride 1024 or more, and no horizontal step finer than 256 pixels, no wrap, nothing per region.
- **Memory port priority:** Marga's line fetch, Lau, sprite fetch, CPU, Ali (Lau moved ahead of the CPU and the sprites: it has a hard 48 kHz deadline, the sprites had the most slack; with the old order Lau needed up to 811 cycles for one sample in the worst load test, absorbed by its FIFO, now 422 of 597).
- **Line limit and why 512:** drawing takes a cycle per on-screen pixel plus about 25 per sprite. With a budget of 640 the worst line (8 x 64 + 8 x 16 pixels, blitter list, 8 voices) took 1,004 of the 1,257 cycles of a line period in simulation, too little margin; with 512 the worst line found took 790 (SDRAM latencies as measured) or 907 (random 6 to 13 cycles). All 16 sprites always fit up to 32 pixels wide on screen; 64-pixel ones: 8 per line.
- **Not built:** collision detection. Pixel-exact collision needs either a read of the sprite buffer before every sprite write (halving the drawing rate, so half the line limit) or the sprite index stored per pixel (a second block RAM). Registers $D945-$D94F are reserved for it. 8 bpp rows of 32 pixels (two bursts) were left out: two 16-pixel sprites side by side do it.

**Cost table** (place\_option 1 unless noted; CLS of 10,368; "Logic" = LUT + ALU from the place-and-route report):

| Build | Change | Logic | CLS | Registers | Block RAM | DSP | clk\_core | clk\_pix | sys\_clk |
|---|---|---|---|---|---|---|---|---|---|
| f1 | REV $0A default (step 17) | 15,850 | 9,196 | 7,607 | 42 | 3 | 30.86 | 81.44 | 38.07 |
| b1 | Sprites (budget 640) and scrolling, first build | 16,382 | 9,315 | 8,274 | 43 | 4 | 30.41 | 94.95 | 42.40 |
| b2 | Final: budget 512, Lau before the sprites, 320x180 clearing fix | 16,438 | 9,411 (91%) | 8,274 | 43 | 4 | **34.45** | 92.31 | 36.82 |
| b3 | Final tree, place\_option 0 | 16,438 | 9,456 | 8,274 | 43 | 4 | **33.99** | 81.15 | 34.04 |

Module view from synthesis: Marga 831 LUT + 124 ALU, 702 registers, 2 block RAMs -> 1,356 LUT + 222 ALU, 1,368 registers, 3 block RAMs, 1 DSP (+623 LUT/ALU, of which about 120 are scrolling). The rest of the design is within the usual synthesis noise (the 65C816 core moved by 180 LUTs between b1 and b2 with no change in it). Timing rule (29.7 MHz on two placements) held with 4 MHz to spare; no fix was needed. The keyboard translator was not touched.

**Simulation** (`sim_a816`, the testbench now models Marga's picture itself: scroll and sprite registers snooped from the CPU's writes and latched by the spec's rules, every displayed pixel compared):

- `sprtest_sim.bin` (`sw/a816/sprtest.s -D SIM`): REGS, PEEK, COMMIT (pending at line 100 and 300, done in vertical blank; done within 50 µs in vertical blank), LIMIT (9 x 64 sets OVERFLOW, 8 do not), LOAD, then 12 random scenes in all three modes (positions over every edge, flips, MAG, 4/8 bpp, PAL, BEHIND, scroll, VHEIGHT, HWRAP, split, pointer): 47-50 million pixels compared, 0 bad, LATE 0. Run with random SDRAM latencies and with `+fixlat`.
- `sprsceneN.bin` (`sw/a816/sprscene.s`, SEED 1-10; 9 and 10 crowded so that the line limit drops sprites): the RTL's frame is byte-identical to emu816's for all ten; their md5s are now emulator tests.
- Regression: self test, bring-up 1 (its REV check now compares the shorter banner), NVTEST (now checks all modes with the pointer: 9.2 million pixels, 0 bad), BLITLIST, SAMPLER, BLITTEST, `run_blit.sh`: all pass.
- **Bandwidth** (LOAD: 640x360x8, all 16 sprites on the same 32 lines at 32 pixels, the full budget; a list of 640x180 copies; with and without 8 Lau voices of 16-bit samples at pitch $FFFF, the worst case): sprite engine at most 790 cycles of 1,257 per line (907 with random latencies); Lau at most 344 cycles per sample of 597 (422 random), FIFO never below 4, AU\_LATE 0; NV\_LATE 0. The list takes 33,554 µs with sprites off and 33,965 µs with them on (+1.2%; 2 records in simulation).

**Board** (b2 loaded to SRAM): self test 11 lines OK (REV 0B); SPRTEST PASS (list of 20 copies: 353,466 µs sprites off, 361,305 µs on, **+2.2%** for the blitter; with 8 voices at $FFFF 458,718 µs; AU\_LATE 00, NV\_LATE 00, SPR\_STATUS 00); BLITTER PASS; BLITLIST PASS (60 frames = 999,504 µs); SAMPLER PASS (AU\_LATE 00); SPLIT 0 bad; SPRDEMO and SCROLLDEMO ran their 1,200 frames in 1,200 VBLANKs, NV\_LATE 00, SPR\_STATUS 00. Classic machine: cold boot to BASIC READY, keys injected through the USB keyboard path reach it (`A` RETURN gives ERROR- A), BLUE.XEX loads and runs (COLOR4 = $94). PC link send works (20 KB to /HWTEST.BIN). Horizon restarts to the desktop (screenshot). The blitter's slowdown on the board is the average over the frame: sprites use the port only on the lines they cover; on a line with the full sprite budget the port is busy for about 16 more bursts.

**Demos** (for the eye; nobody has looked at them on a monitor yet): `sw/a816/SPRDEMO.BIN`, 16 sprites (fish, flags, arrows, boats; flips, MAG, 4 bpp banks with a rotating rainbow, BEHIND pillars) over a drawn picture with the pointer on a Lissajous path, 20 s; `sw/a816/SCROLLDEMO.BIN`, a 1024 x 512 labelled tile map wrapping in both directions under a fixed status panel (split at line 320, frame counter and X/Y), 5 sprites, 20 s. Run: `python3 tools/atari.py run816 sw/a816/SPRDEMO.BIN --seconds 25` (from `core/`); back to Horizon (reloads /SYSTEM/HORIZON.SYS): `cd tools && python3 -c "from atari_link import AtariLink` / `with AtariLink(None) as l: l.restart816()"` (two lines of Python; `restart816()` without `test=True`).

**Emulator:** `nvc.c` models REV $0B bit-exactly (as long as the RTL is not LATE); default REV $0B, `--rev 10` and below hide the new registers. `make test` 24 / 22 / 21 / 20 / 18 at default / `--rev 10` / 9 / 8 / 7. Horizon's `make test` passes with it at the default and at `--rev 10`.

**Housekeeping:** the self-test and bring-up banners now print `ATARI816`; the testbench, `emu/tests/run_tests.sh` and the committed `emu/tests` binaries follow (`NVTEST.BIN` there was also stale and is refreshed). `build.tcl` takes `PLACE_OPTION` from the environment for the second placement.

**Files:** `core/impl/rev0b_default/` (b2 bitstream, report, the unchanged `cold.bin`). The board runs b2 from SRAM; the flash still holds REV $0A.

**Room left:** logic 16,438 of 20,736 (79%), CLS 91%, block RAM 43 / 46, DSP 4 / 24. The keyboard translator (about 300 cells) is still the first candidate if room is needed.

## Step 20: file dates, the boot cartridge, the I/O processor's polling (2026-11-17, firmware only)

No RTL change; the firmware is embedded in the bitstream, so the bitstream was rebuilt.

- **Mailbox $1D SYS\_TIME** (ARG0 = seconds since 2000-01-01 00:00, local): Horizon gives the firmware the time it knows (the clock the user set, or the last one saved, counting from start) whenever `time_set` is called. The firmware counts on with its millisecond timer, and FatFs now stamps files with it (`FF_FS_NORTC = 0`, `get_fattime()`, hot); before a time is given, files get the build date. Horizon 0.19 shows the dates in `ls` and on Files' footer.
- **Mailbox $1E CLASSIC\_STATE** (ARG0 = 5): the cartridge's image size and path, also for a cartridge the firmware loaded by itself (`boot=ash`). Horizon asks at start and reserves its banks as classic\_mount does.
- **The mailbox poll is now hot.** `a816_mailbox()` runs from SDRAM (cold) and was called on every turn of the main loop whenever the rings were set up; the PicoRV32's instruction fetches have priority over the 65C816's port (CPU, Marga, Ali). Found while calibrating the emulator (`sw/a816/timing.s`): with Horizon running, the 65C816 lost 10-20 % of its memory time to it with the desktop's video on (a pure write loop 25.2 ms instead of 21.2 ms; the BASIC sieve 103.4 s). A small hot check (`a816_mb_wanted`, inlined into `bridge_poll`: a request waiting, a key or mouse change, room for an event) now calls it only when there is something to do. Sieve 103.4 s -> 89.2 s; DPW16 under Horizon 500 -> 376 ms.
- "Atari 816" -> "Atari816" in the firmware's comments.

**Build** (place\_option 1, same RTL as step 19's b2): logic 16,438 / 20,736 (80%), CLS 9,411 / 10,368 (91%), registers 8,274, block RAM 43 / 46; **clk\_core 34.45 MHz** (rule 29.7), clk\_pix 92.31, sys\_clk 36.82. Hot firmware 21,140 bytes of 32,768; cold image 18,480 bytes.

**Board** (loaded to SRAM first, with its `cold.bin` in flash): self test 11 lines OK (REV 0B); TIMING.BIN; BRINGUP1 LOOP $5947, READ $860F, MVN $75D3; Horizon 0.19 boots to the desktop; `date 2026-11-17 23:55` then a file copied in the Terminal shows `2026-11-17 23:55` in `ls` (files from before show the old fixed date 2024-01-21) and on Files' footer; after a Horizon restart the provisional clock is given again and a new file gets 23:55; the classic machine runs BLUE.XEX from `run` (COLOR4 = $94) and F12 comes back; PC link send (the 43 files of the card's Horizon); SYSTEST (SYNC, restart 0) and SYSTEST1 (restart 1) pass. Not tested on the board: the boot cartridge (no /ASH.CAR on the card; tested in emu816 with `--boot-cart`), the PC link's listing (it has no listing command).

**Flash:** the board-tested pair is in flash (`cold.bin` at 0x500000, then the bitstream); the FPGA reloaded from flash after the write and came up to the Horizon desktop. Files: `core/impl/rev0b_fw2/` (this build: bitstream, report, timing, `cold.bin`), `core/impl/fallback_rev0b/` (step 19's bitstream with the earlier `cold.bin`).

## Step 21: the PC link, step 1 (2026-11-18)

The USB serial to the PC now carries a packet protocol instead of the old developer commands:
a gateway on the PC (`tools/atari816-link`) shares one folder with the Atari816, which sees it
as a second volume, `/PC:`, and gives it the time; the developer tools (`core/tools/atari.py`)
use the same link. Protocol: `04-pc-link.md`. Horizon 0.20 shows the volume (a "PC" icon,
Files, the shell, the file dialogs) and takes the PC's clock when it connects.

**Hardware change (small, in the 27 MHz I/O domain):** the bridge receiver (`iosys_picorv32.v`)
gets a programmable bit time (register $0200_00C4) and a 2048-byte FIFO in one block RAM (a read
of $0200_00C0 takes a byte; the count and an overrun flag are in the same word); before, it was
fixed at 115,200 baud with a 1-byte register. `simpleuart.v` gets a transmit divider of its own
(bits 31-16 of its divider register; 0 = as before), so the keyboard (CH9350) stays at 115,200
while the PC link sends at 1.5 Mbaud.

**Speed measurements** (raw test firmware, 1 MB per direction and rate, PRNG data checked):

| Rate | PC to board | Board to PC |
|---|---|---|
| 115,200 | 0 errors, 11.3 KB/s | 0 errors, 11.3 KB/s |
| 230,400 | 0 errors, 22.6 KB/s | 0 errors, 22.5 KB/s |
| 460,800 | 0 errors, 44.8 KB/s | 0 errors, 44.6 KB/s |
| 921,600 | 0 errors, 90.6 KB/s | bytes lost after 92 KB of a continuous stream |
| 1,000,000 | 0 errors, 97.6 KB/s | bytes lost after 52 KB of a continuous stream |
| 1.5 / 2 / 3 M | 0 errors when paced (the test loop overflowed the FIFO when not paced: it checks only ~125 KB/s) | 0 errors in 4 KB bursts (256 x 4 KB), 83.4 KB/s at every rate |

The wire is clean at every rate tried. Board to PC, the BL616 forwards at most about 83 KB/s
whatever the rate and drops bytes when a continuous stream goes on longer than its buffer
(about 8 KB of slack); the link's frames (at most 1,051 bytes, then a wait for the ACK) never
reach that. **Chosen: 1.5 Mbaud**, exact on both sides (27 MHz / 18; 12 MHz / 8 in the BL616's
FT2232 model), half the bit-time precision needed at 3 Mbaud. Above it nothing is gained: the
PicoRV32's receive loop and the BL616 are the limits, not the wire.

**Through the protocol** (final firmware, gateway on the PC, board-side timers):

| Path | Speed |
|---|---|
| PC volume READ, 512 KB in 32 KB mailbox requests (`sw/a816/PCBENCH.BIN`) | 5.11 s, **100 KB/s** (77 KB/s with one frame at a time; the gateway now keeps two in flight) |
| PC volume LOAD, 512 KB | 5.04 s, 102 KB/s |
| PC volume WRITE, 512 KB | 9.23 s, **55 KB/s** (the BL616's 83 KB/s and one frame at a time) |
| Shell `cp` of 1.5 MB, card to PC | 37 s, 41 KB/s (cp's request size and the card reads included) |
| Developer PUT (Horizon install, 23 files, 580 KB) | 12.9 s, 45 KB/s (128 KB took 15 s at 115,200 before) |
| Developer SINK / SOURCE (1 MB) | 77 KB/s / 33 KB/s (SOURCE is built byte by byte by cold code) |
| Round trip of a small developer request | 6 ms |
| Card through the mailbox, before / after (`FSBENCH.BIN`, 2 runs each) | write 5.03-5.29 / 5.29-5.32 s (the card's spread), read 3.07 / 3.07 s, load 3.05 / 3.05 s |

A small RTL change would not help much now: board to PC is the BL616's limit; PC to board is the
PicoRV32 (an SDRAM access costs it several microseconds, and the CRC is done in software). A
hardware CRC and a 32-bit FIFO read might give 20-30 % on reads; not done.

**Firmware:** `core/firmware/pclink.c` (the engine: frames, CRC tables, sessions, retries, the
log channel, the PC volume client), `firmware.c` (the mailbox routes `/PC:` paths and the
handles of PC files to it; the developer channel replaces the old bridge commands; the log goes
out as datagrams). Hot (block RAM): text 20,320 + data 616 + bss 4,836 = 25,772 bytes of the
28,672 allowed (was 21,140 + its bss before step 1: about 2.9 KB left); what runs in the idle
loop is hot (`pl_poll`, the receive loop, the CRC, the transmit loop, the copy into 65C816
memory); the rest of the protocol runs from SDRAM only while frames come or go. Cold image
24,952 bytes; 2 KB of buffers in SDRAM after it.

**Build** (place_option 1): logic 16,596 / 20,736 (81 %, +158), CLS 9,395 (91 %), registers
8,325, block RAM 44 / 46 (+1, the FIFO); **clk_core 31.85 MHz** (rule 29.7), clk_pix 89.83,
sys_clk 41.34. The netlist is the same for every firmware build, so the four builds of this
step all placed identically.

**Host test:** `core/test/pclink_host/run_tests.py` runs the firmware's `pclink.c` on the PC
against the real gateway through a pseudo terminal: file requests (60 KB write and read back,
stat, mkdir, rename, readdir, load, `..` and a symlink out refused), developer requests through
the gateway's socket while the board side is busy (parking), a gateway restart; also with one
byte in 20,000 lost in each direction. `tools/test_pclink.py`: the frame parser and the folder's
safety rules.

**Board tests** (final build, first from SRAM, then flashed):

- No gateway: boots to the desktop as before, no PC icon, no `PC:` in `/`; `ls /PC:` and `cp`
  to it answer "no PC link" at once; PCBENCH stops at once with $87. Self test A816.BIN: all
  OK + DONE. FSBENCH as above. The developer tools open the port themselves (ping, status,
  run816, shot816, send).
- Gateway started with the board running: connected within a second; the PC icon appears and
  the clock is set from the PC (the menu bar went from "up 0:00" to the PC's time; `date` in the
  shell). Files lists `/PC:` with sizes and dates (screenshot); `PC:` is the last folder of `/`.
  `ls /PC:` shows dates, `cat /pc:/hello.txt` works (any case), `/PC:/CALC.PRG` starts from the
  PC.
- 1.5 MB copied PC to card and card to PC with the shell's `cp`: the two files on the PC have
  the same MD5.
- Gateway stopped (SIGTERM: BYE) and killed (no BYE): the icon goes, `ls /PC:` says "no PC
  link". Killed during a 1.5 MB copy to the PC: `cp` said "the PC link was lost" after about
  3.5 s, no hang; the half file stays on the PC. Started again: the icon and the volume come
  back.
- The developer tools through the gateway while it serves the volume: ping, status, run816
  (PCBENCH, the self test), shot816, send.
- Classic machine: `run /BLUE.XEX` from the shell, COLOR4 = $94, F12 back.

**Known limits:** keys typed while a long PC volume request runs can be lost (the I/O processor
only looks at the keyboard between mailbox requests, as with long card requests); Atari disk
images cannot be mounted from `/PC:` (copy them to the card); one session, one folder.

**Flash:** `core/impl/pclink1/` (bitstream, report, timing, `cold.bin`) is in flash (`cold.bin`
at 0x500000, then the bitstream); the board came up from flash to the Horizon 0.20 desktop.
`core/impl/rev0b_fw2/` stays the fallback (it needs its own `cold.bin` flashed with it).

## Step 22: input during long requests, copy progress and cancel (2026-11-18, Horizon 0.21)

**The problem, as measured.** While the I/O processor served a long mailbox request (a big
card READ or WRITE, a `/PC:` request waiting for the gateway, a developer upload), keys typed
meanwhile were lost and the pointer stopped. How input reaches the 65C816:

- The keyboard and the mouse are one USB adapter (CH9350) on a 115,200 baud UART. A hardware
  decoder (`uart_kbd_ch9350.sv`) turns the keyboard reports into the held-key state
  (`reg_a816_keys`); the firmware reads the same UART through a 64-byte FIFO (`simpleuart.v`)
  for the mouse reports.
- The firmware made the KEY and MOUSE events (by comparing the held keys with what it had
  reported) only in `a816_mailbox()`, between two requests. A key pressed and released during
  a request was never seen. The mouse UART was drained only in the main loop and in the PC
  link's waits: during a card request the FIFO filled after about 5 reports (40 ms) and the
  rest were lost.
- The pointer itself is Marga's: Horizon's interrupt service writes PTR\_X / PTR\_Y for each
  MOUSE event (`kernel/mouse.s`). A task that waits for a mailbox answer blocks (W\_IO) with
  interrupts on, so the 65C816 is never the reason the pointer stops; the events were.
- Measured with a new board test (`sw/a816/INTEST.BIN`, `core/tools/intest.py`): the 65C816
  counts every event while it copies 1.5 MB in 32 KB requests, and notes the longest time
  between two MOUSE events. Old firmware, a MOUSE request every 10 ms from the PC: idle 14 ms;
  writing the card 414 ms; card to PC 582 ms; PC to card 402 ms.

**The fix (firmware only, no RTL change).** A small input layer in block RAM
(`in_service()` in `firmware.c`):

- Key events come from the firmware's own copy of the keyboard (`kv0`, `kv1`: the CH9350
  reports parsed in order, and the developer KEY / TYPE keys); after every change the
  difference is queued, one event per change, so a short tap is never lost. Mouse motion with
  the same buttons is added up; a button change gets its own event.
- The queue (32 events) goes into the response ring whenever two slots are free; the answer
  of the request in progress is written after the events (`a816_mailbox` reads RSP\_HEAD
  again at the end).
- `in_service()` runs in the main loop, in every wait of the PC link (also between frames of
  a long answer: `pl_busy`), in the SD card driver (between sectors and while the card is
  busy) and in `delay()`. It does nothing costly when there is nothing to send.
- A test generator: developer op $12 INJECT (`04-pc-link.md`) makes key taps and mouse
  reports where the CH9350's enter, and counts as lost what would not have fitted in the
  64-byte FIFO since the firmware last looked.

**After** (INTEST with INJECT: 80 key taps every 60 ms and 600 mouse reports every 8 ms per
phase; 1.5 MB copies in 32 KB requests; a 500 KB developer upload in phase 4):

| Phase | Longest gap between MOUSE events (before / after) | Longest time between two looks at the input | Lost |
|---|---|---|---|
| Idle | 14 ms / 8.2 ms (the report period is 8 ms) | 4.2 ms | 0 |
| 1.5 MB written to the card | 414 ms / 11.1 ms | 4.7 ms | 0 |
| 1.5 MB card to PC | 582 ms / 15.3 ms | 10.1 ms | 0 |
| 1.5 MB PC to card | 402 ms / 17.3 ms | 10.3 ms | 0 |
| 500 KB developer upload | (not measurable before) / 19.7 ms | 12.2 ms | 0 |

All 160 key reports and 600 mouse reports of every phase arrived (80 downs, 80 ups, dx 600).
A first try lost input while a long `/PC:` READ answer streamed in (323 ms): the PC link's
wait loop looked at the input only when no frame came; fixed with `pl_busy`. The 64-byte
FIFO holds 5 mouse reports (40 ms), well above the longest gap now, so no RTL change.

**Throughput** (before / after): FSBENCH write 5.14 / 5.06 s (the card's spread), read 3.08 /
3.11 s, load 3.06 / 3.10 s (+1 %); PCBENCH write 9.23 / 9.23 s, read 5.12 / 5.14 s, load 5.04
/ 5.06 s; INTEST's 1.5 MB copies card to PC 37.2 / 36.9 s, PC to card 31.2 / 30.9 s.

**Screenshots** (`shot816`): 6.3 s -> 2.3 s. The PEEK816 loop (`dev_peek816` and its RLE
helpers) now runs from block RAM (+780 bytes there).

**Firmware:** hot text 22,736 + data 612 + bss 5,068 = 28,416 of 28,672 bytes (256 left; was
25,772); cold image 23,996 bytes.

**Build** (place\_option 1; the netlist did not change): logic 16,596 / 20,736 (81 %), CLS
9,395 (91 %), registers 8,325, block RAM 44 / 46; clk\_core 31.85 MHz (rule 29.7), clk\_pix
89.83, sys\_clk 41.34.

**The gateway** (`tools/pclink.py`): a file the board creates (OPEN mode 2) is written in the
hidden folder `.atari816-partial` and put in place at CLOSE; when the session ends with it
open the temporary file is deleted; leftovers of a killed gateway go at the next start
(`04-pc-link.md`, "Unfinished files"). On the board: gateway killed with SIGKILL during a
shell `cp` of 1.5 MB to the PC: `cp` said "the PC link was lost", nothing appeared under the
name, and the next gateway removed the 512 KB left in `.atari816-partial`.

**Horizon 0.21** (`horizon/README.md`): copies go in pieces of 16 KB (was 32 KB); Files and
the Desktop show a progress window (file name, KB and percent, a bar, Cancel; it opens after
0.5 s); the shell's `cp` and `mv` stop on ctrl-C and keep other keys typed meanwhile (up to
80) for the next prompt; a cancel or an error deletes the partial file. emu816 models the
new event timing and slow transfers (`--card-kbps`, `--pc-kbps`) and the gateway's
unfinished-file rule; new session tests (`tests/pccopy.*`, `tests/cpstop.*`).

**Board tests** (build `core/impl/input1/`, first from SRAM, then flashed; Horizon 0.21 on
the card):

- Self test A816.BIN: 11 lines OK + DONE. FSBENCH, PCBENCH: above. INTEST: no input lost in
  any phase. Classic machine: `run /blue.xex` from the shell, COLOR4 = $94, F12 back.
- Shell `cp` of 1.5 MB card -> PC (38.9 s, 40 KB/s; 37 s with 32 KB pieces in 0.20), PC ->
  card -> PC: the MD5 of both files on the PC equals the original's. 4,878 and 7,000 injected
  mouse reports during these copies: none lost, longest look gap 7.6 / 10.2 ms.
- ctrl-C during `cp` to the PC and during `cp` on the card: "cancelled", no file left on
  either side. Gateway killed with SIGKILL during `cp`: above.
- Desktop, Files: BIG.BIN pasted into `/PC:`: the progress window ("256 of 1,536 KB (16%)");
  120 mouse reports injected during the copy moved the pointer by 120 pixels while it ran;
  Esc: "Copy cancelled", nothing on the PC.
- Screenshots 2.3 s.

**To check by hand** (no real keyboard or mouse could be used here): type and move the real
mouse during a long copy (Files to `/PC:` and the shell's `cp`), and during a `send` from
the PC; a fast click and a fast double click during a copy.

**Flash:** `core/impl/input1/` (bitstream, report, timing, `cold.bin`) is in flash; the board
came up from flash to the Horizon 0.21 desktop. `core/impl/pclink1/` is the fallback (with
its own `cold.bin`).

## Step 23: the internet through the PC link (2026-11-18, Horizon 0.22)

The gateway on the PC now gives the Atari816 the internet (`04-pc-link.md`, "Channels 4 and
5"): a URL is a path (`http://`, `https://`, `ftp://` read as files; `tcp://host:port`,
`tls://host:port` are connections), served by the gateway; the firmware only moves bytes. No
RTL change: the bitstream was rebuilt for the new firmware only.

**Block RAM first** (the hot firmware had 256 of 28,672 bytes left):

| Item | Freed |
| --- | --- |
| A. Run-once code to SDRAM: `mount_volume`, `check_fs`, `sd_init`, `disk_initialize`, `sio_init` (a new section `.coldtext` makes a function cold inside a hot file) | 1,708 |
| B. Dead features: the developer op TYPE (typing text on the classic keyboard: `ty_buf`, its typer, the two ASCII tables), the OSD's drive names | 784 |
| C. The link's CRC tables: the 256-entry byte table split by nibbles (CRC-16 is linear: T[x] = T[x & $F0] ^ T[x & $0F]), four 16-byte tables; the receive loop rewritten (the payload is read in a tight loop with the CRC in registers) | 148 (tables 512 -> 64; the loop grew) |
| F. The screenshot speed-up of step 22 reverted (`dev_peek816` and its RLE helpers back in SDRAM) | 780 |

A first try of C with a plain 16-entry nibble table cost 28 % of the PC-to-board speed
(PCBENCH READ 5.1 -> 7.3 s): this PicoRV32 has no barrel shifter, so a shift costs one cycle
per bit, and the nibble method shifts by 12. The split byte table needs one 4-bit shift a byte.

Hot firmware now: text 20,200 + data 612 + bss 4,296 = **25,108 of 28,672 bytes** (3,564
left; step 2 itself added 112 hot bytes: the stream service check in the main loop, the
event hook, the stack paint). The 4 KB stack reserve is unchanged; the most stack used, now
reported by INFO (`stk`, from a pattern painted at start), was **1,904 bytes** after the self
test, FSBENCH, PCBENCH, NETBENCH and INTEST. Cold image 31,440 bytes; SDRAM buffers after it
19.4 KB (the streams' rings: 4 x 4 KB). The tools lost the commands that used TYPE (`type`,
`kbd`) and those of long-gone features (`hdd-install`, `r-install`); the tools for H:, R:,
the modem and ASH were deleted.

**Firmware** (`core/firmware/pcnet.c`, new, cold): 4 streams (mailbox handles 4-7), 4 KB of
ring each in SDRAM; the gateway sends a stream's bytes only within the credit the board gave
(the ring's room, given back in steps of 1 KB). An OPEN, STAT or READ that waits for the
internet is put aside: the request ring moves on and the answer comes later (matched by TAG),
so the I/O processor never waits for the internet and other programs' file requests go on.
Bytes for a waiting READ go straight into the 65C816's buffer (the hot `pc_put816`). New
mailbox event $E4 NET (a connection has news). Nothing new runs from SDRAM in the idle loop:
the main loop checks a flag (and, while requests are put aside, a 250 ms timer).

**Board** (build `core/impl/net1/`, from SRAM first):

| Test | Before (step 22) | After |
| --- | --- | --- |
| Self test A816.BIN | 11 OK + DONE | 11 OK + DONE |
| FSBENCH write / read / load | 5.11-5.33 / 3.10 / 3.09 s | 4.93-5.31 / 3.10 / 3.10 s |
| PCBENCH write / read / load (512 KB) | 9.23 / 5.14 / 5.06 s | 9.22 / **4.00** / **3.90** s (read 131 KB/s) |
| NETBENCH: 1 MB from a web server on the PC (`http://127.0.0.1`) | - | 13.0 s, **80 KB/s** |
| NETBENCH: 100 round trips of one byte on a TCP connection (polled) | - | 1.21 s, **12 ms** each |
| INTEST (no input lost; longest look gap) | 0 lost; 10.3 ms | 0 lost in all 4 phases; 10.0 ms |
| Desktop screenshot (`shot816`) | 2.3 s | 5.7 s (F) |
| Boot to the main loop (first contact after loading) | ~1.1 s | ~1.2 s |

`sw/a816/NETBENCH.BIN` needs `core/tools/netbench_servers.py` (a web server and an echo server
on the PC's loopback); with an older gateway it stops at once with $8A (no such service).

**Build** (place_option 1; the netlist did not change): logic 16,596 / 20,736 (81 %), CLS
9,395 (91 %), registers 8,325, block RAM 44 / 46; clk_core 31.85 MHz (rule 29.7), clk_pix
89.83, sys_clk 41.34.

**Horizon 0.22 on the board** (gateway `tools/atari816-link`, the board flashed with `net1`):

- `get https://example.com/ /PC:/EX.HTM`: 577 bytes, the same MD5 as curl's copy on the PC.
  `get https://ftp.gnu.org/gnu/hello/hello-2.12.1.tar.gz` (1,033,297 bytes) to the card in
  about 27 s (with the card's writes); copied to /PC:, its MD5 equals a direct download's.
  `get ftp://ftp.gnu.org/gnu/hello/ /PC:/` gave the folder's listing (the gateway now keeps only
  the name of NLST answers that come with the folder in front).
- ctrl-C during `get` to the card and to /PC: (a 1 MB file from a web server on the PC):
  "cancelled", no file on either side. This found a kernel bug older than this step:
  input_poll ignored the Terminal window's keys, so `cp`'s and `get`'s ctrl-C in the Terminal
  window was only seen at the next prompt (fixed in 0.22). Developer KEY injections are
  released by the firmware's main loop, so while the card deletes a partial file the key looks
  held and repeats (`^C` lines at the prompt): a test artefact, a real keyboard's release goes
  through the input layer.
- Gateway killed (SIGKILL) during `get`: "the PC link was lost", no partial file. During a BBS
  session: "The PC link was lost: the connection ended."
- Input during a download and during an open BBS session (developer INJECT, 500 mouse reports
  each): none lost; longest look gap 17.1 ms and 9.6 ms.
- The BBS program against `horizon/tests/bbsserver.py` on the PC (no public board is in the
  address book): the ATASCII test screen with graphics characters and inverse video; the
  telnet answers (WILL TTYPE, DO ECHO, DO SGA, WONT NAWS, terminal type "ATASCII"); echo; the
  remote close message.
- The Downloader (Programs menu): progress "258 of 1,024 KB (25%)" with the bar; Cancel:
  "Cancelled: nothing was saved.", no file; a file that is there: "Replace it?".
- `--no-net` gateway: NETBENCH stops at once with $8A; an old gateway too.
- Classic machine: `run /BLUE.XEX` from the shell, COLOR4 = $94, F12 back.

**Flash:** `core/impl/net1/` (bitstream, report, timing, `cold.bin`) is in flash (`cold.bin` at
0x500000, then the bitstream); the board came up from flash to the Horizon 0.22 desktop and the
self test passed (11 OK + DONE). `core/impl/input1/` is the fallback (with its own `cold.bin`).
