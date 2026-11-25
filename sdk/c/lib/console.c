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

/* the console's column, as far as the library's output shows it: stdout and stderr count
 * what they send (stdio.c), so hz_getline knows where the prompt ends. Printable +1, BS -1,
 * CR and LF 0; escapes are not followed. hz_puts called directly is not counted */
unsigned __hz_concol;

void __hz_concount(const char *s)
{
    unsigned char c;
    while ((c = (unsigned char)*s++) != 0) {
        if (c == '\n' || c == '\r')
            __hz_concol = 0;
        else if (c == '\b') {
            if (__hz_concol)
                --__hz_concol;
        } else if (c >= ' ' && c < 0x7F)
            ++__hz_concol;
    }
}

/* the echo, sent in pieces (one puts per key, not per character) */
static char ob[48];
static unsigned on;

static void flush_(void)
{
    if (on) {
        ob[on] = 0;
        hz_puts(ob);
        on = 0;
    }
}

static void outc(char c)
{
    if (on == sizeof ob - 1)
        flush_();
    ob[on++] = c;
}

static void out(const char *s)
{
    while (*s)
        outc(*s++);
    flush_();
}

/* The line editor's state. The line may be longer than the screen line: it is shown in the
 * room right of the prompt less one column (room), from character vs on, and scrolled
 * sideways by half the room when the cursor would leave it; so it never wraps, and the
 * cursor never has to go back over a screen line's start (the console's BS stops at
 * column 0). As ulib's getline does. */
#define MINROOM 12              /* fewer columns right of the prompt: the next screen line */
#define NONE 0xFFFFu
static char *g_buf;
static unsigned g_len, g_pos, g_vs, g_scr, g_dend, g_room;

/* the cursor to column t of the view: backspaces, or the characters there again */
static void moveto(unsigned t)
{
    unsigned i;
    while (g_scr > t) {
        outc('\b');
        --g_scr;
    }
    while (g_scr < t) {
        i = g_vs + g_scr;
        outc(i < g_len ? g_buf[i] : ' ');
        ++g_scr;
    }
}

/* the screen after a change from character `from` on (NONE: only the cursor moved) */
static void show(unsigned from)
{
    unsigned end, i;
    if (g_pos < g_vs || g_pos - g_vs >= g_room) {
        g_vs = g_pos > g_room / 2 ? g_pos - g_room / 2 : 0;
        from = g_vs;
    }
    if (from < g_vs)
        from = g_vs;
    end = g_vs + g_room;
    if (end > g_len)
        end = g_len;
    if (from < end) {
        moveto(from - g_vs);
        for (i = from; i < end; ++i)
            outc(g_buf[i]);
        g_scr = end - g_vs;
    }
    end -= g_vs;
    if (end < g_dend) {                         /* the columns no longer used: blank */
        moveto(end);
        while (g_scr < g_dend) {
            outc(' ');
            ++g_scr;
        }
    }
    g_dend = end;
    moveto(g_pos - g_vs);
}

int hz_getline(char *buf, unsigned size)
{
    unsigned i, max, c, cols;
    if (!size)
        return 0;
    max = size - 1;
    g_buf = buf;
    g_len = g_pos = g_vs = g_scr = g_dend = 0;
    cols = hz_con_size();
    if (hz_errno || cols < 2)
        cols = 80;
    g_room = cols - 1 - __hz_concol % cols;
    if (g_room < MINROOM) {
        out("\n");
        g_room = cols - 1 < MINROOM ? MINROOM : cols - 1;
    }
    for (;;) {
        flush_();
        c = getkey();
        if (c == '\r' || c == '\n') {
            buf[g_len] = 0;
            out("\n");
            __hz_concol = 0;
            return (int)g_len;
        }
        if (c == 3) {
            buf[g_len] = 0;
            out("^C\n");
            __hz_concol = 0;
            return -1;
        }
        if (c == 4 && g_len == 0) {             /* ctrl-D on an empty line: end of input */
            buf[0] = 0;
            out("\n");
            __hz_concol = 0;
            return -2;
        }
        if (c == '\b' && g_pos) {
            --g_pos;
            for (i = g_pos; i + 1 < g_len; ++i)
                buf[i] = buf[i + 1];
            --g_len;
            show(g_pos);
        } else if (c == KEY_LEFT && g_pos) {
            --g_pos;
            show(NONE);
        } else if (c == KEY_RIGHT && g_pos < g_len) {
            ++g_pos;
            show(NONE);
        } else if (c >= ' ' && c < 0x7F && g_len < max) {
            for (i = g_len; i > g_pos; --i)
                buf[i] = buf[i - 1];
            buf[g_pos] = (char)c;
            ++g_len;
            ++g_pos;
            show(g_pos - 1);
        }
    }
}
