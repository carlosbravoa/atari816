/* too many arguments */
int add(int a, int b);
int main(void)
{
    return add(1, 2, 3);    // EXPECT: error: too many arguments to the function 'add': 3 given, it takes 2
}
