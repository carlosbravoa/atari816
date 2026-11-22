/* assigning to what cannot be assigned */
int f(void) { return 1; }
int main(void)
{
    int x = 0;
    3 = x;              // EXPECT: error: lvalue required
    x + 1 = 2;          // EXPECT: error: lvalue required
    return x;
}
