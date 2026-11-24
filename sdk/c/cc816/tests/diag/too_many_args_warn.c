/* -fextra-args: more arguments than the prototype is a warning (Microsoft C's C4020) */
// FLAGS: -fextra-args
int add(int a, int b);
int none(void);
int main(void)
{
    return add(1, 2, 3)     // EXPECT: warning: too many arguments to the function 'add': 3 given, it takes 2
        + none(4);          // EXPECT: warning: too many arguments to the function 'none': 1 given, it takes 0
}
