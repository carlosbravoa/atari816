# XCOM-XT on the Atari816 (stage 1: assessment and foundation)

[XCOM-XT](https://github.com/fmikowski/xcom-xt) is a from-scratch engine for **X-COM: UFO
Defense** (1994) written for 8088 XTs (EGA, CGA, Hercules) and 286 VGA machines: Open
Watcom C (16-bit large model, about 49,000 lines) plus NASM assembly (about 12,900 lines),
GPL-3, alpha 0.5.1. You bring your own copy of the game; its converter (XCOMCONV, Python)
makes the engine's packs from it.

This folder is the port to the Atari816 (Horizon 0.30). **State: stage 4a of 5**: the
game runs (menus, geoscape, base screens, UFOpaedia, graphs, battles), checked against the
host build by `make test`; no sound, no intro yet; the battle view is drawn by the blitter
but a full redraw still takes 0.2-0.4 s.

| | State |
| --- | --- |
| Upstream | fetched at a pinned commit (`tools/getsrc.sh`), built through one patch (`patches/src-0001-port.patch`: about 180 lines added in 13 files, all in `#if defined(XCOM_PORT)`) |
| Data | `tools/getdata.sh` runs upstream's XCOMCONV on your copy (GOG works with `--skip-check` and one converter patch) |
| Host build (Linux) | the whole engine headless on a model of the DOS machine (`plat/xdos.c`), with DOS's 16-bit `int` (`tools/host16.py`): the reference |
| Atari816 build | `hcc --code large --data far`: XCOM.PRG 846 KB; the main bank 58.6 of 65 KB |
| Tests | `make test`: upstream's KEYS scripts (new game and geoscape, a quick battle, a save and load, BENCH) on both builds with a virtual clock: the same LOG, the same pictures at the same times (the emulator's screen pixel for pixel), the same save file byte for byte; and the real mouse and keyboard through Horizon |
| Screen | 320 x 200 on 320 x 180: every screen pans with the pointer; the battle view is split (the panel whole below 124 rows of the view) |
| Speed | idle 77 % on idle screens (it was 2 %); battle: full redraw 0.21 s (one level) / 0.42 s (four), scroll 0.05-0.11 s, cursor 21 ms (it was 1.3 / 1.9 s, 0.9 s, 81 ms) |

Read [PORTING-NOTES.md](PORTING-NOTES.md): the assessment, the measurements, the plan.

## Build

```sh
sh tools/getsrc.sh                          # upstream/ at the pinned commit (or: make src)
make data GAME="/path/to/X-COM UFO Defense" # data/packs/ from your copy (never in git)
make host                                   # build/host/xcomhost (gcc; Linux)
make host-run ARGS="VGA NOINTRO KEYS $PWD/tests/geo.keys LOG LOG.TXT"
                                            # pictures in build/host/shots/*.ppm, the
                                            # engine's log in data/packs/LOG.TXT
make                                        # XCOM.PRG (hcc --code large --data far)
make test                                   # host vs Atari816 in the emulator (tests/runs)
make run ARGS="VGA NOINTRO"                 # XCOM.PRG in the emulator's shell (build/run)
```

The host runs in the packs folder (as the DOS program runs in its game folder); arguments
are upstream's (`release/MANUAL.TXT` section 10: `VGA`, `NOINTRO`, `BATTLE`, `MISSION
FA1V.PAK`, `SEED n`, `KEYS file`, `LOG file`, `BENCH`, ...). Its clock is virtual: a run
gives the same pictures on any machine. `make check-host` runs `tests/runs` on the host alone. On the Atari816 the options `/V` (virtual clock, test pictures), `/T n` (end after n idle seconds) and `/S` (wait for the blitter at once) come before the engine's.

## Data

Your own copy of X-COM: UFO Defense (DOS 1.4; the GOG edition, whose fonts differ, works
with `--skip-check`, which the Makefile passes). The packs it makes (43 MB; the VGA mode
uses `data/packs/*.PAK` and `data/packs/VGA/`) are for your own use: `data/` is ignored by
git, and reference pictures will be kept as checksums only.

Dependencies of the converter: Python 3 and PyYAML.

## Licence

Upstream is GPL-3 (`upstream/COPYING`); the port's own files are GPL-3 too. The game's data
is not part of this repository.
