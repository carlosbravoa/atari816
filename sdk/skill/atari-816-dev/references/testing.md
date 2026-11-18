# Testing recipes

## run816.py

```
python3 SDK/tools/run816.py PROG.PRG [--horizon DIR] [--mode desktop|shell] [--args TEXT]
        [--script FILE] [--shot SECONDS]... [--seconds N] [--out DIR] [--file SRC[:DEST]]...
        [--rev 7..11] [--log-sound] [--log-lau] [--expect TEXT]... [--window]
```
- Copies `HORIZON/build/sd` to `OUT/card`, puts the program at `/APPS/NAME.PRG`, boots
  emu816 headless, starts the program, plays the script, takes the shots.
- `--mode desktop` (default): the Desktop starts it from its Programs menu (F10, Right,
  Enter at 4.0-4.8 s; time 0 = 5.0 s). No arguments. Console output only in console.txt.
- `--mode shell`: the text shell types `/APPS/NAME.PRG args`; console programs show their
  output on the screen; window programs start the window system themselves.
- Writes `OUT/shotN.png` (1280 x 720), `OUT/console.txt` (the kernel console, escapes
  removed), `OUT/emu.err`, and leaves `OUT/card` (files the program wrote are there).
- Exit 1 on a `[kill]`, a missing `--expect` text, or a blitter rule broken.
- At most 16 shots per run. A run of 20 emulated seconds takes about a second.
- `--window` opens the SDL window for playing by hand (emu816 built with `make SDL=1`).

## Scripts

```
# comments
1000 shot                   absolute ms after the start
+200 key space 100          hold Space 100 ms
+300 key right 900          hold Right
+50 {up}{up}x\n             taps: arrows, 'x', Enter (each key 20 ms, every 50 ms)
+100 ^S                     ctrl+S; {alt-f} Alt+F; {f10}; {esc}; {tab}; {del}
+200 move 200 150           pointer to screen (200, 150) (it starts at 320, 180 at boot)
+100 click                  also: click right, dclick, press, release, wheel -3 (down)
+100 press                  a drag: press, drag X Y (16 px every 30 ms), then release
+100 drag 300 200
+1000 release
+100 down lshift            hold a key until `up lshift`
+800 shot
```
- Keys typed while a menu is open go to the menu.
- In desktop mode Files is open at (24, 24) and has the focus until your window opens;
  your menus come after "Horizon" and "Programs" in the bar.
- `SYS_UPTIME` gives the same value at the same point of every run: random seeds from it
  repeat, which keeps tests reproducible.
- A Makefile with a shell run and a desktop run: the templates put `--mode $(RUNMODE)`
  inside `RUN816`; call run816.py directly for the other mode.
- A shot can catch a sprite between its erase and its redraw (a frame without it): if
  that happens often, the drawing order flickers on the board too.
- Give the program time: a window opens in < 0.5 s; a file dialog ~1 s; typing takes
  50 ms per character.
- Screen coordinates: the content of a window opened at (x, y) starts at (x + 1, y + 16).
  Read positions off a contact sheet (`contact.py`, half size = screen pixels).

## Looking at shots

`python3 SDK/tools/contact.py OUT/sheet.png OUT/shot*.png` (half size; each shot is
labelled with the number in its file name, so shot10 sorted before shot2 is still right) or
`--full --crop X,Y,W,H` to zoom into a window (screen coordinates). Look for: text cut or
overlapping, controls off the grid, leftovers of erased sprites (trails), wrong colours
(img2inc's nearest-colour choice), something not redrawn after a dialog closed.

## Test targets

- Console program: `--mode shell --args ... --expect 'exact output line'`.
- Window program: `print` a line per event worth checking and `--expect` it (under the
  Desktop console output goes only to the log = console.txt); shots; a file the program
  wrote (`test "$(cat build/test/card/F.TXT)" =
  "..."`), or a self-test mode printing PASS lines (`prog -t`, as Calculator, Sheet,
  Solitaire do) checked with `--expect`.
- Game: a script that plays (start, move, a state change), `--log-sound` and
  `grep -q 'DB01' build/test/emu.err`.
- BASIC: `basic -t FILE` runs a script file and copies the console to the log;
  `-r FILE` runs a program (`SDK/templates/basic-game`).
- Revisions: the emulator is REV $0B by default (sprites, scrolling, Lau, command lists);
  `--rev 10` no sprites / scrolling, `--rev 8` no command lists, `--rev 7` no blitter (shows
  what is slow).

## make check

`make -C SDK check`: the reference against horizon.inc / the kernel, and all reference
examples assembled. Run it after changing the reference or when Horizon changes.

## On the board (by the user; needs the PC link)

`python3 SDK/tools/deploy816.py PROG.PRG --dest /BIN/PROG.PRG` copies it to the SD card
over USB (`core/tools/atari.py send`); `--shot out.png` takes a screenshot of the native
screen (`atari.py shot816`). Start the program from the Desktop (Files, or a Programs menu
entry) or the Terminal. The board is about 2 x slower than the emulator on CPU work. Do not
use the board unless the user asks.
