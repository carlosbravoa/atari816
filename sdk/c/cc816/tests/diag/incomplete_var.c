/* a variable of a structure that is declared but not defined */
struct later;
int main(void)
{
    struct later x;     // EXPECT: error: storage size of 'x' is not known (struct later is declared but not defined)
    return 0;
}
