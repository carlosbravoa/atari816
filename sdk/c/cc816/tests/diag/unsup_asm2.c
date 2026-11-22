/* GNU inline assembly */
int main(void)
{
    __asm__ volatile ("sei");   // EXPECT: error: cc816 does not support inline assembly
    return 0;
}
