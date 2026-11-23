#!/usr/bin/env python3
"""genrt.py - the tables that prove the runtime (rt/) against Python's arithmetic.

    genrt.py OUT.BIN [--cases N] [--memcases M] [--seed S]

Writes a binary file that tests/rt/rttest.c reads from the card. With a fixed seed it
holds, for every operation, edge values (0, 1, -1, $7FFF, $8000, $FFFF, $7FFFFFFF,
$80000000, $FFFFFFFF, powers of two and their neighbours) combined with each other and
with random values of every size, plus random cases, with the result computed here with
C's rules (16-bit int, 32-bit long, truncating division, the remainder has the sign of
the dividend, results wrap). No division by zero is in the tables.

Format, little-endian: sections of {u16 op, u16 count, u16 record size} followed by the
records; op 0 ends the file.
  ops 1-12 (arithmetic): {a, b, expected}, 16-bit (6 bytes) or 32-bit (12 bytes)
  op 20 (memory and strings): 9 x u16 {fn, n, src, dst, seed, extra, xval, ret, cksum}
        fn 1 memcpy, 2 memmove, 3 memset, 4 strlen, 5 strcpy, 6 memcmp; the procedure
        (fill, operation, checksum) is mem_case() below and its twin in rttest.c.
"""
import random
import struct
import sys

OPS16 = {1: "mul16u", 12: "mul16s", 2: "div16s", 3: "div16u", 4: "mod16s", 5: "mod16u"}
OPS32 = {6: "mul32u", 7: "mul32s", 8: "div32s", 9: "div32u", 10: "mod32s", 11: "mod32u"}
BUF = 4096


def s16(v):
    v &= 0xFFFF
    return v - 0x10000 if v & 0x8000 else v


def s32(v):
    v &= 0xFFFFFFFF
    return v - 0x100000000 if v & 0x80000000 else v


def cdiv(a, b):
    q = abs(a) // abs(b)
    return q if (a < 0) == (b < 0) else -q


def cmod(a, b):
    return a - cdiv(a, b) * b


def compute(op, a, b):
    if op in (1, 12):
        return (a * b) & 0xFFFF
    if op == 2:
        return cdiv(s16(a), s16(b)) & 0xFFFF
    if op == 3:
        return (a // b) & 0xFFFF
    if op == 4:
        return cmod(s16(a), s16(b)) & 0xFFFF
    if op == 5:
        return (a % b) & 0xFFFF
    if op in (6, 7):
        return (a * b) & 0xFFFFFFFF
    if op == 8:
        return cdiv(s32(a), s32(b)) & 0xFFFFFFFF
    if op == 9:
        return (a // b) & 0xFFFFFFFF
    if op == 10:
        return cmod(s32(a), s32(b)) & 0xFFFFFFFF
    if op == 11:
        return (a % b) & 0xFFFFFFFF
    raise ValueError(op)


def edges(bits):
    m = (1 << bits) - 1
    e = {0, 1, 2, 3, 7, 10, 100, 255, 256, 1000, m, m - 1, (m >> 1), (m >> 1) + 1}
    for k in range(bits):
        p = 1 << k
        e |= {p, p - 1, (p + 1) & m, (-p) & m}
    if bits == 32:
        e |= {0xFFFF, 0x10000, 0x10001, 65535 * 3, 123456789}
    return sorted(x & m for x in e)


def rand_val(rng, bits):
    """random values of every size: the bit length is uniform, not the value"""
    k = rng.randint(0, bits)
    v = rng.getrandbits(k) if k else 0
    if rng.random() < 0.25:
        v = (-v) & ((1 << bits) - 1)
    return v


def arith_cases(op, bits, n, rng):
    ed = edges(bits)
    cases = []
    for a in ed:                      # edges against edges (a sample when too many)
        for b in ed:
            cases.append((a, b))
    rng.shuffle(cases)
    cases = cases[: n // 2]
    while len(cases) < n:
        a = rng.choice(ed) if rng.random() < 0.15 else rand_val(rng, bits)
        b = rng.choice(ed) if rng.random() < 0.15 else rand_val(rng, bits)
        cases.append((a, b))
    out = []
    for a, b in cases:
        if op not in (1, 12, 6, 7) and b == 0:
            b = 1 + rng.getrandbits(bits - 1)
        out.append((a, b, compute(op, a, b)))
    return out


def xorshift_fill(buf, lo, hi, seed):
    """a Weyl sequence (cheap on the 65816): x += $9E3B, the byte = high ^ low"""
    x = seed
    for i in range(lo, hi):
        x = (x + 0x9E3B) & 0xFFFF
        buf[i] = (x >> 8) ^ (x & 0xFF)


def cksum(buf, lo, hi):
    """Fletcher-like: s1 = sum of the bytes, s2 = sum of the s1s (16 bits each)"""
    s1 = s2 = 0
    for i in range(lo, hi):
        s1 = (s1 + buf[i]) & 0xFFFF
        s2 = (s2 + s1) & 0xFFFF
    return s1 ^ ((s2 << 8) & 0xFFFF) ^ (s2 >> 8)


def areas(fn, n, src, dst):
    """the two areas filled and summed: 8 bytes around each operand (strcpy: and the 0)"""
    extra = 1 if fn == 5 else 0
    return (src - 8, src + n + extra + 8), (dst - 8, dst + n + extra + 8)


def mem_case(fn, n, src, dst, seed, extra, xval):
    """the expected (ret, cksum); the procedure rttest.c follows"""
    buf = bytearray(BUF)
    (alo, ahi), (blo, bhi) = areas(fn, n, src, dst)
    xorshift_fill(buf, alo, ahi, seed)
    xorshift_fill(buf, blo, bhi, seed if fn == 6 else (seed + 1) & 0xFFFF)
    ret = 0
    if fn in (4, 5):                          # a string of n non-zero bytes at src
        for i in range(src, src + n):
            if buf[i] == 0:
                buf[i] = 0x55
        buf[src + n] = 0
    if fn == 1:
        buf[dst:dst + n] = buf[src:src + n]
    elif fn == 2:
        buf[dst:dst + n] = bytes(buf[src:src + n])
    elif fn == 3:
        buf[dst:dst + n] = bytes([xval & 0xFF]) * n
    elif fn == 4:
        ret = n
    elif fn == 5:
        buf[dst:dst + n + 1] = bytes(buf[src:src + n + 1])
    elif fn == 6:
        if extra < n:
            buf[dst + extra] = xval & 0xFF
        a, b = bytes(buf[src:src + n]), bytes(buf[dst:dst + n])
        ret = 0 if a == b else (1 if a > b else 0xFFFF)
    cb = cksum(buf, blo, bhi)
    return ret, cksum(buf, alo, ahi) ^ (((cb << 8) | (cb >> 8)) & 0xFFFF)


def mem_cases(per_fn, rng):
    out = []
    for fn in (1, 2, 3, 4, 5, 6):
        lengths = list(range(0, 40)) + [63, 64, 65, 127, 128, 129, 255, 256, 257, 300,
                                        511, 512, 1000, 1023, 1024, 2000, 3000]
        k = 0
        while k < per_fn:
            if k < len(lengths):
                n = lengths[k]
            elif rng.random() < 0.02:
                n = rng.randint(301, 3500)
            else:
                n = rng.randint(0, 300)
            room = BUF - 32 - n - 2
            if fn == 2 and rng.random() < 0.7 and n > 0:
                # overlapping moves, both directions
                src = rng.randint(16, 16 + room)
                d = rng.randint(1, n) * rng.choice((-1, 1))
                dst = src + d
                if not 16 <= dst <= 16 + room:
                    continue
            elif fn in (1, 5, 6):
                # separate areas (memcpy and strcpy may not overlap)
                if 2 * (n + 1) + 64 > BUF - 32:
                    n = rng.randint(1000, 1900)
                src = rng.randint(16, BUF - 16 - 2 * (n + 1) - 32)
                dst = rng.randint(src + n + 17, BUF - 16 - n - 2)
                if rng.random() < 0.5:
                    src, dst = dst, src
            elif fn == 2:
                src = rng.randint(16, 16 + room)
                dst = rng.randint(16, 16 + room)
            else:                             # memset, strlen: one area
                src = dst = rng.randint(16, 16 + room)
            seed = rng.randint(1, 0xFFFF)
            extra = 0xFFFF
            xval = rng.getrandbits(16)
            if fn == 6 and n and rng.random() < 0.8:
                extra = rng.randint(0, n - 1)
            ret, ck = mem_case(fn, n, src, dst, seed, extra, xval)
            out.append((fn, n, src, dst, seed, extra, xval, ret, ck))
            k += 1
    return out


def main():
    a = sys.argv[1:]
    if not a or a[0].startswith("-"):
        sys.exit(__doc__)
    out = a[0]
    cases, memcases, seed = 3000, 2000, 816
    i = 1
    while i < len(a):
        if a[i] == "--cases":
            cases = int(a[i + 1]); i += 2
        elif a[i] == "--memcases":
            memcases = int(a[i + 1]); i += 2
        elif a[i] == "--seed":
            seed = int(a[i + 1]); i += 2
        else:
            sys.exit(__doc__)
    rng = random.Random(seed)
    o = bytearray()
    for op in sorted(OPS16):
        recs = arith_cases(op, 16, cases, rng)
        o += struct.pack("<HHH", op, len(recs), 6)
        for r in recs:
            o += struct.pack("<HHH", *r)
    for op in sorted(OPS32):
        recs = arith_cases(op, 32, cases, rng)
        o += struct.pack("<HHH", op, len(recs), 12)
        for r in recs:
            o += struct.pack("<III", *r)
    recs = mem_cases(memcases, rng)
    o += struct.pack("<HHH", 20, len(recs), 18)
    for r in recs:
        o += struct.pack("<9H", *r)
    o += struct.pack("<HHH", 0, 0, 0)
    with open(out, "wb") as f:
        f.write(o)
    print(f"genrt: {out}: {len(OPS16) + len(OPS32)} arithmetic ops x {cases} cases, "
          f"{len(recs)} memory cases, {len(o):,} bytes")


if __name__ == "__main__":
    main()
