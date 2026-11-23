/* r044_pointer_model.c - the pointer shapes the far data model (hcc --data far) changes,
 * checked in every model (the same results with 16-bit near and 32-bit far pointers):
 * structures of pointers, arrays of strings, static initialisers holding addresses of
 * other objects (relocated at the start), string literals merged, function pointers
 * beside data pointers, variable arguments that are pointers, qsort's callbacks, the
 * address of locals given to the library, recursion through pointers to locals, setjmp
 * with a jmp_buf reached through a pointer, NULL and conversions to unsigned long. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <setjmp.h>

struct item { const char *name; int (*fn)(int); int *count; struct item *next; };
static int twice(int x) { return 2 * x; }
static int neg(int x) { return -x; }
static int counts[3];
static struct item items[3] = {
    { "first", twice, &counts[0], &items[1] },
    { "second", neg, &counts[1], &items[2] },
    { "third", 0, &counts[2], 0 },
};
static const char *const words[] = { "pear", "apple", "fig", "apple" };
static const char *wp = "pear";
static char buf[32];
static char *bp = buf + 3;
static const int table[4] = { 10, 20, 30, 40 };
static const int *tp = &table[2];

static int join(char *out, int n, ...)
{
    va_list ap;
    int len = 0;
    out[0] = 0;
    va_start(ap, n);
    while (n--) {
        const char *s = va_arg(ap, const char *);
        int *k = va_arg(ap, int *);
        strcat(out, s);
        len += *k;
    }
    va_end(ap);
    return len;
}

static int cmp(const void *a, const void *b)
{
    return strcmp(*(const char *const *)a, *(const char *const *)b);
}

static int depth(char *above, int n)
{
    char here[8];
    sprintf(here, "%c", 'a' + n);
    if (n == 0)
        return above[0];
    return depth(here, n - 1) + (above ? above[0] : 0);
}

static jmp_buf jb;
static jmp_buf *jbp = &jb;

int main(void)
{
    struct item *it;
    int total = 0, a = 3, b = 4, k;
    char out[40];
    const char *sorted[4];
    char *nul = NULL;
    for (it = items; it; it = it->next) {
        if (it->fn)
            total += it->fn(5);
        ++*it->count;
    }
    if (total != 5 || counts[0] != 1 || counts[2] != 1 || strcmp(items[2].name, "third"))
        return 1;
    if (words[1] != words[3] || strcmp(words[2], "fig") || wp[0] != 'p')
        return 2;
    bp[0] = 'x';
    if (buf[3] != 'x' || *tp != 30 || tp - table != 2)
        return 3;
    if (join(out, 2, "ab", &a, "cd", &b) != 7 || strcmp(out, "abcd"))
        return 4;
    memcpy(sorted, words, sizeof sorted);
    qsort(sorted, 4, sizeof sorted[0], cmp);
    if (strcmp(sorted[0], "apple") || strcmp(sorted[3], "pear"))
        return 5;
    if (depth(out, 4) != 'a' + 'b' + 'c' + 'd' + 'e' - 'a' + 'a')
        return 6;
    if (nul || nul != 0 || (unsigned long)(void *)nul != 0)
        return 7;
    if ((unsigned)(unsigned long)(void *)&buf[5] != (unsigned)(unsigned long)(void *)buf + 5)
        return 8;
    k = setjmp(*jbp);
    if (k == 0)
        longjmp(*jbp, 9);
    if (k != 9)
        return 9;
    sprintf(out, "%s/%s", items[0].name, words[2]);
    if (strcmp(out, "first/fig"))
        return 10;
    return 0;
}
