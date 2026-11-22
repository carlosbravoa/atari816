/* calling something that is not a function */
int main(void)
{
    int n = 3;
    return n(2);        // EXPECT: error: 'n' is not a function or a function pointer (its type is int)
}
