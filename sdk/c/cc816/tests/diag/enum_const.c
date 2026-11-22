/* an enumeration constant is not a variable */
enum { LIVES = 3 };
int main(void)
{
    LIVES = 4;          // EXPECT: error: 'LIVES' is an enumeration constant
    return 0;
}
