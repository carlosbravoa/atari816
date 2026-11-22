/* a structure defined twice */
struct v { int x; };
struct v { int y; };    // EXPECT: error: redefinition of 'struct v'
int main(void) { return 0; }
