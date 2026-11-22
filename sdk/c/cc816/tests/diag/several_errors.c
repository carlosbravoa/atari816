/* several errors in one function: all of them are reported */
struct s { int a; };
int f(int a, int b) { return a + b; }
int main(void)
{
    struct s v;
    int *p;
    v.b = 1;            // EXPECT: error: no member named 'b' in struct s
    p = v;              // EXPECT: error: incompatible types when assigning struct s to int *
    f(1);               // EXPECT: error: too few arguments to the function 'f': 1 given, it takes 2
    return q;           // EXPECT: error: 'q' undeclared
}
int g(void) { return zz; }      // EXPECT: error: 'zz' undeclared
