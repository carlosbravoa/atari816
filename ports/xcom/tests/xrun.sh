#!/bin/sh
# tests/xrun.sh OUT SECONDS "ARGS" [run816 options]: one run of XCOM.PRG (or $PRG) in the
# emulator's shell with the packs at /GAMES/XCOM and tests/*.keys as NAME.KEY; ARGS: the
# engine's options (put in X.ARG: the shell's line is short). For trying things out.
cd "$(dirname "$0")/.." || exit 1
export PATH=$HOME/.local/bin:$PATH
O=$1; SEC=$2; ARGS=$3; shift 3
rm -rf $O; mkdir -p $O
F=
for f in data/packs/*.PAK data/packs/PACKS.VER; do F="$F --file $f:/GAMES/XCOM/$(basename $f)"; done
for f in data/packs/VGA/*; do F="$F --file $f:/GAMES/XCOM/VGA/$(basename $f)"; done
for f in tests/*.keys; do n=$(basename $f .keys | tr a-z A-Z); F="$F --file $f:/GAMES/XCOM/$n.KEY"; done
echo "$ARGS" > $O/X.ARG
python3 ../../sdk/tools/run816.py ${PRG:-XCOM.PRG} --horizon ../../horizon --mode shell \
  --dest /GAMES/XCOM/XCOM.PRG --cd /GAMES/XCOM --args "@X.ARG" --file $O/X.ARG:/GAMES/XCOM/X.ARG \
  --seconds $SEC --out $O $F "$@" > $O/run.log 2>&1
echo "run816 exit $?"
