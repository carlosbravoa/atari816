/* '.' and '->' on what is not a structure */
struct s { int a; };
int main(void)
{
    int i = 0;
    struct s v, *p = &v;
    i = i.a;            // EXPECT: error: a member ('a') of something that is not a structure or a union (int)
    i = v->a;           // EXPECT: error: '->' needs a pointer to a structure, not struct s (use '.')
    i = p.a;            // EXPECT: error: (use '->' for a pointer)
    return i;
}
