# Horizon

The Atari816 is a new 16-bit Atari, re-imagined around the 65C816, with a desktop of its
own; it is also compatible with the original 8-bit Atari. Horizon is its operating system:
a small Unix-style kernel for the 65C816 in native mode, its desktop and its programs. It uses FREDDIE II for memory protection, the bank 0 window
for each task's private direct page and stack, the I/O processor mailbox for files and
keys, Marga, the video chip, for a text console on screen and for a desktop of windows, and
a mouse pointer, and Ali, the blitter, to draw them (the CPU draws where there is none).
It boots into the Desktop (or, with `/SYSTEM/NODESK` on the card, into the text shell).

## The card (0.17)

| Folder | Contents |
| --- | --- |
| `/SYSTEM` | `HORIZON.SYS` (the kernel), `INIT.PRG`, the system programs `DESK.PRG` (the Desktop), `SH.PRG` (the shell), `ABOUT.PRG`, the settings files `CONFIG` (Settings), `PROGRAMS` (the Desktop's Programs menu) and `NODESK` (optional: boot into the text shell), and (0.14) `ICONS` (the Desktop's icons, made from `sdfiles/icons.txt`), `CLOCK` (the last time set, written by the Desktop and the shell) and `LAYOUT` (where the desktop icons are), (0.22) `URLS` (the Downloader's last addresses) and `BBS.TXT` (the BBS terminal's address book). Files hides it and refuses to start its programs |
| `/SYSTEM/TESTS` | Test and demo programs: SELFTEST, HELLO, COUNT, SPIN, TICK, REGS, CRASH, FTEST, PING, PONG, KEYS, MOUSE, MTEST, BENCH, WDEMO, LEAK, HOG, (0.15) KTEST, (0.17) STEST, (0.18) GTEST |
| `/BIN` | The applications: WFILES (Files), TERM (Terminal), EDIT, WRITE, SHEET, PAINT, BASIC, CALC, SOLITAIR, (0.17) QUABRICK (Quabricks; its samples QUABRICK.SFX, its high scores QUABRICK.DAT), SETTINGS, (0.22) DOWNLOAD (the Downloader), BBS (the BBS terminal), and the shell's tools FILES (the text browser), CAT, DIR, MEM |
| `/Desktop` | Created by the Desktop if missing: what is in it shows as icons on the desktop (0.14: shortcuts are `.LNK` files, below) |
| `/atari.ini` | The classic machine's settings, read by the I/O processor at boot (Settings > Classic Atari edits it) |

The shell finds a command word in `/BIN`, then `/SYSTEM`, then `/SYSTEM/TESTS`.

`/SYSTEM/PROGRAMS` is plain text, one `Title=/path` per line (`#` starts a comment), in
menu order; an entry whose program is not on the card is left out, so a new program needs
no Desktop rebuild:

```
Edit=/BIN/EDIT.PRG
Write=/BIN/WRITE.PRG
...
```

The kernel is 44 KB of 65816 assembly (ca65/ld65; 0.18): 37.5 KB in bank $01 (with the fonts,
the system palette and the pointer images) plus 20 KB of BSS there (the image and BSS end at
$01:E6E9 (BASIC 2.0): 2.3 KB left below $F000), and 6.8 KB of a second code segment that runs from bank 0
$E100-$FEFF (0.7 KB left; its 1.9 KB of tables at $00:A300, 1.3 KB left; see "Version 0.18");
the 800-byte video-state block at $01:F000 and a 256 KB framebuffer; with the window system,
one more bank holds the menus (0.14) and the draw lists' records. `tools/kspace.py` prints
these at every build. Programs are relocatable o65 files linked by
plain ld65.

**Shortcuts** (0.14): a `NAME.LNK` file is plain text: the target's absolute path on a line
of its own, then optionally `title=Label` (what the Desktop shows; else the file name without
`.LNK`) and `args=...` (a program's argument string); `#` starts a comment:

```
/BIN/EDIT.PRG
title=Edit
args="/docs/Read me first.txt"
```

Files and the Desktop open a shortcut as its target (`ui_open`). Dragging a file, folder or
program from Files onto the desktop makes one in `/Desktop` (Shift+drag moves the file
itself), and so does File > Add to desktop.

## Build, run, test

```
make          # build/sd: the normal SD card; build/tsd: the test SD card
make run      # emu816 on build/sd (the shell; with SDL you can type into it)
make test     # the regression at three console speeds, then a scripted shell session
make clean
```

`SHOTPNG=1 make test` (0.15) keeps PNG copies of the session pictures instead of the
PPM files once their md5 is taken (where disk space is short; the md5 are the same).

The two SD cards differ only in `/SYSTEM/INIT.PRG`:

- **`build/sd`:** INIT runs the Desktop, `/SYSTEM/DESK.PRG`, and starts it again whenever
  it exits. With a file `/SYSTEM/NODESK` on the card (any content), or with a key held
  down at start (pressed within INIT's first half second), it runs the text shell,
  `/SYSTEM/SH.PRG`, instead (again whenever it exits). `rm /SYSTEM/NODESK` in the shell
  removes the file. The text-console tests put
  that file on their copy of the card.
- **`build/tsd`:** INIT (`user/tinit.s`) runs `/SYSTEM/TESTS/SELFTEST.PRG`, waits for it and exits,
  so the run ends with `[halt] no tasks`.

`make test` runs twenty-six tests (`make test EMUFLAGS="--rev 7"` runs them on a board without
the blitter: the software drawing paths; both must pass):

1. **Regression.** SELFTEST runs on the test card with `--console-us 0`, `90` and `2000`.
   Each output is compared with `tests/selftest.txt`.
   - The keys that KEYS reads come from a fixed `--keys` script. SELFTEST holds the
     keyboard from its start, so the events queue up whenever they arrive, and KEYS gets
     the keyboard lent at the end.
   - Where several tasks print at once, the order of their lines depends on console
     speed. The expected file marks those stages `@@ any order`; there the lines must all
     be present, as whole lines, in any order.
   - Values that depend on timing, such as the code bank a crashing task happened to get,
     are `~ ` patterns.
2. **Shell session.** (It starts in the browser, like the real machine: Esc first.) The normal card boots into the shell, driven by `tests/shell.keys`.
   `tests/keyscript.py` turns typed text (and `M dx:dy:wheel:buttons` lines) into emu816 `--keys` and `--mouse` lists. The session runs at
   `--console-us 0` and `2000` and is compared with `tests/shell.txt`. It types help, dir,
   cat, hello with arguments, a background count, ps, mem, two crashes, ctrl-C on a
   foreground job, a line edited with backspace, an unknown command, kill, ctrl-C at the
   prompt, the SEI crash (the watchdog kills it), exit (INIT starts a new shell) and ps.
   It also covers line editing (left arrow, insert, right arrow), history (up/down),
   `atari` with keys typed while the Atari has the keyboard, MOUSE fed by an emu816
   `--mouse` script (motion, a drag with the left button, wheel), a key held across the F12
   return (none of these may reach the shell), `cls`, and the Atari software commands.
   emu816 does not implement the I/O processor ops $18-$1A yet (it answers $82), so for
   these the test covers the shell's own argument errors, the error messages and the
   recovery after a failed `boot`. Commands are 2-3 s apart, longer than any of them
   takes at 2000 us per byte. The run ends at `--max-seconds 105`, which is the
   `emu816 exit 3` at the end of the file.
3. **Screen pictures.** `tests/screen.keys` drives a short session, and emu816 takes four
   shots: text with the cursor after an edit, the screen after `cat long.txt` (it scrolls
   past the copy-back) with the mouse pointer moved over it by `--mouse`, the classic
   machine shown (desktop and pointer off: black), and the return.
   The md5 of each picture is compared with `tests/pictures/screen.md5`, and PNG copies
   are kept next to it. After an intended change, look at `build/screen*.ppm`, then run
   `make pictures` to freeze the new ones.
4. **Browser session.** `tests/browse.keys` (keys and mouse) on the test tree (below):
   - into /many (250 entries), PgDn, type-ahead, End/Home;
   - the wheel and a double click run a file; F12;
   - Backspace back to /, type-ahead to docs, the pager;
   - a cartridge, then a disk ("start this, and only this");
   - Esc to the shell and a paged `ls`.
   Seven pictures are checked by md5 (`tests/pictures/browse*.png`), and emu816's log
   of the classic-machine ops is compared with `tests/browse.err`. That log shows the
   ejects before each run.
5. **Window system pictures.** `tests/wdemo.keys` runs `wdemo` (three windows) and uses
   the mouse: a click raises Text, a title drag moves it (stopped at the bottom edge),
   a click raises Shapes, its close box closes it, and two keys close the other two. After
   the last one the window system stops and the shell is back as it was. Six pictures
   (`tests/pictures/wdemo*.png`).
   **Window copy.** `tests/wcopy.keys` runs `wdemo copy`: a pattern, then seven moves
   inside the window with win_draw's copy (overlapping in every direction, one source and
   one destination partly outside). One picture (`tests/pictures/wcopy.md5`), the same
   with and without the blitter (checked against a model of the moves when it was made).
6. **Desktop pictures.** `tests/desk.keys` boots the Desktop (no NODESK): Files at start,
   a live resize by the grip, About from the Horizon menu, the Programs menu open and
   Terminal from it, `ls` in the Terminal, F12 to the classic machine and F12 back.
   Seven pictures (`desk*.png`; with
   `--rev 7` About says "Blitter: none (the CPU draws)" and "Sound: POKEY 2": `desk-rev7.md5`).
7. **Edit, Paint, Settings, Files pictures.** `tests/edit.keys` (text shell: editing,
   selection, copy and paste, both fonts, the save dialog, the close alert),
   `tests/paint.keys` (every tool, undo, saving .PIC and .BMP, a shape drawn with the
   right button in the background colour, the crosshair over the canvas), `tests/settings.keys`
   (Desktop: desktop colour, repeat, alert volume, Save), `tests/files.keys` (Desktop: icons,
   a second Files window, a drag between windows, copy and paste, New folder, Delete).
   Without the blitter these run slower, so the same sessions reach later states: they
   have their own `*-rev7.md5`. A second Edit session, `tests/editw.keys`, types three
   lines, undoes and redoes (words, Backspace), turns word wrap on in both fonts (End on a
   wrapped row), uses Find, Replace all (then undo, redo), Go to line, a double click and
   ctrl-Right, Word count, and saves: nine pictures (`editw*.png`, the same with and
   without the blitter), and the saved file must equal `tests/editw.txt`.
8. **BASIC.** `basic -t` runs `tests/basic.bas` as a script (`tests/basic-t.keys`): it
   RUNs `/programs/TESTS.BAS`, which prints PASS or FAIL for each group of statements and
   functions, then error messages, LIST, INPUT, CONT, SAVE / LOAD and the benchmarks. The
   console is mirrored to DBG_OUT; the output is compared with `tests/basic.txt` (the
   benchmark times are patterns). See BASIC.md.
9. **BASIC pictures.** `tests/basic.keys`: a program typed in lower case and listed, an
   error with its line, the demo in its graphics window, a listing, the Program menu.
   The same pictures with and without the blitter (`tests/pictures/basic.md5`).
10. **Sheet.** `sheet -t` runs `tests/sheet.sht` (`tests/sheet-t.keys`): PASS or FAIL for
   each group (input and rounding, arithmetic, every function, errors, cycles, copy, fill,
   insert and delete with their references, .SHT and CSV round trips, formats, bad input,
   out of memory) and the recalculation benchmark, compared with `tests/sheet-t.txt` (times
   are patterns). Then `tests/sheet.keys`: the budget example, a formula being typed with a
   cell clicked into it, a range selected, the Format menu, a format applied, a column
   widened by its header (`tests/pictures/sheet.md5`, the same with and without the
   blitter). See SHEET.md.
11. **Blitter rules.** No emu816 report of START or register writes while BUSY, or of
   CPU reads without CACHE_FLUSH, in any of the runs.
12. **F12 round trip.** The desktop after F12 and back is compared pixel by pixel with the
   picture before it (below the menu bar, whose clock moves).
13. **The Desktop's system functions** (0.13, `tests/system.keys`, made from
   `tests/system.src` by `tests/mousegen.py`; the card gets `tests/system.programs` as its
   Programs list): the menu read from the file (a missing program left out), `hog 1 &` in
   the Terminal and the shell's "not enough memory" message, Paint's out-of-memory alert,
   Force quit (HOG), About started twice (one window, raised), Shut down cancelled by Edit's
   save question, Shut down again (Discard), the "safe" screen, Restart (emu816 restarts the
   machine: `SYS_RESTART 1` in its log), README.TXT dragged from Files onto the desktop
   (moved into /Desktop: its icon), the SD card icon (Files at the root), the README icon
   (Edit). Fifteen pictures (`system*.png`; About says which chips there are: `system-rev7.md5`).
14. **Keyboard menus** (`tests/kmenu.keys`): F10, arrows, Enter, Alt+letter, Alt alone,
   Esc, letters in a menu, ctrl+W, Alt+Tab, Alt+F4, and `wdemo menu` (check marks, a dimmed
   item, shortcuts, win_mstate). Twelve pictures (`kmenu*.png`, `kmenu-rev7.md5`).
15. **Settings, Classic Atari** (`tests/classic.keys`; the card gets `sdfiles/atari.ini`):
   two values changed, Save, the restart alert; the saved `/atari.ini` must equal
   `tests/atari-ini.txt` (only the lines of the changed keys rewritten, the missing key
   appended). Four pictures (`classic*.png`, the same with and without the blitter).
16. **Files** (0.13 session, sixteen pictures): the Up button, "..", the full path, a drag
   between windows, copy and paste, Rename and New folder (ui_ask, Tab through the buttons),
   a .MD file (Write, or its "not found" alert), Delete, View > Show system files, the
   refusal to start /SYSTEM/INIT.PRG.
17. **Leaks** (`tests/leak.keys`, text shell): `leak 200` starts 200 programs that take a
   window with a menu and a timer, the pointer shape, the screen hold, the clipboard, two
   files, two banks and a port, and give nothing back (half exit, half are killed); the free
   banks, window slots, ports, file handles and task slots must be the same before and after.
18. **0.14 additions.** `wdemo draw` (`tests/wdraw.keys`, text shell): WD_EXPAND opaque, transparent,
   from a bit offset and cut at the edges, WD_KSBLIT with a stride, then SYS_WGEOM moves and
   resizes the window (`wdraw*.png`, the same with and without the blitter). `tests/wins.src`
   (Desktop): maximize by the button, restore, maximize and restore by double clicks,
   minimize, the Windows menu (a minimized window in brackets) and choosing from it, Alt+Tab
   bringing a minimized window back (`wins*.png`). `tests/desk14.src` (Desktop; the card gets
   /GAME.ATR): File > Add to desktop, a shortcut made by a drag from Files, BLUE.XEX and
   GAME.ATR dropped on the Atari icon (the disk goes to D2:), the Atari panel, Eject, Eject
   all, the "Date and time" dialog and the bar's 14:05, an icon dragged and snapped, the
   right-click menu, Tidy up, a shortcut deleted, About's date (`desk14*.png`); the mounts,
   the shortcuts and /SYSTEM/CLOCK are checked too.
19. **0.15 kernel** (`tests/ktest.src`, text shell, `--log-sound`): KTEST reads the joystick
   (SYS_JOY, and its test aid), times 30 vertical blanks (SYS_VSYNC: 500 ms), plays the four
   chimes, lets a child write POKEY 2 and a DAC and exit (the kernel silences them), holds
   all four channels and asks for a chime (channel 4 borrowed and given back); then, with
   the window system: a held key and a second window (the first one gets the key's release
   and WE_UNFOCUS, the second WE_FOCUS, the real release reaches nobody), a menu chosen with
   the mouse and the pointer moved over a WF_HOVER window (its motion events say no button:
   the phantom $0004 is gone), pop-up menus (a right press dragged to an item, a right click
   and Esc, the menu key with Down and Enter). Its console must equal `tests/ktest.txt` and
   its sound writes `tests/ktest.err`.
20. **0.15 pop-up menus** (`tests/desk15.src`, Desktop; the card gets /GAME.ATR): the Atari
   icon's menu, Attach disk... (the file dialog lists only folders and disk images; type-ahead
   selects GAME.ATR), its Eject line, Files' menus on a text file, on a disk image (Load into
   Atari) and below the rows, a text field's menu, the desktop's menu (New folder...), an
   icon's (Rename...), Edit's text menu, by a right click and by the menu key; twelve
   pictures (`desk15*.png`), /Desktop/Games and the mounts are checked. (0.18)
   `tests/desk18.src`: BLUE.XEX dropped on the Atari icon, the panel and its Attach
   cartridge... (the dialog lists only cartridges), Star Raiders attached (the desktop stays),
   the panel's right-click menu, the cartridge's Eject; five pictures (`desk18*.png`), and
   the classic-machine ops must equal `tests/desk18.err` (MOUNT executable; EJECT executable,
   MOUNT cartridge, BOOT; EJECT cartridge, BOOT).
21. **0.17 samples** (`tests/stest.keys`, text shell, `--log-lau`): STEST plays samples from
   its code bank (8-bit, looped) and its window (16-bit), has sample_play refuse the kernel's
   bank, the framebuffer, a bank nobody owns, a range past the window or out of its own bank
   (EFAULT), an odd 16-bit address, no samples, a loop shorter than 4 and voice 8 (EINVAL);
   frees a bank a voice plays from (the voice stops first), fills the eight voices (a ninth
   takes its oldest), stops one and all, changes a voice with sample_set (not another
   task's), starts a child that plays and exits and one that is killed (their voices stop;
   while one plays its voice cannot be taken: EAGAIN), and moves the volume setting (Lau's
   master volume follows). Its console must equal `tests/stest.txt` and its writes to Lau
   (emu816's new `--log-lau`) `tests/stest.err`. Without Lau (`--rev 9` or lower) it prints
   that sample_play returned ENODEV: `tests/stest-nolau.txt`, and nothing is written to Lau.
22. **Quabricks** (with the Calculator and Solitaire in `make test-games`): `quabrick -t`
   (`tests/quabrick-t.keys`) runs the self test of the rules, compared with
   `tests/quabrick-t.txt` (1.1: also every level's speed, played: the frames an O piece takes
   to fall 18 rows and to lock on the floor, levels 1-31); `tests/quabrick.keys` plays a scripted session (fixed seed and a
   forced first list of pieces): title, setup, a double, a T turned and held, a Quad, pause,
   the end, the new record's name, the table, Time Attack, the right button's menu, How to
   play, the high scores. Fifteen pictures (`quabrick*.png`; the same with and without Lau,
   and with or without Ali's command lists (1.1: REV $09+ draws each frame with one draw
   list, REV $08 with win_draw calls), `quabrick-rev7.md5` without the blitter: it draws
   slower, so some shots catch earlier states), and the saved /BIN/QUABRICK.DAT must hold the
   name.
23. **0.18 games round** (`tests/gtest.keys`, text shell): GTEST (`user/gtest.s`) checks frame
   and vsync, palette entries (pal_alloc's spare ranges, a given place, another program's entry
   refused with EAGAIN, entries given back at its end), sprites (refused images: the kernel's
   bank, the framebuffer, a bank nobody owns, past the window, out of an own bank: EFAULT;
   unaligned, another program's sprite, shown without an image, an image's bank freed: EINVAL;
   a child's sprites freed at its exit and kill), full screen (bad blocks, foreign memory
   EFAULT, another program EAGAIN, every scroll set and raster table checked against the
   framebuffer, its bank freed), draw lists (EINVAL, EFAULT, the area limit, 100 keyed blits,
   list_wait), WE_VBL and (0.19) sheets (Version 0.19); its console must equal
   `tests/gtest.txt` (`gtest-r10.txt` on REV $09-$0A, `gtest-r8.txt` below), and two pictures
   (`gtest.md5`: the lists' result, palette entries back at the system's colours; (0.19) the
   sheets' picture) are the same at every revision (Ali's list, single blits, the CPU). On REV $0B also: `tests/gtests.keys` (sprites over a window: shown, hidden
   by the focus going elsewhere, back, one moved past the content's edge), `tests/gtestf.keys`
   (a full-screen 320x180 screen with a split status panel, wrapped scrolling, sprites and two
   raster colours; Alt+Esc back to the desktop; Alt+Tab to it again; its end) and
   `tests/gtestk.keys` (Desktop: `gtest f &` in the Terminal, Alt+Esc, `kill` from the
   Terminal: the desktop as it was).

24. **BASIC 2.0** (`make basic2-test` alone; run first by `make test`): `basic -t` runs
   `tests/basic2.bas` (`tests/basic2-t.keys`; the card gets the sound files of
   `tests/mkwav.py`): every games statement and function with its errors, LIST and SAVE of
   the new words, a 1.x program loaded, drawing in the window and in full screen (the
   blitter's list, then the CPU), sprites and HIT, SCROLL / PANEL / RASTER and their checks,
   WAVE (made, 8- and 16-bit .WAV, raw, a refused stereo file) and PLAY, the cleanup after
   STOP, CONT, an error, RUN and NEW. The output must equal `tests/basic2.txt` (REV $0A
   `basic2-r10.txt`, $09 `-r9`, $08 and $07 `-r8`: the hardware that is missing says "Not
   available on this machine", nothing else changes) and the writes to Lau
   `tests/basic2.err` (`basic2-r10.err`; none without Lau). On REV $0B, `tests/basic2s.keys`:
   SPRITES.BAS, Esc, DRIFT.BAS (title, play), Esc (the desktop, the window with the last
   picture), SCROLLER.BAS (full screen, panel, raster bands), Alt+Tab, Esc, CONT, SCREEN 0:
   ten pictures (`basic2s*.png`).
25. **The PC volume** (0.20, `make test-pc` alone): emu816 serves `/PC:` from a fresh copy of
   `tests/pc` (`--pc-folder build/run-pc`) with the PC's clock fixed (`--pc-time
   2026-03-04T05:06`; the PC files the run did not write get `--card-date`). `tests/pcshell.keys`
   (text shell; the folder also gets HELLO.PRG as hello.prg): `date` (the clock came from the
   PC), `ls /PC:` with dates, `cd /pc:`, `cat`, `cp` both ways (a file, a folder), `mv` from the
   card to the PC (a file, a folder: copy, then delete), a program run from the PC, `mv` inside
   the PC; its console must equal `tests/pcshell.txt`, and the files must be where they should
   be on both sides. `tests/pcshell2.keys` without the volume: `ls`, `cd`, `cp`, `cat`, `mv`
   answer "no PC link" at once (`tests/pcshell2.txt`). `tests/pcdesk.src` (Desktop, with
   `--pc-drop-at 27.5 --pc-back-at 35.5`): the PC icon, BLUE.XEX and the docs folder dropped
   on it (copied), Files at /PC: (a date on the footer), copy and paste from the PC to the
   card, README.TXT dragged from the card's window into the PC's (moved), the icon gone after
   the drop and back after the return, the file dialog (Edit, ctrl-O) at the root with the
   `PC:` folder and in /PC:; nine pictures (`pcdesk*.png`; `pcdesk-rev7.md5`: the free memory
   in the bar is read at other moments), the files on both sides and /SYSTEM/CLOCK checked.
26. **Long copies** (0.21, in `make test-pc`): emu816 with the board's transfer speeds
   (`--card-kbps 170:100 --pc-kbps 100:55`) and a 384 KB `/BIG.BIN` on the card copy
   (`tests/mkbig.py`, the same bytes every time). `tests/pccopy.src` (Desktop, the link dropped at
   44.5 s): BIG.BIN pasted into /PC: in Files, the progress window; meanwhile a click into Edit,
   text typed and the pointer moved, then Files' title clicked: the text is in Edit, the copy
   still runs, the pointer where the moves left it (keys and mouse keep coming during a long
   request); back to the card ("Copy of BIG.BIN"), Esc in the progress window, then in full;
   into /PC: again, Cancel clicked; once more with the link dropped during the copy ("The PC
   link was lost"). Six pictures (`pccopy*.png`; `pccopy-rev7.md5`: without the blitter the
   copy is a little behind at shot 2); the copies must equal BIG.BIN byte for byte,
   and nothing may be left by the cancels or the drop (on the card, in the PC folder, in its
   `.atari816-partial`). `tests/cpstop.keys` (text shell): `cp` to the PC, `cp` on the card and
   `mv` to the PC, each stopped by ctrl-C ("cp: /BIG.BIN: cancelled"), "ls" typed during a copy
   kept for the next prompt; the console must equal `tests/cpstop.txt`, BIG.BIN stays, and no
   partial file is left.

27. **The internet** (0.22, `make test-net` alone): emu816 with `--net-root` on a fresh copy
   of `tests/net` (the host `files.test`, and a 384 KB `big.bin` from tests/mkbig.py) at the
   board's speed. `tests/netshell.keys` (text shell, with `/PC:` too): `get` to the card and to
   `/PC:` (the progress lines, the name without the query), an FTP and an HTTP folder
   listing, 404, a host that is not there, ctrl-C (no partial file), `cp` of a URL into a
   folder, `cat` of a URL, `ls`/`cd`/`rm` of a URL; the console must equal
   `tests/netshell.txt` and the files the server's byte for byte. `netshell2` (a gateway
   without the internet: "no such service"), `netshell3` (the link dropped during a get).
   The Downloader (`tests/download.keys`, 8 pictures): the window, the progress, done, HTTP
   404, the Replace question, Cancel (no file left), the Recent pop-up; /SYSTEM/URLS. The BBS
   terminal (`tests/bbs.keys`, 5 pictures, `--net`): `tests/bbsserver.py`, started by the
   Makefile on a free port of 127.0.0.1 (written into the card's address book as "Test
   board"; the server stops after the session), sends a telnet negotiation and an ATASCII
   screen, an ANSI screen on request, closes on request; the pictures show the ATASCII screen,
   the ASCII mode, the remote close, the Connect dialog and the lost link (`--pc-drop-at`);
   what the server got (the negotiation answers, the terminal types, the keys) must equal
   `tests/bbs.log`. No internet is needed. Not covered: a URL whose size the server does not
   give (emu816 always gives the file's size; uicpwin and `get` show "KB" only then).

The Desktop sessions (`DESK=1` in `tests/shots.sh`) get `tests/desk.programs` as their
Programs menu (the order of 0.12), so programs added to `sdfiles/PROGRAMS` do not change
their pictures. `PREP=command` runs a command on the session's copy of the card first.

The browser session also runs with `--log-sound`: `tests/browse.err` shows POKEY 2 and
the DACs silenced before every boot of the classic machine.

The SD cards also get a test tree, made by `tools/mktree.py`:

- folders with long names containing spaces, `+`, `_`, `(`, `)`, `!`, `[`, `]` and
  apostrophes (disks/xex/R - Z/River Raid (Title Version).xex, carts/Montezuma's
  Revenge _ Parker Brothers.atr, ...);
- `many/` with 250 entries, one name longer than the list column;
- docs/Read me first.txt (60 lines);
- programs/Hello Program.prg.

The Atari files are copies of `BLUE.XEX`, a real 20-byte executable, so the tree also
works on the board.

To run on hardware, copy `build/sd/SYSTEM`, `build/sd/BIN` and `build/sd/README.TXT` to
the SD card.

## The PC volume (0.20)

With the PC link, a folder of your PC is a second volume of the Atari816, next to the SD
card. How to start the gateway on the PC: see the root README, "PC link".

- **Its name is `/PC:`.** `/PC:/Games/blue.xex` is a file in the shared folder. Names are not
  case-sensitive (`/pc:` works too); new files get the case you type. Every program reaches it
  through the normal file calls: `ls /PC:`, `cd /PC:`, `cat`, running a program from it, Edit's
  Open and Save dialogs. In the card's root (`/`) the volume shows as a folder named `PC:` at
  the end of the list (the shell's `ls /`; Files and the dialogs sort it among the folders).
  Files whose names start with `.` on the PC are not shown.
- **The Desktop** shows a "PC" icon (a monitor) under the Atari icon while the volume is
  there; it is looked at every 5 s, so the icon comes when the gateway connects and goes when
  it stops. A double click opens Files at `/PC:`. A file or folder dropped on it (from Files or
  from the desktop) is copied into `/PC:`; a file from the PC dropped on the SD card icon is
  copied to the card's root. The icon's place is kept in /SYSTEM/LAYOUT as `:PC`, also while
  the PC is away.
- **Copy and move between the card and the PC** work both ways, for files and for whole
  folders: Files' Copy and Paste, a drag between two Files windows, the shell's `cp` and `mv`.
  A move between the two volumes is a copy, then the original is deleted (only when the whole
  copy worked). Inside one volume a move is a rename, as before.
- **The clock:** when Horizon starts with the PC there (the Desktop, the shell), and when the
  PC icon comes, the clock is set from the PC's clock and saved in /SYSTEM/CLOCK. Without the
  PC nothing changes: the last saved time (provisional), or the time you set.
- **Errors:** "no PC link" (the PC is not connected: $C7), "the PC link was lost" (the link
  stopped during the operation, or a file was opened before it stopped: $C8), "not on the
  same volume" ($C9, a rename between the card and the PC; Files, the shell and the Desktop
  copy instead).
- The volume is slower than the card: about 100 KB/s to read and 55 KB/s to write, a few ms
  for each operation (the card: about 170 and 100 KB/s).
- **Long copies** (0.21): Files and the Desktop show a progress window when a copy or a move
  takes more than about half a second: the file's name, "123 of 1,500 KB (8%)", a bar and a
  Cancel button (Esc and the close box work too). Cancel stops after the piece being copied:
  the file copied in part is deleted, on the card or on the PC (in a folder copy, the files
  copied before stay). A move that is cancelled or fails never deletes the original. In the
  shell, ctrl-C stops `cp` and `mv` ("cp: NAME: cancelled"). The keyboard and the mouse keep
  working in the other programs during a copy.
- **Unfinished files:** the gateway writes a new file under a temporary name and gives it its
  name only when it is complete. A copy to the PC that is cut off (Cancel, a lost link, a
  reset) never leaves a half file there, and an older file of that name stays as it was.

## The internet (0.22)

With the PC link's gateway running on a PC (and not started with `--no-net`), the Atari816
reaches the internet through it: the PC makes the connections, does the name lookups and
TLS; the Atari816 sees bytes (ABI.md, "The internet"). **A URL is a path:**

- `http://`, `https://` and `ftp://` URLs read like files. The shell's `cat`, `cp` take them
  (`cp https://example.org/file.zip /PC:`); an `ftp://` URL ending in `/` reads as the
  folder's listing. They are read only.
- `tcp://host:port` (and `tls://host:port`, TLS done by the PC) is a connection, for programs
  like the BBS terminal.
- The shell passes a URL on unchanged (no current folder in front, no change of case). A
  copy into a folder takes the URL's last part without its query (`?...`): `index.html` when
  there is none, `listing.txt` for an FTP folder.
- **`get URL [to]`** (the shell) downloads: `to` is a folder (the name goes inside it) or the
  new file's name, by default the URL's name in the current folder. The progress is one line,
  `12 of 40 KB (30%)`, or `12 KB` when the server does not say the size; ctrl-C stops it and
  deletes the partial file. Then `saved NAME (40 KB)`.
- **The Downloader** (Programs menu; `/BIN/DOWNLOAD.PRG`, `download [URL]` in the shell): an
  address field, Save as (the folder last used and the URL's name; Choose... opens the file
  dialog), a bar with `123 of 456 KB (27%)` (or `123 KB`), a status line, Recent... (the last 8
  addresses that worked, kept in /SYSTEM/URLS), Cancel (Esc, the close box) and Download
  (Enter). It reads in pieces of 4 KB and looks at its window between them, so Cancel always
  works; a cancelled or failed download leaves no file. It asks before replacing a file.
- **The BBS terminal** (Programs menu; `/BIN/BBS.PRG`, `bbs [-ascii] [host[:port] | name]`):
  telnet to a bulletin board. Connection > Connect... takes `host`, `host:port`,
  `telnet://host[:port]` or `tcp://host:port` (port 23 when none is given); the address book
  `/SYSTEM/BBS.TXT` (one `Name=host:port` per line, `#` comments; it ships with comments only:
  add your boards) fills the rest of the menu. Mode: **ATASCII** (40 x 24, the Atari character
  set with its graphics characters and inverse video, the screen editor's control codes; the
  keys send Atari codes: Return $9B, Backspace $7E, Tab $7F, the arrows $1C-$1F) or **ASCII**
  (80 x 24, VT52 and a small ANSI subset: positions, erase, bold, inverse). A remote close, a
  lost link or a failed connection is said on the screen. Not yet: file transfers, capture,
  colours.
- **Errors** (the shell and the programs): "no such service: the gateway has no internet (or
  --no-net)", "HTTP error 404", "name not found", "refused or unreachable", "timeout", "TLS
  failed", "the connection was closed", "the PC link was lost", "no PC link".
- **What it reaches:** whatever the PC can reach, the home network too.

## The shell and the file browser

At power-on INIT starts the shell with `files` as its first command, so the machine comes
up in the file browser (Esc leaves it for the `> ` prompt; `files` brings it back). That
suits a games machine: pick a game, Enter, play, F12 returns to the list.

**FILES** (`/BIN/FILES.PRG`, the full-screen browser):

- **List.** The current folder, read once into a bank of its own: up to 1000 entries,
  names of any length, sorted on the way in (folders first, then case-insensitive
  names). Keys only move the selection and redraw the lines that change, so a
  250-entry folder stays instant.
- **Keys:**
  - up/down, PgUp/PgDn, Home/End move;
  - typing jumps to the first name starting with the typed letters (a 1 s pause starts
    over);
  - Backspace goes to the parent folder, with the folder you came from selected;
  - Esc goes back to the shell.
- **Enter:**
  - a folder: goes in;
  - an Atari file (.atr .xfd .xex .com .exe .car .rom .bin): runs it;
  - a .PRG: runs it as a Horizon program;
  - a text file (.txt .doc .nfo .md .cfg .ini .asc): shows it a page at a time.
- **Mouse.** The wheel scrolls, a click selects, a double click (within 0.5 s) opens.
- **Status line.** What is in D1:, the executable and the cartridge (classic_query).
- **Running Atari software is "start this, and only this"** (ulib `atari_run`, also
  the shell's `run`):
  - a disk or an executable ejects the cartridge;
  - a cartridge ejects the executable and D1: (D2:-D4: stay);
  - then the file is mounted on D1: (or as executable / cartridge) and the Atari is
    cold booted.
  `mount` stays additive and `boot` is unchanged. (0.18) Files' Load into Atari (ui_atload)
  only mounts, except a cartridge: the executable ejected, then a cold boot that stays on
  the desktop (a power cycle).

**The shell:**

```
> help
built-ins: help, ls [path] (or dir), cat file, cd [path], pwd, ps,
  mem, kill id, cls, atari, exit, files (the file browser), restart [full], shutdown
files: rm path..., mkdir path, mv from to, cp from to (to: a folder too)
Atari: mount file [1-4], eject d1-d4|cart|xex, boot, run file
other words run <WORD>.PRG from /BIN, /SYSTEM or /SYSTEM/TESTS (or a .PRG path);
  the rest of the line is its argument; a trailing & runs it in the background
names with spaces: "in quotes"; ctrl-C stops the foreground job
```

- **Arguments** may be quoted: `run "River Raid (Title Version).xex"`,
  `cd "disks/xex/R - Z"`.
- **Current directory.** `cd` (no argument: `/`) and `pwd`. Every path is relative to
  it, for the built-ins and for every program: the kernel keeps a current directory per
  task, inherited at spawn.
- **Programs.** A command word with a `/` or ending in `.PRG` is that file (relative
  paths allowed, quotes for spaces); any other word is `<WORD>.PRG` from the first of
  `/BIN`, `/SYSTEM`, `/SYSTEM/TESTS` that has it. When a program cannot start, the shell
  says why: "not enough memory to start it. Close a program and try again.", "too many
  programs are running", "not found", "not a Horizon program", "already running".
- **`restart [full]`, `shutdown`.** Under the Desktop they ask it (SYS_SYSREQ: every program
  is asked to close first). In the text shell they ask "(y/n)"; `shutdown` ends every other
  program, closes the files, flushes the card (SYS_SYNC) and shows "It is now safe to switch
  off the Atari816. Press R to restart."
- **`ls`** (Unix name; `dir` is the alias) prints one entry per line: the name in a
  column as wide as the screen allows (cut with `>`), sizes right-aligned (K above
  64 KB), `<DIR>` for folders. It pauses after each screenful (any key: next page; q,
  Esc or ctrl-C: stop). It lists in the I/O processor's order (FatFs directory order on
  the board, sorted by name in the emulator); the browser sorts.
- **Line editing.** Backspace, left/right (insert in the middle), up/down for the last
  8 lines. A line may use the whole screen width.
- **Background jobs.** `cmd &` runs in the background; `[done] id exit code` comes
  before the next prompt. ctrl-C stops the foreground job.
- **`cp` and `mv`** (0.21): ctrl-C stops a copy between two pieces of 16 KB: "cp: NAME:
  cancelled", the partial file deleted (a move keeps its source). Other keys typed during the
  copy are kept and come at the next prompt (type-ahead, ulib `key_keep`, up to 80 characters:
  a whole command line).
- **Atari software:**
  - `mount FILE [1-4]` mounts a disk on D1:-D4:, an executable, or a cartridge (the
    kind comes from the extension).
  - `eject d1`-`d4` | `cart` | `xex` removes one.
  - `boot` cold boots with what is mounted; `run FILE` = start this, and only this.
  - F12 always returns to Horizon.
- **Tools in `/BIN`:** CAT, DIR, MEM. **In `/SYSTEM/TESTS`:** SELFTEST, HELLO, COUNT
  (argument: a letter), SPIN, TICK, REGS, CRASH (argument: mode 1-13), FTEST (file syscall
  test), PING (it starts PONG), KEYS, BENCH (console speed; `bench FILE` times a cat of
  FILE), MOUSE, MTEST, WDEMO, LEAK (`leak [n]`: n programs that take every kind of resource
  and never give it back; everything must be free afterwards), HOG (`hog [n] &`: holds all
  memory but n banks, for the out-of-memory messages).

## What SELFTEST runs

| Stage | Programs | Shows |
| --- | --- | --- |
| 1 | HELLO | spawn, output, getpid, exit, wait |
| 2 | COUNT A, COUNT B | two tasks at once, sleep, argument strings |
| 3 | SPIN, TICK, REGS | Preemption: TICK finishes while SPIN, a CPU hog, still runs (checked with task_info). TICK checks `uptime` against its sleeps. REGS checks that 8-bit A/B/X/Y, D, DBR and decimal mode survive preemption and syscalls |
| 4 | CRASH 1-12, then 13 | CRASH 1-12 run all at once: kernel write, foreign read, I/O write, bad S + COP, BRK, emulation mode, unowned bank, EFAULT, kill() of a sleeper, death holding 4 files, a port and 5 banks, bad S at an IRQ (whole frame lost, then half lost). CRASH 13 runs alone: SEI + loop, killed by the watchdog |
| 5 | CAT, CAT x2, FILES, DIR | Files, and two tasks using the mailbox at once |
| 6 | MEM, mem_info | bank_alloc until ENOMEM, then everything comes back |
| 7 | PING, PONG | message ports; the port number is passed as an argument string |
| 8 | /SYSTEM/TESTS/NOPE.PRG | spawn error $44 |
| 9 | KEYS | The keyboard is lent to KEYS, which reads 3 queued events, including the system key (F12) as $FF. Afterwards the keyboard is back with SELFTEST |
| 10 | MTEST | The keyboard is lent to MTEST, which feeds mouse events through the kernel (mouse_inject) and checks clamping to (0,0) and (639,359), coalescing of motion, separate button-change events and summed wheel steps, and ws_mouse (position and buttons without an event) |

## Source map

| File | Contents |
| --- | --- |
| `kernel/horizon.s` | Top level: includes every module into one assembly unit in bank $01 |
| `kernel/hw.inc`, `kernel/kdefs.inc` | Hardware registers; constants, bank 0 layout, direct page, macros |
| `kernel/boot.s` | Boot: kernel state, vectors, bank table, mailbox, timer, watchdog, creates INIT |
| `kernel/entry.s` | Vector entry, NMI hold release, user context save/restore, `ret_user`, faults, NMI and watchdog, panic |
| `kernel/sched.s` | `k_block` / `k_yield` / `k_wake`, scheduler, idle loop, interrupt service, tick, clock |
| `kernel/mem.s` (paths) | copy_upath: relative paths, `.`/`..` resolution against the task's current directory |
| `kernel/mem.s` | Bank allocator and FREDDIE II table, user pointer checks, MVN copy and fill |
| `kernel/syscall.s` | Syscall table, exit, yield, sleep, getpid, uptime, putc, puts, bank_alloc/free, mem_info |
| `kernel/task.s` | Task creation, exit, spawn (with arguments), wait, kill, task_info |
| `kernel/mbox.s` | Mailbox requests and responses, file syscalls |
| `kernel/loader.s` | o65 loader. It runs in the new task's own kernel context and places the arguments |
| `kernel/ports.s` | Message ports |
| `kernel/input.s` | Key queue, claim/read/release/lend, break key, classic_show and the key swallowing after it |
| `kernel/classic.s` | classic_mount, classic_eject, classic_boot (I/O processor ops $18-$1A), classic_query |
| `kernel/console.s` | Console lock and cooperative writer, kernel output and formatting |
| `kernel/screen.s` | Screen console: framebuffer, glyphs, cursor, scrolling, palette |
| `kernel/ws.s` | Window system: surfaces and the pixel core (fill, copy), clipped drawing (rectangles, frames, lines, text, blit), the compositor thread and damage list, the window manager, window syscalls |
| `tools/mkuifont.py`, `tools/mkpalette.py` | Make `kernel/uifont.inc` (the proportional UI font, cut from the 8x12 art) and `kernel/palette.inc` (the system palette) |
| `kernel/menu.s`, `kernel/term.s` | The menu bar and drop-downs; terminal windows (cells, control codes, key queue, the console syscalls of attached tasks) |
| `kernel/sound.s` | REV $07 sound: POKEY 2 and the DACs, silenced before every unfreeze; beep (stopped by the tick), sound_write; (0.15) the chime, who owns each channel |
| `kernel/vstate.s` | The video-state block at $01:F000 (ABI.md, "Video state"): NV_CTRL, NV_BASE, NV_STRIDE, the pointer and the palette as written, for tools reading memory from outside; the palette loader every palette write goes through |
| `kernel/mouse.s` | Mouse events, pointer position, hardware pointer, event coalescing, the mouse_inject test syscall |
| `kernel/pointer.txt` | The pointer image as text art. `tools/mkpointer.py` turns it into `kernel/pointer.inc` |
| `kernel/font8x12.txt` | The console font, 8x12 cells (original design), as editable text art. `tools/mkfont.py` turns it into `kernel/font.inc` at build time |
| `kernel/kdata.s` | Kernel variables (BSS in bank $01) |
| `kernel/sys13.s` | (0.13) restart, sync / shut down (I/O ops $1B, $1C), the Desktop request, single-instance programs |
| `kernel/ws13.s` | (0.13) win_mstate, ws_closeall, keyboard menus and window keys, the task helpers for task_info and single instance |
| `kernel/ws14.s` | (0.14) the title bar's minimize / maximize buttons, minimize, maximize, win_geom, the Windows menu, task_name, the clock (time_get / time_set) |
| `kernel/ws15.s` | (0.15) pop-up menus (win_popup), focus events, the keys a window holds |
| `kernel/sys15.s` | (0.15) joystick, vsync |
| `kernel/sys17.s` | (0.17) Lau, the sample player: sample_play / stop / stat / set, the range checks, voice ownership, the voices stopped at a task's end, at bank_free and before the classic machine runs, the master volume |
| `user/stest.s` | (0.17) STEST, the test of the sample calls |
| `kernel/k2.s`, `kernel/k2*.s`, `kernel/k2.inc`, `kernel/kfar.s` | (0.18) the second code segment (bank 0): frame sync and the vertical blank (`k2vbl.s`), palette entries (`k2pal.s`), sprites (`k2spr.s`), full-screen mode, scrolling and the raster table (`k2fs.s`), draw lists (`k2list.s`); its imports and the bank $01 wrappers |
| `kernel/k3.s` | (0.19) the third code segment (bank $7F): sheets (sheet_new, sheet_free, sheet_draw: the fast path and the full one), their cleanup at bank_free and at a task's end |
| `tools/kspace.py` | (0.18) the kernel's space at every build |
| `user/gtest.s` | (0.18) GTEST, the test of the games round's calls, (0.19) and of sheets (`gtest m`: the measurement; `gtest s`, `gtest f`: pictures) |
| `user/quabrick.s`, `user/qb_*.s` | (0.17) Quabricks, the falling-block game (its files are listed at the top of quabrick.s) |
| `tools/mkqbart.py`, `tools/mkqbsfx.py` | (0.17) Quabricks' art (`user/qb_art.inc`: its colours in local entries (1.1), the block tiles with rounded corners, the logo, the big fonts) and its samples (`/BIN/QUABRICK.SFX`) |
| `user/uipop.s` | (0.15) ui_popup, ui_popat, ui_menukey, ui_chime, ui_beep, the text field's pop-up menu |
| `user/ktest.s` | (0.15) KTEST, the test of the kernel's 0.15 additions |
| `user/uidate.s` | (0.14) the date: seconds to a calendar date and back, `/SYSTEM/CLOCK` (also linked by the shell); (0.20) the clock from the PC (ui_clkpc) |
| `user/uicopy.s` | (0.20) copying and deleting files and whole folders, and moves between the card and the PC volume (ui_cptree, ui_rmtree, ui_mvtree; also linked by the shell); (0.21) in pieces of 16 KB, a callback that may cancel; (0.22) URLs as sources (to a short read, ui_cpblk, ui_cpx), ui_isurl, ui_urlname |
| `user/uicpwin.s` | (0.21) the progress window of a long copy or move: name, KB, percent, a bar, Cancel (ui_cpwin, ui_cpdone) |
| `user/download.s` | (0.22) the Downloader: a URL to a file through ui_cptree in pieces of 4 KB, its progress, Cancel, /SYSTEM/URLS |
| `user/bbs.s`, `user/atascii.txt`, `tools/mkatascii.py` | (0.22) the BBS terminal (telnet, the ATASCII and ASCII / VT52 / ANSI screens, the address book /SYSTEM/BBS.TXT); its 8x8 ATASCII font: the graphics characters drawn in atascii.txt, the rest from the console font -> `user/atascii.inc` |
| `tests/net/`, `tests/bbsserver.py` | (0.22) the test "web" for emu816 --net-root (`files.test`) and the scripted loopback BBS of the BBS terminal's session |
| `sdfiles/icons.txt`, `tools/mkicons.py` | (0.14) the Desktop's icons as text art -> `/SYSTEM/ICONS` and `user/icons.inc` |
| `user/horizon.inc` | User ABI: syscall numbers, error codes, macros (`sys`, `print`, `ptr`, `exit`, long branches) |
| `user/ulib.s` | User library: line-buffered output and number printing, HID-to-ASCII (US, shift, caps lock, ctrl), `read_char`, `getline` (echo, backspace, ctrl-C), `parse_dec`, `spawn`, `exit_a`, `args_init` |
| `user/init.s`, `user/tinit.s` | INIT of the normal and of the test SD card |
| `user/desk.s`, `user/wfiles.s`, `user/term.s`, `user/about.s` | The Desktop, Files, Terminal, About |
| `user/edit.s`, `user/paint.s`, `user/settings.s` | Edit, Paint, Settings |
| `user/basic.s`, `user/bas_*.s` | BASIC (see BASIC.md; the files are listed at the top of basic.s); (2.0) `bas_game.s` pictures, sprites, full screen, the draw list, VSYNC; `bas_snd.s` WAVE, PLAY, NOTE |
| `tools/o65strip.py` | (BASIC 2.0) drops the relocation entries that add 0 from BASIC.PRG (linked and loaded at $0100), so the file stays under the loader's 64 KB; it checks that the loaded image is the same |
| `user/sheet.s`, `user/sht_*.s` | Sheet (see SHEET.md; the files are listed at the top of sheet.s) |
| `sdfiles/programs/*.BAS`, `*.SHT` | BASIC examples and the self test, Sheet examples, copied to `/programs` on the card |
| `user/ui.inc`, `user/ui*.s` | The controls library (`build/ui.lib`); 0.13: `uiopen.s` (ui_launch, ui_spawnerr, ui_ftype, ui_open: the one table of file types), `uiask.s` (ui_ask) |
| `kernel/wsx.s` | Clipboard, drag and drop, palette, settings, window titles |
| `user/sh.s`, `user/selftest.s`, `user/*.s` | Shell, regression script, demo programs |
| `user/leak.s`, `user/hog.s` | (0.13) LEAK (every resource comes back), HOG (fills memory) |
| `tests/mousegen.py` | Absolute mouse points (`tests/*.src`) to a keys file |
| `tests/selftest.txt`, `tests/shell.txt` | Expected output |
| `tests/compare.py`, `tests/keyscript.py`, `tests/shell.keys`, `tests/screen.keys` | Output comparison, key and mouse script generator (text, arrows, F12, raw key down/up, `M` mouse lines), session scripts |
| `tests/pictures/` | md5 of the screen, browser and window system pictures, and PNG copies |
| `sdfiles/` | README.TXT and LONG.TXT (150 lines, for scrolling) for the SD cards |

ABI.md describes the program interface: syscalls, the keyboard and console rules, error
codes, the program format, how a task starts, and faults.

## How it works

**Memory.**

- Bank $00:
  - $8000-$80FF: kernel direct page.
  - $8100-$82FF: idle and boot stack.
  - $8300-$A2FF: sixteen 512-byte kernel stacks.
  - $B000 and $C000: the mailbox rings.
  - $E000: JML trampolines to the kernel's vector handlers, write-protected by WP_VEC.
- Bank $01 holds the kernel and its BSS.
- Every other bank comes from the bank allocator, and the FREDDIE II table mirrors it:
  free = $00, kernel = $C0, task = $C0 | id.

**Entry and exit.**

- **From user mode:**
  1. Save A.
  2. FR_CTRL.USER_ARM tells user from supervisor entry.
  3. Save S and switch to the task's kernel stack.
  4. Write FR_CTRL, which releases the REV $04 NMI hold.
  5. Save X, Y, D and DBR, and copy the RTI frame into the TCB. The frame is trusted only
     inside the window, and only with ABORT_CAUSE clear for non-ABORT entries. Otherwise
     the task is killed.
- **`ret_user`:**
  1. Services pending interrupts.
  2. Acts on a kill or a reschedule.
  3. Rebuilds the frame on the task's stack and writes FR_CTRL with USER_ARM.
  4. Executes RTI.
- **Watchdog.** It is re-armed on every 10 ms tick. A watchdog NMI that interrupts user
  mode kills that task (cause $23). One that interrupts the kernel is a panic.

**Blocking.** Each task has its own kernel stack. `k_block` saves S and resumes another
task's kernel context ("S = saved S, RTS"); with none ready, it goes to the idle loop, the
only place with interrupts enabled.

- A new task's kernel stack starts in the loader, so the new task loads its own program
  and then reports to its parent, which is blocked in spawn.
- The kernel is never preempted; `need_resched` is acted on in `ret_user`.

**Console.** The console lock and cooperative writer are described in ABI.md, "Console".
The boot banner, panics and `[halt]` wait for the console directly. Nothing else holds
interrupts off while printing.

**Screen.**

- **Geometry.** 78 x 29 characters (`con_size`) in 8x12 cells, mode 1 (640x360, 4 bpp),
  stride 320, inside a paper-coloured border of 8 pixels left and right and 6 lines top
  and bottom.
- **Cell rows.** The framebuffer keeps a grid of 12-line cell rows (3840 bytes =
  15 x 256, so NV_BASE can point at any cell row); text row r is drawn 6 lines down in
  cell row r of the window. The border columns are never drawn.
- **Font.** Original design in `kernel/font8x12.txt`:
  - capitals and ascenders 7 rows;
  - x-height 6 rows;
  - two-row descenders;
  - glyphs up to 6 pixels wide;
  - row 11 is kept for the cursor.
- **Framebuffer.** It sits in banks $7C-$7F (kernel owned) and holds 60 cell rows
  (720 lines, 230,400 bytes). The pointer image is at $7F:F000, past them. (0.19) Between them,
  $7F:8400-$7F:EFFF: the blitter's command lists, the sheets' row tables and the kernel's third
  code segment (Version 0.19).
- **Scrolling.** The screen shows 30 cell rows from `scr_top`. A new line at the bottom
  moves NV_BASE down one cell row. It clears the cell row that comes into view (3.8 KB)
  and the 6 border lines at the top (1.9 KB), which still hold the lower half of the row
  that scrolled out. When the window reaches the end of the buffer, the visible rows are
  copied back to the top once and NV_BASE returns to the start.
- **Interrupts.** Every clear or copy works in steps of at most 2 KB (about 1 ms of MVN).
  In task context, interrupts are serviced between steps and the task yields when a
  reschedule is due.
- **Glyphs.** Each font row becomes 4 bytes of 4 bpp pixels through a 16-entry nibble
  table. The cursor is an XOR underline on the cell's last line. A writer hides it once
  per string (puts chunk, `[kill]` line), not once per character.
- **Speed in the emulator** (real cycle counts, measured with BENCH, in characters per
  second). BENCH's "plain" part writes 40 lines, so with 29 rows it now scrolls too.

  | Output | 8x8 cells | 8x12 cells (now) |
  | --- | --- | --- |
  | Plain text | 11,304 | 7,647 |
  | Scrolling text | 7,878 | 5,241 |
  | `bench long.txt` (scrolling cat of 9,635 bytes, file reads included) | 7,586 | 5,044 |

  The 12-row glyphs and the larger clear per line cost about a third of the speed. That
  is still well above the board's log (about 11,000 bytes/s at 90 us per byte, often
  much less).

**Classic machine.** On hardware REV $06 or later, the kernel freezes the classic Atari
(SV_CTRL bit 2 FREEZE_REQ, read-modify-write) at boot, once the console is up. It lets the
Atari run only while `classic_show` shows it, and freezes it again on the F12 return.
FROZEN is never waited for. On older hardware, and in the emulator (REV $05), the write is
skipped.

**Mouse.** See ABI.md, "Mouse". MOUSE events from the I/O processor are handled in
interrupt service: they move the clamped position and Marga's hardware pointer at once,
then queue an event for the keyboard holder. Motion events coalesce in the queue;
button changes never do; wheel steps are summed.

**Keyboard.** Claim, lend, release and the ctrl-C break are in ABI.md, "Keyboard".

**Event order.**

- The mailbox is drained before system-key presses are turned into $FF events. So a key
  event that arrived before an F12 press is queued before it, even after a long stretch
  with interrupts off.
- F12's own key events are dropped: the spec says F12 raises SYSTEM_KEY instead.

## The desktop (window system, stages 1 to 3)

INIT starts **DESK** (`user/desk.s`). It starts the window system and opens a backdrop
window (borderless, under all others) with the desktop picture; it carries the system
menus "Horizon" (About Horizon, Settings..., Force quit..., Switch to Atari (F12),
Restart..., Shut down...; 0.15 wording) and
"Programs" (read from /SYSTEM/PROGRAMS). The menu bar's right end
shows the time since start, "up H:MM" (the board has no clock). DESK opens **Files** at start.
Programs started from the menu run detached.

- **Files** (`user/wfiles.s`): the file browser as a resizable window (see its header).
- **Terminal** (`user/term.s`): a WF_TERM window of 76 x 24 cells running `/BIN/SH.PRG`
  unchanged: its output and that of everything it starts go there, and it reads its keys
  there (`ws_term`, inherited). Closing the window ends the shell; `exit` closes the
  window.
- **About** (`user/about.s`): version, machine, drawing mode, memory, tasks, time.
- **F12** (or Atari in the menu) shows the classic machine; F12 there returns to the
  desktop exactly as it was: the screen's banks are not touched, only NV_CTRL changes.
  Atari files opened in Files run the same way.
- `wdemo` shows the drawing primitives; `wdemo bench` prints the costs below.

Stage 3 (programs built on the shared controls library):

- **Desktop icons** (0.13: see "Version 0.13"): "SD card", "Atari" and what is in
  /Desktop, in columns from the top right; a double click opens; files dropped on a folder
  icon move there.
- **Files**: several windows (File > New window; opening a folder icon), drag and drop
  between windows and onto folder rows (moves), Edit > Copy / Paste (copies a file),
  New folder, Rename, Delete (with dialogs); opening a text file starts Edit, a `.BAS`
  file BASIC, a `.PIC` picture Paint.
- **Edit** (`user/edit.s`): texts of up to 32,000 lines / about 768 KB in a line heap
  over several banks; Shift selection, the system clipboard, the fixed or the
  proportional font, file dialogs, a scroll bar, an alert for unsaved changes. Since
  0.12 also: undo / redo (ctrl-Z / ctrl-Y, many levels; typing is one step per word),
  Find (ctrl-F), Find next (F3, ctrl-G), Replace / Replace all (ctrl-H; a dialog that stays
  open), Go to line (ctrl-L), word wrap at the window's width (View > Word wrap; the file
  is not changed; Up / Down, Home / End and PgUp / PgDn by rows, ctrl-Home / End by the
  text), ctrl-Left / Right by words, a double click selects a word, a triple click a line,
  a status line (line, column, lines, Modified, Wrap) and View > Word count.
- **Paint** (`user/paint.s`): a 320x200 canvas in 256 colours: pencil, line, rectangle,
  filled rectangle, flood fill, eyedropper, one undo; `.PIC` (documented in the source)
  and 8-bit BMP. The left button draws in the foreground colour, the right button in the
  background colour; the pointer is a crosshair over the canvas (WF_HOVER).
- **BASIC** (`user/basic.s`, BASIC.md): a line-numbered BASIC with a console window
  (scrollback, line editing, File and Program menus) and a graphics window (SCREEN, PLOT,
  LINE, CIRCLE, ...); Files opens `.BAS` files in it.
- **Sheet** (`user/sheet.s`, SHEET.md): a spreadsheet of 26 x 999 cells: decimal fixed-point
  numbers (four decimals, no binary floating point), formulas with references, ranges and
  functions, recalculated in dependency order after every change, copy / paste with
  references adjusted (and tab-separated text on the system clipboard), fill, insert and
  delete rows and columns, per-column formats, its own `.SHT` files and CSV; Files opens
  `.SHT` and `.CSV` files in it. Examples: `/programs/BUDGET.SHT`, `/programs/LOAN.SHT`.
- **Settings** (`user/settings.s`): two pages. Desktop: desktop colour, mouse speed, key
  repeat, alert volume (the chimes and the beep: `beep=`, kernel setting 1), (0.18) sound
  volume (Lau's master volume, which every program's samples follow: `sound=`, kernel
  setting 4; its Test button plays a short tone through Lau, the information chime without
  it), saved to `/SYSTEM/CONFIG` (`key=value` lines; a key missing keeps its default) and
  applied at boot (`settings apply`, run by DESK). Classic Atari (0.13): the keys of `/atari.ini` that the
  I/O processor reads at boot (`ram`, `stereo`, `kbdlayout`, `joystick`, `scanlines`,
  `hpos`, `boot`), written back keeping every other line, then "Restart now" / "Later".
- **Controls library** (`user/ui*.s`, `user/ui.inc`, built as `build/ui.lib`): buttons,
  scroll bars, text field, list, alert box, file open/save dialog, drawing helpers; one
  look for all programs.
- **Kernel additions**: the clipboard, drag and drop (win_at, win_info, win_drop), motion
  events while a button is held, WF_MODAL dialogs, 32 events per window, palette
  entries, settings (mouse speed, beep volume, key repeat: the kernel now repeats a
  held key), window titles, pointer shapes (arrow, drag, crosshair), blits with a
  source stride. See ABI.md.

Version 0.12:

- **Pointer without a button**: `ws_mouse` ($8A) returns the pointer (on the screen and
  relative to a window) and the buttons at any time; BASIC's MOUSEX, MOUSEY and MOUSEB
  use it, so they are always current. A window with WF_HOVER gets motion events whenever
  the pointer moves over it (coalesced like drag motion) and WE_LEAVE when it leaves; a
  first right or middle press over the top window holds the press like a left one
  (motion events, the release).
- **Copy inside a window** (`win_draw` op 9, WD_COPY; `ui_copy`): overlap-safe in both
  directions, one blitter COPY (BACKWARDS when the destination lies after the source),
  line by line on the CPU without the blitter. Scrolling uses it: the BASIC console,
  Edit, the list control (Files, the file dialog), and the kernel's terminals (which
  scrolled with one COPY already; now through the same routine). Scrolling one line,
  emulated, 100 lines in a row (the compositor's repaints included):

  | | blitter, before | blitter, now | CPU (REV $07), before | CPU, now |
  | --- | --- | --- | --- | --- |
  | BASIC console, 534 x 268, full of 62-character lines | 90 ms | 67 ms | 491 ms | 282 ms |
  | Edit, 480 x 260, LONG.TXT | 126 ms | 55 ms | 650 ms | 232 ms |

  With the blitter most of what is left is the blitter's own time (the copy in the
  window, then the repaint of the same area on the screen: about 9 to 18 ms each at
  this size, in the emulator's model) and the scroll bar's redraw (about 9 ms).
- **Video-state block** at $01:F000 (ABI.md, "Video state"), so the PC link's screenshot
  (`atari.py shot816`) reads mode, base, stride, palette and the pointer (its real shape
  and hot spot) without searching the kernel code.
- **Desktop**: the Programs menu; Files opens `.PIC` pictures in Paint.
- **BASIC**: `RUN /programs/sieve.bas`, `LOAD demo`: file names without quotes (BASIC.md).
- **On the board** (0.12, the Desktop, BASIC from the Terminal; emulator in brackets):
  (BASIC 1.0; for BASIC 1.1 and 1.2 the emulator's times are in BASIC.md, "Speed": they
  differ by at most 2 %) TESTS.BAS 16 groups, 0 failed, 3.66 s (2.02 s); SIEVE.BAS 89.0 s (45.2 s); an empty
  FOR loop of 100,000 4.0 s (2.44 s); arithmetic and an array store, 100,000 times 44.3 s
  (21.8 s). The board takes 1.6 to 2.0 times the emulator's time. `wdemo copy` gives the
  emulator's picture exactly (the blitter's BACKWARDS copies included).

After 0.12 (drawing speed, Edit):

- **Direct drawing** (kernel): a window whose content no other window overlaps, and over
  which no repaint is pending, draws on the screen itself. Each win_draw op is one pass
  instead of two (its bitmap, then the compositor's copy of the same pixels a tick later),
  and a WD_COPY scroll is one copy on the screen. The bitmap is brought up to date from the
  screen (a copy back) only when something needs it: the window gets covered, moves or
  changes size, or a repaint over it comes (only that part while it stays in view).
  ABI.md, "Direct drawing".
- **Terminals** keep their cells in a ring (a scroll moves no cells) and draw in bursts:
  output marks the rows that changed, and the terminal is drawn just before the next
  repaint, with one move for all the rows scrolled since the last one. Output after a quiet
  moment (an echo, a prompt) is drawn at once.
- **ws_hold** ($8B): a program can make the compositor wait while it draws one change in
  several calls (Edit and the BASIC console use it; it matters while the window is covered).
- **Scroll bars** move only their thumb (one copy of it, and the track where it was) when
  only the position changed: `ui_sbpos`, and the bar's own arrows, track, drag and wheel.
- **Text** with the blitter: a string that fits the clip sideways writes only each glyph's
  source and destination (and the UI font's width).
- **Edit** draws only what changed (typing redraws the end of one line; a cursor move, the
  column it left and the one it reached), takes the keys that come faster than it draws
  together (one scroll for all of them), and has the features listed above.
- Emulated times, from the key (or click) until the screen shows it. "100 lines in a
  row" is the method of the 0.12 table above (100 scroll steps programmed, then ws_sync);
  Edit's text area is 466 x 240 (a row less than before: the status line), BASIC's 520 x
  252, the Terminal's 608 x 276:

  | | blitter, 0.12 | blitter, now | CPU (REV $07), 0.12 | CPU, now |
  | --- | --- | --- | --- | --- |
  | Edit: one-line scroll (Down on the last row) | 69 ms | 22 ms | 288 ms | 93 ms |
  | Edit: 100 lines in a row, per line | 55 ms | 17.4 ms | 232 ms | 84 ms |
  | Edit: 100 Down keys 5 ms apart, per line | keys lost | 6.5 ms | keys lost | 12 ms |
  | Edit: PgDn | 137 ms | 55 ms | 642 ms | 344 ms |
  | Edit: a character typed at the end of a 60-character line | 17 ms | 5.2 ms | 38 ms | 9.3 ms |
  | BASIC console: one-line scroll (a click on the scroll bar's arrow) | 68 ms | 33 ms | 358 ms | 112 ms |
  | BASIC console: 100 lines in a row, per line | 67 ms | 28 ms | 282 ms | 137 ms |
  | BASIC: 200 lines printed by a program, per line | 2.4 ms | 1.6 ms | 10 ms | 6.1 ms |
  | Terminal: one-line scroll (Enter at the prompt) | 60 ms | 29 ms | 211 ms | 141 ms |
  | Terminal: `cat LONG.TXT` (150 lines), per line | 49 ms | 10.6 ms | 203 ms | 53 ms |

  A single scroll step cannot take less than one copy of the area in the blitter's model
  (1.85 CPU cycles a pixel): 14.4 ms for Edit, 17 ms for BASIC, 21.6 ms for the Terminal;
  below that only when steps come together (keys faster than the drawing, a program's
  output, a terminal's burst). The click case includes about 5 ms of the emulator's
  mouse delivery.

How it works:

- **Screen.** 640x360, 8 bpp, mode 0, stride 1024 (a power of two, so a line address is
  a shift: 64 lines per bank, 6 contiguous banks).
- **Surfaces.** Every window has its own 8 bpp bitmap with a power-of-two stride in
  contiguous banks, so it is linear and one blit covers any rectangle of it. Programs
  draw into it with win_draw and the kernel clips; they never repaint on exposure. A
  resize keeps the bitmap if it is large enough, else copies it into a new one.
- **Direct drawing.** See "After 0.12" above: a window fully in view draws on the screen,
  its bitmap follows only when needed (`w_stale`, `win_target`, `cr_unstale` in ws.s).
- **Compositor.** A kernel thread ("WS", priority 1) collects damaged rectangles (8;
  overlapping ones merge; when the list is full the new one joins the rectangle it grows
  least). One tick after the first damage it repaints them without overdraw: each
  rectangle is cut into bands (between window top and bottom edges) and each band into
  segments that belong to one window (or the desktop), and each segment is one copy.
  With the blitter (REV $08) a segment is one COPY (the desktop's dither: two COPYs of a
  pattern row, source stride 0, destination stride 2048); without it, the CPU copies line
  by line (MVN) and serves interrupts every 4 lines.
- **Blitter driver.** Rectangle fills are one FILL, text one EXPAND_KEY per glyph from
  the 1 bpp font (clipped with the source offset and SRC_BIT), image blits one COPY or
  COPY_KEY, a terminal scroll one COPY. Lines and the checker pattern stay on the CPU.
  Every user waits for BUSY to drop before writing a register (the blitter reads them
  while it runs; START while BUSY is ignored); a blit is left running, so the CPU works
  meanwhile. Before the CPU reads memory the blitter wrote (a resize that copies the old
  bitmap, switching to the software paths) the kernel writes CACHE_FLUSH ($00:D80A): the
  65C816's cache does not see the blitter's writes. `make test` fails if emu816 reports
  any of these rules broken. The software paths stay, chosen at ws_start by SYS_REV
  (and `ws_config`).
- **Window manager.** In the same thread, fed by button changes, keys and wheel steps
  queued by the interrupt handlers (which only queue: no drawing in interrupt service).
  Live drag and live resize follow the pointer at the rate the compositor can repaint.
- **Menu bar** (`kernel/menu.s`) and **terminals** (`kernel/term.s`): kernel code; a
  terminal keeps its cells and its key queue in a bank of its own.

**Costs** (emu816, `wdemo bench`, 14.3 MHz; the blitter's own time is a model, see
emu/blitter.c):

| Operation | CPU (REV $07) | Blitter, polling BUSY | Blitter, sleeping on its interrupt |
| --- | --- | --- | --- |
| full repaint, 640x360, three windows | 151 ms | 15.7 ms (9.6x) | 17.8 ms |
| move step of a 302x187 window | 51.6 ms | 3.0 ms (17x) | 5.4 ms |
| drawing one 60-character UI-font line | 13.7 ms | 2.0 ms (6.9x) | 1.6 ms |
| repaint after that line | 2.4 ms | 0.12 ms (20x) | 0.12 ms |

Polling BUSY is the default: sleeping on the interrupt costs a task switch per blit and
only pays when another task has work meanwhile.

**On the board** (stage 1 code, CPU only) the same bench measured 434 ms, 176 ms, 24 ms
and 9 ms: about 2.3x the emulator's figures. The emulator counts one CPU cycle per bus
access; on the board every write goes through to SDRAM and the 8 bpp video fetch takes
bus time (see emu/README.md, "Memory timing"). Expect the same factor on the CPU paths.

## Version 0.13

- **The card** is sorted (see "The card" above): system programs in `/SYSTEM`, tests in
  `/SYSTEM/TESTS`, applications in `/BIN`; the shell searches `/BIN`, `/SYSTEM`,
  `/SYSTEM/TESTS`.
- **Desktop icons**: "SD card" (Files at the root) and "Atari", then what is in `/Desktop`
  (files and folders, opened by their type through `ui_open`; created if missing). A
  /Desktop icon can be dragged onto a Files window, a folder icon or the SD card; a file
  dragged from Files onto the desktop moves into /Desktop.
- **Programs menu** from `/SYSTEM/PROGRAMS` (no rebuild for new programs).
- **Single instance** (`task_single`, ABI.md): the Desktop never runs twice; About and
  Settings started again raise the open window.
- **Files** hides /SYSTEM (View > Show system files) and refuses to start its programs; Up
  button, "..", the full path; menus with shortcuts; Rename / New folder with `ui_ask`.
- **When a program cannot start**, whoever started it says why (an alert from `ui_launch` /
  `ui_spawnerr` in the Desktop and Files, a sentence in the shell): not enough memory, too
  many programs, not on the card, not a program. The menu bar shows the free memory
  ("4416K free  up 0:05"); About shows free / total.
- **Force quit...** (Horizon menu): the running programs; the one chosen is killed.
- **Restart... / Shut down...** (Horizon menu, with a confirmation; also `restart [full]`,
  `shutdown` in the shell and SYS_SYSREQ for programs): every other window gets WE_CLOSE
  (ws_closeall); a program may ask to save; one that stays open after its close request
  (idle, no dialog) cancels, and the Desktop says which; one that does not answer for 20 s:
  "Continue anyway?". Then SYS_RESTART (I/O op $1B), or SYS_SYNC (op $1C: every other
  program ended, every file closed, the card flushed) and a full-screen "It is now safe to
  switch off the Atari816" with a Restart button (a full restart). emu816 stubs both ops:
  SYNC closes its files; RESTART reloads HORIZON.SYS from the card and resets the CPU.
- **Keyboard**: F10 or Alt opens the menus (arrows, Enter, Esc, letters), Alt+letter a menu
  by its first letter; Alt+Tab cycles the windows; Alt+F4 and ctrl+W close the top one; in
  dialogs Tab / Shift+Tab move the focus through every control (a focused button: a dotted
  frame; Space or Enter activates it), Enter the default button, Esc Cancel.
- **Menus**: check marks and dimmed items (a state byte, `win_mstate`), shortcut texts after
  a TAB. Button and motion events carry the modifier keys (c = buttons | modifiers << 8).
  Pointer shapes for resizing a column or a row. `ui_ask` asks for one value.
- **Settings > Classic Atari** edits `/atari.ini` (memory, stereo, keyboard layout, arrow
  keys as joystick, scanlines, horizontal position, boot cartridge) and offers "Restart now".
- **Resources come back**: `leak 200` (test 17).
- **Kernel space**: `t_args` and `cl_names` moved to a second BSS past the video-state block
  ($01:F400, BSS2 in kernel.cfg); the image and BSS end at $01:E168 (3.7 KB left below
  $F000).

## Version 0.14

- **Menu bar**: the system menus (Horizon, Programs, and the kernel's Windows menu), a thin
  divider, the front program's name in bold (SYS_TNAME; ui_launch names what it starts),
  then its menus; with no program window in front only the system menus. Horizon: About
  Horizon, Settings..., Force quit..., Atari (F12), Restart..., Shut down... (Settings left
  the Programs menu). The Programs menu is read again from `/SYSTEM/PROGRAMS` whenever it
  opens (WE_MENUOPEN), so new programs appear without a restart.
- **Clock**: the kernel counts seconds from the value set (SYS_TGET / SYS_TSET); the board
  has no battery clock, so the Desktop and the shell keep the last time in
  `/SYSTEM/CLOCK` (when it is set, and before a restart or shut down) and load it at start
  as a provisional value. The bar shows "up H:MM" until the time is confirmed in this
  session, then "HH:MM"; a click on it opens "Date and time" (pre-filled; digits typed
  straight in, arrows or the wheel change the field, Tab moves, Enter confirms, Esc
  cancels). About shows the date. The shell: `date`, `date YYYY-MM-DD HH:MM[:SS]`. File
  dates are not stamped: the I/O processor's FatFs has no clock (FF_FS_NORTC, a fixed date).
- **Windows**: minimize and maximize buttons in the title bar (maximize only for resizable
  windows; dialogs have neither), a double click on the title maximizes / restores, the
  Windows menu lists every window (the front one checked, minimized ones in brackets),
  Alt+Tab brings minimized windows back too. Programs get WE_RESIZE on maximize and
  restore, and can move and resize their own windows (SYS_WGEOM).
- **The Atari icon**: a click opens the "Atari" panel: D1:-D4:, the executable and the
  cartridge loaded (classic_query), an Eject button for each, Eject all, Restart Atari
  (classic_boot) and Switch to Atari (F12) (0.18: also Attach disk..., Attach cartridge...,
  Run program..., and the icon's menu on a right click; a cartridge attached or ejected
  cold boots the Atari without showing it). An Atari file dropped on the icon from Files is
  mounted (a disk on the first free drive). The icon shows a green mark while something
  is loaded; Files' footer follows within 2 s.
- **Desktop icons**: one picture per program (Edit, Write, Sheet, Paint, BASIC, Calculator,
  Solitaire, Terminal, Files, Settings, About) and per document type, from
  `/SYSTEM/ICONS` (26 icons of 32 x 32, text art in `sdfiles/icons.txt`, converted by
  `tools/mkicons.py`, which also writes `user/icons.inc`); shortcuts (above) with a small
  arrow. Icons can be dragged anywhere: they snap to the grid (8 columns x 5 rows from the
  top right), and the places are kept in `/SYSTEM/LAYOUT` ("column row name" lines; the SD
  card and Atari icons as `:SD`, `:ATARI`). A right click: Open, Delete (with a
  confirmation; a shortcut or a file in /Desktop) on an icon, Tidy up on the desktop.
- **Kernel and library for programs**: menus up to 2045 bytes per window (a bank of the
  window system's own holds the menus and the dropped strings, which frees 6 KB of the
  kernel's bank), win_draw WD_EXPAND (a 1 bpp image in an ink and a paper or transparent,
  through the blitter's EXPAND; the CPU without it) and WD_KSBLIT (a keyed blit with a
  source stride), SYS_WGEOM, SYS_TNAME, WE_DROP's modifiers, the date routines (ui_clk*,
  `user/uidate.s`), shortcuts (ui_lnkread, ui_mklink), program and file icons (ui_prog,
  ui_ficon). See ABI.md and ui.inc.

## Version 0.22 (the PC link, step 2: the internet)

The I/O processor and the gateway carry TCP connections (channel 4, Net) and URL fetches
(channel 5, Fetch: HTTP, HTTPS, FTP); Horizon gives them to programs as paths (ABI.md, "The
internet"; Docs/04-pc-link.md, "Channels 4 and 5"). The kernel passes a path starting with
`letters://` on unchanged, has 4 more handles (4-7) for streams, turns the firmware's $E4 into
WE_NET (17) for the program's first window, and puts an HTTP status in X when open or stat
fails with $CF. It also fixes input_poll for a program attached to a Terminal window: it
looked only at the keyboard holder's queue, never at the window's, so ctrl-C during `cp`, `mv`
(0.21) and `get` in the Terminal window was only seen at the next prompt (the text shell was
not affected; found on the board). Bank $01 1,852 bytes left, k2 711, k3 2,386. New errors
E_NOSVC ... E_NET ($CA-$D3) and E_NSTREAM in horizon.inc.

- **The shell:** `get URL [to]` (a download with its progress line and ctrl-C), URLs passed
  on unchanged everywhere, a copy into a folder named from the URL (no query), a sentence for
  every new error ("HTTP error 404" with the status), "denied" ($47) and "not possible here"
  ($C2). The command line holds 128 characters (LINEMAX; 80 before), but the line editor
  still stops at the screen's width - 3 (75 in the text shell, 73 in the Terminal): it does
  not wrap, so a longer URL can only come through a program's argument (the shell's own,
  `SH get ...`) for now.
- **The controls library:** `uicopy.s` reads a file until a short read, never only to its
  STAT size (a URL's size may be unknown: 0); `ui_cpblk` (the piece, 16 KB by default; the
  Downloader and `get` use 4 KB: a URL's read waits until the piece is full); `ui_cpx` (X of a
  failed STAT or OPEN of the source: the HTTP status); `ui_isurl`, `ui_urlname` (the name a
  copy of a path or URL gets). `uicpwin.s`: a size of 0 shows "123 KB", no percent, no bar.
- **The Downloader** (`user/download.s`) and **the BBS terminal** (`user/bbs.s`): see "The
  internet" above. The BBS terminal's 8x8 ATASCII font is Horizon's own: the graphics
  characters are drawn in `user/atascii.txt`, the letters and signs come from the console font
  (`tools/mkatascii.py` makes `user/atascii.inc`); no Atari ROM data. ASCII mode draws the
  console font in 7-pixel cells (its eighth column is always blank) so 80 columns fit.
- **emu816:** `--net` (tcp:// as real loopback sockets), `--net-root DIR` (URLs served from
  `DIR/host/path`, 404 when missing), `--net-delay` (emu/README.md).
- Pictures: About shows 0.22 (desk3, desk7, desk1413, kmenu2, system5, system6). The
  programs linked with the controls library changed, so the Desktop's status line ("NNNNK
  free") catches a program loading or a copy's bank at a slightly different moment in a few
  early shots (desk1, desk151-153, system12-13, files1, files5-7, classic3; only that text
  differs, checked against a run of the 0.21 programs on the same kernel); where REV $08-$0A
  or $07 now differ from the default, `files-rev10.md5` and `classic-rev7.md5` (Makefile
  REV10, REV7IF).
- Tests: "Build, run, test", 27.

## Version 0.21 (long copies: progress and cancel)

A long copy no longer blocks without a word. The kernel did not change (bank $01 2,109 bytes
left, k2 711, k3 2,386: as in 0.20). The I/O processor firmware of this round keeps sending
key and mouse events while it serves a long request (a large card read or write, a request
waiting for the PC, a developer upload); before, the keyboard and the pointer froze until it
was done. The PC gateway writes a new file (mode 2) under a temporary name and gives it its
name at CLOSE, so a copy that is cut off leaves nothing.

- **The controls library, `uicopy.s`:** files are copied in pieces of 16 KB (0.20: 32 KB).
  `ui_cpcb` is called when a file starts (ui_cpk = 0) and after every piece, and may return C
  set to cancel: both files are closed, the partial file is deleted (on the card or on /PC:),
  and ui_cptree / ui_mvtree return C set, A = ECANCELED (10, a new error code of the user side;
  the kernel never returns it). ui_mvtree never deletes the source after an error or a cancel.
- **The progress window, `uicpwin.s`** (new): `ui_cpwin` (A = 0 copy, 1 move) before
  ui_cptree / ui_mvtree, `ui_cpdone` after. A modal window "Copying" / "Moving" opens when the
  copy still runs 0.5 s later: the name, "123 of 1,500 KB (8%)", a bar, Cancel (Esc, the close
  box). Between pieces it looks at the events without waiting and redraws only what changed.
  See ui.inc.
- **Files:** every copy (Paste) and move (a drag, a drop) uses it; the footer's "Copying 64
  of 300 K" is gone. A cancel says "Copy cancelled" (or "Move cancelled") on the footer, with
  no beep; other errors as before ("The PC link was lost", ...).
- **Desktop:** drops that copy or move (onto the PC icon, the SD card icon, a folder) use it;
  a cancel is silent (no beep).
- **The shell:** ctrl-C stops `cp` and `mv` ("cp: NAME: cancelled"); other keys typed meanwhile
  are kept for the next prompt (ulib `key_keep`, up to 80 characters, read first by `read_char`).
- **emu816:** `--card-kbps R:W` and `--pc-kbps R:W` (slow transfers: the board's speeds are
  about 170:100 and 100:55), key and mouse events during a request (every key change in order,
  a quick click never lost), the gateway's temporary files for mode 2 (emu/README.md).
- Tests: "Build, run, test", 26.

## Version 0.20 (the PC link, step 1)

The I/O processor firmware shows one folder of the PC as a second volume, `/PC:` (see "The PC
volume" above and ABI.md, "The PC volume"); the kernel did not change (bank $01 2,109 bytes
left, k2 711, k3 2,386: as in 0.19). New I/O results: $87 no PC link, $88 PC link lost, $89 not
the same volume (Horizon errors $C7, $C8, $C9).

- **The controls library:** `uicopy.s` (ui_cptree: a file or a whole folder copied, 32 KB at a
  time, a callback for the progress; ui_rmtree: a file or a folder and everything in it
  deleted; ui_mvtree: SYS_RENAME, and on $C9 ui_cptree then ui_rmtree). `ui_clkpc` (uidate.s):
  STAT `/PC:` answers with the PC's current time; that sets the clock (CLK_SET) and
  /SYSTEM/CLOCK. `ui_clkload` asks it first when the clock is not set.
- **Desktop:** the third fixed icon (kind K_PC) while STAT `/PC:` works (in every rescan,
  every 5 s); the number of fixed icons is now a variable (`nfix`). When it comes, ui_clkpc.
  Drops: onto the PC icon copied into /PC:, onto the SD card icon from the PC copied; other
  moves through ui_mvtree. `sdfiles/icons.txt` has the PC icon (ICO_PC, the last one).
- **Files:** a move (a drag) through ui_mvtree; Paste through ui_cptree, so folders are
  copied too (before 0.20 they were refused); the messages for $C7-$C9.
- **The shell:** `cp` through ui_cptree (a folder too), `mv` through ui_mvtree; the messages
  "no PC link", "the PC link was lost", "not on the same volume".
- **emu816:** `--pc-folder DIR`, `--pc-time`, `--pc-drop-at`, `--pc-back-at` (emu/README.md).
- Tests: "Build, run, test", 25.

## Version 0.19 (sheets)

Cheaper queued drawing. In 0.18 a `draw_list` record cost the kernel about 1,400 CPU cycles,
most of it checking that the record's source lies in the program's own memory. **Sheets**
(ABI.md, "Sheets (0.19)") move that check to the start: a program registers a rectangle of its
memory holding art once (`sheet_new`, $A1: address, stride, width, height; the rules of every
address Ali reads), and the 16-byte records of `sheet_draw` ($A3) name a sheet and a rectangle
in it: the kernel compares small numbers with the sheet's size and finds the source in a table
of the sheet's rows. `sheet_free` ($A2); a sheet also goes when its bank is freed and when the
program ends, and stops the program's running list then, as draw_list's do.

- **The fast path** (`kernel/k3.s`, `sh_fast`): the window drawn on the screen directly (or in
  full-screen mode), a copy or keyed copy from the sheet and op of the record before, wholly
  inside the content. Then the record's destination comes from a table of the target's rows
  (made again only when the window moved), and only the bytes of Ali's 24-byte record that
  change are written (FLAGS, RFLAGS and the reserved bytes stay 0; the records an earlier
  list gave flags are cleared first). **305 CPU cycles a record** (emu816 trace, the loop from
  one record to the next; 318 with the calls' share: below). Other records (fills, SH_VBL,
  records cut at the edges, a covered window's bitmap) take the full path, `sh_one`, which
  shares draw_list's clipping and record making: about 1,100 cycles.
- **Revisions**: as draw_list (one command list on REV $09+, the records started one by one on
  REV $08, the CPU on REV $07); GTEST's new picture is the same on all of them.
- **draw_list itself** got cheaper too, without changing what it does: the records now go to
  a fixed place, $7F:8400 (below), written with long,X stores; a record's damage rectangle is
  only kept when the target is the window's bitmap (it is not used otherwise); the target's
  overlap test (`win_visible`) runs once a call instead of twice (it is only needed for a
  bitmap, after `win_target` asked it already); the pending-repaint case finds the bitmap's
  row address with shifts instead of a multiplication. 1,284 cycles a record (was 1,407), a
  call 272 us (was 303).
- **Measurement** (emulator; `gtest m`, 100 keyed 16 x 16 blits a frame, 60 frames; new in
  `gtest m`: the CPU's part exactly, 500 calls of 100 1 x 1 records each and 2,000 calls of
  one record, each call followed by a 0.5 ms loop that is measured alone and taken off;
  `uptime` advances with the 10 ms tick, so the per-frame figures, as in 0.18, are only
  rough for calls of a few ms):

  | 100 records a frame | REV $0B / $09 | REV $08 | REV $07 (the CPU draws) |
  | --- | --- | --- | --- |
  | 100 win_draw calls | 26.6 ms | 26.4 ms | 96 ms |
  | one draw_list, 0.18 | 14.4 ms | 21.7 ms | 80 ms |
  | one draw_list, 0.19 | 13.8 ms | 16.7 ms | 79 ms |
  | one sheet_draw | 4.0 ms | 13.6 ms | 71 ms |

  | The CPU's part exactly, a call | draw_list 0.18 | draw_list 0.19 | sheet_draw |
  | --- | --- | --- | --- |
  | 100 records, REV $0B / $09 | 10,016 us | 9,136 us | 2,460 us |
  | 1 record, REV $0B / $09 | 303 us | 272 us | 265 us |
  | a record (the difference / 99) | 98.1 us: 1,407 cycles | 89.5 us: 1,284 cycles | 22.2 us: 318 cycles |
  | 100 records, REV $08 (started one by one) | 12,820 us | 11,938 us | 5,280 us |
  | 100 records, REV $07 (1 x 1: the CPU's drawing is small) | 12,746 us | 11,862 us | 5,194 us |

  (A call's own cost, about 3,800 cycles, is the syscall, the window and target checks, the
  list's start and its end-of-list interrupt; `gtest m4`, the bitmap target: sheet_draw's full
  path, about 1,100 cycles a record in the trace.)
- **Converted** (REV $09+ paths; the pictures did not change):

  | | before | after |
  | --- | --- | --- |
  | Quabricks 1.2, `quabrick -m` (tests/quabrick.keys, 695 frames of play) | 290 us of CPU a frame, 2.62 syscalls | 257 us, 2.62 syscalls |
  | the same, all CPU (every task and the kernel: the emu816 trace less the idle loop's WAI, 9-16 s) | 1,311 us a frame | 1,290 us a frame |
  | Deep Dive (sdk/examples/deepdive, its test.script) | 1.83 ms of CPU a frame (833 ms, 456 frames) | 1.73 ms (792 ms, 457 frames) |
  | BASIC, full screen: 20 `PUT` of 16 x 16 and VSYNC a frame (all CPU, trace, 7-13 s) | 10.1 ms a frame, 2 syscalls | 8.8 ms, 2 syscalls |
  | BASIC, 2,400 `PUT` without VSYNC (lists sent when full) | 446 us a PUT | 375 us |

  Quabricks sends a frame that only blits its tiles and erow / srow and fills as one
  `sheet_draw` (its records are made as before and turned into sheet records in place;
  frames with moves or the big font's expands stay one `draw_list`); its frames draw only a
  few cells, so little changes. Deep Dive sends its tiles as sheet records (one `sheet_draw`
  a frame; a frame that also writes the panel's letters, which are 1 bpp, one `draw_list` as
  before). BASIC makes each picture bank a sheet (64 x 1024: 16 pictures) and sends PUT, FRECT
  and GCLS in full screen as sheet records; COPY stays a draw_list record (a record of the
  other kind sends the list first, as a full list does).
- **Kernel space: a third code segment.** Sheets live in `kernel/k3.s`, its own assembly unit
  run from $7F:E000-$7F:EFFF: the console framebuffer's last bank ($7C-$7F, kernel owned)
  holds 60 cell rows up to $7F:83FF and the pointer images from $7F:F000; the space between
  was unused. In the file it follows k2.s; boot copies it there, after k2.s. Bank $01 pays 71
  bytes in all (the copy at boot, the syscall entries, 42 bytes of variables of k2.s and k3.s).
  Bank $01 reaches it with JSL (`sys_k3`, the syscalls $A1-$A3); it uses
  k2list.s through the f2_* wrappers. The same free part holds the command lists (SL_LIST,
  $7F:8400-$8FFF, 128 x 24: draw_list's and sheet_draw's; the window system's bank no longer
  holds them), the fast path's table of the target's rows ($9000-$9FFF, 1024 rows) and the
  sheets' rows ($A000-$DFFF, 4096 rows). The sheet table (32 sheets) is in k2's bank 0
  variables. After 0.19 (`tools/kspace.py`): bank $01 2,256 bytes left below $F000 (2,327
  before), the second segment 711 of 7,680 bytes left (746), its bank 0 variables 928 of
  3,328 (1,376), the third segment 2,386 of 4,096 left; the file 47,105 bytes (loader limit
  65,280).
- **Tests**: GTEST's part 8 (`tests/gtest*.txt`): refused sheets (sizes; the kernel's bank, the
  framebuffer, a bank nobody owns, past the window, out of an own bank: EFAULT), refused
  records (past the sheet, overflowing, no such sheet, op 3, records outside the window, the
  area limit), another program's sheet, the table full (32 sheets, 4096 rows), a child's sheets
  freed at its exit and at its kill, a bank freed (its sheet gone, the running list stopped),
  rows moved by a free; and a second picture (`gtest2`, the same on REV $0B, $0A, $09, $08,
  $07): fast records, clipped ones, fills, a 32 x 32 one, a bitmap target, a sheet whose rows
  moved. Re-frozen: `basic2s3`-`8` and `basic2s10` (REV $0B). They differ by timing only:
  draw_list is faster, so DRIFT.BAS's `RANDOMIZE` (seeded by the clock) gets another seed
  (other ripples and river), SCROLLER.BAS has scrolled further at the shot, and Esc breaks in
  another line ("Break in 300", was 270); 0.18's BASIC.PRG on the 0.19 kernel gives exactly
  the new pictures, and 0.18's BASIC on 0.18's kernel the old ones. Also `files8` of
  `files-rev7.md5` (REV $07, 26.6 s): Write still painting its first rows (the CPU draws them)
  when the shot is taken, a little further on than before (0.18's card gives the old one).
- **Not done**: the icon dragged on the desktop or in Files as a hardware sprite. A window's
  sprites show only while it has the focus and nothing covers it, so a drag across windows
  would need a sprite of the window manager's own, like the pointer; the 16 sprites are all
  programs' to take (spr_alloc), and 32 x 32 icons at 8 bpp need two 16 x 32 sprites (or a 4
  bpp image in one palette bank, which the icons' colours do not fit). Left for a later round.

### 0.19: file dates, the boot cartridge, the board's speed

- **File dates** (with the I/O processor firmware of bring-up step 20): `time_set` also gives
  the time to the I/O processor (op $1D SYS_TIME), which counts on from it and stamps the files
  it writes; so files get the date and time Horizon knows (the clock the user set, or the last
  one saved in /SYSTEM/CLOCK counting from start), and the firmware's build date before a time
  was given in this session (an older firmware keeps its fixed date: it answers $82). `ls` /
  `dir` print each entry's date and time (`YYYY-MM-DD HH:MM`, one STAT each; the name column is
  18 characters narrower); Files shows "Modified YYYY-MM-DD HH:MM" for the selected entry on its
  footer after what is mounted, when it fits whole (the 2 s look at the mounts keeps it).
- **The boot cartridge:** a cartridge the I/O processor loaded by itself at power-on
  (`boot=ash` in /atari.ini) is asked for once, by the first task's loader (op $1E
  CLASSIC_STATE): its banks are reserved as classic_mount reserves them, and classic_query
  reports it (Files' footer: Cart:). 147 bytes of bank $01 (2,109 left).
- **The emulator now runs at the board's speed** (emu/README.md, "Memory timing": cache
  misses, SDRAM write stalls, Marga's fetch, the cache sweeps, Ali's measured rates). The
  sessions of `make test` were timed for the ideal model and check what is drawn, not how fast,
  so they run with `--ideal-timing` (the Makefile's `CARDDATE`, which also gives `--card-date`:
  the date STAT reports for the files a run did not write). Board against emu816 now (BASIC
  sieve, `basic -t` in the Terminal; step 20 firmware): board 89.2 s, emu816 87.9 s (-1.5 %),
  the ideal model 45.9 s. With the step 19 firmware the board took 103.4 s: its I/O processor
  polled the mailbox from SDRAM and took 10-20 % of the 65C816's memory time.
- **Games at the board's speed** (emu816's default model): Quabricks' scripted game (`quabrick
  -m`) 688 frames, 0 missed, 1.63 ms of CPU a frame (0.26 ms ideal); Deep Dive's test 452
  frames, 0 missed, 3.3 ms a frame (1.7 ideal); BASIC runs at about half the ideal model's
  speed (the sieve: 45.9 -> 87.9 s), so DRIFT.BAS's 5.5 ms a frame becomes about 11 ms, inside
  the 16.7 ms frame (estimated, not measured frame by frame).
- Pictures re-frozen for these: every Desktop session picture with a Files window whose footer
  now shows the selected entry's date (desk, system, wins, desk14, desk15, desk18, kmenu, files,
  classic, and their REV $07 sets), `ls` listings (screen1, browse7, desk4, desk6), and
  tests/shell.txt (the `ls` lines and the paging they shift).

## BASIC 2.0 (on Horizon 0.18)

BASIC (BASIC.md) gets the games hardware, in the plain style of Atari BASIC: a game of a page
of BASIC at 60 frames a second, because the hardware does the work.

- **Pictures** (SHAPE from text art, GET from the drawing, PUT, COPY), **sprites** (SPRITE n,
  x, y, picture, flags; HIT for collisions by boxes), **full screen** (`SCREEN 1` 320 x 180,
  `SCREEN 2` 640 x 360, a drawing area up to 2048 x 960 that wraps: SCROLL; a fixed panel:
  PANEL; colour bands: RASTER), **samples** (WAVE makes a sine, square, triangle, saw or noise
  with a decay, or loads a .WAV or raw file; PLAY with a note's name or semitones, volume,
  pan, voice; NOTE), FRAME. VSYNC sends a frame's changes together (one `spr_set`, the scroll
  set, the raster table, the blitter's list starting in the vertical blank). STICK(0) and
  STRIG(0) follow the arrow keys and Space too. Errors: "Not available on this machine"
  (REV $0A has no sprites, $09 no Lau, $08 and $07 no raster events either), "Full screen
  only", "In use by another program", "Undefined picture", "Undefined sample". END, errors,
  Break and STOP hide the sprites, stop the voices and leave the full screen; CONT brings
  them back; RUN and NEW free everything.
- **Examples** in `/programs`: SPRITES.BAS (bouncing balls with sounds), DRIFT.BAS (a
  small complete game: about 5.5 ms of BASIC a frame in the emulator, none of 1200 frames
  missed), SCROLLER.BAS (full screen, panel, raster sky, blitter copies), MUSIC.BAS (a tune
  with note names). TESTS.BAS has a 2.0 group.
- **Space.** BASIC.PRG's text, data and BSS end at $F2F7 of its code bank (3.3 KB left): the
  control stack (6 KB), the line editor's history (2 KB) and the new tables (the row table of
  up to 1024 rows, the draw list, the sprite entries, the full-screen palette) moved to the
  window bank, below the stack's floor (STKMIN $4100). The file went over the loader's 64 KB
  (71 KB: a third of it relocation entries that add 0, since programs are linked and loaded
  at $0100): the Makefile runs `tools/o65strip.py` on it (52 KB).
- **Kernel** (small): **win_front** ($A0, ABI.md): a program brings its own window back to the
  front with the focus (BASIC's SCREEN, CONT and the end of INPUT: sprites and a full screen
  show only while their window has the focus). A fix: `fs_raster` with count 0 (the table
  off) returned EINVAL. 24 bytes of bank $01, 3 of the second segment.

## Version 0.18 (the games round)

The new hardware (Marga's sprites, fine scrolling and raster events, Ali's command lists, Lau)
for programs, safely and cheaply for the CPU. Marga, Ali and Lau read and write RAM by
themselves, past FREDDIE II, so every address a program hands over is checked against its own
memory, and everything a program holds goes back when it ends or frees the memory involved.
ABI.md, "The games round", has the rules; `user/gtest.s` tests them.

- **Kernel space: a second code segment.** Bank $01 was full (3.6 KB left). The new calls live
  in `kernel/k2.s` and its modules, a separate assembly unit that runs from bank 0 $E100-$FEFF
  (write-protected by WP_VEC like the vectors, readable only by the kernel), with its larger
  tables in bank 0 $A300-$AFFF. It is linked into the same HORIZON.SYS after the bank $01
  image (the I/O processor loads the file to $01:0000 as before; boot copies the segment to
  bank 0 before it clears the BSS). Bank $01 reaches it with JSL; it reaches bank $01 only
  through the JSL wrappers of `kernel/kfar.s` (a JSR across banks is an assembly error there).
  `tools/kspace.py` prints the space of each part at every build and fails the build when the
  file outgrows the loader ($FF00 bytes) or the bank $01 BSS reaches $F000.
- **Frame sync**: SYS_VSYNC waits for Marga's VBLANK interrupt (REV $09+; the timer fallback
  stays below) and returns NV_FRAME, so missed frames show; SYS_FRAME reads it; WE_VBL
  (SYS_WINVBL) for event-loop programs.
- **Palette entries**: SYS_PALALLOC / SYS_PALSET; an entry a program holds shows its colour
  while one of its windows has the focus, the system's otherwise, and returns at its end
  (Quabricks' force-quit no longer leaves 75 entries changed; Solitaire claims the entries its
  card backs use, so no other program gets them).
- **Sprites** (SYS_SPRALLOC ... SYS_SPRSHOW), **full-screen mode** (SYS_FSENTER, SYS_FSLEAVE,
  SYS_FSSCROLL, SYS_FSRASTER), **draw lists** (SYS_DRAWLIST, SYS_LISTWAIT): ABI.md.
- **Sound volume** (setting 4, Settings' "Sound volume", `sound=` in /SYSTEM/CONFIG): Lau's
  master volume, separate from the alert volume.
- **Cartridges and memory** (owner's report from the board): the I/O processor loads a
  cartridge into its SDRAM from $400000, which the 65C816 sees as banks $70 and up, and the
  kernel took its runs of banks (the screen, window bitmaps) from the top below $7C. So
  attaching a cartridge wrote it over a window's bitmap (a garbage band on the desktop) and the
  desktop then drew into the cartridge (a black screen on the Atari, until it was detached).
  Now the kernel takes its runs below $70 first, and classic_mount reserves a cartridge's banks
  (size / 64 KB, at most 12) until it is ejected (ENOMEM if one is in use). classic_boot with
  A = CB_STAY cold boots without showing the Atari: the Desktop attaches and ejects cartridges
  as a power cycle.
- **Attaching a cartridge is a power cycle** (owner's report: Attach cartridge... from the
  Atari icon's menu only mounted it; the Atari then showed a black screen, and Restart Atari
  did not help while an executable was mounted, as the firmware boots an executable in
  preference to a cartridge). As on a real machine:
  - attaching a cartridge (the icon's menu or the panel's Attach cartridge..., a drop on the
    icon, Files' Load into Atari: `ui_atload`) ejects the executable (the disks stay), mounts
    the cartridge and cold boots the classic machine with classic_boot CB_STAY: the desktop
    stays, the Atari is not shown;
  - ejecting the cartridge (its Eject button or menu line, Eject all with a cartridge in)
    cold boots it the same way afterwards;
  - Restart Atari with a cartridge in first ejects the executable, so the firmware does a
    plain cold boot with the cartridge (then shows the Atari, as before);
  - attaching a disk or an executable only mounts it; Run program... still starts the
    program and shows the Atari ("start this, and only this", now with ui_open's alerts);
  - no room for the cartridge's banks (ENOMEM): "Not enough free memory for the cartridge:
    close a program and try again." (Files: on its footer).
- **The Atari panel** (owner's request: attach from the panel, open from an earlier session):
  Attach disk..., Attach cartridge..., Run program... buttons above Eject all, Restart Atari,
  Switch to Atari (two rows of three, the panel 376 x 218); a right click or the menu key in
  it opens the icon's menu (without Open panel). They do exactly what the icon's menu does.
- **Measurement** (emulator, `gtest m`: 100 keyed 16x16 blits a frame for 60 frames, the time
  in the drawing calls; the board is about 2x slower on CPU work):

  | | REV $0B / $09 | REV $08 | REV $07 (the CPU draws) |
  | --- | --- | --- | --- |
  | 100 win_draw calls a frame | 100 syscalls, 26.6 ms | 26.4 ms | 102 ms |
  | one draw_list a frame | 1 syscall, 14.4 ms | 21.7 ms | 80 ms |

  A list's time is the kernel checking and clipping each record (about 2,000 cycles; (0.19)
  measured exactly, 1,400: Version 0.19); Ali's own
  blitting (about 2.3 ms) then runs while the program goes on. Without command lists (REV
  $08) the kernel starts the records one by one; an LS_VBL record then waits in the call.
  Quabricks 1.1: 290 us of CPU and 2.6 syscalls a frame (1.0: 650 us, 4.3).
- **Fix**: a program printing on the text console while it runs the window system (from the
  text shell) moved NV_BASE when the console scrolled, so the desktop showed the console's
  memory; the console no longer touches NV_BASE while the desktop is shown.

## Version 0.17

- **Samples** (kernel, `kernel/sys17.s`; ABI.md, "Samples"): Lau, the 8-voice sample player of
  REV $0A, for every program: SYS_SPLAY ($68) plays signed 8- or 16-bit PCM from the
  program's own memory on a voice it names or the first free one (pitch in 2.14 steps of
  the 48 kHz output, left and right volume, a loop), SYS_SSTOP ($69) stops one or all of
  its voices, SYS_SSTAT ($6A) says which play, SYS_SSET ($6B) changes pitch and volumes
  while a voice plays. Because Lau reads RAM past FREDDIE II's protection, the kernel checks
  that the whole sample lies in the caller's window, code bank or allocated banks (a range
  may run across consecutive banks of its own), keeps the owner of each voice (a program
  cannot stop, change or take another's), and stops a program's voices when it ends (exit,
  kill, crash: before its banks are freed) and when it frees a bank a voice reads. Every
  voice stops when the classic machine is shown. Lau's master volume follows the volume
  setting (Settings' alert volume x 17). Without Lau (REV < $0A) the calls return the new
  error ENODEV (9) and programs use POKEY 2; the alert chime stays on POKEY 2.
- **Quabricks** (`/BIN/QUABRICK.PRG`, in the Programs menu): a falling-block puzzle game in
  a window, after the owner's SDL2 Quabricks: Marathon and Time Attack, a next queue of
  five, hold, a ghost outline, a fair bag of seven, turns both ways with wall kicks, a lock
  delay (30 frames, restarted by up to 15 moves), spins, back-to-back Quads and spins,
  combos, line-clear flash and a hard-drop jolt, a title, a setup screen, pause, the
  game-over sweep, per-mode high scores with name entry (`/BIN/QUABRICK.DAT`), How to play,
  menus and a right-click menu. Samples on Lau (`/BIN/QUABRICK.SFX`, 42 KB of 16 kHz 8-bit
  sound made at build time by `tools/mkqbsfx.py`), POKEY 2 without Lau or without the file.
  It is frame-synchronous: in play it waits for the vertical blank, takes the queued events
  without waiting, runs one step of the rules and draws only the cells and numbers that
  changed (a line clear moves the rows with window copies); menus wait for events. Its own
  colours are 75 palette entries no desktop icon uses (76-113, 136-175), set at its start
  and given back (the system cube) when it closes (1.1: taken with pal_alloc, below).
  Emulated, in play: 0.66 ms of CPU and 4.3 syscalls a frame on average, no frame missed
  (`quabrick -m`; 1.1: below).
- **Quabricks, the details.**
  - Keys: Left / Right move (auto shift by the game from the key events: first repeat
    after 10 frames, then every 2), Down soft drop (a row every 4 frames; on the floor it
    locks), Up or Space hard drop, Z / X turn left / right, C or Shift hold, Enter (or P)
    pause and resume, Esc pause (in the pause: back to the title), F2 a new game. Menus:
    Up / Down the mode, Left / Right the level, Enter, Esc. Joystick 1: the stick moves and
    soft-drops, up hard-drops, the trigger turns clockwise. The game pauses when its window
    loses the focus (another window, a menu of another program, minimize).
  - Menus: Game (New game F2, Pause Enter, High scores, Sound (checked), Quit), Help (How
    to play, About Quabricks...); a right click: Pause / Resume, New game, High scores,
    Sound, Quit.
  - Rules: a well of 10 x 20, the pieces enter at the top, a next queue of five, a bag of
    seven (each piece once per seven), turns with kicks left, right and up (two left / right
    more for the long piece), a lock delay of 30 frames restarted by up to 15 moves or turns
    on the floor (and again by every new lowest row), gravity 60 - 4 (level - 1) frames a
    row (at least 4), a level every 10 lines, starting level 1-15. A piece locking above
    the top, or one that cannot enter, ends the game. Time Attack: 60 s; 1 / 2 / 3 / 4
    lines add 2 / 4 / 6 / 10 s. (1.1: the speed by level and starting levels 1-20, below.)
  - Points (times the level; the SDL2 game's table, extended): 1 / 2 / 3 lines 100 / 300 /
    500, a Quad (4 lines) 800; a spin (the T turned last, three corners of its box taken)
    400 / 800 / 1200 / 1600 for 0-3 lines; a mini spin (turned into a place it cannot leave,
    without three corners) 100 / 200 for 0 / 1 line; back-to-back (a Quad or a spin with
    lines after another one, nothing but non-clearing pieces between): x 1.5; a combo (each
    further piece in a row that clears lines) + 50 x combo x level; soft drop 1, hard drop 2
    a row.
  - Files: `/BIN/QUABRICK.DAT` (188 bytes: "QBK1", sound, mode, level, then 2 x 5 entries of
    name, score, level, lines; see qb_file.s), written when a record or a setting changes;
    the game runs without it and on a card it cannot write. `/BIN/QUABRICK.SFX` the samples.
  - Arguments: `-t` the self test, `-s N` a fixed seed, `-q LIST` the first pieces, `-m`
    the measurement printed at each game's end.
  - Sizes: QUABRICK.PRG 53.9 KB on the card (21.4 KB of code with the controls library,
    23.4 KB of art and tables, 10.5 KB of variables; 55 KB of the code bank in use), one
    bank for the samples (42.9 KB file: 15 effects, 2.67 s of 16 kHz 8-bit sound).
  - The well is drawn with one blit of a pre-made tile per changed cell; a line clear moves
    the rows above with window copies and blits whole empty rows at once; the hard drop's
    jolt moves only the rows with blocks; the flash and the pause dim change palette
    entries (right after the vertical blank). (1.1: a frame's blits are one draw list, below.)
- **Quabricks 1.1** (with 0.18; the About box says 1.1):
  - Speed: the owner played level 55 of 1.0 comfortably (its gravity stopped at 4 frames a
    row at level 15, nothing got harder after). Now, a level every 10 lines as before:

    | Level | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 |
    | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
    | Frames a row | 60 | 48 | 38 | 30 | 24 | 19 | 15 | 12 | 10 | 8 | 6 | 5 | 4 | 3 | 2 | 1 |

    | Level | 17 | 18 | 19 | 20 | 21 and up |
    | --- | --- | --- | --- | --- | --- |
    | Rows a frame | 2 | 3 | 5 | 10 | 20 (at once to the floor) |

    About x 0.8 a level from a row a second at level 1 (as comfortable as before) down to a
    row a frame at 16; rows that fall in one frame give no soft-drop points. The lock delay
    (frames on the floor before a piece locks; up to 15 moves or turns there restart it, a
    new lowest row gives them back):

    | Level | 1-20 | 21 | 22 | 23 | 24 | 25 | 26 | 27 | 28 | 29 | 30 and up |
    | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
    | Lock delay | 30 | 28 | 26 | 24 | 22 | 20 | 18 | 16 | 14 | 12 | 10 |

    So from level 21 (200 lines) a piece lands at once and can only slide, and from level 30
    it has a sixth of a second there: the game ends for anyone. The setup offers starting
    levels 1-20 (20 pips); How to play gives the speed in two lines; the self test plays
    every level (`tests/quabrick-t.txt`).
  - Colours: the art is made in local colours 1 .. 75 (`tools/mkqbart.py`); at its start the
    game takes 75 palette entries with `pal_alloc(1, $FFFF)`, one at a time, so the kernel
    gives the first free ones in its order (76-113, 136-175, then from 16 up) whatever
    other programs hold (Solitaire holds 79: the game then gets 76-78, 80-113, 136-...),
    translates its tiles and logo in place (cmap) and the colours of its fills, text and
    big font in its drawing primitives, and sets its colours with one `pal_set` per run of
    consecutive entries (the pause's dimming and the restore too: 2-4 calls instead of 75).
    Its entries show its colours while its window has the focus (it pauses otherwise); it
    gives them back at its end (`pal_alloc 0`; the kernel does it too at exit and kill).
    The pictures are the same with 79 and 140-141 already taken.
  - Blocks with rounded corners, as in the owner's game: the three pixels of each corner
    (a radius of 2 pixels, 4 on the screen) show what lies behind the block: the well's tiles
    are made over its empty cell (the grid line on the top and left), the hold and next
    tiles over the panel, the title's grey blocks are keyed; the ghost's outline follows
    the same shape. The logo's little bricks keep square corners (rounded, its letters read
    as beads).
  - Draw lists: with Ali's command lists (REV $09+, found by asking for WE_VBL) a frame's
    drawing (the cells, the rows moving down after a clear with LS_MOVE, whole empty rows,
    the next queue moving up, the numbers in the big font, the jolt, the sweep) is one
    `draw_list` whose first record waits for the vertical blank (LS_VBL): tear-free, shown
    one frame later than before. The big font is composed into an arena that is not
    written again until the list has run; text (the UI font is not a list op) is drawn
    right after the next vsync. Whole screens (title, menus, the end) are drawn at once as
    before. Before REV $09 the kernel would unroll the list (one blit at a time, or the
    CPU) for more CPU time than the win_draw calls, so the game keeps those there.
    Measured with `quabrick -m` on the scripted session (its Marathon game; 1.1 also prints
    the most syscalls in one frame and counts missed frames only between two frames of
    play, not across a pause):

    | Emulated | CPU a frame | Syscalls a frame | Most in a frame | Frames missed |
    | --- | --- | --- | --- | --- |
    | 1.0, REV $0B | 650 us | 4.33 | 82 | 0 |
    | 1.1, REV $0B | 290 us | 2.62 | 11 | 0 |
    | 1.0 / 1.1, REV $09 | 671 / 304 us | 4.88 / 3.19 | 83 / 12 | 0 |
    | 1.0 / 1.1, REV $08 | 685 / 684 us | 4.89 / 4.68 | 83 / 63 | 0 |
    | 1.0 / 1.1, REV $07 | 2985 / 2996 us | 5.23 / 5.00 | 83 / 63 | 0 |

    (The board runs the CPU about half as fast. REV $09 has no Lau: the effects' POKEY 2
    writes are syscalls too.)
  - No sprites for the piece and its ghost: measured, they would not pay. A frame that only
    moves the piece is one `draw_list` already, and would be one `spr_set` instead (8
    sprites: no syscall saved; a lock still needs its list); all the drawing calls together
    cost 0.10 ms of CPU a frame on average (290 us with the list call, 187 us without it).
    And they would look worse: a window's sprites are hidden whenever anything covers it
    (the piece would vanish under the game's own right-click menu and the menu bar's
    menus), would stand in front of the pause box, need 14 aligned 16 x 16 images (3.5 KB:
    more than the 1.9 KB left in the code bank) and a second drawing path for REV < $0B.
  - Sizes: QUABRICK.PRG 55.0 KB (22.5 KB of code with the controls library, 23.0 KB of art
    and tables, 16.1 KB of variables: the list's 128 records, the big font's 2 KB arena;
    61.8 KB of the code bank in use).
- **emu816**: `--log-lau` logs every write to Lau.
- **Spelling**: the blitter is **Ali** (was ALi) in the About box and the documents.

## Version 0.16

- **Names.** The machine is the **Atari816** (one word) everywhere: the About box, the
  desktop's corner label, the shut-down alert and screen, the shell. The custom chips have
  names: **Marga**, the video chip (the NVC before), **Ali**, the blitter, and **Lau**, the
  8-voice sample player; FREDDIE II and POKEY 2 keep theirs. Register and symbol prefixes
  (NV_*, BL_*, AU_*) do not change.
- **About** names the chips: "65C816 at 14.3 MHz", "Video: Marga, 640 x 360, 256 colours",
  "Blitter: Ali" (or "Blitter: none (the CPU draws)" before REV $08), "Sound: POKEY 2, Lau"
  (REV $0A and later; "Sound: POKEY 2" on REV $07-$09), and ends with "Not affiliated with
  or endorsed by Atari." It learns the revision from ws_config, which now also returns
  SYS_REV in X (ABI.md).
- **Settings**: the Classic Atari page offers only the memory sizes the hardware has, 128
  and 320 KB (an /atari.ini with another value shows as 320, as the firmware reads it); the
  alert volume's Test button plays the information chime only (0.15 played all four).

## Version 0.15

- **Pop-up menus** (SYS_WPOPUP, `ui_popup`): a menu at the pointer, chosen by a right press
  (dragged to an item and released, or clicked), by the keyboard (the menu key or
  Shift+F10: the first item highlighted, arrows, Enter, Esc). The caller blocks until it
  closes and gets the item. Used by the Desktop (the Atari icon: Attach disk... /
  cartridge..., Run program..., one Eject line per thing loaded, Eject all, Restart Atari,
  Switch to Atari, Atari settings... (Settings on its Classic Atari page), Open panel;
  other icons: Open, Show original (shortcuts), Rename..., Delete; the desktop: New
  folder..., Tidy up, Settings...), by Files (a row: Open, Open with Edit / Write for text,
  Load into Atari for Atari files, Copy, Add to desktop, Rename..., Delete; a folder: Open
  in new window; below the rows: New folder..., Paste, Parent folder), by every text field
  of the controls library (Cut, Copy, Paste, Select all) and by Edit's and Write's text
  (Undo, Redo, Cut, Copy, Paste, Select all).
- **The About box** says what the machine is ("Atari816 / A 16-bit Atari and desktop on
  the 65C816. / With original 8-bit Atari compatibility."), then Horizon's version, the
  processor and screen, the drawing mode, memory, tasks, time and date (0.16: the chips by
  name, below).
- **The alert chime**: a soft two-note chime on POKEY 2 instead of the beep (SYS_CHIME,
  `ui_chime`): pure tone, the volume falling every 10 ms tick; four variants (information
  A5 then E5, warning A5 twice, question E5 then A5, error E5 then C5), each 0.22 s: the
  first note 60 ms (falling to 9/16 of the peak) and 10 ms of silence, the second note 150
  ms falling from the peak to silence. Peak = 3/4 of the alert volume setting (default 8:
  peak 6 of 15). Alerts have four kinds with their own icon and chime; Settings' Test
  plays the four (0.16: only the information chime).
- **Sound ownership**: each POKEY 2 channel and DAC remembers the task that wrote it; when
  that task ends its channels and DACs are silenced (AUDCTL and SKCTL put back if it wrote
  them). The chime takes a channel no program owns (4, 3, 2, 1, one AUDCTL leaves alone);
  only when every channel is taken does it borrow channel 4 for its 0.22 s, and gives the
  program's values back afterwards (the program's writes meanwhile go to a shadow copy).
- **Games**: SYS_JOY (the two DB9 ports: directions and triggers; BASIC's STICK and STRIG);
  SYS_VSYNC (blocks until the next vertical blank; derived from the raster line with
  TIMER1, and from the VBLANK interrupt as soon as the hardware raises it); WE_FOCUS and
  WE_UNFOCUS (a window that loses the focus first gets the releases of the keys it holds;
  their real releases, and their repeats, are dropped); BASIC 1.2 (STICK, STRIG, VSYNC).
- **Fixes**: motion events of a WF_HOVER window no longer report a phantom button ($0004)
  after a menu was used (the window manager kept a window number as the buttons); a blit
  from a program's memory (WD_BLIT, WD_KBLIT, WD_SBLIT, WD_EXPAND, WD_KSBLIT) is finished
  before win_draw returns, so the program may change its buffer at once (ABI.md); the key
  that closes a menu no longer sends its release to the window under it.
- **Wording**: alerts, menus and dialogs say what will happen, in plain words ("Restart
  Horizon? All programs will be closed."), with the same button order everywhere (the
  default rightmost, Cancel leftmost) and an ellipsis on every item that opens a dialog.
- **Programs**: Force quit lists the programs by the names the menu bar shows (task_name;
  SYS_TNAME reads it); the Calculator changes its view by resizing its window (win_geom);
  the file dialog has type-ahead in its list (what matches nothing goes to the Name field)
  and an optional filter (Atari disks, programs or cartridges only); Edit's menus show
  their shortcuts; Settings opens on its Classic Atari page with `settings atari`; Files
  opens a file's folder with the file selected (`wfiles PATH`: the Desktop's Show
  original).
- **Tests**: KTEST and the pop-up menu session (tests 19 and 20); `tests/mousegen.py` no
  longer lets a click overtake the move before it.

## Current limits

- The PC volume (0.20): one shared folder; no Atari disk images mounted from it (CLASSIC_MOUNT
  of a `/PC:` path answers $82: copy the image to the card first); a long copy blocks the
  program doing it (Files, the Desktop, the shell) until it ends.

- Desktop: 16 windows including the menu bar and an open drop-down; menus 2045 bytes per
  window (the Desktop's Programs menu: 16 programs), 12 titles in the bar;
  18 icons from /Desktop; a terminal at most 128 x 40 cells; resizing shows the new
  area in the body colour and tells the program at the release; no outline drag (live
  only); the clock is kept by the tick from the last time set (no battery clock).

- 92 banks of 64 KB in the pool on 8 MB. 4 of them are the screen's framebuffer, so 88
  are left for tasks.
- 16 task slots, 62 task ids, 16 ports, 4 open files for the whole system (an I/O
  processor limit), 128 queued key events.
- Programs:
  - text + data + bss up to 65,280 bytes in one bank;
  - zp up to 256 bytes;
  - the file must be smaller than 64 KB;
  - no imports, so no shared libraries yet.
- Arguments: one string of at most 127 characters.
- Paths: at most 127 characters after the kernel made them absolute, the I/O processor's
  limit (`static char path[128]` in `a816_mailbox()`).
- Edit: Find / Replace texts are one line of at most 63 characters, compared ignoring
  case; undo keeps about 64 KB of changes (the oldest go; one change larger than that,
  such as cutting a very large selection, empties the history); with word wrap the scroll
  bar counts lines, not rows, and a word longer than the row is cut.
- FILES: up to 1000 entries per folder and about 64 KB of names; beyond that the title
  says "more not shown". Names with non-ASCII (code page 437) characters show those as
  `?`.
- A pointer range passed to a syscall must not cross a bank boundary (or $00:8000).
- No per-task heap. Memory comes in 64 KB banks only, and bank contents are not cleared
  (only bss and zp are).
- The shell has no pipes or redirection (arguments may be quoted; command words are looked
  up in `/BIN`, `/SYSTEM`, `/SYSTEM/TESTS`). `dir` and `cat` take one
  path. At most 8 background jobs are tracked.
- Console output also goes to a log (DBG_OUT), which receives every byte unchanged (the
  escapes too).
- USB gamepads and media keys are not passed to programs (the DB9 joysticks are: SYS_JOY).
- The screen has no colour escapes (cursor addressing and clearing: the VT52 subset in
  ABI.md, "Console"). Lines longer than 78
  characters wrap, and BS does not go back across a wrap.
- While the classic machine is shown, console output still goes to the framebuffer
  (invisible) and to DBG_OUT.
