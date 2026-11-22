/* setjmp.c - setjmp and longjmp: from deep recursion with locals on both stacks, from a
 * qsort comparison (a library function's callee-saved registers), many times in a loop
 * (no stack is lost), with long, long long and float values, volatile locals that keep
 * their last value, a value live across setjmp that is not changed, longjmp(env, 0). */
#include <horizon.h>
#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>

static jmp_buf jb, jb2;
static int calls;

static void deep(int n, long acc, long long big, float f)
{
    char pad[24];               /* (on the software stack) */
    int i;
    for (i = 0; i < 24; i++)
        pad[i] = (char)(n + i);
    ++calls;
    if (n == 0)
        longjmp(jb, (int)(acc % 1000) + pad[3] + (int)(big >> 40) + (int)f);
    deep(n - 1, acc * 3 + n, big * 2, f + 1.5f);
}

static int ncmp;
static int cmp(const void *a, const void *b)
{
    int x = *(const int *)a, y = *(const int *)b;
    if (++ncmp == 9)
        longjmp(jb, 99);
    return x - y;
}

static int inner(int k)
{
    if (setjmp(jb2) == 0) {
        if (k)
            longjmp(jb2, 0);    /* setjmp then returns 1 */
        return 10;
    }
    return 20;
}

int main(void)
{
    volatile int count = 0;
    volatile long lv = 1;
    volatile long long llv = 5;
    volatile float fv = 1.5f;
    long keep = 123456789L;     /* not changed after setjmp: keeps its value */
    long long kll = -0x123456789ALL;
    int r, i, arr[30];
    unsigned hs, ss;
    int bad = 0;

    r = setjmp(jb);
    if (r == 0) {
        count = 1;
        lv = 100000L;
        llv = 1LL << 40;
        fv = 2.5f;
        deep(12, 1, 1LL << 41, 0.5f);
        bad |= 1;               /* not reached */
    }
    /* deep(12): acc % 1000 is 227 (acc 3587227), pad[3] 3, big >> 40 8192, f 18.5 */
    if (r != 227 + 3 + 8192 + 18 || calls != 13)
        bad |= 2;
    if (count != 1 || lv != 100000L || llv != 1LL << 40 || fv != 2.5f)
        bad |= 4;
    if (keep != 123456789L || kll != -0x123456789ALL)
        bad |= 8;

    for (i = 0; i < 30; i++)
        arr[i] = 30 - i;
    if ((r = setjmp(jb)) == 0)
        qsort(arr, 30, sizeof arr[0], cmp);
    if (r != 99 || ncmp != 9)
        bad |= 16;

    hs = hz_stack_free();
    ss = hz_sstack_free();
    for (i = 0; i < 2000; i++) {
        if (setjmp(jb) == 0) {
            count++;
            deep(i % 9, i, i, 0.0f);
        }
    }
    if (count != 2001)
        bad |= 32;
    if (hz_stack_free() != hs || hz_sstack_free() != ss)
        bad |= 64;
    if (inner(0) != 10 || inner(1) != 20)
        bad |= 128;
    if (keep != 123456789L || kll != -0x123456789ALL)
        bad |= 256;
    if (bad)
        printf("setjmp: failed %d\n", bad);
    return bad;
}
