/* funcptr.c - function pointers: in structures and arrays, called through, given as
 * arguments and returned, typedefs, a pointer to a function returning a function
 * pointer, compared, NULL. */
#include <stddef.h>

typedef int (*binop)(int, int);

static int add(int a, int b) { return a + b; }
static int sub(int a, int b) { return a - b; }
static int mul(int a, int b) { return a * b; }
static long lsum(long a, long b) { return a + b; }

struct op { const char *name; binop f; long (*lf)(long, long); };

static struct op ops[] = { {"add", add, lsum}, {"sub", sub, NULL}, {"mul", &mul, 0} };
static binop table[3] = { add, sub, mul };
static int (*table2[])(int, int) = { mul, add };

static int apply(binop f, int a, int b) { return f(a, b); }
static binop pick(int k) { return k ? sub : add; }
static int (*pick2(int k))(int, int) { return table[k]; }
static binop (*chooser(void))(int) { return pick; }

struct machine { int acc; void (*step)(struct machine *, int); };
static void inc(struct machine *m, int k) { m->acc += k; }

int main(void)
{
    binop f = add;
    struct machine m = { 0, inc };
    int i, s = 0;
    if (f(2, 3) != 5 || (*f)(2, 3) != 5 || (**f)(2, 3) != 5)
        return 1;
    for (i = 0; i < 3; i++)
        s += ops[i].f(10, 2);
    if (s != 12 + 8 + 20)
        return 2;
    if (ops[0].lf(100000L, 1L) != 100001L || ops[1].lf != NULL)
        return 3;
    if (table[2](3, 4) != 12 || table2[1](3, 4) != 7)
        return 4;
    if (apply(sub, 9, 4) != 5 || apply(table[0], 1, 1) != 2)
        return 5;
    if (pick(1)(7, 2) != 5 || pick2(2)(7, 2) != 14 || chooser()(0)(7, 2) != 9)
        return 6;
    if (f != add || f == sub || table[1] != sub || !f)
        return 7;
    m.step(&m, 3);
    (*m.step)(&m, 4);
    if (m.acc != 7)
        return 8;
    f = 0;
    if (f)
        return 9;
    return 0;
}
