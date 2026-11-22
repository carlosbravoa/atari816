/* setjmp.h */
#include <setjmp.h>
int main(void) { return 0; }
// EXPECT: setjmp.h:*: error: cc816 does not support setjmp and longjmp
