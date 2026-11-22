/* operators on operands they do not take */
struct s { int a; };
int main(void)
{
    struct s v;
    int *p = 0, *q = 0, i = 1;
    i = v + 1;          // EXPECT: error: invalid operands to + (struct s and int)
    p = p + q;          // EXPECT: error: adding two pointers
    p = 1 - q;          // EXPECT: error: an integer minus a pointer
    i = p * 2;          // EXPECT: error: invalid operands to *
    return i;
}
