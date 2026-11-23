/* far_edges.h - far pointer arithmetic at a bank's edges, shared by r047_far_wrap.c
 * (-ffar-wrap: the offset alone, the bank never changes, DOS's far pointers) and
 * r048_far_carry.c (the default: a pointer value is the 24-bit address, one past the
 * bank's last byte is the next bank's offset 0; an element p[i] with a signed i, in the
 * far data model, on the offset). Values are compared as (unsigned long), so the default's
 * pointers into the next bank are never read. LEVELS: 0 1 2 */
#include <horizon.h>

#ifdef __CC816_FAR_WRAP__
#define W 1
#else
#define W 0
#endif

enum { T = 10000 };
struct rec { int a; unsigned char b; long c; };

static unsigned long U(const void __far *p) { return (unsigned long)p; }
static unsigned long A(unsigned bank, unsigned off) { return ((unsigned long)bank << 16) | off; }

/* the integers come through functions, so nothing is folded at compile time */
static int iv(int x) { return x; }
static unsigned uv(unsigned x) { return x; }
static long lv(long x) { return x; }

static int values(unsigned b)
{
    unsigned char __far *top = hz_farptr(b, 0xFFFF);
    unsigned char __far *bot = hz_farptr(b, 0);
    unsigned char __far *mid = hz_farptr(b, 0x1000);
    unsigned char __far *hi = hz_farptr(b, 0xC000);
    unsigned char __far *p;
    int __far *q;
    struct rec __far *r;
    /* one past the bank's last byte */
    if (U(top + 1) != (W ? A(b, 0) : A(b + 1, 0)))
        return 10;
    if (U(top + iv(1)) != (W ? A(b, 0) : A(b + 1, 0)))
        return 11;
    p = top; p++;
    if (U(p) != (W ? A(b, 0) : A(b + 1, 0)))
        return 12;
    p = top; ++p;
    if (U(p) != (W ? A(b, 0) : A(b + 1, 0)))
        return 13;
    p = top; p += uv(1);
    if (U(p) != (W ? A(b, 0) : A(b + 1, 0)))
        return 14;
    if (U(&top[1]) != (W ? A(b, 0) : A(b + 1, 0)))
        return 15;
    /* one before the bank's first byte */
    if (U(bot - 1) != (W ? A(b, 0xFFFF) : A(b - 1, 0xFFFF)))
        return 20;
    if (U(bot - iv(1)) != (W ? A(b, 0xFFFF) : A(b - 1, 0xFFFF)))
        return 21;
    p = bot; p--;
    if (U(p) != (W ? A(b, 0xFFFF) : A(b - 1, 0xFFFF)))
        return 22;
    if (U(bot + iv(-1)) != (W ? A(b, 0xFFFF) : A(b - 1, 0xFFFF)))
        return 23;
    /* an int that overflowed (4 * 10000 = 40000 is -25536 in 16 bits): DOS added it to
       the offset (0x1000 + 40000 = 0xAC40); the 24-bit address goes 25,536 bytes back */
    if (U(mid + iv(4 * T)) != (W ? A(b, 0xAC40) : A(b, 0x1000) - 25536ul))
        return 30;
    if (U((unsigned short __far *)(mid + iv(4 * T))) != (W ? A(b, 0xAC40) : A(b, 0x1000) - 25536ul))
        return 31;
    q = (int __far *)mid;
    if (U(q + iv(2 * T)) != (W ? A(b, 0xAC40) : A(b, 0x1000) - 25536ul))
        return 32;
    /* the unsigned 40000: forwards in both, the carry differs past the bank's end */
    if (U(mid + uv(40000u)) != A(b, 0xAC40))
        return 33;
    if (U(hi + uv(40000u)) != (W ? A(b, 0x5C40) : A(b + 1, 0x5C40)))
        return 34;
    if (U(hi + 40000u) != (W ? A(b, 0x5C40) : A(b + 1, 0x5C40)))
        return 35;
    if (U(hi - uv(0xD000u)) != (W ? A(b, 0xF000) : A(b - 1, 0xF000)))
        return 36;
    /* a long: its low word with -ffar-wrap (as Watcom's far + long), the whole value by
       default */
    if (U(mid + lv(0x10000L)) != (W ? A(b, 0x1000) : A(b + 1, 0x1000)))
        return 40;
    if (U(mid + lv(-1L)) != A(b, 0x0FFF))
        return 41;
    if (U(top + lv(2L)) != (W ? A(b, 1) : A(b + 1, 1)))
        return 42;
    /* a structure pointer, stepped */
    r = (struct rec __far *)hz_farptr(b, 0xFFF9);
    r++;
    if (U(r) != (W ? A(b, 0x0000) : A(b + 1, 0x0000)))
        return 50;
    r = (struct rec __far *)hz_farptr(b, 3);
    if (U(r - iv(1)) != (W ? A(b, 0xFFFC) : A(b - 1, 0xFFFC)))
        return 51;
    /* the difference of two pointers is of their offsets, in both */
    if ((top + 1) - mid != (int)(0x10000ul - 0x1000))
        return 60;
    /* inside the bank, the two agree */
    if (U(mid + iv(-0x800)) != A(b, 0x0800) || U(top - iv(0x7FFF)) != A(b, 0x8000))
        return 61;
    return 0;
}

/* -ffar-wrap: reads and writes through pointers that wrapped stay in the bank */
static int reads(unsigned char __far *bank)
{
#if W
    unsigned b = HZ_BANK(bank);
    unsigned char __far *top = hz_farptr(b, 0xFFFE);
    unsigned char __far *hi = hz_farptr(b, 0xC000);
    unsigned char __far *bot = hz_farptr(b, 0);
    unsigned char __far *p;
    unsigned short __far *w;
    int i, s;
    bank[0xFFFE] = 1; bank[0xFFFF] = 2; bank[0] = 3; bank[1] = 4; bank[2] = 5;
    p = top;
    s = 0;
    for (i = 0; i < 5; i++)
        s = s * 10 + *p++;                      /* across the top: 1 2 3 4 5 */
    if (s != 12345 || U(p) != A(b, 3))
        return 70;
    if (top[iv(2)] != 3 || top[uv(3)] != 4 || top[iv(4)] != 5)
        return 71;
    if (bot[-1] != 2 || bot[iv(-2)] != 1 || bot[uv(0xFFFFu)] != 2)
        return 72;
    bank[0x5C40] = 77;
    if (hi[40000u] != 77 || hi[uv(40000u)] != 77 || *(hi + iv(40000u)) != 77)
        return 73;
    w = (unsigned short __far *)hz_farptr(b, 0x1000);
    bank[0xAC40] = 0x34; bank[0xAC41] = 0x12;
    if (*(w + iv(2 * T)) != 0x1234 || w[iv(2 * T)] != 0x1234)
        return 74;
    p = hz_farptr(b, 1);
    p -= 2;
    if (*p != 2)
        return 75;
    for (i = 0, p = top; i < 4; i++)
        *p++ = (unsigned char)(i + 10);         /* writes across the top */
    if (bank[0xFFFE] != 10 || bank[0xFFFF] != 11 || bank[0] != 12 || bank[1] != 13)
        return 76;
#else
    (void)bank;
#endif
    return 0;
}

int main(void)
{
    unsigned char __far *bank = hz_far_alloc();
    int k;
    if (!bank)
        return 1;
    k = values(HZ_BANK(bank));
    if (!k)
        k = reads(bank);
    hz_far_free(bank);
    return k;
}
