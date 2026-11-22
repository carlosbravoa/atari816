/* a far pointer cast to a near one: with -Wall a warning (the bank is lost) */
// FLAGS: -Wall
#include <horizon.h>
int main(void)
{
    unsigned char __far *f = hz_far_alloc();
    char *n = (char *)f;        // EXPECT: warning: a cast of a far pointer (unsigned char __far *) to a near one (char *): only its offset is kept
    return n != 0;
}
