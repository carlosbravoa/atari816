/* -w silences every warning but -Woverflow: a value that int's 16 bits change (the X-COM
   port's p + 4 * T went 25 KB back with a far pointer) */
// FLAGS: -w
enum { T = 10000 };
unsigned char __far *p;
int main(void)
{
    unsigned short __far *b = (unsigned short __far *)(p + 4 * T);  // EXPECT: warning: integer overflow in a constant expression: the result 40000 does not fit int
    int x = 70000L;                                                 // EXPECT: warning: the conversion to int changes the value 70000
    long y;
    if (y = 2)
        undeclared_fn();
    return (int)b + x;
}
