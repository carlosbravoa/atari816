/* -Werror: a warning stops the build */
// FLAGS: -Werror
int main(void)
{
    return undeclared_fn(1);    // EXPECT: error: implicit declaration of the function 'undeclared_fn'
}
