/* h16lib.c - the definitions of h16old.h, in old C (host16.py's test: h16old.C) */
#include <stdlib.h>
#include <string.h>
#include "h16old.h"

struct box { int w, h; };

static count;                           /* implicit int */

twice(a)                                /* implicit int, K&R */
int a;
{
    return a * 2;
}

scale(v, k)                             /* K&R parameters without a declaration: int */
{
    return v * k;
}

/* declared 'long widen();': a prototype definition with promoted parameters */
long widen(short lo, char hi)
{
    return ((long)hi << 16) | (unsigned short)lo;
}

void fill_pair(int *p, int a, int b)
{
    p[0] = a;
    p[1] = b;
}

int box_area(struct box *b)
{
    return b->w * b->h;
}

int counted(void)
{
    register i;                         /* implicit int */
    for (i = 0; i < 3; i++)
        count++;
    return count + (int)sizeof(count) + (int)sizeof(i) + is_high_code(0);
}
