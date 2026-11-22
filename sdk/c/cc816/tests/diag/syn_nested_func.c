/* a function defined inside another (GNU C) */
int main(void)
{
    int inner(int x) { return x; }      // EXPECT: error: nested functions
    return inner(1);
}
