/* a member twice */
struct s {
    int x;
    long x;             // EXPECT: error: duplicate member 'x'
};
int main(void) { return 0; }
