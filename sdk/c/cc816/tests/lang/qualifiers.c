/* qualifiers.c - const and volatile, inline functions, static in array parameters,
 * restrict, _Static_assert, __func__, __FILE__, __LINE__, __DATE__, __TIME__. */
#include <string.h>

static inline int twice(int x) { return 2 * x; }
inline int thrice(int x) { return 3 * x; }       /* a C99 inline definition */

static int first(const int a[static 3]) { return a[0] + a[2]; }
static void copy(char *restrict d, const char *restrict s) { while ((*d++ = *s++)) ; }

_Static_assert(sizeof(int) == 2, "int is 16 bits");

static const char *name(void) { return __func__; }

int main(void)
{
    const int k = 4;
    volatile int v = 3;
    const int arr[3] = { 1, 2, 3 };
    char buf[8];
    volatile unsigned char flag = 0;
    _Static_assert(sizeof(long) == 4, "long is 32 bits");
    if (twice(k) != 8 || thrice(v) != 9)
        return 1;
    v += 2;
    if (v != 5 || first(arr) != 4)
        return 2;
    copy(buf, "abc");
    if (strcmp(buf, "abc") != 0)
        return 3;
    if (strcmp(name(), "name") != 0 || strcmp(__func__, "main") != 0)
        return 4;
    if (__LINE__ != 33 || strstr(__FILE__, "qualifiers.c") == 0)
        return 5;
    if (strlen(__DATE__) != 11 || __DATE__[6] != ' ' || strlen(__TIME__) != 8 ||
        __TIME__[2] != ':')
        return 6;
    flag = 1;
    while (!flag)
        ;
    return 0;
}
