/* inline assembly */
int main(void)
{
    asm("nop");             // EXPECT: error: cc816 does not support inline assembly (asm): put the code in a .s file
    return 0;
}
