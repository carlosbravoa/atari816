/* r031_licm.c - loop-invariant code motion (a computation whose operands do not change in
 * the loop moves before it) and strength reduction sharing one induction variable among
 * arrays of the same element size. A value assigned once in the loop but read before it
 * (the previous iteration's) must not move; nor one that is live into the loop; a loop
 * run zero times; a value used after the loop. */
static unsigned char map[12][20];
static int ax[10], ay[10], az[10];
static long lx[10];
static volatile unsigned twelve = 12, zero = 0;

static unsigned sum2d(unsigned rows)
{
    unsigned r, c, t = 0;
    for (r = 0; r < rows; r++)
        for (c = 0; c < 20; c++)
            t += map[r][c];
    return t;
}

static int lagged(int k)
{
    int i, prev = 0, cur = 0, s = 0;
    for (i = 0; i < 5; i++) {
        s += prev;              /* the value of the last iteration */
        prev = cur;
        cur = k * 3;            /* invariant, but prev reads it a turn late */
    }
    return s;                   /* 0 + 0 + 3k + 3k + 3k */
}

static int after(int a, int b, unsigned n)
{
    unsigned i;
    int t = 0, u = 0;
    for (i = 0; i < n; i++) {
        t = a * b + 1;          /* invariant */
        u += t;
    }
    return t + u;
}

int main(void)
{
    unsigned r, c, i;
    long sl = 0;
    int s = 0;
    for (r = 0; r < 12; r++)
        for (c = 0; c < 20; c++)
            map[r][c] = (unsigned char)(r * 20 + c);
    if (sum2d(twelve) != 28680u || sum2d(zero) != 0)
        return 1;
    if (lagged(7) != 63)
        return 2;
    if (after(3, 4, 5) != 13 + 65 || after(3, 4, zero) != 0)
        return 3;
    for (i = 0; i < 10; i++) {
        ax[i] = (int)i;
        ay[i] = (int)i * 2;
        az[i] = ax[i] + ay[i];
        lx[i] = (long)az[i] * 1000;
    }
    for (i = 0; i < 10; i++) {
        s += az[i];
        sl += lx[i];
    }
    if (s != 135 || sl != 135000L)
        return 4;
    return 0;
}
