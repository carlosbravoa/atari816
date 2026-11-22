/* a case value twice, two defaults */
int main(void)
{
    int x = 2;
    switch (x) {
    case 1: x = 5; break;
    case 2: x = 6; break;
    case 1: x = 7; break;       // EXPECT: error: duplicate case value 1 (also at line 6)
    default: break;
    default: break;             // EXPECT: error: multiple default labels in one switch
    }
    return x;
}
