/* -w -Wno-overflow: no warning at all */
// FLAGS: -w -Wno-overflow
enum { T = 10000 };
int main(void)
{
    int x = 70000L;
    return 4 * T + x + undeclared_fn();
}
