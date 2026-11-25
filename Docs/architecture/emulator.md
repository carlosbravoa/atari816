# The emulator, emu816

emu816 (`emu/`) is a C model of the native machine: the 65C816, FREDDIE II, the system
block, the mailbox and the I/O processor's file service, Marga, Ali, Lau and the OPL2. It
boots the same `HORIZON.SYS` and the same card folder as the board, so Horizon, the SDK's
programs and the ports are developed and tested on a PC. It runs headless (the tests) or in
an SDL window with keyboard, mouse and sound (`make SDL=1`).

Its full description, every option and every test: [emu/README.md](../../emu/README.md).
How a developer drives it: `sdk/tools/run816.py` ([sdk/docs/tools.md](../../sdk/docs/tools.md),
[sdk/docs/testing.md](../../sdk/docs/testing.md)).

## What its models follow

| Part | Modelled after | How close |
| --- | --- | --- |
| 65C816 | the data sheet; checked against the SingleStepTests/65816 suite | 508,400 tests pass, bus cycle by bus cycle; `make test` runs a 200-per-file sample when it has been downloaded (`make sst`) |
| FREDDIE II, the system block | a line-by-line model of `core/src/a816/a816_sys.sv` | ABORT, the mode stack, the NMI hold and the bank 0 window as the RTL does them |
| Mailbox | the firmware's `a816_mailbox()` | the same operations, result codes and event order; the I/O processor polls every 512 CPU cycles |
| Marga | `core/src/a816/a816_nvc.sv` | the raster timing to the pixel clock; ten random sprite scenes must equal the RTL simulation's frames pixel for pixel |
| Ali | the register spec and the RTL's costs | every operation, command lists, the colour remap; busy times from board measurements |
| Lau | `a816_snd.sv`, bit for bit | the same arithmetic; the hardware's 4-sample lead (83 us) is not modelled |
| OPL2 | registers and timers after JTOPL; the sound from Nuked OPL3 1.8 in OPL2 mode | the low bits of envelopes and LFOs may differ from JTOPL's |

## The board's timing

Until Horizon 0.19 the emulator counted ideal CPU cycles, and the board ran CPU-heavy code
about twice as slowly (the BASIC sieve took 89 s on the board and 45 s in the emulator).
Since then it models what the board's memory costs, from measurements made on the board:

- **CPU stalls.** `core/sw/a816/timing.s` (TIMING.BIN) times loops of one kind of access
  each (register work, direct-page writes, long reads and writes, cache misses, the stack,
  calls, MVN, interrupts, COP, blitter fills and copies), with the video off, in the
  desktop's mode, in 320 x 180 and with the classic machine running. emu816 charges every
  RAM write its SDRAM wait, every read miss its line fill (the 4 KB cache is modelled line
  by line), Marga's and the classic machine's share of the memory port, and the cache sweep
  of each mailbox answer. On these loops the emulator is within about 7 % of the board, most
  of them within 2 % ([emu/README.md](../../emu/README.md), "Memory timing", has the table).
- **Ali's speed.** The busy time of each operation per pixel, by video mode and with the
  classic machine frozen or running, from the same measurements; a fill is charged by the
  32-bit words it writes, as the RTL writes them.
- **The SD card** (`--card-board`, 2026-11-23). On the board an OPEN or a STAT costs 9 to 16
  ms and a READ 1 to 2 ms before its bytes; the instant card of older emulators made file
  calls look 5 to 15 times cheaper. The model charges each request what the firmware's FatFs
  reads: a fixed part, the folder levels and folder sectors scanned, the sectors read. It
  was fitted to the X-COM port's I/O benchmark run on the board and in the emulator on the
  same folders: every line within 6 %. `--card-board-old` has the costs of the firmware
  before Horizon 0.30 (the card clocked at 1.34 MHz instead of 10.7 MHz). `run816.py` turns
  the board's card on from the program's start; `--fast-card` turns it off.
- **Test aids.** `--cpu-slow PCT` and `--kernel-slow PCT` make every instruction (or every
  kernel instruction) cost more or fewer cycles, so a test can show that it does not depend
  on the exact speed. `--ideal-timing` gives the old model back.

What is not measured: the card's write rate and its folder operations are estimated; the
mailbox's round trip on the board was not measured.

## Built for tests

- **Deterministic.** The same card and the same input give the same run: the timer, the
  microsecond clock and the card's answers are emulated time. `--ram-random SEED` fills RAM
  with other junk, for programs that read memory they never wrote.
- **Scripted input.** `--keys` and `--mouse` lists at emulated milliseconds, plus waits:
  until the program prints a line, until the screen has been still for N frames, until a
  frame changes, until a Lau voice starts. `sdk/tools/inputscript.py` writes these lists
  from a readable script.
- **Observation.** Screenshots at times or at console lines (`--shot-on`), RAM dumps at a
  console line, writes into a memory range logged with the instruction that made them
  (`--watch`), every sound chip write logged with its time, Lau and the OPL2 recorded to a
  WAV file, a cycle profile by instruction address (`--prof`, read by
  `sdk/tools/prof816.py`).
- **Rule checks.** Every broken blitter rule (a register written while busy, a read of
  blitter output without a cache flush) is counted and reported; `run816.py` fails the run.
  `--log-bankwrap` (used by the compiler's tests) reports an indexed access that carries
  into the next bank.
- **The PC link.** A shared folder (`--pc-folder`), link drops, the internet (`--net` for
  real TCP connections, `--net-root` serving URLs from files), printing.

## What it does not model

- the classic Atari (no 6502, ANTIC, GTIA or classic POKEY; the classic syscalls answer as
  the firmware does, without a machine behind them);
- POKEY's sound (its writes are logged, not heard) and the classic machine's sound;
- the joysticks (they read 0);
- TLS, HTTP redirects and real HTTP or FTP (URLs are served from files);
- a few of the board's small timing details, listed in [emu/README.md](../../emu/README.md),
  "Not modelled".

A program that works in the emulator can still meet what only the board shows: POKEY's
sound, the joysticks, the keyboard adapter's firmware, the HDMI faults of
[core/KNOWN_ISSUES.md](../../core/KNOWN_ISSUES.md).
