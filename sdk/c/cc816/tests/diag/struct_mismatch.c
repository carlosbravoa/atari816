/* structures of different types, and a structure given to an int */
struct a { int x; };
struct b { int x; };
int main(void)
{
    struct a va;
    struct b vb;
    int i;
    va = vb;            // EXPECT: error: incompatible types when assigning struct b to struct a
    i = va;             // EXPECT: error: incompatible types when assigning struct a to int
    return i;
}
