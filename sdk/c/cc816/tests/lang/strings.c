/* strings.c - string literals: joined, escapes, sizes, wide characters and strings
 * (wchar_t is 16 bits; the source is UTF-8). */
#include <string.h>
#include <wchar.h>

static const char joined[] = "ab" "cd"
                             "ef";
static const wchar_t raw[] = L"né€";     /* UTF-8 in the source */
static const wchar_t wide[] = L"h\u00e9llo \x263A";     /* h e-acute llo, a smiley */

int main(void)
{
    const char *e = "\a\b\f\n\r\t\v\\\'\"\?\x41\101\0z";
    wchar_t w = L'\u20AC';
    wchar_t w2 = L'€';     /* the euro sign, as UTF-8 in the source */
    const wchar_t *wp = L"caf" L"\u00e9";
    if (sizeof joined != 7 || strcmp(joined, "abcdef") != 0)
        return 1;
    if (e[0] != 7 || e[1] != 8 || e[2] != 12 || e[3] != 10 || e[4] != 13 || e[5] != 9 ||
        e[6] != 11 || e[7] != '\\' || e[8] != '\'' || e[9] != '"' || e[10] != '?' ||
        e[11] != 'A' || e[12] != 'A' || e[13] != 0 || e[14] != 'z')
        return 2;
    if (sizeof "abc" != 4 || sizeof "" != 1 || sizeof "a\0b" != 4)
        return 3;
    if (sizeof(wchar_t) != 2 || sizeof wide != 2 * 8 || wide[1] != 0xE9 || wide[6] != 0x263A ||
        wide[7] != 0 || sizeof raw != 8 || raw[1] != 0xE9 || raw[2] != 0x20AC)
        return 4;
    if (w != 0x20AC || w2 != 0x20AC || L'A' != 65 || wcslen(wp) != 4 || wp[3] != 0xE9)
        return 5;
    if ("xyz"[1] != 'y' || *"q" != 'q')
        return 6;
    if ('\377' != 255 || '\xff' != 255 || 'ab' != 0x6162)
        return 7;
    {
        char buf[8] = "hi";
        if (buf[1] != 'i' || buf[2] != 0 || buf[7] != 0)
            return 8;
    }
    return 0;
}
