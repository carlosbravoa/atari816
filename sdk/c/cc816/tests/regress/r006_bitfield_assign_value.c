/* r006_bitfield_assign_value.c - the value of an assignment (= and the compound ones) to a
 * bit-field must be the value stored, converted to the field's width; cc816 gives the
 * right-hand side unconverted (here 0x1F7 / 0x1FA instead of 0x17 / 0x1A; a signed field
 * gives 31 instead of -1). The field itself is stored right; ++ and -- give the right
 * value. Found by genfuzz --features bitfield. */
struct B { unsigned f : 5; signed s : 5; };
static struct B g = { 3, 0 };

int main(void)
{
    volatile unsigned k = 0x1F7;
    unsigned v = (g.f = k);              /* 0x17 */
    unsigned w = (g.f += 0x1E3);         /* 0x17 + 0x1E3 = 0x1FA -> 0x1A */
    int x = (g.s = 31);                  /* -1 */
    if (g.f != 0x1A || g.s != -1)
        return 1;                        /* (the store is right) */
    return (v == 0x17 && w == 0x1A && x == -1) ? 0 : 2;
}
