/* pointers of different types, and const thrown away */
void put(char *s) { (void)s; }
int main(void)
{
    int n = 0;
    long *lp = &n;              // EXPECT: warning: initialising long * with int *: incompatible pointer types
    const char *msg = "hi";
    char *w = msg;              // EXPECT: warning: initialising char * with const char * discards the 'const' qualifier
    put(msg);                   // EXPECT: warning: passing argument 1 of 'put' discards the 'const' qualifier
    void *v = lp;
    int *ip = v;
    return (int)(lp != 0) + (w != 0) + (*ip);
}
