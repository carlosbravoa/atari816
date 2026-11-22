/* an unknown type name (a typedef from a header that was not included) */
int main(void)
{
    uint8_t x = 1;      // EXPECT: error: unknown type name 'uint8_t'
    return x;
}
