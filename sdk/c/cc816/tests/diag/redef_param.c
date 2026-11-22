/* a local with the name of a parameter, in the function's outer block */
int f(int n)
{
    int n = 2;          // EXPECT: error: redefinition of 'n' (a parameter
    return n;
}
int main(void) { return f(1); }
