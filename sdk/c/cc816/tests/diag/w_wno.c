/* -Wno-NAME turns one warning off */
// FLAGS: -Wno-implicit-function-declaration
int main(void)
{
    char *p = 5;                // EXPECT: warning: initialising char * with int makes a pointer
    return undeclared_fn(1);
}
