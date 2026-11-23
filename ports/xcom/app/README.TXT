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

  1. Get the port's source (ports/xcom of the Atari816 repository) and run,
     on the PC:
         sh tools/getsrc.sh
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


2. PLAYING
----------
The game is X-COM as you know it, with the mouse; the keys are XCOM-XT's
(the full list: the engine's MANUAL.TXT, section 11).

The screen: the game's 320 x 200 pictures on the Atari816's 320 x 180. The
picture follows the pointer up and down (move to the top or bottom edge to
see the top or bottom rows). In battle the panel is always shown whole and
the map view above it follows the pointer.

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
effects (the Sound Blaster's samples) on the sample player.


3. DIFFERENCES FROM DOS
-----------------------
XCOM-XT's own (its MANUAL.TXT, section 12): a flat world map with three zoom
levels instead of the globe, soldiers step from tile to tile, a few shortcuts.
The Atari816's: the screen pans as above; F10 and F12 belong to Horizon (the
menu bar and leaving the full screen).


4. KNOWN FAULTS
---------------
See PORTING-NOTES.md in the port's source ("What is next"). The aliens' turn
in a big battle takes long (tens of seconds in the first turns).
