/* r046_negative_index.c - a negative index through a near pointer: the index went into
 * an index register (Y of (dp),y or (sr,s),y; X of abs,x) as its 16-bit value, $FFFF for
 * -1, and the 65816 adds an index register to its base in 24 bits: p[-1] read p + $FFFF,
 * the next bank, not p - 1. Only a constant index (p[-1]) and an array indexed from its
 * start were right. Now an index is kept in a register only when it is known to be a
 * non-negative offset (a byte, a mask, a loop counting up from 0, a value a branch found
 * >= 0); any other is added to the pointer in 16 bits (which wraps in the bank, as C's
 * near pointers do: p[u] with an unsigned u of $FFFF is p[-1]). The shapes: a pointer
 * parameter with an int, a signed char, an i - 1, an i + 2 index, *(p - n), a loop down
 * to 0, a pointer into the middle of an array both ways, an array of structures, a row
 * of a 2-D array, a pointer to an element of a global (a[5] + i: abs,x with X = i + 10),
 * a[d + 1] split (r040), stores, and the far pointers' p[d + 1] at a bank's offset 0
 * (IR addlo: the constant part was put in Y, which carried into the next bank). The
 * emulator's --log-bankwrap (check.py runs every program with it) reports any access
 * that still carries. Found by the far data model's r045. LEVELS: 0 1 2 */
#include <horizon.h>

struct cell { int a; unsigned char b; long c; };

static int arr[10] = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
static unsigned char bytes[8] = { 10, 20, 30, 40, 50, 60, 70, 80 };
static struct cell cells[6];
static int grid[5][4];
static struct { int pad; int row[6]; } holder = { 99, { 11, 12, 13, 14, 15, 16 } };
static volatile int vm1 = -1, vm2 = -2, v0 = 0, v3 = 3;

static int get(const int *p, int i) { return p[i]; }
static int getc8(const unsigned char *p, signed char i) { return p[i]; }
static int getm1(const int *p, int i) { return p[i - 1]; }
static int getp2(const int *p, int i) { return p[i + 2]; }
static int back(const int *p, int n) { return *(p - n); }
#ifndef __CC816_FAR_DATA__
static int getu(const int *p, unsigned u) { return p[u]; }
#endif
static long cellc(const struct cell *p, int i) { return p[i].c + p[i].a + p[i].b; }
static int row(int (*q)[4], int i, int j) { return q[i][j]; }
static void put(int *p, int i, int v) { p[i] = v; }
static void putb(unsigned char *p, int i, int v) { p[i] = (unsigned char)v; }

static int sum_down(const int *p, int n)
{
    int i, s = 0;
    for (i = n; i > 0; i--)
        s += p[i - 1];
    return s;
}

static int sum_from(const int *p, int lo, int hi)
{
    int i, s = 0;
    for (i = lo; i < hi; i++)
        s += p[i];
    return s;
}

static int sum_while(const int *p, int n)
{
    int s = 0;
    while (--n >= 0)
        s += p[n];
    return s;
}

static int global_mid(int i)
{
    int *p = &arr[5];
    return p[i];
}

static int split(int d)
{
    return arr[d + 1];
}

static long far_split(const int __far *p, int d)
{
    return p[d + 1] + p[d + 2];
}

int main(void)
{
    int *m = arr + 5;
    int i, k;
    if (get(m, vm1) != 5 || get(m, vm2) != 4 || get(m, -5) != 1 || get(m, v3) != 9)
        return 1;
    if (getc8(bytes + 4, (signed char)vm1) != 40 || getc8(bytes + 4, -4) != 10 ||
            getc8(bytes + 4, (signed char)v3) != 80)
        return 2;
    if (getm1(m, v0) != 5 || getm1(m, vm1) != 4 || getm1(arr + 1, v0) != 1)
        return 3;
    if (getp2(m, vm2) != 6 || getp2(m, -7) != 1)
        return 4;
    if (back(m, 1) != 5 || back(m, v3) != 3 || back(m, vm1) != 7 || m[-1] != 5)
        return 5;
#ifndef __CC816_FAR_DATA__
    /* (far data does not wrap an offset: docs/c/reference.md, the far data model) */
    if (getu(m, 0xFFFFu) != 5 || getu(m, (unsigned)vm2) != 4)
        return 6;
#endif
    if (sum_down(arr, 10) != 55 || sum_down(m, 5) != 40)
        return 7;
    if (sum_from(m, -5, 5) != 55 || sum_from(m, vm2, 0) != 9)
        return 8;
    if (sum_while(arr, 10) != 55 || sum_while(m, 3) != 21)
        return 9;
    for (i = 0; i < 6; i++) {
        cells[i].a = i;
        cells[i].b = (unsigned char)(10 * i);
        cells[i].c = 1000L * i;
    }
    if (cellc(cells + 3, vm1) != 2022 || cellc(cells + 3, -3) != 0 || cellc(cells + 3, 2) != 5055)
        return 10;
    for (i = 0; i < 5; i++)
        for (k = 0; k < 4; k++)
            grid[i][k] = i * 10 + k;
    if (row(grid + 2, vm1, 3) != 13 || row(grid + 2, -2, 0) != 0 || row(grid + 4, v0, 1) != 41)
        return 11;
    if (global_mid(vm1) != 5 || global_mid(-5) != 1 || global_mid(v3) != 9)
        return 12;
    if (split(vm1) != 1 || split(v0) != 2)
        return 13;
    put(m, vm1, 50);
    putb(bytes + 4, vm2, 33);
    if (arr[4] != 50 || bytes[2] != 33)
        return 14;
    i = vm1;
    m[i] = 5;
    m[i - 1] += 1;
    if (arr[4] != 5 || arr[3] != 5)
        return 15;
    k = vm2;
    if (holder.row[k + 3] != 12 || (holder.row + 3)[k] != 12)
        return 16;
    {
        int __far *fp = (int __far *)hz_far_alloc();
        if (!fp)
            return 17;
        fp[0] = 7;
        fp[1] = 8;
        if (far_split(fp, vm1) != 15)             /* the bank's offset 0 */
            return 18;
        hz_far_free(fp);
    }
    return 0;
}
