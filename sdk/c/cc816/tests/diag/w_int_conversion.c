/* integers and pointers mixed without a cast */
char *name(int n) { return n ? "a" : 0; }
int len(const char *s) { return s ? 1 : 0; }
int main(void)
{
    char *p = 1234;         // EXPECT: warning: initialising char * with int makes a pointer from an integer without a cast
    int i = p;              // EXPECT: warning: initialising int with char * makes an integer from a pointer without a cast
    char *q = 0;
    p = i;                  // EXPECT: warning: assigning int to char * makes a pointer from an integer without a cast
    i += len(5);            // EXPECT: warning: passing argument 1 of 'len' makes a pointer from an integer without a cast
    if (p == 5)             // EXPECT: warning: comparison between a pointer and an integer
        return 1;
    return i + (q == 0);
}
int back(void) { char *s = "x"; return s; }     // EXPECT: warning: returning char * from a function that returns int makes an integer from a pointer
