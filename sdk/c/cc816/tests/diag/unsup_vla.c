/* a variable-length array */
int sum(int n)
{
    int a[n];               // EXPECT: error: cc816 does not support variable-length arrays: give the array a constant size, or take the memory from malloc
    a[0] = n;
    return a[0];
}
int main(void) { return sum(3); }
