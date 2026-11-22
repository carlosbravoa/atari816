/* an undeclared name in an array's size is reported as undeclared (not as a variable-length
 * array): found by the Xargon port (a header used without the one defining the size) */
extern int table[numkinds];     // EXPECT: error: 'numkinds' undeclared
int main(void) { return 0; }
