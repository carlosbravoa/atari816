/* 128-bit integers */
int main(void)
{
    __int128 big = 1;       // EXPECT: error: cc816 does not support 128-bit integers (__int128): long long is 64 bits
    return (int)big;
}
