/* fptest.c - cc816's floating point against the table of genfp.py, bit for bit.
 *
 *   fptest [TABLE [TEXT [MATH]]]   (default /FPTAB.BIN /FMTTAB.TXT /MATHTAB.BIN)
 *
 * TABLE (genfp.py): each record names an operation, its operands and the expected
 * result's bits; the operation is done with C's operators on volatile floats (so the
 * compiler's code and the runtime helpers are what is tested). TEXT (genfmt.py): sprintf
 * of a float with a format, and strtod of a string, against glibc's results. MATH
 * (mathhost.sh --table): math.h's functions against the same C built for the host (so the
 * compiler and the soft float must give its results bit for bit). Prints
 * "fp NAME: N cases, F failures" per operation (and the first failures), then "FPU PASS"
 * or "FPU FAIL".
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#define NOPS 18
static const char *const names[NOPS] = {
    "", "add", "sub", "mul", "div", "cmp", "ftol", "ftoul", "ltof", "ultof", "ftoi", "ftou",
    "itof", "utof", "neg", "ftob", "ftosc", "uctof"};
static unsigned long ncase[NOPS], nfail[NOPS];

typedef union { float f; unsigned long u; long l; } fu;

static volatile float X, Y;
static unsigned char rec[16 * 64];

static unsigned long rd32(const unsigned char *p)
{
    return (unsigned long)p[0] | (unsigned long)p[1] << 8 | (unsigned long)p[2] << 16 |
           (unsigned long)p[3] << 24;
}

/* mathacc.c's order: op 100 + this index */
static const char *const mnames[] = {
    "sqrt", "fabs", "floor", "ceil", "trunc", "round", "rint", "fmod", "remainder", "sin",
    "cos", "tan", "atan", "atan2", "asin", "acos", "exp", "exp2", "expm1", "log", "log10",
    "log2", "log1p", "pow", "cbrt", "hypot", "sinh", "cosh", "tanh"};
#define NMATH (sizeof mnames / sizeof mnames[0])
static unsigned long mcase[NMATH], mfail[NMATH];

static float mathop(unsigned k, float x, float y)
{
    switch (k) {
    case 0: return sqrt(x);
    case 1: return fabs(x);
    case 2: return floor(x);
    case 3: return ceil(x);
    case 4: return trunc(x);
    case 5: return round(x);
    case 6: return rint(x);
    case 7: return fmod(x, y);
    case 8: return remainder(x, y);
    case 9: return sin(x);
    case 10: return cos(x);
    case 11: return tan(x);
    case 12: return atan(x);
    case 13: return atan2(x, y);
    case 14: return asin(x);
    case 15: return acos(x);
    case 16: return exp(x);
    case 17: return exp2(x);
    case 18: return expm1(x);
    case 19: return log(x);
    case 20: return log10(x);
    case 21: return log2(x);
    case 22: return log1p(x);
    case 23: return pow(x, y);
    case 24: return cbrt(x);
    case 25: return hypot(x, y);
    case 26: return sinh(x);
    case 27: return cosh(x);
    default: return tanh(x);
    }
}

static unsigned long run(unsigned op, unsigned long a, unsigned long b)
{
    fu x, y, r;
    volatile long vl;
    volatile unsigned long vul;
    volatile int vi;
    volatile unsigned vu;
    volatile unsigned char vuc;
    x.u = a;
    y.u = b;
    X = x.f;
    Y = y.f;
    r.u = 0;
    switch (op) {
    case 1: r.f = X + Y; break;
    case 2: r.f = X - Y; break;
    case 3: r.f = X * Y; break;
    case 4: r.f = X / Y; break;
    case 5:
        r.u = (unsigned long)((X < Y) | (X <= Y) << 1 | (X > Y) << 2 | (X >= Y) << 3 |
                              (X == Y) << 4 | (X != Y) << 5);
        break;
    case 6: r.l = (long)X; break;
    case 7: r.u = (unsigned long)X; break;
    case 8: vl = (long)a; r.f = (float)vl; break;
    case 9: vul = a; r.f = (float)vul; break;
    case 10: r.u = (unsigned)(int)X; break;
    case 11: r.u = (unsigned)X; break;
    case 12: vi = (int)(unsigned)a; r.f = (float)vi; break;
    case 13: vu = (unsigned)a; r.f = (float)vu; break;
    case 14: r.f = -X; break;
    case 15: r.u = (_Bool)X; break;
    case 16: r.u = (unsigned)(int)(signed char)X; break;
    case 17: vuc = (unsigned char)a; r.f = (float)vuc; break;
    }
    return r.u;
}

int main(int argc, char **argv)
{
    const char *name = argc > 1 ? argv[1] : "/FPTAB.BIN";
    FILE *f = fopen(name, "rb");
    unsigned long total = 0, fails = 0;
    unsigned i, n, op, shown = 0;
    if (!f) {
        printf("fptest: cannot open %s\nFPU FAIL\n", name);
        return 1;
    }
    for (;;) {
        n = (unsigned)fread(rec, 16, 64, f);
        if (!n)
            break;
        for (i = 0; i < n; ++i) {
            const unsigned char *p = rec + 16 * i;
            unsigned long a, b, e, g;
            op = p[0] | (unsigned)p[1] << 8;
            if (!op || op >= NOPS)
                goto end;
            a = rd32(p + 4);
            b = rd32(p + 8);
            e = rd32(p + 12);
            g = run(op, a, b);
            ++ncase[op];
            ++total;
            if (g != e) {
                ++nfail[op];
                ++fails;
                if (shown < 24) {
                    ++shown;
                    printf("  %s %08lX %08lX: %08lX, want %08lX\n", names[op], a, b, g, e);
                }
            }
        }
    }
end:
    fclose(f);
    f = fopen(argc > 2 ? argv[2] : "/FMTTAB.TXT", "r");
    if (f) {
        static char line[300], out[300];
        unsigned long np = 0, fp = 0, ns = 0, fs = 0;
        while (fgets(line, sizeof line, f)) {
            char *t1, *t2, *t3, *nl;
            nl = strchr(line, '\n');
            if (nl)
                *nl = 0;
            t1 = strchr(line, '\t');
            if (!t1)
                continue;
            *t1++ = 0;
            t2 = strchr(t1, '\t');
            if (!t2)
                continue;
            *t2++ = 0;
            t3 = strchr(t2, '\t');
            if (!t3)
                continue;
            *t3++ = 0;
            if (line[0] == 'P') {
                fu v;
                v.u = strtoul(t1, 0, 16);
                ++np;
                sprintf(out, t2, v.f);
                if (strcmp(out, t3)) {
                    ++fp;
                    if (shown < 60) {
                        ++shown;
                        printf("  printf(\"%s\", %s): \"%s\", want \"%s\"\n", t2, t1, out, t3);
                    }
                }
            } else {
                fu v;
                char *end;
                unsigned long want = strtoul(t2, 0, 16);
                unsigned used = (unsigned)atoi(t3);
                v.f = strtod(t1, &end);
                ++ns;
                if (v.u != want || (unsigned)(end - t1) != used) {
                    ++fs;
                    if (shown < 60) {
                        ++shown;
                        printf("  strtod(\"%s\"): %08lX used %u, want %08lX used %u\n", t1, v.u,
                               (unsigned)(end - t1), want, used);
                    }
                }
            }
        }
        fclose(f);
        printf("fp printf: %lu cases, %lu failures\n", np, fp);
        printf("fp strtod: %lu cases, %lu failures\n", ns, fs);
        total += np + ns;
        fails += fp + fs;
    }
    f = fopen(argc > 3 ? argv[3] : "/MATHTAB.BIN", "rb");
    if (f) {
        for (;;) {
            n = (unsigned)fread(rec, 16, 64, f);
            if (!n)
                break;
            for (i = 0; i < n; ++i) {
                const unsigned char *p = rec + 16 * i;
                unsigned k;
                fu x, y, r;
                unsigned long e;
                op = p[0] | (unsigned)p[1] << 8;
                if (op < 100 || op >= 100 + NMATH)
                    goto mend;
                k = op - 100;
                x.u = rd32(p + 4);
                y.u = rd32(p + 8);
                e = rd32(p + 12);
                r.f = mathop(k, x.f, y.f);
                ++mcase[k];
                ++total;
                if (r.u != e) {
                    ++mfail[k];
                    ++fails;
                    if (shown < 60) {
                        ++shown;
                        printf("  %s(%08lX, %08lX): %08lX, want %08lX\n", mnames[k], x.u, y.u,
                               r.u, e);
                    }
                }
            }
        }
mend:
        fclose(f);
        for (i = 0; i < NMATH; ++i)
            if (mcase[i])
                printf("fp %s: %lu cases, %lu failures\n", mnames[i], mcase[i], mfail[i]);
    }
    for (op = 1; op < NOPS; ++op)
        if (ncase[op])
            printf("fp %s: %lu cases, %lu failures\n", names[op], ncase[op], nfail[op]);
    printf("fpu: %lu cases, %lu failures\n", total, fails);
    printf(fails ? "FPU FAIL\n" : "FPU PASS\n");
    return 0;
}
