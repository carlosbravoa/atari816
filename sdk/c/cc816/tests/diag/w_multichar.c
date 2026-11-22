/* character constants of more than two characters, extern with a value */
extern int level = 3;           // EXPECT: warning: 'level' is declared extern and given a value
int main(void)
{
    return 'abc' != 0;          // EXPECT: warning: a character constant of more than two characters
}
