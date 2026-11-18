#!/usr/bin/env python3
"""basic_fp.py - Horizon BASIC's floating point, computed on the PC (mpmath, 40 digits).

  python3 tests/basic_fp.py consts   the constants and polynomial tables of user/bas_fp.s
  python3 tests/basic_fp.py table [N]   the DATA lines of TESTS.BAS (from line N): arguments
                                     and the true values (12 significant digits) of the
                                     functions

A BASIC float: 12 decimal digits d1..d12 (d1 <> 0), value 0.d1d2..d12 x 10^e; packed as four
words: ft = (e + 128) << 8 | 4 | sign, then d9..d12, d5..d8, d1..d4 (BCD).
"""
import sys
import mpmath as mp

mp.mp.dps = 40


def digits12(x):
    """x (mpf, not 0) -> (sign, e, 12-digit int) rounded half to even"""
    s = 1 if x < 0 else 0
    x = abs(x)
    e = int(mp.floor(mp.log10(x))) + 1
    m = x / mp.mpf(10) ** e * 10 ** 12          # [1e11, 1e12)
    if m < 10 ** 11:
        e -= 1
        m *= 10
    if m >= 10 ** 12:
        e += 1
        m /= 10
    n = int(mp.nint(m))                          # (mpmath nint: half to even)
    if n == 10 ** 12:
        n //= 10
        e += 1
    return s, e, n


def pack(x, comment):
    x = mp.mpf(x)
    if x == 0:
        return "        .word   $0000, $0000, $0000, $0000   ; %s" % comment
    s, e, n = digits12(x)
    d = "%012d" % n
    w = [((e + 128) << 8) | 4 | s, int(d[8:12], 16), int(d[4:8], 16), int(d[0:4], 16)]
    return "        .word   $%04X, $%04X, $%04X, $%04X   ; %s" % (w[0], w[1], w[2], w[3], comment)


def fit(f, a, b, n):
    """a Chebyshev fit of n coefficients (degree n - 1) on [a, b], the highest first"""
    return mp.chebyfit(f, [a, b], n)


def consts():
    pi = mp.pi
    ln10 = mp.log(10)
    out = []
    c = lambda name, v, txt: out.append(name + ":\n" + pack(v, txt))
    c("c_one", 1, "1")
    c("c_half", mp.mpf(0.5), "0.5")
    c("c_c30", mp.sqrt(3) / 2, "cos(30 degrees)")
    c("c_pi", pi, "pi")
    c("c_pi2", pi / 2, "pi / 2")
    c("c_pi6", pi / 6, "pi / 6")
    c("c_2pi", 2 / pi, "2 / pi")
    c1 = mp.mpf("1.570796")
    c("c_pi2a", c1, "pi / 2, its first 7 digits (k * it is exact in 16 digits)")
    c("c_pi2b", pi / 2 - c1, "pi / 2 - c_pi2a")
    c("c_d2r", pi / 180, "pi / 180")
    c("c_r2d", 180 / pi, "180 / pi")
    c("c_i90", mp.mpf(1) / 90, "1 / 90")
    c("c_sq3", mp.sqrt(3), "sqrt(3)")
    c("c_tp12", 2 - mp.sqrt(3), "tan(pi / 12) = 2 - sqrt(3)")
    c("c_ln10", ln10, "ln(10)")
    l1 = mp.mpf("2.302585")
    c("c_ln10a", l1, "ln(10), its first 7 digits")
    c("c_ln10b", ln10 - l1, "ln(10) - c_ln10a")
    c("c_l10e", 1 / ln10, "1 / ln(10) = log10(e)")
    for name, f, a, b, n, txt in (
            ("sin_c", lambda z: mp.sin(mp.sqrt(z)) / mp.sqrt(z) if z else mp.mpf(1), 0, (pi / 4) ** 2, 6,
             "sin(r) = r * S(r^2), |r| <= pi / 4"),
            ("cos_c", lambda z: mp.cos(mp.sqrt(z)), 0, (pi / 4) ** 2, 7, "cos(r) = C(r^2)"),
            ("atn_c", lambda z: mp.atan(mp.sqrt(z)) / mp.sqrt(z) if z else mp.mpf(1), 0, (2 - mp.sqrt(3)) ** 2, 7,
             "atn(t) = t * A(t^2), |t| <= 2 - sqrt(3)"),
            ("exp_c", mp.exp, mp.mpf(-0.05), mp.mpf(0.05), 7, "exp(t), |t| <= 0.05"),
            ("log_c", lambda z: mp.atanh(mp.sqrt(z)) / mp.sqrt(z) if z else mp.mpf(1), 0, mp.mpf(0.05) ** 2, 4,
             "ln((1 + s) / (1 - s)) = 2 s L(s^2), |s| <= 0.05")):
        co = fit(f, a, b, n)
        lines = [name + ":                          ; " + txt + ", %d terms" % n]
        for i, v in enumerate(co):
            lines.append(pack(v, "x^%d" % (n - 1 - i)))
        out.append("\n".join(lines))
    lines = ["exp_t:                          ; e^(j / 10), j = -12 .. 12"]
    for j in range(-12, 13):
        lines.append(pack(mp.exp(mp.mpf(j) / 10), "e^%s" % (mp.nstr(mp.mpf(j) / 10, 3))))
    out.append("\n".join(lines))
    lines = ["ln_t:                           ; ln(c), c = 0.31, 0.32 .. 0.99, then 1.0, 1.1 .. 3.1"]
    for k in range(31, 100):
        lines.append(pack(mp.log(mp.mpf(k) / 100), "ln 0.%d" % k))
    for k in range(10, 32):
        lines.append(pack(mp.log(mp.mpf(k) / 10), "ln %d.%d" % (k // 10, k % 10)))
    out.append("\n".join(lines))
    print("\n".join(out))


# the function table of TESTS.BAS: (code, function, arguments)
TABLE = [
    (1, "SQR", ["2"]), (1, "SQR", ["1E-50"]), (1, "SQR", ["123456.789"]), (1, "SQR", ["9.87654321E77"]),
    (2, "SIN", ["1"]), (2, "SIN", ["-0.0001"]), (2, "SIN", ["3"]), (2, "SIN", ["100.5"]), (2, "SIN", ["-1234.5678"]),
    (3, "COS", ["1"]), (3, "COS", ["-2"]), (3, "COS", ["1.5"]), (3, "COS", ["50"]),
    (4, "TAN", ["0.5"]), (4, "TAN", ["-1.2"]), (4, "TAN", ["1.5707"]), (4, "TAN", ["10"]),
    (5, "ATN", ["0.1"]), (5, "ATN", ["-0.5"]), (5, "ATN", ["1"]), (5, "ATN", ["7"]), (5, "ATN", ["-12345"]),
    (6, "EXP", ["1"]), (6, "EXP", ["-5.5"]), (6, "EXP", ["0.001"]), (6, "EXP", ["100"]), (6, "EXP", ["-200.25"]),
    (7, "LOG", ["2"]), (7, "LOG", ["0.001"]), (7, "LOG", ["0.5"]), (7, "LOG", ["1.0001"]), (7, "LOG", ["7.5E88"]),
    (8, "LOG10", ["2"]), (8, "LOG10", ["0.03"]), (8, "LOG10", ["123456"]), (8, "LOG10", ["4.4E-77"]),
    (9, "^", ["1.5", "2.5"]), (9, "^", ["10", "-3.3"]), (9, "^", ["0.9", "100"]), (9, "^", ["2", "0.5"]),
    (9, "^", ["123.4", "-12.5"]), (9, "^", ["1.0001", "10000"]),
]


def ref12(x):
    """x to 12 significant digits, as BASIC reads it"""
    s, e, n = digits12(mp.mpf(x))
    d = "%012d" % n
    return ("-" if s else "") + d[0] + "." + d[1:].rstrip("0").rstrip(".") + "E" + str(e - 1) \
        if d[1:].rstrip("0") else ("-" if s else "") + d[0] + "E" + str(e - 1)


def table(first):
    """DATA lines from line first, step 1: code, x [, y], the true value (12 digits)"""
    f = {1: mp.sqrt, 2: mp.sin, 3: mp.cos, 4: mp.tan, 5: mp.atan, 6: mp.exp, 7: mp.log,
         8: mp.log10}
    n = first
    for code, name, args in TABLE:
        a = [mp.mpf(v) for v in args]
        v = a[0] ** a[1] if code == 9 else f[code](a[0])
        print("%d DATA %d,%s,%s" % (n, code, ",".join(args), ref12(v)))
        n += 1
    print("%d DATA 0" % n)


if __name__ == "__main__":
    if sys.argv[1:2] == ["table"]:
        table(int(sys.argv[2]) if len(sys.argv) > 2 else 2600)
        sys.exit()
    if sys.argv[1:] == ["consts"]:
        consts()
    else:
        print(__doc__)
