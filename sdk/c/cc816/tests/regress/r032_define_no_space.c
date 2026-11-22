/* r032_define_no_space.c - "#define NAME= value", without white space between the name and
 * its replacement, was refused ("Bad macro definition"): C99 asks for the space, but older
 * compilers took it, and gcc warns and takes the rest of the line ('=' and all) as the
 * replacement. Xargon's keyboard.h has "#define scan_f1= 0x3B" (never used). cc816 now does
 * as gcc (a warning). Found by the Xargon port. */
#define scan_f1= 0x3B
#define PLUS+1
#define scan_esc 0x01

int main(void)
{
    int x scan_f1;                      /* int x = 0x3B; */
    int y = 2 PLUS;                     /* 2 + 1 */
    if (x != 0x3B)
        return 1;
    if (y != 3)
        return 2;
    if (scan_esc != 1)
        return 3;
    return 0;
}
