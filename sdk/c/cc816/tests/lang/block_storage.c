/* block_storage.c - static and extern at block scope; a static local keeps its value;
 * an extern inside a function names the global (also one defined later). */
static int counter(void)
{
    static int n;           /* zero at start */
    static int step = 2;
    n += step;
    return n;
}

int total = 10;

int use_later(void)
{
    extern int later;       /* defined below */
    return later + 1;
}

int main(void)
{
    int total = 1;          /* hides the global */
    counter();
    counter();
    if (counter() != 6)
        return 1;
    {
        extern int total;   /* the global again */
        if (total != 10)
            return 2;
        total = 11;
    }
    if (total != 1)
        return 3;
    {
        static const char msg[] = "abc";
        static const char *p = msg + 1;     /* a static's address: a constant */
        if (sizeof msg != 4 || msg[2] != 'c' || *p != 'b')
            return 4;
    }
    if (use_later() != 43)
        return 5;
    {
        extern int total;
        if (total != 11)
            return 6;
    }
    return 0;
}

int later = 42;
