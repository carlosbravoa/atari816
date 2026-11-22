/* r029_far_postinc.c - *p++ and *p-- through __far pointers: the access through p, then a
 * 32-bit step of p (no copy of the old pointer; the step carries into the bank: a pointer
 * at offset $FFFF steps into the next bank). Copy loops of bytes, words and longs, both
 * directions. (Before, far *p++ copied the pointer each time; the step is now done in
 * place, the +1 as INC / BNE / INC.) */
#include <horizon.h>

static unsigned char src[40], dst[40];
static unsigned wsrc[8], wdst[8];
static long lsrc[4], ldst[4];

static void copyb(unsigned char __far *d, const unsigned char __far *s, unsigned n)
{
    while (n--)
        *d++ = *s++;
}

static void copyw(unsigned __far *d, const unsigned __far *s, unsigned n)
{
    while (n--)
        *d++ = *s++;
}

static void copyl(long __far *d, const long __far *s, unsigned n)
{
    while (n--)
        *d++ = *s++;
}

static void rcopy(unsigned char __far *d, const unsigned char __far *s, unsigned n)
{
    d += n - 1;
    s += n - 1;
    while (n--)
        *d-- = *s--;
}

int main(void)
{
    unsigned i;
    unsigned char __far *bank;
    unsigned char __far *p;
    for (i = 0; i < 40; i++)
        src[i] = (unsigned char)(i * 7 + 1);
    for (i = 0; i < 8; i++)
        wsrc[i] = i * 1000u + 3;
    for (i = 0; i < 4; i++)
        lsrc[i] = 100000L * i - 7;
    copyb(dst, src, 40);
    for (i = 0; i < 40; i++)
        if (dst[i] != src[i])
            return 1;
    copyw(wdst, wsrc, 8);
    for (i = 0; i < 8; i++)
        if (wdst[i] != wsrc[i])
            return 2;
    copyl(ldst, lsrc, 4);
    for (i = 0; i < 4; i++)
        if (ldst[i] != lsrc[i])
            return 3;
    for (i = 0; i < 40; i++)
        dst[i] = 0;
    rcopy(dst + 1, src, 39);
    for (i = 0; i < 39; i++)
        if (dst[i + 1] != src[i])
            return 4;
    if (dst[0] != 0)
        return 5;
    /* the step carries into the bank */
    bank = hz_far_alloc();
    if (!bank)
        return 0;
    p = bank + 0xFFFFu;
    *p++ = 42;
    if ((unsigned long)p != (unsigned long)bank + 0x10000L || bank[0xFFFFu] != 42)
        return 6;
    p = bank + 0xFFFFu;
    *p-- = 43;
    if ((unsigned long)p != (unsigned long)bank + 0xFFFEL)
        return 7;
    hz_far_free(bank);
    return 0;
}
