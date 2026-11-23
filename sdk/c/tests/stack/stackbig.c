/* stackbig.c - the software stack's entry check (cc816: every function with a frame):
 * a big structure returned by value (the SkyRoads port's CarAtlas: its copy in the
 * caller's frame, the local in the callee's) in a 6 KB software stack (hcc --stack 6144).
 * The check stops the program in big_atlas, before its frame reaches the heap, with the
 * function's name; without it the frame went into the heap silently. Prints "survived"
 * only if the check did not fire. */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

struct atlas { char a[2500]; };

static struct atlas big_atlas(unsigned seed)
{
    struct atlas b;
    memset(&b, (int)seed, sizeof b);
    return b;
}

int main(void)
{
    char *heap = malloc(64);
    struct atlas t;
    strcpy(heap, "heap intact");
    printf("calling big_atlas\n");
    t = big_atlas(7);
    printf("survived %d, %s\n", t.a[0], heap);
    return 0;
}
