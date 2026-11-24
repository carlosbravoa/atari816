/* hcc -o without --stack: the program links with the default stack (8 KB), so a frame
 * bigger than that is an error at the compile (w_frame.c: compiled alone, a warning) */
// HCC: -o X.PRG
// EXPECT-HCC: error: the function 'f' needs a software-stack frame of 9,000 bytes, more than the whole software stack (8,192 bytes): make the big locals static or global, or give hcc --stack 10240
int f(void)
{
    char a[9000];
    a[0] = 1;
    return a[0];
}
int main(void) { return f(); }
