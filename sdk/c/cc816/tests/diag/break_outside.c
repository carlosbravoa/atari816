/* break and continue outside a loop */
int main(void)
{
    break;              // EXPECT: error: a 'break' not within a loop or a switch
    continue;           // EXPECT: error: a 'continue' not within a loop
    return 0;
}
