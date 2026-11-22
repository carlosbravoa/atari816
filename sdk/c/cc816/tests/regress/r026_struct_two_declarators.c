/* r026_struct_two_declarators.c - a structure, union or enum defined in a declaration
 * with more than one declarator, static struct bag {...} a[7], b[7];, was refused:
 * "redefinition of 'struct bag'" and then "'b' undeclared" (the declarators share one
 * definition, which was read once for each). An anonymous one gave each declarator a
 * type of its own, so a = b was refused. Found by the Digger port (bags.c). */
static struct bag { int x; char c; } bagdat1[7], bagdat2[7], bagdat[7];
struct { int y; long z; } p, q;
union u { int i; unsigned char b[2]; } u1, u2;
enum col { RED = 3, GREEN } c1, c2;

int main(void)
{
    struct pt { int x, y; } s = {1, 2}, t;
    enum { A = 5, B } e1 = B, e2;
    t = s;
    if (t.x + t.y != 3)
        return 1;
    bagdat[3].x = 7;
    bagdat2[0] = bagdat[3];
    bagdat1[6] = bagdat2[0];
    if (bagdat1[6].x != 7 || sizeof bagdat2 != 21)
        return 2;
    p.y = 5;
    p.z = 70000;
    q = p;
    if (q.y != 5 || q.z != 70000)
        return 3;
    u1.i = 0x1234;
    u2 = u1;
    if (u2.b[0] != 0x34)
        return 4;
    c1 = GREEN;
    c2 = RED;
    e2 = A;
    if (c1 != 4 || c2 != 3 || e1 != 6 || e2 != 5)
        return 5;
    return 0;
}
