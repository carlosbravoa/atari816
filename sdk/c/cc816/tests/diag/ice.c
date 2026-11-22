/* an internal compiler error (made on purpose by a test pragma): a plain message with
 * the function's name, no traceback */
int main(void)
{
#pragma cc816 internal_error_test
    return 0;
}
// EXPECT: internal compiler error: in function main
