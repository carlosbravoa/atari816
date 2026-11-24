/* r057_writable_strings.c - -fwritable-strings: string literals in the program's data
 * (not its constants) and each one an object of its own (it implies -fno-merge-strings):
 * a DOS program that writes into its literals (strupr("Land") in place). With far data
 * (hcc --data far) they stay in far data, distinct. LEVELS: 0 1 2 */
// FLAGS: -fwritable-strings
#include <string.h>
#include <ctype.h>

static char *upper(char *s)
{
    char *p;
    for (p = s; *p; p++)
        *p = (char)toupper(*p);
    return s;
}

int main(void)
{
    char *a = "Land", *b = "Land";
    if (a == b) return 1;
    upper(a);
    if (strcmp(a, "LAND") || strcmp(b, "Land")) return 2;
    return 0;
}
