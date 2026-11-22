/* long long */
int main(void)
{
    long long big = 1;      // EXPECT: error: cc816 does not support long long (64-bit integers): long is 32 bits
    return (int)big;
}
