/* flex.c - a flexible array member, the structure taken from malloc. */
#include <stdlib.h>
#include <string.h>

struct msg { unsigned len; char data[]; };
struct nums { int n; long v[]; };

int main(void)
{
    struct msg *m = malloc(sizeof(struct msg) + 6);
    struct nums *n = malloc(sizeof(struct nums) + 3 * sizeof(long));
    if (!m || !n)
        return 1;
    if (sizeof(struct msg) != 2 || sizeof(struct nums) != 2)
        return 2;
    m->len = 5;
    strcpy(m->data, "hello");
    n->n = 3;
    n->v[0] = 1;
    n->v[2] = 100000L;
    if (m->data[4] != 'o' || strlen(m->data) != 5 || n->v[2] != 100000L)
        return 3;
    if ((char *)&n->v[1] - (char *)n != 2 + 4)
        return 4;
    free(m);
    free(n);
    return 0;
}
