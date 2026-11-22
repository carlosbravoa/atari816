/* r007_far_struct_copy.c - a structure assignment through __far pointers copies in the
 * wrong bank: cc816 emits the block move (MVN) with the code bank in both operands
 * (mvn #^_f, #^_f) instead of the pointers' banks, so p[1] = p[0] in a bank from
 * hz_far_alloc reads and writes the program's own bank. The same for near <- far,
 * far <- near, a far structure passed by value (g(p[0])) and a returned structure
 * stored through a far pointer (p[3] = mk(7)). Found by genfuzz --features far
 * (fs[1] = fs[0]). */
#include <horizon.h>

struct S { int a; char b; long c; unsigned d; };

static long g(struct S s) { return s.a + s.c; }
static struct S mk(int k) { struct S s; s.a = k; s.b = 0; s.c = k * 100000L; s.d = 0; return s; }

int main(void)
{
    struct S __far *p = hz_far_alloc();
    struct S l;
    int r = 0;
    if (!p)
        return 9;
    p[0].a = 1; p[0].b = 2; p[0].c = 70000L; p[0].d = 4;
    p[1].a = 0; p[1].b = 0; p[1].c = 0; p[1].d = 0;
    p[1] = p[0];                                     /* far <- far */
    if (!(p[1].a == 1 && p[1].b == 2 && p[1].c == 70000L && p[1].d == 4))
        r |= 1;
    l = p[0];                                        /* near <- far */
    if (!(l.a == 1 && l.c == 70000L && l.d == 4))
        r |= 2;
    l.c = 5;
    p[2] = l;                                        /* far <- near */
    if (!(p[2].a == 1 && p[2].c == 5 && p[2].d == 4))
        r |= 4;
    if (g(p[0]) != 70001L)                           /* by value from far */
        r |= 8;
    p[3] = mk(7);                                    /* returned, into far */
    if (!(p[3].a == 7 && p[3].c == 700000L))
        r |= 16;
    hz_far_free(p);
    return r;
}
