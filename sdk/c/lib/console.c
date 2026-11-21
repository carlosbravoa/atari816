/* console.c - keys to ASCII and line input, as ulib's key_ascii and getline do. */
#include <horizon.h>

static const char ktab[] = "abcdefghijklmnopqrstuvwxyz1234567890\r\033\b\t -=[]\\\0;'`,./";
static const char kshift[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ!@#$%^&*()\r\033\b\t _+{}|\0:\"~<>?";
static unsigned char caps;

/* HID usage + modifiers | down << 8 -> ASCII, KEY_* for the arrows and the editing keys,
 * 1-26 for ctrl + letter, 0 for nothing (a key release, a modifier). Caps lock toggles. */
unsigned hz_key_ascii(unsigned usage, unsigned mods)
{
    unsigned c;
    if (mods < 0x100)
        return 0;                               /* a release */
    if (usage >= 0x4F && usage < 0x53)
        return usage - 0x4F + KEY_RIGHT;
    if (usage >= 0x4A && usage < 0x4F)
        return usage - 0x4A + KEY_HOME;
    if (usage == 0x39) {
        caps ^= 1;
        return 0;
    }
    if (usage < 4 || usage > 0x38)
        return 0;
    c = (unsigned char)((mods & 0x22) ? kshift : ktab)[usage - 4];
    if (!c)
        return 0;
    if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')) {
        if (caps)
            c ^= 0x20;
        if (mods & 0x11)
            return c & 0x1F;                    /* ctrl */
    }
    return c;
}

/* the next character typed (blocks); 3 when the keyboard is not ours */
static unsigned getkey(void)
{
    unsigned u, c;
    for (;;) {
        u = hz_input_read();
        if (hz_errno) {
            hz_sleep(10);
            return 3;
        }
        if (u >= 0x100)
            continue;                           /* mouse, wheel */
        c = hz_key_ascii(u, hz_x);
        if (c)
            return c;
    }
}

static void out(const char *s)
{
    hz_puts(s);
}

static void outc(char c)
{
    char b[2];
    b[0] = c;
    b[1] = 0;
    hz_puts(b);
}

int hz_getline(char *buf, unsigned size)
{
    unsigned len = 0, pos = 0, i, max, c;
    if (!size)
        return 0;
    max = size - 1;
    c = hz_con_size();
    if (!hz_errno && c > 3 && max > c - 3)
        max = c - 3;
    for (;;) {
        c = getkey();
        if (c == '\r' || c == '\n') {
            buf[len] = 0;
            out("\n");
            return (int)len;
        }
        if (c == 3) {
            buf[len] = 0;
            out("^C\n");
            return -1;
        }
        if (c == 4 && len == 0) {               /* ctrl-D on an empty line: end of input */
            buf[0] = 0;
            out("\n");
            return -2;
        }
        if (c == '\b' && pos) {
            --pos;
            for (i = pos; i + 1 < len; ++i)
                buf[i] = buf[i + 1];
            --len;
            outc('\b');
            for (i = pos; i < len; ++i)
                outc(buf[i]);
            outc(' ');
            for (i = pos; i <= len; ++i)
                outc('\b');
        } else if (c == KEY_LEFT && pos) {
            --pos;
            outc('\b');
        } else if (c == KEY_RIGHT && pos < len) {
            outc(buf[pos++]);
        } else if (c >= ' ' && c < 0x7F && len < max) {
            for (i = len; i > pos; --i)
                buf[i] = buf[i - 1];
            buf[pos] = (char)c;
            ++len;
            for (i = pos; i < len; ++i)
                outc(buf[i]);
            ++pos;
            for (i = pos; i < len; ++i)
                outc('\b');
        }
    }
}
