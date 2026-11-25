# The hardware

The Atari816 is one FPGA design for the Sipeed Tang Nano 20K (a Gowin GW2AR-18 with 8 MB of
SDRAM in its package). The design holds two computers that share the SDRAM and the HDMI
output: the native machine around a 65C816, and a classic Atari 8-bit. A small RISC-V
processor inside the same FPGA does the slow input and output for both.

This page describes what is built. The register-level definition is
[Docs/02-register-spec.md](../02-register-spec.md); where this page and the source differ, the
source wins (`core/src/a816/` for the native machine, `core/firmware/` for the I/O
processor). How to build and flash the bitstream: [core/README.md](../../core/README.md).
Open faults: [core/KNOWN_ISSUES.md](../../core/KNOWN_ISSUES.md).

## The parts at a glance

| Part | What it is | Where the source is |
| --- | --- | --- |
| 65C816 | the CPU core of the MiSTer SNES core (via SNESTang), 14.34 MHz, with a 4 KB cache | `core/src/a816/P65C816.v`, `a816_sys.sv` |
| FREDDIE II | the memory manager: bank table, user and supervisor modes, ABORT on a refused access, the bank 0 window | `a816_sys.sv` |
| System block | identity and revision, interrupts, two timers, the microsecond clock, the watchdog, keyboard routing, the joystick ports | `a816_sys.sv` |
| Marga | the video chip: three framebuffer modes, palette, hardware pointer, 16 sprites, fine scrolling | `a816_nvc.sv` |
| Ali | the blitter: fill, copy, keyed copy, 1-to-8 bpp expansion, command lists, colour remap | `a816_blit.sv` |
| Lau | an 8-voice sample player that reads its samples from RAM | `a816_snd.sv` |
| OPL2 | a YM3812 FM synthesizer (the JTOPL core by Jose Tejada Gomez) | `a816_opl.sv`, `jtopl/` |
| POKEY | the classic machine's sound chip, lent to the 65C816 while that machine is frozen | the classic core |
| I/O processor | a PicoRV32 with its firmware: SD card (FatFs), USB keyboard and mouse, the classic machine's disks, the PC link | `core/firmware/` |
| Mailbox | two rings of 16-byte messages in main RAM between Horizon and the I/O processor | `a816_sys.sv`, `firmware.c` |
| Classic Atari | an Atari 800XL/130XE-class machine: 6502, ANTIC, GTIA, POKEY, PIA (Mark Watson's atari800core) | `core/rtl/` |

## Revisions

A program reads the hardware revision (SYS_REV, `$00:DE01`; Horizon's `sys_info`) and uses
what that revision has. Each revision adds to the one before:

| REV | Adds |
| --- | --- |
| $06 | the native machine without native sound or blitter |
| $07 | native sound: the second POKEY and four 8-bit DACs |
| $08 | Ali, the blitter |
| $09 | Ali's command lists, Marga's vertical-blank interrupt and frame counter, raster events at the beam |
| $0A | Lau, the sample player |
| $0B | Marga's 16 sprites and fine scrolling |
| $0C | the OPL2; one POKEY (mono): the second POKEY and the DACs are gone, native sound plays from a second register bank of the one POKEY |
| $0D | Ali's colour remap |

The register specification (dated 2026-11-24) says REV $0D is the default build and is still
"to be built and checked on the board"; REV $0C has been run on the board. emu816 reports
$0D by default and can be told any older revision (`--rev`).

## The 65C816 and its memory

- **Clock.** The core runs at 28.69 MHz (clk_core) and the CPU takes a cycle every second
  clock: 14.34375 MHz. The emulator's microsecond clock uses the same figure
  (`floor(32 x cycles / 459)`).
- **Memory.** 8 MB of SDRAM, banks $00 to $7F, shared with Marga, Ali, Lau, the classic
  machine and the I/O processor. The CPU reads through a 4 KB direct-mapped cache (512 lines
  of 8 bytes) and writes through it to SDRAM. The I/O page ($00:Dxxx) is never cached.
- **What memory costs.** Every write waits for the SDRAM and every read miss fills a line.
  Measured on the board with `core/sw/a816/timing.s` (TIMING.BIN), a write costs about 3.7
  CPU cycles more than the ideal with the video off, 5.0 in the desktop's 640 x 360 x 8 mode
  and 9.3 while the classic machine runs; a read miss 5.8, 6.5 and 11.3. CPU-heavy code
  therefore runs at roughly half the speed the cycle counts of the data sheet promise
  ([emu/README.md](../../emu/README.md), "Memory timing").
- **Cache rule.** Ali, Lau and the I/O processor write and read SDRAM behind the cache. A
  program never sees this: the kernel writes CACHE_FLUSH (`$00:D80A`) before it reads what
  the blitter wrote, and the hardware sweeps the cache before each new mailbox answer.

## FREDDIE II: protection

The 65C816 has no user mode of its own. FREDDIE II adds one:

- **Two modes.** Every vector fetch (an interrupt, COP, BRK, ABORT, reset) enters supervisor
  mode in hardware. The kernel returns to user mode by arming a flag and executing RTI.
- **A bank table.** 256 entries, one per 64 KB bank: an owner (0 the kernel, 1 to 62 a
  task, 63 shared), a write bit and a valid bit. In user mode an access is allowed only to a
  valid bank owned by the current task (or shared), and a write only with the write bit.
  The I/O page is always refused in user mode.
- **ABORT.** A refused access raises the 65C816's ABORT input. The instruction ends
  without changing memory or registers, and the kernel's ABORT handler runs: Horizon kills
  that task and prints the cause and address. A program cannot reach the hardware or
  another program's memory.
- **The bank 0 window.** The 65C816 keeps its direct page and stack in bank 0. FREDDIE II
  replaces $00:0000-$7FFF with the current task's own 32 KB, so every task has a private
  direct page and stack; the kernel's stays above $00:8000. A task switch rewrites only the
  current task number and the window's bank, never the table.
- **Vectors.** $00:E000-$FFFF can be write-protected even against the kernel (WP_VEC).
- **NMI hold.** After an entry from user mode the hardware holds the NMI off until the
  kernel has moved to its own stack (since REV $04; `horizon/ABI.md`, "NMI hold").

Two faults in this logic were found with the emulator and fixed in the RTL (a refused COP
push that still entered supervisor mode, and emulation-mode interrupts that pushed B = 1):
[emu/README.md](../../emu/README.md), "RTL issues found".

## Marga, the video chip

- **Modes.** 640 x 360 at 8 bpp (the desktop), 640 x 360 at 4 bpp (the text console) and
  320 x 180 at 8 bpp, from a framebuffer anywhere in RAM, with a 256-entry palette. The
  picture goes out as 1280 x 720: 2 x 2 per pixel, 4 x 4 in the 320 x 180 mode.
- **Raster.** The output is 1572 x 760 pixel clocks at 71.71875 MHz: 60.03 frames a
  second, 238,944 CPU cycles a frame. (It is sent as 720p60; the CEA timing has other
  porches: [core/KNOWN_ISSUES.md](../../core/KNOWN_ISSUES.md), the first entry, is about the
  picture being lost now and then.)
- **Pointer.** A 32 x 32 hardware pointer in 2 bpp, drawn by Marga, moved by Horizon's
  interrupt service at each mouse event: the pointer moves while a program is busy.
- **Sprites (REV $0B).** 16 sprites read from RAM by Marga itself: 16 or 32 pixels wide,
  16 or 32 lines, 8 bpp or 4 bpp with a palette bank, flips, 2 x magnification, a "behind
  the bitmap" bit; a line takes as many as fit its width budget.
- **Fine scrolling (REV $0B).** Pixel offsets, horizontal wrap (a row is a ring) and
  vertical wrap, and a second scroll set from a split line (a fixed status panel).
- **Raster events (REV $09).** An interrupt at a chosen line and at the vertical blank, and
  a frame counter. Horizon uses the line interrupt for raster tables (palette changes at
  given lines); programs never run interrupt code.

## Ali, the blitter

Ali works on 8 bpp rectangles anywhere in RAM: FILL, COPY, COPY_KEY (one colour
transparent), EXPAND and EXPAND_KEY (1 bpp to two colours, for text and icons), with
strides and a backwards mode for overlapping moves. From REV $09 it runs **command lists**:
records in RAM, one after the other, a record optionally waiting for the vertical blank.

**Colour remap (REV $0D).** Ali holds a 256-entry table in its own block RAM. COPY_REMAP and
COPY_KEY_REMAP write `table[source pixel]` instead of the pixel: shades, fades, team
colours and night without the CPU touching a pixel or the palette. TABLE (op 5) loads the
table, or part of it, from RAM. In the RTL simulation (`core/sim_a816/tb_blit.sv`) a
320 x 200 remapped copy took between 10 % less and 12 % more time than a plain copy,
depending on the SDRAM's latency and burst length; the emulator charges +12 %. Horizon
0.31 uses it for its sheets (`sheet_draw`), and hgame for `hg_draw_remap`.

**Speed.** Measured on the board (TIMING.BIN), in clk_core cycles a pixel with the classic
machine frozen: FILL 2.06, COPY and COPY_KEY 2.90, EXPAND 2.27 with Marga off; 3.41, 4.50
and 3.77 in 640 x 360 x 8. With the classic machine running in 640 x 360 x 8: 7.0, 10.7
and 7.8. A fill is about 14 million pixels a second at best, a copy about 7.7 million
([sdk/docs/reference/hardware.md](../../sdk/docs/reference/hardware.md)).

**Rules.** No register write and no START while it is busy, and a cache flush before the
CPU reads what it wrote. Only the kernel drives Ali; the emulator counts every broken rule
and `run816.py` fails a run that broke one.

## Sound: Lau, the OPL2 and POKEY

Everything is mixed into the HDMI audio at 48 kHz.

- **Lau (REV $0A).** Eight voices of signed 8- or 16-bit PCM from anywhere in RAM. Each
  voice has a 24-bit start, length and loop point, a pitch in 2.14 fixed point
  (`$4000` = one sample per 48 kHz output sample) and two 8-bit volumes. After KEYON the
  hardware needs nothing more from the CPU. There is no interpolation (it did not fit the
  logic budget).
- **The OPL2 (REV $0C).** A YM3812, the AdLib card's chip: nine FM channels or six and five
  rhythm instruments, its two timers and its status as on the chip. Its clock is
  clk_core / 8 (3.5859 MHz), 0.18 % above the AdLib's: notes are 3 cents sharp.
- **POKEY.** While the classic machine is frozen (whenever the desktop is shown), the
  65C816 can play POKEY's four voices. From REV $0C they play from a second register bank,
  so a frozen game finds its sound as it left it.

## The system block

Interrupt status and enables for the vertical blank, the line event, two timers, the
blitter, audio, the I/O processor and the classic supervisor; an NMI for the system key
(F12) and the watchdog (2 s, armed by Horizon). A 32-bit microsecond counter (UPTIME). The
keyboard route (to Horizon or straight into the classic machine's keyboard matrix). The two
DB9 joystick ports, readable by the native side.

## The I/O processor and the mailbox

A PicoRV32 (RV32I) runs the firmware: FatFs on the SD card, the USB keyboard and mouse
adapter (a CH9350 or a Pico running TinyUSB, on one UART pin), the classic machine's disk
drives, executables and cartridges, and the PC link over the board's USB-C serial port at
1.5 Mbaud. Its hot part runs from 32 KB of block RAM; the rest is kept in SPI flash and
copied to SDRAM at boot (its CRC is checked against the bitstream's).

**The mailbox.** Horizon and the firmware exchange 16-byte messages through two rings of
256 entries in main RAM; the registers at $00:DD00 hold only the ring positions. A request
has an operation (OPEN, READ, WRITE, SEEK, STAT, READDIR, LOAD, ...), a tag, a buffer
address and arguments; the answer carries the same tag. Keys and mouse moves come as events
on the same ring, also while a long request is being served. Requests that wait for the
internet are put aside, so other requests go on meanwhile. The firmware reads and writes
the 65C816's buffers directly. The full list of operations is in the register
specification, "I/O processor mailbox".

**Boot.** The I/O processor holds the 65C816 in reset, loads `/SYSTEM/HORIZON.SYS` from
the card to $01:0000, writes a small reset stub and releases the CPU. Without Horizon on the
card it runs `/A816.BIN` (a bare-metal test program) instead.

**The PC link.** The same USB cable carries framed packets: the log, the PC's shared folder
(`/PC:`), the internet (URLs as file names, `tcp://` connections), printing to PDF and the
developer tools' requests. The gateway on the PC is [tools/atari816-link](../../tools/README.md);
its protocol is [Docs/04-pc-link.md](../04-pc-link.md).

## SD card and HDMI

- **SD card.** FAT32 with long names, read and written by the firmware's FatFs. Four files
  can be open at once in the whole system (handles 0 to 3; URLs and connections get 4 to 7).
  Paths are at most 127 characters. The card's per-request costs were measured on the board
  and are modelled by the emulator ([emulator.md](emulator.md)).
- **HDMI.** One raster for both machines, so switching between the desktop and the classic
  machine never makes the monitor resynchronise. The desktop is Marga's picture; the
  classic machine's picture is scaled 3 x through a genlocked line buffer.

## The classic Atari beside it

An Atari 8-bit (XL/XE, NTSC at its exact speed) with 128 or 320 KB, BASIC, `.atr`/`.xfd`
disks on D1: to D4:, `.xex` executables and cartridges of the common types, one POKEY,
two joysticks and the keyboard. The OS and BASIC ROM images are not included; you supply
them ([core/README.md](../../core/README.md), "SD card").

- **Frozen while the desktop is shown.** Horizon freezes it at boot and lets it run only
  while its picture is shown. F12 returns to the desktop exactly as it was.
- **Fast disk.** A parallel-bus device that the XL OS asks before it uses the serial port:
  a sector read takes about 3 ms instead of 90.
- **From Horizon.** Programs and the shell attach disks, executables and cartridges and
  start the machine through syscalls (`classic_mount`, `classic_boot`, `classic_show`); a
  folder of the card can be shown to it as an Atari DOS 2 disk, and what it prints becomes
  a text file in `/Printouts`.
- **Kept small on purpose.** The 8-bit machine is kept at the level needed to boot and run
  normal software; features beyond that (more RAM schemes, cartridge types, the second
  POKEY) were removed to make room for the native machine.

The register specification also describes parts that are designed but not built: the
classic supervisor's breakpoints, single step and chip-state read-back (for save states and
a debugger), the per-session classic memory map, a turbo speed and 16 MB of RAM. In the RTL
the supervisor implements the freeze (`SV_CTRL` bit 2) and nothing more.
