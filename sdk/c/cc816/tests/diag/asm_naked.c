/* a naked function holds asm statements only */
__attribute__((naked)) int one(void)
{
    asm("\tlda #1\n\trts");
}
__attribute__((naked)) int two(void)
{
    return 2;               // EXPECT: error: the naked function 'two' may hold asm statements only
}
int main(void) { return one() + two(); }
