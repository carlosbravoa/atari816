/* _Static_assert */
_Static_assert(sizeof(int) == 2, "int is 16 bits");
_Static_assert(sizeof(long) == 8, "long is 64 bits");   // EXPECT: error: static assertion failed: "long is 64 bits"
int main(void)
{
    _Static_assert(1 + 1 == 3, "arithmetic");            // EXPECT: error: static assertion failed: "arithmetic"
    return 0;
}
