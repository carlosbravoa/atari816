#!/usr/bin/env python3
"""genfp.py - the table that proves cc816's floating point (rt/fp_*.s and the
compiler's conversions) bit for bit.

    genfp.py OUT.BIN [--cases N] [--seed S] [--no-host]

Writes a binary file that tests/fpu/fptest.c reads from the card: for every operation,
special values (zeros, infinities, NaNs, the smallest and largest denormals and normals,
1 and its neighbours) combined with each other and with random values, operands made to
give exact ties and near ties of the rounding, results in the denormal range and at the
overflow edge, and random patterns. The expected results are those of cc816's
specification (sdk/c/cc816/cc816/fp.py: IEEE 754 single precision, round to nearest even,
x86's NaN rules). Unless --no-host, the same inputs are also run through the host's own
hardware (a C program built with gcc: SSE, single precision) and the two must agree
(apart from which NaN comes out when both operands are NaN: counted, not an error).

Format, little-endian: records of 16 bytes {u16 op, u16 0, u32 a, u32 b, u32 expected};
op 0 ends the file. Ops: 1 a+b, 2 a-b, 3 a*b, 4 a/b, 5 the six compares of a and b (bits:
1 <, 2 <=, 4 >, 8 >=, 16 ==, 32 !=), 6 (long)a, 7 (unsigned long)a, 8 (float)(long)a,
9 (float)(unsigned long)a, 10 (int)a, 11 (unsigned)a, 12 (float)(int)a, 13
(float)(unsigned)a, 14 -a, 15 (_Bool)a, 16 (signed char)a, 17 (float)(unsigned char)a.
"""
import os
import random
import struct
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'cc816'))
from cc816 import fp  # noqa: E402

NAMES = {1: 'add', 2: 'sub', 3: 'mul', 4: 'div', 5: 'cmp', 6: 'ftol', 7: 'ftoul', 8: 'ltof',
         9: 'ultof', 10: 'ftoi', 11: 'ftou', 12: 'itof', 13: 'utof', 14: 'neg', 15: 'ftob',
         16: 'ftosc', 17: 'uctof'}

SPECIAL = [0x00000000, 0x80000000, 0x7F800000, 0xFF800000, 0x7FC00000, 0xFFC00000,
           0x7F800001, 0x7FBFFFFF, 0xFFA00000, 0x00000001, 0x80000001, 0x00000002,
           0x007FFFFF, 0x807FFFFF, 0x00400000, 0x00800000, 0x80800000, 0x00800001,
           0x00FFFFFF, 0x7F7FFFFF, 0xFF7FFFFF, 0x7F7FFFFE, 0x7F000000, 0x3F800000,
           0xBF800000, 0x3F800001, 0x3F7FFFFF, 0x40000000, 0x3F000000, 0x4B000000,
           0x4B7FFFFF, 0x4B800000, 0x34000000, 0x33800000, 0x33800001, 0x40490FDB,
           0x3DCCCCCD, 0x3EAAAAAB, 0x4F000000, 0xCF000000, 0x4EFFFFFF, 0x4F800000,
           0x4F7FFFFF, 0x0C000000, 0x01000000, 0x7E800000]


def f32(sign, e, m):
    return (sign << 31) | (e << 23) | (m & 0x7FFFFF)


class G:
    def __init__(self, seed):
        self.r = random.Random(seed)

    def any(self):
        r = self.r
        k = r.random()
        if k < 0.2:
            return r.choice(SPECIAL)
        if k < 0.45:
            return r.getrandbits(32)
        if k < 0.75:
            return f32(r.getrandbits(1), r.randint(100, 154), r.getrandbits(23))
        if k < 0.85:                        # few significand bits (exact products, ties)
            return f32(r.getrandbits(1), r.randint(110, 145), r.getrandbits(12) << 11)
        if k < 0.92:                        # denormal
            return f32(r.getrandbits(1), 0, r.getrandbits(r.randint(1, 23)))
        return f32(r.getrandbits(1), r.choice([1, 2, 3, 252, 253, 254]), r.getrandbits(23))

    def near(self, a, op):
        """a second operand made for a (ties, cancellation, denormal or huge results)"""
        r = self.r
        e = (a >> 23) & 0xFF
        if e in (0, 255):
            return self.any()
        k = r.random()
        if op in (1, 2):
            if k < 0.3:                     # a multiple of a's half-ulp: ties, near ties
                be = max(1, e - 24 + r.randint(-2, 2))
                return f32(r.getrandbits(1), be, r.getrandbits(3) << 20)
            if k < 0.6:                     # the same exponent or close: cancellation
                return f32(r.getrandbits(1), max(1, min(254, e + r.randint(-2, 2))),
                           (a & 0x7FFFFF) ^ r.getrandbits(r.randint(1, 23)))
            return f32(r.getrandbits(1), max(1, min(254, e - r.randint(0, 30))), r.getrandbits(23))
        if op == 3:
            if k < 0.4:                     # products near the denormal / overflow range
                want = r.choice([r.randint(-26, 3), r.randint(250, 256)])
                be = want - e + 127
                be = max(0, min(254, be))
                return f32(r.getrandbits(1), be, r.getrandbits(23) if be else r.getrandbits(23))
            return f32(r.getrandbits(1), r.randint(100, 154), r.getrandbits(12) << 11)
        if op == 4:
            if k < 0.3:                     # exact quotients
                q = f32(0, r.randint(120, 134), r.getrandbits(8) << 15)
                prod = fp.mul(a & 0x7FFFFFFF, q)
                return f32(r.getrandbits(1), (prod >> 23) & 0xFF, prod)
            if k < 0.6:
                want = r.choice([r.randint(-26, 3), r.randint(250, 256)])
                be = e + 127 - want
                be = max(1, min(254, be))
                return f32(r.getrandbits(1), be, r.getrandbits(23))
            return self.any()
        if op == 5 and k < 0.3:
            return a ^ r.choice([0, 0x80000000, 1, 0x80000001])
        return self.any()

    def intlike(self, lo, hi, frac=True):
        """a float in [lo, hi): integers, halves, random"""
        r = self.r
        k = r.random()
        if k < 0.3:
            v = r.randint(int(lo), int(hi) - 1)
            return fp.from_int(v)
        if k < 0.5:
            v = r.randint(int(lo), int(hi) - 1) + 0.5
            b = fp.from_py(v)
        else:
            b = fp.from_py(r.uniform(lo, hi) if r.random() < 0.5 else
                           r.choice([1, -1]) * 2 ** r.uniform(-30, 31))
        x = fp.to_py(b)
        if not (lo < x < hi):
            b = fp.from_int(int(lo) + 1)
        return b


def expected(op, a, b):
    if op == 1:
        return fp.add(a, b)
    if op == 2:
        return fp.sub(a, b)
    if op == 3:
        return fp.mul(a, b)
    if op == 4:
        return fp.div(a, b)
    if op == 5:
        c = fp.cmp(a, b)
        return (c == -1) | ((c in (-1, 0)) << 1) | ((c == 1) << 2) | ((c in (0, 1)) << 3) | \
            ((c == 0) << 4) | ((c != 0) << 5)
    if op in (6, 10, 16):
        v = fp.to_int(a)
        if op == 10:
            v &= 0xFFFF
        if op == 16:
            v &= 0xFF
            v = v - 256 if v & 0x80 else v
            v &= 0xFFFF
        return v & 0xFFFFFFFF
    if op == 7:
        return fp.to_int(a, signed=False) & 0xFFFFFFFF
    if op == 11:
        return fp.to_int(a) & 0xFFFF
    if op == 8:
        return fp.from_int(a - (1 << 32) if a >> 31 else a)
    if op == 9:
        return fp.from_int(a)
    if op == 12:
        a &= 0xFFFF
        return fp.from_int(a - 0x10000 if a >> 15 else a)
    if op == 13:
        return fp.from_int(a & 0xFFFF)
    if op == 14:
        return a ^ 0x80000000
    if op == 15:
        return int((a & 0x7FFFFFFF) != 0)
    if op == 17:
        return fp.from_int(a & 0xFF)
    raise ValueError(op)


def cases(n, seed):
    g = G(seed)
    r = g.r
    out = []
    for op in (1, 2, 3, 4, 5):
        for x in SPECIAL:                   # every special against every special
            for y in SPECIAL[::3] if op != 5 else SPECIAL:
                out.append((op, x, y))
        for _ in range(n):
            a = g.any()
            out.append((op, a, g.near(a, op) if r.random() < 0.6 else g.any()))
    m = max(n // 3, 50)
    for _ in range(m):
        out.append((6, g.intlike(-2147483648.0, 2147483648.0), 0))
        out.append((7, g.intlike(-0.9, 4294967296.0) if r.random() < 0.9 else
                    fp.from_py(-r.random()), 0))
        out.append((10, g.intlike(-32768.0, 32768.0), 0))
        out.append((11, g.intlike(-0.9, 65536.0), 0))
        out.append((16, g.intlike(-128.0, 128.0), 0))
        v = r.choice([r.getrandbits(32), r.getrandbits(r.randint(1, 32)),
                      ((1 << r.randint(24, 31)) + r.randint(-3, 3) * (1 << r.randint(0, 7))) &
                      0xFFFFFFFF])
        out.append((8, v, 0))
        out.append((8, (-v) & 0xFFFFFFFF, 0))
        out.append((9, v, 0))
        out.append((12, r.getrandbits(16), 0))
        out.append((13, r.getrandbits(16), 0))
        out.append((14, g.any(), 0))
        out.append((15, g.any(), 0))
        out.append((17, r.getrandbits(8), 0))
    for v in (0, 1, 0x7FFFFFFF, 0x80000000, 0x80000001, 0xFFFFFFFF, 0x01000001, 0x01000003,
              0xFFFFFF80, 0xFFFFFF7F, 0xFFFFFF81, 0x7FFFFFC0, 0x7FFFFF80, 0x00FFFFFF):
        out.append((8, v, 0))
        out.append((9, v, 0))
    for b in (0x4EFFFFFF, 0xCF000000, 0x4F7FFFFF, 0x3F7FFFFF, 0xBF7FFFFF, 0x3F000000,
              0x00000001, 0x80000000, 0x46FFFE00, 0xC7000000, 0x477FFF00):
        x = fp.to_py(b)
        if -2147483648.0 <= x < 2147483648.0:
            out.append((6, b, 0))
        if -1 < x < 4294967296.0:
            out.append((7, b, 0))
        if -32768 <= x < 32768:
            out.append((10, b, 0))
        if -1 < x < 65536:
            out.append((11, b, 0))
    return out


HOST_C = r'''
#include <stdio.h>
#include <stdint.h>
#include <string.h>
static float F(uint32_t u) { float f; memcpy(&f, &u, 4); return f; }
static uint32_t U(float f) { uint32_t u; memcpy(&u, &f, 4); return u; }
int main(void)
{
    unsigned op; unsigned long a, b;
    while (scanf("%u %lx %lx", &op, &a, &b) == 3) {
        volatile float x = F((uint32_t)a), y = F((uint32_t)b), r;
        uint32_t v = 0;
        switch (op) {
        case 1: r = x + y; v = U(r); break;
        case 2: r = x - y; v = U(r); break;
        case 3: r = x * y; v = U(r); break;
        case 4: r = x / y; v = U(r); break;
        case 5: v = (x < y) | (x <= y) << 1 | (x > y) << 2 | (x >= y) << 3 | (x == y) << 4 |
                    (x != y) << 5; break;
        case 6: v = (uint32_t)(int32_t)x; break;
        case 7: v = (uint32_t)(int64_t)x; break;
        case 8: r = (float)(int32_t)(uint32_t)a; v = U(r); break;
        case 9: r = (float)(uint32_t)a; v = U(r); break;
        case 10: v = (uint16_t)(int16_t)x; break;
        case 11: v = (uint16_t)(int32_t)x; break;
        case 12: r = (float)(int16_t)a; v = U(r); break;
        case 13: r = (float)(uint16_t)a; v = U(r); break;
        case 14: r = -x; v = U(r); break;
        case 15: v = (_Bool)x; break;
        case 16: v = (uint16_t)(int16_t)(signed char)(int32_t)x; break;
        case 17: r = (float)(unsigned char)a; v = U(r); break;
        }
        printf("%08lx\n", (unsigned long)v);
    }
    return 0;
}
'''


def host_check(cs, exp):
    with tempfile.TemporaryDirectory() as d:
        c = os.path.join(d, 'h.c')
        open(c, 'w').write(HOST_C)
        exe = os.path.join(d, 'h')
        subprocess.run(['gcc', '-O0', '-msse2', '-mfpmath=sse', '-ffp-contract=off', '-o', exe, c],
                       check=True)
        inp = ''.join(f'{op} {a:x} {b:x}\n' for op, a, b in cs)
        r = subprocess.run([exe], input=inp, capture_output=True, text=True, check=True)
        got = [int(x, 16) for x in r.stdout.split()]
    bad = nan2 = 0
    for (op, a, b), e, h in zip(cs, exp, got):
        if e == h:
            continue
        if fp.is_nan(e) and fp.is_nan(h) and fp.is_nan(a) and fp.is_nan(b):
            nan2 += 1                       # which of two NaNs: the hardware's choice
            continue
        bad += 1
        if bad <= 10:
            print(f'genfp: the host disagrees: {NAMES[op]} {a:08X} {b:08X}: spec {e:08X}, '
                  f'host {h:08X}', file=sys.stderr)
    return bad, nan2


def main():
    a = sys.argv[1:]
    n, seed, host = 1500, 1, True
    if '--cases' in a:
        i = a.index('--cases'); n = int(a[i + 1]); del a[i:i + 2]
    if '--seed' in a:
        i = a.index('--seed'); seed = int(a[i + 1]); del a[i:i + 2]
    if '--no-host' in a:
        a.remove('--no-host'); host = False
    if len(a) != 1:
        sys.exit(__doc__)
    cs = cases(n, seed)
    exp = [expected(op, x, y) for op, x, y in cs]
    if host:
        bad, nan2 = host_check(cs, exp)
        print(f'genfp: {len(cs)} cases; the host agrees on all but {bad}'
              f' ({nan2} two-NaN cases where the NaN chosen differs)')
        if bad:
            sys.exit(1)
    with open(a[0], 'wb') as f:
        for (op, x, y), e in zip(cs, exp):
            f.write(struct.pack('<HHIII', op, 0, x, y, e))
        f.write(struct.pack('<HHIII', 0, 0, 0, 0, 0))


if __name__ == '__main__':
    main()
