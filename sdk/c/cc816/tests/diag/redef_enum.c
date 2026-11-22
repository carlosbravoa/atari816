/* an enumerator that is already a name */
enum colour { RED, GREEN };
enum fruit { APPLE, RED };      // EXPECT: error: redeclaration of 'RED'
int main(void) { return 0; }
