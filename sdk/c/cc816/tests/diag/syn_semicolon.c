/* a ';' missing at the end of a line */
int main(void)
{
    int x = 3
    return x;       // EXPECT: error: expected ';' before 'return' (at the end of line 4)
}
