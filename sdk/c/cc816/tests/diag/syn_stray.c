/* a character that is not C */
int main(void)
{
    int a = 1 @ 2;      // EXPECT: error: syntax error
    return a;
}
