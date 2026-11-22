/* offsetof.c - offsetof as a constant: in an array size, a static initialiser, a case,
 * an enumerator; of nested members and array elements. */
#include <stddef.h>

struct inner { char c; long l; };
struct outer { int a; struct inner in[3]; char tail[5]; };

enum { OFF_TAIL = offsetof(struct outer, tail) };
static char buf[offsetof(struct outer, in[1].l)];
static const unsigned offs[] = { offsetof(struct outer, a), offsetof(struct outer, in),
                                 offsetof(struct outer, in[2].c) };

static int which(unsigned k)
{
    switch (k) {
    case offsetof(struct outer, in[1]): return 1;
    case offsetof(struct outer, tail): return 2;
    }
    return 0;
}

int main(void)
{
    if (OFF_TAIL != 2 + 3 * 5 || sizeof buf != 2 + 5 + 1)
        return 1;
    if (offs[0] != 0 || offs[1] != 2 || offs[2] != 2 + 10)
        return 2;
    if (which(7) != 1 || which(17) != 2 || which(3) != 0)
        return 3;
    return 0;
}
