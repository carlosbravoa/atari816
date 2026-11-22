/* r024_static_compound_literal.c - a static structure (or an element of a static array)
 * given a compound literal of its own type, struct S g = (struct S){1, 2}, was refused
 * ("not a constant"); GNU C takes the literal's list. Found by the c-testsuite
 * (00216.c). */
struct S { unsigned char a, b; unsigned char c[2]; };
struct W { void *f; };
static int n;
static void bump(void) { n++; }

struct S gs = ((struct S){1, 2, 3, 4});
struct W tab[] = { ((struct W){ bump }), { bump } };

int main(void)
{
    if (gs.a != 1 || gs.b != 2 || gs.c[0] != 3 || gs.c[1] != 4)
        return 1;
    ((void (*)(void))tab[0].f)();
    ((void (*)(void))tab[1].f)();
    return n == 2 ? 0 : 2;
}
