/* an assignment as a condition: only with -Wall */
// FLAGS: -Wall
int main(void)
{
    int a = 0, b = 1;
    if (a = b)          // EXPECT: warning: an assignment used as a condition
        return 1;
    return 0;
}
