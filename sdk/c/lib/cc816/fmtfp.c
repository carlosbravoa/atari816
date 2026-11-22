/* fmtfp.c - printf's floating-point conversions for cc816: %f %F %e %E %g %G %a %A.
 *
 * fmt.c calls __hz_fmtfp through the hook rt/cc816/fp_hookp.s installs in programs that
 * use floating point. A float (and a double: the same 32-bit format) is printed from its
 * exact decimal value (every float is m * 2^e: a finite decimal fraction), rounded to the
 * precision with ties to even, as glibc does: printf("%.1f", 0.25) gives 0.2, and
 * printf("%.20f", 0.1f) every digit of 0.100000001490116119384765625. Infinity is inf
 * (INF), NaN nan (NAN), with a - when the sign bit is set (-nan, as glibc).
 * Flags - + space # 0, width, precision (default 6).
 */
#include <string.h>

typedef void (*hz_outfn)(int c, void *ctx);

#define NDIG 168        /* a float's decimal expansion: 1 + 39 integer + 149 fraction... */
                        /* ...at most 8 + 149 significant positions with a leading 0 */

static unsigned char dg[NDIG];  /* the digits, dg[0] a leading 0 */
static int nd;                  /* digits in dg */
static int ip;                  /* digits before the decimal point (with the leading 0) */

/* the exact decimal expansion of m * 2^e (m < 2^24, -149 <= e <= 104) into dg */
static void expand(unsigned long m, int e)
{
    char t[10];
    int n = 0, i, k;
    do {
        t[n++] = (char)(m % 10);
        m /= 10;
    } while (m);
    dg[0] = 0;
    for (i = 0; i < n; ++i)
        dg[1 + i] = (unsigned char)t[n - 1 - i];
    nd = ip = n + 1;
    for (; e > 0; --e) {                /* x 2 */
        unsigned c = 0;
        for (k = nd - 1; k >= 0; --k) {
            unsigned v = dg[k] * 2u + c;
            c = v >= 10;
            dg[k] = (unsigned char)(c ? v - 10 : v);
        }
        if (c || dg[0]) {               /* keep a leading 0 */
            memmove(dg + 1, dg, (unsigned)nd);
            dg[0] = 0;
            if (c)
                dg[1] = 1;
            ++nd;
            ++ip;
        }
    }
    for (; e < 0; ++e) {                /* / 2 */
        unsigned r = 0;
        for (k = 0; k < nd; ++k) {
            unsigned v = r * 10u + dg[k];
            dg[k] = (unsigned char)(v >> 1);
            r = v & 1;
        }
        if (r)
            dg[nd++] = 5;
    }
}

/* keep the first k digits, rounded to nearest (ties to even): the digits after are
 * dropped. k <= 0 rounds to 0 (the leading digit is always the 0). */
static void round_at(int k)
{
    int i, up;
    if (k >= nd)
        return;
    if (k < 1) {
        nd = 1;
        dg[0] = 0;
        return;
    }
    if (dg[k] > 5)
        up = 1;
    else if (dg[k] < 5)
        up = 0;
    else {
        up = dg[k - 1] & 1;             /* a tie: to even */
        for (i = k + 1; i < nd; ++i)
            if (dg[i]) {
                up = 1;
                break;
            }
    }
    nd = k;
    if (up)
        for (i = k - 1; i >= 0; --i) {
            if (dg[i] < 9) {
                ++dg[i];
                break;
            }
            dg[i] = 0;
        }
}

static unsigned char digit(int i)
{
    return (unsigned char)(i >= 0 && i < nd ? '0' + dg[i] : '0');
}

/* the output, twice: counted (out == 0) for the padding, then written */
static hz_outfn o_fn;
static void *o_ctx;
static int o_n;

static void put(int c)
{
    ++o_n;
    if (o_fn)
        o_fn(c, o_ctx);
}

static void putn(int c, int n)
{
    while (n-- > 0)
        put(c);
}

/* the body of a number (no sign, no padding) */
static void body(unsigned c, unsigned flags, int prec, int first, int x, int gstrip)
{
    int i, last, up = c < 'a';
    if (c == 'f' || c == 'F') {
        /* integer digits: from the first nonzero (or the units digit) */
        for (i = first; i < ip; ++i)
            put(digit(i));
        last = ip + prec;               /* the digits after the point to print */
        if (gstrip)
            while (last > ip && digit(last - 1) == '0')
                --last;
        if (last > ip || (flags & 8))
            put('.');
        for (i = ip; i < last; ++i)
            put(digit(i));
        return;
    }
    /* e: d.ddd e+xx; first is the first significant digit */
    put(digit(first));
    last = first + 1 + prec;
    if (gstrip)
        while (last > first + 1 && digit(last - 1) == '0')
            --last;
    if (last > first + 1 || (flags & 8))
        put('.');
    for (i = first + 1; i < last; ++i)
        put(digit(i));
    put(up ? 'E' : 'e');
    if (x < 0) {
        put('-');
        x = -x;
    } else
        put('+');
    if (x >= 100)
        put('0' + x / 100);
    put('0' + x / 10 % 10);
    put('0' + x % 10);
}

static void hexbody(unsigned c, unsigned flags, int prec, unsigned long m, int e)
{
    /* m: 24 bits, leading 1 at bit 23 (0 for zero): 1.hhhhhhp+e (the 0x is written
     * before, the zeros of the 0 flag after it) */
    static const char lo[] = "0123456789abcdef", hi[] = "0123456789ABCDEF";
    const char *h = c == 'A' ? hi : lo;
    unsigned long f = (m & 0x7FFFFFUL) << 1;  /* 24 bits: 6 hex digits */
    int nh = 6, i;
    char lead = m ? '1' : '0';
    if (prec >= 0 && prec < 6) {
        int drop = 4 * (6 - prec);
        unsigned long half = 1UL << (drop - 1), r = f & ((1UL << drop) - 1);
        f >>= drop;
        if (r > half || (r == half && (f & 1)))
            ++f;
        if (f >> (4 * prec)) {          /* 1.fff rounded up: 2.000 (as glibc) */
            f &= (1UL << (4 * prec)) - 1;
            lead = '2';
        }
        nh = prec;
    } else if (prec < 0) {
        while (nh && !(f & 15)) {
            f >>= 4;
            --nh;
        }
    }
    put(lead);
    if (nh || (flags & 8) || prec > 0)
        put('.');
    for (i = nh - 1; i >= 0; --i)
        put(h[(unsigned)(f >> (4 * i)) & 15]);
    if (prec > 6)
        putn('0', prec - 6);
    put(c == 'A' ? 'P' : 'p');
    if (e < 0) {
        put('-');
        e = -e;
    } else
        put('+');
    if (e >= 100)
        put('0' + e / 100);
    if (e >= 10)
        put('0' + e / 10 % 10);
    put('0' + e % 10);
}

int __hz_fmtfp(hz_outfn out, void *ctx, unsigned c, unsigned flags, unsigned width,
               int prec, unsigned long bits)
{
    int neg = (bits >> 31) != 0, ex = (int)((bits >> 23) & 0xFF), pass, len = 0;
    unsigned long m = bits & 0x7FFFFFUL;
    const char *sign = neg ? "-" : (flags & 2) ? "+" : (flags & 4) ? " " : "";
    int first = 0, x = 0, gstrip = 0, special = ex == 255;
    unsigned conv = c;
    int up = c < 'a';
    if (!special) {
        if (conv == 'a' || conv == 'A') {
            int e;
            if (ex)
                m |= 0x800000UL, e = ex - 127;
            else if (m) {
                e = -126;
                while (!(m & 0x800000UL)) {
                    m <<= 1;
                    --e;
                }
            } else
                e = 0;
            for (pass = 0; pass < 2; ++pass) {
                o_fn = pass ? out : 0;
                o_ctx = ctx;
                o_n = 0;
                if (pass && !(flags & 1) && !(flags & 16))
                    putn(' ', (int)width - len);
                for (first = 0; sign[first]; ++first)
                    put(sign[first]);
                put('0');
                put(c == 'A' ? 'X' : 'x');
                if (pass && !(flags & 1) && (flags & 16))
                    putn('0', (int)width - len);
                hexbody(c, flags, prec, m, e);
                if (pass && (flags & 1))
                    putn(' ', (int)width - len);
                if (!pass)
                    len = o_n;
            }
            return o_n;
        }
        if (prec < 0)
            prec = 6;
        if (ex)
            m |= 0x800000UL;
        else
            ex = 1;
        expand(m, ex - 150);
        if (conv == 'g' || conv == 'G') {
            int p = prec ? prec : 1;
            /* the exponent %e would have with p significant digits */
            for (first = 0; first < nd && !dg[first]; ++first)
                ;
            if (first == nd)
                x = 0;
            else {
                round_at(first + p);
                for (first = 0; first < nd && !dg[first]; ++first)
                    ;
                x = ip - 1 - first;
            }
            gstrip = !(flags & 8);
            if (x < p && x >= -4) {
                conv = up ? 'F' : 'f';
                prec = p - 1 - x;
            } else {
                conv = up ? 'E' : 'e';
                prec = p - 1;
            }
        }
        if (conv == 'f' || conv == 'F') {
            round_at(ip + prec);
            for (first = 0; first < ip - 1 && !dg[first]; ++first)
                ;
        } else {
            for (first = 0; first < nd && !dg[first]; ++first)
                ;
            if (first >= nd) {          /* zero */
                first = ip - 1;
                x = 0;
            } else {
                round_at(first + 1 + prec);
                for (first = 0; first < nd && !dg[first]; ++first)
                    ;
                x = ip - 1 - first;
            }
        }
    }
    for (pass = 0; pass < 2; ++pass) {
        int i;
        o_fn = pass ? out : 0;
        o_ctx = ctx;
        o_n = 0;
        if (pass && !(flags & 1) && (special || !(flags & 16)))
            putn(' ', (int)width - len);
        for (i = 0; sign[i]; ++i)
            put(sign[i]);
        if (pass && !(flags & 1) && !special && (flags & 16))
            putn('0', (int)width - len);
        if (special) {
            const char *s = m ? (up ? "NAN" : "nan") : (up ? "INF" : "inf");
            while (*s)
                put(*s++);
        } else
            body(conv, flags, prec, first, x, gstrip);
        if (pass && (flags & 1))
            putn(' ', (int)width - len);
        if (!pass)
            len = o_n;
    }
    return o_n;
}
