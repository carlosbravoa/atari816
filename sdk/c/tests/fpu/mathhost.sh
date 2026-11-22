#!/bin/sh
# mathhost.sh - build cc816's math library (lib/cc816/math_*.c) for the host in single
# precision and measure it (mathacc.c): sh mathhost.sh [N arguments a function]
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
LIB=$HERE/../../lib/cc816
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
ln -s "$HERE/../../cc816/include/math.h" "$T/math.h"
REN=""
for f in sin cos tan atan atan2 asin acos exp exp2 expm1 log log10 log2 log1p pow sqrt \
         cbrt hypot sinh cosh tanh floor ceil trunc round rint nearbyint lround lrint fabs \
         fmod remainder modf frexp ldexp scalbn ilogb logb copysign nextafter fmin fmax \
         fdim fma; do
    REN="$REN -D$f=t_$f"
done
for s in "$LIB"/math_*.c; do
    gcc -c -O1 -fwrapv -fno-builtin -ffp-contract=off -msse2 -mfpmath=sse -Ddouble=float \
        -w -I "$T" $REN -o "$T/$(basename "$s" .c).o" "$s"
done
gcc -O1 -o "$T/mathacc" "$HERE/mathacc.c" "$T"/math_*.o -lm
"$T/mathacc" "$@"
