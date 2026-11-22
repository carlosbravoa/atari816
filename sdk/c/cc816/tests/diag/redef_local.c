/* two variables of one name in one block */
int main(void)
{
    int a = 1;
    long a = 2;         // EXPECT: error: redefinition of 'a'
    return 0;
}
