/* an array is not assigned with = */
int main(void)
{
    int a[3], b[3];
    a = b;              // EXPECT: error: assignment to an array (int [3])
    return 0;
}
