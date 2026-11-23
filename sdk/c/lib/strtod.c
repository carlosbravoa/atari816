/* strtod.c - strtod, strtof, strtold, atof for cc816: a decimal or hexadecimal number ->
 * float (double and long double are the same 32-bit format).
 *
 * Exact: the result is the input rounded to nearest (ties to even), however many digits
 * it has. The digits (the first 120 significant ones; any digit after them only counts as
 * "more than zero", which is enough: no float's halfway point has more digits) become a
 * big integer D and the value is D * 10^E: for E >= 0 the product is made and its top bits
 * taken; for E < 0 the quotient D * 2^k / 10^-E is found by long division to 27 bits, the
 * remainder telling whether anything is left. Big integers: 16-bit limbs, at most 640 bits.
 * Accepted: white space, a sign, digits with one '.', an exponent (e or E, a sign, digits),
 * 0x hexadecimal (with a p exponent), inf, infinity, nan, nan(...), in any case.
 * ERANGE when the result overflows to infinity or a nonzero input becomes 0.
 */
#include <stdlib.h>
#include <errno.h>
#include <stdint.h>

#define NL 40                   /* limbs: 640 bits */
#define MAXD 120                /* significant digits kept */

typedef struct {
    unsigned n;                 /* limbs in use (no zero limb on top) */
    uint16_t l[NL];
} big;

static big A, B;

static void b_set(big *a, uint16_t v)
{
    a->l[0] = v;
    a->n = v ? 1 : 0;
}

static void b_muladd(big *a, uint16_t m, uint16_t add)
{
    uint32_t c = add;
    unsigned i;
    for (i = 0; i < a->n; ++i) {
        c += (uint32_t)a->l[i] * m;
        a->l[i] = (uint16_t)c;
        c >>= 16;
    }
    if (c && a->n < NL)
        a->l[a->n++] = (uint16_t)c;
}

static void b_pow10(big *a, unsigned e)
{
    for (; e >= 4; e -= 4)
        b_muladd(a, 10000, 0);
    while (e--)
        b_muladd(a, 10, 0);
}

static unsigned b_bits(const big *a)
{
    uint16_t t;
    unsigned n;
    if (!a->n)
        return 0;
    n = (a->n - 1) * 16;
    for (t = a->l[a->n - 1]; t; t >>= 1)
        ++n;
    return n;
}

static void b_shl(big *a, unsigned k)
{
    unsigned w = k >> 4, s = k & 15, i;
    if (!a->n)
        return;
    if (s) {
        uint16_t c = 0;
        for (i = 0; i < a->n; ++i) {
            uint16_t v = a->l[i];
            a->l[i] = (uint16_t)((v << s) | c);
            c = (uint16_t)(v >> (16 - s));
        }
        if (c && a->n < NL)
            a->l[a->n++] = c;
    }
    if (w) {
        if (a->n + w > NL)
            w = NL - a->n;
        for (i = a->n; i-- > 0;)
            a->l[i + w] = a->l[i];
        for (i = 0; i < w; ++i)
            a->l[i] = 0;
        a->n += w;
    }
}

static void b_shr1(big *a)
{
    unsigned i;
    for (i = 0; i < a->n; ++i) {
        a->l[i] >>= 1;
        if (i + 1 < a->n && (a->l[i + 1] & 1))
            a->l[i] |= 0x8000;
    }
    while (a->n && !a->l[a->n - 1])
        --a->n;
}

static int b_cmp(const big *a, const big *b)
{
    unsigned i;
    if (a->n != b->n)
        return a->n < b->n ? -1 : 1;
    for (i = a->n; i-- > 0;)
        if (a->l[i] != b->l[i])
            return a->l[i] < b->l[i] ? -1 : 1;
    return 0;
}

static void b_sub(big *a, const big *b)          /* a -= b, a >= b */
{
    unsigned i;
    uint16_t br = 0;
    for (i = 0; i < a->n; ++i) {
        uint16_t x = a->l[i], y = i < b->n ? b->l[i] : 0;
        uint16_t d = (uint16_t)(x - y - br);
        br = (uint16_t)(x < y || (x == y && br));
        a->l[i] = d;
    }
    while (a->n && !a->l[a->n - 1])
        --a->n;
}

static unsigned long bits_of(float f)
{
    union { float f; unsigned long u; } v;
    v.f = f;
    return v.u;
}

static float float_of(unsigned long u)
{
    union { float f; unsigned long u; } v;
    v.u = u;
    return v.f;
}

/* q * 2^-k (q > 0, below 2^31), plus a sticky bit: something more than zero is left
 * below q -> the float, rounded to nearest even */
static float mk(uint32_t q, int k, int sticky, int neg)
{
    unsigned bl = 0;
    int be, drop;
    uint32_t t, r, half;
    unsigned long s = neg ? 0x80000000UL : 0;
    for (t = q; t; t >>= 1)
        ++bl;
    while (bl < 26) {
        q <<= 1;
        ++k;
        ++bl;
    }
    be = (int)bl - 1 - k + 127;
    drop = (int)bl - 24;
    if (be < 1) {
        drop += 1 - be;
        be = 0;
    }
    if (drop > (int)bl) {
        errno = ERANGE;
        return float_of(s);
    }
    half = (uint32_t)1 << (drop - 1);
    r = q & ((half << 1) - 1);
    q = drop >= 32 ? 0 : q >> drop;
    if (r > half || (r == half && (sticky || (q & 1))))
        ++q;
    if (be == 0) {
        if (!q)
            errno = ERANGE;
        return float_of(s | q);         /* 2^23 is the smallest normal: still right */
    }
    if (q == 0x1000000UL) {
        q >>= 1;
        ++be;
    }
    if (be >= 255) {
        errno = ERANGE;
        return float_of(s | 0x7F800000UL);
    }
    return float_of(s | ((unsigned long)be << 23) | (q & 0x7FFFFFUL));
}

static int lower(int c)
{
    return c >= 'A' && c <= 'Z' ? c + 32 : c;
}

static int word(const char *s, const char *w)  /* s starts with w (any case) */
{
    for (; *w; ++s, ++w)
        if (lower((unsigned char)*s) != *w)
            return 0;
    return 1;
}

static int hexval(int c)
{
    if (c >= '0' && c <= '9')
        return c - '0';
    c = lower(c);
    if (c >= 'a' && c <= 'f')
        return c - 'a' + 10;
    return -1;
}

/* the exponent after e/E or p/P: s at the letter; -> the value, *end after it (or s when
 * no digit follows, so the letter is not part of the number) */
static long expo(const char *s, const char **end)
{
    const char *p = s + 1;
    int neg = 0;
    long e = 0;
    if (*p == '+' || *p == '-')
        neg = *p++ == '-';
    if (*p < '0' || *p > '9') {
        *end = s;
        return 0;
    }
    while (*p >= '0' && *p <= '9') {
        if (e < 100000L)
            e = e * 10 + (*p - '0');
        ++p;
    }
    *end = p;
    return neg ? -e : e;
}

static float hexnum(const char *s, const char **end, int neg)
{
    uint32_t q = 0;
    int any = 0, sticky = 0, dot = 0;
    long k = 0;                         /* value = q * 2^-k */
    int d;
    const char *p = s;
    for (;; ++p) {
        if (*p == '.' && !dot) {
            dot = 1;
            continue;
        }
        d = hexval((unsigned char)*p);
        if (d < 0)
            break;
        any = 1;
        if (q < 0x01000000UL) {         /* up to 28 bits kept */
            q = q * 16 + (uint32_t)d;
            if (dot)
                k += 4;
        } else {
            sticky |= d != 0;
            if (!dot)
                k -= 4;
        }
    }
    if (!any)
        return -1.0f;                   /* (the caller sees: no digits) */
    if (lower((unsigned char)*p) == 'p') {
        const char *e;
        long x = expo(p, &e);
        k -= x;
        p = e;
    }
    *end = p;
    if (!q)
        return float_of(neg ? 0x80000000UL : 0);
    if (k > 400)
        k = 400;
    if (k < -400)
        k = -400;
    return mk(q, (int)k, sticky, neg);
}

double strtod(const char *s, char **endp)
{
    static unsigned char dig[MAXD];
    const char *p = s;
    int neg = 0, sticky = 0, any = 0, dot = 0;
    unsigned nd = 0, i;
    long e10 = 0;
    float r;
    while (*p == ' ' || (*p >= 9 && *p <= 13))
        ++p;
    if (*p == '+' || *p == '-')
        neg = *p++ == '-';
    if (word(p, "inf")) {
        p += word(p, "infinity") ? 8 : 3;
        r = float_of((neg ? 0x80000000UL : 0) | 0x7F800000UL);
        goto done;
    }
    if (word(p, "nan")) {
        unsigned long pay = 0;
        p += 3;
        if (*p == '(') {
            /* nan(n-chars): a number (C's base 0) is the payload, as glibc */
            const char *q = p + 1;
            char *e;
            while ((*q >= '0' && *q <= '9') || (lower((unsigned char)*q) >= 'a' &&
                   lower((unsigned char)*q) <= 'z') || *q == '_')
                ++q;
            if (*q == ')') {
                pay = strtoul(p + 1, &e, 0);
                if (e != q)
                    pay = 0;
                p = q + 1;
            }
        }
        r = float_of((neg ? 0x80000000UL : 0) | 0x7FC00000UL | (pay & 0x3FFFFFUL));
        goto done;
    }
    if (p[0] == '0' && lower((unsigned char)p[1]) == 'x' &&
        (hexval((unsigned char)p[2]) >= 0 || (p[2] == '.' && hexval((unsigned char)p[3]) >= 0))) {
        const char *e;
        r = hexnum(p + 2, &e, neg);
        p = e;
        goto done;
    }
    for (;; ++p) {
        if (*p == '.' && !dot) {
            dot = 1;
            continue;
        }
        if (*p < '0' || *p > '9')
            break;
        any = 1;
        if (*p == '0' && !nd) {         /* a leading zero */
            if (dot)
                --e10;
            continue;
        }
        if (nd < MAXD) {
            dig[nd++] = (unsigned char)(*p - '0');
            if (dot)
                --e10;
        } else {
            sticky |= *p != '0';
            if (!dot)
                ++e10;
        }
    }
    if (!any) {
        if (endp)
            *endp = (char *)s;
        return 0.0;
    }
    if (lower((unsigned char)*p) == 'e') {
        const char *e;
        long x = expo(p, &e);
        e10 += x;
        p = e;
    }
    if (!nd) {
        r = float_of(neg ? 0x80000000UL : 0);
        goto done;
    }
    /* value = D * 10^e10, D = the nd digits: the leading digit's power of 10 */
    if (e10 + (long)nd - 1 >= 39) {
        errno = ERANGE;
        r = float_of((neg ? 0x80000000UL : 0) | 0x7F800000UL);
        goto done;
    }
    if (e10 + (long)nd - 1 <= -47) {
        errno = ERANGE;
        r = float_of(neg ? 0x80000000UL : 0);
        goto done;
    }
    b_set(&A, 0);
    for (i = 0; i < nd; ++i) {
        if (!A.n)
            b_set(&A, dig[i]);
        else
            b_muladd(&A, 10, dig[i]);
    }
    if (e10 >= 0) {
        unsigned bl, j;
        uint32_t q = 0;
        b_pow10(&A, (unsigned)e10);
        bl = b_bits(&A);
        /* the top 26 bits, the rest sticky */
        for (j = 0; j < 26 && j < bl; ++j) {
            unsigned b = bl - 1 - j;
            q = (q << 1) | ((A.l[b >> 4] >> (b & 15)) & 1);
        }
        if (bl > 26) {
            unsigned b;
            for (b = 0; b < bl - 26 && !sticky; ++b)
                if ((A.l[b >> 4] >> (b & 15)) & 1)
                    sticky = 1;
            r = mk(q, -(int)(bl - 26), sticky, neg);
        } else
            r = mk(q, 0, sticky, neg);      /* D * 10^e10 itself */
    } else {
        int k;
        unsigned j;
        uint32_t q = 0;
        b_set(&B, 1);
        b_pow10(&B, (unsigned)-e10);
        k = (int)b_bits(&B) - (int)b_bits(&A) + 26;
        if (k > 0)
            b_shl(&A, (unsigned)k);
        else if (k < 0)
            b_shl(&B, (unsigned)-k);
        b_shl(&B, 26);
        for (j = 0; j <= 26; ++j) {
            q <<= 1;
            if (b_cmp(&A, &B) >= 0) {
                b_sub(&A, &B);
                q |= 1;
            }
            b_shr1(&B);
        }
        r = mk(q, k, sticky || A.n != 0, neg);
    }
done:
    if (endp)
        *endp = (char *)p;
    return r;
}

float strtof(const char *s, char **endp)
{
    return strtod(s, endp);
}

long double strtold(const char *s, char **endp)
{
    return strtod(s, endp);
}

double atof(const char *s)
{
    return strtod(s, (char **)0);
}
