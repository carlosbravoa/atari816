/* GNU asm operand lists */
int main(void)
{
    int x = 1, y;
    __asm__ volatile ("lda %1" : "=r"(y) : "r"(x));    // EXPECT: error: cc816 does not support GNU asm operands (the ': output : input : clobbers' lists): name C variables in the text with %[name] instead
    return y;
}
