/* comparisons decided by the type at its edges: with -Wall */
// FLAGS: -Wall
int main(void)
{
    unsigned u = 3;
    int x = 1;
    if (u >= 0)         // EXPECT: warning: comparison is always true: 'u' is unsigned int, 0 to 65535
        x++;
    if (x <= 32767)     // EXPECT: warning: comparison is always true: 'x' is int, -32768 to 32767
        x++;
    return x;
}
