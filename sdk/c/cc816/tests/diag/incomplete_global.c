/* a global of a structure never defined: found at the end of the file */
struct never;
struct never g;         // EXPECT: error: storage size of 'g' is not known
int main(void) { return 0; }
