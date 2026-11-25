/* r054_implicit_int.c - C89's implicit int (-std=c89; also -fimplicit-int, -fdos-keywords):
 * functions defined and declared without a return type, K&R parameter lists with and
 * without declarations, 'register x;', 'static n;', 'const k = 5;', a call before any
 * declaration (an implicit one). SimCity's source had 248 such functions, a large DOS
 * strategy game's several; before, each was an error ("has no return type"). Warnings only
 * (-Wimplicit-int); the code is what 'int' would give. LEVELS: 0 1 2 */
// FLAGS: -std=c89 -Wno-implicit-int -Wno-implicit-function-declaration
static bar();
extern baz();
static n;
const k = 5;
unsigned u0 = 40000;

twice(a)
int a;
{
    return a * 2;
}

static sum3(a, b, c)            /* b and c undeclared: int */
char *a;
{
    register r;
    register unsigned ru = 65535;
    r = *a + b + c;
    return r + (ru == 65535u ? 0 : 100);
}

static bar() { return -3; }

baz() { n++; return n; }

frame(void) { return later(7L); }

later(x) long x; { return (int)(x * 3); }

main()
{
    auto t = 9;
    if (twice(21) != 42) return 1;
    if (sum3("A", 2, 3) != 'A' + 5) return 2;
    if (bar() != -3) return 3;
    if (baz() != 1 || baz() != 2) return 4;
    if (k + t != 14) return 5;
    if (u0 != 40000u) return 6;
    if (sizeof(twice(1)) != sizeof(int)) return 7;
    if (frame() != 21) return 8;
    return 0;
}
