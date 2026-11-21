/* stdlib.c - heap (first fit, from the end of bss up to the software stack), exit, numbers */
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <horizon.h>

extern char __heap_start[];
extern unsigned __sp;             /* the software stack pointer (direct page) */

struct blk { unsigned size; struct blk *next; };   /* size includes the header; free list */
static struct blk *freel;
static char *brk_p;

void *malloc(size_t n)
{
    struct blk **pp, *b;
    unsigned need;
    if (n == 0) n = 1;
    if (n > 60000u) return NULL;
    need = (n + sizeof(struct blk) + 1) & ~1u;
    for (pp = &freel; (b = *pp) != NULL; pp = &b->next) {
        if (b->size >= need) {
            if (b->size - need >= 16) {
                struct blk *r = (struct blk *)((char *)b + need);
                r->size = b->size - need;
                r->next = b->next;
                *pp = r;
                b->size = need;
            } else
                *pp = b->next;
            return (char *)b + sizeof(unsigned);
        }
    }
    if (!brk_p) brk_p = (char *)(((unsigned)__heap_start + 1) & ~1u);
    {
        unsigned top = (unsigned)&need - 1024u;      /* a local's address: near __sp */
        if ((unsigned)brk_p + need > top || (unsigned)brk_p + need < (unsigned)brk_p)
            return NULL;
    }
    b = (struct blk *)brk_p;
    brk_p += need;
    b->size = need;
    return (char *)b + sizeof(unsigned);
}

void free(void *p)
{
    struct blk *b;
    if (!p) return;
    b = (struct blk *)((char *)p - sizeof(unsigned));
    b->next = freel;
    freel = b;
}

void *calloc(size_t n, size_t m)
{
    unsigned long t = (unsigned long)n * m;
    void *p;
    if (t > 60000u) return NULL;
    p = malloc((size_t)t);
    if (p) memset(p, 0, (size_t)t);
    return p;
}

void *realloc(void *p, size_t n)
{
    struct blk *b;
    void *q;
    if (!p) return malloc(n);
    b = (struct blk *)((char *)p - sizeof(unsigned));
    if (b->size - sizeof(unsigned) >= n) return p;
    q = malloc(n);
    if (q) { memcpy(q, p, b->size - sizeof(unsigned)); free(p); }
    return q;
}

static void (*atx[8])(void);
static int natx;
int atexit(void (*f)(void)) { if (natx == 8) return -1; atx[natx++] = f; return 0; }

void exit(int code)
{
    while (natx) atx[--natx]();
    fflush(stdout);
    for (;;) hz_sys(SYS_EXIT, (unsigned)code, 0, 0);
}

void abort(void) { fflush(stdout); hz_puts("abort\n"); for (;;) hz_sys(SYS_EXIT, 134, 0, 0); }

void __assert_fail(const char *e, const char *file, int line)
{
    printf("assertion failed: %s (%s:%d)\n", e, file, line);
    abort();
}

int abs(int x) { return x < 0 ? -x : x; }
long labs(long x) { return x < 0 ? -x : x; }

unsigned long strtoul(const char *s, char **end, int base)
{
    unsigned long v = 0;
    int neg = 0;
    while (*s == ' ' || *s == '\t' || *s == '\n') s++;
    if (*s == '-') { neg = 1; s++; } else if (*s == '+') s++;
    if ((base == 0 || base == 16) && s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) { s += 2; base = 16; }
    else if (base == 0 && s[0] == '0') base = 8;
    else if (base == 0) base = 10;
    for (;;) {
        int c = *s, d;
        if (c >= '0' && c <= '9') d = c - '0';
        else if (c >= 'a' && c <= 'z') d = c - 'a' + 10;
        else if (c >= 'A' && c <= 'Z') d = c - 'A' + 10;
        else break;
        if (d >= base) break;
        v = v * base + d;
        s++;
    }
    if (end) *end = (char *)s;
    return neg ? -v : v;
}
long strtol(const char *s, char **end, int base) { return (long)strtoul(s, end, base); }
int atoi(const char *s) { return (int)strtol(s, NULL, 10); }
long atol(const char *s) { return strtol(s, NULL, 10); }

static unsigned long seed = 1;
int rand(void) { seed = seed * 1103515245UL + 12345; return (int)((seed >> 16) & 0x7FFF); }
void srand(unsigned s) { seed = s; }

div_t div(int a, int b) { div_t r; r.quot = a / b; r.rem = a % b; return r; }
ldiv_t ldiv(long a, long b) { ldiv_t r; r.quot = a / b; r.rem = a % b; return r; }

static void swapb(char *a, char *b, size_t n) { while (n--) { char t = *a; *a++ = *b; *b++ = t; } }

void qsort(void *base, size_t n, size_t size, int (*cmp)(const void *, const void *))
{
    /* insertion sort for small n, else a simple quicksort (last element pivot) */
    char *b = base;
    size_t i, j;
    if (n < 2) return;
    if (n <= 8) {
        for (i = 1; i < n; i++)
            for (j = i; j > 0 && cmp(b + (j - 1) * size, b + j * size) > 0; j--)
                swapb(b + (j - 1) * size, b + j * size, size);
        return;
    }
    swapb(b + (n / 2) * size, b + (n - 1) * size, size);
    for (i = j = 0; j < n - 1; j++)
        if (cmp(b + j * size, b + (n - 1) * size) < 0) {
            swapb(b + i * size, b + j * size, size);
            i++;
        }
    swapb(b + i * size, b + (n - 1) * size, size);
    qsort(b, i, size, cmp);
    qsort(b + (i + 1) * size, n - i - 1, size, cmp);
}

void *bsearch(const void *key, const void *base, size_t n, size_t size, int (*cmp)(const void *, const void *))
{
    const char *b = base;
    while (n) {
        const char *m = b + (n / 2) * size;
        int c = cmp(key, m);
        if (c == 0) return (void *)m;
        if (c > 0) { b = m + size; n = n - n / 2 - 1; } else n /= 2;
    }
    return NULL;
}
int errno;
