# XCOM-XT on the Atari816 (stage 1: assessment and foundation)

[XCOM-XT](https://github.com/fmikowski/xcom-xt) is a from-scratch engine for **X-COM: UFO
Defense** (1994) written for 8088 XTs (EGA, CGA, Hercules) and 286 VGA machines: Open
Watcom C (16-bit large model, about 49,000 lines) plus NASM assembly (about 12,900 lines),
GPL-3, alpha 0.5.1. You bring your own copy of the game; its converter (XCOMCONV, Python)
makes the engine's packs from it.

This folder is the port to the Atari816 (Horizon 0.30). **State: stage 1 of 5.**

| | State |
| --- | --- |
| Upstream | fetched at a pinned commit (`tools/getsrc.sh`), built through one patch (`patches/src-0001-port.patch`: about 180 lines added in 13 files, all in `#if defined(XCOM_PORT)`) |
| Data | `tools/getdata.sh` runs upstream's XCOMCONV on your copy (GOG works with `--skip-check` and one converter patch) |
| Host build (Linux) | the whole engine runs headless on a model of the DOS machine (`plat/xdos.c`) with upstream's assembly in C (`plat/`): start menu, new game, geoscape, basescape, UFOpaedia, graphs, quick battles (upstream's BENCH self-checks and voxel-line checks pass), driven by upstream's own KEYS scripts; `make check-host` compares 14 pictures by checksum |
| Atari816 build | every upstream file compiles with cc816 (`hcc --code large`, 578 KB of code); it does not link yet: the main bank is 18.4 KB too small, and the engine needs far data (PORTING-NOTES.md, "SDK needs") |
| Measured on the 816 | the VGA path's costs with the real packs (`tests/bench816`): PORTING-NOTES.md, "Measured" |

Read [PORTING-NOTES.md](PORTING-NOTES.md): the assessment, the measurements, the plan.

## Build

```sh
sh tools/getsrc.sh                          # upstream/ at the pinned commit (or: make src)
make data GAME="/path/to/X-COM UFO Defense" # data/packs/ from your copy (never in git)
make host                                   # build/host/xcomhost (gcc; Linux)
make host-run ARGS="VGA NOINTRO KEYS $PWD/tests/geo.keys LOG LOG.TXT"
                                            # pictures in build/host/shots/*.ppm, the
                                            # engine's log in data/packs/LOG.TXT
make                                        # XCOM.PRG (fails at the link in stage 1)
```

The host runs in the packs folder (as the DOS program runs in its game folder); arguments
are upstream's (`release/MANUAL.TXT` section 10: `VGA`, `NOINTRO`, `BATTLE`, `MISSION
FA1V.PAK`, `SEED n`, `KEYS file`, `LOG file`, `BENCH`, ...). Its clock is virtual: a run
gives the same pictures on any machine. `make check-host` runs `tests/host.runs`.

## Data

Your own copy of X-COM: UFO Defense (DOS 1.4; the GOG edition, whose fonts differ, works
with `--skip-check`, which the Makefile passes). The packs it makes (43 MB; the VGA mode
uses `data/packs/*.PAK` and `data/packs/VGA/`) are for your own use: `data/` is ignored by
git, and reference pictures will be kept as checksums only.

Dependencies of the converter: Python 3 and PyYAML.

## Licence

Upstream is GPL-3 (`upstream/COPYING`); the port's own files are GPL-3 too. The game's data
is not part of this repository.
