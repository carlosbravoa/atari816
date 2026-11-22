/* a GCC built-in function cc816 does not have */
int main(void)
{
    return __builtin_popcount(7u);      // EXPECT: error: cc816 does not support the GCC built-in function __builtin_popcount
}
