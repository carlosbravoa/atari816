/* hcc --stack N: a frame bigger than that stack is an error at the compile */
// HCC: -o X.PRG --stack 4096
// EXPECT-HCC: error: the function 'f' needs a software-stack frame of 5,000 bytes, more than the whole software stack (4,096 bytes)
int f(void)
{
    char a[5000];
    a[0] = 1;
    return a[0];
}
int main(void) { return f(); }
