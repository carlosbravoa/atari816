/* with -fsigned-char a char holds -1: no warning */
// FLAGS: -fsigned-char
#include <stdio.h>
int main(void)
{
    char c;
    int n = 0;
    while ((c = getchar()) != EOF)
        n++;
    if (c > 200)        // EXPECT: warning: comparison is always false: 'c' is char, -128 to 127
        n = 0;
    return n;
}
