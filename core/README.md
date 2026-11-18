# Atari816 hardware (`core/`)

This directory is the hardware of the [Atari816](../README.md), a 16-bit Atari on the 65C816
with original 8-bit Atari compatibility, for the
[Sipeed Tang Nano 20K](https://wiki.sipeed.com/hardware/en/tang/tang-nano-20k/nano-20k.html)
(Gowin GW2AR-LV18QN88C8/I7). It holds:

- the FPGA design: the 65C816 native machine (`src/a816/`: CPU, FREDDIE II memory protection,
  system block, and the custom chips Marga, the video chip (with 16 sprites and fine
  scrolling from REV $0B), Ali, the blitter, and Lau, the 8-voice sample player), the shared
  SDRAM arbiter and HDMI output (`src/tang_top.sv`), and the 8-bit Atari (6502, ANTIC, GTIA, two POKEYs, PIA) based on
  Mark Watson's atari800core (`rtl/`, `src/address_decoder.vhdl`);
- the firmware of the PicoRV32 I/O processor (`firmware/`): SD card, the mailbox the 65C816
  talks to, the 8-bit Atari's disks, executables and cartridges, keyboard and mouse, PC link;
- 65C816 test programs (`sw/a816/`), simulations (`sim_a816/`) and PC-side tools (`tools/`).

The native machine's registers are specified in
[`../Docs/02-register-spec.md`](../Docs/02-register-spec.md); its history and the current
resource and timing figures are in [`../Docs/03-bringup1-log.md`](../Docs/03-bringup1-log.md).
Horizon, the operating system, is in [`../horizon/`](../horizon/).

## Build

Needs the Gowin EDA (V1.9.x) with a licence, `riscv64-unknown-elf-gcc`, `ca65`/`ld65`,
`openFPGALoader`, Verilator 5 (simulations) and Python 3.

```bash
export LM_LICENSE_FILE=/path/to/your/gowin_XXXXXXXX.lic   # build.tcl refuses to run without it
cd core
make -C firmware                  # firmware.bin -> src/fw_lane{0..3}.hex, plus firmware/cold.bin
/path/to/gowin/IDE/bin/gw_sh build.tcl > build.log 2>&1    # about 8 minutes
```

Result: `impl/atari800_tn20k/impl/pnr/atari800_tn20k.fs`; resource use in
`atari800_tn20k.rpt.txt`, timing in `atari800_tn20k_tr_content.html` next to it (clk_core
needs 28.69 MHz, clk_pix 71.72 MHz, sys_clk 27 MHz; the project keeps clk_core at 29.7 MHz or
more). The firmware hex files are tracked in git, so a bitstream-only build works without the
RISC-V toolchain, but always rebuild the firmware before the bitstream when it has changed.

### The firmware is in two parts

- **Hot** (block RAM, 32 KB, inside the bitstream): boot, SD and FatFs I/O, SIO, the mailbox,
  all data and the stack. Functions are made hot by listing them in `firmware/baremetal.ld`.
- **Cold** (`firmware/cold.bin`): everything else. It is kept in SPI flash at 0x500000 and
  copied to SDRAM at boot. The hot part carries the cold image's CRC-32, so a cold image from
  another build is refused (message on the serial log).

The firmware is RV32I (no compressed instructions, no multiply/divide). A bitstream and its
`cold.bin` always go together.

### Load and flash

```bash
openFPGALoader -b tangnano20k -f -o 0x500000 firmware/cold.bin            # cold firmware to flash
openFPGALoader -b tangnano20k impl/atari800_tn20k/impl/pnr/atari800_tn20k.fs   # bitstream to SRAM (lost at power-off)
./flash_it.sh                     # both to flash: cold.bin and the bitstream
```

Stop the PC link gateway (`../tools/atari816-link`) and any `tools/atari.py` command first: loads fail while the serial port is open.

## SD card

FAT32. In the root:

| File | |
| --- | --- |
| `ATARIXL.ROM` (16384 B), `BASIC.ROM` (8192 B) | The 8-bit Atari's OS and BASIC. **Not included; you supply them.** |
| `/SYSTEM/HORIZON.SYS` | Horizon (see `../horizon/README.md`); without it the I/O processor runs `/A816.BIN`, without both the 65C816 stays in reset |
| `/atari.ini` | The 8-bit Atari's settings (below); optional |
| `HDD.ATR` | Optional: mounted on D4: at every boot |
| `ASH.CAR` | Optional: the default cartridge when `boot=ash` |

### `/atari.ini`

Read at power-on and at a full restart (mailbox SYS_RESTART 1). Horizon's Settings program
edits it. One `key=value` per line; `#` starts a comment.

| Key | Values |
| --- | --- |
| `ram` | `128` (130XE, the default) or `320` (RAMBO). Any other value gives 320 KB and a line on the serial log |
| `stereo` | `1` = the second POKEY ($D210) on the right channel |
| `kbdlayout` | `0` Atari key positions, `1` US PC symbols |
| `joystick` | `1` = arrow keys are joystick 1, Left Alt is fire |
| `scanlines` | `0` off, `1` 25%, `2` 50%, `3` 75% |
| `hpos` | Horizontal picture position, 0 to 48 |
| `boot` | `ash` = `/ASH.CAR` is the default cartridge |

## The 8-bit Atari

XL/XE (NTSC, exact speed) with 128 or 320 KB, BASIC, `.atr`/`.xfd` disks on D1: to D4:,
`.xex` executables, cartridges (raw `.rom` of 2, 4, 8 or 16 KB; `.car` of the types standard
8/16 KB, OSS, XEGS and switchable XEGS, Atarimax 1 and 8 Mbit, SIC 128 to 512 KB, MegaCart
16 KB to 4 MB; other `.car` types are refused), two POKEYs, two joysticks, keyboard. No paddles. Horizon
loads software into it (`run FILE` in the Terminal, mailbox ops $18 to $1A) and switches to it;
F12 returns to the desktop and freezes it. The 8-bit machine is kept at the level of
compatibility needed to boot, run normal disks, executables and cartridges, and play sound and
joystick games; features beyond that were removed to make room for the native machine
(Docs/03-bringup1-log.md, steps 13 and 17).

## PC link and tools

The USB-C cable of the board carries a serial port to the I/O processor (`pip install pyserial`).
Since the PC link (`../Docs/04-pc-link.md`) it carries framed packets at 1.5 Mbaud: the log, the
PC volume served by the gateway (`../tools/atari816-link`, see the root README) and the
requests of these developer tools. The tools go through the gateway when it runs, else they
open the port themselves for the time of the command.

```bash
python3 tools/atari.py log                       # firmware and 65C816 debug log
python3 tools/atari.py send FILE [NAME]          # copy a file to the SD card (/PC/ by default)
python3 tools/atari.py run816 sw/a816/A816.BIN   # send a 65C816 program, restart the 65C816, show its log
python3 tools/atari.py shot816 OUT.png           # screenshot of the native screen
python3 tools/atari.py peek816 ADDR [LEN]        # 65C816 memory
python3 tools/atari.py run GAME.XEX              # send and boot an executable on the 8-bit Atari
python3 tools/atari.py --help                    # all commands
```

## Tests

| What | How |
| --- | --- |
| 65C816 machine in simulation | `sim_a816/run.sh` (self test), `sim_a816/run.sh +prog=NAME.bin` for `bringup1_sim.bin`, `nvtest_sim.bin`, `blitlist_sim.bin`, `sampler_sim.bin`, `sprtest_sim.bin` (`+timeout_ms=3000`), `sprsceneN.bin` (`+ppm2` keeps the last frames for comparing with emu816), `BLITTEST.BIN`; `sim_a816/run_blit.sh` (random blitter test). The testbench compares every pixel of Marga's output with its own model (bitmap, scrolling, pointer, sprites); `+fixlat` gives the SDRAM's own latencies instead of random ones |
| On the board | `make -C sw/a816`, then `tools/atari.py run816 sw/a816/X.BIN`: `A816.BIN` (self test), `BLITTEST.BIN`, `BLITLIST.BIN`, `SAMPLER.BIN`, `SPRTEST.BIN`, `SYSTEST.BIN`, `FSBENCH.BIN` (SD speed), `PCBENCH.BIN` (the same on the PC volume, needs the gateway), `TIMING.BIN` (CPU and Ali speed by access kind and video mode: emu816's memory model is calibrated against it, emu/README.md "Memory timing"); `PLAYDEMO.BIN`, `SPLIT.BIN`, `SPRDEMO.BIN` and `SCROLLDEMO.BIN` are for ears and eyes. The list is at the top of `sw/a816/Makefile` |
| The folder disk (host) | `test/fdisk_host/run_tests.sh` |
| PC link framing (host) | `test/pclink_host/run_tests.py` |

## Pins

From `constraints/tang_nano_20k.cst` (the authority if this table and the file differ).

| Function | FPGA pin | Dir |
|----------|----------|-----|
| System clock (27 MHz) | 4 | in |
| Reset button S1 / button S2 | 88 / 87 | in |
| LEDs | 17-20 | out |
| HDMI TMDS CLK, D0, D1, D2 (+/-) | 33/34, 35/36, 37/38, 39/40 | out |
| SD CLK / MOSI / MISO / CS | 83 / 82 / 84 / 81 | out/out/in/out |
| Keyboard and mouse UART RX (CH9350 or Pico TX) | 53 | in |
| PC link TX / RX (BL616 USB serial) | 69 / 70 | out / in |
| Joystick 1 Up / Down / Left / Right / Fire | 27 / 28 / 25 / 26 / 29 | in |
| Joystick 2 Up / Down / Left / Right / Fire | 42 / 41 / 56 / 54 / 48 | in |

Never wire inputs to pins 69-76 and 79 (driven by the BL616) or 51 (PLL clock input).

## Credits and licences

> **Bitstreams are non-commercial.** The 8-bit Atari core inside is offered by its author for
> non-commercial use only, so this directory and any bitstream built from it may be used and
> shared for **non-commercial purposes only**. Commercial use needs permission from Mark Watson
> (`scrameta@gmail.com`) and from the other copyright holders whose licences do not already
> allow it. **[`LICENSE`](LICENSE) is the authoritative, per-component map.**

| Component | Author | Terms |
|---|---|---|
| **Atari 8-bit core**, [Atari800_MiSTer](https://github.com/MiSTer-devel/Atari800_MiSTer) / atari800core (`rtl/`) | Mark Watson | Custom **non-commercial** notice ([text](LICENSES/Mark-Watson-NonCommercial.txt)) |
| **6502 core**, FPGA 64 `cpu_65xx.vhd` | Peter Wendrich | "All Rights Reserved" header, reaches us via the core above |
| **Cartridge bank switching, freezer, PBI ROM** | Matthias Reichl, Wojciech Mostowski | LGPL v2-or-later |
| **65C816 CPU core** (`src/a816/P65C816.v` and its parts), SNES_FPGA via [snestang](https://github.com/nand2mario/snestang); `P65C816.v` and `AddrGen.v` modified here | srg320, gyurco, nand2mario | **GPL-3.0** |
| **I/O subsystem** (PicoRV32 host, SPI), adapted from [nestang](https://github.com/nand2mario/nestang) | nand2mario | **GPL-3.0** |
| **Firmware base** (`firmware/`), [firmware-picorv32](https://github.com/nand2mario/firmware-picorv32) | nand2mario | No licence file upstream; ships in NESTang under GPL-3.0 and is treated as such here |
| **PicoRV32**, [YosysHQ/picorv32](https://github.com/YosysHQ/picorv32) | Claire Xenia Wolf | ISC |
| **Simple UART** (`src/simpleuart.v`, PicoSoC) | Claire Xenia Wolf | ISC |
| **SD-card SPI driver** (`firmware/spi_sd.c`), [learn-fpga](https://github.com/BrunoLevy/learn-fpga) | Bruno Levy, nand2mario | BSD 3-Clause ([text](LICENSES/BSD-3-Clause-learn-fpga.txt)) |
| **FatFs** (`firmware/fatfs/`) | ChaN | 1-clause BSD |
| **Low-latency SDRAM controller**, [sdram-tang-nano-20k](https://github.com/nand2mario/sdram-tang-nano-20k) | nand2mario | Apache 2.0 |
| **HDMI library**, [hdl-util/hdmi](https://github.com/hdl-util/hdmi) | Sameer Puri | MIT **or** Apache 2.0 |
| **Atari palette** (tables in `gtia_palette.vhdl`, `src/nvc_palette.hex`) | Avery Lee (Altirra) | default palettes of the Altirra emulator, credited |
| **Atari816 hardware and the Tang Nano 20K port**: everything else | Carlos Bravo | **CC BY-NC-SA 4.0 _or_ GPL-3.0-or-later**, your choice ([`LICENSE-PORT`](LICENSE-PORT)) |

`sdram_nestang.v` is nand2mario's controller with a 32-bit masked-write path and half-rate
BL2 burst reads added. `rtl/common/a8core/antic.vhdl` carries a one-line fix to an upstream
ANTIC bug (mode-8 HSCROL) and other files under `rtl/` were changed for the Atari816; as
derived works they stay under Mark Watson's terms.

The user manual of the 8-bit port this hardware grew from lives in that port's own repository.
Full licence texts are in [`LICENSES/`](LICENSES/). Every source file's own header notice is
authoritative for that file; please keep them intact.
