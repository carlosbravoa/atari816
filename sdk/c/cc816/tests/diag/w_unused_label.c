/* an unused label: only with -Wall */
// FLAGS: -Wall
int main(void)
{
    int i = 0;
spare:                  // EXPECT: warning: label 'spare' defined but not used
    i++;
    return i;
}
