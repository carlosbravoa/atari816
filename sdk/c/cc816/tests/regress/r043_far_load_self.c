/* r043_far_load_self.c - p = p->next with a far p: the register allocator gives the loaded
 * value p's own register, and the 4-byte load stored the low word before it read the high
 * one through the half-changed pointer (a crash: Horizon ended the program reading bank
 * $E5). The words are now all read first. Found by the random programs in the far data
 * model (a linked list of structures walked through far pointers). */
#include <horizon.h>

struct gt { const char __far *name; int v; struct gt __far *next; };

static unsigned long walk(struct gt __far *p, int n)
{
    unsigned long h = 0;
    const char __far *s;
    while (p && n-- > 0) {
        for (s = p->name; *s; s++)
            h = h * 31u + (unsigned char)*s;
        h = h * 31u + (unsigned)p->v;
        p = p->next;
    }
    return h;
}

int main(void)
{
    struct gt __far *b = (struct gt __far *)hz_far_alloc();
    char __far *names = (char __far *)b + 1000;
    unsigned long h;
    if (!b)
        return 1;
    names[0] = 'a'; names[1] = 0;
    names[2] = 'b'; names[3] = 'c'; names[4] = 0;
    b[0].name = names;     b[0].v = 1; b[0].next = &b[1];
    b[1].name = names + 2; b[1].v = 2; b[1].next = &b[2];
    b[2].name = names + 1; b[2].v = 3; b[2].next = 0;
    h = walk(b, 5);
    /* (the same computed on the host) */
    if (h != ((((97UL * 31 + 1) * 31 + 98) * 31 + 99) * 31 + 2) * 31 + 3)
        return 2;
    hz_far_free(b);
    return 0;
}
