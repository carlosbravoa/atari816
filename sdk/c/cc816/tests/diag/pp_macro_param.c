/* a macro definition with a parameter without a name */
#define ADD(x, ) ((x) + 1)      // EXPECT: error: a macro parameter without a name
int main(void) { return 0; }
