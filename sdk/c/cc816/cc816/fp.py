"""IEEE 754 single precision for the compiler: constants, constant folding, conversions.

A float value is its 32-bit pattern (an int). The arithmetic here gives what cc816's
runtime (sdk/c/rt/cc816/fp_*.s) gives at run time, bit for bit: round to nearest even,
gradual underflow, and x86's NaN rules (a NaN operand comes back quieted, the first one
when both are; an invalid operation, such as 0/0 or inf - inf, gives the default NaN
0xFFC00000).

The rounding is exact: + - * / are done in Python's double precision, which holds the exact
result of + - * of two singles and, for /, a double rounding that is innocuous for singles
(53 >= 2 * 24 + 2); the double is then rounded to single by struct ('f'). Decimal and
hexadecimal constants are rounded from their exact rational value (fractions.Fraction).
"""
import math
import struct
from fractions import Fraction

QNAN = 0xFFC00000          # the default NaN (x86's)
INF = 0x7F800000
SIGN = 0x80000000


class FV:
    """a float constant in constant expressions (const_eval): .bits is the pattern"""
    __slots__ = ('bits',)

    def __init__(self, bits):
        self.bits = bits & 0xFFFFFFFF

    def __bool__(self):
        return (self.bits & 0x7FFFFFFF) != 0          # -0.0 is false, a NaN is true

    def __eq__(self, o):
        if isinstance(o, FV):
            return cmp(self.bits, o.bits) == 0
        if isinstance(o, int) and not isinstance(o, bool):
            return cmp(self.bits, from_int(o)) == 0
        return False

    def __ne__(self, o):
        return not self.__eq__(o)

    def __hash__(self):
        return hash(self.bits)

    def __repr__(self):
        return f'FV({to_py(self.bits)!r}:{self.bits:08X})'


def is_nan(b):
    return (b & 0x7FFFFFFF) > INF


def to_py(b):
    """pattern -> Python float (exact)"""
    return struct.unpack('<f', struct.pack('<I', b & 0xFFFFFFFF))[0]


def from_py(x):
    """Python float -> pattern, rounded to nearest even (overflow -> infinity)"""
    if x != x:
        return QNAN
    try:
        return struct.unpack('<I', struct.pack('<f', x))[0]
    except OverflowError:
        return INF | (SIGN if x < 0 else 0)


def from_fraction(q, neg=False):
    """an exact rational (>= 0) -> pattern, rounded to nearest even"""
    s = SIGN if neg else 0
    if q == 0:
        return s
    n, d = q.numerator, q.denominator

    def scaled(e):                      # q / 2^e as num / den
        return (n, d << e) if e >= 0 else (n << -e, d)
    # e such that 2^23 <= q / 2^e < 2^24
    e = n.bit_length() - d.bit_length() - 23
    while True:
        num, den = scaled(e)
        if num >= den << 24:
            e += 1
        elif num < den << 23:
            e -= 1
        else:
            break
    be = e + 150                        # the biased exponent of m * 2^e
    if be < 1:                          # gradual underflow: units of 2^-149
        num, den = scaled(-149)
    m, r = divmod(num, den)
    half = 2 * r - den
    if half > 0 or (half == 0 and m & 1):
        m += 1
    if be < 1:
        return s | m                    # m = 2^23 is the smallest normal: still right
    if m == 1 << 24:
        m >>= 1
        be += 1
    if be >= 255:
        return s | INF
    return s | (be << 23) | (m & 0x7FFFFF)


def from_int(v):
    """an integer -> pattern (rounded to nearest even)"""
    if v == 0:
        return 0
    return from_fraction(Fraction(abs(v)), v < 0)


def to_int(b, bits=32, signed=True):
    """pattern -> integer, truncated toward zero; out of range (undefined in C) gives
    what the runtime gives: __ftol 0x80000000, __ftoul 0xFFFFFFFF for 2^32 and above
    (and NaN), a negative value through __ftol"""
    x = to_py(b)
    if x != x or math.isinf(x):
        v = None
    else:
        v = math.trunc(x)
    if signed or (b & SIGN):
        if v is None or not -(1 << 31) <= v < (1 << 31):
            v = -(1 << 31)
    else:
        if v is None or v >= (1 << 32):
            v = (1 << 32) - 1
    return v


def parse(s):
    """a C floating constant (without its suffix) -> pattern"""
    t = s.lower()
    if t.startswith('0x'):
        mant, _, exp = t[2:].partition('p')
        ip, _, fp = mant.partition('.')
        digits = (ip + fp) or '0'
        q = Fraction(int(digits, 16), 16 ** len(fp))
        e = int(exp) if exp else 0
        q = q * 2 ** e if e >= 0 else q / 2 ** -e
        return from_fraction(q)
    return from_fraction(Fraction(t))


def _nan_result(a, b):
    """the NaN an operation with a NaN operand gives (x86): the first NaN, quieted"""
    if is_nan(a):
        return a | 0x00400000
    return b | 0x00400000


def add(a, b):
    if is_nan(a) or is_nan(b):
        return _nan_result(a, b)
    x, y = to_py(a), to_py(b)
    if math.isinf(x) and math.isinf(y) and (a ^ b) & SIGN:
        return QNAN
    return from_py(x + y)


def sub(a, b):
    if is_nan(a) or is_nan(b):
        return _nan_result(a, b)
    return add(a, b ^ SIGN)


def mul(a, b):
    if is_nan(a) or is_nan(b):
        return _nan_result(a, b)
    x, y = to_py(a), to_py(b)
    if (math.isinf(x) and y == 0) or (math.isinf(y) and x == 0):
        return QNAN
    return from_py(x * y)


def div(a, b):
    if is_nan(a) or is_nan(b):
        return _nan_result(a, b)
    x, y = to_py(a), to_py(b)
    s = (a ^ b) & SIGN
    if y == 0:
        if x == 0:
            return QNAN
        return INF | s
    if math.isinf(x):
        if math.isinf(y):
            return QNAN
        return INF | s
    return from_py(x / y)


def cmp(a, b):
    """-1 (a < b), 0 (equal), 1 (a > b), 2 (unordered: a NaN)"""
    if is_nan(a) or is_nan(b):
        return 2
    x, y = to_py(a), to_py(b)
    return -1 if x < y else (1 if x > y else 0)


OPS = {'fadd': add, 'fsub': sub, 'fmul': mul, 'fdiv': div}
