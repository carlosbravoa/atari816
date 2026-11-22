/* int64_t (stdint.h has no 64-bit types) */
#include <stdint.h>
int64_t counter;            // EXPECT: error: unknown type name 'int64_t': cc816 does not support 64-bit integers
int main(void) { return 0; }
