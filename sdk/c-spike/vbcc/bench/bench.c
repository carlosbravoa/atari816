/* bench.c - the same file for every compiler tried. The port supplies:
 *   unsigned long bench_ms(void);        milliseconds (Horizon uptime, 32 bits)
 *   void bench_out(const char *name, unsigned long ms, unsigned long check);
 * Call bench_all() from main. Do not change this file; report if it needs a change.
 */
extern unsigned long bench_ms(void);
extern void bench_out(const char *name, unsigned long ms, unsigned long check);

#define SIEVE_N 8190
static unsigned char flags[SIEVE_N + 1];
static unsigned int  words[2000];
static char          sbuf[4096], dbuf[4096];

static unsigned int sieve(void) {            /* 8-bit data, 16-bit indexes */
    unsigned int i, k, count = 0, iter;
    for (iter = 0; iter < 10; iter++) {
        count = 0;
        for (i = 0; i <= SIEVE_N; i++) flags[i] = 1;
        for (i = 0; i <= SIEVE_N; i++) {
            if (flags[i]) {
                unsigned int prime = i + i + 3;
                for (k = i + prime; k <= SIEVE_N; k += prime) flags[k] = 0;
                count++;
            }
        }
    }
    return count;                            /* 1899 */
}

static unsigned int sum16(void) {            /* 16-bit data */
    unsigned int i, r, s = 0;
    for (i = 0; i < 2000; i++) words[i] = i * 7 + 3;
    for (r = 0; r < 50; r++)
        for (i = 0; i < 2000; i++) s += words[i] ^ r;
    return s;
}

static unsigned long mul32(void) {           /* 32-bit arithmetic */
    unsigned long x = 12345, s = 0;
    unsigned int i;
    for (i = 0; i < 5000; i++) {
        x = x * 1103515245UL + 12345UL;
        s += (x >> 16) & 0x7FFF;
        s ^= x / 7;
    }
    return s;
}

static unsigned int fib(unsigned int n) {    /* calls */
    return n < 2 ? n : fib(n - 1) + fib(n - 2);
}

static unsigned int strs(void) {             /* pointers and bytes */
    unsigned int i, r, n = 0;
    char *p, *q;
    for (i = 0; i < 4095; i++) sbuf[i] = (char)('a' + i % 26);
    sbuf[4095] = 0;
    for (r = 0; r < 20; r++) {
        p = sbuf; q = dbuf;
        while ((*q++ = *p++) != 0) ;
        for (p = dbuf; *p; p++) if (*p == 'e') n++;
    }
    return n;
}

struct pt { int x, y; };
static struct pt pts[200];
static long structs(void) {                  /* structures, signed, shifts */
    int i, r; long acc = 0;
    for (i = 0; i < 200; i++) { pts[i].x = i * 3 - 100; pts[i].y = 50 - i; }
    for (r = 0; r < 50; r++)
        for (i = 0; i < 200; i++) {
            struct pt *p = &pts[i];
            p->x += p->y >> 2;
            p->y -= p->x >> 3;
            acc += (long)p->x * p->y;
        }
    return acc;
}

void bench_all(void) {
    unsigned long t; unsigned long c;
    t = bench_ms(); c = sieve();        bench_out("sieve",   bench_ms() - t, c);
    t = bench_ms(); c = sum16();        bench_out("sum16",   bench_ms() - t, c);
    t = bench_ms(); c = mul32();        bench_out("mul32",   bench_ms() - t, c);
    t = bench_ms(); c = fib(22);        bench_out("fib22",   bench_ms() - t, c);
    t = bench_ms(); c = strs();         bench_out("strs",    bench_ms() - t, c);
    t = bench_ms(); c = (unsigned long)structs(); bench_out("structs", bench_ms() - t, c);
}
