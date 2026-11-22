#!/usr/bin/env python3
"""genfmt.py - the table that checks cc816's printf float conversions and strtod against
the host's C library (glibc): its printf prints a float's exact decimal value rounded with
ties to even, and its strtof rounds exactly, so the two must agree character for
character and bit for bit.

    genfmt.py OUT.TXT [--cases N] [--seed S]

Lines (tab-separated), read by tests/fpu/fptest.c:
    P <bits> <format> <expected output>        sprintf(buf, format, value)
    S <string> <expected bits> <characters used>   strtod(string, &end)
"""
import os
import random
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'cc816'))
from cc816 import fp  # noqa: E402

HOST_C = r'''
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
int main(void)
{
    char line[1024], out[1024];
    while (fgets(line, sizeof line, stdin)) {
        line[strcspn(line, "\n")] = 0;
        if (line[0] == 'P') {
            uint32_t u; float f; char *fmt;
            u = (uint32_t)strtoul(line + 2, &fmt, 16);
            fmt++;
            memcpy(&f, &u, 4);
            if (strchr(fmt, 'L'))
                snprintf(out, sizeof out, fmt, (long double)f);
            else
                snprintf(out, sizeof out, fmt, (double)f);
            printf("%s\n", out);
        } else {
            char *end; float f = strtof(line + 2, &end); uint32_t u;
            memcpy(&u, &f, 4);
            printf("%08lx %d\n", (unsigned long)u, (int)(end - (line + 2)));
        }
    }
    return 0;
}
'''


def value(r):
    k = r.random()
    if k < 0.15:
        return r.choice([0, 0x80000000, 0x7F800000, 0xFF800000, 0x7FC00000, 0xFFC00000,
                         0x00000001, 0x007FFFFF, 0x00800000, 0x7F7FFFFF, 0x3F800000,
                         0x3F000000, 0x40200000, 0x3E800000, 0x3DCCCCCD, 0x40490FDB,
                         0x4B189680, 0x501502F9, 0x49742400, 0x3F7FFFFF, 0x3F7FFFF0])
    if k < 0.35:
        return r.getrandbits(32)
    if k < 0.55:                        # integers and halves: ties at %.0f / %.1f
        v = r.randint(-100000, 100000) / r.choice([1, 2, 4, 8, 16, 1000])
        return fp.from_py(v)
    if k < 0.75:
        return fp.from_py(r.choice([1, -1]) * 10 ** r.uniform(-12, 12))
    if k < 0.85:
        return fp.from_py(r.choice([1, -1]) * 10 ** r.uniform(-45, 38.5))
    return (r.getrandbits(1) << 31) | (r.randint(110, 150) << 23) | (r.getrandbits(8) << 15)


def fmt(r):
    conv = r.choice('ffffeeeggggaAEGF')
    flags = ''.join(c for c in '-+ #0' if r.random() < 0.2)
    w = str(r.randint(1, 25)) if r.random() < 0.4 else ''
    p = ''
    k = r.random()
    if k < 0.6:
        p = '.' + str(r.choice([0, 0, 1, 2, 3, 4, 5, 6, 8, 10, 12, r.randint(0, 40)]))
    elif k < 0.65:
        p = '.'
    pre = r.choice(['', '', 'x=', '[']) 
    post = r.choice(['', '', ']', ' end'])
    lm = r.choice(['', '', 'l', 'L']) if conv not in 'aA' else ''
    return f'{pre}%{flags}{w}{p}{lm}{conv}{post}'


def numstr(r):
    k = r.random()
    if k < 0.25:                        # a float printed back with some digits
        b = value(r)
        x = fp.to_py(b)
        if x != x or x in (float('inf'), float('-inf')):
            return r.choice(['inf', '-INF', 'nan', 'Infinity', '+nan(123)', 'NaNx', 'infinit'])
        return f'%.{r.randint(1, 12)}{r.choice("eg")}' % x
    if k < 0.45:                        # random digits, random exponent
        d = ''.join(r.choice('0123456789') for _ in range(r.randint(1, 30)))
        if r.random() < 0.5:
            i = r.randint(0, len(d))
            d = d[:i] + '.' + d[i:]
        if r.random() < 0.7:
            d += r.choice('eE') + r.choice(['', '+', '-']) + str(r.randint(0, 50))
        return r.choice(['', '-', '+', ' ', '  -']) + d
    if k < 0.65:                        # halfway points between floats, exactly, and nearby
        b = r.getrandbits(31)
        if (b >> 23) == 255:
            b &= 0x7F7FFFFF
        from fractions import Fraction
        e = (b >> 23) & 0xFF
        m = b & 0x7FFFFF
        if e:
            m |= 0x800000
        else:
            e = 1
        mid = Fraction(2 * m + 1, 2) * Fraction(2) ** (e - 150)
        eps = r.choice([0, 0, Fraction(1, 10 ** 60), -Fraction(1, 10 ** 60)])
        q = mid * (1 + eps)
        # exact decimal of q (scientific, many digits)
        digits = r.randint(9, 120)
        s = dec(q, digits)
        return s
    if k < 0.75:                        # hexadecimal
        h = ''.join(r.choice('0123456789abcdefABCDEF') for _ in range(r.randint(1, 10)))
        if r.random() < 0.5:
            i = r.randint(0, len(h))
            h = h[:i] + '.' + h[i:]
        if r.random() < 0.8:
            h += 'p' + r.choice(['', '+', '-']) + str(r.randint(0, 160))
        return r.choice(['', '-']) + '0x' + h
    if k < 0.85:                        # tiny and huge
        return f'{r.randint(1, 99999)}e{r.randint(-60, 45)}'
    return r.choice(['0', '-0', '0.', '.5', '5.', '.', '-', 'e5', '1e', '1e+', '1.5e-x',
                     '0x', '0x.p1', '1' + '0' * 50, '0.' + '0' * 50 + '1', '3.4028235e38',
                     '3.40282357e38', '3.4028236e38', '1.4e-45', '7.006e-46', '7.0064923e-46',
                     '7.0064924e-46', '1.17549435e-38', '0.1', '1e-46', '  12abc', '00012',
                     '1.' + '9' * 40, '9' * 40 + 'e-40'])


def dec(q, digits):
    """q (a positive Fraction) in scientific notation with this many significant digits
    (truncated)"""
    from fractions import Fraction
    e = 0
    while q >= 10:
        q /= 10
        e += 1
    while q < 1:
        q *= 10
        e -= 1
    s = ''
    for _ in range(digits):
        d = int(q)
        s += str(d)
        q = (q - d) * 10
    return s[0] + '.' + s[1:] + f'e{e}'


def main():
    a = sys.argv[1:]
    n, seed = 1500, 1
    if '--cases' in a:
        i = a.index('--cases'); n = int(a[i + 1]); del a[i:i + 2]
    if '--seed' in a:
        i = a.index('--seed'); seed = int(a[i + 1]); del a[i:i + 2]
    if len(a) != 1:
        sys.exit(__doc__)
    r = random.Random(seed)
    lines = []
    for _ in range(n):
        lines.append(('P', value(r), fmt(r)))
    for _ in range(n):
        lines.append(('S', numstr(r)))
    with tempfile.TemporaryDirectory() as d:
        c = os.path.join(d, 'h.c')
        open(c, 'w').write(HOST_C)
        exe = os.path.join(d, 'h')
        subprocess.run(['gcc', '-O0', '-w', '-o', exe, c], check=True)
        inp = ''.join((f'P {l[1]:08x} {l[2]}\n' if l[0] == 'P' else f'S {l[1]}\n') for l in lines)
        res = subprocess.run([exe], input=inp, capture_output=True, text=True, check=True)
    outs = res.stdout.split('\n')
    with open(a[0], 'w') as f:
        for l, o in zip(lines, outs):
            if l[0] == 'P':
                f.write(f'P\t{l[1]:08X}\t{l[2]}\t{o}\n')
            else:
                bits, used = o.split()
                f.write(f'S\t{l[1]}\t{int(bits, 16):08X}\t{used}\n')
    print(f'genfmt: {len(lines)} cases')


if __name__ == '__main__':
    main()
