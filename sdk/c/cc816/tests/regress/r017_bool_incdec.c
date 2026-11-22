/* r017_bool_incdec.c - ++ of a _Bool made it 2 (it is 1 after ++, and -- flips it).
 * Found by tests/lang/exprs.c. */
#include <stdbool.h>

static bool g;

int main(void)
{
    bool t = false;
    t++;
    t++;
    if (t != 1)
        return 1;
    t--;
    if (t != 0)
        return 2;
    t--;
    if (t != 1)
        return 3;
    g++;
    ++g;
    if (g != 1 || sizeof g != 1)
        return 4;
    return 0;
}
