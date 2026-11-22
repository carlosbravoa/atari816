/* subtracting pointers to different types */
int main(void)
{
    int a[4];
    char c[4];
    return (int)(&a[2] - &c[1]);    // EXPECT: error: subtracting pointers to different types (int * and char *)
}
