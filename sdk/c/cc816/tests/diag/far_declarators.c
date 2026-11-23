/* DOS compilers' far declarators (ports/xcom items 3 and 4): a qualifier before a later
 * declarator's '*' is that declarator's; a far function pointer is accepted with a
 * warning (__far ignored: a function pointer is the main-bank entry in every model) */
unsigned char __far *p, __far *q;
int a = 1, __far *ip;
struct t { char __far *x, __far *y; };
void (__far *fp)(void);       // EXPECT: warning: '__far' on a function pointer is ignored
typedef int (__far *cmpfn)(int);  // EXPECT: warning: '__far' on a function pointer is ignored
int main(void)
{
    struct t s;
    return sizeof p + sizeof q + sizeof ip + sizeof s.y - 16;
}
