/* qsort.c - qsort (Shell's sort: no recursion, no extra memory) and bsearch, cc816 */
#include <stdlib.h>

static void swap(unsigned char *a, unsigned char *b, size_t n)
{
    unsigned char t;
    while (n--) {
        t = *a;
        *a++ = *b;
        *b++ = t;
    }
}

void qsort(void *base, size_t n, size_t size, int (*cmp)(const void *, const void *))
{
    unsigned char *a = base;
    size_t gap, i, j;
    for (gap = 1; gap < n / 3; gap = gap * 3 + 1)
        ;
    for (; gap; gap /= 3)
        for (i = gap; i < n; ++i)
            for (j = i; j >= gap && cmp(a + (j - gap) * size, a + j * size) > 0; j -= gap)
                swap(a + (j - gap) * size, a + j * size, size);
}

void *bsearch(const void *key, const void *base, size_t n, size_t size,
              int (*cmp)(const void *, const void *))
{
    const unsigned char *a = base;
    size_t lo = 0, hi = n, mid;
    int r;
    while (lo < hi) {
        mid = lo + (hi - lo) / 2;
        r = cmp(key, a + mid * size);
        if (r == 0)
            return (void *)(a + mid * size);
        if (r < 0)
            hi = mid;
        else
            lo = mid + 1;
    }
    return 0;
}
