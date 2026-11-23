#!/bin/sh
# tests/layouts.sh [HORIZON] [PAD...] - make test with the program's layout shifted (make
# test-layouts): for each PAD (default 0 1 37 250 500) PRINCE.PRG is linked with
# tools/mkpad.py's object first (PAD = 0: none) and tests/check.sh runs; a fault that
# depends on where code and data lie (an index register gone negative, a far address
# taken as near, a read of memory nobody wrote) shows as a difference between layouts.
# PRINCE.PRG is left linked without the pad.
HZ=${1:-../../horizon}
[ $# -gt 0 ] && shift
PADS=${*:-0 1 37 250 500}
cd "$(dirname "$0")/.." || exit 1
fail=0
summary=
for p in $PADS; do
  echo "== layout PAD=$p"
  if ! make -s PAD="$p" PRINCE.PRG > build/layout.log 2>&1; then
    cat build/layout.log; echo "FAIL  PAD=$p: no build"; fail=1; summary="$summary PAD=$p:nobuild"; continue
  fi
  if sh tests/check.sh "$HZ"; then summary="$summary PAD=$p:pass"
  else fail=1; summary="$summary PAD=$p:FAIL"; fi
done
make -s PAD=0 PRINCE.PRG > /dev/null 2>&1
echo "layouts:$summary"
if [ $fail = 0 ]; then echo "layouts: all passed"; else echo "layouts: FAILED"; fi
exit $fail
