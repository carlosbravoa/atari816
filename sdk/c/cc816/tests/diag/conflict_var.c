/* a variable declared with two types */
extern int lives;
long lives;             // EXPECT: error: conflicting types for 'lives'
int main(void) { return 0; }
