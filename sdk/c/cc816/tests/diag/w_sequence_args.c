/* -Wsequence-args (only when named, not in -Wall): two or more arguments of one call that
   call functions (the X-COM port's hurt(roll(), side()), both drawing random numbers) */
// FLAGS: -Wsequence-args
int a(void), b(void), c(int);
void f(int, int, int);
int (*fp)(int, int);
int main(void)
{
    int x = 1;
    f(a(), b(), 3);                     // EXPECT: warning: arguments 1 and 2 of 'f' call functions: C leaves the order unspecified; cc816 evaluates them left to right (DOS's compilers and gcc on x86 right to left: -fargs-right-to-left)
    f(a(), x, c(b()) + 1);              // EXPECT: warning: arguments 1 and 3 of 'f'
    (*fp)(a(), b());                    // EXPECT: warning: arguments 1 and 2 of a call through a pointer
    f(a(), x, (int)sizeof(b()));
    f(x, x + 1, c(2));
    return 0;
}
