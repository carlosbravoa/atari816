/* #line: the messages give the line (and file) it says */
int main(void)
{
#line 100 "game.c"
    return nothere;
}
// EXPECT: game.c:100: error: 'nothere' undeclared
