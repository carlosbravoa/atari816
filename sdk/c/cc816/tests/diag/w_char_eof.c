/* plain char is unsigned in cc816: a char never equals EOF (-1) */
#include <stdio.h>
int main(void)
{
    char c;
    int n = 0;
    while ((c = getchar()) != EOF)      // EXPECT: warning: comparison is always true: the value is char, 0 to 255 (plain char is unsigned in cc816
        n++;
    if (c < 0)                          // EXPECT: warning: comparison is always false: 'c' is char, 0 to 255
        n = 0;
    return n;
}
