/* structures cannot be compared with == (compare the members, or memcmp) */
struct p { int x, y; };
int main(void)
{
    struct p a = {1, 2}, b = {1, 2};
    if (a == b)         // EXPECT: error: invalid operands to == (struct p and struct p)
        return 1;
    return a.x < b;     // EXPECT: error: invalid operands to < (int and struct p)
}
