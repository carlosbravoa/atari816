/* an undeclared name is reported once in a function */
int main(void)
{
    int x = 1;
    x = y + 2;      // EXPECT: error: 'y' undeclared (first use in this function)
    x = y + 3;
    return x;
}
