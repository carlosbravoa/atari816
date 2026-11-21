#!/bin/sh
# check.sh - the regression set: hello, window, bench (in emu816), the c-testsuite (if
# downloaded to $CTS), and random programs from genfuzz (seeds 1 and 2).
set -e
here=$(cd "$(dirname "$0")" && pwd)
own=$(dirname "$here")
cc="python3 $own/cc816.py"
B=$own/build/check
mkdir -p $B
cd $here/hello && $cc hello.c -o $B/HELLO.PRG
$here/run.sh hello $B/HELLO.PRG --mode shell --args 'one "two words" three' --seconds 3 \
    --expect '&local passed: 42 (42)  local array: 6 (6)  global: 100 (100)' \
    --expect 'sum 124716 (124716)' --expect 'ok' | tail -1
cd $here/window && $cc window.c -o $B/CWIN.PRG
$here/run.sh window $B/CWIN.PRG --script test.script --expect 'CWIN: closed' | tail -1
cd $here/bench && $cc bench_hz.c bench.c -o $B/CBENCH.PRG -m $B/CBENCH.map
$here/run.sh bench $B/CBENCH.PRG --mode shell --seconds 40 --expect 'bench done' \
    --expect 'check 1899' --expect 'check 27824' --expect 'check 1071602483' \
    --expect 'check 17711' --expect 'check 3160' --expect 'check 4275534039' | tail -1
sed -n '/CBENCH/,$p' $own/build/run-bench/console.txt | grep check
ls -l $B/CBENCH.PRG | awk '{print "CBENCH.PRG", $5, "bytes"}'
if [ -n "$CTS" ]; then
    python3 $here/conform/conform.py --out $own/build/cts $CTS/tests/single-exec/*.c | head -1
fi
for seed in 1 2; do
    F=$own/build/fuzzsrc$seed
    [ -d $F ] || python3 $here/fuzz/genfuzz.py $F $((200 * seed)) $seed > /dev/null
    python3 $here/conform/conform.py --out $own/build/fuzz$seed --seconds-per-test 2 $F/fz*.c | head -1
done
