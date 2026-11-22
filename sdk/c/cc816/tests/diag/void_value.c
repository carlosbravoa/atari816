/* the result of a void function used as a value */
void nothing(void) { }
int main(void)
{
    int x = nothing();  // EXPECT: error: a void value is used
    return x;
}
