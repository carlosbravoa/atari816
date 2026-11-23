#!/bin/sh
# tests/hostframes.sh - after make test: the replays' pictures (build/test/frames) against
# the same ticks drawn by upstream SDLPoP on the PC (make host: data/sdlpop/prince-ref),
# pixel for pixel (tests/cmpframe.py; the differences in build/test/host/diff-*.png)
cd "$(dirname "$0")/.." || exit 1
test -x data/sdlpop/prince-ref || { echo "hostframes: no data/sdlpop/prince-ref (make host)"; exit 1; }
fail=0
mkdir -p build/test/host
for r in tests/replays/*.p1r; do
  n=$(basename "$r" .p1r)
  con=build/test/val-$n/console.txt
  [ -f "$con" ] || { echo "hostframes: no $con (make test first)"; exit 1; }
  ticks=$(tr -d '\r' < "$con" | grep -a '^prince: shot' | awk '{print $5}' | paste -sd,)
  [ -n "$ticks" ] || continue
  (cd data/sdlpop && SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy POP_REF_SHOTS=$ticks \
     POP_REF_DIR=../../build/test/host ./prince-ref validate ../../$r > /dev/null 2>&1)
  tr -d '\r' < "$con" | grep -a '^prince: shot' | while read a b k c tick d vy g; do
    mv build/test/host/frame-$tick.png build/test/host/$n-$tick.png
    python3 tests/cmpframe.py build/test/frames/$n-$tick.png build/test/host/$n-$tick.png \
      $vy $g --diff build/test/host/diff-$n-$tick.png || echo FAIL > build/test/host/failed
  done
done
if [ -f build/test/host/failed ]; then echo "hostframes: FAILED"; rm build/test/host/failed; exit 1; fi
echo "hostframes: every picture as the PC's"
