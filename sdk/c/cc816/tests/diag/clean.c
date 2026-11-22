/* ordinary code says nothing (no false warnings), even with -Wall */
// FLAGS: -Wall
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <horizon.h>

typedef struct { int x, y; unsigned char flags; } sprite;
static sprite sprites[8];
static const char *const names[] = { "one", "two", 0 };
enum mode { M_TITLE, M_PLAY = 5, M_OVER };

static int clamp(int v, int lo, int hi) { return v < lo ? lo : v > hi ? hi : v; }

static void update(sprite *s, int dx)
{
    s->x = clamp(s->x + dx, 0, 319);
    if ((s->flags & 1) != 0 && s->y < 200)
        s->y++;
}

int main(int argc, char **argv)
{
    int i, c;
    long total = 0;
    char buf[32];
    unsigned char b = 255;
    void *mem = malloc(100);
    char *text = mem;
    enum mode m = M_TITLE;
    unsigned char __far *far = hz_far_alloc();
    for (i = 0; i < 8; i++)
        update(&sprites[i], i - 4);
    while ((c = getchar()) != EOF && c != '\n')
        total += c;
    if (b == 255 && m == M_TITLE && names[0] != NULL)
        total++;
    sprintf(buf, "%d %ld %s %u %c", argc, total, argv[0], (unsigned)sizeof buf, 'x');
    strcpy(text, buf);
    if (far) {
        far[1000] = b;
        hz_far_free(far);
    }
    printf("%s %5.2f\n", text, 1.5);
    free(mem);
    return (int)strlen(buf) > 100 ? 1 : 0;
}
