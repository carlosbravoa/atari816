#!/bin/sh
# tests/run.sh HORIZON OUT [run816 options...] - the game in the emulator with its files
# (build/card) on the card in /APPS/MICROPOLIS, started from the shell there (the args
# with --args). The other tests call it.
HZ=$1
OUT=$2
shift 2
cd "$(dirname "$0")/.." || exit 1
FILES=
for f in build/card/*.* build/card/SND/* build/card/CITIES/*; do
  [ -f "$f" ] || continue
  FILES="$FILES --file $f:/APPS/MICROPOLIS/${f#build/card/}"
done
exec python3 ../../sdk/tools/run816.py MICROPOL.PRG --horizon "$HZ" \
  --dest /APPS/MICROPOLIS/MICROPOL.PRG --mode shell --cd /APPS/MICROPOLIS $FILES \
  --out "$OUT" "$@"
