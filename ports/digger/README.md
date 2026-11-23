# Digger for the Atari816

Windmill Software's **Digger** (1983, IBM PC), from **Digger Remastered** by Andrew Jenner
(as kept by Maksym Sobolev: <https://github.com/sobomax/digger>, commit `53bf330`,
2026-03-26), on Horizon with the C SDK (cc816 and hgame). The game's own C files are
upstream's, with the few changes listed in `PORTING-NOTES.md` (all of them in
`upstream.patch`); `horizon/` is the new platform layer, the counterpart of upstream's SDL
back end.

Everything plays: the title screen and its parade, one or two players (alternating or
simultaneous), the gauntlet modes, levels and their backgrounds, digging, emeralds and
the eight-in-a-row bonus, gold bags wobbling, falling, breaking into gold, nobbins and
hobbins, the bonus mode (the cherry, the flashing palette, the William Tell music),
firing and recharging, lives, the score, the high scores with initials (kept in
`DIGGER.SCO`), the music (Popcorn, the bonus music, the dirge) and every sound effect on
POKEY, recording and playing back games (`.DRF`), pause, the speed keys.

## Build and run

```
make            # DIGGER.PRG (hcc --code large) and DIGGER.DAT (the pictures)
make run        # in the emulator, a scripted game (tests/play.script)
make test       # the checks below
make app        # DIGGER.HZA: the app, for Horizon 0.29's Installer
make test-app   # DIGGER.HZA installed, started, played and updated in the emulator
```

**Install it (Horizon 0.29 and later):** copy `DIGGER.HZA` anywhere on the card, double
click it in Files (or type `install DIGGER.HZA` in the shell) and click Install. Digger goes
to `/APPS/DIGGER` and is in the Desktop's Programs menu under Games. Installing a newer
`DIGGER.HZA` the same way replaces the program and keeps the high scores. To remove it:
Files, `/APPS`, the folder DIGGER, Remove app... (that deletes the high scores too). On
Horizon 0.28: unpack the archive on a PC (any `tar`) and copy the folder DIGGER to `/APPS`,
or copy DIGGER.PRG and DIGGER.DAT into any folder; start DIGGER.PRG from Files.

The pictures are made from upstream's C files (`src/data/vgagrafx.c`, `alpha.c`,
`title_gz.c`) by `tools/mkdata.py` into `DIGGER.DAT`. Copy **DIGGER.PRG and DIGGER.DAT**
into the same folder on the card and start DIGGER.PRG from the Desktop (Programs, or
Files). It needs **Horizon 0.28** or later (a program with more than one bank of code in
one file), a REV $0B board (scrolling) and 1.2 MB of free memory: it checks these at its
start and says what is missing (`hcc --needs`). The high scores (`DIGGER.SCO`),
`DIGGER.INI` and saved recordings go into the program's folder.

Upstream's options work from the shell: `DIGGER.PRG /Q` (no sound), `/M` (no music), `/S:N`
(a frame of N x 2 ms: the default is 40, 80 ms; `/S:0` as fast as it goes), `/L:file` (a
level file), `/P:file` / `/E:file` (play a recording back, then go on / exit), `/R:file`
(record), `/G[:secs]` (gauntlet), `/2` (two players at once), `/U` (unlimited lives),
`/I:level`.

## Keys

| | Player 1 | Player 2 |
| --- | --- | --- |
| Move | arrow keys, or joystick 1 | W A Z S (up, left, down, right), or joystick 2 |
| Fire | F1, or the trigger | Tab, or the trigger |

Space or P: pause. N (on the title): one player / two players / simultaneous / gauntlet.
F7 music on/off, F9 sound on/off, keypad + / - faster / slower, F8 save the last game's
recording (named after the initials and the score), T: the cheat (no recording). F10 or
Esc: back to the title; on the title, leave. Any other key on the title starts a game.
Alt+Tab, Alt+Esc or F12 pause the game and show the Desktop (as every full-screen
program); Alt+F4 closes it.

## The screen

Upstream's VGA graphics are 640 x 400 in 16 colours: the 320 x 200 game drawn at twice
the resolution. Horizon's modes are 320 x 180 and 640 x 360 (shown 4 x 4 or 2 x 2 on the
720-line HDMI picture), so 40 of the 400 rows do not fit. Chosen:

- **640 x 360 in 16 colours** (`HG_640X360X4`): the VGA art at its full resolution, its
  own 16-colour palettes (and the bonus mode's palette flashing, by palette writes), each
  pixel exactly 2 x 2 on the monitor. Not the CGA set at 320 x 180: it has 4 colours.
- **No squashing.** Dropping 40 rows evenly would distort a picture whose pixels were
  already 1.2 times taller than wide on the original 4:3 monitor (on this square-pixel
  screen the game is already a little flatter than on the PC).
- **The score line stays, the playfield follows the digger.** The framebuffer has the
  whole 640 x 400 picture (hgame's `hg_screen_fb`); a split in the display (`hg_split`)
  keeps rows 0-27 (the score and lives line) fixed at the top, and below it shows 332 of
  the playfield's 372 rows, gliding every sixtieth of a second (1-2 rows a vertical blank,
  whatever the game is doing in its 80 ms frame) to keep the digger in
  the middle: the 10 rows of the maze are all reachable, 2 rows' worth (40 lines) are out
  of sight at a time. With two diggers it follows the middle between them.
- **The title screen** shows its top 360 rows for 6 seconds, then glides down to show the
  bottom line (the Windmill Software copyright) for 3, and back up.

The game draws into a buffer of its own; what it changed goes to the screen just after
each vertical blank, so no sprite is seen half drawn.

## Sound

The original used the PC speaker: square waves from the PC's timer chip, one at a time,
effects through timer 2 and the music through timer 0 (its loudness a pulse width).
Here each timer is one of POKEY's two 16-bit voices (two channels joined, clocked at
1.79 MHz; hgame's `hg_note`): a square wave like the speaker's at exactly the speaker's
pitch. The music's loudness envelope is the voice's volume. As on the PC one of the two sounds
at a time (upstream's speaker switching is kept: an effect silences the music while it
plays). The level-end jingle's beating is played as its plain notes. (The emulator does not play POKEY: it logs the writes,
`--log-sound`, `--log-sound-us` with their times; the board plays them.)

The speaker's steps come 72.8 times a second, as the original's timer interrupt made them,
also while the game is busy drawing: the program keeps time by Horizon's music timer
(`sample_timer`, a message every 3.4 ms) and looks at it every few milliseconds of its work
(PORTING-NOTES.md, "The board's report"). It needs a board with Lau (REV $0A or later);
without it the steps go by the vertical blanks, as before.

## Speed

The game runs at the original's 12.5 frames a second (upstream's default frame time,
80 ms), each frame starting within 3.4 ms of its beat (the music timer's clock:
`horizon/hz_timer.c`); the picture changes at vertical blanks, 5, 5, 5, 5, 4 apart.
Measured in the emulator (which models the board's timing within a few per cent):

- the scripted game (`make test`): 811 frames counted, 8 later than their time (the title
  drawn, the level's start, the game over: none in play);
- upstream's recorded `thevoids.drf` played back at the game's pace (9 levels, 41,561
  frames): 3,365 s against 3,325 s at exactly 80 ms a frame (1.2 % slower in all, level
  drawing included); 298 frames late (0.7 %), in short runs where many sprites overlap
  (upstream's software sprites redraw every overlapping one);
- a key reaches the screen in 65 ms on average, 116 at most (it is read at every vertical
  blank; the game reads its direction at the start of its frame);
- at full speed (`/S:0`) a frame takes 20-45 ms on average, level drawing included.

PORTING-NOTES.md ("Speed", "The board's report") has the figures before and after.

## What differs from the original

- The view scrolls (above): 40 of the 400 lines are out of sight at a time.
- POKEY instead of the PC speaker (above): the same pitches; a cleaner square wave than
  the speaker's cone.
- Joysticks work (upstream's SDL version has none); Esc also leaves (upstream: F10).
- Recordings hold about 9 hours of play (upstream: 36): a buffer is one 64 KB bank.
- The redefine-keys option (`/K`, from the shell) is upstream's and was not tried; its
  INI file holds HID usages, which are SDL's scancodes.

## Tests

`make test` (`HORIZON=DIR` for another Horizon tree):

1. the scripted game, `tests/play.script`: title, a game, the five emeralds of the middle
   column, three lives lost, game over, initials HZD, the title with the new high score,
   F8, Esc; each step waits for the program's console line for that state (`digger:
   title`, `digger: play`, `digger: dead`, `digger: initials`: run816.py's `wait`), not a
   fixed time, so a slower or quicker start changes nothing (checked with the start
   delayed by 1.5 and 3 s: a file `DELAY.TXT` with the milliseconds, next to the program);
   the console's frame statistics are expected (no pictures: see 2);
2. `tests/check.sh`: `DIGGER.SCO` has HZD 125; POKEY's 16-bit voices were set up and
   played (the logged writes); the game's own recording (F8) plays back to the same
   score; `tests/frames.sh`: the game's recording of that game (`tests/play.drf`) played
   back, a picture at each game frame of `tests/frames.txt` (the program stops there and
   asks for it: `run816.py --shot-on`), each equal to `tests/ref/frame-N.png` pixel for
   pixel; the pictures are of game frames, so the program's timing does not move them
   (`make refs` writes them again after a change meant to show: look at them first);
3. `tests/drf.sh`: seven of upstream's recorded games (`tests/drf/`, from upstream's
   `tests/data`) played back at full speed; each must end with upstream's own result
   (score, level, frame count: `tests/drf/*.out`, from upstream's CI). The game logic
   looks at the screen's pixels, so this checks the drawing too.

`make test-app` (`tests/app.sh`, `tests/app.script`): the Desktop with nothing started
(`run816.py --mode none`), `DIGGER.HZA` opened in Files, Install, Programs > Games > Digger,
its title, a game to a high score (APP 125), back to the Desktop, the archive opened again:
Replace. The card must then hold `/APPS/DIGGER` with APP.INF, DIGGER.PRG, DIGGER.DAT,
DIGGER.ICN, and DIGGER.SCO with the score, kept by the update.

## Files

| | |
| --- | --- |
| `src/` | upstream's game (GPL; see below), `src/data/` its pictures as C arrays (unchanged) |
| `horizon/` | the platform layer: `hz_vid.c` + `hz_blit.s` (video), `hz_data.c` (DIGGER.DAT), `hz_timer.c` (frames, the view), `hz_snd.c` (sound), `hz_kbd.c` (keys, joysticks), `hz_main.c` (start, files) |
| `tools/mkdata.py` | upstream's pictures to DIGGER.DAT, and the app's icon DIGGER.ICN (from the VGA digger) |
| `tools/keyhold.c` | a board test: every key event with its time (the held-key fault, PORTING-NOTES.md) |
| `app/APP.INF` | the app's description (`make app`) |
| `tests/` | the scripted game, the checks, upstream's recordings, the reference pictures, the app's test |
| `upstream.patch` | every change to upstream's files |
| `PORTING-NOTES.md` | what the port needed, the SDK problems met, timings |
| `COPYING` | the GNU GPL version 2 (upstream's `pkg/windows/LICENSE`) |

## Licence

Digger Remastered is Andrew Jenner's, who was granted the rights to the remake by
Digger's author and licensed it under the **GNU GPL** (upstream `digger.txt`, "Is this
legal?"); upstream's tree as a whole is "Public Domain, Beer-Ware, 2-clause BSD and GNU
General Public License version 2" by file (upstream `README.md`), with the GPL version 2
text as its licence file (`pkg/windows/LICENSE`, here `COPYING`). The files taken here
are Andrew Jenner's (GPL) and Maksym Sobolev's `digger_types.h`, `*_obj.[ch]` (2-clause
BSD, in their headers); the palettes in `horizon/hz_vid.c` come from upstream's
`sdl_vid.c` (Beer-Ware, Maksym Sobolev). The port (`horizon/`, `tools/`, `tests/`) is
under the GPL version 2 like the game it is part of. The original game is © 1983
Windmill Software.
