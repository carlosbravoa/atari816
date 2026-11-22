/* constants that do not fit: int is 16 bits */
int main(void)
{
    int a = 40000L;             // EXPECT: warning: the conversion to int changes the value 40000 to -25536 (int is 16 bits in cc816: use long)
    unsigned char c = 300;      // EXPECT: warning: the conversion to unsigned char changes the value 300 to 44
    unsigned char d = -1;
    int e = 0xFFFF;
    long f = 320 * 200;         // EXPECT: warning: integer overflow in a constant expression: the result 64000 does not fit int (16 bits in cc816
    long g = 320L * 200;
    return a + c + d + e + (int)f + (int)g;
}
