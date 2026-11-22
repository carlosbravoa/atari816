/* shifts by the width of the type or more */
int main(void)
{
    int x = 1;
    long y;
    x = x << 16;            // EXPECT: warning: shift count (16) is negative or not less than the width of int (16 bits in cc816)
    y = 1 << 20;            // EXPECT: warning: shift count (20) is negative or not less than the width of int
    y = 1L << 20;
    x = 6 >> -1;            // EXPECT: warning: shift count (-1) is negative
    return x + (int)y;
}
