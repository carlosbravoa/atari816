/* a function without a return type (C89's implicit int) */
main(void)          // EXPECT: error: the function 'main' has no return type: write 'int main(...)'
{
    return 0;
}
