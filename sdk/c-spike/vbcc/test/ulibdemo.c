/* ulibdemo.c - C calling Horizon's ulib (ca65/ld65 code) through the blob's jump table */
#include "horizon.h"

void ul_puts(const char *s);        /* ulib put_str (line-buffered output) */
void ul_putdec(unsigned v);         /* put_dec */
void ul_puthex(unsigned v);         /* put_hex16 */
void ul_flush(void);                /* out_flush */

static const char glob[] = "a string in the code bank, ";

int main(void)
{
    char loc[24];
    loc[0] = 'a'; loc[1] = ' '; loc[2] = 'l'; loc[3] = 'o'; loc[4] = 'c'; loc[5] = 'a';
    loc[6] = 'l'; loc[7] = '\n'; loc[8] = 0;
    ul_puts("ULIB from C: ");
    ul_putdec(12345);
    ul_puts(" $");
    ul_puthex(0xBEEF);
    ul_puts(", ");
    ul_puts(glob);
    ul_puts(loc);                   /* bank 0: ulib's put_str takes any bank */
    ul_flush();
    return 0;
}
