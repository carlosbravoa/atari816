# emu816: Atari816 native-side emulator

emu816 is a fast C model of the Atari816 native machine: a 65C816, FREDDIE II (memory map,
bank 0 window, user/supervisor modes, protection, ABORT), the system block, the I/O
processor mailbox, Marga, the video chip (first called the NVC, with sprites and fine scrolling
from REV $0B), Ali, the blitter, Lau, the sample player, next to POKEY 2 (from REV $0C POKEY 1's
native register bank), and from REV $0C the OPL2 (YM3812): its registers and timers, and its
sound from Nuked OPL3 (`nuked-opl3/`). Use it to develop Horizon on a PC. The reference for FREDDIE II and the system block is `core/src/a816/a816_sys.sv`.
The reference for the mailbox is `a816_mailbox()` in `core/firmware/firmware.c`. The reference for Marga is
`core/src/a816/a816_nvc.sv`. The rest follows `Docs/02-register-spec.md`.

## Build and run

```
make                 # emu816, C11 + libc (+ libm)
make SDL=1           # adds a 1280x720 window, keyboard, mouse and live sound (needs SDL2)
make test            # acceptance tests (see "Tests")
make sst             # downloads the SingleStepTests sample that make test uses (~40 MB)
```

```
emu816 [--sd DIR] [--load FILE@ADDR]... [--max-seconds N] [--trace]
       [--keys LIST] [--mouse LIST] [--shot FILE.ppm] [--shot-at SECONDS] [--stats] [--headless] [--fast]
       [--ideal-timing] [--boot-cart PATH] [--pc-folder DIR] [--pc-time T]
       [--card-kbps R:W] [--pc-kbps R:W] [--net] [--net-root DIR] [--net-delay MS]
       [--no-pc-print] [--classic-print FILE@SECONDS]... PROGRAM.BIN
```

| Option | Meaning |
| --- | --- |
| `--sd DIR` | Host directory served as the SD card through the mailbox |
| `--load FILE@ADDR` | Extra file at a 24-bit hex address (`02:0000`, `$020000` and `0x20000` all work) |
| `--max-seconds N` | Stop after N seconds of emulated time |
| `--trace` | One line per instruction on stderr: cycle, PBR:PC, bytes, disassembly, A X Y S D DB, flags, E/N, U/S. IRQ, NMI and ABORT entries are marked `***` |
| `--shot FILE.ppm` | Write the 1280x720 output frame (scaled, as on screen) as a PPM. It is written at the first VBLANK (trigger 360) at or after the following `--shot-at` seconds, or at exit. Repeatable |
| `--keys LIST` | Key changes `t_ms:usage:down,...` (usage in hex) at emulated milliseconds |
| `--mouse LIST` | Mouse input `t_ms:dx:dy:wheel:buttons,...` at emulated milliseconds: decimal motion in desktop pixels (dy > 0 = down), buttons bit 0 left, 1 right, 2 middle (`0x` allowed). Example: `--mouse 100:5:-3:0:1,200:0:0:0:0` |
| `--console-us N` | Slow console: after each DBG_OUT byte, DBG_STAT bit 7 reads 1 for N emulated microseconds, and bytes written meanwhile are dropped, as on the hardware. The board takes about 90 us per byte while its log is read and can stall for milliseconds. Default 0: never busy |
| `--stats` | At exit, print the emulated time, host time, emulated MHz, the cycles the CPU waited in WAI (the kernel's idle loop: the rest is its load) and counters (and the dropped console bytes with `--console-us`; the cache fills, RAM writes, cache sweeps and stall cycles of the memory model) |
| `--rev N` | SYS_REV to report: 6 (no sound page, no blitter), 7 (sound page), 8 (sound and blitter), 9 (+ blitter command lists, raster events at the beam, NV_FRAME), 10 = $0A (+ Lau, the sample player, the default hardware build of bring-up step 17), 11 = $0B (+ Marga's sprites and fine scrolling, bring-up step 19), 12 = $0C (default: + the OPL2 at $00:DB30-$DB33; POKEY 2 replaced by POKEY 1's native register bank at the same addresses; the four DACs gone). Below 12 $00:DB30-$DB33 belong to Lau's page as before (they read 0); below 11 Marga's registers $D930-$D9FF read 0 and ignore writes; below 10 the sample player reads 0 and ignores writes; below 9 the list registers do, and the raster events come at the fetch trigger; below 8 the blitter registers read 0 and ignore writes; below 7 the sound page ignores writes |
| `--wav FILE.wav` | Write the sound the board's HDMI output carries, without the classic machine's part: Lau's left and right plus the OPL2's output on both (REV $0C), saturated to 16 bits, 48 kHz stereo, from the start of the run. Not in it: POKEY (the native bank and the classic machine's) and GTIA. See "OPL2", the mix |
| `--log-sound` | Print every accepted write to the sound page ($00:DB00-$DB13; from REV $0C $DB00-$DB0F) on stderr |
| `--log-lau` | Print every write to Lau, the sample player ($00:DB20-$DBFF, REV $0A), on stderr as `lau $DBxx = $yy` (Horizon's sample-call test compares it) |
| `--log-lau-us` | The same as `--log-lau`, each line with the emulated time in microseconds: `lau 1234567 $DB89 = $12` (the music tests rebuild Lau's voice state at every tick from it) |
| `--log-opl` | Print every OPL2 data write ($00:DB31, REV $0C) on stderr as `opl $RR = $yy`, RR the register selected at $DB30 (the selects themselves are not printed) |
| `--log-opl-us` | The same as `--log-opl`, each line with the emulated time in microseconds: `opl 1234567 $B0 = $31` (Horizon's OPL2 and MIDI tests compare it) |
| `--headless` | SDL builds open a window by default; this flag suppresses it (accepted and ignored in plain builds) |
| `--fast` | SDL: keep the window but do not throttle to real time (the live sound is then cut to about 100 ms a frame) |
| `--mute` | SDL: no live sound. Without the option the window plays what `--wav` records, through SDL's default output device (none found: a note on stderr, the run goes on silently) |
| `--ideal-timing` | The time model before Horizon 0.19: every CPU cycle ideal (no cache misses, SDRAM write stalls or cache sweeps) and Ali's older per-pixel rates. Programs then run about twice as fast as on the board (see "Memory timing") |
| `--card-date YYYY-MM-DDTHH:MM` | The date STAT reports for every file this run did not create or write, on the card and on the PC volume (Horizon's tests run on fresh copies of the card, whose host dates mean nothing); the files the run writes keep the date SYS_TIME gives them |
| `--pc-folder DIR` | The PC volume of the PC link: paths starting `/PC:` are served from DIR (see "The PC volume" below). Without it the volume is absent: those paths answer $87 |
| `--pc-time YYYY-MM-DDTHH:MM` | The PC's clock at power-on; it counts on with emulated time. STAT `/PC:` reports it, and the PC files the run writes get it as their date. Default: the host's clock. (The PC files the run did not write get `--card-date`, as the card's) |
| `--pc-drop-at SECONDS` | The PC link drops at this emulated time: open PC handles answer $88, new `/PC:` calls $87, the `PC:` entry leaves the root. Streams too (see "The internet"): open streams answer $88, requests put aside answer $88, each connection gets an $E4 event, new URL opens answer $87 |
| `--pc-back-at SECONDS` | The link comes back at this time (after `--pc-drop-at`): a new session; handles from before the drop stay dead ($88) |
| `--card-kbps R:W` | Slow card (see "Slow transfers"): READ and LOAD at R KB/s, WRITE at W KB/s, and 1 ms for every request on the card. 0 = instant. Default: off (every request instant). The board: about `170:100` |
| `--pc-kbps R:W` | Slow PC volume: the same, with 6 ms for every request on the PC. The board: about `100:55` |
| `--net` | The Net service of the PC link (step 2): `tcp://host:port` paths are real TCP connections from the host (see "The internet (PC link step 2)"). Without it they answer $8A |
| `--net-root DIR` | The Fetch service: `http://`, `https://` and `ftp://` URLs are served from files in DIR (`scheme://host[:port]/path` = the file `DIR/host/path`). Without it they answer $8A |
| `--net-delay MS` | The time the PC takes to answer an OPEN or STAT of a URL (the server's answer), in emulated milliseconds. Default 0 (+ 6 ms when `--pc-kbps` is given) |
| `--no-pc-print` | (Horizon 0.23) The gateway cannot make PDFs: STAT `/PC:` answers its services without bit 4 (PRINT): $0D instead of $1D (see "Printing, Run in Atari, the folder disk") |
| `--classic-print FILE@SECONDS` | (Horizon 0.23) At that emulated time the classic Atari prints FILE (ATASCII bytes as P: sends them, e.g. `HELLO` $9B): a print job `/Printouts/YYYY-MM-DD HH.MM.SS Atari.txt`, converted by the firmware's own `core/firmware/prnconv.c` (in records of 40 bytes, a record ending at its EOL), written at once under its `.` name and finished 3 s later (the firmware ends a job after 3 s without data); stderr: `emu816: P: job /Printouts/...`. Repeatable (8 at most) |
| `--boot-cart PATH` | A cartridge (a FAT path on `--sd`) that the I/O processor loaded by itself at power-on (`boot=ash` in /atari.ini): CLASSIC\_STATE ($1E) reports it, from power-on and after a full restart |

Exit codes: 0 when the program executes STP, 3 at the `--max-seconds` limit, 1 on a usage
or file error. Output written to DBG_OUT ($00:DEF0) goes to stdout.

### Boot

Boot follows the I/O processor and the RTL testbench:

1. Every RAM byte is filled with `$EA ^ (address & $FF)`, junk rather than zeros.
2. The program is loaded at $01:0000: at most 65,280 ($FF00) bytes, as the firmware reads. `--load` files have no limit.
3. The reset stub `18 FB 5C 00 00 01` (CLC XCE JML $010000) goes to $00:FF00, and STP to $00:FF10.
4. Every vector $00:FFE0-$FFFF points to $FF10, except RESET, which points to $FF00.
5. The CPU is reset in emulation mode.

## What is modelled

### 65C816 (`cpu65816.c`)

- All 256 opcodes, in native and emulation mode, including decimal ADC/SBC in 8 and 16 bits.
- Emulation-mode direct page and stack wrapping: the "new" instructions (PEA, PEI, PER,
  PHD, PLD, PLB, JSL, RTL, JSR (a,X), [dp]) use the 16-bit stack and direct page, then
  force S back into page 1.
- MVN/MVP move one byte per execution and fetch the opcode again, so a block move takes
  7 cycles per byte and is interruptible.
- WAI, STP, and IRQ/NMI/RESET/COP/BRK/ABORT entry.
- Every bus access is one call to `read(addr, flags)` or `write(addr, val, flags)`. The
  flags mark an opcode fetch (SYNC), an operand fetch, a data access, a vector pull and
  "inside an entry sequence". Internal cycles are counted but make no access.
- Cycle counts follow the data sheet. They were checked against the SingleStepTests/65816
  suite: 508,400 tests (1,000 per opcode and mode) pass, including the exact sequence of
  valid bus cycles. `make test` runs a 200-per-file sample.
- Known difference from the suite: WAI and STP take 3 cycles, as in the data sheet; the
  suite counts 4.
- ABORT follows the RTL. A refused access sets `cpu->abort`, and the refused read returns
  $EA. The instruction runs to its end. Then every register (A X Y S D DBR PBR P E PC) is
  restored to its value at the opcode fetch, and the ABORT vector is taken
  ($00:FFE8 native, $00:FFF8 emulation). ABORT has priority and a pending NMI waits.
  Refusals during an entry sequence are ignored.
- Interrupt sampling follows the RTL:
  - After any entry sequence (IRQ, NMI, ABORT, reset), one instruction always runs before
    the next interrupt is taken.
  - IRQ is polled at the end of an instruction. CLI, SEI, PLP, REP and SEP are polled with
    the I flag they started with, the usual 65xx one-instruction delay.
  - NMI is edge-triggered.
- In emulation mode, IRQ/NMI/ABORT push P with B=0 and BRK pushes B=1, as on a WDC part
  and in the fixed RTL.

### FREDDIE II (`freddie.c`)

This is a line-by-line model of the FREDDIE II part of `a816_sys.sv`:

- **Memory map:** 8 MB of flat RAM. RAM_BANKS reads $7F. Reads above $7F:FFFF return $00
  and writes there are dropped. The I/O page is $00:D000-$DFFF.
- **Bank 0 window:** only bits 6-0 of B0WIN are used, as in `eff_bank[AW-17:0]`.
- **Mode stack:** 8 deep.
  - A vector pull pushes the current mode and enters supervisor mode. Only the first of
    the two pull cycles pushes.
  - Exception: the vector pull of a BRK/COP that already had a refused access (wr_block
    set, outside an entry sequence) does neither. It is checked like any user-mode read,
    as in a816_sys.sv `vpull`.
  - An RTI whose opcode was fetched in supervisor mode, outside an entry sequence, pops
    the stack at the next opcode fetch. That fetch may be the first cycle of an interrupt
    entry.
  - FR_CTRL bit 1 is the top of the stack; FR_CTRL bit 7 is the current mode.
- **NMI hold:** the first cycle of a counted vector pull out of user mode sets `nmi_hold`;
  any FR_CTRL write and reset clear it. While it is set the NMI line is not presented
  (`nmi_n = ~(|nmi_status && !nmi_hold)`). NMI_STATUS still latches, and the CPU sees the
  edge when the hold is released, so the first kernel instructions after an entry from
  user mode, still on the task's S, are never preempted by an NMI.
- An RTI opcode fetch that was refused does not arm the mode-stack pop (`!refuse`).
- **Protection check:** `user_eff` is applied per access. Reads inside an entry sequence
  are not checked; pushes are.
- **WP_VEC** works independently of PROT_EN.
- **ABORT_ADDR / ABORT_CAUSE** record the first refused access of each instruction.
  A read-only refusal sets only the WRITE cause bit.
- **Write block:** after a refusal, writes are blocked until the next opcode fetch, so
  the ABORT sequence's own pushes go through.
- **Protection table:** like block RAM, it is not cleared at reset.
- **CACHE_FLUSH** ($00:D80A) accepts writes and does nothing, because there is no cache.

### System block (`sysblock.c`)

- SYS_ID reads $81, SYS_REV reads $0C (or `--rev`), and SYS_SPEED reads 0.
- **Sound (REV $07):** writes to $00:DB00-$DB13 (POKEY 2, the four DACs) are kept and
  counted only while SV_CTRL FREEZE_REQ is set, as on the hardware; otherwise they are
  counted as ignored. No audio is produced. `--stats` prints both counts. From REV $0C
  $DB00-$DB0F reach POKEY 1's native register bank (still only while frozen) and the DACs
  are gone: writes to $DB10-$DB13 do nothing and are not counted.
- **SV_CTRL** ($00:DC00): bit 2 FREEZE_REQ is stored, bit 0 reads 1. **SV_STATUS**
  ($00:DC01) bit 0 FROZEN follows FREEZE_REQ at once. The rest of the supervisor page
  reads 0 (the classic machine is not modelled).
- **IRQ_STATUS** latches bits 0 VBLANK, 1 LINE, 2 TIMER0, 3 TIMER1 and 4 BLITTER; they are
  W1C. Bit 6 (IOP) is the live level MB_RSP_HEAD != MB_RSP_TAIL: it cannot be cleared by
  W1C and reads back as part of IRQ_STATUS, as in the RTL's `irq_now`. So is bit 5 (AUDIO):
  Lau's end interrupt ORed (REV $0C) with the OPL2's.
- **UPTIME** follows the RTL accumulator exactly: UPTIME = floor(32 x cycles / 459), which
  is microseconds at 14.34375 MHz. Reading $DE18 latches $DE19-$DE1B.
- **Timers:** count at microsecond ticks. A count <= 1 at a tick fires, then reloads or
  stops.
- **Watchdog:** $5A arms it for 2,000,000 us and $A5 restarts it. Expiry sets NMI_STATUS
  bit 1.
- **NMI** is held while NMI_STATUS != 0. The CPU sees the 0 to non-zero edge.
- **DBG_OUT** ($DEF0) prints to stdout. DBG_STAT reads 0 unless `--console-us` is given.
- **KB_ROUTE** ($DE20, bit 0) resets to 1, as in the RTL; the spec says 0. While it is 1
  the keyboard belongs to the classic machine, which is not modelled, so no KEY events are
  produced. JOY_PORT ($DE21) and JOY_TRIG ($DE22) read 0.
- **F12** sets NMI_STATUS bit 0 (SYSTEM_KEY).

### Mailbox (`mailbox.c`)

The I/O processor polls every 512 CPU cycles (about 36 us) and serves one request at a time,
as the firmware does. Software cannot depend on synchronous answers.

- **One poll:** first at most one event (a key, else the mouse; see "Keyboard events"),
  also while a request is in progress. Then, if a request is in progress and its time is up,
  its answer. Else, if the poll sent no event, the next request is taken: without the slow
  transfer options it is answered at once (as before); with them its answer comes later.
- **IOP_READY:** MB_STATUS bit 0 is set on the first poll after both MB_REQ_BASE and
  MB_RSP_BASE are non-zero. MB_REQ_TAIL and MB_RSP_HEAD restart at 0.
- **Reset:** clearing a base closes every file and resets the state.
- **Errors:** an unreadable ring sets IOP_ERROR (bit 1).
- **Cache sweep:** every new MB_RSP_HEAD (an answer or an event) empties the 65C816's cache and
  pauses the CPU for 256 cycles (18 us), as the RTL does before the head becomes visible; so
  does a CACHE_FLUSH write (see "Memory timing").

Responses copy the request, set OP | $80, and put the result in ARG0 and the value in ARG1.
Result codes in ARG0 are:

| Code | Meaning |
| --- | --- |
| 0 | OK |
| 1-19 | FatFs FRESULT (4 NO_FILE, 5 NO_PATH, 6 INVALID_NAME, 7 DENIED, 8 EXIST, 18 TOO_MANY_OPEN_FILES, ...). Host errno values are mapped to the FRESULT FatFs would return |
| $80 | Bad handle |
| $81 | Bad address: >= $80:0000, or anywhere in bank $10, which the firmware cannot reach |
| $82 | Unsupported operation (TIME $30, MOUNT, UNMOUNT and anything unknown, as in the current firmware; CLASSIC_MOUNT of a `/PC:` path while the PC volume is there) |
| $87 | No PC link: a `/PC:` path while the PC volume is absent |
| $88 | PC link lost: READ, WRITE or SEEK on a handle of the PC volume opened before the link dropped |
| $89 | Not the same volume: RENAME between the card and the PC volume |
| $8A-$93 | The internet (PC link step 2, see "The internet"): $8A no such service, $8B bad address, $8C name not found, $8D refused, $8E timeout, $8F HTTP status >= 400 (ARG1 = the status), $90 the connection was closed, $91 TLS failed, $93 other network error |

The open formats match the firmware:

| Op | Format |
| --- | --- |
| OPEN | FLAGS 0 = read, 1 = read+write (file must exist), 2 = create/truncate read+write, 3 = append (write only). At most 4 files; handles 0-3, the lowest free one is used |
| READ / WRITE | Through 1 MB-contiguous chunks, as `mb_xfer` does. A short count means end of file. A handle opened without that direction answers FR_DENIED |
| SEEK | ARG1 = offset. The answer is the new position. A read-only file is clipped to its size, like `f_lseek` |
| STAT | Writes 9 bytes into BUF: `u32 size, u8 attr, u32 time`. attr bit 4 = directory, $20 = archive (files), bit 0 = read-only. time is `fdate << 16 \| ftime`, FAT format, local time. ARG1 = size. STAT of the root answers FR_INVALID_NAME, as FatFs does |
| READDIR | ARG0 = entries to skip, for continuation. Writes packed `{u32 size, u8 attr, u8 namelen, name}` entries, with no terminator, into BUF, which first holds the path. It stops when the next entry would not fit in LEN. ARG1 = entries returned. Entries are sorted by name; "." and ".." are left out |
| RENAME | BUF = `"old\0new"`. Answers FR_EXIST if the target exists |
| LOAD | Whole file to ARG0. ARG1 = bytes loaded |
| SYS_TIME ($1D) | ARG0 = seconds since 2000-01-01 00:00 (local), as Horizon gives it at start and when the clock is set. The firmware counts on from it and FatFs stamps files with it; here the count is emulated time, and a file the 65C816 created or wrote gets that time as its host modification time when it is closed (MKDIR at once), so STAT shows it and runs stay deterministic. Before it is given: 2026-01-01 00:00 (the firmware: its build date) |
| CLASSIC_MOUNT / EJECT / BOOT ($18-$1A) | A stub (there is no classic machine): the firmware's argument checks and result codes; any existing file mounts (kind 0: by its extension); BOOT always works. One line per op on stderr (`emu816: CLASSIC_MOUNT kind 1 slot 1 /GAME.ATR -> 00`). (Horizon 0.23) Kind 4 (CK_BASRUN, "Run in Atari"): a file on the card, $84 when empty or over 96 KB, recorded and answered as kind 2. Kind 5 (CK_FOLDER, ARG0 = the drive 0-3): a folder (made if missing; $48 if it is a file), answered as kind 1; one drive at most (a folder on another drive moves it); a disk image, executable or BASIC program mounted over that drive, and EJECT of it, end it |
| CLASSIC_STATE ($1E) | ARG0 = 5 (the cartridge): ARG1 = its image size in bytes (a .CAR without its 16-byte header; 0 = none), BUF (LEN bytes) its path. The cartridges CLASSIC_MOUNT attached, or the `--boot-cart` one from power-on and after a full restart. $83 for another ARG0 |

Mapping FAT paths to the `--sd` directory:

- A leading `/` or `0:` is optional.
- Each path component is matched case-insensitively, as on FAT.
- `..` components answer FR_INVALID_NAME.
- Any existing path that resolves outside the directory, for example through a symlink,
  answers FR_DENIED.

**The PC volume** (PC link step 1, `--pc-folder DIR`; the firmware gets it from the PC
gateway over the USB serial link):

- A path whose first four characters are `/PC:` (any case), followed by the end or `/`, is on
  the PC volume; `/PC:` alone is its root. The rest is resolved in DIR like a card path
  (each component exact first, then ignoring case), never outside DIR: `..` and anything that
  resolves outside it, a symlink pointing out (existing or dangling) or a new name in such a
  folder, answer FR_DENIED (7). Deleting a folder that is not empty: 7.
- Absent (no `--pc-folder`, or after `--pc-drop-at`): every path op on a `/PC:` path (OPEN,
  STAT, READDIR, MKDIR, DELETE, RENAME, LOAD) answers $87; CLASSIC_MOUNT of one too ($82 while
  present).
- READDIR of `/` (exactly) gives one more entry at the end while the volume is there: `PC:`,
  size 0, attr $10; the skip count counts it. READDIR on the volume: names starting with `.`
  are left out, sorted by name, symlinks pointing out of DIR left out.
- STAT of `/PC:`: size = the services (Horizon 0.23: $1D, see below; 0 before), attr $10, time = the PC's current time (`--pc-time`, counting on with
  emulated time; else the host's clock). STAT of anything else: as on the card (`--card-date`
  for the files the run did not write; the files it wrote: the PC's time at their close).
- The 4 handles are shared by both volumes. RENAME between them: $89. After a drop, READ,
  WRITE and SEEK on a PC handle answer $88 (also after `--pc-back-at`: a new session); CLOSE
  frees it and answers 0. SYS_SYNC closes the PC's files too. A transfer takes no extra time
  here unless `--pc-kbps` is given (see "Slow transfers"; on the board: about 55-100 KB/s, a
  few ms a call).
- **Unfinished files** (the gateway's rule, Docs/04-pc-link.md): a file opened with mode 2 is
  written under a temporary name in the hidden folder `.atari816-partial` at the top of the
  folder; CLOSE (and SYS_SYNC) moves it onto its name in one step. Until then an older file of
  that name stays as it was (STAT shows the old one, or none). When the session ends with the
  file still open (the link drops, the 65C816 is reset or restarted), the temporary file is
  deleted and the older file stays as it was. Modes 1 and 3 write in place.

**Printing, Run in Atari, the folder disk** (PC link step 3, Horizon 0.23; the firmware's
rules, ABI.md "Printing, Run in Atari and the folder disk"):

- **`/PRN:NAME`** (any case for `PRN`): OPEN in any mode creates a print job, a normal handle
  0-3, written as `/Printouts/.YYYY-MM-DD HH.MM.SS NAME.txt` (the firmware's clock, SYS_TIME;
  `/Printouts` made if missing) and moved onto the name without the `.` at CLOSE, and also when
  the 65C816 is reset (a job is never thrown away). NAME: cut to 24 characters, `\ / : * ? " <
  > |` and bytes below 32 made `_`, blanks and dots at its ends removed, empty: `Job`; a name
  taken (finished or open): ` 2` .. ` 99` after NAME. Without a clock given every job has the
  fixed date 2026-01-01 00.00.00 (Horizon's tests put a /SYSTEM/CLOCK on the card when they
  need running times).
- **STAT of exactly `/PRN:`**: size = the jobs finished since power-on (also `--classic-print`
  ones; it survives restarts of the 65C816), attr $10, time = now. STAT of `/PRN:NAME`, and
  READDIR, MKDIR, DELETE, RENAME, LOAD, CLASSIC_MOUNT of a `/PRN:` path: $82.
- **STAT of exactly `/PC:`** (the root): size = the gateway's services: bit 0 files, 2 net,
  3 fetch, 4 print: $1D with `--pc-folder`, $0D with `--no-pc-print` (bit 1, the developer
  service, is never reported). A file written as `/PC:/Printouts/NAME.pdf` with the print
  marker stays as it was written (the gateway would make a PDF of it): tests compare its bytes.
- **The folder disk** (CLASSIC_MOUNT kind 5): there is no classic Atari, so no disk is built.
  STAT of exactly `/D1:` .. `/D4:` (any case) for the folder's drive gives the numbers of the
  firmware's rule, as they were at the mount (a refresh, the same folder and drive again,
  counts again): size = files shown | files left out << 8 | free sectors << 16, attr $10 (never
  FD_SAVING: nothing waits to be saved here), the FAT time of the mount. The rule: in name
  order (the Atari's 8.3 name, upper case) at most 64 files whose names fit Atari DOS (1-8
  letters or digits, the first a letter, optionally a dot and 1-3 letters or digits), each
  needing max(1, ceil(size / 125)) of 707 sectors (one that does not fit is left out and the
  next ones tried); folders inside ignored; every other file "left out". Another drive: $04.
  Not modelled: /atari.ini's `folder=` lines (the folder disk is kept across restarts of the
  65C816 here, but not written to the card), the copy of the Atari's changes into the folder.

**Slow transfers** (`--card-kbps R:W`, `--pc-kbps R:W`; off by default, so every request is
answered in the poll that takes it, as before):

- READ, WRITE and LOAD on that volume take len / rate (KB = 1024 bytes; LOAD: the file's
  size, at the read rate) plus a fixed cost per request: 1 ms on the card, 6 ms on the PC.
  The other file requests on that volume (OPEN, CLOSE, SEEK, STAT, READDIR, MKDIR, DELETE,
  RENAME) take the fixed cost. A request refused at once (a `/PC:` path with no link, a dead
  PC handle) takes no time.
- The request is done, and its answer written, when its time is up. Meanwhile no other request
  is served, but KEY and MOUSE events keep coming.
- A PC request during which the link drops (`--pc-drop-at`) answers $88 (link lost) at its end,
  and is not done (a WRITE writes nothing; its mode 2 file was deleted at the drop).
- The board's measured speeds: card read about 170 KB/s, write about 100 KB/s; PC read about
  100 KB/s, write about 55 KB/s: `--card-kbps 170:100 --pc-kbps 100:55`.

**Keyboard events** follow the firmware's "Keyboard events" block (with the changes of the
firmware of Horizon 0.21: events during a request, every key change in order):

- **Source:** keys come from SDL (scancodes are HID usages) or from `--keys`. The host
  state is 4 held usages plus a modifier bitmap; a fifth key is dropped.
- **When** (the firmware of Horizon 0.21): every poll may produce one event, also while a
  request is in progress (a long card or PC transfer), while IOP_READY is set, KB_ROUTE = 0
  and the response ring has at least 2 free slots (one stays free for the answer of the
  request in progress). A key event comes before a mouse event.
- **Order:** every key change is reported, in the order it happened: a press and its release
  are two events even when both come between two polls. A change that is no news (the release
  of a key never reported, a fifth key) is skipped. Keys held before KB_ROUTE went to 0 are
  reported from the difference between the keys held and those reported: releases first, then
  modifier changes (usages $E0-$E7), then presses. While KB_ROUTE = 1 the keys count as not
  held (held keys are reported released) and nothing is kept.
- **Format:** OP=$E0, TAG=0, byte 8 = usage, byte 12 = current modifier bitmap,
  byte 13 = 1 down / 0 up, every other byte 0.
- **F12** produces a KEY event and the SYSTEM_KEY NMI, as on the hardware.
- **Testing without SDL:** `--keys "t_ms:usage:down,..."` injects key changes at given
  emulated times, with the usage in hex: `--keys 100:04:1,150:04:0` presses and releases
  A.

**Mouse events** follow the firmware's "Mouse event ($E1)" block (0.21: events during a
request, a button change always its own event):

- **Source:** the host side adds motion and wheel into int16 accumulators, one run for each
  button state: motion with unchanged buttons is added to the last run; a button change starts
  a new run (the motion of that same report goes with the new buttons).
- **When:** in a poll with no key event to send, under the same conditions as key events. The
  oldest run is sent (its motion with its buttons) before the next; a run that starts with a
  button change is always sent, even without motion, so a quick click (a press and its release
  between two polls) gives two events. While KB_ROUTE = 1 the motion is dropped and the
  buttons count as reported.
- **Format:** OP=$E1, TAG=0, byte 8 = dx, 9 = dy, 10 = wheel, each clamped to -127..127
  with the remainder kept for the next event, and byte 12 = buttons (bit 0 left, 1 right,
  2 middle). Every other byte is 0.
- **SDL:** relative motion is scaled so that one desktop pixel is one count: window
  pixels / 2, or / 4 in mode 2, with the remainder kept. Buttons and the wheel come from
  the window, and there is no grab.
- **Testing without SDL:** `--mouse "t_ms:dx:dy:wheel:buttons,..."`, next to `--keys`.

### The internet (PC link step 2) (`net.c`)

The internet as the 65C816 sees it through the mailbox (`Docs/04-pc-link.md`, "What the 65C816
sees (step 2)"): a URL is a path, and streams take 4 more handles, **4 to 7**. The gateway's
services are the options: **Net** (`--net`) makes `tcp://` connections real host sockets;
**Fetch** (`--net-root DIR`) serves `http://`, `https://` and `ftp://` URLs from host files.
Tests never need the internet: a loopback server (`127.0.0.1`) is enough for Net.

- **A URL** is a path that starts with letters and `://` (the scheme, any case), passed as it
  is (no leading `/`). Its service: `http`, `https`, `ftp` = Fetch; `tcp`, `tls` = Net; any
  other scheme answers $8B. The link: up while any PC service is given (`--pc-folder`, `--net`,
  `--net-root`), down between `--pc-drop-at` and `--pc-back-at`. Without `--pc-folder` the
  files service is absent as before (`/PC:` answers $87) while the other services work.
- **At once:** the link down: $87; READDIR, LOAD, CLASSIC_MOUNT of a URL: $82; MKDIR, DELETE,
  RENAME (either name a URL): 7; an unknown scheme: $8B; the service not given: $8A; STAT of
  `tcp://` / `tls://`: $82; `tls://`: $91 (TLS is not modelled); a 5th stream: 18.
- **Handles 4-7** (the lowest free), apart from the files' 0-3. CLOSE frees one (also one of
  an ended session: 0); a handle not open, or whose OPEN is not answered yet: $80. SEEK on a
  stream: $82. SYS_SYNC closes every stream (requests put aside answer $88); a reset of the
  mailbox (a base cleared) and SYS_RESTART close them all (sockets closed).
- **Requests put aside:** an OPEN or STAT of a URL, a Fetch READ that waits for its data and a
  Net OPEN waiting for its connection do not hold the I/O processor: the request ring moves on
  (MB_REQ_TAIL advances at once), other requests are served, KEY and MOUSE events keep coming,
  and the answer comes later, matched by its TAG. The answers and $E4 events of the streams
  are sent like KEY and MOUSE events: one per poll, while the response ring has 2 free slots
  (a key or mouse event first). A request whose answer is already due is answered in the poll
  that takes it, as before.

**Fetch** (`--net-root DIR`):

- `scheme://[user[:password]@]host[:port]/path[?query][#fragment]` is the file `DIR/host/path`:
  the scheme, user and port are ignored; the query and fragment are left out; `%XX` is decoded;
  every part is found ignoring case as on the PC volume, never outside DIR (`..` and links
  pointing out: not found). No path = `/`.
- A folder (with or without a final `/`) gives its listing as the body: `name\n` per entry,
  sorted by name (byte order), names starting with `.` left out, folders without a mark. A path
  ending in `/` that is a file: not found.
- **Results:** no folder `DIR/host`: $8C (name not found). Not found: http(s) $8F with ARG1 =
  404; ftp $8D. Otherwise 0.
- **STAT:** writes `u32 size, u8 $21, u32 time` (the PC's clock now, `--pc-time`) into BUF;
  ARG1 = the size. **OPEN** (FLAGS 0; any other mode: 7): ARG1 = the handle. Both answer after
  `--net-delay` ms (+ 6 ms with `--pc-kbps`). A STAT and then an OPEN of the same URL (the same
  bytes) within 15 s: the OPEN answers at once, and the body has been coming since the STAT's
  answer.
- **READ** answers when LEN bytes have come or the body ended (fewer = the end; then 0).
  The body comes from the OPEN's answer at the `--pc-kbps` read rate (else all at once); while
  no READ waits, at most 4 KB more than the program has read (the firmware's buffer) comes.
  So a 64 KB download with `--pc-kbps 100:55` takes about 0.64 s, for progress windows.
  WRITE: 7. A Fetch stream sends no $E4.

**Net** (`--net`): `tcp://host:port` (port 1-65535, `[v6]` allowed, an optional final `/`;
anything else $8B).

- **OPEN** (any FLAGS): the name is looked up at once (blocking `getaddrinfo`, fine for
  loopback and the LAN; failure: $8C), then the connection is made without blocking the
  emulated machine; each address in turn. The answer (ARG1 = the handle) comes when it is
  connected (and `--net-delay` has passed), or fails: refused / unreachable $8D, 15 s of host
  time $8E, else $93. TCP_NODELAY is set.
- **READ** never waits: the bytes that have come, up to LEN (0 = none yet; up to 4 KB are kept
  per stream, more stays in the host's socket). When the other end has closed and every byte
  was read: $90; after a socket error (reset): $93.
- **WRITE** never waits: the bytes are copied into a 4 KB send buffer (the gateway's credit)
  and sent as the socket takes them; ARG1 = the bytes taken (fewer than LEN, perhaps 0, when the
  buffer is full: try again later). After the end: $90 (after an error: $93).
- **$E4 NET** (TAG 0, ARG0 = the handle): when bytes come, the other end closes or an error
  happens, and the program has READ from the handle since the last $E4 (an edge: each READ
  re-arms it; the OPEN's answer arms it too, and gives an event at once if bytes came before
  it). So a program reads until READ answers 0 (or an error), then waits for $E4.
- **Time:** while a connection is open or connecting, emulated time is held to the host's
  clock (each mailbox poll waits on the sockets for as long as emulated time is ahead), so a
  remote program answers within the emulated time it would on the board and `--max-seconds`
  is about host seconds. Otherwise emulated time runs as fast as it can.

**Link drops** (`--pc-drop-at`, `--pc-back-at`): at the drop every stream ends (sockets closed,
bodies dropped): READ and WRITE answer $88, requests put aside answer $88 at once, every
connection that had answered its OPEN gets one $E4 event, CLOSE frees the handle (0), and new
URL requests answer $87 until the link is back. Handles from before the drop stay dead after
`--pc-back-at`.

**Not modelled:** TLS (`tls://` answers $91), HTTP redirects and real HTTP / FTP (Fetch never
connects anywhere), the 40 s limit for requests put aside, the 8-streams-per-channel limit of
the gateway ($92), the gateway's own name lookup (the host's resolver is used).

### Marga (video) — $D900 (`nvc.c`)

This is a model of `core/src/a816/a816_nvc.sv`, which is the definition.

Modes:

- Mode 0 is 640x360x8. Mode 1 is 640x360x4: 320 bytes per line, high nibble = left pixel,
  palette entries 0-15. Mode 2 is 320x180x8. The line buffer holds one palette index per
  picture pixel in every mode (as the RTL does from REV $0B), with the pointer and the
  sprites already merged.
- The output is 1280x720: the picture is shown 2x (mode 2: 4x). With ENABLE clear at
  display time the line is black.
- NV_STRIDE resets to 640. The RTL requires a multiple of 8.
- A line is fetched as 80 bursts of 8 bytes, or 40 in modes 1 and 2.

Timing (the CPU cycle is 2 clk_core; the pixel clock is 71.71875 MHz = 2.5 clk_core, so
5 pixel clocks per CPU cycle):

- The raster is 1572 x 760 pixel clocks, one output picture of 1280x720 for everything.
  An output line is 314.4 CPU cycles and a frame exactly 238,944 CPU cycles (60.03 Hz).
- Positions are counted in pixel clocks, so the fraction is exact. An event is seen at
  the first CPU cycle at or after its pixel clock. The frame phase is 0 at reset.
- Trigger n (n = 0-365) fires at the start of output line 28 + 2n, every 628.8 CPU
  cycles. Output lines 0-27 have no trigger. The first active output line is 30.
- At trigger n:
  - NV_LINE = n. It is not latched, and resets to 360.
  - At n == 360, a VBLANK pulse sets IRQ_STATUS bit 0. At n == NV_LINE_CMP (reset 511 =
    never), a LINE pulse sets bit 1. IN_VBLANK = NV_LINE >= 360.
  - At n == 0, NV_BASE is taken, BASE_PENDING clears, the scroll registers (and
    NV_LINE_CMP, for the split) are taken, and the row address restarts at
    NV_BASE + NV_SCROLLY x NV_STRIDE. With SPLIT, at n == the split line it restarts at
    NV_BASE + NV_SCROLLY2 x NV_STRIDE. Otherwise it advances by NV_STRIDE (mode 2: every
    second trigger), or goes back to NV_BASE when the row number reaches NV_VHEIGHT.
  - From trigger 360 to trigger 0 (vertical blank) a pending NV_SPR_COMMIT is done: the 128
    record bytes as written are copied to the set in use (a COMMIT written in that window is
    done at once).
  - If ENABLE and n < 360, the line (640 or 320 pixels, from NV_SCROLLX on, HWRAP: modulo
    NV_STRIDE bytes) is fetched from RAM into half n&1 of the two-line buffer. The sprites
    and the pointer are merged in at that moment, using their registers, records and images
    as they are then. Writes to the framebuffer, the pointer or sprite images after a line's
    fetch show up a frame later.
  - Sprites follow the register spec exactly (choice in index order within the 640-pixel
    width budget, OVERFLOW, drawing from 15 down to 0, BEHIND, flips, MAG, 4 bpp PAL). The
    choice runs (and sets OVERFLOW) even when no picture is wanted.
- Line n is on screen from trigger n+1 on (output lines 30+2n and 31+2n). It is converted
  to RGB with NV_CTRL as it was then and with the palette of that moment.
  - The conversion is lazy: lines are converted before the next palette write, or when a
    picture is needed.
  - When no picture is wanted (no SDL window, no pending `--shot`), fetch and display are
    skipped altogether, because nothing can observe them.
- The fetcher's SDRAM addresses are 23 bits, so they wrap within 8 MB.

Registers:

- NV_BASE: the low byte ($D901) is ignored. Writing $D902 or $D903 sets BASE_PENDING.
- NV_LATE ($D90B) reads 0, because the emulator is never late; writes are ignored.
- PAL_R and PAL_G read back the last value written; PAL_B reads 0.
- PTR_X is 10 bits (0-639), PTR_Y 9 bits and NV_LINE_CMP 9 bits.
- REV $0B: the scroll registers read back the value written; NV_SPR_COMMIT reads PENDING;
  NV_SPR_STATUS bit 1 (LATE) is always 0, because the emulator is never late; the records
  ($D980-$D9FF) read 0, and NV_SPR_PEEKD returns the byte selected by the last NV_SPR_PEEK
  write (taken at that write).
- All of Marga's registers reset with the machine, the sprite records (both sets) included.

Reset palette:

- It is `core/src/nvc_palette.hex`, the GTIA NTSC palette, copied into `nvc_palette.h`.
  Regenerate that header if the hex file changes.

Pointer:

- PTR_IMG is 8-byte aligned. Each of the 32 rows is 8 bytes, 2 bpp, with the leftmost
  pixel in bits 7-6.
- The top-left corner is at (PTR_X - 2 x PTR_HOT[3:0], PTR_Y - 2 x PTR_HOT[7:4]).
- In mode 2 the pointer pixels are framebuffer pixels (4x).
- PTR_C1-C3 reset to $00, $0F and $08. In 4 bpp mode the low nibble of PTR_Cn is used.

### Ali (blitter) — $DA00 (`blitter.c`)

Ali:

- REV $08 and up (`--rev`). The pixels are written when START is written; then BUSY reads
  1 for the board's measured time (core/sw/a816/timing.s): clk_core cycles per pixel, FILL /
  COPY and COPY_KEY / EXPAND, with the classic machine frozen 2.06 / 2.90 / 2.27 (Marga off),
  3.41 / 4.50 / 3.77 (640x360x8), 2.56 / 3.55 / 2.82 (320x180x8), and with it running
  7.0 / 10.7 / 7.8 in 640x360x8 (the other cases interpolated; a CPU cycle is 2 clk_core),
  plus 8 CPU cycles a blit and, for FILL and EXPAND, 2 a line. A CPU access to RAM while Ali
  is busy delays Ali by the access's time (and the CPU's access waits a little longer; see
  "Memory timing"). IRQ_EN raises BLITTER when BUSY drops. `--ideal-timing` keeps the older
  rates (FILL 2.0, EXPAND 2.2, COPY 2.9 / 3.5 + 0.8 with the video on, 8 + 2 a line).
- The RTL's rules are enforced by counting (and printed on stderr, the first 10 of each):
  START while BUSY is ignored; a write to $DA00-$DA12 while BUSY is illegal; a CPU read
  of an 8-byte line the blitter wrote since the last cache sweep is a stale read. A
  sweep is a CACHE_FLUSH write ($00:D80A) or the one the RTL makes before a new
  MB_RSP_HEAD becomes visible. `--stats` prints the counts.
- Addresses are physical, with no window and no protection.
- BACKWARDS walks lines bottom to top and pixels right to left. The addresses still name
  the first (top-left) byte of each rectangle.
- EXPAND source lines start at BL_SRC + y x BL_SRC_STRIDE, at bit SRC_BIT (7 = leftmost),
  and the bit position carries on into the following bytes.
- A width or height of 0 draws nothing.

Command lists (REV $09):

- LIST reads the record at BL_LIST 30 CPU cycles after the previous blit has finished
  (BL_LIST + 24, BL_COUNT - 1, bytes 0-18 into $DA00-$DA12), then starts it at once or,
  with WAIT_VBL, at the next VBLANK event. Its pixels are written when it starts; it is
  BUSY for the same modelled time as a single blit. One interrupt at the end of the list.
- ABORT stops the list and drops BUSY at once; unlike the hardware, the blit that was
  running has already written all its pixels. DONE / ABORTED / WAITING as in the spec.
- From REV $09 register writes while BUSY are ignored (still counted and reported).

### Raster events (Marga, `nvc.c`, REV $09)

NV_LINE, LINE, VBLANK and NV_FRAME come 2852 pixel clocks (1572 + 1280) after fetch
trigger n: at the horizontal blank before line n is drawn. Below REV $09 they come at the
trigger. Reading $D906 / $D90C latches $D907 / $D90D.

### Lau (sample player) — $DB20 (`audio.c`, REV $0A, `--rev 10`)

A bit-exact model of `a816_snd.sv`: output sample k at CPU cycle floor(k x 11953 / 40)
(48 kHz from the pixel clock), the same position, loop, volume and saturation arithmetic, and the per-voice 8-byte block (a voice plays the bytes of its
block as they were when it read them). Differences: the hardware computes up to four
samples ahead into a FIFO, so its positions and KEYON lead the emulator's by up to 4
samples (83 us); AU_LATE is always 0. Steps run only while a voice plays (or with
`--wav`, or the SDL build's live sound).

### OPL2 (YM3812) — $DB30 (`opl.c`, REV $0C)

The part of `a816_opl.sv` and JTOPL (`jtopl_mmr.v`, `jtopl_timers.v`) that software can see.
Like the hardware's, these registers work whether or not the classic machine is frozen.

- **$DB30** write: the register select; read: the status `{IRQ, T1, T2, 0 0 1 1 0}`, $06
  when idle. **$DB31** write: the data for the selected register, kept in a 256-byte shadow
  ($01-$F5 are the chip's); `--log-opl` / `--log-opl-us` print these writes. $DB31 reads 0.
- **$DB32 / $DB33** (OPL_OUT): the output sample now, signed 16-bit, from the sound core (below).
- **Sound:** Nuked OPL3 1.8 (`nuked-opl3/`, Nuke.YKT, LGPL-2.1-or-later, copied unmodified;
  upstream and commit in `nuked-opl3/README`), a cycle-accurate model of the YMF262 made from
  die shots, run in OPL2 mode (the OPL3's NEW bit is never set, so its second register bank,
  stereo bits and extra waveforms stay off). Every $DB31 write reaches it at its emulated
  cycle; it makes one sample per 72 chip clocks (288 CPU cycles, 49,803 Hz): sample n at
  cycle t0 + 288 n from the chip's reset t0, from the registers written before that cycle;
  before sample 1 the output is 0. Pitches follow the board's clock (F-number x 49,803 /
  2^(20 - block): F-number 579, block 4 is 440.0 Hz). Around the core, as JTOPL does: register
  $01 bit 5 (WSE) masks the waveform bits of $E0-$F5 (the OPL3 has no such bit: the core gets 0
  while it is clear and the registers again when it is set), and the output is JTOPL's sum
  (`jtopl_acc.v`): each operator that reaches the output at full scale (the rhythm
  instruments doubled), except that JTOPL scales the carriers of channels 0 to 3 by 256, 181,
  203 and 203 / 256 (0, -3, -2, -2 dB; rounding down), summed in 17 bits and saturated to 16.
  The timers, status and interrupt above stay this file's own model: the core has none. The
  core runs lazily, up to the cycle a write, an OPL_OUT read or an output sample needs it
  (about 0.7 us of host time per sample once the chip has been touched). Differences from the
  board: the core is an OPL3 in compatibility mode, not JTOPL, so envelope steps, the
  phase and the LFOs' rounding may differ in the low bits; CSM mode ($08 bit 7) is ignored
  by both. A silent operator gives -1 in the negative half of its phase, as on the chips: a
  released note leaves a +-1 ripple.
- **The mix** (`--wav`, the live sound): sample k of the 48 kHz output (CPU cycle
  floor(k x 11953 / 40), Lau's) is Lau's L / R plus the OPL2's latest sample at that cycle on
  both channels, saturated to 16 bits, as `mix_sat` in `tang_top.sv` without its classic
  part. On the board that part (POKEY and GTIA, moved up by 16384) is added too, so with a
  silent classic machine the board's output sits 16384 lower and clips below -16384
  (`Docs/02-register-spec.md`, Lau "Mix"); the WAV has no such offset. Lau's own registers
  ($DB2C-$DB2F) still read Lau alone.
- **Timers:** the chip runs on clk_core / 8 (3.5859 MHz). Timer A steps every 288 chip clocks
  (1,152 CPU cycles, 80.3 us), timer B every 1,152 (4,608 CPU cycles, 321 us), on
  free-running prescalers that start at the chip's reset. A timer starts at its value
  ($02 / $03) on the rising edge of its load bit ($04 bit 0 / 1); the step after 255 sets its
  flag and reloads the value as it is then, so a new value takes effect at the next overflow.
  A stopped timer keeps its count.
- **$04:** bit 7 (IRQ reset) clears both flags and changes nothing else. Otherwise bit 6 /
  bit 5 clear the flag of A / B and mask it, and bits 0 / 1 are the load bits. As in JTOPL
  (unlike the data sheet's wording), a masked timer still sets its flag; the mask only hides
  it from the status and the IRQ, so unmasking without a clear shows it at once.
- **IRQ:** a visible flag of A or B (status bit 7) drives IRQ_STATUS bit 5 (AUDIO), ORed with
  Lau's. An overflow is a scheduled device event, so a WAI wakes at its exact cycle.
- **Reset:** at power-on and whenever the 65C816 is held in reset (SYS_RESTART): every
  register 0, both masks off, the prescalers restart.
- Not modelled: the one-clk_core write and read registers of `a816_opl.sv`, and the flag
  clear lasting until JTOPL's next operator clock (at most 16 CPU cycles). No minimum time
  between writes is enforced (the YM3812 wants 3.3 us after a select and 23 us after data).

### Memory timing (since Horizon 0.19)

The board ran CPU-heavy code about twice as slow as emu816 used to (the BASIC sieve 89 s
there, 45 s here). `core/sw/a816/timing.s` (TIMING.BIN) measured why: loops of one kind of
access each, timed with UPTIME on the board and here, with the classic machine frozen and
Marga off (P4), in 640x360x8 at stride 1024 (P1, the desktop), 320x180x8 (P3), and with the
classic machine running (P2). The CPU core itself takes exactly the emulator's cycles (REG,
DPR, IOR: 1.00); everything else is memory:

- **Every RAM write waits for SDRAM** (write-through, `a816_sys.sv` S_WR): about 3.7 CPU
  cycles extra with Marga off, 5.0 in 640x360x8, 9.3 with the classic machine running; a write
  right after a write a little more (3.8 / 6.2 / 12.4).
- **A read miss fills an 8-byte line** (S_FILL): 5.8 / 6.5 / 11.3 cycles extra. The cache is
  4 KB direct-mapped (512 lines, index = address bits 11-3), so code and data that share
  index bits evict each other; it is modelled line by line.
- **Marga's line fetch and the classic machine** share the port (the classic machine and
  the I/O processor come first; Marga before the CPU): the costs above by mode.
- **Ali** fills at 1.90 clk_core a pixel (2.95 in 640x360x8) and copies at 2.8 (4.2-4.3), and
  a CPU access to RAM while it runs delays it by the access's time.
- **Every mailbox answer or event sweeps the cache** with the CPU paused (18 us), and so does
  a CACHE_FLUSH write.
- **The I/O processor's polling** (found with these loops): the firmware called its mailbox
  routine, which runs from SDRAM, on every turn of its main loop, and the PicoRV32's
  instruction fetches come before the 65C816, Marga and Ali. While Horizon runs (a response
  ring with room) this took 10-20 % of the 65C816's memory time in 640x360x8. The firmware of
  bring-up step 20 checks the mailbox registers first, in block RAM, and calls the routine
  only when there is something to do; the tables below are with it.

emu816 models all of this (`freddie.c` `stall()`, `blitter.c` `blit_cost()`), in sixteenths of
a cycle, deterministically. `--ideal-timing` gives the old model (every cycle ideal, Ali's
older rates). Horizon's picture sessions use it: they were timed for it and check what is
drawn, not how fast.

TIMING.BIN, microseconds (board / emu816 0.18 = ideal, and the ratio / emu816 now, and its
error), REV $0B, bring-up step 20 firmware:

| Loop | Marga off: board | ideal | now | 640x360x8: board | ideal | now | classic running: board | now |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| REG (DEX BNE) | 22,851 | 22,849 (1.00) | +0 % | 22,854 | 1.00 | -0 % | 22,856 | -0 % |
| DPW (STA dp) | 16,585 | 8,286 (2.00) | +1 % | 20,246 | 2.44 | -3 % | 31,242 | -5 % |
| DPW16 | 27,658 | 10,570 (2.62) | -0 % | 36,202 | 3.42 | -0 % | 60,357 | -0 % |
| LRSEQ (long reads) | 18,540 | 16,853 (1.10) | +0 % | 19,137 | 1.14 | -2 % | 20,201 | +0 % |
| LRMISS (every read a fill) | 3,767 | 2,110 (1.79) | +1 % | 3,962 | 1.88 | +1 % | 5,287 | +2 % |
| LWSEQ (long writes) | 24,956 | 16,852 (1.48) | +1 % | 27,002 | 1.60 | +5 % | 36,048 | +6 % |
| STACK (PHA PLA) | 13,700 | 9,427 (1.45) | -0 % | 15,117 | 1.60 | +0 % | 18,748 | +7 % |
| JSR RTS | 23,647 | 15,139 (1.56) | -0 % | 28,026 | 1.85 | -0 % | 39,851 | +0 % |
| MVN 32 KB | 26,277 | 15,997 (1.64) | -0 % | 30,252 | 1.89 | -3 % | 38,441 | +6 % |
| ICMISS (16 KB of code) | 10,201 | 6,861 (1.49) | +1 % | 10,495 | 1.53 | +1 % | 12,974 | +4 % |
| IRQ every 25 us | 28,661 | 26,215 (1.09) | -0 % | 30,081 | 1.15 | -0 % | 35,491 | -2 % |
| COP RTI | 19,989 | 11,212 (1.78) | -1 % | 24,817 | 2.21 | -1 % | 37,046 | +2 % |
| Ali fill 640 x 200 x 4 | 33,997 | 35,826 (0.95) | +0 % | 53,060 | 1.48 | -1 % | 112,234 | +0 % |
| Ali copy 320 x 100 x 4 | 12,574 | 13,015 (0.97) | -2 % | 19,209 | 1.16 | -2 % | 43,460 | +0 % |
| Ali 256 keyed 16 x 16 | 7,190 | 8,186 (0.88) | +2 % | 10,756 | 1.08 | +0 % | 23,455 | +1 % |
| SIEVE (assembly) | 289,628 | 243,527 (1.19) | +0 % | 304,079 | 1.25 | +2 % | 370,391 | -0 % |

320x180x8 lies between (all within 2 %). The remaining spread (up to 7 % with the classic
machine running, 5-8 % for some loops whose period beats against the SDRAM's) is the phase of
a loop against the memory's own cadence, which the model averages. BRINGUP1.BIN (classic
machine running, Marga off): LOOP $5947 board / $5948 here, READ $860F / $8676, MVN $75D3 /
$72FE. Under Horizon (the desktop, a program in the Terminal, 0.19 card, step 20 firmware;
TBENCH, the same loops as a Horizon program, ms): REG 250 / 240, DPW 210 / 210, DPW16 376 / 367,
LRMISS 90 / 89, LWSEQ 350 / 330, JSR 287 / 310, WRFILL 98 / 100, SIEVE 790 / 807. The BASIC
sieve (SIEVE.BAS, `basic -t` in the Terminal): see Horizon's README, "Version 0.19".

Not measured: the mailbox's round trip (the PC link that reads the board's log keeps the
I/O processor busy meanwhile: 500 us there against 72 here); the I/O processor still polls
every 512 CPU cycles here.

### Not modelled

- **Audio:** the sound page (POKEY's native bank) is write only and makes no sound, nor does
  the classic machine's POKEY and GTIA. Lau and the OPL2 sound (`--wav`, live in SDL builds;
  see "OPL2").
- **Classic side:** the supervisor ($00:DC00) and the chipset window ($00:D000-$D7FF) read
  0, and the classic map ($00:D810-) is not implemented.
- **Inputs:** joysticks read 0, and turbo mode is not modelled.
- **4 bpp mode in the blitter:** the spec leaves this open, and the blitter is 8 bpp only.

## Tests

`make test` runs `tests/run_tests.sh`. Every check passes. `EMUFLAGS="--rev 11" ./tests/run_tests.sh` (or 10, 9, 8, 7) runs them on an older board; checks of hardware it lacks are skipped:

| Test | Checks |
| --- | --- |
| A816.BIN | The self test (FREDDIE II, timers, preemption, watchdog, mailbox), run with `--sd` pointing at a copy of itself. Uses `core/sw/a816/A816.BIN` when it exists |
| BRINGUP1.BIN | RAM test, LOOP ($5948, the board $5947), READ and MVN (within 3 % of the board's values) |
| tests/asm/mbdemo | Mailbox: open/read/close, LOAD, READDIR (and with skip), create/write/STAT/DELETE, error codes $80/$81/$82/6/5. Waits with WAI on the IOP interrupt |
| tests/asm/pctest | The PC volume, three runs: with `--pc-folder` (the `PC:` entry at the end of the root and the skip count, STAT `/PC:` = `--pc-time` and (Horizon 0.23) the services $1D, case-insensitive names, a file written, read back and seeked, MKDIR, RENAME inside the volume, $89 across, `..` and a symlink out denied, $87 / $82 for CLASSIC_MOUNT), without it ($87 everywhere, the root unchanged), and with `--pc-drop-at` / `--pc-back-at` ($88 on old handles, CLOSE frees them, the entry gone and back). Outputs `tests/expected/pctest*.txt`; nothing may be written outside the folder |
| tests/asm/cpuirq | COP and BRK frames, an MVN interrupted 88 times by a 50 us timer, WAI with I clear, the NMI edge rule |
| tests/asm/nvcdemo | Palette writes, every blitter operation, the pointer, 3 VBLANKs = 49,975 us (60.03 Hz). Picture checked by md5 |
| tests/asm/nvcmode1/2 | 4 bpp and 320x180 modes, the LINE interrupt, BASE_PENDING. Picture checked by md5 |
| NVTEST.BIN | `core/sw/a816/nvtest.s`, the hardware test of Marga, with shots at 1.5 s (mode 0 with the pointer), 24 s (mode 1) and 29 s (mode 2). Pictures are checked by md5; the PNGs are in `tests/pictures/` |
| tests/asm/copabort, eirq | The two fixed RTL issues (below) |
| tests/asm/nmihold | A user task with S at $00:9000 takes TIMER0; the watchdog NMI fires 3 us later. The NMI must stay latched but untaken until the handler writes FR_CTRL, and the canary at the task's S must be intact |
| A816.BIN, slow console | The self test again with `--console-us 90`: same output |
| tests/asm/mousetest | MOUSE events from a `--mouse` script: clamping with the remainder carried, a key event taking priority, motion discarded while KB_ROUTE = 1, a quick click (motion, press and release in one poll: three events) and a key tap in one poll (two events) |
| tests/asm/kbtest | `core/sw/a816/kbtest.s`, unchanged, run with a `--keys` script: modifiers, the 4-key limit, F12 (KEY event + NMI), a key held before KB_ROUTE = 0, releases in the order they happened |
| tests/asm/slowtest | `--card-kbps 64:32 --pc-kbps 100:8 --pc-drop-at 3`: each answer after its time (a 32 KB card read 0.5 s, PC requests 6 ms), KEY and MOUSE events (a quick click, a tap) printed while a request is in progress, a mode 2 PC file not there before CLOSE, a 32 KB PC write cut by the drop: $88, no file left, the older file as it was |
| tests/asm/nettest1-3 | The internet (PC link step 2), from `nettest.s` built three ways. 1: Fetch (`--net-root`, `--pc-kbps 16:16`): STAT then OPEN of the same URL (the OPEN at once), READ to the end, WRITE 7, SEEK $82, a closed handle $80, 404 in ARG1 with $8F, ftp $8D, no host $8C, mode 2 7, a folder's listing (case, query, dot files), MKDIR / RENAME 7, READDIR / LOAD $82, no Net $8A, an unknown scheme $8B, `/PC:` $87, an 8 KB READ put aside (0.5 s) while a card STAT is answered, the 5th stream 18. 2: Net (`--net`, `tests/netserver.py`: an echo server on 127.0.0.1 at a free port): OPEN, WRITE, $E4, READ, STAT / SEEK $82, a refused port $8D, `tls://` $91, no Fetch $8A, no port $8B, the server closing: $90. 3: `--pc-drop-at 1.5` with a connection and a slow Fetch READ open: $E4 at the drop, $88 for the READ put aside and on the handles, CLOSE 0, $87 after. Outputs `tests/expected/nettestN.txt`; 2 and 3 are skipped without python3 |
| BLITTEST.BIN | `core/sw/a816/blittest.s`: every blitter op against a 65C816 reference (REV $08 and up) |
| BLITLIST.BIN | `core/sw/a816/blitlist.s`: command lists against single blits, ABORT, WAIT_VBL, raster events, 60 frames = 999,504 us (REV $09 and up) |
| SAMPLER.BIN | `core/sw/a816/sampler.s`: Lau's rate, end interrupt, loop, mix values, AU_LATE (REV $0A and up) |
| SPRTEST.BIN | `core/sw/a816/sprtest.s`: Marga's REV $0B registers, NV_SPR_PEEK, COMMIT latching, the line limit (OVERFLOW), the load test (REV $0B and up) |
| tests/sprsceneN.bin | `core/sw/a816/sprscene.s` with SEED 1-10: a random scene each (9 and 10 crowded, so the line limit drops sprites) (all modes, scrolling, wrap, split, pointer, 16 sprites with every option). The pictures must be identical to the frames the RTL simulation gave (`expected/sprsceneN.ppm.md5`), REV $0B and up |
| OPLTEST.BIN | `core/sw/a816/opltest.s`, the OPL2 hardware self test (REV $0C and up): STAT ($06), TIMER (the AdLib detection sequence, status $C6, IRQ_STATUS bit 5) and TONE (a 440 Hz note: OPL_OUT reads both positive and negative samples) must pass (`OPL2 PASS`). Below REV $0C it must print `STAT FAIL 00` |
| tests/asm/opltone | The OPL2's sound (REV $0C and up): a 440 Hz sine on channel 0 (F-number 579, block 4) keyed on for 1 s and released, recorded with `--wav` twice; `tests/oplwav.py` checks both sides equal, 440 +-0.5 Hz, the peak (one operator at total level 0: 4,000-4,100), the note's length (1.0-1.1 s above 200) and the last 0.5 s within +-2, and the two files must be the same bytes. Below REV $0C the recording must be silent |
| tests/asm/opltimer | The OPL2's timers (REV $0C and up): the idle status, $DB31-$DB33 reading 0, timer A and B periods at value $F0 (1,285 us and 5,140 us, between two overflows), a masked flag that still sets and shows when unmasked, IRQ_STATUS bit 5 waking WAI, a new value taking effect after the running count, a stopped timer; with `--log-sound` its two frozen writes give only `sound $DB00 = $12` ($DB10 was a DAC). Output `tests/expected/opltimer.txt` |
| SingleStepTests | 102,000 tests, with `tests/fetch_sst.py` / `make sst` to download them |

LOOP prints `00005948` (`00005943` with `--ideal-timing`); the board printed `00005947`. The
emulator's cycle count for that window is the RTL's own: both have 327,771 CPU cycles
between the two UPTIME latches, compared instruction by instruction against a Verilator
trace; the rest are the SDRAM write stalls inside the measured window (stores to t0, the JSR
and PHX pushes), which the memory model now adds.

## RTL issues found (now fixed in the RTL, and in emu816)

1. **A refused BRK/COP push broke protection.** A user task with S in kernel memory
   executed COP. The first push was refused, but COP's vector pull still pushed the mode
   stack and entered supervisor mode. The ABORT entry then wrote PBR, PC and P (all chosen
   by the task) into kernel memory, and the handler saw USER_ARM = 0.
   - Fixed in a816_sys.sv: `vpull = ~cpu_vpb && !(wr_block && !cpu_int_seq)`. emu816 does
     the same.
   - `tests/asm/copabort.s` now prints `FR_CTRL 07 CAUSE 03 KERNEL $8FFD-$9000 55555555`.
2. **Emulation-mode IRQ/NMI/ABORT pushed B=1.** Fixed in P65C816.v: the pushed bit 4 is now
   `EF ? ~GotInterrupt : P[4]`. emu816 now always pushes B=0 for hardware interrupts, as a
   WDC part does. `tests/asm/eirq.s` prints P=$20.
3. **Bank $10 is unreachable for the I/O processor.** The firmware's `mb_ptr` refuses it, so
   transfers there answer $81. This is mirrored. Also, for addresses below $40:0000 `mb_ptr`
   XORs bit 20; it is worth checking that this matches the CPU's own SDRAM mapping for
   banks $11-$3F.
