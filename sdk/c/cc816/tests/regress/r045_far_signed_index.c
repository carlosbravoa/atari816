/* r045_far_signed_index.c - p[i] through a far pointer with a signed i: in the far data
 * model the index is added to the offset alone (IR addlo: the element lies in the
 * pointer's object, so in its bank), no longer widened to 32 bits; negative indexes, an
 * object at a bank's offset 0, a structure array through a pointer, and the near model's
 * 32-bit step, all must give the same results. LEVELS: 0 1 2 */
#include <stdlib.h>
#include <horizon.h>

struct cell { int a; unsigned char b; };
static int arr[10] = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
static struct cell cells[6];

static int sum_around(const int *p, int lo, int hi)
{
    int i, s = 0;
    for (i = lo; i < hi; i++)
        s += p[i];
    return s;
}

static int far_back(unsigned char __far *q, int n)
{
    int i, s = 0;
    for (i = -n; i < 0; i++)
        s += q[i];
    return s;
}

int main(void)
{
    unsigned char __far *bank = hz_far_alloc();
    struct cell *c = cells + 3;
    int i, k;
    char *m;
    if (!bank)
        return 1;
    if (sum_around(arr + 5, -5, 5) != 55 || sum_around(arr, 0, 10) != 55)
        return 2;
    for (i = 0; i < 20; i++)
        bank[i] = (unsigned char)(i + 1);
    if (far_back(bank + 10, 10) != 55)          /* down to the bank's offset 0 */
        return 3;
    for (i = -3; i < 3; i++) {
        c[i].a = i * 7;
        c[i].b = (unsigned char)(i + 3);
    }
    k = 0;
    for (i = 0; i < 6; i++)
        k += cells[i].a + cells[i].b;
    if (k != -21 + 15)
        return 4;
    m = malloc(100);
    if (!m)
        return 5;
    for (i = 0; i < 100; i++)
        m[i] = (char)i;
    m += 50;
    k = 0;
    for (i = -50; i < 50; i++)
        k += m[i];
    if (k != 4950)
        return 6;
    free(m - 50);
    hz_far_free(bank);
    return 0;
}
