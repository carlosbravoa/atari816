/* -fimplicit-int (and -std=c89, -fdos-keywords): C89's implicit int is a warning, not an
 * error; a function only declared without a type ('static g();') was taken before and
 * says nothing */
// FLAGS: -fimplicit-int
static g();
twice(a)            // EXPECT: warning: type defaults to 'int' in the definition of 'twice' (C89's implicit int)
int a;
{
    register r = a; // EXPECT: warning: type defaults to 'int' in the declaration of 'r'
    return r * 2 + g();
}
static g() { return 1; }    // EXPECT: warning: type defaults to 'int' in the definition of 'g'
static n;           // EXPECT: warning: type defaults to 'int' in the declaration of 'n'
int main(void) { return twice(n); }
