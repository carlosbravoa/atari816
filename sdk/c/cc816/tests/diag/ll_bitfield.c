/* long long: bit-fields of it are not supported; a constant too big for 64 bits */
struct s { long long f : 40; };     // EXPECT: error: cc816 does not support a long long bit-field ('f'): declare it long or unsigned long (up to 32 bits)
unsigned long long big = 18446744073709551616;   // EXPECT: error: the integer constant 18446744073709551616 is too large for 64 bits
int main(void) { return 0; }
