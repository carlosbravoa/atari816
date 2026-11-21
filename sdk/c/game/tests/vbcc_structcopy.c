/* vbcc_structcopy.c - vbcc 65816's structure-copy fault (sdk/docs/c/games.md, "Limits and
 * known faults"): "a[i] = b[i]" between arrays of structures, at -O1, copies from and to
 * addresses it never loaded (the task is killed, or memory is damaged). SAFE=1: memcpy. */
#include <stdio.h>
#include <string.h>

typedef struct { unsigned char a, b; short x, y; unsigned char c[3]; unsigned char d; } S10;
static S10 src[4], dst[4];

int main(void)
{
    unsigned i;
    for (i = 0; i < 4; i++) {
        src[i].a = (unsigned char)(10 + i);
        src[i].x = (short)(100 + i);
        src[i].d = (unsigned char)(50 + i);
    }
    for (i = 0; i < 2; i++)
#if SAFE
        memcpy(&dst[i], &src[i], sizeof(S10));
#else
        dst[i] = src[i];
#endif
    if (dst[0].a == 10 && dst[0].x == 100 && dst[1].d == 51)
        printf("STRUCTCOPY: ok\n");
    else
        printf("STRUCTCOPY: wrong\n");
    return 0;
}
