/* a far pointer given to a near one: the bank is lost */
#include <horizon.h>
int main(void)
{
    unsigned char __far *f = hz_far_alloc();
    unsigned char *n;
    n = f;                  // EXPECT: warning: assigning unsigned char __far * to unsigned char *: a far pointer given to a near one loses its bank
    n = (unsigned char *)f;
    return n != 0;
}
