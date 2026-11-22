/* signed_char.c - with -fsigned-char a plain char is signed (-128 to 127). */
// FLAGS: -fsigned-char
#include <limits.h>

int main(void)
{
    char c = 200;               /* -56 */
    char d = '\xff';
    if (c >= 0 || c != -56 || d != -1 || '\xff' != -1)
        return 1;
    if (CHAR_MIN != -128 || CHAR_MAX != 127)
        return 2;
#ifdef __CHAR_UNSIGNED__
    return 3;
#endif
    return 0;
}
