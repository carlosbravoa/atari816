/* an error in an included header is reported at the header's line */
#include "diag_bad.h"
int main(void) { return helper(); }
// EXPECT: diag_bad.h:4: error: 'undefined_in_header' undeclared
