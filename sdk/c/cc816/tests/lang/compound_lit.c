/* compound_lit.c - compound literals: at file scope and in blocks, arrays and
 * structures, their addresses, as arguments, changed. */
struct pt { int x, y; };

static int *gp = (int []){ 1, 2, 3 };
static struct pt *gs = &(struct pt){ 5, 6 };

static int sum(const int *a, int n)
{
    int s = 0;
    while (n--)
        s += *a++;
    return s;
}

static int dist(struct pt p) { return p.x + p.y; }

int main(void)
{
    struct pt p = (struct pt){ .y = 4, .x = 3 };
    int *q = (int [4]){ [3] = 9 };
    char *s = (char []){ "hey" };
    if (gp[2] != 3 || gs->y != 6)
        return 1;
    if (p.x != 3 || p.y != 4 || q[3] != 9 || q[0] != 0 || s[1] != 'e')
        return 2;
    if (sum((int []){ 10, 20, 30 }, 3) != 60 || dist((struct pt){ 1, 2 }) != 3)
        return 3;
    q[0] = 7;
    gp[0] = 8;
    if (q[0] != 7 || gp[0] != 8)
        return 4;
    p = (struct pt){ p.y, p.x };
    if (p.x != 4 || p.y != 3)
        return 5;
    if (((struct pt){ 7, 8 }).y != 8 || (int){ 42 } != 42)
        return 6;
    return 0;
}
