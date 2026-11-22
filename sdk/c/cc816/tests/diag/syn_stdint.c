/* int64_t without stdint.h */
int64_t counter;            // EXPECT: error: unknown type name 'int64_t' (#include <stdint.h>)
int main(void) { return 0; }
