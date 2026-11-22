/* more initialisers than places */
int small[2] = {1, 2, 3};       // EXPECT: warning: excess elements in the array initialiser
char word[3] = "hello";         // EXPECT: warning: the string is longer than the array (5 characters for 3)
int main(void)
{
    int x = {1, 2};             // EXPECT: warning: excess elements in the initialiser of 'x'
    return small[0] + word[0] + x;
}
