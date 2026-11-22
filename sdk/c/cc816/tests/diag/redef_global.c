/* a global defined twice */
int score = 1;
int score = 2;          // EXPECT: error: redefinition of 'score' (declared at line 2)
int main(void) { return score; }
