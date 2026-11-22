/* arr_struct.c - arrays of arrays of structures: initialised, read, written, sizes. */
struct cell { unsigned char kind; int value; };

static struct cell grid[3][4] = {
    { {1, 10}, {2, 20} },
    { {3, 30}, {4, 40}, {5, 50}, {6, 60} },
    [2][3] = {9, 99},
};

static int sum(struct cell (*g)[4], int rows)
{
    int r, c, s = 0;
    for (r = 0; r < rows; r++)
        for (c = 0; c < 4; c++)
            s += g[r][c].value;
    return s;
}

int main(void)
{
    struct cell local[2][2] = { { {1, 1}, {2, 2} }, { {3, 3} } };
    if (sizeof grid != 3 * 4 * 3 || sizeof grid[0] != 12 || sizeof grid[0][0] != 3)
        return 1;
    if (grid[0][1].value != 20 || grid[1][3].kind != 6 || grid[2][3].value != 99 ||
        grid[0][3].value != 0)
        return 2;
    if (sum(grid, 3) != 10 + 20 + 30 + 40 + 50 + 60 + 99)
        return 3;
    grid[2][0] = grid[1][2];
    grid[2][0].value++;
    if (grid[2][0].kind != 5 || grid[2][0].value != 51)
        return 4;
    if (local[1][0].value != 3 || local[1][1].kind != 0 || sum(local, 0) != 0)
        return 5;
    {
        struct cell *p = &grid[1][0];
        p += 5;                     /* grid[2][1] */
        p->value = -5;
        if (grid[2][1].value != -5)
            return 6;
    }
    return 0;
}
