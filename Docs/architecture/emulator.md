# Emulator

emu816 (`emu/`) is a C model of the native machine: the 65C816, FREDDIE II, the system
block, the mailbox and the I/O processor's file service, Marga, Ali, Lau and the OPL2. It
boots the same `HORIZON.SYS` and the same card folder as the board, so Horizon, the SDK's
programs and the ports are developed and tested on a PC. It runs headless (for tests) or in
an SDL window with keyboard, mouse and sound (`make SDL=1`).

Full description, every option and every test: [emu/README.md](../../emu/README.md).
Driving it from scripts: `sdk/tools/run816.py` ([sdk/docs/tools.md](../../sdk/docs/tools.md),
[sdk/docs/testing.md](../../sdk/docs/testing.md)).

## Models

- 65C816: modelled after the data sheet and checked against the SingleStepTests/65816
  suite. 508,400 tests pass, bus cycle by bus cycle. `make test` runs a sample of 200 per
  file when the suite has been downloaded (`make sst`).
- FREDDIE II and the system block: a line-by-line model of `core/src/a816/a816_sys.sv`.
  ABORT, the mode stack, the NMI hold and the bank 0 window behave as in the RTL.
- Mailbox: modelled after the firmware's `a816_mailbox()`, with the same operations,
  result codes and event order. The modelled I/O processor polls every 512 CPU cycles.
- Marga: modelled after `core/src/a816/a816_nvc.sv`, with the raster timing to the pixel
  clock. Ten random sprite scenes are compared with the RTL simulation's frames and must
  match pixel for pixel.
- Ali: modelled after the register specification and the RTL's costs. Every operation,
  command lists, the colour remap, and busy times from board measurements.
- Lau: `a816_snd.sv`, bit for bit, with the same arithmetic. The hardware's lead of 4
  samples (83 us) is not modelled.
- OPL2: registers and timers after JTOPL, the sound from Nuked OPL3 1.8 in OPL2 mode. The
  low bits of envelopes and LFOs may differ from JTOPL's.

## Board timing

With ideal cycle counts, CPU-heavy code runs about twice as fast as on the board (the BASIC
sieve took 89 s on the board and 45 s in the emulator with ideal timing). emu816 models what
the board's memory costs, from measurements made on the board:

- CPU stalls: `core/sw/a816/timing.s` (TIMING.BIN) times loops of one kind of access each
  (register work, direct-page writes, long reads and writes, cache misses, the stack,
  calls, MVN, interrupts, COP, blitter fills and copies), with the video off, in the
  desktop's mode, in 320 x 180 and with the classic machine running. emu816 charges every
  RAM write its SDRAM wait, every read miss its line fill (the 4 KB cache is modelled line
  by line), Marga's and the classic machine's share of the memory port, and the cache sweep
  of each mailbox response. On these loops the emulator is within 7 % of the board, most of
  them within 2 % (the table is in [emu/README.md](../../emu/README.md), "Memory timing").
- Ali's speed: the busy time of each operation per pixel, by video mode and with the
  classic machine frozen or running, from the same measurements. A fill is charged by the
  32-bit words it writes, as the RTL writes them.
- SD card (`--card-board`): on the board an OPEN or a STAT costs 9 to 16 ms and a READ 1 to
  2 ms before its bytes. An instant card makes file calls 5 to 15 times cheaper than on the
  board. The model charges each request what the firmware's FatFs reads: a fixed part, the
  folder levels and folder sectors scanned, the sectors read. It was fitted to the X-COM
  port's I/O benchmark, run on the board and in the emulator on the same folders: every
  line is within 6 %. `--card-board-old` has the costs of the firmware before Horizon 0.30
  (the card clocked at 1.34 MHz instead of 10.7 MHz). `run816.py` enables the board's card
  from the program's start. `--fast-card` disables it.
- Speed variation: `--cpu-slow PCT` and `--kernel-slow PCT` make every instruction (or
  every kernel instruction) cost more or fewer cycles, so a test can show that it does not
  depend on the exact speed. `--ideal-timing` selects ideal cycle counts.

Not measured: the card's write rate and its folder operations are estimated. The mailbox's
round trip on the board was not measured.

## Test features

- Determinism: the same card and the same input give the same run. The timer, the
  microsecond clock and the card's responses run on emulated time. `--ram-random SEED`
  fills RAM with different values, for programs that read memory they never wrote.
- Scripted input: `--keys` and `--mouse` lists at emulated milliseconds, plus wait conditions: until
  the program prints a line, until the screen has been still for N frames, until a frame
  changes, until a Lau voice starts. `sdk/tools/inputscript.py` generates these lists from
  a readable script.
- Observation: screenshots at times or at console lines (`--shot-on`), RAM dumps at a
  console line, writes into a memory range logged with the instruction that made them
  (`--watch`), every sound chip write logged with its time, Lau and the OPL2 recorded to a
  WAV file, a cycle profile by instruction address (`--prof`, read by
  `sdk/tools/prof816.py`).
- Rule checks: every broken blitter rule (a register written while busy, a read of blitter
  output without a cache flush) is counted and reported, and `run816.py` fails the run.
  `--log-bankwrap` (used by the compiler's tests) reports an indexed access that carries
  into the next bank.
- PC link: a shared folder (`--pc-folder`), link drops, the internet (`--net` for real TCP
  connections, `--net-root` serving URLs from files), printing.

## Not modelled

- the classic Atari (no 6502, ANTIC, GTIA or classic POKEY; the classic syscalls return
  what the firmware returns, without a machine behind them);
- POKEY's sound (its writes are logged, not played) and the classic machine's sound;
- the joysticks (they read 0);
- TLS, HTTP redirects and real HTTP or FTP (URLs are served from files);
- a few of the board's small timing details, listed in [emu/README.md](../../emu/README.md),
  "Not modelled".

Only the board exercises POKEY's sound, the joysticks, the keyboard adapter's firmware and
the HDMI faults of [core/KNOWN_ISSUES.md](../../core/KNOWN_ISSUES.md).
