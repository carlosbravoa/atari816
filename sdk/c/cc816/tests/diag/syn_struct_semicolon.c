/* the ';' after a structure's definition missing */
struct point { int x, y; }      // EXPECT: error: two types in one declaration
int main(void) { return 0; }
