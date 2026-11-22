/* a member through a pointer to an incomplete structure */
struct opaque;
int get(struct opaque *p)
{
    return p->field;    // EXPECT: error: a member ('field') of an incomplete type: struct opaque is declared but not defined here
}
int main(void) { return 0; }
