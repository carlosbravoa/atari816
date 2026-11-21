/* wc.c - count lines, words and bytes of files, as Unix wc does: a file tool in C.
 *
 *   > wc /README.TXT /LONG.TXT
 *         3      16     110 /README.TXT
 *       ...
 *
 * Shows: path arguments, stdio reading in blocks (fread), errors with strerror, an exit
 * code. Options: -l, -w, -c (only lines, words, bytes). Wildcards are not expanded (the
 * shell passes the words as they are).
 */
#include <stdio.h>
#include <string.h>
#include <errno.h>

static unsigned long tl, tw, tc;
static int show_l = 1, show_w = 1, show_c = 1;

static void out(unsigned long l, unsigned long w, unsigned long c, const char *name)
{
    if (show_l) printf("%8lu", l);
    if (show_w) printf("%8lu", w);
    if (show_c) printf("%8lu", c);
    printf(" %s\n", name);
}

static int count(const char *path)
{
    static unsigned char buf[1024];
    unsigned long l = 0, w = 0, c = 0;
    size_t n, i;
    int inword = 0;
    FILE *f = fopen(path, "r");
    if (!f) {
        printf("wc: %s: %s\n", path, strerror(errno));
        return 1;
    }
    while ((n = fread(buf, 1, sizeof(buf), f)) > 0) {
        c += n;
        for (i = 0; i < n; i++) {
            unsigned char ch = buf[i];
            if (ch == '\n')
                ++l;
            if (ch == ' ' || ch == '\n' || ch == '\t' || ch == '\r') {
                inword = 0;
            } else if (!inword) {
                inword = 1;
                ++w;
            }
        }
    }
    fclose(f);
    out(l, w, c, path);
    tl += l; tw += w; tc += c;
    return 0;
}

int main(int argc, char **argv)
{
    int i, files = 0, bad = 0, opt = 0;
    for (i = 1; i < argc; i++) {
        if (argv[i][0] == '-' && argv[i][1]) {
            if (!opt) { show_l = show_w = show_c = 0; opt = 1; }
            if (strchr(argv[i], 'l')) show_l = 1;
            if (strchr(argv[i], 'w')) show_w = 1;
            if (strchr(argv[i], 'c')) show_c = 1;
        }
    }
    for (i = 1; i < argc; i++) {
        if (argv[i][0] == '-' && argv[i][1])
            continue;
        bad |= count(argv[i]);
        ++files;
    }
    if (!files) {
        printf("usage: wc [-l] [-w] [-c] FILE...\n");
        return 2;
    }
    if (files > 1)
        out(tl, tw, tc, "total");
    return bad;
}
