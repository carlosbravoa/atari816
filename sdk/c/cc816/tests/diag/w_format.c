/* printf and scanf formats against the arguments: int is 16 bits, long 32 */
#include <stdio.h>
int main(void)
{
    long big = 100000L;
    int n = 3;
    char name[8];
    printf("%d\n", big);            // EXPECT: warning: printf: '%d' takes an int (16 bits in cc816; use %ld for a long), but argument 2 is long
    printf("%ld\n", n);             // EXPECT: warning: printf: '%ld' takes a long (32 bits; use %d for an int), but argument 2 is int
    printf("%s\n", n);              // EXPECT: warning: printf: '%s' takes a char * (a string), but argument 2 is int
    printf("%f\n", n);              // EXPECT: warning: printf: '%f' takes a double (or a float), but argument 2 is int
    printf("%d %d\n", n);           // EXPECT: warning: printf: too few arguments for the format
    printf("%d\n", n, n);           // EXPECT: warning: printf: too many arguments for the format
    scanf("%d", n);                 // EXPECT: warning: scanf: '%d' takes a pointer (&variable), but argument 2 is int
    scanf("%d", &big);              // EXPECT: warning: scanf: '%d' takes an int * (16 bits), but argument 2 is long *
    scanf("%7s %ld %5.2f", name, &big, &n);   // EXPECT: warning: scanf: an unfinished conversion
    printf("%u %x %c %5.1f %p %%\n", 1u, n, 'a', 2.5, name);
    return 0;
}
