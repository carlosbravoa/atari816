/* int is 16 bits: an int compared with a value it cannot hold */
int main(void)
{
    int x = 1000;
    unsigned u = 5;
    if (x > 40000)          // EXPECT: warning: comparison is always false: 'x' is int, -32768 to 32767 (int is 16 bits in cc816)
        return 1;
    if (u < 70000L)         // EXPECT: warning: comparison is always true: 'u' is unsigned int, 0 to 65535
        x++;
    if (x <= 32767)         /* (an edge: only with -Wall) */
        x++;
    return x;
}
