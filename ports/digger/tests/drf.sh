#!/bin/sh
# tests/drf.sh - upstream's recorded games (tests/drf/*.drf, from upstream's tests/data) played
# back in the emulator at full speed (/Q /S:0 /E:FILE, as upstream's scripts/do-test-run.sh
# "quick"), each compared with upstream's result (tests/drf/*.drf.out: the score, the level
# and the frames at the end): the game logic must be the PC's to the frame.
#   tests/drf.sh [HORIZON] [NAMES...]       (all of them by default; in parallel)
HZ=${1:-../../horizon}; shift
cd "$(dirname "$0")/.." || exit 1
names=${*:-$(cd tests/drf && ls *.drf | sed 's/\.drf$//')}
fail=0
for n in $names; do
  up=$(echo "$n" | tr a-z A-Z)
  (python3 ../../sdk/tools/run816.py DIGGER.PRG --horizon "$HZ" --mode shell \
     --args "/Q /S:0 /E:$up.DRF" --file DIGGER.DAT:/APPS/DIGGER.DAT \
     --file tests/drf/$n.drf:/APPS/$up.DRF --seconds 1500 --out build/drf/$n >/dev/null 2>&1) &
done
wait
for n in $names; do
  got=$(grep -a '^score=' build/drf/$n/console.txt | tr -d '\r')
  want=$(cat tests/drf/$n.drf.out)
  t=$(grep -a '^digger: ' build/drf/$n/console.txt | tr -d '\r')
  if [ "$got" = "$want" ]; then echo "PASS  $n: $got ($t)"; else echo "FAIL  $n: got '$got', upstream '$want'"; fail=1; fi
done
exit $fail
