/* r019_init_override.c - an initialiser given again for the same member: a later
 * brace list replaces the whole member (.a = {1, 2}, .a = {3}: a is {3, 0}, as gcc does),
 * and a later 0 replaces an earlier value (.x = 5, .x = 0: x is 0; cc816 skipped the 0,
 * the object being zeroed first). Found by the random programs (genfeat.py init). */
struct s { int a[2]; int x; char name[4]; };

static struct s g = { .a = { 1, 2 }, .x = 5, .a = { 3 }, .x = 0, .name = "abc", .name = "d" };

int main(void)
{
    struct s l = { .a = { 1, 2 }, .x = 5, .a = { 3 }, .x = 0, .name = "abc", .name = "d" };
    if (g.a[0] != 3 || g.a[1] != 0 || g.x != 0 || g.name[0] != 'd' || g.name[1] != 0 ||
        g.name[2] != 0)
        return 1;
    if (l.a[0] != 3 || l.a[1] != 0 || l.x != 0 || l.name[0] != 'd' || l.name[1] != 0 ||
        l.name[2] != 0)
        return 2;
    return 0;
}
