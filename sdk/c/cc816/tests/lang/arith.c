/* arith.c - the integer promotions and the usual arithmetic conversions at the limits
 * (int 16 bits, long 32, char unsigned), division and modulo signs, shifts. */
#include <limits.h>

static volatile int vi;
static volatile unsigned vu;
static volatile long vl;
static volatile unsigned char vc;
static volatile signed char vs;

int main(void)
{
    vi = -1; vu = 1; vl = -1; vc = 255; vs = -128;
    if (!(vi < vu ? 0 : 1))         /* -1 becomes 65535u: not smaller than 1u */
        return 1;
    if (!(vl < vu))                 /* long holds every unsigned: -1 < 1 */
        return 2;
    if (vc + 1 != 256 || vs - 1 != -129 || (unsigned char)(vc + 1) != 0)
        return 3;
    if (sizeof(vc + vc) != 2 || sizeof(vc + 1L) != 4 || sizeof(vu + vl) != 4)
        return 4;
    vi = INT_MAX;
    if (vi + 1 != INT_MIN || (unsigned)vi + 1 != 32768u)    /* wraps (as gcc does) */
        return 5;
    vu = UINT_MAX;
    if (vu + 1 != 0 || vu * vu != 1 || (long)vu != 65535L)
        return 6;
    vl = LONG_MAX;
    if ((unsigned long)vl + 1 != 0x80000000UL)
        return 7;
    vi = -7;
    if (vi / 2 != -3 || vi % 2 != -1 || 7 / -2 != -3 || 7 % -2 != 1 || -7 / -2 != 3 ||
        -7 % -2 != -1)
        return 8;
    vl = -100000L;
    if (vl / 7 != -14285L || vl % 7 != -5 || vl / -7 != 14285L)
        return 9;
    vu = 40000u;
    if (vu / 3 != 13333u || vu % 3 != 1 || (vu >> 1) != 20000u)
        return 10;
    vi = -16;
    if ((vi >> 2) != -4 || (vi << 2) != -64 || ((unsigned)vi >> 12) != 15)
        return 11;
    vl = 1;
    if ((vl << 31) != LONG_MIN || (1UL << 31) != 0x80000000UL || (vl << 16) != 65536L)
        return 12;
    vc = 200;
    if ((vc ^ 0xFF) != 55 || (~vc & 0xFFFF) != 0xFF37u || -vc != -200)
        return 13;
    if (CHAR_MIN != 0 || CHAR_MAX != 255 || SCHAR_MIN != -128)
        return 14;
    {
        char c = 200;
        if (c < 0 || c != 200)
            return 15;
    }
    if (-32768 != INT_MIN - 0L || sizeof(-32768) != 4 || sizeof(32767) != 2 ||
        sizeof(65535u) != 2 || sizeof(65536) != 4 || sizeof(0xFFFF) != 2)
        return 16;
    return 0;
}
