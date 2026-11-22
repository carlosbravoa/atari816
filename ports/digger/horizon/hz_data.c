/* hz_data.c - Digger's pictures (DIGGER.DAT, made by tools/mkdata.py from upstream's
 * vgagrafx.c, alpha.c and title_gz.c) loaded into far memory: a bank for each of the
 * file's bank images. */
#include <stdio.h>
#include <string.h>
#include <horizon.h>
#include "hz_plat.h"

#define MAXB 8
#define NSPR 120
#define NCH  0x5F

/* where everything is: in a bank of its own (the main bank is full) */
struct tab {
    unsigned char bankof[MAXB];
    unsigned char sprb[NSPR];
    unsigned spro[NSPR], sprn[NSPR];
    unsigned char chb[NCH][4];
    unsigned cho[NCH][4];
    unsigned char titb[2];
    unsigned tito[2];
};
static struct tab __far *T;

static unsigned u16(const unsigned char *p)
{
    return p[0] | (unsigned)p[1] << 8;
}

static int rd(int fh, void __far *dst, unsigned n)
{
    hz_io io;
    unsigned k;
    unsigned char __far *d = (unsigned char __far *)dst;
    while (n) {
        k = n > 0x8000u ? 0x8000u : n;
        io.handle = (unsigned char)fh;
        HZ_U24(io.buf, d);
        io.len = k;
        if (hz_read(&io) != (int)k)
            return -1;
        d += k;
        n -= k;
    }
    return 0;
}

static int fail(const char *what)
{
    printf("digger: DIGGER.DAT: %s\n", what);
    return -1;
}

int hzd_load(void)
{
    static char path[160];
    unsigned char e[16];
    unsigned nb, ns, nc, i, k;
    unsigned long len[MAXB];
    int fh;

    strcpy(path, hz_progdir);
    strcat(path, "DIGGER.DAT");
    fh = hz_open(path, HZ_O_READ);
    if (fh < 0)
        fh = hz_open("DIGGER.DAT", HZ_O_READ);
    if (fh < 0)
        return fail("not found (it belongs next to DIGGER.PRG)");
    T = (struct tab __far *)hz_far_alloc();
    if (!T) {
        hz_close((unsigned)fh);
        return fail("no free memory bank");
    }
    if (rd(fh, e, 16) || memcmp(e, "DIGHZ1", 6))
        goto bad;
    nb = u16(e + 8);
    ns = u16(e + 10);
    nc = u16(e + 12);
    if (nb > MAXB || ns != NSPR || nc != NCH)
        goto bad;
    /* the table, an entry at a time (no big buffer in the main bank) */
    for (i = 0; i < nb; i++) {
        if (rd(fh, e, 4))
            goto bad;
        len[i] = u16(e) | (unsigned long)u16(e + 2) << 16;
    }
    for (i = 0; i < ns; i++) {
        if (rd(fh, e, 5))
            goto bad;
        T->sprb[i] = e[0];
        T->spro[i] = u16(e + 1);
        T->sprn[i] = u16(e + 3);
    }
    for (i = 0; i < nc; i++)
        for (k = 0; k < 4; k++) {
            if (rd(fh, e, 3))
                goto bad;
            T->chb[i][k] = e[0];
            T->cho[i][k] = u16(e + 1);
        }
    for (i = 0; i < 2; i++) {
        if (rd(fh, e, 3))
            goto bad;
        T->titb[i] = e[0];
        T->tito[i] = u16(e + 1);
    }
    for (i = 0; i < nb; i++) {
        void __far *b = hz_far_alloc();
        if (!b) {
            hz_close((unsigned)fh);
            return fail("no free memory bank");
        }
        T->bankof[i] = (unsigned char)HZ_BANK(b);
        /* an image of 65,536 bytes: two reads (a length is 16 bits) */
        if (len[i] > 0xFFFFUL) {
            if (rd(fh, b, 0x8000u) ||
                rd(fh, (unsigned char __far *)b + 0x8000u, 0x8000u))
                goto bad;
        } else if (rd(fh, b, (unsigned)len[i]))
            goto bad;
    }
    hz_close((unsigned)fh);
    return 0;
bad:
    hz_close((unsigned)fh);
    return fail("damaged or of another version (make it again: make)");
}

static unsigned long addr(unsigned b, unsigned off)
{
    return (unsigned long)T->bankof[b] << 16 | off;
}

unsigned long hzd_sprite(unsigned ch, unsigned *bytes)
{
    if (ch >= NSPR || T->sprb[ch] == 0xFF)
        return 0;
    *bytes = T->sprn[ch];
    return addr(T->sprb[ch], T->spro[ch]);
}

unsigned long hzd_char(unsigned ch, unsigned colour)
{
    if (ch >= NCH || T->chb[ch][colour & 3] == 0xFF)
        return 0;
    return addr(T->chb[ch][colour & 3], T->cho[ch][colour & 3]);
}

unsigned long hzd_title(unsigned half)
{
    return addr(T->titb[half & 1], T->tito[half & 1]);
}
