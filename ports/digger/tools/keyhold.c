/* keyhold.c - a board test for the held-key fault (ports/digger/PORTING-NOTES.md): every key
 * event a program gets, with its time, on the screen and on the console.
 *
 *   sdk/c/bin/hcc -o KEYHOLD.PRG ports/digger/tools/keyhold.c
 *
 * Start it from the Desktop, press and HOLD a letter key (say A) for 3 seconds, let go,
 * then Esc. Each line is: the time (ms since the start), "down" / "rep" / "up", the key
 * (HID usage). A key held reads "down", then (Horizon's key repeat, from 0.4 s) "rep" every
 * 50 ms, then "up" when it is let go. With the firmware's 1-second timeout (before 2026-11)
 * the "up" comes about 1,000 ms after the "down" while the key is still held, and the
 * "rep" lines stop there. */
#include <stdio.h>
#include <hgame.h>

#define LINES 30
static char log_[LINES][40];
static unsigned nlog, changed = 1;

static void add(const char *s)
{
    unsigned i;
    printf("%s\n", s);
    if (nlog == LINES) {
        for (i = 1; i < LINES; i++)
            sprintf(log_[i - 1], "%s", log_[i]);
        --nlog;
    }
    sprintf(log_[nlog++], "%s", s);
    changed = 1;
}

int main(void)
{
    static unsigned char held[256];
    static char line[40];
    unsigned long t0;
    unsigned k, i, u, y;
    if (hg_window(320, 320, "Key hold test") < 0)
        return 1;
    t0 = hg_ms();
    add("hold a key 3 s, let go; Esc ends");
    while (hg_frame()) {
        /* presses and repeats, in order (each a down event of the kernel) */
        while ((k = hg_key_next()) != 0) {
            u = k & 0xFF;
            sprintf(line, "%6lu %s $%02X", hg_ms() - t0, held[u] ? "rep " : "down", u);
            add(line);
            held[u] = 1;
        }
        /* releases: a key we saw down that is no longer down */
        for (u = 1; u < 256; u++)
            if (held[u] && !hg_key(u)) {
                held[u] = 0;
                sprintf(line, "%6lu up   $%02X", hg_ms() - t0, u);
                add(line);
            }
        if (hg_key_pressed(HG_KEY_ESC))
            break;
        if (changed) {                  /* (text is slow: only when the log changed) */
            changed = 0;
            hg_fill(0, 0, 320, 320, 16);
            for (i = 0, y = 4; i < nlog; i++, y += 10)
                hg_text(4, (int)y, log_[i], 1);
        }
    }
    return 0;
}
