/* r023_union_designators.c - a union initialised with two designators into its anonymous
 * structure ({.b = 8, .a = 7}) kept the first only and warned of excess elements: after
 * a designator the union took no more. Designators after it now choose again (GNU C and
 * C11 do so). Found by the c-testsuite (00216.c). */
typedef unsigned char u8;
union UV {
    struct { u8 a, b; };
    unsigned w;
};
union UV g = { .b = 8, .a = 7 };

int main(void)
{
    union UV l = { .b = 2, .a = 1 };
    if (g.a != 7 || g.b != 8 || g.w != 0x0807)
        return 1;
    if (l.a != 1 || l.b != 2)
        return 2;
    return 0;
}
