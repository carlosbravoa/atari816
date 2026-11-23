#!/bin/sh
# tests/mklevels.sh [--refs] - the level replays (and the shadow's: tests/levels/shadow.txt,
# tests/patchp1r.py), from upstream SDLPoP built on the PC (make
# host): for each level 1-14 a replay recorded from the level's start (tests/levels/idle.txt:
# 40 ticks standing still; "record N seed=1") into build/levels/levN.p1r, validated there:
# the state every 10 ticks, the level structure's checksum and start room ("lvl:" lines,
# host/refhook.c's POP_REF_LEVEL), upstream's end lines (build/levels/levN.ref) and the
# picture at tick 40 (build/levels/host-N.png). A replay holds a savestate, and so the
# level's map: they stay out of git (build/); --refs: the text results (no game data) are
# written as tests/levels/levN.ref too, the reference tests/levels.sh holds the PC to.
set -e
cd "$(dirname "$0")/.."
test -x data/sdlpop/prince-ref || { echo "mklevels: no data/sdlpop/prince-ref (make host)"; exit 1; }
mkdir -p build/levels
for n in 1 2 3 4 5 6 7 8 9 10 11 12 13 14; do
  (cd data/sdlpop && SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy POP_REF_SILENT=1 POP_REF_FAST=1 \
     POP_REF_INPUT=../../tests/levels/idle.txt POP_REF_REC=../../build/levels/lev$n.p1r \
     ./prince-ref record $n seed=1 > /dev/null 2>&1)
  (cd data/sdlpop && SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy POP_REF_EVERY=10 POP_REF_LEVEL=1 \
     POP_REF_SHOTS=40 POP_REF_DIR=../../build/levels ./prince-ref validate ../../build/levels/lev$n.p1r 2>&1) |
    grep -E "^ref:|^lvl:|^Replay (started|ended)|^Kid is|^Remaining|^Elapsed|^Play duration" |
    grep -v "^ref: shot" > build/levels/lev$n.ref
  mv build/levels/frame-40.png build/levels/host-$n.png
  [ "$1" = --refs ] && cp build/levels/lev$n.ref tests/levels/lev$n.ref
  echo "mklevels: level $n: $(grep '^lvl:' build/levels/lev$n.ref), $(grep -c '^ref:' build/levels/lev$n.ref) states"
done
# the shadow (level 6, room 1: tests/levels/shadow.txt), its pictures at ticks 20 and 40
(cd data/sdlpop && SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy POP_REF_SILENT=1 POP_REF_FAST=1 \
   POP_REF_INPUT=../../tests/levels/shadow.txt POP_REF_REC=../../build/levels/shadow0.p1r \
   ./prince-ref record 6 seed=1 > /dev/null 2>&1)
python3 tests/patchp1r.py build/levels/shadow0.p1r build/levels/shadow.p1r 18 66 118 0
(cd data/sdlpop && SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy POP_REF_EVERY=2 \
   POP_REF_SHOTS=20,40 POP_REF_DIR=../../build/levels ./prince-ref validate ../../build/levels/shadow.p1r 2>&1) |
  grep -E "^ref:|^Replay (started|ended)|^Kid is|^Remaining|^Elapsed|^Play duration" |
  grep -v "^ref: shot" > build/levels/shadow.ref
mv build/levels/frame-20.png build/levels/host-shadow-20.png
mv build/levels/frame-40.png build/levels/host-shadow-40.png
[ "$1" = --refs ] && cp build/levels/shadow.ref tests/levels/shadow.ref
echo "mklevels: the shadow: $(grep -c '^ref:' build/levels/shadow.ref) states"
