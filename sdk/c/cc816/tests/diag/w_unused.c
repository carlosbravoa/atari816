/* an unused variable: only with -Wall */
// FLAGS: -Wall
int main(void)
{
    int used = 1, unused = 2;       // EXPECT: warning: unused variable 'unused'
    static int s_unused;            // EXPECT: warning: unused variable 's_unused'
    return used;
}
