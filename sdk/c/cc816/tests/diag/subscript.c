/* [] of what is not an array, and a float index */
int main(void)
{
    int n = 1, a[4];
    float f = 1.0f;
    n = n[2];           // EXPECT: error: a subscript ([]) of something that is not an array or a pointer (int)
    n = a[f];           // EXPECT: error: an array subscript is not an integer (float)
    return n;
}
