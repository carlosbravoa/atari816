/* -Wno-frame-larger-than: no warning for a big frame */
// FLAGS: -Wno-frame-larger-than
int f(void)
{
    char a[3000];
    a[0] = 1;
    return a[0];
}
int main(void) { return f(); }
