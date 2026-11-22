/* -w: no warnings */
// FLAGS: -w
int main(void)
{
    char *p = 5;
    return undeclared_fn(p);
}
