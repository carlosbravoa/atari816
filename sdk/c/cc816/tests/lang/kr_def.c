/* kr_def.c - old-style (K&R) function definitions: parameters declared after the list,
 * in any order, some left int; char and float parameters (promoted by the caller). */
int add(a, b)
int a, b;
{
    return a + b;
}

long mix(c, l, s, n)
char c;
long l;
char *s;
{                       /* n is not declared: an int */
    return c + l + s[1] + n;
}

double half(x)
float x;
{
    return x / 2;
}

static unsigned char low(v)
unsigned v;
{
    return (unsigned char)v;
}

int old_proto();        /* no prototype: any arguments */

int main(void)
{
    if (add(2, 3) != 5)
        return 1;
    if (mix('A', 100000L, "xy", 7) != 65 + 100000L + 'y' + 7)
        return 2;
    if (half(5.0f) != 2.5)
        return 3;
    if (low(0x1234) != 0x34)
        return 4;
    if (old_proto(1, 2) != 3)
        return 5;
    return 0;
}

int old_proto(a, b)
int a, b;
{
    return a + b;
}
