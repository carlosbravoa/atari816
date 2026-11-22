# Xargon for the Atari816

Allen Pilgrim's **Xargon** (Epic MegaGames, 1993-1994; three episodes: *Beyond Reality*,
*The Secret Chamber*, *Xargon's Fury*), from its released source code, on Horizon with the
C SDK (cc816 and hgame). The game's own C files are upstream's, with the few changes listed
in `PORTING-NOTES.md` (all of them in `upstream.patch`); `horizon/` is the new platform
layer: what upstream had in assembly that was never released (VGA mode X drawing, the
keyboard interrupt, the timer, the WORX Sound Blaster library) and its DOS hardware files.

Seen working in the emulator (the tests and the runs of `PORTING-NOTES.md`): the title, the
main menu (new game, load, demo, high scores), the map, its
paths and journals, entering level 1, walking, jumping, shooting, death in the water and
the restart at the checkpoint, the game's menu, quitting, the high scores, saving and
loading games (7 slots, `SAVE_n.XRn`, `CONFIG.XRn`), the recorded demo to its end (5,077
frames: it scores 15,050 points, takes 14 emeralds and never loses health, as recorded:
enemies shot, items, emeralds, text objects, scrolling in every direction), the sound
effects (Lau) and the music (the OPL2). Episodes 2 and 3 were run to their maps (title,
menu, map, their music). The rest (the later levels, the shop, the bee and swimming forms,
switches, elevators, the end of an episode) is upstream's code running unchanged with
the same platform layer, but was not played through one by one. All three episodes, one
program each (`XARGON1.PRG` .. `XARGON3.PRG`, as upstream's `XRFILE01-03.EXE`).

## Build and run

```
make data       # the game's files: downloaded (tools/getdata.sh) or from your copy
                # (make data GAME=DIR), converted into data/card/ (tools/mkdata.py)
make            # XARGON1.PRG, XARGON2.PRG, XARGON3.PRG (hcc --code large)
make run        # episode 1 in the emulator with the scripted game: build/run/
make test       # the checks (tests/check.sh)
```

Copy the programs and everything in `data/card/` into one folder of the card (say
`/GAMES/XARGON/`) and start `XARGON1.PRG` (2, 3) from the Desktop. It needs **Horizon 0.28**
or later and a board with Lau and the OPL2 (REV $0C) for the sound: without them it plays
silently. Options (from the shell, as upstream's): `/NOSB` no sound, `/NOSND` the same;
`/STATS` frame statistics on the console every 10 s; `/BUSY:ms` (tests) that much more
CPU time each game frame, as on a slower machine.

## Keys

As upstream's: arrows (or the keypad) move, climb and look, **Ctrl** or **Alt** jump,
**Shift** or **Space** fire, **Enter** the inventory, **Esc** or **Q** the game's menu,
**F1** help, **S**/**L** save/load (on the map), **B** buy, **P** pause, **G** granny mode,
**N** noise on/off. Joystick 1 moves, its trigger jumps; the trigger of joystick 2 fires
(Space and Shift fire too). Alt+Tab, Alt+Esc, F12 pause the game and show the Desktop;
Alt+F4 closes it.

## The screen

Upstream draws 320 x 200 in 256 colours: the playfield (158 rows, rows 2-159) above a
40-row status bar. Horizon's screen is 320 x 180. Chosen: **the playfield's 140 middle
rows (11-150) and the whole status bar**, in 256 colours, each pixel 4 x 4 on the
monitor. The game still works on its 158-row view (as upstream: the game logic updates
the objects near the view, so a smaller view would change the game, and its recorded
demo): 9 rows are out of sight at the top and at the bottom. The game keeps the hero
between rows 32 and 120 of its view and its windows inside rows 16-144, so both are always
seen. Full-screen pictures (the title, the story, the ordering pages) show rows 0-179.

Scrolling is smooth and costs nothing: both pages are in one framebuffer whose rows are
rings (Marga's horizontal wrap); the view moves by the scroll registers instead of the
50 KB copy upstream makes on the VGA each frame. The tiles and sprites are drawn by the
blitter from an atlas of the game's shapes in far memory (sheets), the fonts' glyphs in
their colours through a small cache: `PORTING-NOTES.md`, "The platform layer".

## Sound

- **Effects**: upstream's 49 digitised Sound Blaster effects (8-bit, 6,250 Hz) on Lau,
  one at a time with upstream's priorities.
- **Music**: the CMF songs (Creative's FM music files) on the OPL2, converted at build
  time into AdLib register streams (as Creative's SBFMDRV plays them: its voice
  allocation, rhythm mode, transposition) and played by hgame's `hg_opl_play`. The songs
  are 13.5 dB quieter than on a Sound Blaster: the board mixes the OPL2 three times louder
  than a Lau voice, and they clipped. The timing is the frame's (60 Hz) where the Sound
  Blaster driver ticked at 96 Hz: a note may come up to 1/60 s late.
- The PC speaker's versions are not needed.

## Speed

The game runs at the original's speed, one step per BIOS tick (18.2 a second), the
vertical blanks counted for the ticks. Measured in the emulator (`make test`, `/STATS`):
the map and most of level 1 at 18.2 frames a second (3.3 blanks apart, about 1.1-1.5
blanks of CPU a frame); the recorded demo's busiest scenes (40 objects, a room full of
text) at about 17 (3.46 blanks apart on average over its first 5,000 frames: 95 %).
Details in `PORTING-NOTES.md`, "Speed".

## Tests

`make test` (`HORIZON=DIR` for another Horizon tree; data in `data/card` first):

1. the scripted game (`tests/play.script`): the title, the main menu, a game saved on the
   map (slot 1, "HZTEST"), the map's paths and its journal, level 1 (a jump, a shot, the
   water: the hero dies and starts again), the game's menu, quitting, the high scores,
   the game loaded again: the save on the card, the game loaded where it was saved, the
   sound (Lau's writes, the recording's level and clipping), the frame statistics, 14
   screenshots against `tests/play.md5`;
2. the recorded demo (`DEMO_MAC.XR0`, the menu's DEMO-PREVIEW) twice, the second time on a
   slower machine (`/BUSY:30`): at its frame 1,500 the game must be as `tests/demo.ref`
   says (score, health, emeralds, hero, objects), the same both times.

The screenshots' references are kept as checksums (the game's pictures stay out of the
repository, as its data); `make refs` writes new ones and the pictures into `tests/ref/`
(look at them before you keep them).

## Files

| | |
| --- | --- |
| `src/` | upstream's source as released (names in lower case), with `upstream.patch` applied |
| `horizon/` | the platform layer: `hz_vga.c` + `hz_blit.s` (drawing, the VGA's registers), `hz_shm.c` (the shapes), `hz_frame.c` (the clock, the retrace, the game port, statistics), `hz_kbd.c` (keyboard), `hz_snd.c` (sound), `hz_cfg.c` (configuration), `hz_dos.c` + `compat/` (DOS and Turbo C), `hz_main.c` |
| `tools/getdata.sh` | the game's files: downloaded (SHA-256 checked) or from your copy, into `data/orig/` |
| `tools/mkdata.py` | the game's files to the port's: `XSHAPES.XRn` (the shapes' atlas), `XSOUND.XRn` (the effects), `SONG_n.OPn` (the music), the boards and texts as they are |
| `tests/` | the scripts, `check.sh`, `shots.py`, `wavcheck.py`, the references |
| `upstream.patch` | every change to upstream's files |
| `PORTING-NOTES.md` | what the port needed, the SDK problems met, timings |
| `Kiloblaster_and_Xargon_Freeware_License.txt` | upstream's licence |

## Licence

**The source.** Allen Pilgrim released the source of Xargon (and Kiloblaster) on 4 August
2008 under the *Kiloblaster and Xargon Freeware License* (`Kiloblaster_and_Xargon_
Freeware_License.txt`, as published with the source at classicdosgames.com and in the
`dos-games/vanilla-xargon` mirror):

> "Finally, I included the source code for "Kiloblaster" and "Xargon." My intent is to
> allow people to use this in any way they choose, including to create a commercial
> product. The two limitations are: 1) They can't release a game that in any way resembles
> either of my games and, 2) They can't use it for anything pornographic, illegal or in any
> way immoral. Those are my only requirements."

Limitation 1 read literally would forbid a port. The author settled that for ports
himself, on the Classic DOS Games forum, thread "Is porting Xargon permitted?" (topic 971,
posts as *kilodude*, July 2011, about Adam Nielsen's SDL port): "port away and use the
essence of the GNU license here", "Feel free to distribute the entire thing under the GPL
license", "If you were making a commercial port then that would be different". This port
is non-commercial and kept with its source. Its own files (`horizon/`, `tools/`, `tests/`)
are offered under the GNU GPL version 3 (`LICENSES/GPL-3.0.txt` at the top of the repository), as the SDL port was, in that spirit. Adam
Nielsen's SDL port (GPL 3) was read for the formats (the board files' 4-byte pointers, the
CMF music); none of its code is used.

**The data.** The game itself (episodes 1-3: graphics, levels, sounds, music) was made
freeware by its author on the same date (classicdosgames.com: "Author Allen Pilgrim
generously released this game as freeware under the Kiloblaster and Xargon Freeware
License"); the archive (`Xargon_Commercial.zip`) still holds Epic MegaGames' 1994
`LICENSE.DOC` ("This game is copyrighted, commercial software ... Any unauthorized
copying or distribution is prohibited") and no written licence for redistributing the
data. So the data files are **not** in this repository: `tools/getdata.sh` downloads the
freeware archive (or takes your copy) and `make data` converts it, into `data/` (ignored
by git). The screenshots of the tests are kept as checksums for the same reason.
