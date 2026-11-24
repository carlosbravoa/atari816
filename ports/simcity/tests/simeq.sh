#!/bin/sh
# tests/simeq.sh [HORIZON] [TICKS] [CASES...] - the simulator on the Atari816 (SIMTEST.PRG in the
# emulator) against its twins on the PC (build/host16/simtest: the same engine with a
# 16-bit int; build/host32/simtest: upstream's types): the same city, the same seed, the
# same ticks; the state's checksum (the whole map, the other maps, the histories, funds,
# population, evaluation, the moving things, the random numbers) every 100 ticks must be
# the same in all three. The acceptance test of the compiler and of the port.
#
# Cases (tests/simeq.cases, one a line: NAME ARGS for simtest; files it loads from
# engine/res and engine/cities).
HZ=${1:-../../horizon}
TICKS=${2:-5000}
shift 2 2>/dev/null
cd "$(dirname "$0")/.." || exit 1
fail=0
ok() { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fail=1; }
mkdir -p build/simeq
CASES=$(grep -v '^#' tests/simeq.cases | grep . | cut -d' ' -f1)
[ $# -gt 0 ] && CASES="$*"
pids=
for c in $CASES; do
  a=$(grep "^$c " tests/simeq.cases | cut -d' ' -f2-)
  # the files the case reads, on the card in /APPS
  files=
  for f in $(echo "$a" | tr ' ' '\n' | grep '\.cty$'); do
    files="$files --file engine/cities/$(basename $f):/APPS/$(basename $f | tr a-z A-Z)"
  done
  case "$a" in *scen*) n=$(echo "$a" | sed 's/.*scen \([0-9]\).*/\1/'); files="$files --file engine/res/snro.$n$n$n:/APPS/SNRO.$n$n$n";; esac
  a816=$(echo "$a" | sed 's#load \([^ ]*\)#load /APPS/\1#')
  python3 ../../sdk/tools/run816.py SIMTEST.PRG --horizon "$HZ" --mode shell \
    --args "res /APPS $a816 ticks $TICKS every 100" $files --seconds 3000 \
    --stop-on "sim: end" --stop-on-delay 500 --out build/simeq/$c > build/simeq/$c.log 2>&1 &
  pids="$pids $!"
done
for c in $CASES; do
  a=$(grep "^$c " tests/simeq.cases | cut -d' ' -f2-)
  ah=$(echo "$a" | sed 's#load \([^ ]*\)#load engine/cities/\1#')
  build/host16/simtest res engine/res $ah ticks $TICKS every 100 | grep '^sim: \(start\|tick\|end\)' > build/simeq/$c.h16
  build/host32/simtest res engine/res $ah ticks $TICKS every 100 | grep '^sim: \(start\|tick\|end\)' > build/simeq/$c.h32
done
wait $pids
for c in $CASES; do
  tr -d '\r' < build/simeq/$c/console.txt | grep -a '^sim: \(start\|tick\|end\)' > build/simeq/$c.816
  n=$(wc -l < build/simeq/$c.h16)
  last=$(tail -1 build/simeq/$c.h16 | cut -d' ' -f2-9)
  if ! cmp -s build/simeq/$c.h16 build/simeq/$c.h32; then
    bad "$c: host16 and host32 part: $(diff build/simeq/$c.h32 build/simeq/$c.h16 | sed -n 2p)"
  elif ! cmp -s build/simeq/$c.816 build/simeq/$c.h16; then
    bad "$c: the Atari816 parts from the PC: $(diff build/simeq/$c.h16 build/simeq/$c.816 | sed -n 2,4p | tr '\n' ' ')"
  else
    ms=$(tr -d '\r' < build/simeq/$c/console.txt | sed -n 's/^sim: [0-9]* ticks in \([0-9]*\) ms/\1/p')
    ok "$c: $n states equal on the Atari816 and the PC's twins ($last; $ms ms on the Atari816)"
  fi
done
exit $fail
