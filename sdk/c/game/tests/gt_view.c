/* gt_view.c - hgame's test: a framebuffer taller than the screen (hg_screen_fb), the view
 * on it (hg_split: a fixed panel above a part that scrolls; hg_scroll), the key queue
 * (hg_key_next) and POKEY's 16-bit voices (hg_note). What a 320 x 200 game needs at
 * 320 x 180 (the Digger port, ports/digger, is built on these). */
#include <stdio.h>
#include <string.h>
#include <hgame.h>

static unsigned fails;

static void check(const char *what, int ok)
{
    printf("%s view: %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        ++fails;
}

static void until(unsigned long t0, unsigned long t)
{
    while (hg_ms() - t0 < t && hg_frame())
        ;
}

int main(void)
{
    unsigned long t0 = hg_ms();
    unsigned y, k, got[3], n = 0;
    static char line[32];

    /* refused shapes: nothing is opened */
    check("a stride that is not a multiple of 16 is refused",
          hg_screen_fb(HG_320X180, "gt_view", 330, 0) < 0);
    check("rows fewer than the screen's are refused",
          hg_screen_fb(HG_320X180, "gt_view", 0, 100) < 0);
    check("with HG_DOUBLE is refused",
          hg_screen_fb(HG_320X180 | HG_DOUBLE, "gt_view", 512, 400) < 0);

    /* 320 x 180 on a framebuffer of 400 rows of 512 bytes */
    if (hg_screen_fb(HG_320X180, "gt_view", 512, 400) < 0) {
        printf("FAIL view: hg_screen_fb\n");
        return 1;
    }
    check("the framebuffer's shape", hg_fb_stride == 512 && hg_fb_rows == 400);
    hg_fill(0, 0, 320, 20, 17);                         /* the panel: rows 0-19 */
    hg_text(8, 5, "PANEL (rows 0-19)", 1);
    for (y = 20; y < 400; y += 20) {                    /* bands, each with its row */
        hg_fill(0, (int)y, 320, 20, 16 + (y / 20) * 7 % 200);
        sprintf(line, "row %u", y);
        hg_text(120, (int)y + 5, line, 1);
    }
    hg_fill(300, 396, 20, 4, 196);                      /* the very last rows */
    check("drawing reaches the framebuffer's last row", hg_peek(310, 399) == 196);
    check("and the row below the screen's last", hg_peek(10, 185) == 16 + 9 * 7);

    /* the panel fixed (screen rows 0-19), below it rows 20-179 */
    hg_split(20, 0, 20);
    until(t0, 2000);                                    /* shot 1 at 1.5 s */
    /* the lower part scrolled: rows 220-379 below the panel */
    hg_split(20, 0, 220);
    hg_split(20, 0, 300);       /* refused (would show rows past 400): the view stays */
    hg_scroll(0, 390);          /* refused too */
    until(t0, 3400);                                    /* shot 2 at 3 s */

    /* the key queue: the script types a, b, Enter */
    while (n < 3 && hg_ms() - t0 < 6000 && hg_frame())
        while (n < 3 && (k = hg_key_next()) != 0)
            got[n++] = k;
    check("three keys in the queue", n == 3);
    check("a: usage 4, character 'a'", n > 0 && got[0] == (0x04 | 'a' << 8));
    check("b: usage 5, character 'b'", n > 1 && got[1] == (0x05 | 'b' << 8));
    check("Enter: usage $28", n > 2 && (got[2] & 0xFF) == HG_KEY_ENTER);
    check("then the queue is empty", hg_key_next() == 0);

    /* the 16-bit voices (the emulator logs the writes: run.py looks for AUDCTL) */
    hg_note(0, 440, 8);
    hg_note(1, 1193182UL / 0x11D1, 10);         /* a PC speaker's PIT divisor */
    until(t0, hg_ms() - t0 + 200);
    hg_note(0, 0, 0);
    hg_sound_off();

    printf("gt_view: %u failed\n", fails);
    return 0;
}
