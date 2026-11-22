/* an extern inside a function with a value */
int main(void)
{
    extern int g = 3;   // EXPECT: error: 'g' is declared extern inside a function and has a value
    return g;
}
