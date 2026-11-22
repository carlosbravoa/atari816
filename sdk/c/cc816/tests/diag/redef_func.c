/* a function defined twice */
int twice(void) { return 1; }
int twice(void) { return 2; }       // EXPECT: error: redefinition of 'twice'
int main(void) { return twice(); }
