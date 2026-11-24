# This fork of Micropolis

This folder is **our fork of the simulator of Micropolis**, the GPL-3 release of the
original SimCity source (Will Wright, Electronic Arts; the Unix/OLPC port by Don Hopkins),
from <https://github.com/SimHacker/micropolis>, commit
`c98f6b08519887b450d9be198bfca5237aab6d0c` (10 February 2026; `COMMIT`). It is the C tree
`micropolis-activity/` (not MicropolisCore, the C++ rewrite). Micropolis is a registered
trademark of Micropolis Corporation (Micropolis GmbH) and is licensed here as a courtesy of
the owner (`MicropolisPublicNameLicense.md`); the name SimCity is Electronic Arts' and is not
used for the program.

## The files taken (the pristine base)

`ports/simcity/tools/vendor.sh UPSTREAM OUT` copies exactly these from a clone at that
commit (nothing of upstream's is built or run):

| Here | Upstream (`micropolis-activity/` unless said) |
| --- | --- |
| `README`, `COPYING` | `README` (the licence notices, EA's additional terms), `COPYING` (GPL-3) |
| `MicropolisPublicNameLicense.md` | the repository's root |
| `src/sim/*.c` | `src/sim/`: `s_alloc s_disast s_eval s_fileio s_gen s_init s_msg s_power s_scan s_sim s_traf s_zone rand g_ani g_smmaps w_sprite w_tool w_budget w_graph w_update w_util w_eval w_con` (23 files) |
| `src/sim/headers/*.h` | `src/sim/headers/`: `sim mac macros view animtab` |
| `cities/*.cty` | `cities/` (24 cities) |
| `res/snro.111` ... `888`, `res/stri.*` | `res/` (the 8 scenarios, the string lists) |
| `res/sounds/*.wav` | `res/sounds/` (49 sounds; not the shell script `player`) |
| `images/tiles.xpm`, `tilessm.xpm`, `obj*.xpm` | `images/` (the 960 tiles, the overview's tiles, the 8 moving things' frames) |

Not taken: the Tcl/Tk front end (`res/*.tcl`, `src/tcl*`, `src/tk*`), the X11 drawing and
Tcl glue (`src/sim/g_*.c` but `g_ani.c`, `sim.c`, `w_*.c` but those above), `random.c`
(unused), the terrain generator in `src/sim/terrain/` (the game uses `s_gen.c`'s), the
other images, `micropolis-graphics/`, MicropolisCore and the rest of the repository.
`g_smmaps.c` is not built (the overview map is the port's `src/dialogs.c`); it is kept as
the reference of upstream's map colours.

The licence: upstream's `README` puts the source **and** "all of the non-text files in this
source code release, including cities/*, images/*, res/hexa.*, res/snro.*, res/sounds/*,
res/stri.*" under GPL-3 with EA's additional terms (no trademark rights, keep the notices,
mark modified versions as such, the disclaimer). So the art, the cities, the scenarios and
the sounds are committed here (unlike the data of other ports).

## The builds

| Build | How | Tested |
| --- | --- | --- |
| the Atari816 (`MICROPOL.PRG`, `SIMTEST.PRG`) | `make` in `ports/simcity` (hcc, `--code large`) | `make test`, `make test-app` (the emulator) |
| host16 (`build/host16/simtest`) | `make host`: every file through `tools/host16.py` (int -> short) and gcc | the reference of `make test` |
| host32 (`build/host32/simtest`) | `make host`: the files as they are, gcc (int 32 bits, long 32 by `port.h`) | upstream's own types: equal to host16 in every case of `make test` |

`MICROPOLIS_PORT` is defined in all three; upstream's X11 build is not kept working (its
code stays in `#if !defined(MICROPOLIS_PORT)` groups where it was replaced, for reading).

## Our changes, by topic

Compare with the pristine base (`git diff <its commit> -- ports/simcity/engine`).

**C for cc816 (every build).** cc816 has no implicit int: every function definition got its
return type (`int` where it returns a value, else `void`; 248 functions), `register x;`
locals `register int x;`, a few calls given their prototype's arguments (`DoFreePop(Ch9)`,
`MakeShipHere(x, y)` with a third 0, `ToolUp` of a void `ToolDrag`), the static helpers of
`w_con.c` declared. `src/proto.h` (outside this folder, made by `tools/mkproto.py`) declares
every function: upstream declares few, and a function returning a pointer or a 32-bit value
needs a declaration where `int` is not that wide. `ZonePlop` returns TRUE at its end (it fell
off; no caller reads it).

**The headers.** `sim.h` takes `port.h` (`ports/simcity/src`) instead of X11, Tcl and Tk;
`view.h` is not read (port.h has the views' few fields the engine still touches, and
upstream's `SimSprite`). Upstream's declarations that `proto.h` replaces are in
`#if !defined(MICROPOLIS_PORT)`.

**Far memory (the Atari816).** `MAPFAR` (`__far` on the Atari816, nothing on the PC) on the
map (`Map`, 24,000 bytes), the 2 x 2 and 4 x 4 maps, the histories and the power scan's
stack: `s_alloc.c` puts them all in one block (`port_far_alloc`: a bank of their own). The
pointers into them (`w_con.c`'s `TileAdrPtr`, `w_tool.c`'s `tilePtr`, `g_ani.c`'s,
`drawMonth`'s) are `MAPFAR` too.

**16-bit int faults of upstream** (each also wrong on any 16-bit compiler; the fixes give
upstream's 32-bit results; found by comparing the Atari816's state with the PC's):

1. `rand.c` `sim_rand`: `SIM_RAND_MAX + 1` is 0 with a 16-bit int (0xffff is unsigned), the
   modulus a division by zero; its result 0-65,535 does not fit an int: unsigned QUAD
   arithmetic, an unsigned result.
2. `s_sim.c` `Rand`, `Rand16`, `Rand16Signed`: the same numbers as negative ints (random
   numbers below 0, `Rand(n)` out of its range): unsigned arithmetic; the seed path
   (`SeedRand`, `GenerateSomeCity`, `GenerateMap`) unsigned QUAD.
3. `s_sim.c` `GetBoatDis`: `dist = 99999` is negative in a 16-bit int: every drawbridge
   opened at every pass (32,767 now).
4. `s_eval.c` `GetAssValue`: `PolicePop * 1000` and its sisters overflowed (33 police
   stations); `s_sim.c` `CollectTax`: `PolicePop * 100`, `RoadTotal + RailTotal * 2` the same:
   QUAD products.
5. `w_budget.c` `DoBudgetNow`: `(int)(FireFund * firePercent)` cut a fund over 32,767:
   `(QUAD)`.
6. `w_util.c` `SetYear`: `year * 48` (QUAD now).
7. `w_update.c`: `int megalinium = 1000000` (QUAD); the funds printed with `%d` of a QUAD
   (`%ld` on the Atari816: `PRIQ` in `proto.h`; also `w_eval.c`, `w_budget.c`).

**Upstream's bugs that make results depend on the machine** (every build):

- `s_eval.c` `VoteProblems` reads `ProblemTable[PROBNUM]`, one past the array (and may count
  a vote there): the arrays have one more element, always 0.
- `s_eval.c` `GetUnemployment`: a float out of a short's range converted to a short
  (undefined): through 32 bits.
- `s_fileio.c` read 32-bit values as `*(QUAD *)(MiscHis + n)` (QUAD 32 bits, aligned, the
  byte order of the machine): the port reads and writes the same file format word by word
  (big-endian, as upstream's files are), through a small buffer to the far map; upstream's
  second, unswapped reading of the budget's percents (overwritten by InitFundingLevel) left
  out.

**The UI glue.** Tcl's `Eval` stays: `port_eval` (the front end) reads the commands
(`UISetMessage {...}`, `UIShowBudgetAndWait`, ...). `MakeSound` the same. Upstream's
functions from files not taken (`SetFunds`, `Spend`, `DropFireBombs`, `DoEarthQuake`,
`TickCount`, `GetIndString`, ...) are in `ports/simcity/src/hooks.c`; the `stri.*` strings
are compiled in (`tools/mkstri.py`). Chalk and the eraser (they drew on the X view) are left
out; the Tcl command tables of `w_graph.c`, `w_sprite.c` and the X drawing of the sprites
are in `#if !defined(MICROPOLIS_PORT)`. `gettimeofday` (the random seed of a new game)
became `port_seed()`.

**Speed (the Atari816; the same results):** `g_ani.c`'s loop and `rand.c`'s `sim_rand` in
assembly (`ports/simcity/src/fast.s`), `Rand` keeps its last range's limit, the power map's
bit from a table (`POWERBIT`), the traffic search's neighbours through one pointer
(`GetFromMap`, `DriveDone`). The tick (`hooks.c`, `port_tick`) animates a quarter of the
map at a time.
