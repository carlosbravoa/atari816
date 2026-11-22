/* r035_far_index.c - an element of a __far array of arrays (int __far bd[128][64];
 * bd[x][y]) was reached by a 32-bit address built at every access (the base, plus each
 * index sign-extended to 32 bits and added): the Xargon port's board, read hundreds of
 * times a frame, cost most of its drawing loop. A __far object lies in one bank, so its
 * indexes now add up in 16 bits, in Y ([base],y); an unsigned index through a far pointer
 * does the same (Y carries into the bank as a 32-bit add would); a signed one through a
 * far pointer still takes the 32-bit step (it may be negative). Arrays of arrays in the
 * code bank also add their indexes into one (a[i][j]: abs,x). Found by the Xargon port. */
#include <horizon.h>

int __far bd[128][64];
static __far unsigned char cube[4][5][6];
struct cell { int a; unsigned char b[3]; };
static __far struct cell cells[10][4];
int near2[12][9];

static int sum_row(int x)
{
    int y, s = 0;
    for (y = 0; y < 64; y++)
        s += bd[x][y] & 0x3fff;
    return s;
}

int main(void)
{
    int x, y, z, s;
    unsigned u;
    unsigned char __far *bank;
    int __far *ip;
    struct cell __far *cp;

    for (x = 0; x < 128; x++)
        for (y = 0; y < 64; y++)
            bd[x][y] = (x * 64 + y) | 0x4000;
    for (x = 0; x < 128; x++)
        for (y = 0; y < 64; y++)
            if ((bd[x][y] & 0x3fff) != x * 64 + y)
                return 1;
    if (sum_row(127) != 127 * 64 * 64 + 2016)
        return 2;
    x = 100;
    y = 10;
    bd[x][y - 1] |= 0x8000;             /* (a negative constant offset) */
    if (bd[100][9] != (int)(0x8000 | 0x4000 | (100 * 64 + 9)))
        return 3;
    for (x = 0; x < 4; x++)
        for (y = 0; y < 5; y++)
            for (z = 0; z < 6; z++)
                cube[x][y][z] = (unsigned char)(x * 30 + y * 6 + z);
    s = 0;
    for (x = 0; x < 4; x++)
        for (y = 0; y < 5; y++)
            for (z = 0; z < 6; z++)
                s += cube[x][y][z];
    if (s != 119 * 120 / 2)
        return 4;
    for (x = 0; x < 10; x++)
        for (y = 0; y < 4; y++) {
            cells[x][y].a = x * 4 + y;
            cells[x][y].b[2] = (unsigned char)(x + y);
        }
    if (cells[9][3].a != 39 || cells[7][1].b[2] != 8 || cells[0][0].b[2] != 0)
        return 5;
    for (x = 0; x < 12; x++)
        for (y = 0; y < 9; y++)
            near2[x][y] = x - y;
    if (near2[11][0] != 11 || near2[3][8] != -5)
        return 6;
    /* far pointers: an unsigned index (Y), a signed one, a negative one */
    bank = (unsigned char __far *)hz_far_alloc();
    if (!bank)
        return 7;
    for (u = 0; u < 40000u; u++)
        bank[u] = (unsigned char)(u * 7);
    for (u = 39000u; u < 40000u; u++)
        if (bank[u] != (unsigned char)(u * 7))
            return 8;
    ip = (int __far *)(bank + 20000);
    x = -5;
    if (ip[x] != (int)(bank[19990] | bank[19991] << 8))
        return 9;
    if (ip[-1] != (int)(bank[19998] | bank[19999] << 8))
        return 10;
    u = 3;
    cp = (struct cell __far *)(bank + 1000);
    cp[u].b[1] = 77;
    if (bank[1000 + 3 * sizeof(struct cell) + 3] != 77)
        return 11;
    x = -2;
    if (cp[x].a != (int)(bank[1000 - 2 * (int)sizeof(struct cell)] |
                         bank[1001 - 2 * (int)sizeof(struct cell)] << 8))
        return 12;
    return 0;
}
