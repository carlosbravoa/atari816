/* case and default outside a switch */
int main(void)
{
    int x = 1;
case 1:                 // EXPECT: error: a 'case' label not within a switch statement
    x = 2;
default:                // EXPECT: error: a 'default' label not within a switch statement
    return x;
}
