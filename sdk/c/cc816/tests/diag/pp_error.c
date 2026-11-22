/* #error stops the build, and every #error is reported */
#ifndef CONFIG
#error "CONFIG is not set"      // EXPECT: error: #error "CONFIG is not set"
#endif
#error second one               // EXPECT: error: #error second one
int main(void) { return 0; }
