# Prince of Persia on the Atari816

Jordan Mechner's Prince of Persia (the DOS version, 1990) on Horizon, from
[SDLPoP](https://github.com/NagyD/SDLPoP) (NagyD and contributors), the C port of the DOS
game's disassembly. The game's own logic runs unchanged (SDLPoP's `seg000.c`-`seg008.c`,
`seqtbl.c`, `replay.c`), on a platform layer of the Atari816 in place of SDLPoP's SDL one.
It plays as recorded games played on a PC do: the four test replays end exactly as on the
PC, state for state, and their pictures are equal to the PC's pixel for pixel.

## Build and run

```
make data       # SDLPoP's data: tools/getdata.sh downloads SDLPoP at commit f7be2e9
                # (SHA-256 checked) or takes your copy (make data SDLPOP=DIR: a checkout
                # with data/); tools/mkdata.py converts it into data/card/ (about 1.9 MB)
make            # PRINCE.PRG (needs cc65's ca65/ld65 and the SDK; Horizon 0.30)
make run        # the game in the emulator (build/run/)
make test       # the checks (tests/check.sh), about 50 s on a fast PC
make test-long  # every level against the PC's (tests/levels.sh; needs make host)
make app        # PRINCE.HZA: the app (APP.INF, the program, the data, an icon)
make test-app   # installs PRINCE.HZA in the emulator, starts it from Programs > Games
make host       # optional: upstream SDLPoP built on the PC as the reference (SDL2, zlib)
make check-host # after make test: the replays' pictures against the PC's
```

A user who wants the game on the board: `make data && make app`, copy `PRINCE.HZA` to the
card, double-click it in Files (the Installer puts it in `/APPS/PRINCE`); it appears in
Programs > Games. The archive contains the converted game data: it is built on your
machine from your copy, never committed or published here.

The program needs Horizon 0.30, the blitter and 3 MB of free memory (`hcc --needs`; on a machine
without them it prints what is missing and ends). Sound uses Lau (REV $0A) and the OPL2 (REV $0C)
when they are there; without them the game plays silently.

## Keys

The game shows a loading screen at once (its bar follows the bytes read: about 4 s on the
board's card, 1.9 MB), then its first screen with the keys. There **Space or Enter starts
the game**, Ctrl+L loads the saved game, any other key shows the title, where any key (or
Shift, or the joystick's button) starts it, as in the original.

| Key | |
| --- | --- |
| Arrows (or the joystick) | run, jump (Up), crouch / climb down (Down), Up + a direction: running jump |
| Shift (or the joystick's button) | careful step (with Left/Right), grab a ledge, drink, pick up, strike |
| Esc | pause (any key goes on) |
| Space | the time left |
| Ctrl+A | restart the level |
| Ctrl+G / Ctrl+L | save the game (levels 3-13) / load it (also on the title) |
| F6 / F9 | quicksave / quickload (QUICKSAVE.SAV) |
| Ctrl+S | sound on / off |
| Ctrl+R | back to the title (a new game); Ctrl+Q quits |
| Shift+L | the next level (levels 1-3; every level with `megahit`) |

Saves (`PRINCE.SAV`, `QUICKSAVE.SAV`) and the hall of fame (`PRINCE.HOF`) are written in the
program's folder; an update of the app keeps them.

Command line (the shell): SDLPoP's own (`megahit N` starts level N with cheats,
`validate FILE.P1R` checks a replay and prints how it ended, `FILE.P1R` plays one, `seed=N`),
and the port's: `nosound` (no sound at all: replays recorded silently), `/BUSY:ms` (a
slower machine: the tests), `stats=N` (frame times every N game frames), `every=N`,
`shots=a,b`, `dump=a` (the tests' state lines, pictures and savestate dumps at replay ticks),
`levelsum` (each level's checksum), `sndtest` (every sound once, then it ends).

## Differences from the PC

- **Screen.** The game draws 320 x 200; the Atari816's full screen shows 320 x 180.
  In a room the screen shows 172 of the room's 192 rows and, below a split (Marga, no
  cost), the 8-row status line (health, messages). The view follows the kid: his row
  selects which 172 rows are shown (the top ones when he is up, the bottom ones when he is
  down), moving a row a frame. Full pictures (the title, the story, the princess's room) show
  their rows 20-199 (the top 20 are a border). Nothing is squeezed.
- **The palette** is the DOS game's VGA palette (each image set in its own row of 16
  colours, as on the VGA): colours are exact; the flashes change palette entry 0, as the
  DOS game did. The shadow's second blit (an XOR) is SDLPoP's, in RGB: each colour it makes
  gets a palette entry of its own (rows 4 and 15 are free), so the shadow looks as on the PC
  pixel for pixel.
- **Sound.** The digital effects (DIGISND) play on Lau at their own rate; the music is the
  AdLib (OPL2) version, played by the real OPL2 from register streams made from the game's
  MIDI data with SDLPoP's own interpretation (tools/midi2imf.c: the same register writes,
  checked; 13.5 dB quieter: the board mixes the OPL2 three times louder than Lau, and so the
  songs are as loud as the effects, tests/sndlevel.py); the four PC speaker sounds on
  POKEY. SDLPoP's OGG music is not used.
- **Not in the port:** SDLPoP's pause menu (settings, mods), SDLPoP.ini (its defaults are
  used: the original game's behaviour, no fixes), mods and custom level sets, screenshots,
  lighting, fast forward, recording replays with Ctrl+Tab (replays play and validate).
- Room changes show a short black frame (as SDLPoP's "dark transition" and the original).

## Licences

The code: SDLPoP is GPL-3 (`COPYING`); its README says: "This program is open source under
the GNU General Public License terms, see `COPYING` and `src/GPLv3.h`. The following files
are external libraries with their own licenses: `src/opl3.c`, `src/opl3.h`,
`src/stb_vorbis.c`." This port (src/, horizon/, tools/, host/, tests/) is GPL-3 as well.
The port does not use opl3.c or stb_vorbis.c.

The data: SDLPoP's repository ships the DOS game's data (`data/`: the graphics extracted as
PNG, levels, sounds) without any licence statement for it; it is the original game's
(Broderbund / Jordan Mechner). So the port keeps all of it out of git: `tools/getdata.sh`
fetches SDLPoP itself, `make data` converts it on the user's machine, test pictures are kept
as checksums only, the test replays without their level (a replay's savestate begins with
the level's map: `tests/replays/*.p1x`, `tools/p1rstrip.py`; make test rebuilds the `.p1r`
from your data, byte for byte), and the app archive is built locally.

## Tests

`make test` (tests/check.sh), all in the emulator, its card as slow as the board's (run816's
default; each step of the scripts starts on a console line of the program, never after a
fixed time):

1. four replays recorded with upstream SDLPoP on a PC (`tests/replays`: level 1 from its
   start to the sword and on through ten rooms; a loose floor; a sword fight on level 2;
   rebuilt first from the `.p1x` and the game's levels into `build/replays`, MD5-checked),
   in upstream's `validate` mode: the game's state every 10 ticks and upstream's own end
   lines must equal the PC's (`tests/ref/*.ref`, 246 states, 2,478 ticks in all);
2. one of them at the game's speed on a machine 30 ms a frame slower: the same states;
3. 18 pictures at replay ticks (checksums in `tests/frames.md5`; equal pixel for pixel to
   the PC's frames: `make check-host`);
4. a game through the keyboard (`tests/play.script`, its steps start on the program's
   console lines): the first screen, the title, level 1, a quicksave and quickload, a pause
   (QUICKSAVE.SAV, the quickload's savestate checksum equal to the quicksave's, Lau's
   writes, pictures in `tests/play.md5`: the first whole, the others' status line); the
   title music's OPL2 writes against its stream for 10 s; a key at the title after 15, 40
   and 60 s: level 1 in room 1 with the heap as after a key at once (no leak); Enter on the
   first screen: level 1 at once, without the title;
5. a game saved on level 3 (Ctrl+G, typed quickly: Ctrl and G released together) and loaded
   from the title (Ctrl+L);
6. every sound once (`sndtest`), recorded as the board mixes Lau and the OPL2
   (`tests/sndlevel.py`): the effects' and the songs' median rms within 3 dB (-27.6 and
   -28.4 dBFS), no clipping, the loudest peak -9 dBFS.

`make test-long` (tests/levels.sh; `make host` first: the host build records the replays into
`build/levels`, `tests/mklevels.sh`, since a replay holds the level's map):

1. each level 1-14 from its start (40 ticks): the start room, the level structure's
   checksum (all 2,305 bytes), the states and upstream's end lines as the PC's
   (`tests/levels/*.ref`), the picture at tick 40 equal to the PC's pixel for pixel;
2. level 6's shadow (a replay whose start `tests/patchp1r.py` moved next to its room):
   27 states and two pictures as the PC's (the XOR blit's colours);
3. the game walked through with Shift+L (`megahit 1`): each level in its start room with
   the heap as when started directly (`megahit N`).

`make test-layouts`: `make test`'s checks with the program's layout shifted (`PAD=n`:
`tools/mkpad.py`'s object linked first; default 0 1 37 250 500).

The Makefile rebuilds by content (checksums in `build/sum/`), so a copy with old file
times (rsync -a, an archive) still rebuilds what changed.

`make test-app`: the archive installed with the Installer, started from Programs > Games
into level 1, a quicksave, the app updated (Replace keeps QUICKSAVE.SAV).

`make host`, `make refs-host`: the reference build (upstream at the same commit, with
`host/ref.patch`: a state and picture hook, an OPL log, scripted recording) and the
reference results; `tests/mkref.sh`.
