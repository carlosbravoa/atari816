# Micropolis for the Atari816

**Micropolis, the city simulator from the original SimCity source**, on the Atari816 and
Horizon 0.30: the simulator of the GPL-3 release of SimCity's source (Micropolis, Electronic
Arts 2008, Don Hopkins' Unix port) as it is, in C (`engine/`, our fork), with a front end of
our own on the SDK's game library hgame: full screen 640 x 360, mouse-driven, the original's
tiles and moving things.

Micropolis is a registered trademark of Micropolis Corporation (Micropolis GmbH) and is
licensed here as a courtesy of the owner. SimCity is a trademark of Electronic Arts; this
program is not SimCity and not affiliated with Electronic Arts. It is a modified version of
Micropolis (engine/FORK.md lists the changes).

## Build, run, test

```
make data        build/card: the art (MICROPOL.GFX), the sounds (SND/), the cities, the scenarios
make             MICROPOL.PRG (the game) and SIMTEST.PRG (the simulator without a screen)
make host        the simulator's twins on the PC (build/host16/simtest, build/host32/simtest)
make run         the game in the emulator (build/run)
make test        the checks (tests/check.sh): about 4 minutes on 16 threads
make test-long   the simulator's equality only, 20,000 ticks a case (TICKS=n)
make app         MICROPOLIS.HZA; make test-app installs it from the Desktop and plays
```

Needs: Horizon 0.30, REV $0B (sprites, scrolling with wrap), the blitter, 2 MB free; Lau
for the sounds (without it the game is silent). `MICROPOL.PRG` is 173 KB, the app 1.7 MB
(the art 467 KB, 24 cities, 8 scenarios, 20 sounds).

## Playing

The screen: the menu bar (File, Speed, Disasters, Windows, Options), the date and the funds;
the tools; the demand for residential, commercial and industrial zones (the three bars);
the speed and the city's name; the message line, with the tool's name and cost at its right.
The rest is the city, 40 x 19.5 tiles of 16 pixels, or 80 x 39 of 8 (zoomed out, Z).

| | |
| --- | --- |
| Left button | the tool: click, or drag (roads, rails, power lines, bulldozer) |
| Right button | what is there (the query: zone, density, value, crime, pollution, growth) |
| Screen edges, arrows, the wheel | scroll |
| D R T W K | bulldozer, road, rail (track), wire (power line), park |
| 1 2 3 | residential, commercial, industrial zone |
| P F S E A O N | police, fire station, stadium, seaport, airport, coal and nuclear power |
| Q | query |
| Space, F2, F3, F4 | pause / go on; slow, medium, fast |
| B V G M | the budget, the evaluation, the graphs, the overview map |
| Z | zoom out / in |
| Ctrl+N, Ctrl+O, Ctrl+S | new city, load a city, save |
| Esc | close a window; on the map: quit (with Save and quit) |
| F9 | the state's checksum on the log (the tests) |

The overview map shows the city or one of 13 overlays (residential, commercial, industrial,
power, transport, population density, growth, traffic, pollution, crime, land value, fire
and police coverage); a click on it moves the view there. A new city: the terrain generator
with a number (Generate another), the difficulty (funds $20,000, $10,000, $5,000). Cities
are saved in the app's folder (`NAME.CTY`, upstream's format: upstream's cities load and
ours load in upstream's game); upstream's 24 cities are in `CITIES/`. The 8 scenarios
(Dullsville, San Francisco, Hamburg, Bern, Tokyo, Detroit, Boston, Rio de Janeiro) with
their disasters and goals. Disasters: fire, flood, tornado, earthquake, monster, nuclear
meltdown, air crash (and upstream's random ones unless Options > Disasters is off). The
options: auto budget, auto bulldoze, disasters, sound, auto go-to (the view jumps to where
something happens), animation. Starting it with a `.CTY` (a double click in Files) loads it.

## Implementation

- `engine/`: upstream's C (`src/sim`), cities, scenarios, strings, tiles, sprites, sounds;
  our fork (engine/FORK.md: what was taken, every change)
- `src/port.h`, `proto.h`, `hooks.[ch]`: what upstream took from X11 and Tcl; one tick
  (`port_tick`: upstream's sim_loop once); the state's checksum
- `src/simtest.c`: the simulator alone: the same program on the Atari816 and the PC
- `src/game.c`: the start, the loop, the mouse and keys, the tools, Tcl's commands from the
  engine
- `src/view.c`: the city: a ring of tile slots in the framebuffer that Marga scrolls
  (horizontal and vertical wrap, a split for the panel); each frame the slots whose tile
  changed are drawn from the tile sheet by the blitter. The moving things are 4 bpp
  hardware sprites (a 48 x 48 one is four), and so is the tool's frame
- `src/panel.c`, `dialogs.c`: the panel; the menus and windows, drawn on a page of the
  framebuffer shown instead of the city (over a copy of it)
- `src/data.c`, `tools/mkdata.py`: the art: upstream's XPM pictures made into a sheet of
  4096 x 64 (the 960 tiles of 16 x 16), one of 8 x 8 tiles (each 2 x 2 block's commonest
  colour), the overview's 3 x 3 tiles, the sprites at 4 bpp (full and half size);
  upstream's 16-bit 22 kHz sounds as 8-bit 11 kHz WAV
- `src/fast.s`: the tile animation and the random numbers in assembly
- `tools/host16.py`: the host16 twin's sources (int -> short; from ports/xcom)

Why 640 x 360: the original ran on 640 x 480-class screens with 16-pixel tiles; at 640 x 360
the text (8 x 10) and the menus are as legible as upstream's, the mouse pointer is the
hardware's, and 40 x 19 tiles show a useful part of the 120 x 100 map. The 8-pixel zoom shows
two thirds of the map's width at once.

Speed: one tick (upstream's sim_loop once: a sixteenth of a simulation pass at the fast
speed, the moving things, a quarter of the map's animation) costs 50 ms in a small city,
90-110 ms in Tokyo, 140 ms in Kobe (a dense city of 300,000): a pass of 16 ticks 0.8 to 2.3
s; at the fast speed the game runs a tick every frame it can. PORTING-NOTES.md has the
measurements.

## Tests (make test)

1. The simulator on the Atari816 (SIMTEST.PRG in the emulator) against its two twins on the
   PC (host16: the same engine with a 16-bit int; host32: upstream's types), 5,000 ticks of
   ten cases (four generated cities with a small city laid by the tools, four scenarios, two
   of upstream's cities): the whole state (every map, the histories, the moving things,
   funds, population, the evaluation, the random numbers) equal every 100 ticks in all three.
2. The tools in the game with the mouse and keys (tests/tools.script): every call the game
   made to the engine's tools, made again by simtest on the PC: the same state; four
   pictures (the city, the query window, the zoomed-out view, the overview map) against
   their checksums.
3. Saving: a city loaded and saved by the game, byte for byte the file simtest saves on the
   PC; SIMTEST.PRG's too; the saved map is the map in memory; the file loads again.
4. The Tokyo scenario played at the fast speed for two minutes: the ticks' cost on the log.
5. The windows (budget, evaluation, graphs, a menu, the load window): pictures.

`make test-app`: MICROPOLIS.HZA installed from Files, started from Programs > Games, a city
saved in the app's folder, the app installed again: the saved city is kept.

## Licence

GPL-3 with Electronic Arts' additional terms (engine/COPYING, engine/README); the name under
the Micropolis public name licence (engine/MicropolisPublicNameLicense.md). Upstream's
README puts the art, the cities, the scenarios, the strings and the sounds under the same
licence; they are committed here. Our files: GPL-3, the same terms.
