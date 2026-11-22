/* malloc.c - malloc, free, calloc, realloc for cc816: the heap is the code bank from the
 * end of bss to the software stack's guard zone (rt/cc816/crt0.s: __hz_heapstart,
 * __hz_heapend). First fit on a free list kept in address order; free joins neighbours.
 * A block has a 4-byte header (the next free block, the size); sizes are even.
 * hz_heap_free, hz_heap_largest, hz_heap_peak (horizon.h): what is free now, and the most
 * in use since the start (crt0.s keeps the counts: hcc --debug prints them at exit). */
#include <horizon.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

typedef struct blk {
    struct blk *next;           /* free: the next free block (in address order) */
    unsigned size;              /* the whole block, header included */
} blk;

#define HDR sizeof(blk)
extern char *__hz_heapstart, *__hz_heapend;
static blk *freel;
static unsigned char ready;
extern unsigned __hz_heapuse, __hz_heappeak;

static void used(unsigned n)
{
    __hz_heapuse += n;
    if (__hz_heapuse > __hz_heappeak)
        __hz_heappeak = __hz_heapuse;
}

static void init(void)
{
    unsigned a = ((unsigned)__hz_heapstart + 1) & ~1u;
    unsigned e = (unsigned)__hz_heapend & ~1u;
    ready = 1;
    if (e <= a + HDR + 2)
        return;
    freel = (blk *)a;
    freel->next = 0;
    freel->size = e - a;
}

void *malloc(size_t n)
{
    blk *b, **pp;
    unsigned need;
    if (!ready)
        init();
    if (n > 0xFFF0u - HDR)
        goto none;
    need = (n + HDR + 1) & ~1u;
    if (need < HDR + 2)
        need = HDR + 2;
    for (pp = &freel; (b = *pp) != 0; pp = &b->next) {
        if (b->size < need)
            continue;
        if (b->size - need >= HDR + 4) {        /* split: the end part is used */
            b->size -= need;
            b = (blk *)((char *)b + b->size);
            b->size = need;
        } else
            *pp = b->next;
        b->next = 0;
        used(b->size);
        return b + 1;
    }
none:
    errno = ENOMEM;
    return 0;
}

void free(void *p)
{
    blk *b, *q, *prev;
    if (!p)
        return;
    b = (blk *)p - 1;
    __hz_heapuse -= b->size;
    prev = 0;
    for (q = freel; q && q < b; q = q->next)
        prev = q;
    /* join with the next free block */
    if (q && (char *)b + b->size == (char *)q) {
        b->size += q->size;
        b->next = q->next;
    } else
        b->next = q;
    /* and with the one before */
    if (prev && (char *)prev + prev->size == (char *)b) {
        prev->size += b->size;
        prev->next = b->next;
    } else if (prev)
        prev->next = b;
    else
        freel = b;
}

void *calloc(size_t n, size_t size)
{
    unsigned long t = (unsigned long)n * size;
    void *p;
    if (t > 0xFFF0u) {
        errno = ENOMEM;
        return 0;
    }
    p = malloc((size_t)t);
    if (p)
        memset(p, 0, (size_t)t);
    return p;
}

void *realloc(void *p, size_t n)
{
    blk *b, *q, **pp;
    unsigned need, have;
    void *np;
    if (!p)
        return malloc(n);
    if (!n) {
        free(p);
        return 0;
    }
    if (n > 0xFFF0u - HDR) {
        errno = ENOMEM;
        return 0;
    }
    b = (blk *)p - 1;
    have = b->size;
    need = (n + HDR + 1) & ~1u;
    if (need < HDR + 2)
        need = HDR + 2;
    if (need <= have)
        return p;                       /* (a shrink keeps the block) */
    /* the free block right after it, when it is big enough */
    for (pp = &freel; (q = *pp) != 0 && q < b; pp = &q->next)
        ;
    if (q && (char *)b + have == (char *)q && have + q->size >= need) {
        if (have + q->size - need >= HDR + 4) {
            blk *r = (blk *)((char *)b + need);
            r->next = q->next;
            r->size = have + q->size - need;
            *pp = r;
            b->size = need;
        } else {
            *pp = q->next;
            b->size = have + q->size;
        }
        used(b->size - have);
        return p;
    }
    np = malloc(n);
    if (!np)
        return 0;
    memcpy(np, p, have - HDR);
    free(p);
    return np;
}

/* the heap's free bytes now (all the free blocks; each one's 4-byte header counted) */
unsigned hz_heap_free(void)
{
    blk *b;
    unsigned n = 0;
    if (!ready)
        init();
    for (b = freel; b; b = b->next)
        n += b->size;
    return n;
}

/* the biggest malloc that would work now */
unsigned hz_heap_largest(void)
{
    blk *b;
    unsigned n = 0;
    if (!ready)
        init();
    for (b = freel; b; b = b->next)
        if (b->size > n)
            n = b->size;
    return n > HDR ? n - HDR : 0;
}

/* the most bytes in use at once since the start (headers counted) */
unsigned hz_heap_peak(void)
{
    return __hz_heappeak;
}
