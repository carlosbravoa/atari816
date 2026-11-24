#!/bin/sh
# tools/firstdiff.sh A B ARGS... : run two builds of simtest (A, B: their programs) with
# the same ARGS, a line every tick, and show the first tick where their states part and
# what differs then (the map's cells, the other lines of the dump). For finding a 16-bit
# fault (A = build/host32/simtest, B = build/host16/simtest).
A=$1; B=$2; shift 2
T=${TMPDIR:-/tmp}/firstdiff.$$
mkdir -p $T
$A "$@" every 1 | grep '^sim: \(tick\|end\)' > $T/a
$B "$@" every 1 | grep '^sim: \(tick\|end\)' > $T/b
d=$(diff $T/a $T/b | head -2 | sed -n 's/^< sim: [a-z]* \([0-9]*\) .*/\1/p')
if [ -z "$d" ]; then echo "same states ($(wc -l < $T/a) lines)"; rm -rf $T; exit 0; fi
echo "first difference at tick $d:"
diff $T/a $T/b | head -2
args=$(echo "$@" | sed 's/ticks [0-9]*//')
$A $args ticks $d dump $T/da > /dev/null
$B $args ticks $d dump $T/db > /dev/null
python3 - $T/da $T/db <<'PY'
import sys
a = open(sys.argv[1]).read().split('\n'); b = open(sys.argv[2]).read().split('\n')
print('a:', a[0]); print('b:', b[0])
n = 0
for y in range(1, 101):
    for x in range(120):
        p, q = a[y][4*x:4*x+4], b[y][4*x:4*x+4]
        if p != q:
            n += 1
            if n <= 12: print('map', x, y - 1, p, q)
print('map cells differing:', n)
for i in range(101, min(len(a), len(b))):
    if a[i] != b[i]:
        print('line', i, '\n  a:', a[i][:200], '\n  b:', b[i][:200])
        n += 1
        if n > 30: break
PY
rm -rf $T
