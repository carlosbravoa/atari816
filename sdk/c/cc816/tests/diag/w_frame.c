/* a function's software-stack frame over 1 KB: a warning that names the function and the
 * stack's size. Compiled alone (cc816, or hcc -c without --stack) the program's stack is
 * not known: the warning names the default (8 KB) and what --stack a bigger frame needs;
 * only a frame past the largest stack (32 KB) is an error. A build that links (hcc -o)
 * or names --stack knows the stack: w_frame_link.c, w_frame_stack.c */
struct big { char a[3700]; };

struct big make(void)       // EXPECT: warning: the function 'make' needs a software-stack frame of 3,700 bytes (the default software stack is 8,192 bytes; the program's is what its link says, hcc --stack N; arrays
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

int huge(void)              // EXPECT: warning: the function 'huge' needs a software-stack frame of 9,000 bytes (the default software stack is 8,192 bytes; the program's is what its link says, hcc --stack N: at least 10240;
{
    char buf[9000];
    buf[0] = 2;
    return buf[0];
}

int giant(void)             // EXPECT: error: the function 'giant' needs a software-stack frame of 40,000 bytes, more than the largest software stack (32,768 bytes, hcc --stack)
{
    char buf[40000];
    buf[0] = 3;
    return buf[0];
}

int main(void) { return user() + small() + huge() + giant(); }
