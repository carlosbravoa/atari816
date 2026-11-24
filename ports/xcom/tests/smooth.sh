#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/smooth.sh (make smooth): what a player feels, with limits: the board measuring kit's
# runs in the emulator (tests/perf.sh: the app's folder, the board's card, the real clock,
# the pointer circling, /M), a battle (tests/perf/smooth.keys: cursor steps and scrolls,
# key bursts, walks, selections, kneeling, shots, the turn's end) and the geoscape
# (tests/perf/geo.keys: a new game, base screens, the clock at 5 s and 1 day), the same
# battle at night (NIGHT: the view's shade at every present: the blitter's colour remap
# from REV $0D, PORTING-NOTES.md 4j), then
# tests/smooth.py on each: the player's longest gap between event polls (the pointer
# stands still) and longest frame (the view stands still while the CPU works; under the
# hourglass, while loading and /M's own report do not count), the battle view's frame
# rates scrolling and walking. Fails over the limits (PORTING-NOTES.md 4h: set from the
# measured figures with about a third of headroom).
cd "$(dirname "$0")/.." || exit 1
O=build/smooth
rm -rf $O && mkdir -p $O
sh tests/perf.sh $O/bat 140 "/M /MN PERFSM /W /Q 120 NOINTRO BATTLE SEED 6 MISSION FA1V.PAK RACE RSV.PAK KEYS PSMOOTH.KEY" > $O/bat.log &
sh tests/perf.sh $O/night 140 "/M /MN PERFSN /W /Q 120 NOINTRO BATTLE SEED 6 MISSION FA1V.PAK RACE RSV.PAK NIGHT KEYS PSMOOTH.KEY" > $O/night.log &
sh tests/perf.sh $O/geo 120 "/M /MN PERFGEO /W /Q 100 NOINTRO KEYS PGEO.KEY" > $O/geo.log &
wait
fail=0
echo "== a battle (tests/perf/smooth.keys)"
python3 tests/smooth.py $O/bat/console.txt --gap 120 --frame 250 || fail=1
echo "== the same battle at night"
grep -a "xcom: night shade" $O/night/console.txt | head -1
python3 tests/smooth.py $O/night/console.txt --gap 120 --frame 250 || fail=1
echo "== the geoscape (tests/perf/geo.keys)"
python3 tests/smooth.py $O/geo/console.txt --gap 450 --frame 250 || fail=1
[ $fail = 0 ] && echo "smooth: passed" || echo "smooth: FAILED"
exit $fail
