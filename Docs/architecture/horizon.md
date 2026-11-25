# Horizon

Horizon is the software of the native machine: a preemptive, memory-protected kernel for
the 65C816 in native mode, a window system, a controls library and the programs on the
card. All of it is 65816 assembly built with ca65 and ld65 (`horizon/`: about 23,900 lines
in `kernel/*.s` and 124,000 in `user/*.s`). The current version is 0.31.

The interface for programs is [horizon/ABI.md](../../horizon/ABI.md). Building, testing,
the card's layout and the version history are in [horizon/README.md](../../horizon/README.md).

## Boot

The I/O processor loads `/SYSTEM/HORIZON.SYS` to bank $01 and starts the 65C816. The
kernel sets up the mailbox rings, the bank table, the scheduler tick and the console,
freezes the classic machine and starts `/SYSTEM/INIT.PRG`. INIT runs the Desktop
(`/SYSTEM/DESK.PRG`) and restarts it whenever it ends. With `/SYSTEM/NODESK` on the card,
or a key held at start, it runs the text shell (`/SYSTEM/SH.PRG`) instead.

## Tasks and protection

- Tasks: preemptive, by priority, round robin within a priority, on a 10 ms timer tick.
  16 task slots and 62 task ids. Each task has its own kernel stack. The kernel itself is
  never preempted and acts on a reschedule when it returns to user mode.
- Memory: the unit is a 64 KB bank. A program gets a code bank (its code, data, bss and,
  for C programs, the heap), its private 32 KB bank 0 window (direct page and stack) and
  the banks it requests (`bank_alloc`). FREDDIE II's table mirrors the allocator, so a task
  can access only its own banks. Everything is freed when the task ends.
- Faults: an access FREDDIE II blocks, a BRK, a switch to emulation mode, a stack the
  entry frame cannot be pushed through, or interrupts kept off for 2 s (the watchdog) kill
  the task with a line `[kill] task N NAME cause CC addr AAAAAA pc PPPPPP`. The rest of the
  system continues. A watchdog that fires inside the kernel is a panic.
- Message ports: 16 ports for messages between tasks (`port_create`, `send`, `recv`).
- Limits: four open files for the whole system (the I/O processor's), paths of 127
  characters, an argument string of 127 characters ([horizon/README.md](../../horizon/README.md),
  "Current limits").

## System calls

A system call is `COP #n`. The number is the instruction's signature byte, the arguments
are in A, X and Y, a pointer is X = offset and Y = bank, and the carry is clear on success
(on failure it is set and A holds the error code). The kernel checks that every range a
program passes is readable (and writable, where the kernel writes) by that program and
does not cross a bank boundary. Release 0.31 has 115 calls, in these groups:

- Tasks, time, memory, console, keyboard, ports, system: `exit`, `spawn`, `sleep`,
  `uptime_us`, `bank_alloc`, `puts`, `input_read`, `joystick`, `sys_info`. Reference:
  [system.md](../../sdk/docs/reference/system.md).
- Files and folders: `open`, `read`, `seek`, `readdir`, `rename`. URLs are file names too.
  Reference: [files.md](../../sdk/docs/reference/files.md),
  [internet.md](../../sdk/docs/reference/internet.md).
- Window system: `win_open`, `win_event`, `win_menu`, `clip_put`, `ws_palette`. Reference:
  [windows.md](../../sdk/docs/reference/windows.md).
- Drawing: `win_draw` (fills, blits, text, lines, copies). Reference:
  [drawing.md](../../sdk/docs/reference/drawing.md).
- Games: `fs_enter`, `fs_scroll`, `spr_set`, `draw_list`, `sheet_draw`, `fill_runs`,
  `vsync`. Reference: [games.md](../../sdk/docs/reference/games.md).
- Sound: `sound_write` (POKEY), `sample_play` (Lau), `opl_write` (OPL2). Reference:
  [sound.md](../../sdk/docs/reference/sound.md).
- Classic machine: `classic_mount`, `classic_boot`, `classic_show`. Reference:
  [classic.md](../../sdk/docs/reference/classic.md).

`horizon.inc` defines them for assembly. The C SDK generates one C function for each from
the same sources (`hzsys.h`, [sdk/docs/c/syscalls.md](../../sdk/docs/c/syscalls.md)), and
its build checks that the two agree.

## Programs

Programs are relocatable o65 files linked by ld65 at $0100. The loader puts the code and
data at $0100 of a fresh code bank and applies the relocations (16-bit addresses, bank
bytes and 24-bit addresses). Bytes after the o65 part of the file are allowed and never
loaded. The C SDK's large code model keeps its other code banks there and loads them
itself. Start conditions, the argument string and exit codes: ABI.md, "Program format" and
"Task start conditions".

## Files and devices

The kernel passes file calls to the I/O processor through the mailbox and blocks the
calling task. Other tasks run meanwhile. Paths are made absolute against the task's current
folder. Besides the card there are:

- `/PC:`, the folder shared by the PC link's gateway;
- URLs: `http://`, `https://` and `ftp://` open as read-only files, `tcp://host:port` and
  `tls://host:port` as connections, through the gateway;
- `/PRN:NAME`, a print job, kept as a text file in `/Printouts` (and sent to the PC as a
  PDF when the gateway runs).

## Window system and desktop

- Screen: 640 x 360 at 8 bpp, in six banks. The palette has 16 UI colours, a 6 x 6 x 6
  cube and 24 greys. Programs can allocate entries of their own (`pal_alloc`).
- Windows: every window has its own 8 bpp bitmap, so programs never redraw on exposure. A
  kernel thread, the compositor, repaints damaged rectangles one tick after the damage,
  each part of the screen once, with one blitter copy per segment. A window that nothing
  covers draws directly onto the screen. Without the blitter (REV $07) the CPU does the
  same work, 5 to 15 times slower.
- Events: keys, buttons, motion, the wheel, menus, a 10 ms timer, drops, the vertical
  blank, in a queue of 32 per window (`win_event`).
- Menus: drawn and run by the kernel. A program gives a menu bar in a table and receives
  the chosen item as an event.
- Full screen (`fs_enter`): a program shows its own framebuffer in any of Marga's three
  modes, with its own palette, scrolling, a raster table, sprites and draw lists run by Ali
  in the vertical blank. Alt+Tab, Alt+Esc and F12 always return to the desktop.
- Terminals: a window with a terminal (`ws_term`) runs a console program, either the shell
  in the Terminal or any program whose app requests a console.
- Controls library (`ui.lib`, `user/ui*.s`): buttons, fields, lists, scroll bars, menus,
  the file dialog, alerts and small dialogs, in one house style. Horizon's own programs use
  it. C programs use it through `hui.h`.

## Programs on the card

- `/SYSTEM`: the kernel, INIT, the Desktop, the shell, About, the print sender, the screen
  saver, the music engine.
- `/BIN`: Files, Terminal, Edit, Write, Sheet, Paint, BASIC, Calculator, Solitaire,
  Quabricks, FreeCell, Settings, the Downloader, the BBS terminal, Printer, the Music
  Player, the Installer, and the shell's tools (`files`, `cat`, `dir`, `mem`).
- `/SYSTEM/TESTS`: the test and demo programs used by the kernel's tests (SELFTEST,
  CRASH, KTEST, GTEST, ...).
- `/Music`: two original modules and four MIDI songs, generated at build time.
- `/APPS`: apps installed from `.HZA` archives, one folder each.

BASIC is described in [horizon/BASIC.md](../../horizon/BASIC.md) and the spreadsheet in
[horizon/SHEET.md](../../horizon/SHEET.md). Apps and their installation:
[sdk/docs/apps.md](../../sdk/docs/apps.md).

## Tests

`make -C horizon test` boots the emulator on fresh copies of two cards and runs scripted
sessions: the kernel's self test at three console speeds, the shell, every bundled
program, the window system, full screen and sprites, the music, the PC link, the internet,
printing and the apps. It compares console output with expected files and screenshots with
stored checksums, and fails on any broken blitter rule. See [Verification](verification.md).
