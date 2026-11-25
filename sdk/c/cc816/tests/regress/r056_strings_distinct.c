/* r056_strings_distinct.c - -fno-merge-strings: each string literal an object of its own,
 * as DOS's compilers made them (a DOS game's MESSAGE.C wrote into five equal literals as
 * five buffers; cc816, as gcc, merged them into one). By default equal literals in a file
 * are one object (r056 without the option: one address). LEVELS: 0 1 2 */
// FLAGS: -fno-merge-strings
#include <string.h>

static char *v[] = { "    ", "    ", "    " };

static char *name(void) { return "Land"; }

int main(void)
{
    char *a = "same", *b = "same";
    if (v[0] == v[1] || v[1] == v[2] || v[0] == v[2]) return 1;
    if (a == b) return 2;
    strcpy(v[0], "ab");
    strcpy(v[1], "cd");
    if (strcmp(v[0], "ab") || strcmp(v[1], "cd") || strcmp(v[2], "    ")) return 3;
    if (name() != name() || strcmp(name(), "Land")) return 4;   /* one literal: one object */
    return 0;
}
