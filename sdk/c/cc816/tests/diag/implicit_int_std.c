/* -std=c89 turns on -fimplicit-int and -fextra-args; -Wno-implicit-int silences it */
// FLAGS: -std=c89 -Wno-implicit-int
int f(int a);
main()
{
    return f(1, 2);     // EXPECT: warning: too many arguments to the function 'f': 2 given, it takes 1 (the extra ones are evaluated and pushed, never read) [-Wextra-args]
}
int f(int a) { return a; }
