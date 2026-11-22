/* an operand missing */
int f(int a)
{
    return a + ;    // EXPECT: error: syntax error before ';'
}
int main(void) { return f(1); }
