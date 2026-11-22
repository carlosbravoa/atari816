/* the same checks for a global's initialiser as for a local's */
char *p = 1234;                 // EXPECT: warning: initialising char * with int makes a pointer from an integer without a cast
unsigned char c = 300;          // EXPECT: warning: the conversion to unsigned char changes the value 300 to 44
int n = 70000L;                 // EXPECT: warning: the conversion to int changes the value 70000 to 4464
const char *ok = 0;
static const int *q = &n;       /* (adding const: no warning) */
int main(void) { return c + n + (p != 0) + (ok != 0) + (q != 0); }
