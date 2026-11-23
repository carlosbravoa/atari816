# XCOM-XT on the Atari816 (stage 5: a playable app)

[XCOM-XT](https://github.com/fmikowski/xcom-xt) is a from-scratch engine for **X-COM: UFO
Defense** (1994) written for 8088 XTs (EGA, CGA, Hercules) and 286 VGA machines: Open
Watcom C (16-bit large model, about 49,000 lines) plus NASM assembly (about 12,900 lines),
GPL-3, alpha 0.5.1. You bring your own copy of the game; its converter (XCOMCONV, Python)
makes the engine's packs from it.

This folder is the port to the Atari816 (Horizon 0.30). **State: a complete, playable
app** (`make app`: XCOM.HZA, no game data in it): the intro, menus, geoscape, base screens,
UFOpaedia, interceptions, battles, debriefings, the end slides; the AdLib music on the
OPL2 (a helper task keeps its tempo while the game computes) and the Sound Blaster effects
on Lau; saves (also inside a battle) in the app's folder. Every screen is checked against
the PC build by `make test`. Battles are still slow in places (PORTING-NOTES.md, "What is
next").

| | State |
| --- | --- |
| Upstream | fetched at a pinned commit (`tools/getsrc.sh`), built through patches (`patches/src-000N-*.patch`, all in `#if defined(XCOM_PORT)`: the port's hooks, sound, screens and three upstream bugs, the speed hooks, fixes) |
| Data | `tools/getdata.sh` runs upstream's XCOMCONV on your copy (GOG works with `--skip-check` and one converter patch); the VGA mode uses 18.3 MB of it |
| Host build (Linux) | the whole engine headless on a model of the DOS machine (`plat/xdos.c`), with DOS's 16-bit `int` (`tools/host16.py`): the reference |
| Atari816 build | `hcc --code large --data far`: XCOM.PRG and MUSD.PRG (the music task) |
| Tests | `make test`: 14 KEYS-script runs of every screen on both builds (same LOG, same pictures pixel for pixel, same saves, open files counted), the real mouse and keyboard three times (the clock as after the start, after 5 minutes, wrapping), a full card, the sound (OPL2 stream and Sound Blaster blocks against the host's, the beat, the volume); `make test-long`: longer runs (a big battle saved and loaded, the defeat slides, the campaign soak); `make test-app`: the app installed and started from the Desktop |
| Screen | 320 x 200 on 320 x 180: the picture stands still, each kind of screen at its own rows (centred, or where its buttons are); the mouse wheel or F5 / F6 move it; the battle view is split (the panel whole below 124 rows of the view); the pointer is a hardware sprite |
| On the board | `make kit`: a measuring kit (XCOM.ARG, `/M` self-timing to `/PC:/`, `/IOB` the card's costs); PORTING-NOTES.md section 4e |

Read [PORTING-NOTES.md](PORTING-NOTES.md): the assessment, the measurements, the plan,
what is next. The player's guide is [app/README.TXT](app/README.TXT) (it goes into the app).

## Build

```sh
sh tools/getsrc.sh                          # upstream/ at the pinned commit (or: make src)
make data GAME="/path/to/X-COM UFO Defense" # data/packs/ from your copy (never in git)
make builds                                 # MUSD.PRG, XCOM.PRG, build/host/xcomhost
make test                                   # host vs Atari816 in the emulator (about 2 min)
make test-long                              # the longer runs
make app                                    # XCOM.HZA: the app, no game data
make test-app                               # installed and started in the emulator
make card                                   # build/card/APPS/XCOM: the app + YOUR data, for your card
make app DATA=1                             # also build/XCOM-DATA.HZA: the same with your data
make run ARGS="VGA NOINTRO"                 # XCOM.PRG in the emulator's shell (build/run)
make host-run ARGS="VGA NOINTRO KEYS $PWD/tests/geo.keys LOG LOG.TXT"
```

On the Atari816 the options `/V` (virtual clock, test pictures), `/T n` (end after n idle
seconds), `/S` (wait for the blitter at once) and `/U n` (n microseconds added to the
clock: a machine on for long) come before the engine's (upstream's `release/MANUAL.TXT`
section 10: `NOINTRO`, `BATTLE`, `MISSION FA1V.PAK`, `SEED n`, `KEYS file`, `LOG file`,
`BENCH`, ...). Without options the game starts in VGA mode with its intro.

## Data

Your own copy of X-COM: UFO Defense (DOS 1.4; the GOG edition, whose fonts differ, works
with `--skip-check`, which the Makefile passes). The packs it makes are for your own use:
`data/` is ignored by git, reference pictures are kept as checksums only, and XCOM.HZA
holds none of them. On the card the app needs `PACKS.VER`, `*.PAK` and `VGA/` in its folder
(`/APPS/XCOM/`); without them it says so on its screen.

Dependencies of the converter: Python 3 and PyYAML.

## Licence

Upstream is GPL-3 (`upstream/COPYING`); the port's own files are GPL-3 too. The game's data
is not part of this repository.
