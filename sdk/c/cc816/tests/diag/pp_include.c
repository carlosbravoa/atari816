/* an include file that does not exist */
#include "no_such_header.h"     // EXPECT: error: cannot find the include file no_such_header.h
int main(void) { return 0; }
