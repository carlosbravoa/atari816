/* exprs.c - the comma operator, the conditional operator with mixed types, sizeof of
 * expressions, types and arrays, _Bool. */
#include <stddef.h>
#include <stdbool.h>

/* a data pointer's size: 2, or 4 with far data (hcc --data far) */
#ifdef __CC816_FAR_DATA__
#define PTRSZ 4
#else
#define PTRSZ 2
#endif

static int calls;
static int touch(int v) { calls++; return v; }

int main(void)
{
    int a = 1, b = 2, arr[10];
    long l = 100000L;
    char c = 'x';
    char *p = NULL;
    void *v = &a;
    _Bool t = 5, f = 0;
    bool z = 0.5;
    a = (b++, b + 10);                  /* comma: b is 3 */
    if (a != 13 || b != 3)
        return 1;
    if ((1 ? l : a) != 100000L || sizeof(1 ? l : a) != 4 || sizeof(0 ? c : c) != 2 ||   /* (char ? char: promoted to int) */
       
        sizeof(1 ? c : 1) != 2)
        return 2;
    if ((a ? p : NULL) != NULL || (a ? v : &b) != &a || (b > 100 ? 1.5 : 2) != 2.0)
        return 3;
    if (sizeof arr != 20 || sizeof arr[0] != 2 || sizeof(arr) / sizeof(arr[0]) != 10 ||
        sizeof(long) != 4 || sizeof(char *) != PTRSZ || sizeof &arr != PTRSZ ||
        sizeof "abc" != 4)
        return 4;
    if (sizeof(touch(1)) != 2 || calls != 0)   /* sizeof does not evaluate */
        return 5;
    if (t != 1 || f != 0 || z != 1 || sizeof(_Bool) != 1 || (_Bool)256 != 1 || !t + 1 != 1)
        return 6;
    t = 0;
    t++;
    t++;
    if (t != 1)
        return 7;
    t--;
    if (t != 0)
        return 7;
    t--;                                /* 0 - 1 is true */
    if (t != 1 || t++ != 1 || t != 1)
        return 7;
    {
        static _Bool g;
        g++;
        g++;
        if (g != 1)
            return 7;
    }
    if ((touch(0) && touch(1)) || calls != 1 || (touch(1) || touch(2)) != 1 || calls != 2)
        return 8;
    a = 5;
    b = a > 3 ? a < 10 ? 1 : 2 : 3;
    if (b != 1)
        return 9;
    return 0;
}
