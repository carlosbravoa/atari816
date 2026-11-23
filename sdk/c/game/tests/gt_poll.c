/* gt_poll.c - hgame's test: the mouse in full screen without a button (the pointer's
 * motion, as a mouse-driven game needs it), and a program without frames (a DOS port: it
 * keeps its own time and calls only hg_poll) whose hg_scroll / hg_split reach the screen:
 * by hg_poll, and at once by hg_view_send. 320 x 180 on a framebuffer of 400 rows. */
#include <stdio.h>
#include <hgame.h>

static unsigned fails;

static void check(const char *what, int ok)
{
    printf("%s poll: %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        ++fails;
}

int main(void)
{
    unsigned long t0 = hg_ms();
    unsigned y, moves = 0, buttons = 0, polls = 0;
    int lx, ly;
    static char line[32];

    if (hg_screen_fb(HG_320X180, "gt_poll", 320, 400) < 0) {
        printf("FAIL poll: hg_screen_fb\n");
        return 1;
    }
    for (y = 0; y < 400; y += 20) {                     /* bands, each with its row */
        hg_fill(0, (int)y, 320, 20, 16 + (y / 20) * 7 % 200);
        sprintf(line, "row %u", y);
        hg_text(120, (int)y + 5, line, 1);
    }
    hg_flush(1);

    /* 1. frames: the script moves the mouse at 0.5 s (to 400, 200 of 640 x 360) with no
     * button held: hg_mouse_x / y follow (halved) */
    lx = hg_mouse_x;
    ly = hg_mouse_y;
    while (hg_ms() - t0 < 2000 && hg_frame()) {
        if (hg_mouse_x != lx || hg_mouse_y != ly)
            ++moves;
        lx = hg_mouse_x;
        ly = hg_mouse_y;
        buttons |= hg_mouse_b | hg_mouse_clicked();
    }
    hg_end();                                           /* (no frame open from here on) */
    printf("gt_poll: %u frames saw the pointer move, now at %d,%d\n", moves, hg_mouse_x,
           hg_mouse_y);
    check("the pointer moves without a button (hg_frame)", moves > 0);
    check("at the place moved to, halved", hg_mouse_x == 200 && hg_mouse_y == 100);
    check("no button seen", buttons == 0);

    /* 2. no frames: hg_scroll, then only hg_poll. The script moves the mouse again at
     * 2.4 s; shot 1 at 2.8 s: rows 100-279 */
    hg_scroll(0, 100);
    while (hg_ms() - t0 < 3000) {
        if (!hg_poll())
            return 1;
        ++polls;
        hz_vsync();
    }
    check("the pointer moves without a button (hg_poll)", hg_mouse_x == 50 && hg_mouse_y == 150);

    /* 3. hg_split, then hg_view_send and no poll: shot 2 at 3.8 s shows rows 100-139 above
     * the split at line 40 and rows 220-359 below it */
    hg_split(40, 0, 220);
    hg_view_send();
    while (hg_ms() - t0 < 4200)
        hz_vsync();
    printf("gt_poll: %u polls\n", polls);
    printf("gt_poll: %u failed\n", fails);
    return 0;
}
