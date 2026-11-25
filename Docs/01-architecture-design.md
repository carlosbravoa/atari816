# Atari816: System Architecture Design v0.1

Nov 16, 2026 · @Carlos

> **A historical document.** This is the design written before the machine was built. Some
> of it was built differently or not at all (for example the 16 MB option and other
> candidates it weighs). What the machine is now: [architecture/](architecture/README.md)
> and the register specification, [02-register-spec.md](02-register-spec.md).

## Summary and goals

The Atari816 is two machines in one box: a 65C816 desktop computer with 16 MB of RAM, and a complete Atari 8-bit that lives inside it as a sandboxed "classic session". The recommended design gives the classic side its own cycle-exact 6502 core and the original chipset, so 8-bit software keeps exact timing and illegal opcodes, while the 65C816 desktop keeps running next to it.

Design goals:

- **Full classic compatibility:** 400/800, XL and XE (including 130XE banked RAM), NTSC and PAL, illegal opcodes, cycle timing.
- **A real desktop:** mouse, windows, icons, file manager, multitasking.
- **One-click classic:** launch an 8-bit title from an icon, return to the desktop with one key, with save states.
- **Persistence:** hard disk on SD card, files exchangeable with a PC.
- **Networking:** built around FujiNet, so classic programs get N: devices and native apps get sockets.
- **FPGA first:** every block maps onto proven open cores where one exists.

Working names used below, all open to change: **Atari816** (the machine), **Horizon** (the native OS), **FREDDIE II** (memory controller, named after the XE's memory chip), **Marga** (the video chip; first called NVC, native video controller), **Ali** (the blitter) and **Lau** (the sample player). The register prefixes keep the old names (NV\_\*, BL\_\*, AU\_\*).

## System overview

```
            Native side              Shared                   Classic side
   +------------------+     +------------------+     +--------------------+
   | 65C816 CPU       |<--->| FREDDIE II       |<----| NMOS 6502 core     |
   | 14.3 MHz,Horizon |     | native + classic |     | 1.79 MHz, 64 KB map|
   +------------------+     | map, ABORT prot. |     +--------------------+
            ^               +------------------+               ^
            v                        ^                         v
   +------------------+     +------------------+     +--------------------+
   | Native I/O       |     | 8 MB SDRAM       |     | Classic chipset    |
   | timers, IRQs,    |     | (16 MB on bigger |     | ANTIC GTIA POKEY   |
   | IOP mailbox      |     |  boards)         |     | PIA, cycle-exact   |
   +------------------+     +------------------+     +--------------------+
            ^                        | framebuffers            | picture (frame
            v                        v                         v  buffer 3x), audio
   +------------------+     +------------------+     +--------------------+
   | I/O processor    |     | Marga            |---->| HDMI out           |
   | PicoRV32: SD,    |     | 640x360 desktop, |     | switches classic / |
   | FAT32, USB, SIO  |     | Ali, pointer     |     | desktop, 720p60    |
   +------------------+     +------------------+     +--------------------+
     I/O processor <== SIO bus (disk images today, FujiNet N: later) ==> chipset
```

FREDDIE II is the hinge: it gives the 65C816 a flat 16 MB and gives the 6502 core only the 64 KB classic map of the running session. Classic sessions are full screen: the HDMI output switches between the classic picture and Marga's desktop, while Horizon keeps running in the background either way.

## CPU and 8-bit compatibility

Recommendation: the 65C816 is the system CPU and always runs the desktop; a cycle-exact NMOS 6502 core (a "SALLY" equivalent) runs classic sessions as a compatibility co-processor, the way the PlayStation 2 kept a PS1 CPU on board. On an FPGA the second core costs very little.

### Why a plain 65C816 is not enough

In emulation mode the 65C816 behaves like a 6502, but not like the NMOS 6502C that Atari shipped:

- **Illegal opcodes:** the NMOS undocumented opcodes (LAX, SAX, DCP, ISC and friends), used by many games and most demos, are new instructions on the 65C816 (COP, JSL, JML, WDM and so on). Those also let a classic program escape its 64 KB sandbox.
- **Read-modify-write:** NMOS writes the old value back before the new one; the 65C816 does an extra read instead. A few hardware tricks depend on the double write.
- **Small differences:** the JMP ($xxFF) page bug is fixed, decimal mode sets flags differently and takes an extra cycle, interrupts clear the D flag, and some dummy bus cycles hit different addresses.

### Options

| Option | How it works | Classic compatibility | Desktop during a game | FPGA cost |
| --- | --- | --- | --- | --- |
| **A. Dual CPU (recommended)** | 65C816 for native, separate NMOS 6502 core for classic | Exact, including illegal opcodes and timing | Keeps running in the background | One extra small core |
| B. Single 65C816 with an "NMOS personality" bit | Custom 65C816 core that decodes the NMOS opcode table in emulation mode | Near exact, needs careful core work | Frozen while the game runs (Apple IIgs style) | Custom core changes |
| C. Stock 65C816 emulation mode | Real silicon behaviour | Breaks illegal-opcode software and some timing | Frozen while the game runs | None, also works with a real W65C816S chip |

Option A also makes the supervisor simple: freezing a game is stopping a clock enable, and the classic CPU physically cannot see memory outside its map. Option C only matters if a real-silicon board is ever wanted.

### Clocks

- **Classic:** 1.7897725 MHz (NTSC) or 1.7734475 MHz (PAL), with ANTIC cycle stealing exactly as on the real machine. A per-title "turbo" setting can raise it for productivity software that tolerates it.
- **Native:** 14.318 MHz baseline (4 times the NTSC colour burst, exactly 8 times the NTSC classic clock), so one master clock with clock enables drives both sides. Higher is welcome if the FPGA core and memory allow it.
- **Interrupts and syscalls:** the native side uses the 65C816's COP instruction for system calls and its ABORT input for memory protection (see the memory section).

## Memory map

All 16 MB is one flat RAM pool on the 65C816's 24-bit bus; there is no ROM in the map except a tiny boot ROM. Each classic session is a 64 KB (or larger) slice of that pool, seen by the 6502 core through a classic map that FREDDIE II rebuilds per session.

### Native view (65C816)

| Range | Size | Use |
| --- | --- | --- |
| $00:0000 to $00:CFFF | 52 KB | Bank 0 RAM: direct pages and stacks (the 65C816 requires both in bank 0), interrupt trampolines |
| $00:D000 to $00:D7FF | 2 KB | Classic chipset window (GTIA, POKEY, PIA, ANTIC), usable by native code only when no classic session owns the chips |
| $00:D800 to $00:DFFF | 2 KB | Native I/O: FREDDIE II, Marga, Ali, audio (POKEY, Lau, OPL2), interrupt controller, timers, SD, companion link, classic supervisor |
| $00:E000 to $00:FFFF | 8 KB | Kernel entry points and 65C816 vectors, in RAM, write-protected after boot |
| $01:0000 to $0F:FFFF | 960 KB | Kernel, drivers, GUI toolkit, fonts, disk cache |
| $10:0000 to $FF:FFFF | 15 MB | General pool in 64 KB banks: apps, documents, framebuffers, classic sessions, ROM images |

The first hardware has 8 MB, so the pool ends at $7F:FFFF; nothing else changes, and 16 MB stays the spec for bigger hardware. A typical 8 MB load: kernel and GUI about 1 MB, one 640x360x8 desktop framebuffer 225 KB, the classic frame buffer 92 KB, classic ROM library 256 KB, one 130XE session 128 KB, leaving roughly 6 MB for applications and data.

**Bank 0 is the scarce resource.** Every task needs its direct page and stack there. FREDDIE II can remap $00:0000 to $00:7FFF per task, so each task gets a private 32 KB bank 0 area and the shared kernel area stays at $00:8000 and up.

### Protection

The 65C816 has no user mode, so FREDDIE II adds one: a user/supervisor flag that hardware clears on every interrupt or COP vector fetch, plus a 256-entry table (one per 64 KB bank) of owner and write permission. A user-mode access to a bank it does not own asserts the 65C816's ABORT pin, which cancels the instruction cleanly and enters the kernel. A crashing desktop app then kills only itself.

### Classic view (6502 core)

The 6502 only ever issues 16-bit addresses. FREDDIE II translates each region through a pointer register, which is how one design covers every model:

| Classic range | Maps to |
| --- | --- |
| $0000 to $3FFF | Session main RAM |
| $4000 to $7FFF | Main RAM, or an extended bank selected by PORTB (130XE scheme up to 1 MB, separate CPU and ANTIC access bits) |
| $5000 to $57FF | Self-test ROM image when PORTB bit 7 selects it (XL/XE) |
| $8000 to $BFFF | RAM, BASIC image, or cartridge image (bank switching via $D500 for common cartridge types) |
| $C000 to $CFFF | XL OS image or RAM (PORTB bit 0) |
| $D000 to $D7FF | The real chipset; $D100 to $D1FF also holds a mailbox to the native side |
| $D800 to $FFFF | OS image or RAM (PORTB bit 0) |

A **machine profile** (800 48K with OS-B, 800XL 64K, 130XE, 1 MB XE) is just a set of values for these registers plus ROM image choices. ROM images live in write-protected banks and are shared by all sessions. ANTIC's DMA fetches go through the same map, so display lists read exactly what the CPU reads.

In native mode ANTIC gets a bank register too, so native programs can use classic display lists anywhere in 16 MB.

## Video and sound

The original ANTIC, GTIA and POKEY stay untouched for classic sessions; a new video chip, Marga, draws the desktop. Classic sessions are full screen only, so the HDMI output simply switches between the two pictures and the two video paths never compete for memory bandwidth.

### Marga, the video chip (first called the native video controller, NVC)

- **Desktop mode:** 640 pixels wide at 8 bits per pixel, default palette = the GTIA 256-colour palette so native and classic colours match. The desktop is 640x360 (16:9), 225 KB, shown at exactly 2x. A 4 bpp mode halves memory and bandwidth.
- **Framebuffer in main RAM**, single-buffered by default (double-buffered if bandwidth allows), any 64 KB-aligned address.
- **Blitter (Ali):** rectangle copy and fill, 1-bit to 8-bit expansion for fonts and icons, transparent colour, clipping. Required: a 14 MHz 65C816 moving 300 KB by hand needs several frames, so the GUI lives or dies on the blitter.
- **Hardware mouse pointer** (32x32).
- **Sprites and fine scrolling (REV $0B):** 16 hardware sprites for games (16 or 32 pixels wide, 16 or 32 lines, 8 or 4 bpp with a palette bank, flips, 2x magnification, behind-the-bitmap bit), read from main RAM by Marga itself and merged in the scan-out path, with registers latched at vertical blank; pixel-exact horizontal and vertical scroll offsets, wrap-around in a larger virtual bitmap and a split screen for a fixed status panel. Details in the register spec.
- **Overlay:** the system menu shown over a frozen classic session, reusing the OSD overlay that the Tang Nano 20K core already has.

### Switching between classic and desktop

Everything leaves the machine as one standard 1280x720 at 60 Hz raster. The desktop is Marga's framebuffer at exactly 2x. A classic session's GTIA picture is written into a small frame buffer (384x240, 8 bpp, 92 KB) and read out at 3x, pillarboxed to 1152x720. The switch between the two is a source multiplexer in front of the HDMI encoder: same timing, so the monitor never resyncs. While a game is shown, the NVC stops reading the desktop framebuffer; while the desktop is shown, a frozen or suspended classic session uses no video bandwidth.

### Output

- **HDMI 1280x720 at 60 Hz (CEA standard)** for both pictures, so it works on strict displays too.
- **Classic latency:** the classic frame buffer adds about one frame. The Atari runs at 59.92 Hz, so one frame is repeated roughly every 12 s.
- **Low-latency option for purists:** the current core's genlocked line buffer (1056x720, 1 to 2 lines of latency) stays available as a setting for games; leaving the game then costs a monitor resync of a second or two.
- **PAL** is a later item; the classic frame buffer makes a 50 Hz source on a 60 Hz output possible.

### Sound

- **Classic:** POKEY as original. (Until REV $0B there was an optional second POKEY for stereo, the common stereo upgrade layout; it made room for the OPL2 in REV $0C.)
- **Native:** Lau, an 8-channel DMA sample engine (8 or 16 bit, up to 48 kHz) for desktop sounds, music and speech, plus a native-side POKEY for chiptune apps (the classic machine's own, playing a second register bank while that machine is frozen) and, from REV $0C, an OPL2 (YM3812) FM synthesizer for MIDI music.
- A mixer combines both sides, with per-session volume. Output over HDMI audio and a line-out (I2S DAC or PWM).

## Input, storage and networking

For v1, the I/O processor is the PicoRV32 already inside the Tang Nano 20K core: it already does the SD card, FAT32, USB keyboard, SIO disk emulation, H:, the OSD and the PC Link. Horizon communicates with it through a mailbox, the same way the 65C816 would drive any I/O chip. A FujiNet ESP32 on the SIO pins (already analysed in `docs/fujinet_esp32_bridge.md`) is the planned networking add-on; whether it also takes over USB input is still open (decision 6).

### Input

- **Keyboard:** USB keyboard via the I/O processor (CH9350 or Pico adapter today). With the desktop focused, keys go to Horizon as events. With a classic session focused, a virtual keyboard matrix feeds POKEY's scan exactly like the real keyboard; F2 to F4 map to Start, Select, Option, and a dedicated System key (for example the Windows key or F12) always goes to the supervisor, never to the game.
- **Mouse:** USB mouse via the I/O processor (the CH9350 also reports mice), driving Marga's hardware pointer. For classic programs that support an ST or Amiga mouse on a joystick port, the supervisor can emulate one from the USB mouse.
- **Joysticks:** two real DB9 ports (Atari joysticks and paddles) on the classic PIA and POKEY, readable by native games too, plus USB gamepads mapped onto them.

### Storage

- **Hard disk:** one SD card on the FPGA, owned by Horizon (see Persistence). The "hard disk" holds the OS, apps, documents and the 8-bit library.
- **Classic disks:** the native side handles SIO commands for D1: to D8: from ATR images on the hard disk, like a built-in SIO2PC, including high-speed SIO. No real drive needed.
- **Fast host access for classic:** an H: device handler (as in the Atari800 emulator) reaches native files through the $D1xx mailbox, for loading XEX files or saving from classic programs straight to the hard disk.
- **Real SIO connector** kept on the back, so a real 1050, printer or external FujiNet still works.

### Networking

- **Classic:** unmodified FujiNet firmware behaviour on the SIO bus: N: devices, TNFS disk mounts, network printers, clock.
- **Native:** a socket API (TCP, UDP, TLS offloaded to the ESP32, HTTP helper, NTP) over the native link. That is enough for a web or Gopher browser, Telnet, IRC, file download and TNFS browsing from the desktop.
- **Work needed:** FujiNet firmware gains a "native channel" protocol on SPI or a fast UART. FujiNet already supports several host buses, so this is a new bus adapter, not a fork.

### Expansion

A cartridge slot is optional on FPGA; cartridge images (.CAR) cover the need. A small PBI-style expansion header on the native bus is worth reserving for future hardware.

## Native OS (Horizon)

Horizon is a small preemptive multitasking kernel with hardware memory protection, written for the 65C816 in native mode. Sixteen megabytes and a protection unit let it behave like a 1990 workstation rather than an 8-bit DOS.

### Kernel

- **Tasks:** preemptive, priority round robin, driven by a timer IRQ. A context switch saves A, X, Y, DP, DBR, PBR, S and P, and swaps the task's bank 0 window (see Memory map).
- **System calls:** the COP instruction, with the call number as its operand. COP vectors through the kernel and flips FREDDIE II to supervisor mode in hardware.
- **Memory:** a bank allocator (64 KB units) and a small-block heap per task. Freed automatically when a task ends.
- **IPC:** message ports, as on the Amiga. The GUI, file system and network services are tasks that receive messages.
- **Drivers:** SD card, FAT32, Marga and Ali, audio, input events, network (companion link), classic supervisor.

### Programs

- **Executable format:** relocatable, based on the o65 format (which already describes 65816 code), so programs load into any bank.
- **Shared libraries:** jump tables called with JSL, versioned, loaded once (GUI toolkit, math, file dialogs, networking).
- **Toolchain:** ca65/ld65 from cc65 for assembly and a 65816 C compiler (Calypsi is one candidate) for apps. Both need a quick check before committing.
- **Command line:** a SpartaDOS-flavoured shell in a window, for scripting and power users.

### Boot

1. FPGA loads; the PicoRV32 I/O processor starts from its block RAM firmware, as it does today.
2. The I/O processor reads `/SYSTEM/HORIZON.SYS` from the SD card into bank $01 and releases the 65C816 from reset; the kernel copies its vectors to $00:E000 and write-protects them.
3. Kernel starts drivers, loads ROM images for the classic library, starts the desktop.
4. If the SD card is missing or broken, the boot ROM shows a recovery screen that can load a kernel over the USB-C PC Link, so the machine is never a brick.

## Desktop and applications

The desktop is a classic 1980s-style WIMP (menu bar, windows, icons, pointer) with one modern habit that 16 MB allows: every window keeps its own off-screen backing store, so moving or uncovering windows is a blitter copy, not an app redraw.

- **Look:** a Fuji menu at the top left (About, Control Panel, running tasks, Shut down), app menus beside it, a desktop of drive and folder icons, and a task strip listing running apps and classic sessions.
- **GUI server:** a kernel task that owns the screen, routes input, and composites window surfaces with the blitter. Apps draw into their own surface through the GUI library (lines, rectangles, text, icons, bitmaps) and report to the server which part changed.
- **Cost check:** a full-screen window surface is 225 KB at 8 bpp, so ten large windows use about 2.3 MB of the roughly 6 MB free on the 8 MB machine. That is the trade that GEM and GEOS could not afford.
- **Toolkit:** buttons, menus, lists, text fields, scroll bars, file dialogs, alerts. Bitmap proportional fonts, with the Atari 8x8 font as the system mono font.
- **File manager:** browse the SD card and TNFS servers, open documents with their app, show 8-bit files (XEX, ATR, CAR, BAS) as classic icons.
- **Clipboard:** text and bitmaps between native apps, and a bridge to classic sessions (next section).

## Launching and closing 8-bit titles

A classic title is launched by double-clicking it, runs on its own hardware with exact timing, and is closed with the System key. The classic program has no access to the desktop and cannot detect it.

### Launch

1. The user double-clicks a XEX, ATR, CAR or BAS file (or a library entry).
2. Horizon reads its **profile**: a small sidecar file next to the title (or a default) naming the machine (800 48K, XL, 130XE, 1 MB), OS image (OS-B, XL, AltirraOS), BASIC on or off, NTSC or PAL, disks for D1: to D8:, cartridge type, joystick mapping, turbo.
3. The supervisor allocates the session's RAM, points FREDDIE II's classic map at it and the ROM images, mounts the disk images on the native SIO responder, and hands the classic chipset to the session.
4. It releases the 6502 core from reset. The classic OS cold-starts and boots the title exactly as a real machine would (XEX files load through a tiny boot loader, as emulators do).
5. The HDMI output switches to the classic picture, and keyboard and joysticks go to the session.

### Running

- The 65C816 keeps running the desktop. Downloads, music and other apps continue.
- Only one session at a time drives the real chipset. Other sessions can be **suspended** in RAM and resumed later; they appear in the task strip.

### Close

1. The user presses the System key (F12, as the OSD key on the current core).
2. The supervisor freezes the 6502 at the next vertical blank, on an instruction boundary. Freezing at vertical blank keeps ANTIC's state simple to capture.
3. An overlay menu appears over the frozen picture: **Resume**, **Save state**, **Reset**, **Suspend to desktop**, **Quit**.
4. Quit frees the session's memory, unmounts its images and returns the chipset. The desktop is already there, so return is instant.

The supervisor also steps in when the 6502 hits a jam (KIL) opcode, when a classic program requests an exit through the $D1xx mailbox, or when a breakpoint fires.

### Save states and debugging

A save state is the 6502 registers, the session RAM and extended banks, and the full internal state of ANTIC, GTIA, POKEY and PIA. Those chips have write-only registers on the original, so the FPGA versions get a read-back path that only the supervisor can see. The same path gives a built-in debugger: step, breakpoints, memory and chip views.

### Clipboard bridge

- **Copy from classic:** the supervisor walks the session's display list and screen memory and turns text-mode screens into text.
- **Paste into classic:** text is typed into the session through the virtual keyboard matrix, at a speed the classic program can absorb.

## Persistence and productivity software

The hard disk is a FAT32 SD card that a PC can read directly, and the first productivity apps are a small, useful set built on the shared GUI toolkit.

### File system

- **FAT32 with long file names**, so the same card can be filled with ATR and XEX files on a PC. exFAT is avoided for complexity.
- **Layout:** `/SYSTEM` (kernel, drivers, libraries, fonts), `/APPS`, `/DOCS`, `/CLASSIC` (titles, profiles, save states, ROM images), `/HOME` (settings).
- **Safety:** FAT32 is not crash-safe, so Horizon writes new files to a temporary name and renames on close, and flushes metadata promptly. A journaled file system is a later option, not a v1 need.
- **ROM images:** AltirraOS and Altirra BASIC ship as the defaults, because they can be redistributed (to confirm). Users can drop original Atari ROM dumps into `/CLASSIC/ROMS`.

### First set of native apps

| App | What it does |
| --- | --- |
| Files | File manager, local and TNFS |
| Write | Word processor with fonts and print to FujiNet printers |
| Calc | Spreadsheet, using the 16 MB for large sheets |
| Paint | 8 bpp paint program with the GTIA palette |
| Term | Telnet and serial terminal (VT100) |
| Browse | Gopher and simple HTML browser over the companion's HTTP and TLS |
| BASIC 816 | Turbo-BASIC-style language with access to all 16 MB and the GUI |
| Tracker | Music tracker for the sample engine and POKEY |
| Monitor | Assembler, debugger and memory viewer for native and classic code |

Classic productivity software (AtariWriter, SynCalc, SpartaDOS X tools) also runs, full screen, with files reaching the hard disk through H: or ATR images.

## Decisions

Carlos settled these on 2026-11-16; the rest of this doc follows them. Row 10 was added and settled the same day.

| # | Decision | Choice | What it means for the design |
| --- | --- | --- | --- |
| 1 | How classic code runs | **Dual CPU** | 65C816 for Horizon, separate NMOS 6502 core for classic sessions |
| 2 | Classic on screen | **Full screen only** | No capture buffer or window compositing. The HDMI output switches between the classic picture and the desktop, and the classic and native video paths never run at the same time |
| 3 | Native multitasking | **Preemptive with protection** | COP syscalls, user mode and ABORT in FREDDIE II |
| 4 | Desktop resolution | **640x360 desktop on 1280x720 output** | Changed from 640x480 after row 10; 16:9, exactly 2x |
| 5 | Native CPU clock | **14.3 MHz spec, faster as a setting** | Software must work at 14.3 MHz; a turbo setting is allowed where hardware gives more |
| 6 | Networking and I/O companion | **Open; FujiNet makes sense** | v1 uses the PicoRV32 I/O processor already in the Tang Nano 20K core; a FujiNet ESP32 on the SIO pins is the planned add-on |
| 7 | File system | **FAT32** | Same card layout as the current Tang Nano 20K core |
| 8 | Default classic ROMs | **AltirraOS and Altirra BASIC** | Original ROM dumps optional |
| 9 | RAM | **8 MB, 16 MB optional** | 8 MB on the Tang Nano 20K; 16 MB stays possible on bigger hardware (MiSTer) |
| 10 | Video output | **Standard 720p60, one raster** | Machine-first spec: desktop at 2x, classic through a frame buffer at 3x, instant switching. The current core's genlocked line buffer stays as a low-latency option for games |

## FPGA plan: Tang Nano 20K first

The Tang Nano 20K is a realistic first target if the Atari816 is built on top of the existing [atari800\_tang\_nano20k](https://github.com/carlosbravoa/atari800_tang_nano20k) core. The hard limit there is SDRAM transactions and block RAM, not logic: the 65C816 needs a small cache to get near 14 MHz. MiSTer is the fallback with plenty of headroom.

### What the existing core already gives

| Need in this design | Already in atari800\_tang\_nano20k |
| --- | --- |
| Classic machine | 800, XL, 130XE and RAMBO up to 320 KB (capped in step 17 of the bring-up), exact NTSC speed, ACID800 57/57, dual POKEY |
| Memory | 8 MB on-package SDRAM (32-bit), working controller and arbiter |
| Video out | Genlocked 1056x720 HDMI line buffer (3x), about 1 to 2 lines of latency, HDMI audio |
| I/O processor | PicoRV32 firmware with FatFs, SD card, USB keyboard, SIO disk emulation D1: to D4:, H:, PC Link, OSD |
| Classic memory map | The address decoder in `src/`, which is where FREDDIE II's per-session classic map goes |
| Loading titles | ATR, XEX and CAR loading, 52 cartridge types |
| Networking | FujiNet ESP32 bridge analysed (3 pins), not built |

### What is new

1. **65C816 core**, ported from the MiSTer SNES core, clocked at clk\_core ÷ 2 = 14.34 MHz (28.6875 MHz ÷ 2, within 0.2% of the 14.318 MHz spec). Turbo means clk\_core ÷ 1 if timing closes.
2. **A 2 to 4 KB cache for the 65C816**, filled with 4-word SDRAM bursts (the BL4 path already designed in `docs/framebuffer_feasibility.md`).
3. **FREDDIE II:** native map, per-session base registers in the classic address decoder, protection table and the ABORT signal.
4. **Marga:** framebuffer reader using bursts, a simple blitter (fill and copy first), mouse pointer, and a source switch in front of the HDMI encoder.
5. **Supervisor:** freeze the 6502 at vertical blank, chip-state readback, mailbox to Horizon.
6. **I/O processor mailbox protocol** for files, input events and, later, sockets.

### Budget on the Tang Nano 20K

| Resource | In use today | The new blocks need | Verdict |
| --- | --- | --- | --- |
| LUTs (20.7 K) | About 11.3 K (build snapshot in `docs/PHASE_AB_TESTING.md`) | 65C816 3 to 5 K, FREDDIE II about 1 K, Marga and a simple blitter 2 to 4 K | Tight but plausible |
| Block RAM (46 blocks) | 42 in that snapshot; the firmware shrink freed some since | Cache 1 to 2 blocks, Marga's line buffer 1 block | The real squeeze; needs a fresh count |
| SDRAM transactions | About 4.8 M/s single-word; the Atari uses about 1.8 M/s (37%) | An uncached 65C816 at 14 MHz could request up to 14 M/s | Impossible without the cache; fine with the cache and BL4 bursts for video |
| PLLs (2) | Both used | One PLL for the standard 720p HDMI clock (74.25 MHz, as in release v1.1), one for the core; the 65C816 runs on clk\_core ÷ 2. The low-latency option switches the HDMI clock source with a clock mux | OK |

Full screen only helps here: during a game only the classic frame buffer streams run, and on the desktop only Marga's reader runs, so the video clients never stack on the arbiter. LUT and speed figures for new blocks are estimates.

### One standard raster

The machine defines its own output instead of inheriting the current core's: standard 720p60, with the desktop at 2x and classic sessions through a frame buffer at 3x. This is the same conclusion as the repo's `docs/exact_speed_scaler.md`: exact speed plus a steady, standard picture needs a frame buffer. The frame buffer writer and reader need the BL4 burst path from `docs/framebuffer_feasibility.md`, which the 65C816 cache needs anyway.

### MiSTer as fallback

The DE10-Nano has far more logic, DDR3, and the SDRAM module, so 16 MB is easy. It also runs Atari800\_MiSTer, the core the Tang Nano 20K port came from, and the SNES core whose 65C816 we would reuse. Keeping every new block portable both ways costs little.

## Next steps

With the decisions settled, the next work is register-level specs, then a first 65C816 bring-up inside the existing Tang Nano 20K core.

1. Done: all ten decisions settled.
2. Take a fresh resource count (LUTs, block RAM) of the current Tang Nano 20K build, since the budget depends on it.
3. Done: register-level specs are in `02-register-spec.md`.
4. Bring-up 1: the 65C816 core with its cache on the Tang Nano 20K next to the Atari core, running a test program from SDRAM and printing through the OSD.
5. Bring-up 2: Marga's framebuffer and the HDMI source switch, then the freeze-and-return path for classic sessions.
6. Horizon kernel, then the desktop, developed in parallel on a software model (an emulator extended with the 65C816, FREDDIE II and Marga).
7. FujiNet ESP32 bridge as the networking add-on.
