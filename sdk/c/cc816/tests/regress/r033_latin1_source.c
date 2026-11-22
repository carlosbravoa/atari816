/* r033_latin1_source.c - a source with bytes above 127 that are not UTF-8 (a DOS game's
 * code page 437 text in a string, Xargon's cfg_win.h: TheDraw's crunched screen, in a
 * header) made an internal compiler error (UnicodeDecodeError) when it was in an included
 * file: the main file was read as Latin-1, the headers as UTF-8. Now every file is read
 * byte for byte, and the bytes of strings and character constants stay as they are. Found
 * by the Xargon port. This file has such bytes (keep it Latin-1) and includes itself once
 * (as a header) to have them in an included file too. */
#ifndef R033_ONCE
#define R033_ONCE
#include "r033_latin1_source.c"
static const unsigned char raw[] = "ܰ Ŀ";
static const unsigned char esc[] = "\xdc\xb0 \xc4\xbf";

int main(void)
{
    unsigned i;
    unsigned char c = '�';
    for (i = 0; i < sizeof esc; i++)
        if (raw[i] != esc[i] || inc[i] != esc[i])
            return 1 + i;
    if (sizeof raw != 6 || sizeof inc != 6)
        return 10;
    if (c != 0xB0)
        return 11;
    return 0;
}
#else
static const unsigned char inc[] = "ܰ Ŀ";
#endif
