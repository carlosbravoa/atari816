/* -Wsequence-args with -fargs-right-to-left says the order used; -Wall alone does not warn */
// FLAGS: -Wsequence-args -fargs-right-to-left
int a(void), b(void);
void f(int, int);
int main(void)
{
    f(a(), b());                        // EXPECT: warning: arguments 1 and 2 of 'f' call functions: C leaves the order unspecified; cc816 evaluates them right to left here (-fargs-right-to-left)
    return 0;
}
