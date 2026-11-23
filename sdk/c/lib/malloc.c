/* malloc.c - malloc, free, calloc, realloc for cc816: the heap is the code bank from the
 * end of bss to the software stack's guard zone (rt/crt0.s: __hz_heapstart,
 * __hz_heapend). First fit on a free list kept in address order; free joins neighbours.
 * A block has a 4-byte header (the next free block, the size); sizes are even.
 * hz_heap_free, hz_heap_largest, hz_heap_peak (horizon.h): what is free now, and the most
 * in use since the start (crt0.s keeps the counts: hcc --debug prints them at exit). */
#include <horizon.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

#ifdef __CC816_FAR_DATA__
/* The far data model (hcc --data far): malloc returns far pointers. The heap is a list of
 * arenas, each in one bank: [0] the main bank's room (from the end of bss to the software
 * stack's guard zone), then whole banks from Horizon (hz_bank_alloc) when no arena has
 * room. Each arena is a first-fit free list in address order as above, with 16-bit links
 * (offsets in the arena's bank: a block never crosses a bank). A bank arena whose blocks
 * are all free goes back to Horizon while another bank arena is empty too (so one free
 * bank is kept against malloc/free of a big block in turn); Horizon frees the rest at the
 * program's end. */
typedef struct fblk {
    unsigned next;              /* free: the next free block's offset (0: none) */
    unsigned size;              /* the whole block, header included */
} fblk;

#define HDR 4
#define MAXAR 64
#define BANKLO 0x0002           /* a bank arena: offsets 2 to 0xFFFE (0 is "none") */
#define BANKHI 0xFFFEu
extern char __near *__hz_heapstart, __near *__hz_heapend;
static struct arena {
    unsigned char bank;
    unsigned freel;             /* the first free block's offset, 0: none */
    unsigned lo, hi;
} ar[MAXAR];
static unsigned nar;
static unsigned long inuse, peak;

static fblk *B(struct arena *a, unsigned off)
{
    return (fblk *)(((unsigned long)a->bank << 16) | off);
}

static void used(unsigned n)
{
    inuse += n;
    if (inuse > peak)
        peak = inuse;
}

static void init(void)
{
    unsigned a = ((unsigned)__hz_heapstart + 1) & ~1u;
    unsigned e = (unsigned)__hz_heapend & ~1u;
    fblk *b;
    nar = 1;
    ar[0].bank = HZ_BANK(&nar);         /* the main bank */
    ar[0].lo = a;
    ar[0].hi = e;
    ar[0].freel = 0;
    if (e <= a + HDR + 2)
        return;
    ar[0].freel = a;
    b = B(&ar[0], a);
    b->next = 0;
    b->size = e - a;
}

static void *take(struct arena *a, unsigned need)
{
    unsigned o, prev = 0;
    fblk *b;
    for (o = a->freel; o; prev = o, o = b->next) {
        b = B(a, o);
        if (b->size < need)
            continue;
        if (b->size - need >= HDR + 4) {        /* split: the end part is used */
            b->size -= need;
            o += b->size;
            b = B(a, o);
            b->size = need;
        } else if (prev)
            B(a, prev)->next = b->next;
        else
            a->freel = b->next;
        b->next = 0;
        used(b->size);
        return (char *)b + HDR;
    }
    return 0;
}

static int newbank(void)
{
    unsigned bk;
    struct arena *a;
    fblk *b;
    if (nar >= MAXAR)
        return 0;
    bk = hz_bank_alloc();
    if (hz_errno)
        return 0;
    a = &ar[nar++];
    a->bank = (unsigned char)bk;
    a->lo = BANKLO;
    a->hi = BANKHI;
    a->freel = BANKLO;
    b = B(a, BANKLO);
    b->next = 0;
    b->size = BANKHI - BANKLO;
    return 1;
}

static unsigned blocksize(size_t n)
{
    unsigned need = (n + HDR + 1) & ~1u;
    return need < HDR + 2 ? HDR + 2 : need;
}

void *malloc(size_t n)
{
    unsigned i, need;
    void *p;
    if (!nar)
        init();
    if (n > BANKHI - BANKLO - HDR)
        goto none;
    need = blocksize(n);
    for (i = 0; i < nar; i++)
        if ((p = take(&ar[i], need)) != 0)
            return p;
    if (newbank() && (p = take(&ar[nar - 1], need)) != 0)
        return p;
none:
    errno = ENOMEM;
    return 0;
}

static struct arena *arena_of(void *p)
{
    unsigned i;
    unsigned char bk = HZ_BANK(p);
    for (i = 0; i < nar; i++)
        if (ar[i].bank == bk)
            return &ar[i];
    return 0;
}

static int empty(struct arena *a)
{
    return a->freel == a->lo && B(a, a->lo)->size == a->hi - a->lo;
}

void free(void *p)
{
    struct arena *a;
    fblk *b, *q;
    unsigned o, qo, prev;
    if (!p)
        return;
    a = arena_of(p);
    if (!a)
        return;                         /* (not malloc's: ignored) */
    o = HZ_OFF(p) - HDR;
    b = B(a, o);
    inuse -= b->size;
    prev = 0;
    for (qo = a->freel; qo && qo < o; qo = B(a, qo)->next)
        prev = qo;
    /* join with the next free block */
    if (qo && o + b->size == qo) {
        q = B(a, qo);
        b->size += q->size;
        b->next = q->next;
    } else
        b->next = qo;
    /* and with the one before */
    if (prev && prev + B(a, prev)->size == o) {
        q = B(a, prev);
        q->size += b->size;
        q->next = b->next;
    } else if (prev)
        B(a, prev)->next = o;
    else
        a->freel = o;
    if (a != &ar[0] && empty(a)) {
        /* an empty bank goes back while another one is empty too */
        unsigned i;
        for (i = 1; i < nar; i++)
            if (&ar[i] != a && empty(&ar[i])) {
                hz_bank_free(a->bank);
                *a = ar[--nar];
                break;
            }
    }
}

void *calloc(size_t n, size_t size)
{
    unsigned long t = (unsigned long)n * size;
    void *p;
    if (t > BANKHI - BANKLO - HDR) {
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
    struct arena *a;
    fblk *b, *q;
    unsigned need, have, o, qo, prev;
    void *np;
    if (!p)
        return malloc(n);
    if (!n) {
        free(p);
        return 0;
    }
    if (n > BANKHI - BANKLO - HDR) {
        errno = ENOMEM;
        return 0;
    }
    a = arena_of(p);
    o = HZ_OFF(p) - HDR;
    b = (fblk *)((char *)p - HDR);
    have = b->size;
    need = blocksize(n);
    if (need <= have)
        return p;                       /* (a shrink keeps the block) */
    if (a) {
        /* the free block right after it, when it is big enough */
        prev = 0;
        for (qo = a->freel; qo && qo < o; qo = B(a, qo)->next)
            prev = qo;
        if (qo && o + have == qo && have + B(a, qo)->size >= need) {
            q = B(a, qo);
            if (have + q->size - need >= HDR + 4) {
                unsigned ro = o + need;
                fblk *r = B(a, ro);
                r->next = q->next;
                r->size = have + q->size - need;
                if (prev)
                    B(a, prev)->next = ro;
                else
                    a->freel = ro;
                b->size = need;
            } else {
                if (prev)
                    B(a, prev)->next = q->next;
                else
                    a->freel = q->next;
                b->size = have + q->size;
            }
            used(b->size - have);
            return p;
        }
    }
    np = malloc(n);
    if (!np)
        return 0;
    memcpy(np, p, have - HDR);
    free(p);
    return np;
}

/* the heap's free bytes now (the free blocks of every arena, headers counted) */
unsigned long hz_heap_free(void)
{
    unsigned i, o;
    unsigned long n = 0;
    if (!nar)
        init();
    for (i = 0; i < nar; i++)
        for (o = ar[i].freel; o; o = B(&ar[i], o)->next)
            n += B(&ar[i], o)->size;
    return n;
}

/* the biggest malloc that would work now (a whole bank's when Horizon has one free) */
unsigned hz_heap_largest(void)
{
    unsigned i, o, n = 0;
    if (!nar)
        init();
    for (i = 0; i < nar; i++)
        for (o = ar[i].freel; o; o = B(&ar[i], o)->next)
            if (B(&ar[i], o)->size > n)
                n = B(&ar[i], o)->size;
    if (n < BANKHI - BANKLO && nar < MAXAR && hz_mem_info() > 0)
        n = BANKHI - BANKLO;
    return n > HDR ? n - HDR : 0;
}

/* the most bytes in use at once since the start (headers counted) */
unsigned long hz_heap_peak(void)
{
    return peak;
}

#else
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
#endif
