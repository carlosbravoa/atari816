#!/bin/sh
# tests/mkref.sh - the reference results (tests/ref/NAME.ref) from upstream SDLPoP built on
# the PC (make host): each replay validated, its state every 10 ticks (host/refhook.c) and
# upstream's own end lines. Text only: no game data in them.
set -e
cd "$(dirname "$0")/.."
test -x data/sdlpop/prince-ref || { echo "mkref: no data/sdlpop/prince-ref (make host)"; exit 1; }
mkdir -p tests/ref
sh tests/replays.sh > /dev/null || exit 1
for r in build/replays/*.p1r; do
  n=$(basename $r .p1r)
  (cd data/sdlpop && SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy POP_REF_EVERY=10 \
     ./prince-ref validate ../../$r 2>&1) |
    grep -E "^ref:|^Replay (started|ended)|^Kid is|^Remaining|^Elapsed|^Play duration" > tests/ref/$n.ref
  echo "mkref: tests/ref/$n.ref: $(grep -c '^ref:' tests/ref/$n.ref) states"
done
