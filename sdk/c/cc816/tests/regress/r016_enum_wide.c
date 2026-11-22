/* r016_enum_wide.c - an enumeration constant of 32768 or more was an int: 40000 became
 * -25536 when widened to a long, and 100000 lost its high word. An enumerator's type now
 * holds its value (unsigned int, long). */
enum { BIG = 40000u, HUGE = 100000L, NEG = -2 };

int main(void)
{
    long a = BIG, b = HUGE, c = NEG;
    if (a != 40000L || b != 100000L || c != -2L)
        return 1;
    if (BIG < 0 || HUGE / 10 != 10000L)
        return 2;
    return 0;
}
