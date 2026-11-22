/* r003_nearfar.c - a near pointer widened to 32 bits (a __far pointer or a long) gets the
 * code bank as its high word (HZ_BANK of any pointer is right), and a null pointer stays
 * null (a far null from a near one). */
#include <horizon.h>

static char g[4];

int main(void)
{
    char loc[4];
    char *np = 0;
    char __far *f1 = np;                 /* null stays null */
    char __far *f2 = g;
    char __far *f3 = loc;
    unsigned long l = (unsigned long)g;
    unsigned bank = HZ_BANK(g);
    if (f1)
        return 1;
    if (!f2 || !f3)
        return 2;
    if ((unsigned)(l >> 16) != bank || bank == 0)
        return 3;
    if (HZ_OFF(g) != (unsigned)g || HZ_BANK(loc) != bank)
        return 4;
    g[1] = 5;
    if (f2[1] != 5)
        return 5;
    loc[2] = 7;
    if (f3[2] != 7)
        return 6;
    f2[3] = 9;
    return g[3] == 9 ? 0 : 7;
}
