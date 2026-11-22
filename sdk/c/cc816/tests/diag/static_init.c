/* a global initialised with something that is not a constant */
int f(void) { return 3; }
int x = f();            // EXPECT: error: the initialiser is not a constant: a global or static variable takes constants only
int main(void)
{
    int y = 2;
    static int z = y;   // EXPECT: error: the initialiser is not a constant
    return x + z;
}
