/* rttest.c - the runtime (fastrt/: 16- and 32-bit multiply, divide, modulo; memcpy,
 * memmove, memset, strlen, strcpy, memcmp) against the tables of tools/genrt.py.
 *
 *   rttest [TABLE]          (default /RTTAB.BIN)
 *
 * Prints "rt NAME: N cases, F failures" per operation (and the first failures in hex),
 * then "RT PASS" or "RT FAIL". The checks use no multiply or divide (the expected values
 * come from the table; numbers are printed by subtraction), and the memory checks fill
 * and sum the buffer with byte loops, not with the functions under test. In the large
 * model the memory cases run twice: in a buffer in the code bank, and in a bank of its
 * own (hz_far_alloc), plus copies between the two.
 */
#include <string.h>
#include <horizon.h>

#define BUF 4096
/* vbcc -mtiny defines __MNEAR (not __MTINY, which its manual names) */
#if defined(__MTINY) || defined(__MNEAR)
#define RT_TINY 1
#endif
#define MAXSHOW 4

static int fh;
static unsigned char rb[2304];
static unsigned rpos, rlen;
static unsigned long total_fail;
static char staticbuf[BUF];
static char *buf;

/* ---- output without the runtime under test */

static void out(const char *s) { hz_puts(s); }

static void outu(unsigned long v)
{
    static const unsigned long p10[] = {1000000000UL, 100000000UL, 10000000UL, 1000000UL,
                                        100000UL, 10000UL, 1000UL, 100UL, 10UL, 1UL};
    char s[12];
    unsigned i, k = 0;
    unsigned char d;
    for (i = 0; i < 10; ++i) {
        d = 0;
        while (v >= p10[i]) {
            v -= p10[i];
            ++d;
        }
        if (d || k || i == 9)
            s[k++] = (char)('0' + d);
    }
    s[k] = 0;
    out(s);
}

static void outx(unsigned long v, unsigned digits)
{
    static const char hx[] = "0123456789ABCDEF";
    char s[10];
    unsigned i;
    for (i = 0; i < digits; ++i)
        s[i] = hx[(unsigned)(v >> ((digits - 1 - i) << 2)) & 15];
    s[digits] = 0;
    out("$");
    out(s);
}

/* ---- the table, streamed from the card */

static void *next(unsigned size)
{
    hz_io io;
    unsigned i, keep;
    int r;
    if (rlen - rpos < size) {
        keep = rlen - rpos;
        for (i = 0; i < keep; ++i)
            rb[i] = rb[rpos + i];
        rpos = 0;
        rlen = keep;
        io.handle = (unsigned char)fh;
        HZ_U24(io.buf, rb + rlen);
        io.len = (unsigned short)(sizeof(rb) - rlen);
        r = hz_read(&io);
        if (r > 0)
            rlen += (unsigned)r;
        if (rlen < size) {
            out("rt: the table ends too early\n");
            return 0;
        }
    }
    rpos += size;
    return rb + rpos - size;
}

static unsigned rd16(const unsigned char *p) { return p[0] | ((unsigned)p[1] << 8); }
static unsigned long rd32(const unsigned char *p)
{
    return rd16(p) | ((unsigned long)rd16(p + 2) << 16);
}

static const char *opname(unsigned op)
{
    switch (op) {
    case 1: return "mul16u";  case 12: return "mul16s";
    case 2: return "div16s";  case 3: return "div16u";
    case 4: return "mod16s";  case 5: return "mod16u";
    case 6: return "mul32u";  case 7: return "mul32s";
    case 8: return "div32s";  case 9: return "div32u";
    case 10: return "mod32s"; case 11: return "mod32u";
    }
    return "?";
}

/* volatile: the compiler must call the runtime, not fold anything */
static volatile unsigned va, vb;
static volatile int sa, sb;
static volatile unsigned long la, lb;
static volatile long sla, slb;

static unsigned long calc(unsigned op, unsigned long a, unsigned long b)
{
    switch (op) {
    case 1:  va = (unsigned)a; vb = (unsigned)b; return (unsigned)(va * vb);
    case 12: sa = (int)a; sb = (int)b; return (unsigned)(sa * sb);
    case 2:  sa = (int)a; sb = (int)b; return (unsigned)(sa / sb);
    case 3:  va = (unsigned)a; vb = (unsigned)b; return va / vb;
    case 4:  sa = (int)a; sb = (int)b; return (unsigned)(sa % sb);
    case 5:  va = (unsigned)a; vb = (unsigned)b; return va % vb;
    case 6:  la = a; lb = b; return la * lb;
    case 7:  sla = (long)a; slb = (long)b; return (unsigned long)(sla * slb);
    case 8:  sla = (long)a; slb = (long)b; return (unsigned long)(sla / slb);
    case 9:  la = a; lb = b; return la / lb;
    case 10: sla = (long)a; slb = (long)b; return (unsigned long)(sla % slb);
    case 11: la = a; lb = b; return la % lb;
    }
    return 0;
}

static void arith(unsigned op, unsigned count, unsigned size)
{
    unsigned i, fails = 0, w = size == 6 ? 4 : 8;
    unsigned long a, b, e, r;
    const unsigned char *p;
    for (i = 0; i < count; ++i) {
        if (!(p = next(size)))
            return;
        if (size == 6) {
            a = rd16(p); b = rd16(p + 2); e = rd16(p + 4);
        } else {
            a = rd32(p); b = rd32(p + 4); e = rd32(p + 8);
        }
        r = calc(op, a, b);
        if (r != e) {
            if (++fails <= MAXSHOW) {
                out("  "); out(opname(op)); out(" "); outx(a, w); out(", "); outx(b, w);
                out(": "); outx(r, w); out(", expected "); outx(e, w); out("\n");
            }
        }
    }
    out("rt "); out(opname(op)); out(": "); outu(count); out(" cases, "); outu(fails);
    out(" failures\n");
    total_fail += fails;
}

/* ---- memory and strings (the twin of genrt.py's mem_case) */

static void fill(unsigned lo, unsigned hi, unsigned x)
{
    unsigned i;
    for (i = lo; i < hi; ++i) {
        x += 0x9E3B;
        buf[i] = (char)((x >> 8) ^ x);
    }
}

static unsigned cksum(unsigned lo, unsigned hi)
{
    unsigned i, s1 = 0, s2 = 0;
    for (i = lo; i < hi; ++i) {
        s1 += (unsigned char)buf[i];
        s2 += s1;
    }
    return s1 ^ (s2 << 8) ^ (s2 >> 8);
}

static const char *fnname(unsigned fn)
{
    switch (fn) {
    case 1: return "memcpy";  case 2: return "memmove"; case 3: return "memset";
    case 4: return "strlen";  case 5: return "strcpy";  case 6: return "memcmp";
    }
    return "?";
}

static unsigned mfail[7], mcount[7];

static void memcase(const unsigned char *p)
{
    unsigned fn = rd16(p), n = rd16(p + 2), src = rd16(p + 4), dst = rd16(p + 6);
    unsigned seed = rd16(p + 8), extra = rd16(p + 10), xval = rd16(p + 12);
    unsigned eret = rd16(p + 14), eck = rd16(p + 16);
    unsigned alo, ahi, blo, bhi, i, ret = 0, ck, bad = 0, x = fn == 5;
    void *rp = 0;
    alo = src - 8;
    ahi = src + n + x + 8;
    blo = dst - 8;
    bhi = dst + n + x + 8;
    fill(alo, ahi, seed);
    fill(blo, bhi, fn == 6 ? seed : seed + 1);
    if (fn == 4 || fn == 5) {
        for (i = src; i < src + n; ++i)
            if (!buf[i])
                buf[i] = 0x55;
        buf[src + n] = 0;
    }
    switch (fn) {
    case 1: rp = memcpy(buf + dst, buf + src, n); break;
    case 2: rp = memmove(buf + dst, buf + src, n); break;
    case 3: rp = memset(buf + dst, (int)xval, n); break;
    case 4: ret = strlen(buf + src); break;
    case 5: rp = strcpy(buf + dst, buf + src); break;
    case 6:
        if (extra < n)
            buf[dst + extra] = (char)xval;
        ret = (unsigned)memcmp(buf + src, buf + dst, n);
        break;
    }
    x = cksum(blo, bhi);
    ck = cksum(alo, ahi) ^ ((x << 8) | (x >> 8));
    if (fn == 1 || fn == 2 || fn == 3 || fn == 5) {
        if (rp != (void *)(buf + dst))
            bad = 1;
    } else if (ret != eret)
        bad = 1;
    if (ck != eck)
        bad = 1;
    mcount[fn]++;
    if (bad && ++mfail[fn] <= MAXSHOW) {
        out("  "); out(fnname(fn)); out(" n "); outu(n); out(" src "); outu(src);
        out(" dst "); outu(dst); out(": result "); outx(ret, 4); out(" sum "); outx(ck, 4);
        out(", expected "); outx(eret, 4); out(" sum "); outx(eck, 4);
        if (rp && rp != (void *)(buf + dst))
            out(" (wrong pointer returned)");
        out("\n");
    }
}

static void memsection(unsigned count, const char *where)
{
    unsigned i, f;
    const unsigned char *p;
    for (i = 1; i <= 6; ++i)
        mfail[i] = mcount[i] = 0;
    for (i = 0; i < count; ++i) {
        if (!(p = next(18)))
            return;
        memcase(p);
    }
    for (f = 1; f <= 6; ++f) {
        out("rt "); out(fnname(f)); out(where); out(": "); outu(mcount[f]); out(" cases, ");
        outu(mfail[f]); out(" failures\n");
        total_fail += mfail[f];
    }
}

static int open_table(const char *path)
{
    fh = hz_open(path, HZ_O_READ);
    rpos = rlen = 0;
    if (fh < 0) {
        out("rt: cannot open "); out(path); out(": "); out(hz_strerror(hz_errno)); out("\n");
        return -1;
    }
    return 0;
}

static int run_table(const char *path, const char *where)
{
    const unsigned char *p;
    unsigned op, count, size;
    if (open_table(path))
        return -1;
    for (;;) {
        if (!(p = next(6)))
            break;
        op = rd16(p); count = rd16(p + 2); size = rd16(p + 4);
        if (!op)
            break;
        if (op == 20)
            memsection(count, where);
        else if (!*where)
            arith(op, count, size);
        else {                                  /* second pass: skip the arithmetic */
            while (count--)
                next(size);
        }
    }
    hz_close(fh);
    return 0;
}

#ifndef RT_TINY
/* copies between the code bank and another bank */
static void crossbank(char *far)
{
    unsigned i, c1, c2, fails = 0;
    char *save = buf;
    for (i = 0; i < 1000; ++i)
        staticbuf[i] = (char)(i * 7 + 3);
    memcpy(far + 100, staticbuf, 1000);
    memmove(staticbuf + 1001, far + 100, 1000);
    buf = staticbuf; c1 = cksum(0, 1000); c2 = cksum(1001, 2001);
    if (c1 != c2) ++fails;
    buf = far; c2 = cksum(100, 1100);
    if (c1 != c2) ++fails;
    memset(far + 5000, 'x', 3000);
    for (i = 5000; i < 8000; ++i)
        if (far[i] != 'x') { ++fails; break; }
    if (memcmp(far + 100, staticbuf, 1000) != 0) ++fails;
    buf = save;
    out("rt crossbank: 4 checks, "); outu(fails); out(" failures\n");
    total_fail += fails;
}
#endif

int main(int argc, char **argv)
{
    const char *path = argc > 1 ? argv[1] : "/RTTAB.BIN";
    unsigned long t_start = hz_uptime();
    out("rt: the runtime against ");
    out(path);
#ifdef RT_TINY
    out(" (tiny model)\n");
#else
    out(" (large model)\n");
#endif
    buf = staticbuf;
    if (run_table(path, ""))
        return 2;
#ifndef RT_TINY
    {
        char *far = (char *)hz_far_alloc();
        if (!far) {
            out("rt: no bank for the far pass\n");
            total_fail++;
        } else {
            buf = far;
            run_table(path, " (far bank)");
            crossbank(far);
        }
    }
#endif
    out("rt: ");
    outu(hz_uptime() - t_start);
    out(" ms in all\n");
    out(total_fail ? "RT FAIL\n" : "RT PASS\n");
    return total_fail ? 1 : 0;
}
