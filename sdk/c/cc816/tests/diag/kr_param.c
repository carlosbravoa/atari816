/* an old-style definition that declares a parameter it does not have */
int f(a, b)
int a;
int c;                  // EXPECT: error: declaration for parameter 'c' but no such parameter
{
    return a + b;
}
int main(void) { return 0; }
