/* r028_far_objects.c - __far objects at file scope: a table declared __far is reached by
 * far pointers; in the large code model hcc puts it in a bank of far data of its own
 * (segment FD_name), so big constant tables do not fill the main bank (the Digger port
 * needed it: its pictures and tables filled the main bank). Its address is a far one
 * (bank patched at load), in code in any bank, in the main bank's data and in other far
 * data; arrays of structures, two dimensions, a writable one, a static one. */
#include <string.h>

__far const unsigned char big[40000] = { 1, 2, 3, [39999] = 99 };
__far const int words[5] = { 10, -20, 30, -40, 50 };
static __far const char msg[] = "far hello";
struct pt { int x, y; };
__far const struct pt pts[3] = { {1, 2}, {3, 4}, {5, 6} };
__far const unsigned char grid[4][3] = { {1, 2, 3}, {4, 5, 6}, {7, 8, 9}, {10, 11, 12} };
__far unsigned char work[100];
__far long count;
const unsigned char __far *pbig = big;
const unsigned char __far *const __far ptab[2] = { big, (const unsigned char __far *)msg };

static unsigned sum(const unsigned char __far *p, unsigned n)
{
    unsigned s = 0;
    while (n--)
        s += *p++;
    return s;
}

int main(void)
{
    unsigned i, s = 0;
    char buf[16];
    const struct pt __far *pp = &pts[1];
    for (i = 0; i < 5; i++)
        s += (unsigned)words[i];
    if (s != 30)
        return 1;
    if (big[0] != 1 || big[2] != 3 || big[39999] != 99 || pbig[1] != 2 || big[100] != 0)
        return 2;
    if (sum(big, 40000) != 105)
        return 3;
    for (i = 0; msg[i]; i++)
        buf[i] = msg[i];
    buf[i] = 0;
    if (strcmp(buf, "far hello") != 0)
        return 4;
    if (pts[2].x != 5 || pts[1].y != 4 || pp->x != 3)
        return 5;
    s = 0;
    for (i = 0; i < 4; i++)
        s += grid[i][2];
    if (s != 30 || grid[3][1] != 11)
        return 6;
    for (i = 0; i < 100; i++)
        work[i] = (unsigned char)i;
    work[50] += 5;
    if (work[50] != 55 || work[99] != 99)
        return 7;
    if (ptab[0][39999] != 99 || ptab[1][4] != 'h')
        return 8;
    if (&big[5] - &big[0] != 5 || sizeof big != 40000u || sizeof pts != 12u)
        return 9;
    count = 70000L;
    count += 5;
    if (count != 70005L)
        return 10;
    return 0;
}
