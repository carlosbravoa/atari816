X-COM: UFO DEFENSE on the Atari816 (XCOM-XT)
============================================

XCOM-XT is a new engine for X-COM: UFO Defense (MicroProse, 1994), written for
old DOS PCs by Filip Mikowski and others (GPL-3, github.com/fmikowski/xcom-xt).
This is its port to the Atari816 (Horizon 0.30). It plays the game's own
pictures, music and sounds, which you bring from your own copy of the game:
nothing of the game is in this app.


1. YOUR GAME DATA
-----------------
You need X-COM: UFO Defense (the DOS version 1.4, or the GOG edition) and a PC
with Python 3 and PyYAML.

  1. Get the port's source (ports/xcom of the Atari816 repository: the
     engine and its converter are in it) and run, on the PC:
         make data GAME="/path/to/your/X-COM folder"
     This runs XCOMCONV, the engine's converter, and writes data/packs/.
  2. Copy onto the card, into this app's folder /APPS/XCOM/:
         data/packs/PACKS.VER
         data/packs/*.PAK          (5 files, 290 KB)
         data/packs/VGA/           (the whole folder, 82 files, 18 MB)
     The EGA and CGA folders are not needed.
     (Or, on the PC: make card -- it builds build/card/APPS/XCOM/ with the
     program and your data, to copy whole onto the card.)

Without the data the program says so and ends. Updating the app keeps the
data and your saves (the Installer keeps files that are not in the archive).
When a new version needs new packs (PACKS.VER names their format: 5 since
the buttons' and windows' sounds came in), the program says so on its
screen: make them again (make data) and copy them over the old ones.


2. PLAYING
----------
The game is X-COM as you know it, with the mouse; the keys are XCOM-XT's
(the full list: the engine's MANUAL.TXT, section 11).

The screen: the game's 320 x 200 pictures on the Atari816's 320 x 180: 20
rows do not fit. The picture stands still; the MOUSE WHEEL moves it up or
down (two steps from the middle to an end), and so do F5 (up) and F6
(down). Each kind of screen starts where its buttons are: the geoscape and
its windows in the middle (rows 10-189: the INTERCEPT button, in the top
rows, is one wheel step up, or the I key), the base screens at the bottom
(their buttons are in the last rows; the base's name is cut), the graphs
and the UFOpaedia's articles at the top, the battle's inventory near the
top (its OK button). In battle the panel is always shown whole and the map
view above it starts in the middle; the wheel moves it the same way.

Start menu: N new game, L load, Q quit.
Geoscape: 1-4 time speed, Space pause, + / - zoom, arrows scroll, Tab next
  UFO or site, Enter send the transport, I intercept, B bases, R soldiers,
  F funding, G graphs, U UFOpaedia, S save, Esc options.
Bases: the buttons as in DOS; Purchase/Sell/Transfer + / - one more or less.
Battle: click a tile to move the cursor, again to walk; arrows / PgUp / PgDn
  move the cursor, + / - level, Tab next soldier, Enter walk, Space turn,
  F / A / U snap / aimed / auto shot, G throw, R reload, K kneel, I
  inventory, M medi-kit, C centre, E end turn, S sound on/off, Esc options
  (load, save, abandon), F2 abort the mission.

Saves: ten slots, XCOMXT0-9.SAV in this app's folder (also in the middle of
a battle). The game's options: XCOMXT.CFG there too.

Sound: the music on the OPL2 (the AdLib music, played by a small helper
program, MUSD.PRG, so that it keeps its tempo while the game is busy); the
effects (the Sound Blaster's samples) on the sample player. Outside a
battle, as in DOS: a click when a button is pressed with the mouse and one
of the three pop-up sounds when a window opens (the start menu, the
options, the saves, the geoscape's and the bases' windows); a chime when a
UFO is detected; in an interception the craft's and the UFO's shots, hits,
the crash; at a base's defence its guns. In a battle: every footstep, the
shots (by weapon), hits, deaths, doors, explosions, a throw (its menus are
silent). S in a battle turns the sound off and on.


3. DIFFERENCES FROM DOS
-----------------------
XCOM-XT's own (its MANUAL.TXT, section 12): a flat world map with three zoom
levels instead of the globe, soldiers step from tile to tile, a few shortcuts.
The Atari816's: the 20 rows (the wheel, F5 / F6, above); F10 and F12 belong
to Horizon (the menu bar and leaving the full screen).


4. OPTIONS: XCOM.ARG
--------------------
Started from the Desktop the program gets no options. If a file XCOM.ARG is
in its folder (/APPS/XCOM/XCOM.ARG), its words are the options instead (a #
starts a comment to the line's end). For example, to skip the intro:
    NOINTRO
The engine's options are in its MANUAL.TXT, section 10 (NOINTRO, BATTLE,
SEED n, KEYS file, LOG file, BENCH, ...). The port's own come first:
  /M          measure: the program times itself and writes XCOMPERF.TXT in
              its folder (and /PC:/XCOMPERF.TXT when the PC link is up):
              a line every 5 s, a block every 30 s, the totals at the end
  /MN NAME    the same, into NAME.TXT
  /W          the pointer goes round in circles by itself (for /M runs)
  /Q n        end after n seconds (with /M)
  /E          end when the game first waits for input (after BENCH)
  /C FILE     copy FILE to /PC:/ at the end (e.g. /C BENCH.TXT)
  /IOB        time the card's requests, write IOBENCH.TXT (and /PC:/), end
  /PANPTR     the earlier screen: the picture follows the pointer up and down
  /CPUPTR     the game draws its pointer into the picture (not a sprite)
The engine's NOEXACTAI makes the aliens' turns much shorter (a battle's
turn of 45 s takes about 8 s), with sight and aiming a little simpler than
DOS's (MANUAL.TXT section 12).
Delete XCOM.ARG (or empty it) to play normally.


5. KNOWN FAULTS
---------------
See PORTING-NOTES.md in the port's source ("What is next"). The aliens' turn
in a battle takes long (tens of seconds in the first turns; the pointer
still moves meanwhile); NOEXACTAI (above) shortens it.
