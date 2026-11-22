/* r015_pp_div_paste.c - the preprocessor: #if computed -7 / 2 and -7 % 3 as Python does
 * (-4 and 2, not C's -3 and -1); A ## B with B empty pasted A to the token after B
 * (60 Q(+,)3 became 60 ++3); two tokens a macro put side by side were read as one
 * (a-X with X -1 became a--1); #line was ignored. Found by the c-testsuite (00202.c,
 * 00152.c). */
#define Q(A, B) A ## B+
#define X -1
#if -7 / 2 != -3 || -7 % 3 != -1 || 7 % -3 != 1
#error "C division in #if"
#endif

int main(void)
{
    int a = 5;
    int b = 60 Q(+,)3;      /* 60 + +3 */
    int c = a-X;            /* a - -1 */
    if (b != 63 || c != 6)
        return 1;
#line 1000
    if (__LINE__ != 1000)
        return 2;
    return 0;
}
