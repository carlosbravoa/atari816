/* a non-void function whose end can be reached */
#include <stdlib.h>
int sign(int x)
{
    if (x > 0)
        return 1;
    if (x < 0)
        return -1;
}                           // EXPECT: 9: warning: control reaches the end of the non-void function 'sign'
int forever(void) { for (;;) { } }
int bye(int x) { if (x) return 1; exit(2); }
int all(int x) { switch (x) { case 1: return 1; default: return 2; } }
int main(void) { return sign(1) + bye(1) + all(1); }
