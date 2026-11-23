#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/prof.sh [HORIZON] [PRG]: where the Atari816's time goes on each kind of screen, with
# the real clock (as a player has it): the program idle at the start menu, the geoscape
# with its clock running at 5 s (geo) and at 1 day (geoday: key 4), a base screen, a
# quick battle's view idle. For each: a profile of 10 s (run816 --prof, sdk/tools/
# prof816.py), its top rows in build/prof/NAME.txt.
HZ=${1:-../../horizon}
PRG=${2:-XCOM.PRG}
cd "$(dirname "$0")/.." || exit 1
O=build/prof
rm -rf $O
mkdir -p $O
FILES=
for f in data/packs/*.PAK data/packs/PACKS.VER; do FILES="$FILES --file $f:/GAMES/XCOM/$(basename "$f")"; done
for f in data/packs/VGA/*; do FILES="$FILES --file $f:/GAMES/XCOM/VGA/$(basename "$f")"; done
# NAME  FROM  TO  the engine's options (KEYS P.KEY: tests/prof/NAME.keys)
while read -r name from to args; do
  case "$name" in ''|\#*) continue ;; esac
  k=
  [ -f tests/prof/$name.keys ] && k="--file tests/prof/$name.keys:/GAMES/XCOM/P.KEY"
  echo "$args" > $O/$name.arg
  python3 ../../sdk/tools/run816.py $PRG --horizon "$HZ" --mode shell \
    --dest /GAMES/XCOM/XCOM.PRG --cd /GAMES/XCOM --args "@P.ARG" $FILES $k \
    --file $O/$name.arg:/GAMES/XCOM/P.ARG --seconds $to --prof $O/$name.prof \
    --prof-from $from --prof-to $to --shot $to --out $O/$name > $O/$name.log 2>&1 &
done <<'RUNS'
menu    10 20  VGA NOINTRO
geo     40 50  VGA NOINTRO KEYS P.KEY
geoday  40 50  VGA NOINTRO KEYS P.KEY
base    40 50  VGA NOINTRO KEYS P.KEY
battle  40 50  VGA NOINTRO BATTLE SEED 1 MISSION FA1V.PAK RACE RSV.PAK
RUNS
wait
for n in menu geo geoday base battle; do
  python3 ../../sdk/tools/prof816.py --counts $O/$n.prof --map $(dirname $PRG)/build/816/XCOM.map \
    --prg $PRG --top 16 > $O/$n.txt 2>&1
  echo "== $n"; head -24 $O/$n.txt
done
