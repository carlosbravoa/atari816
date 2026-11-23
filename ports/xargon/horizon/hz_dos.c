/* hz_dos.c - the DOS and Turbo C library functions Xargon's files call (compat/*.h,
 * xcompat.h): the I/O ports they touch (emulated: the VGA's DAC, status and CRTC, the
 * game port), delay, the text screen, Turbo C's itoa family and its rand. */
#include <stdio.h>
#include <string.h>
#include <horizon.h>
#include <hgame.h>
#include "dos.h"
#include "conio.h"
#include "io.h"
#include "alloc.h"
#include "hz_plat.h"

/* ---------------------------------------------------------------- the I/O ports */

unsigned char inportb(unsigned port)
{
    switch (port) {
    case 0x3DA:                         /* input status 1: bit 3 the vertical retrace */
        return hzf_retrace();
    case 0x201:                         /* the game port */
        return hzf_gameport();
    }
    return 0xFF;
}

unsigned inport(unsigned port)
{
    return inportb(port);
}

void outportb(unsigned port, unsigned char value)
{
    switch (port) {
    case 0x3C8:                         /* the DAC's write index */
        hzv_dac_index(value);
        break;
    case 0x3C9:                         /* the DAC's data: red, green, blue */
        hzv_dac_data(value);
        break;
    case 0x201:                         /* the game port: its one-shots start */
        hzf_gameport_fire();
        break;
    }
}

void outport(unsigned port, unsigned value)
{
    if (port == 0x3D4)                  /* the CRTC: index in the low byte, data high */
        hzv_crtc((unsigned char)value, (unsigned char)(value >> 8));
    /* (3C4, 3CE: mode X's set-up, nothing to do) */
}

void intr(int n, struct REGPACK *r)
{
    (void)n;
    r->r_ax = 0x0003;                   /* (the BIOS video mode asked: text) */
    r->r_flags = 0;
}

void enable(void)
{
}

void disable(void)
{
}

void sound(unsigned hz)
{
    (void)hz;
}

void nosound(void)
{
}

/* the frames go on while the time passes */
void delay(unsigned ms)
{
    unsigned long t = hg_ms();
    do
        hzf_pump();
    while (hg_ms() - t < ms);
}

/* ---------------------------------------------------------------- the text screen */

void clrscr(void)
{
}

void window(int l, int t, int r, int b)
{
    (void)l, (void)t, (void)r, (void)b;
}

void textcolor(int c)
{
    (void)c;
}

void textbackground(int c)
{
    (void)c;
}

void gotoxy(int x, int y)
{
    (void)x, (void)y;
}

int cputs(const char *s)
{
    fputs(s, stdout);
    fflush(stdout);
    return 0;
}

/* ---------------------------------------------------------------- files, memory */

long filelength(int fd)
{
    long here = lseek(fd, 0, SEEK_CUR), n;
    if (here < 0)
        return -1;
    n = lseek(fd, 0, SEEK_END);
    lseek(fd, here, SEEK_SET);
    return n;
}

/* read and write into far memory (the board, 16 KB: xargon.c's loadboard, saveboard): as
 * read and write, through a near buffer */
static unsigned char fbuf[256];

int hz_readfar(int fd, void __far *buf, unsigned n)
{
    unsigned char __far *p = (unsigned char __far *)buf;
    unsigned done = 0, k;
    int r;
    while (done < n) {
        k = n - done > sizeof fbuf ? sizeof fbuf : n - done;
        r = read(fd, fbuf, k);
        if (r < 0)
            return done ? (int)done : -1;
        if (r == 0)
            break;
        hz_far_copy(p + done, fbuf, (unsigned)r);
        done += (unsigned)r;
    }
    return (int)done;
}

int hz_writefar(int fd, const void __far *buf, unsigned n)
{
    const unsigned char __far *p = (const unsigned char __far *)buf;
    unsigned done = 0, k;
    while (done < n) {
        k = n - done > sizeof fbuf ? sizeof fbuf : n - done;
        hz_far_copy(fbuf, p + done, k);
        if (write(fd, fbuf, k) != (int)k)
            return -1;
        done += k;
    }
    return (int)done;
}

/* mem.h's (x_objman.c calls it without mem.h: declared by its call) */
void setmem(void *p, unsigned n, char v)
{
    memset(p, v, n);
}

/* the memory left: the heap's and the free banks' (upstream checks for DOS's 545 KB) */
unsigned long coreleft(void)
{
    return hz_heap_free() + ((unsigned long)hz_mem_info() << 16);
}

/* ---------------------------------------------------------------- the heap (hz_heap.h) */
#undef malloc
#undef calloc
#undef realloc
void *malloc(size_t n);
void *calloc(size_t n, size_t size);
void *realloc(void *p, size_t n);

static void out_of_memory(size_t n)
{
    unsigned f = hz_heap_free(), l = hz_heap_largest();
    hg_close();                         /* (as hz_fatal) */
    printf("xargon: out of memory: %u bytes wanted, %u free, %u in one piece\n", (unsigned)n,
           f, l);
    exit(1);
}

void *hz_malloc_or_quit(size_t n)
{
    void *p = malloc(n);
    if (!p)
        out_of_memory(n);
    return p;
}

void *hz_calloc_or_quit(size_t n, size_t size)
{
    void *p = calloc(n, size);
    if (!p)
        out_of_memory(n * size);
    return p;
}

void *hz_realloc_or_quit(void *p, size_t n)
{
    void *q = realloc(p, n);
    if (!q && n)
        out_of_memory(n);
    return q;
}

void hz_heap_report(const char *what, const char *name)
{
    printf("xargon: heap %s %s: %u free, %u in one piece\n", what, name, hz_heap_free(),
           hz_heap_largest());
}

/* ---------------------------------------------------------------- Turbo C's stdlib */

static char *utoa_(unsigned long v, char *s, int radix, int neg)
{
    char t[34];
    int n = 0, i = 0;
    if (radix < 2 || radix > 36)
        radix = 10;
    do {
        int d = (int)(v % (unsigned)radix);
        t[n++] = (char)(d < 10 ? '0' + d : 'a' + d - 10);
        v /= (unsigned)radix;
    } while (v);
    if (neg)
        s[i++] = '-';
    while (n)
        s[i++] = t[--n];
    s[i] = 0;
    return s;
}

char *itoa(int v, char *s, int radix)
{
    if (radix == 10 && v < 0)
        return utoa_((unsigned long)(-(long)v), s, 10, 1);
    return utoa_(radix == 10 ? (unsigned long)(long)v : (unsigned)v, s, radix, 0);
}

char *ltoa(long v, char *s, int radix)
{
    if (radix == 10 && v < 0)
        return utoa_((unsigned long)-v, s, 10, 1);
    return utoa_((unsigned long)v, s, radix, 0);
}

char *ultoa(unsigned long v, char *s, int radix)
{
    return utoa_(v, s, radix, 0);
}

/* Turbo C's rand: the same sequence for the same seed (the recorded demo depends on it) */
static unsigned long bc_seed = 1;

int bc_rand(void)
{
    bc_seed = bc_seed * 0x015A4E35UL + 1;
    return (int)(bc_seed >> 16) & 0x7FFF;
}

void bc_srand(unsigned seed)
{
    bc_seed = seed;
}
