#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/speed.sh [PRG]: what the player feels, measured (make speed): upstream's BENCH
# with the real clock (no /V: the emulator's time is the board's), by day and at night,
# and a quick battle's alien turn (FA5V, 11 sectoids, SEED 2: tests/prof/alien.keys).
# Reports the figures; fails only when a run does not end or BENCH's own checks fail
# (never on time: the figures are for reading, PORTING-NOTES.md "Speed").
cd "$(dirname "$0")/.." || exit 1
PRG=${1:-XCOM.PRG}
O=build/speed
rm -rf $O && mkdir -p $O
printf '0 wait xcom: end\n' > $O/end.script
fail=0
run() {         # NAME SECONDS ARGS [run816 options]
  n=$1 s=$2 a=$3; shift 3
  PRG=$PRG sh tests/xrun.sh $O/$n $s "$a" "$@" > /dev/null
}
run day 400 "VGA NOINTRO BENCH MISSION FA1V.PAK RACE RSV.PAK LOG BENCHLOG.TXT" --script $O/end.script &
run night 400 "VGA NOINTRO BENCH NIGHT MISSION FA1V.PAK RACE RSV.PAK LOG BENCHLOG.TXT" --script $O/end.script &
run alien 200 "VGA NOINTRO BATTLE SEED 2 MISSION FA5V.PAK RACE RSV.PAK LOG ALIEN.TXT KEYS P.KEY" \
  --file tests/prof/alien.keys:/GAMES/XCOM/P.KEY &
wait
for n in day night; do
  B=$O/$n/card/GAMES/XCOM/BENCH.TXT
  [ -f $B ] || { echo "speed: $n: no BENCH.TXT"; fail=1; continue; }
  echo "== BENCH ($n, real clock)"
  grep -a "average full redraw\|^20,20 level 0:\|^view 20,20 levels 0-3\|scroll by one\|cursor step\|^unit step, one\|present view:\|path search unit 0\|360 voxel lines:\|8 aims\|smoke + 16 fire tiles:" $B | sed 's/^/  /' | sort -u
  # (the redraw checks hold whatever the clock: a full redraw is the same picture)
  grep -a "full redraw DIFFERENT\|MISMATCH" $B && fail=1
done
echo "== a quick battle (FA5V, SEED 2)"
grep -a "xcom: battle:" $O/alien/console.txt | sed 's/^/  /'
grep -a "walked\|alien turn" $O/alien/card/GAMES/XCOM/ALIEN.TXT | sed 's/^/  /' || fail=1
[ $fail = 0 ] && echo "speed: done" || echo "speed: FAILED"
exit $fail
