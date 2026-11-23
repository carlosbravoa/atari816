/* -Wsequence-args is not part of -Wall (it would flag every printf of two calls) */
// FLAGS: -Wall
int a(void), b(void);
void f(int, int);
int main(void)
{
    f(a(), b());
    return 0;
}
