/* an #if without its #endif */
#if 1                           // EXPECT: error: this #if has no #endif
int main(void) { return 0; }
