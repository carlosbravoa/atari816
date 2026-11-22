/* a ')' missing */
int main(void)
{
    int x;
    x = (3;         // EXPECT: error: syntax error before ';'
    return x;
}
