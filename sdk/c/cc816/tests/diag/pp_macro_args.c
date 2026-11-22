/* a macro called with the wrong number of arguments */
#define ADD(a, b) ((a) + (b))
int main(void)
{
    return ADD(1);              // EXPECT: error: the macro ADD takes 2 arguments, not 1
}
