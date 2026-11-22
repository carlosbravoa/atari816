/* designators.c - designated initialisers: .a.b = 1, [3] = ..., nested, mixed with
 * positional ones, overriding, static and local. */
struct pt { int x, y; };
struct box { struct pt a, b; int tag; char name[4]; };

static struct box gb = { .b.y = 4, .a = { 1, 2 }, .tag = 7, .name = "ab" };
static int ga[8] = { [3] = 30, 31, [0] = 1, [6] = 60 };
static struct pt gp[4] = { [2].y = 22, [1] = { 11, 12 }, [0].x = 1 };
static struct box gx = { {1, 2}, .b.x = 3, 4, 5, "xyz" };

int main(void)
{
    struct box lb = { .tag = 9, .a.y = -2, .b = { .y = 8 } };
    int la[5] = { [4] = 4, [1] = 1, 2 };
    struct pt lp[3] = { [1].x = 5, [0] = { .y = 6 } };
    int over[3] = { 1, 2, 3, [0] = 9 };
    if (gb.a.x != 1 || gb.a.y != 2 || gb.b.x != 0 || gb.b.y != 4 || gb.tag != 7 ||
        gb.name[1] != 'b' || gb.name[2] != 0)
        return 1;
    if (ga[0] != 1 || ga[3] != 30 || ga[4] != 31 || ga[5] != 0 || ga[6] != 60)
        return 2;
    if (gp[0].x != 1 || gp[1].y != 12 || gp[2].y != 22 || gp[2].x != 0 || gp[3].x != 0)
        return 3;
    if (gx.b.x != 3 || gx.b.y != 4 || gx.tag != 5 || gx.name[2] != 'z')
        return 4;
    if (lb.tag != 9 || lb.a.y != -2 || lb.a.x != 0 || lb.b.y != 8 || lb.b.x != 0)
        return 5;
    if (la[4] != 4 || la[1] != 1 || la[2] != 2 || la[0] != 0 || la[3] != 0)
        return 6;
    if (lp[1].x != 5 || lp[0].y != 6 || lp[0].x != 0 || lp[2].y != 0)
        return 7;
    if (over[0] != 9 || over[1] != 2)
        return 8;
    return 0;
}
