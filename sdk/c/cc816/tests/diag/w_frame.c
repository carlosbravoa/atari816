/* a function's software-stack frame over 1 KB: a warning that names the function and the
 * stack's size; a frame bigger than the whole software stack: an error */
struct big { char a[3700]; };

struct big make(void)       // EXPECT: warning: the function 'make' needs a software-stack frame of 3,700 bytes (the software stack is 8,192 bytes
{
    struct big b = { { 0 } };
    return b;
}

int user(void)              // EXPECT: warning: the function 'user' needs a software-stack frame of 7,400 bytes
{
    struct big c = make();
    return c.a[0];
}

int small(void)
{
    char buf[1024];
    buf[0] = 1;
    return buf[0];
}

int huge(void)              // EXPECT: error: the function 'huge' needs a software-stack frame of 9,000 bytes, more than the whole software stack (8,192 bytes): make the big locals static or global, or give hcc --stack 10240
{
    char buf[9000];
    buf[0] = 2;
    return buf[0];
}

int main(void) { return user() + small() + huge(); }
