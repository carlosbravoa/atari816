/* '*' of what is not a pointer, and through a void pointer */
int main(void)
{
    int n = 1;
    void *vp = &n;
    n = *n;             // EXPECT: error: '*' needs a pointer, not int
    n = *vp;            // EXPECT: error: a 'void' value is read
    return n;
}
