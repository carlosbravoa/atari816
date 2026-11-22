/* a directive the preprocessor does not know */
#frobnicate 1                   // EXPECT: error: unknown preprocessor directive #frobnicate
int main(void) { return 0; }
