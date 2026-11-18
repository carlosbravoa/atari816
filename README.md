# Atari816

**A 16-bit Atari and desktop on the 65C816, with original 8-bit Atari compatibility.**

The Atari816 is a new 16-bit machine re-imagined around the 65C816: an Atari that never
existed. It has its own operating system (Horizon), its own programs, an emulator and an SDK,
and it runs on a Sipeed Tang Nano 20K FPGA board. Horizon is a preemptive multitasking kernel
with memory protection and a mouse-driven desktop (windows, icons, a terminal, and
applications such as Files, Edit, Write, Sheet, Paint, BASIC, a Downloader and a BBS terminal). Its own custom chips are
FREDDIE II, the memory manager, Marga, the video chip, Ali, the blitter, and Lau, an 8-voice
sample player, next to a second POKEY (POKEY 2).

Inside the same FPGA is a complete, cycle-exact Atari 8-bit computer (400/800/XL/XE), so
original 8-bit software runs on its own hardware; F12 switches between it and the desktop.

![The Horizon desktop, captured from the board](Docs/images/horizon-desktop.png)

*The Horizon desktop, captured from a Tang Nano 20K (640 x 360, 256 colours).*

## Status

Work in progress. The hardware, Horizon, the emulator and the SDK all work and are under
active development; interfaces can still change.

## What is where

| Directory | Contents |
| --- | --- |
| [`core/`](core/) | The hardware: the FPGA design for the Tang Nano 20K (the Atari 8-bit core, the 65C816 native machine in `core/src/a816/`), the I/O processor firmware and PC-side tools |
| [`horizon/`](horizon/) | Horizon, the operating system, and its programs (65816 assembly, ca65/ld65) |
| [`emu/`](emu/) | emu816, a C emulator of the native machine, for developing on a PC |
| [`sdk/`](sdk/) | The SDK: getting-started guide, programmer's reference, templates, examples, tools |
| [`tools/`](tools/) | `atari816-link`, the PC side of the PC link (shares a folder of the PC with the Atari816, and connects it to the internet) |
| [`Docs/`](Docs/) | Design documents: architecture, register specification, bring-up log, the PC link |

## How to try it

- In the emulator, no board needed: [`sdk/docs/getting-started.md`](sdk/docs/getting-started.md)
  (build `emu/` and `horizon/`, then run Horizon).
- On a Tang Nano 20K: build and flash the hardware as described in
  [`core/README.md`](core/README.md), then prepare a FAT32 SD card with Horizon as described
  in [`sdk/docs/getting-started.md`](sdk/docs/getting-started.md), section 6, and
  [`horizon/README.md`](horizon/README.md).

## The PC link

The USB cable that powers the board also connects it to the PC. With the gateway running on
the PC, one folder of the PC appears on the Atari816 as a second volume, **`/PC:`**: a "PC"
icon on the desktop, a `PC:` folder in Files, usable from the shell and from every program
(copy between the card and the PC both ways, open and save, start programs from it). The
Atari816 also takes the PC's time when the gateway connects, so the clock no longer needs to
be set by hand.

The gateway also brings the **internet** to the Atari816: a URL is a file name. `get
https://example.com/file.zip` in the shell (or `cp https://... /somewhere`, or the Downloader
on the Programs menu) downloads a file; `http://`, `https://` and `ftp://` work. Programs can
open TCP connections (`tcp://host:port`): the **BBS** program on the Programs menu uses this to
reach the old Atari BBSes that are still on the internet by telnet. The PC does the hard
parts (names, TLS and certificates, redirects).

```
pip install pyserial
tools/atari816-link                 # shares ~/Atari816 (made if missing)
tools/atari816-link ~/somewhere     # shares another folder
tools/atari816-link --read-only     # the Atari816 can read, not change anything
tools/atari816-link --no-net        # no internet for the Atari816
```

Leave it running; stop it with Ctrl-C. It finds the board by itself and reconnects when the
board is reset or plugged in again. The icon appears within a few seconds and goes away when
the gateway stops.

- **Only that folder** is shared. Nothing outside it can be read or changed: `..`, hidden
  names (starting with `.`) and links that point out of the folder are refused.
- **It listens on no network port.** It only talks to the board over USB, and to the
  developer tools through a socket in your runtime folder that only you can use. It makes
  connections outwards for the Atari816 (the internet is on unless you start it with
  `--no-net`): **programs on the Atari816 can reach whatever the PC can reach, including your
  home network.**
- Without the gateway the Atari816 works as before; `/PC:` then answers "no PC link".
- Linux: your user must be allowed to use the serial port (group `dialout`). Stop the gateway
  before you load a new bitstream with openFPGALoader.

The protocol, for anyone who wants to write another gateway: [`Docs/04-pc-link.md`](Docs/04-pc-link.md).

## What you must supply yourself

The Atari OS and BASIC ROM images are **not included** in this repository and must not be
added to it. To run the 8-bit Atari side on the board you need your own ROM images (see
[`core/README.md`](core/README.md), "SD Card Setup").

## Licences

The repository is not under a single licence. Each directory has its own; the full texts are
in [`LICENSES/`](LICENSES/) and [`core/LICENSES/`](core/LICENSES/). See [`LICENSE`](LICENSE).

| Directory | Licence |
| --- | --- |
| `horizon/` | GPL-3.0-or-later |
| `emu/` | GPL-3.0-or-later |
| `tools/` | GPL-3.0-or-later |
| `sdk/` | MIT |
| `Docs/` | CC-BY-SA-4.0 |
| `core/` (original work) | CC-BY-NC-SA-4.0 OR GPL-3.0-or-later, at your option ([`core/LICENSE-PORT`](core/LICENSE-PORT)) |
| `core/` (third-party components) | Their own licences, listed in [`core/LICENSE`](core/LICENSE) |

**Bitstreams are non-commercial.** The 8-bit Atari core inside the hardware (Mark Watson's
atari800core) is offered by its author for non-commercial use only. Any bitstream built from
`core/`, including published `.fs` files, may therefore be used and shared for
non-commercial purposes only. Commercial use needs permission from Mark Watson and from the
other copyright holders whose licences do not already allow it. `core/LICENSE` explains this,
including the tension between that condition and the GPL of some components.

## Credits

The hardware builds on the work of others (details and licences in
[`core/LICENSE`](core/LICENSE)):

- Mark Watson: the Atari 8-bit core (atari800core, via
  [Atari800_MiSTer](https://github.com/MiSTer-devel/Atari800_MiSTer)).
- Peter Wendrich: the 6502 CPU core (FPGA 64).
- Matthias Reichl and Wojciech Mostowski: cartridge, freezer and PBI logic.
- Sergiy Dvodnenko (srg320), gyurco and nand2mario: the 65C816 CPU core (SNES_FPGA, via
  [SNESTang](https://github.com/nand2mario/snestang)).
- nand2mario: the PicoRV32 I/O subsystem and firmware base (NESTang/SNESTang) and the
  low-latency SDRAM controller.
- Claire Xenia Wolf: PicoRV32 and the PicoSoC UART.
- Bruno Levy: the SD-card SPI driver (learn-fpga).
- ChaN: FatFs.
- Sameer Puri: the HDMI library (hdl-util/hdmi).
- WangXuan95: the SD-card reader.
- Avery Lee: the Altirra palettes.

## Disclaimer

This is an independent hobby project. It is not affiliated with, endorsed by or sponsored by
Atari. Atari and related names are trademarks of their respective owners and are used here
only to describe compatibility and heritage.
