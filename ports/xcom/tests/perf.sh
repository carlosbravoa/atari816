#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/perf.sh OUT SECONDS "XCOM.ARG's text" [run816 options]: the board measuring kit
# (README.md "Measuring on the board") tried in the emulator: the app's folder as on the
# board (/APPS/XCOM: XCOM.PRG, MUSD.PRG, the packs, tests/perf/*.keys as P*.KEY), XCOM.ARG
# with the text, the program started WITHOUT options (as from the Desktop), the PC link's
# folder at OUT/pc (the /PC:/ copies land there). Real clock. CARD=slow: the board's card
# speed (emu816 --card-kbps 170:100, PC link 100:55).
cd "$(dirname "$0")/.." || exit 1
export PATH=$HOME/.local/bin:$PATH
O=$1; SEC=$2; ARGS=$3; shift 3
rm -rf $O; mkdir -p $O/pc
F=
for f in data/packs/*.PAK data/packs/PACKS.VER MUSD.PRG; do F="$F --file $f:/APPS/XCOM/$(basename $f)"; done
for f in data/packs/VGA/*; do F="$F --file $f:/APPS/XCOM/VGA/$(basename $f)"; done
for f in tests/perf/*.keys; do n=$(basename $f .keys | tr a-z A-Z); F="$F --file $f:/APPS/XCOM/P$n.KEY"; done
printf '%s\n' "$ARGS" > $O/XCOM.ARG
S=
[ "$CARD" = slow ] && S="--emu-arg --card-kbps --emu-arg 170:100 --emu-arg --pc-kbps --emu-arg 100:55"
python3 ../../sdk/tools/run816.py ${PRG:-XCOM.PRG} --horizon ../../horizon --mode shell \
  --dest /APPS/XCOM/XCOM.PRG --cd /APPS/XCOM --file $O/XCOM.ARG:/APPS/XCOM/XCOM.ARG \
  --emu-arg --pc-folder --emu-arg "$PWD/$O/pc" $S \
  --seconds $SEC --out $O $F "$@" > $O/run.log 2>&1
echo "run816 exit $?"
