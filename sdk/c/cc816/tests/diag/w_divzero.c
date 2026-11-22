/* a division by a constant 0 */
int main(void)
{
    int x = 5;
    return x / 0;           // EXPECT: warning: division by zero
}
