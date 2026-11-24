/* -fdos-keywords (a DOS program: C89) turns on -fimplicit-int and -fextra-args, unless
 * -fno-implicit-int says otherwise */
// FLAGS: -fdos-keywords -fno-implicit-int
main(void)          // EXPECT: error: the function 'main' has no return type: write 'int main(...)' (C99 has no implicit int; -fimplicit-int or -std=c89 takes C89's)
{
    return 0;
}
