/* return with and without a value in the wrong place */
void none(int x)
{
    return x;           // EXPECT: warning: 'return' with a value in the function 'none', which returns void
}
int some(int x)
{
    if (x)
        return;         // EXPECT: warning: 'return' with no value in the function 'some', which returns int
    return 1;
}
int main(void) { none(1); return some(0); }
