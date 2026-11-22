/* r021_va_struct.c - a structure among a variadic function's arguments was passed as its
 * address (as for a parameter), so va_arg(ap, struct s) read the pointer and the bytes
 * after it, and an odd-sized one (7 bytes) put every later argument out of step. A
 * variadic structure is now its bytes on the stack, padded to an even size. Found by
 * the c-testsuite (00204.c). */
#include <stdarg.h>
#include <string.h>

struct s3 { char x[3]; };
struct s8 { long a; int b; char c, d; };

static int check(int n, ...)
{
    va_list ap;
    int bad = 0;
    va_start(ap, n);
    while (n--) {
        struct s3 a = va_arg(ap, struct s3);
        int k = va_arg(ap, int);
        struct s8 b = va_arg(ap, struct s8);
        bad |= memcmp(a.x, "abc", 3) != 0;
        bad |= (k != 1234) << 1;
        bad |= (b.a != -100000L || b.b != 7 || b.c != 'x' || b.d != 'y') << 2;
    }
    va_end(ap);
    return bad;
}

int main(void)
{
    struct s3 a = { { 'a', 'b', 'c' } };
    struct s8 b = { -100000L, 7, 'x', 'y' };
    return check(2, a, 1234, b, a, 1234, b);
}
