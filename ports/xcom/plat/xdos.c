/* SPDX-License-Identifier: GPL-3.0-or-later */
/* The DOS machine the engine was written for (compat/xdos.h): memory,
   the DOS memory chain, the BIOS data the engine reads, interrupts and
   ports answered by C, files. Shared by both back ends. */
#include "xcompat.h"
#include "plat.h"
#include "sb.h"

#if defined(__CC816__)
#include <horizon.h>
#include <unistd.h>
#endif

xd_ptr xd_mem;
unsigned _amblksiz = 8192;
unsigned _psp = 0x0080;
int __argc;
char **__argv;
char rd_dir;
unsigned char xd_dac[768];

#define LIN(seg, off)   (((unsigned long)(seg) << 4) + (unsigned)(off))

/* ---------------------------------------------------------------- the arena */

#if defined(__CC816__)
/* 17 banks: linear address a is bank xd_banks[a >> 16], offset a & FFFF. A
   DOS block never crosses one (xd_alloc), so pointer arithmetic on a far
   pointer (16 bits, within its bank) stays right for any object. */
unsigned char xd_banks[17];

void __far *xd_mkfp_raw(unsigned seg, unsigned off)
{
    /* linear seg * 16 + off in 16-bit steps: its low word, its bank */
    unsigned lo = (seg << 4) + off, b = seg >> 12;

    if (lo < off)
        b++;
    return (void __far *)(((unsigned long)xd_banks[b] << 16) | lo);
}

/* The engine's MK_FP: a pointer into the battle view's back buffer (bank D,
   plat.h XD_BB_SEG) is made after what the blitter was sent is drawn (the
   engine reads it: BENCH's checks) */
void __far *xd_mkfp(unsigned seg, unsigned off)
{
    if ((seg >> 12) == 0xD)
        plat_bb_sync();
    return xd_mkfp_raw(seg, off);
}

static unsigned long lin_of(const void __far *p)
{
    unsigned long v = (unsigned long)p;
    unsigned b = (unsigned)(v >> 16) & 0xFF, i;

    for (i = 0; i < 17; i++)
        if (xd_banks[i] == b)
            return ((unsigned long)i << 16) | (unsigned)v;
    return 0xFFFFFFFFUL;
}
#else
void *xd_mkfp(unsigned seg, unsigned off)
{
    return xd_mem + LIN(seg & 0xFFFF, off & 0xFFFF);
}

void *xd_mkfp_raw(unsigned seg, unsigned off)
{
    return xd_mkfp(seg, off);
}

static unsigned long lin_of(const void *p)
{
    const unsigned char *q = p;

    if (q < xd_mem || q >= xd_mem + XD_ARENA)
        return 0xFFFFFFFFUL;
    return (unsigned long)(q - xd_mem);
}
#endif

/* A pointer outside the arena (a global, a local) has no segment on this
   machine: the engine takes FP_SEG only of heap memory and video memory,
   so this is a port fault: say where. */
static void not_arena(const char *what)
{
    static int n;
    char b[80];

    if (n++ < 8) {
        sprintf(b, "xdos: %s of a pointer outside the DOS memory", what);
        plat_note(b);
    }
}

/* DOS pointers carry their segment; here a pointer is an address, and the
   segment is found again: a heap pointer has its block's segment (the engine
   makes them as MK_FP(seg, 0) + offset and takes FP_SEG / FP_OFF back,
   e.g. a table at an offset of the block's segment: geo.c), video memory
   A000 or B800, the BIOS data 0040, the ROM F000; anything else the
   normalised form (offset 0-15). */
static unsigned block_of(unsigned long a);

static unsigned long seg_of(unsigned long a)
{
    unsigned s = 0;

    if (a >= 0xA0000UL && a < 0xB0000UL)
        s = 0xA000;
    else if (a >= 0xB8000UL && a < 0xC0000UL)
        s = 0xB800;
    else if (a >= 0xF0000UL && a < 0x100000UL)
        s = 0xF000;
    else if (a >= 0x400UL && a < 0x500UL)
        s = 0x40;
    else if (a >= (unsigned long)XD_HEAP_SEG << 4 && a < (unsigned long)XD_HEAP_END << 4)
        s = block_of(a);
    if (!s || a - ((unsigned long)s << 4) > 0xFFFFUL)
        s = (unsigned)(a >> 4);
    return s;
}

#if defined(__CC816__)
unsigned xd_seg(const void __far *p)
#else
unsigned xd_seg(const void *p)
#endif
{
    unsigned long a = lin_of(p);

    if (a == 0xFFFFFFFFUL) {
        /* a global or a local: no segment here; not 0, so that the engine's
           "not NULL" tests (panel.c: FP_OFF(u)) hold */
        not_arena("FP_SEG");
        return p ? 0xFFFF : 0;
    }
    return (unsigned)seg_of(a);
}

#if defined(__CC816__)
unsigned xd_off(const void __far *p)
#else
unsigned xd_off(const void *p)
#endif
{
    unsigned long a = lin_of(p);

    if (a == 0xFFFFFFFFUL) {
#if defined(__CC816__)
        /* a global of the program's main bank: panel.c's FP_OFF(u) of a unit in g_units,
           only to test it for NULL (as xd_seg says): expected, not reported */
        if (((unsigned long)p >> 16) != ((unsigned long)(void __far *)&xd_mem >> 16))
#endif
        not_arena("FP_OFF");
        return p ? (unsigned)((unsigned long)p & 0xFFFF) | 1 : 0;
    }
    return (unsigned)(a - (seg_of(a) << 4));
}

/* ---------------------------------------------------------------- the DOS memory chain */
/* As DOS: a memory control block (MCB) in the paragraph before each block:
   'M' or 'Z' (the last), the owner (0 free), the size in paragraphs. */

#define MCB_B(s, o)     (*(unsigned char far *)MK_FP(s, o))
#define MCB_W(s, o)     (*(unsigned short far *)MK_FP(s, o))
#define FIRST_MCB       (XD_HEAP_SEG - 1)

static unsigned mcb_next(unsigned m)
{
    return m + 1 + MCB_W(m, 3);
}

static void mcb_set(unsigned m, char kind, unsigned owner, unsigned size)
{
    MCB_B(m, 0) = (unsigned char)kind;
    MCB_W(m, 1) = (unsigned short)owner;
    MCB_W(m, 3) = (unsigned short)size;
}

/* The block (its segment) that holds linear address a, 0 if none. */
static unsigned block_of(unsigned long a)
{
    static unsigned last;
    unsigned m = FIRST_MCB;
    unsigned long p = a >> 4;

    if (last && p >= last && p < (unsigned long)last + MCB_W(last - 1, 3) && MCB_W(last - 1, 1))
        return last;
    for (;;) {
        if (p > m && p <= (unsigned long)m + MCB_W(m, 3)) {
            if (!MCB_W(m, 1))
                return 0;
            last = m + 1;
            return last;
        }
        if (MCB_B(m, 0) == 'Z' || m > p)
            return 0;
        m = mcb_next(m);
    }
}

/* Joins free blocks that follow each other. */
static void mcb_merge(void)
{
    unsigned m = FIRST_MCB, n;

    for (;;) {
        if (MCB_B(m, 0) == 'Z')
            return;
        n = mcb_next(m);
        if (!MCB_W(m, 1) && !MCB_W(n, 1)) {
            MCB_B(m, 0) = MCB_B(n, 0);
            MCB_W(m, 3) = (unsigned short)(MCB_W(m, 3) + 1 + MCB_W(n, 3));
            continue;
        }
        m = n;
    }
}

/* Where a block of `paras` could start in the free block whose MCB is m
   without crossing a 64 KB line (a bank on the Atari816), 0 if nowhere. */
static unsigned fit_in(unsigned m, unsigned paras)
{
    unsigned start = m + 1, end = m + 1 + MCB_W(m, 3);
    unsigned long s = start;

    if ((s & 0xFFF) + paras > 0x1000) {
        s = (s + 0xFFF) & ~0xFFFUL;
        if (s - start < 1)              /* room for the gap's own MCB */
            s += 0x1000;
    }
    if (s + paras > end)
        return 0;
    return (unsigned)s;
}

/* The largest block that could be had now. */
static unsigned mcb_largest(void)
{
    unsigned m = FIRST_MCB, best = 0, size, s;

    for (;;) {
        if (!MCB_W(m, 1)) {
            size = MCB_W(m, 3);
            s = m + 1;
            (void)s;    /* DOS's answer: the whole free block (a block of more
                           than 64 KB is then refused: xd_alloc_big logs it) */
            if (size > best)
                best = size;
        }
        if (MCB_B(m, 0) == 'Z')
            return best;
        m = mcb_next(m);
    }
}

static unsigned mcb_alloc(unsigned paras, unsigned owner)
{
    unsigned m = FIRST_MCB, s, gap, rest;
    char kind;

    if (!paras)
        return 0;
    if (paras > 0x1000) {
        char b[64];
        if (paras >= 0x9000)            /* "how much is there" / "all of it" */
            return 0;
        sprintf(b, "xdos: a block of %u paragraphs (over 64 KB) refused", paras);
        plat_note(b);
        return 0;
    }
    for (;;) {
        if (!MCB_W(m, 1) && (s = fit_in(m, paras)) != 0) {
            kind = (char)MCB_B(m, 0);
            rest = m + 1 + MCB_W(m, 3) - (s + paras);
            gap = s - 1 - (m + 1);
            if (s - 1 != m) {           /* a free gap before it */
                mcb_set(m, 'M', 0, gap);
                m = s - 1;
            }
            if (rest) {
                mcb_set(m, 'M', owner, paras);
                mcb_set(s + paras, kind, 0, rest - 1);
            } else
                mcb_set(m, kind, owner, paras);
            return s;
        }
        if (MCB_B(m, 0) == 'Z')
            return 0;
        m = mcb_next(m);
    }
}

static int mcb_free(unsigned seg)
{
    unsigned m = FIRST_MCB;

    for (;;) {
        if (m + 1 == seg && MCB_W(m, 1)) {
            plat_mem_changed(MK_FP(seg, 0), (unsigned long)MCB_W(m, 3) << 4);
            MCB_W(m, 1) = 0;
            mcb_merge();
            return 0;
        }
        if (MCB_B(m, 0) == 'Z')
            return 9;               /* invalid block */
        m = mcb_next(m);
    }
}

/* Grows or shrinks a block in place; 0 ok, else 8 with *max the most. */
static int mcb_resize(unsigned seg, unsigned paras, unsigned *max)
{
    unsigned m = seg - 1, n, have, can;

    if (MCB_B(m, 0) != 'Z') {
        n = mcb_next(m);
        if (!MCB_W(n, 1))
            mcb_merge();
    }
    have = MCB_W(m, 3);
    can = have;
    if (MCB_B(m, 0) != 'Z' && !MCB_W(mcb_next(m), 1))
        can = have + 1 + MCB_W(mcb_next(m), 3);
    if ((seg & 0xFFF) + (unsigned long)paras > 0x1000 && paras > have)
        can = 0x1000 - (seg & 0xFFF);
    if (paras > can) {
        if (max)
            *max = can;
        return 8;
    }
    if (paras == have)
        return 0;
    if (paras < have) {
        char kind = (char)MCB_B(m, 0);
        plat_mem_changed(MK_FP(seg + paras, 0), (unsigned long)(have - paras) << 4);
        MCB_B(m, 0) = 'M';
        MCB_W(m, 3) = (unsigned short)paras;
        mcb_set(seg + paras, kind, 0, have - paras - 1);
        mcb_merge();
        return 0;
    }
    /* take from the free block after it */
    n = mcb_next(m);
    {
        char kind = (char)MCB_B(n, 0);
        unsigned left = can - paras;
        if (left) {
            MCB_W(m, 3) = (unsigned short)paras;
            mcb_set(seg + paras, kind, 0, left - 1);
        } else {
            MCB_B(m, 0) = (unsigned char)kind;
            MCB_W(m, 3) = (unsigned short)can;
        }
    }
    return 0;
}

unsigned _dos_allocmem(unsigned paras, unsigned *seg)
{
    unsigned s = mcb_alloc(paras, _psp);

    if (!s) {
        static int said;
        /* DOS's answer (the engine plans by it: asking for FFFFh is how it
           measures); a real shortage is said on the console a few times */
        if (paras < 0x9000u && said++ < 4) {
            char b[80];
            sprintf(b, "xdos: no DOS block of %u paragraphs (the largest %u)", paras,
                    mcb_largest());
            plat_note(b);
        }
        *seg = mcb_largest();
        return 8;
    }
    *seg = s;
    return 0;
}

unsigned _dos_freemem(unsigned seg)
{
    return (unsigned)mcb_free(seg);
}

unsigned _dos_setblock(unsigned paras, unsigned seg, unsigned *max)
{
    return (unsigned)mcb_resize(seg, paras, max);
}

#if defined(XD_HEAP_IN_ARENA)
/* The engine's malloc: one DOS block each (offset 0), its size kept by the
   MCB. Watcom's far heap packs small blocks into bigger DOS blocks; here
   each costs a paragraph more: the free memory the engine sees is
   smaller by that (it plans by it: picplan.c), but the same on every
   machine. */
void *xd_malloc(size_t n)
{
    unsigned s = mcb_alloc((unsigned)(((unsigned long)n + 15) >> 4) + (n == 0), _psp);

    if (!s) {
        static int said;
        if (said++ < 4) {
            char b[80];
            sprintf(b, "xdos: malloc(%u): the DOS memory is full (the largest block %u "
                    "paragraphs)", (unsigned)n, mcb_largest());
            plat_note(b);
        }
    }

    return s ? (void *)MK_FP(s, 0) : NULL;
}

void *xd_calloc(size_t n, size_t k)
{
    unsigned long t = (unsigned long)n * k;
    void *p;

    if (t > 0xFFF0UL)
        return NULL;
    p = xd_malloc((size_t)t);
    if (p)
        memset(p, 0, (size_t)t);
    return p;
}

void xd_free(void *p)
{
    if (p)
        mcb_free(FP_SEG(p));
}

void *xd_realloc(void *p, size_t n)
{
    unsigned seg, paras = (unsigned)(((unsigned long)n + 15) >> 4), old;
    void *q;

    if (!p)
        return xd_malloc(n);
    seg = FP_SEG(p);
    if (!mcb_resize(seg, paras ? paras : 1, NULL))
        return p;
    old = MCB_W(seg - 1, 3);
    q = xd_malloc(n);
    if (!q)
        return NULL;
    memcpy(q, p, (size_t)(old < paras ? old : paras) << 4);
    xd_free(p);
    return q;
}
#endif

/* ---------------------------------------------------------------- start */

static void mouse_vector(void)
{
}
static void files_report(void);
static xd_isr __far vectors[256];      /* (__far: out of the full main bank) */

/* The 8 x 8 font the BIOS keeps at F000:FA6E (hud.c reads it there): a
   public-domain 8x8 font (plat/font8x8.h). */
#include "font8x8.h"

void xd_init(int argc, char **argv)
{
    unsigned i;

    __argc = argc;
    __argv = argv;
    for (i = 0; i < 0x800; i++)
        *(unsigned char far *)MK_FP(0, i) = 0;
    /* the PSP's MCB, the PSP (its word 2: the top of memory), the chain */
    mcb_set(_psp - 1, 'M', _psp, FIRST_MCB - _psp);
    MCB_W(_psp, 2) = (unsigned short)XD_HEAP_END;
    mcb_set(FIRST_MCB, 'Z', 0, XD_HEAP_END - XD_HEAP_SEG);
    /* the BIOS: equipment word (colour card), the clock, the font */
    MCB_W(0x40, 0x10) = 0x0020;
    for (i = 0; i < 128 * 8; i++)
        *(unsigned char far *)MK_FP(0xF000, 0xFA6E + i) = font8x8[i];
    /* a mouse driver: INT 33h points at something that is not an IRET */
    vectors[0x33] = mouse_vector;
    atexit(files_report);
}

/* ---------------------------------------------------------------- test pictures */

int xd_mode = 3;
unsigned char xd_dac_dirty = 1;
int g_plat_shots;
unsigned g_plat_idle = 30;

/* A Fletcher sum of the picture: A000's 32,000 words, then the DAC's 384. */
unsigned long xd_screen_sum(void)
{
    const unsigned short far *p = (const unsigned short far *)MK_FP(0xA000, 0);
    const unsigned short *d = (const unsigned short *)xd_dac;
    unsigned short a = 0, b = 0;
    unsigned i;

    for (i = 0; i < 32000u; i++) {
        a = (unsigned short)(a + p[i]);
        b = (unsigned short)(b + a);
    }
    for (i = 0; i < 384u; i++) {
        a = (unsigned short)(a + d[i]);
        b = (unsigned short)(b + a);
    }
    return (unsigned long)b << 16 | a;
}

static unsigned long shot_try, shot_sum;
static unsigned shot_n;

/* A picture if the screen changed since the last one; looked at no more
   often than every gap_ms of virtual time (0: now). */
void xd_shot_point(unsigned gap_ms, const char *why)
{
    unsigned long now, sum;

    if (!g_plat_shots || xd_mode != 0x13)
        return;
    now = plat_now();
    if (gap_ms && shot_try && now - shot_try < (unsigned long)gap_ms * 1193UL)
        return;
    shot_try = now ? now : 1;
    sum = xd_screen_sum();
    if (shot_n && sum == shot_sum)
        return;
    shot_sum = sum;
    plat_shot(shot_n++, now / 1193UL, sum, why);
}

/* ---------------------------------------------------------------- time */

/* The BIOS clock at 0040:006C follows the model's clock (18.2065 Hz). */
static void bios_clock(unsigned long c)
{
    /* the PIT counts (32 bits) wrap after an hour of play: the BIOS clock goes on
       (its high word counts the wraps) instead of falling back to 0, which would end
       every wait at once or make one wait an hour */
    static unsigned long last_c, wraps;

    if (c < last_c)
        wraps++;
    last_c = c;
    *(unsigned long far *)MK_FP(0x40, 0x6C) = wraps << 16 | c >> 16;
}

void timer_run_hook_at(unsigned long now);

/* One reading of the clock serves the BIOS clock and the timer hook. */
void xd_poll(void)
{
    unsigned long now;

    plat_poll();
    xd_shot_point(500, "poll");
    now = plat_counts();
    bios_clock(now);
    timer_run_hook_at(now);
}

void delay(unsigned ms)
{
    unsigned long t0 = plat_counts(), n = (unsigned long)ms * 1193UL;

    (void)t0;
    if (g_plat_virtual)
        plat_wait_counts(n);
    else
        plat_sleep_counts(n);
}

void sound(unsigned hz)
{
    (void)hz;
}

void nosound(void)
{
}

/* ---------------------------------------------------------------- the keyboard */

static unsigned key_held;
static unsigned long idle_since;
extern FILE *g_script;                  /* the engine's KEYS script (input.c) */

/* The platform's next key. In a test run (the virtual clock) the engine
   asking for a key is a point for a picture, and a run whose script is done
   ends after g_plat_idle seconds of nothing. */
static unsigned next_key(void)
{
    if (g_plat_virtual) {
        unsigned long now = plat_now();
        xd_shot_point(200, "waiting for input");
        if (g_script || !idle_since)
            idle_since = now ? now : 1;
        else if (now - idle_since > g_plat_idle * 1193182UL) {
            xd_shot_point(0, "end");
            plat_end();
        }
    }
    return plat_key();
}

unsigned _bios_keybrd(unsigned cmd)
{
    unsigned k;

    xd_poll();
    if (cmd == _KEYBRD_READY || cmd == 0x11) {
        if (!key_held)
            key_held = next_key();
        return key_held;
    }
    if (cmd == _KEYBRD_SHIFTSTATUS || cmd == 0x12)
        return 0;
    while (!key_held) {
        key_held = next_key();
        if (!key_held) {
            if (g_plat_virtual)
                plat_wait_counts(1193UL * 10);
            xd_poll();
        }
    }
    k = key_held;
    key_held = 0;
    return k;
}

int kbhit(void)
{
    return _bios_keybrd(_KEYBRD_READY) != 0;
}

int getch(void)
{
    return _bios_keybrd(_KEYBRD_READ) & 0xFF;
}

/* ---------------------------------------------------------------- interrupts */

xd_isr _dos_getvect(unsigned n)
{
    return vectors[n & 255];
}

void _dos_setvect(unsigned n, xd_isr f)
{
    vectors[n & 255] = f;
}

void _chain_intr(xd_isr f)
{
    (void)f;
}

void segread(struct SREGS *s)
{
    s->es = s->ds = s->ss = 0x0800;     /* DGROUP: anything in the arena */
    s->cs = 0x0100;
}

/* INT 10h: a VGA card (mode 13h). */
static void int10(union REGS *r)
{
    switch (r->h.ah) {
    case 0x00:
        xd_mode = r->h.al & 0x7F;
        plat_setmode(xd_mode);
        break;
    case 0x0F:
        r->h.al = 0x13;
        r->h.ah = 40;
        r->h.bh = 0;
        break;
    case 0x10:                          /* palette registers: the DAC only */
        break;
    case 0x11:                          /* font: the 8 x 8 one */
        break;
    case 0x12:                          /* EGA information: 256 KB, colour */
        if (r->h.bl == 0x10) {
            r->h.bh = 0;
            r->h.bl = 3;
            r->x.cx = 9;
        }
        break;
    case 0x1A:                          /* display combination: VGA colour */
        r->h.al = 0x1A;
        r->h.bl = 8;
        r->h.bh = 0;
        break;
    }
}

/* INT 21h: memory, version; file calls on handles go through _dos_*. */
static void int21(union REGS *r, struct SREGS *s)
{
    unsigned seg;

    r->x.cflag = 0;
    switch (r->h.ah) {
    case 0x30:                          /* DOS 5.0 */
        r->h.al = 5;
        r->h.ah = 0;
        break;
    case 0x48:
        if (_dos_allocmem(r->x.bx, &seg)) {
            r->x.cflag = 1;
            r->x.ax = 8;
            r->x.bx = (unsigned short)seg;
        } else
            r->x.ax = (unsigned short)seg;
        break;
    case 0x49:
        if (_dos_freemem(s ? s->es : 0)) {
            r->x.cflag = 1;
            r->x.ax = 9;
        }
        break;
    case 0x4A: {
        unsigned max = 0;
        if (_dos_setblock(r->x.bx, s ? s->es : 0, &max)) {
            r->x.cflag = 1;
            r->x.ax = 8;
            r->x.bx = (unsigned short)max;
        }
        break;
    }
    case 0x52:                          /* list of lists: the first MCB at ES:BX - 2 */
        if (s)
            s->es = 0x0060;
        r->x.bx = 0x0010;
        *(unsigned short far *)MK_FP(0x0060, 0x000E) = (unsigned short)(_psp - 1);
        break;
    case 0x58:                          /* strategy, UMB link: no UMBs */
        if (r->h.al == 0 || r->h.al == 2)
            r->x.ax = 0;
        break;
    case 0x42: {                        /* seek on a handle (cut.c's end slides): CX:DX from
                                           AL's origin, the new position in DX:AX */
        long pos = lseek(r->x.bx, (long)((unsigned long)r->x.cx << 16 | r->x.dx),
                         r->h.al == 1 ? SEEK_CUR : r->h.al == 2 ? SEEK_END : SEEK_SET);
        if (pos < 0) {
            r->x.cflag = 1;
            r->x.ax = 25;               /* seek error */
        } else {
            r->x.ax = (unsigned short)pos;
            r->x.dx = (unsigned short)((unsigned long)pos >> 16);
        }
        break;
    }
    default:
        r->x.cflag = 1;
        r->x.ax = 1;                    /* invalid function */
        break;
    }
}

/* INT 33h: the mouse driver. Positions as a driver gives them in mode
   13h: x in 0-639 (the engine asks for that range), y 0-199. */

static void int33(union REGS *r)
{
    int x, y, b;

    /* the platform's events once per mouse_poll (its function 3 comes
       first; 5 and 6 answer from the same state) */
    if (r->x.ax == 3)
        xd_poll();
    switch (r->x.ax) {
    case 0x00:
    case 0x21:
        r->x.ax = 0xFFFF;
        r->x.bx = 2;
        break;
    case 0x03:
        plat_mouse(&x, &y, &b);
        r->x.bx = (unsigned short)b;
        r->x.cx = (unsigned short)(x * 2);
        r->x.dx = (unsigned short)y;
        break;
    case 0x04:
        plat_mouse_set(r->x.cx / 2, r->x.dx);
        idle_since = 0;                 /* (a script's CLICK or MOVE) */
        break;
    case 0x05: {                        /* presses since the last call, where */
        int n;
        plat_mouse(&x, &y, &b);
        r->x.ax = (unsigned short)b;
        n = plat_mouse_press(r->x.bx & 1, &x, &y);
        r->x.bx = (unsigned short)n;
        r->x.cx = (unsigned short)(x * 2);
        r->x.dx = (unsigned short)y;
        break;
    }
    case 0x06:
        plat_mouse(&x, &y, &b);
        r->x.ax = (unsigned short)b;
        r->x.bx = 0;
        r->x.cx = (unsigned short)(x * 2);
        r->x.dx = (unsigned short)y;
        break;
    case 0x24:
        r->x.bx = 0x0800;
        r->x.cx = 0x0400;
        break;
    }
}

int int86x(int n, union REGS *in, union REGS *out, struct SREGS *s)
{
    if (out != in)
        *out = *in;
    out->x.cflag = 0;
    switch (n) {
    case 0x10: int10(out); break;
    case 0x21: int21(out, s); break;
    case 0x33: int33(out); break;
    case 0x16: {                        /* the keyboard */
        unsigned k = _bios_keybrd(out->h.ah & 0x0F);
        out->x.ax = (unsigned short)k;
        break;
    }
    case 0x2F:                          /* no XMS, no multiplex services */
        if (out->x.ax == 0x4300)
            out->h.al = 0;
        break;
    case 0x67:                          /* no EMS */
        out->h.ah = 0x80;
        break;
    default:
        break;
    }
    return out->x.ax;
}

int int86(int n, union REGS *in, union REGS *out)
{
    return int86x(n, in, out, NULL);
}

int intdos(union REGS *in, union REGS *out)
{
    return int86x(0x21, in, out, NULL);
}

int intdosx(union REGS *in, union REGS *out, struct SREGS *s)
{
    return int86x(0x21, in, out, s);
}

/* ---------------------------------------------------------------- ports */

static unsigned dac_w, dac_r, opl_reg;
static unsigned char vsync_bit;
/* the OPL2's status (an AdLib: music.c's opl_detect): register 4's bit 7
   clears the timer flags, a timer started unmasked has overflowed by the
   next read (the detection waits 80 us for it) */
static unsigned char opl_stat;

unsigned outp(unsigned port, unsigned v)
{
    v &= 0xFF;
    switch (port) {
    case 0x3C8: dac_w = v * 3; break;     /* (v < 256: below 768) */
    case 0x3C7: dac_r = v * 3; break;
    case 0x3C9:
        xd_dac[dac_w] = (unsigned char)(v & 63);
        if (++dac_w == 768)
            dac_w = 0;
        xd_dac_dirty = 1;
        break;
    case 0x388: opl_reg = v; break;
    case 0x389:
        if (opl_reg == 4)
            opl_stat = v & 0x80 ? 0 : (v & 1) && !(v & 0x40) ? 0xC0 : opl_stat;
        plat_opl((int)opl_reg, (int)v);
        break;
    default:
        sb_outp(port, v);               /* the Sound Blaster, the DMA (plat/sb.c) */
        break;
    }
    return v;
}

unsigned outpw(unsigned port, unsigned v)
{
    outp(port, v & 0xFF);
    outp(port + 1, v >> 8);
    return v;
}

unsigned inp(unsigned port)
{
    unsigned v;

    switch (port) {
    case 0x3C9:
        v = xd_dac[dac_r];
        if (++dac_r == 768)
            dac_r = 0;
        return v;
    case 0x3DA:                         /* the vertical retrace comes and goes */
        vsync_bit ^= 8;
        return vsync_bit;
    case 0x388:                         /* OPL2 status: the timers' flags as an OPL2 */
        return opl_stat;
    default:
        v = (unsigned)sb_inp(port);     /* the Sound Blaster (plat/sb.c) */
        return v == 0xFFFFu ? 0xFF : v; /* nothing there */
    }
}

unsigned inpw(unsigned port)
{
    return inp(port) | inp(port + 1) << 8;
}

/* ---------------------------------------------------------------- files */

/* A DOS name for the platform: '\\' to '/', the case found on the disk
   (host; FAT ignores case anyway). Read-only opens try the mode folder
   first ("VGA/NAME"), as rdcount.asm's INT 21h hook does. */
static char path_buf[200];

#if !defined(__CC816__)
#include <dirent.h>
/* Finds `name` in folder `dir` whatever its case. */
static int find_case(const char *dir, const char *name, char *out)
{
    DIR *d = opendir(*dir ? dir : ".");
    struct dirent *e;
    int ok = 0;

    if (!d)
        return 0;
    while ((e = readdir(d)) != NULL)
        if (!strcasecmp(e->d_name, name)) {
            strcpy(out, e->d_name);
            ok = 1;
            break;
        }
    closedir(d);
    return ok;
}
#endif

static const char *dos_path(const char *name, int folder)
{
    char tmp[160], *p, *last;

    if (folder && rd_dir && !strchr(name, '\\') && !strchr(name, '/'))
        sprintf(tmp, "%cGA/%s", rd_dir, name);
    else
        strncpy(tmp, name, sizeof tmp - 1), tmp[sizeof tmp - 1] = 0;
    for (p = tmp; *p; p++)
        if (*p == '\\')
            *p = '/';
#if !defined(__CC816__)
    {
        /* each part in the case the disk has */
        char built[200], part[64], found[256];
        const char *q = tmp;
        strcpy(built, g_plat_dir);
        while (*q) {
            const char *e = strchr(q, '/');
            size_t n = e ? (size_t)(e - q) : strlen(q);
            char dir[200];
            memcpy(part, q, n);
            part[n] = 0;
            strcpy(dir, built);
            if (*dir && dir[strlen(dir) - 1] == '/')
                dir[strlen(dir) - 1] = 0;
            if (find_case(dir, part, found))
                strcat(built, found);
            else
                strcat(built, part);
            if (e) {
                strcat(built, "/");
                q = e + 1;
            } else
                break;
        }
        strcpy(path_buf, built);
    }
    (void)last;
#else
    (void)last;
    strcpy(path_buf, g_plat_dir);
    strcat(path_buf, tmp);
#endif
    return path_buf;
}

/* ---------------------------------------------------------------- open files
   Horizon has 4 file handles for the whole system. The model gives the engine
   the same 4 on both builds (the host refuses a fifth as the Atari816 would, so
   both behave alike), counts them and reports at the end the most that were
   open at once and which: "xcom: files: at most N open (A B C)", and every
   refusal: "xcom: files: NAME refused: 4 files open (A B C D)" (tests/check.sh
   fails on one). */
#define XD_MAX_FILES 4
int xd_files, xd_files_peak;
unsigned xd_files_refused;
static struct { const void *f; int fd; char name[16]; } open_tab[XD_MAX_FILES];
static char peak_names[XD_MAX_FILES * 16 + 4];

static void open_names(char *out)
{
    int i;

    *out = 0;
    for (i = 0; i < XD_MAX_FILES; i++)
        if (open_tab[i].name[0]) {
            if (*out)
                strcat(out, " ");
            strcat(out, open_tab[i].name);
        }
}

/* the last part of the name, at most 15 characters */
static void short_name(char *d, const char *name)
{
    const char *p = name, *q;

    for (q = name; *q; q++)
        if (*q == '/' || *q == '\\')
            p = q + 1;
    strncpy(d, p, 15);
    d[15] = 0;
}

static int file_room(const char *name)
{
    char all[XD_MAX_FILES * 16 + 4], n[16];

    if (xd_files < XD_MAX_FILES)
        return 1;
    xd_files_refused++;
    open_names(all);
    short_name(n, name);
    if (xd_files_refused <= 8) {
        char line[160];
        sprintf(line, "xcom: files: %s refused: %d files open (%s)", n, xd_files, all);
        plat_note(line);
    }
    return 0;
}

static void file_opened(const void *f, int fd, const char *name)
{
    int i;

    for (i = 0; i < XD_MAX_FILES; i++)
        if (!open_tab[i].name[0]) {
            open_tab[i].f = f;
            open_tab[i].fd = fd;
            short_name(open_tab[i].name, name);
            break;
        }
    if (++xd_files > xd_files_peak) {
        xd_files_peak = xd_files;
        open_names(peak_names);
    }
}

static void file_closed(const void *f, int fd)
{
    int i;

    for (i = 0; i < XD_MAX_FILES; i++)
        if (open_tab[i].name[0] && (f ? open_tab[i].f == f : open_tab[i].fd == fd)) {
            open_tab[i].name[0] = 0;
            open_tab[i].f = NULL;
            xd_files--;
            return;
        }
}

/* the open file's short name (for /M's table), "?" if not known */
static const char *name_of(const void *f, int fd)
{
    int i;

    for (i = 0; i < XD_MAX_FILES; i++)
        if (open_tab[i].name[0] && (f ? open_tab[i].f == f : open_tab[i].fd == fd))
            return open_tab[i].name;
    return "?";
}

static void files_report(void)
{
    char line[160];

    sprintf(line, "xcom: files: at most %d open (%s), %u refused", xd_files_peak,
            peak_names, xd_files_refused);
    plat_note(line);
}

/* ---------------------------------------------------------------- the packs in memory
   (Atari816) The board's card answers each request slowly whatever its size (an OPEN or
   a STAT about 24 ms, a READ 4.5 ms + its bytes: emu/README.md "The card's speed"), and
   the engine opens and reads its packs again at every screen (UIV.PAK's pictures, PALV.PAK
   at each palette, NAMES.PAK, WORLDV.PAK in small pieces): seconds of card calls on the
   board. So the packs (read-only opens of *.PAK, PACKS.VER) are read through a cache: a
   name table (each path looked up on the card once: there or not, its size), and the
   files' contents in blocks of 16 KB in far banks taken while memory is plentiful (at most
   XC_BANKS, never leaving fewer than XC_RESERVE free; xc_release gives one back to the
   battle's atlas), the least recently used block reused. An open, a seek, a read of what
   is in memory: no card call at all. A miss opens the file (kept open until the engine
   closes it, as before) and reads its whole block. The engine sees the same bytes, the same
   open files (counted as before: the 4 of Horizon), the same errors; the host reads the
   files as they are (the reference). /M counts the card's own calls ("card"). */
#if defined(__CC816__)
#define XC_BLOCK    16384u
#define XC_BANKS    24
#define XC_RESERVE  12                  /* banks left free for the battle's atlas, sound, ... */
#define XC_NAMES    64
#define XC_FILES    6
#define XC_FD0      200                 /* the engine's fd of cached file i: XC_FD0 + i */

static struct { char path[32]; long size; } __far xc_names[XC_NAMES];      /* size -1: none */
static int xc_nnames;
static unsigned char __far *xc_bank[XC_BANKS];
static int xc_nbanks;
static struct { int name; unsigned blk; unsigned long used; } __far xc_slot[XC_BANKS * 4];
static unsigned long xc_clock;
typedef struct {
    int name, h, ungot, last;           /* h: the card's handle once a block was missed */
    long pos;
    unsigned char open, err;
} XcFile;
static XcFile __far xc_files[XC_FILES];
static char __far xc_tag[XC_FILES];     /* (FILE *)&xc_tag[i] is cached file i's FILE */

static void xc_card(int slot, unsigned long t0, unsigned long bytes)
{
    PERF_IO(slot, NULL, bytes, t0);
}

static int xc_wants(const char *name)
{
    size_t n = strlen(name);

    return n > 4 && (!strcasecmp(name + n - 4, ".PAK") || !strcasecmp(name + n - 4, ".VER"));
}

/* the name's entry (looked up on the card the first time) */
static int xc_name(const char *path)
{
    hz_fileinfo st;
    int i;
    PERF_T0(pt0);

    for (i = 0; i < xc_nnames; i++)
        if (!strcmp(xc_names[i].path, path))
            return i;
    if (strlen(path) >= sizeof xc_names[0].path || xc_nnames == XC_NAMES)
        return -1;
    i = xc_nnames++;
    strcpy(xc_names[i].path, path);
    xc_names[i].size = hz_stat_path(path, &st) < 0 || (st.attr & HZ_ATTR_DIR) ? -1L : (long)st.size;
    xc_card(PF_CARD, pt0, 0);
    return i;
}

/* opens a pack: the cached file's index, -1 when not there (-2: not a pack, or no room
   in the tables: the caller opens it as before) */
static int xc_open(const char *name)
{
    int n = -1, i;

    if (!xc_wants(name))
        return -2;
    if (rd_dir) {
        n = xc_name(dos_path(name, 1));
        if (n >= 0 && xc_names[n].size < 0)
            n = -1;
    }
    if (n < 0) {
        n = xc_name(dos_path(name, 0));
        if (n < 0)
            return -2;
        if (xc_names[n].size < 0)
            return -1;
    }
    for (i = 0; i < XC_FILES; i++)
        if (!xc_files[i].open) {
            xc_files[i].open = 1;
            xc_files[i].name = n;
            xc_files[i].h = -1;
            xc_files[i].pos = 0;
            xc_files[i].ungot = -1;
            xc_files[i].err = 0;
            xc_files[i].last = -1;
            return i;
        }
    return -2;
}

static int xc_of_file(const FILE *f)
{
    const char __far *p = (const char __far *)f;

    return p >= xc_tag && p < xc_tag + XC_FILES ? (int)(p - xc_tag) : -1;
}

static int xc_of_fd(int fd)
{
    return fd >= XC_FD0 && fd < XC_FD0 + XC_FILES && xc_files[fd - XC_FD0].open ? fd - XC_FD0 : -1;
}

static unsigned char __far *xc_mem(int s)
{
    return xc_bank[s >> 2] + (unsigned)(s & 3) * XC_BLOCK;
}

int xc_nbanks_now(void)
{
    return xc_nbanks;
}

/* a free bank to the battle's atlas (horizon/hz_bb.c, when its own allocation failed):
   1 when one was given back */
int xc_release(void)
{
    int s;

    if (!xc_nbanks)
        return 0;
    xc_nbanks--;
    for (s = xc_nbanks * 4; s < xc_nbanks * 4 + 4; s++)
        xc_slot[s].used = 0;
    hz_far_free(xc_bank[xc_nbanks]);
    xc_bank[xc_nbanks] = NULL;
    for (s = 0; s < XC_FILES; s++)
        xc_files[s].last = -1;
    return 1;
}

/* block b of file i in memory: its slot, -1 on a card error */
static int xc_block(int i, unsigned b)
{
    XcFile __far *x = &xc_files[i];
    int s, best = -1;
    unsigned long when = 0xFFFFFFFFUL, off;
    unsigned len;
    hz_io io;

    if (x->last >= 0 && xc_slot[x->last].used && xc_slot[x->last].name == x->name
        && xc_slot[x->last].blk == b) {
        xc_slot[x->last].used = ++xc_clock;
        return x->last;
    }
    for (s = 0; s < xc_nbanks * 4; s++) {
        if (xc_slot[s].used && xc_slot[s].name == x->name && xc_slot[s].blk == b) {
            xc_slot[s].used = ++xc_clock;
            return x->last = s;
        }
        if (xc_slot[s].used < when) {
            when = xc_slot[s].used;
            best = s;
        }
    }
    if ((best < 0 || when) && xc_nbanks < XC_BANKS && hz_mem_info() > XC_RESERVE) {
        unsigned char __far *m = (unsigned char __far *)hz_far_alloc();
        if (m) {
            xc_bank[xc_nbanks] = m;
            best = xc_nbanks * 4;
            for (s = best; s < best + 4; s++)
                xc_slot[s].used = 0;
            xc_nbanks++;
        }
    }
    if (best < 0)
        return -2;                      /* (no memory at all: the caller reads the card) */
    xc_slot[best].used = 0;
    if (x->h < 0) {
        PERF_T0(pt0);
        x->h = hz_open(xc_names[x->name].path, HZ_O_READ);
        xc_card(PF_CARD, pt0, 0);
        if (x->h < 0)
            return -1;
    }
    off = (unsigned long)b * XC_BLOCK;
    len = xc_names[x->name].size - off > XC_BLOCK ? XC_BLOCK : (unsigned)(xc_names[x->name].size - off);
    {
        PERF_T0(pt0);
        if (hz_seek((unsigned)x->h, off) == -1 && hz_errno)
            return -1;
        io.handle = (unsigned char)x->h;
        HZ_U24(io.buf, xc_mem(best));
        io.len = len;
        if (hz_read(&io) != (int)len)
            return -1;
        xc_card(PF_CARD, pt0, len);
    }
    xc_slot[best].name = x->name;
    xc_slot[best].blk = b;
    xc_slot[best].used = ++xc_clock;
    return x->last = best;
}

/* n bytes from the file's place into p: the count read (short at the end; an error: the
   count so far, err set) */
static unsigned long xc_read(int i, void *p, unsigned long n)
{
    XcFile __far *x = &xc_files[i];
    unsigned char *q = (unsigned char *)p;
    unsigned long done = 0, size = xc_names[x->name].size;

    if (n && x->ungot >= 0) {
        *q++ = (unsigned char)x->ungot;
        x->ungot = -1;
        x->pos++;
        done++;
        n--;
    }
    while (n && x->pos < (long)size) {
        unsigned b = (unsigned)((unsigned long)x->pos / XC_BLOCK), o = (unsigned)((unsigned long)x->pos % XC_BLOCK);
        unsigned long k = XC_BLOCK - o;
        int s = xc_block(i, b);
        if (s == -2) {
            /* no memory for the cache: straight from the card, as before */
            unsigned want = n > 0x7FFFu ? 0x7FFFu : (unsigned)n;
            hz_io io;
            int got;
            if (x->h < 0 && (x->h = hz_open(xc_names[x->name].path, HZ_O_READ)) < 0)
                s = -1;
            else if (hz_seek((unsigned)x->h, (unsigned long)x->pos) == -1 && hz_errno)
                s = -1;
            else {
                io.handle = (unsigned char)x->h;
                HZ_U24(io.buf, q);
                io.len = want;
                got = hz_read(&io);
                if (got <= 0) {
                    if (got < 0)
                        x->err = 1;
                    break;
                }
                q += (unsigned)got;
                x->pos += got;
                done += (unsigned)got;
                n -= (unsigned)got;
                continue;
            }
        }
        if (s < 0) {
            x->err = 1;
            break;
        }
        if (k > n)
            k = n;
        if (k > size - (unsigned long)x->pos)
            k = size - (unsigned long)x->pos;
        memcpy(q, xc_mem(s) + o, (size_t)k);
        q += (unsigned)k;
        x->pos += (long)k;
        done += k;
        n -= k;
    }
    return done;
}

static long xc_seek(int i, long off, int how)
{
    XcFile __far *x = &xc_files[i];
    long p = how == SEEK_SET ? off : how == SEEK_CUR ? x->pos + off : xc_names[x->name].size + off;

    if (p < 0)
        return -1;
    x->pos = p;
    x->ungot = -1;
    return p;
}

static void xc_close(int i)
{
    XcFile __far *x = &xc_files[i];

    if (x->h >= 0) {
        PERF_T0(pt0);
        hz_close((unsigned)x->h);
        xc_card(PF_CARD, pt0, 0);
    }
    x->open = 0;
}
#endif

static FILE *save_f;                    /* a save being written (xd_fclose) */
static char save_path[160];

#undef fopen
FILE *xd_fopen(const char *name, const char *mode)
{
    FILE *f = NULL;
    PERF_T0(pt0);

    if (!file_room(name))
        return NULL;
#if defined(__CC816__)
    if (mode[0] == 'r' && !strchr(mode, '+')) {
        int i = xc_open(name);
        if (i == -1) {
            PERF_IO(PF_OPEN, name, 0, pt0);
            return NULL;
        }
        if (i >= 0) {
            f = (FILE *)(xc_tag + i);
            file_opened(f, -1, name);
            PERF_IO(PF_OPEN, name, 0, pt0);
            return f;
        }
    }
#endif
    if (mode[0] == 'r' && !strchr(mode, '+') && rd_dir)
        f = fopen(dos_path(name, 1), mode);
    if (!f)
        f = fopen(dos_path(name, 0), mode);
    if (f)
        file_opened(f, -1, name);
    PERF_IO(PF_OPEN, name, 0, pt0);
    if (f && mode[0] == 'w') {
        size_t n = strlen(name);
        if (n > 4 && !strcasecmp(name + n - 4, ".SAV")) {
            save_f = f;
            strncpy(save_path, dos_path(name, 0), sizeof save_path - 1);
            save_path[sizeof save_path - 1] = 0;
        }
    }
    return f;
}

#undef fclose
/* A save written short (a full card: the engine says "Could not save the game!") is
   removed: a cut save in its slot would load as garbage. The engine's own battle saves
   go through XCOMXT.TMP and a rename, and remove a failed one themselves. */
int xd_fclose(FILE *f)
{
    int bad = 0, r;
    PERF_T0(pt0);

#if defined(__CC816__)
    if (xc_of_file(f) >= 0) {
        file_closed(f, -1);
        xc_close(xc_of_file(f));
        PERF_ADD(PF_CLOSE, pt0);
        return 0;
    }
#endif
    if (f == save_f) {
        bad = ferror(f) != 0 || fflush(f) != 0;
        save_f = NULL;
    }
    file_closed(f, -1);
    r = fclose(f);
    if (save_path[0] && (bad || r)) {
        char line[200];
        remove(save_path);
        sprintf(line, "xcom: files: %s written short (the card is full?): removed", save_path);
        plat_note(line);
        r = -1;
    }
    save_path[0] = 0;
    PERF_ADD(PF_CLOSE, pt0);
    return r;
}

#undef close
int xd_close(int fd)
{
    int r;
    PERF_T0(pt0);

    file_closed(NULL, fd);
#if defined(__CC816__)
    if (xc_of_fd(fd) >= 0) {
        xc_close(xc_of_fd(fd));
        PERF_ADD(PF_CLOSE, pt0);
        return 0;
    }
#endif
    r = close(fd);
    PERF_ADD(PF_CLOSE, pt0);
    return r;
}

#if defined(__CC816__)
#undef lseek
#undef fseek
long xd_lseek(int fd, long off, int how)
{
    long r;
    PERF_T0(pt0);

    if (xc_of_fd(fd) >= 0)
        r = xc_seek(xc_of_fd(fd), off, how);
    else
        r = lseek(fd, off, how);
    PERF_ADD(PF_SEEK, pt0);
    return r;
}

int xd_fseek(FILE *f, long off, int how)
{
    int r;
    PERF_T0(pt0);

    if (xc_of_file(f) >= 0)
        r = xc_seek(xc_of_file(f), off, how) < 0 ? -1 : 0;
    else
        r = fseek(f, off, how);
    PERF_ADD(PF_SEEK, pt0);
    return r;
}

#undef ftell
#undef fgetc
#undef getc
#undef ungetc
#undef ferror
#undef feof
long xd_ftell(FILE *f)
{
    int i = xc_of_file(f);

    return i >= 0 ? xc_files[i].pos : ftell(f);
}

int xd_fgetc(FILE *f)
{
    int i = xc_of_file(f);
    unsigned char c;

    if (i < 0)
        return fgetc(f);
    return xc_read(i, &c, 1) == 1 ? c : EOF;
}

int xd_ungetc(int c, FILE *f)
{
    int i = xc_of_file(f);

    if (i < 0)
        return ungetc(c, f);
    if (c == EOF || xc_files[i].ungot >= 0 || !xc_files[i].pos)
        return EOF;
    xc_files[i].ungot = c & 0xFF;
    xc_files[i].pos--;
    return c & 0xFF;
}

int xd_ferror(FILE *f)
{
    int i = xc_of_file(f);

    return i >= 0 ? xc_files[i].err : ferror(f);
}

int xd_feof(FILE *f)
{
    int i = xc_of_file(f);

    return i >= 0 ? xc_files[i].pos >= xc_names[xc_files[i].name].size : feof(f);
}
#endif

/* reads into the engine's memory: the platform hears of them (plat_mem_changed) */
#undef fread
#undef read
unsigned long xd_bytes_read;

size_t xd_fread(void *p, size_t size, size_t n, FILE *f)
{
    PERF_T0(pt0);
    size_t k;
#if defined(__CC816__)
    int i = xc_of_file(f);
    if (i >= 0)
        k = size ? (size_t)(xc_read(i, p, (unsigned long)size * n) / size) : 0;
    else
#endif
    k = fread(p, size, n, f);

    PERF_IO(PF_READ, name_of(f, -1), (unsigned long)size * k, pt0);
    plat_mem_changed(p, (unsigned long)size * n);
    xd_bytes_read += (unsigned long)size * k;
    plat_progress();
    return k;
}

/* n bytes, or to the end of the file: read() moves at most 32,767 bytes a call
   (the SDK's read returns a short count above that), so in pieces until n, the end
   (0) or an error (-1: returned as 0xFFFFFFFF). DOS's read gave all of n at once. */
static unsigned long read_all(int fd, void *p, unsigned n)
{
    unsigned long total = 0;
    unsigned char *q = (unsigned char *)p;
    PERF_T0(pt0);

#if defined(__CC816__)
    if (xc_of_fd(fd) >= 0) {
        total = xc_read(xc_of_fd(fd), p, n);
        if (!total && xc_files[xc_of_fd(fd)].err)
            return 0xFFFFFFFFUL;
        n = 0;
    }
#endif
    while (n) {
        unsigned want = n > 0x7FFFu ? 0x7FFFu : n;
        int k = (int)read(fd, q, want);
        if (k < 0)
            return total ? total : 0xFFFFFFFFUL;
        if (k == 0)
            break;
        total += (unsigned)k;
        q += (unsigned)k;
        n -= (unsigned)k;
    }
    xd_bytes_read += total;
    PERF_IO(PF_READ, name_of(NULL, fd), total, pt0);
    plat_progress();
    return total;
}

static unsigned long write_all(int fd, const void *p, unsigned n)
{
    unsigned long total = 0;
    const unsigned char *q = (const unsigned char *)p;

    while (n) {
        unsigned want = n > 0x7FFFu ? 0x7FFFu : n;
        int k = (int)write(fd, q, want);
        if (k < 0)
            return 0xFFFFFFFFUL;
        if (k == 0)
            break;
        total += (unsigned)k;
        q += (unsigned)k;
        n -= (unsigned)k;
    }
    return total;
}

int xd_read(int fd, void *p, unsigned n)
{
    unsigned long k = read_all(fd, p, n);

    plat_mem_changed(p, n);
    return k == 0xFFFFFFFFUL ? -1 : (int)(unsigned)k;
}

#undef open
int xd_open(const char *name, int flags, ...)
{
    int fd = -1;
    PERF_T0(pt0);

    if (!file_room(name))
        return -1;
#if defined(__CC816__)
    if ((flags & 3) == O_RDONLY) {
        int i = xc_open(name);
        if (i >= 0) {
            fd = XC_FD0 + i;
            file_opened(NULL, fd, name);
        }
        if (i != -2) {
            PERF_IO(PF_OPEN, name, 0, pt0);
            return fd;
        }
    }
#endif
    if ((flags & 3) == O_RDONLY && rd_dir)
        fd = open(dos_path(name, 1), flags & ~O_BINARY);
    if (fd < 0)
#if defined(__CC816__)
        fd = open(dos_path(name, 0), flags & ~O_BINARY);
#else
        fd = open(dos_path(name, 0), flags & ~O_BINARY, 0644);
#endif
    if (fd >= 0)
        file_opened(NULL, fd, name);
    PERF_IO(PF_OPEN, name, 0, pt0);
    return fd;
}

#undef access
int xd_access(const char *name, int mode)
{
    FILE *f = xd_fopen(name, "rb");

    (void)mode;
    if (!f)
        return -1;
    xd_fclose(f);
    return 0;
}

#undef remove
int xd_remove(const char *name)
{
    return remove(dos_path(name, 0));
}

#undef rename
int xd_rename(const char *a, const char *b)
{
    char pa[200];

    strcpy(pa, dos_path(a, 0));
    return rename(pa, dos_path(b, 0));
}

#undef getenv
char *xd_getenv(const char *name)
{
    /* a Sound Blaster 2.0 (plat/sb.c); no XCV, XPIC, ... */
    static char blaster[] = "A220 I7 D1 T3";

    if (!strcmp(name, "BLASTER"))
        return blaster;
    return NULL;
}

char *strupr(char *s)
{
    char *p;

    for (p = s; *p; p++)
        *p = (char)toupper((unsigned char)*p);
    return s;
}

char *strlwr(char *s)
{
    char *p;

    for (p = s; *p; p++)
        *p = (char)tolower((unsigned char)*p);
    return s;
}

unsigned _dos_open(const char *path, unsigned mode, int *handle)
{
    int fd = xd_open(path, (int)(mode & 3));

    if (fd < 0)
        return 2;                       /* file not found */
    *handle = fd;
    return 0;
}

unsigned _dos_creat(const char *path, unsigned attr, int *handle)
{
    int fd = xd_open(path, O_WRONLY | O_CREAT | O_TRUNC);

    (void)attr;
    if (fd < 0)
        return 5;
    *handle = fd;
    return 0;
}

unsigned _dos_close(int handle)
{
    return xd_close(handle) ? 6 : 0;
}

#if defined(__CC816_FAR_DATA__)
/* the far data model: read and write take the far buffer as it is (the card reads
   straight into the arena's bank) */
/* (the C library's read and write move at most 32,767 bytes a call (ssize_t is
   int): DOS's up to 65,535 in pieces, as the end slides' 64,000-byte pictures) */
unsigned _dos_read(int handle, void *buf, unsigned n, unsigned *got)
{
    unsigned long k = read_all(handle, buf, n);     /* (in pieces: read_all) */

    plat_mem_changed(buf, n);
    if (k == 0xFFFFFFFFUL)
        return 5;
    *got = (unsigned)k;
    return 0;
}

unsigned _dos_write(int handle, const void *buf, unsigned n, unsigned *put)
{
    unsigned long k = write_all(handle, buf, n);

    if (k == 0xFFFFFFFFUL)
        return 5;
    *put = (unsigned)k;
    return 0;
}
#elif defined(__CC816__)
unsigned _dos_read(int handle, void __far *buf, unsigned n, unsigned *got)
{
    /* the SDK's read takes a near buffer: through one */
    static unsigned char tmp[512];
    unsigned char __far *p = buf;
    unsigned done = 0;
    int k;

    while (done < n) {
        unsigned want = n - done > sizeof tmp ? sizeof tmp : n - done;
        k = read(handle, tmp, want);
        if (k < 0)
            return 5;
        hz_far_copy(p + done, tmp, (unsigned)k);
        done += (unsigned)k;
        if ((unsigned)k < want)
            break;
    }
    *got = done;
    return 0;
}

unsigned _dos_write(int handle, const void __far *buf, unsigned n, unsigned *put)
{
    static unsigned char tmp[512];
    const unsigned char __far *p = buf;
    unsigned done = 0;
    int k;

    while (done < n) {
        unsigned want = n - done > sizeof tmp ? sizeof tmp : n - done;
        hz_far_copy(tmp, p + done, want);
        k = write(handle, tmp, want);
        if (k < 0)
            return 5;
        done += (unsigned)k;
        if ((unsigned)k < want)
            break;
    }
    *put = done;
    return 0;
}
#else
unsigned _dos_read(int handle, void *buf, unsigned n, unsigned *got)
{
    ssize_t k = read(handle, buf, n);

    plat_mem_changed(buf, n);
    if (k < 0)
        return 5;
    xd_bytes_read += (unsigned long)k;
    *got = (unsigned)k;
    return 0;
}

unsigned _dos_write(int handle, const void *buf, unsigned n, unsigned *put)
{
    ssize_t k = write(handle, buf, n);

    if (k < 0)
        return 5;
    *put = (unsigned)k;
    return 0;
}
#endif

/* _dos_findfirst: the engine looks for single names and patterns like
   "FA?V.PAK", "R??V.PAK" (startup.c find_packs). */
#if defined(__CC816__)
#include <dirent.h>
#endif
static int wild_match(const char *pat, const char *s)
{
    for (; *pat; pat++, s++) {
        if (*pat == '*')
            return 1;
        if (!*s)
            return 0;
        if (*pat != '?' && toupper((unsigned char)*pat) != toupper((unsigned char)*s))
            return 0;
    }
    return !*s;
}

struct find_state { DIR *d; char pat[64]; };

unsigned _dos_findnext(struct find_t *f)
{
    struct find_state *st = *(struct find_state **)f->reserved;
    struct dirent *e;

    if (!st)
        return 18;
    while ((e = readdir(st->d)) != NULL)
        if (wild_match(st->pat, e->d_name) && strlen(e->d_name) <= 12) {
            strcpy(f->name, e->d_name);
            strupr(f->name);
            f->attrib = _A_NORMAL;
            f->size = 0;
            return 0;
        }
    closedir(st->d);
    free(st);
    *(struct find_state **)f->reserved = NULL;
    return 18;                          /* no more files */
}
unsigned _dos_findfirst(const char *path, unsigned attr, struct find_t *f)
{
    char dir[200], *slash;
    const char *full;
    struct find_state *st;

    (void)attr;
    full = dos_path(path, 0);
    strcpy(dir, full);
    slash = strrchr(dir, '/');
    st = (struct find_state *)malloc(sizeof *st);
    memset(f, 0, sizeof *f);
    if (!st)
        return 8;                       /* not enough memory (DOS's answer) */
    if (slash) {
        strncpy(st->pat, slash + 1, sizeof st->pat - 1);
        st->pat[sizeof st->pat - 1] = 0;
        slash[1] = 0;
    } else {
        strncpy(st->pat, dir, sizeof st->pat - 1);
        st->pat[sizeof st->pat - 1] = 0;
        strcpy(dir, ".");
    }
    st->d = opendir(dir);
    if (!st->d) {
        free(st);
        return 3;
    }
    *(struct find_state **)f->reserved = st;
    return _dos_findnext(f);
}

unsigned _dos_findclose(struct find_t *f)
{
    (void)f;
    return 0;
}

/* ---------------------------------------------------------------- printf with 32-bit long */
#if !defined(__CC816__)
#undef printf
#undef sprintf
#undef fprintf
#undef vsprintf
#undef vfprintf
#undef snprintf
#undef vsnprintf

/* "%ld" -> "%d" etc.: `long` is int here (xcompat.h). "%lld" is left. And "%d" ->
   "%hd", "%u" -> "%hu", "%x" -> "%hx" ...: an int argument is DOS's 16-bit one (the
   host's int is short: tools/host16.py; an expression promoted to 32 bits prints as
   the 16-bit int it is on DOS). */
static const char *fix_fmt(const char *fmt, char *out, size_t size)
{
    size_t n = 0;
    const char *p = fmt;

    if (!strstr(fmt, "%"))
        return fmt;
    while (*p && n + 2 < size) {
        out[n++] = *p;
        if (*p++ != '%')
            continue;
        if (*p == '%') {
            out[n++] = *p++;
            continue;
        }
        while (*p && strchr("-+ #0123456789.*", *p) && n + 2 < size)
            out[n++] = *p++;
        if (*p == 'l' && p[1] != 'l')
            p++;
        else if (*p && strchr("diouxX", *p))
            out[n++] = 'h';
    }
    out[n] = 0;
    return out;
}

int xd_vsnprintf(char *buf, size_t size, const char *fmt, va_list ap)
{
    char f[512];
    return vsnprintf(buf, size, fix_fmt(fmt, f, sizeof f), ap);
}

int xd_vsprintf(char *buf, const char *fmt, va_list ap)
{
    char f[512];
    return vsprintf(buf, fix_fmt(fmt, f, sizeof f), ap);
}

int xd_vfprintf(FILE *fp, const char *fmt, va_list ap)
{
    char f[512];
    return vfprintf(fp, fix_fmt(fmt, f, sizeof f), ap);
}

int xd_sprintf(char *buf, const char *fmt, ...)
{
    va_list ap;
    int n;
    va_start(ap, fmt);
    n = xd_vsprintf(buf, fmt, ap);
    va_end(ap);
    return n;
}

int xd_snprintf(char *buf, size_t size, const char *fmt, ...)
{
    va_list ap;
    int n;
    va_start(ap, fmt);
    n = xd_vsnprintf(buf, size, fmt, ap);
    va_end(ap);
    return n;
}

int xd_fprintf(FILE *fp, const char *fmt, ...)
{
    va_list ap;
    int n;
    va_start(ap, fmt);
    n = xd_vfprintf(fp, fmt, ap);
    va_end(ap);
    return n;
}

int xd_printf(const char *fmt, ...)
{
    va_list ap;
    int n;
    va_start(ap, fmt);
    n = xd_vfprintf(stdout, fmt, ap);
    va_end(ap);
    return n;
}
#endif

/* INT 10h AX 1130h (the font pointer) answered with the font at F000:FA6E. */
void intr(int n, union REGPACK *r)
{
    if (n == 0x10 && r->w.ax == 0x1130) {
        r->w.es = 0xF000;
        r->w.bp = 0xFA6E;
        r->w.cx = 8;
        return;
    }
    {
        union REGS q;
        q.x.ax = r->w.ax; q.x.bx = r->w.bx; q.x.cx = r->w.cx; q.x.dx = r->w.dx;
        q.x.si = r->w.si; q.x.di = r->w.di;
        int86(n, &q, &q);
        r->w.ax = q.x.ax; r->w.bx = q.x.bx; r->w.cx = q.x.cx; r->w.dx = q.x.dx;
    }
}
