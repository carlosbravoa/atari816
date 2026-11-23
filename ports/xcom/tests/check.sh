#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/check.sh [HORIZON] [--refs]: make test. Each run of tests/runs (upstream's KEYS
# scripts: a new game, the geoscape, base screens, UFOpaedia, graphs; a quick battle):
#
#   1. on the host build (the reference, build/host/xcomhost: the engine on Linux with the
#      virtual clock): its LOG, its pictures (the model's test pictures, plat.h "test
#      runs"); the pictures' checksums against tests/host.md5 (the reference itself has not
#      moved: the data's pictures are not in git, only their checksums)
#   2. on the Atari816 in the emulator (XCOM.PRG /V: the same virtual clock), in parallel:
#      the same LOG line for line (tests/compare.py: the lines that may differ, and why),
#      the same pictures at the same virtual times (the model's checksum of A000 and the
#      DAC, printed by both), and what the emulator showed at each (the 320 x 180 shown
#      of the 320 x 200 at the pan printed) equal pixel for pixel to the host's picture
#
# --refs: write tests/host.md5 anew (look at the pictures first). The packs must be in
# data/packs (make data).
HZ=${1:-../../horizon}
REFS=$2
cd "$(dirname "$0")/.." || exit 1
fail=0
ok() { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fail=1; }
O=build/test
rm -rf $O
mkdir -p $O

# ---------------------------------------------------------------- the card's files
FILES=
for f in data/packs/*.PAK data/packs/PACKS.VER; do FILES="$FILES --file $f:/GAMES/XCOM/$(basename "$f")"; done
for f in data/packs/VGA/*; do FILES="$FILES --file $f:/GAMES/XCOM/VGA/$(basename "$f")"; done

# ---------------------------------------------------------------- 1. the host
while read -r name args; do
  case "$name" in ''|\#*) continue ;; esac
  mkdir -p $O/$name
  sh tests/hostrun.sh "$name" $O/$name/host $args > $O/$name/host.txt 2>&1 || true
  [ -d $O/$name/host ] || { bad "$name: the host run"; continue; }
done < tests/runs
(cd $O && for n in */host/shot*.ppm; do md5sum "$n"; done | sed 's|/host/|/|') > $O/host.md5
if [ "$REFS" = --refs ]; then
  cp $O/host.md5 tests/host.md5
  echo "tests/host.md5 written ($(wc -l < $O/host.md5) pictures)"
elif cmp -s tests/host.md5 $O/host.md5; then
  ok "the host's reference runs: $(wc -l < $O/host.md5) pictures as tests/host.md5"
else
  bad "the host's reference runs: pictures not as tests/host.md5:"
  diff tests/host.md5 $O/host.md5 | head -6
fi

# ---------------------------------------------------------------- 2. the Atari816
pids=
while read -r name args; do
  case "$name" in ''|\#*) continue ;; esac
  U=$(echo "$name" | tr a-z A-Z)
  # (BENCH reads the back buffer behind the blitter's back: /S waits for it at once)
  S=; case " $args " in *" BENCH "*) S=/S ;; esac
  K=; [ -f tests/$name.keys ] && K="KEYS $U.KEY"
  echo "/V /T 5 $S $args $K" > $O/$name/$U.ARG
  printf '0 wait xcom: end\n' > $O/$name/end.script
  python3 ../../sdk/tools/run816.py XCOM.PRG --horizon "$HZ" --mode shell \
    --dest /GAMES/XCOM/XCOM.PRG --cd /GAMES/XCOM --args "@$U.ARG" $FILES \
    $( [ -f tests/$name.keys ] && echo --file tests/$name.keys:/GAMES/XCOM/$U.KEY) --file $O/$name/$U.ARG:/GAMES/XCOM/$U.ARG \
    --script $O/$name/end.script --shot-on "xcom: shot" --seconds ${XCOM_SECONDS:-400} \
    --out $O/$name/816 > $O/$name/run816.log 2>&1 &
  pids="$pids $!"
done < tests/runs
wait $pids

# ---------------------------------------------------------------- 3. the real input
# Horizon's keyboard and mouse in full screen, the real clock, no KEYS script
# (tests/input.script): start menu, New Game, the difficulty, a base placed by a click
# on the globe and Enter, the base screen by its button, back by GEOSCAPE (the pan
# brings the bottom rows in), G for the graphs; the engine's LOG says each happened
echo "VGA NOINTRO LOG INPUT.TXT" > $O/INPUT.ARG
python3 ../../sdk/tools/run816.py XCOM.PRG --horizon "$HZ" --mode shell \
  --dest /GAMES/XCOM/XCOM.PRG --cd /GAMES/XCOM --args "@INPUT.ARG" $FILES \
  --file $O/INPUT.ARG:/GAMES/XCOM/INPUT.ARG --script tests/input.script --seconds 70 \
  --out $O/input > $O/input.log 2>&1 &
ipid=$!

while read -r name args; do
  case "$name" in ''|\#*) continue ;; esac
  log=$(echo "$args" | sed -n 's/.*LOG \([^ ]*\).*/\1/p')
  python3 tests/compare.py $name $O/$name "$log" || fail=1
done < tests/runs

wait $ipid
L=$O/input/card/GAMES/XCOM/INPUT.TXT
okl=1
for w in "new game, difficulty Beginner" "X-COM base operational" "BASE menu: 11 buttons" \
         "GRAPHS UFO areas"; do
  grep -q "$w" $L 2>/dev/null || { bad "the real input: no '$w' in INPUT.TXT"; okl=0; }
done
grep -aq '\[kill\]' $O/input/console.txt && { bad "the real input: $(grep -a '\[kill\]' $O/input/console.txt)"; okl=0; }
[ $okl = 1 ] && ok "the real input (mouse and keys through Horizon): new game, base placed, base screen, back, graphs"

if [ $fail = 0 ]; then echo "check: all passed"; else echo "check: FAILED"; fi
exit $fail
