/* what an asm statement can name with %[name] */
int g;
int main(void)
{
    int a[4], x = 0, *p = a;
    asm("\tlda %[a]");      // EXPECT: error: %[a]: 'a' is an array, kept on the software stack, which one operand cannot reach: take its address in a pointer variable ('p = a;') and use (%[p]),y
    asm("\tlda %[nope]");   // EXPECT: error: 'nope' undeclared (named in an asm statement as %[nope])
    asm("\tlda %[g]\n\tsta %[x]\n\tlda (%[p]),y");
    return x;
}
asm("\tlda %[g]");
asm("\tlda %[main]");
