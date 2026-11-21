/* window.c - a C window program on the raw window-system syscalls (cc816, Horizon).
 * Opens a window, draws text, a filled rectangle and a frame; a click in the content
 * draws a small square there; the close box (or ctrl+W) ends it.
 * The draw block and the event record are locals (on the stack in bank 0): the
 * syscalls get them as X = offset, Y = 0, which is the task's window.
 */
#include <stdio.h>
#include "horizon.h"

static hz_wopen_t wo;            /* a global: in the code bank */
static char line[48];
static unsigned char win;

static void draw(unsigned char op, unsigned char c1, unsigned char c2,
                 int x, int y, int w, int h, const char *text)
{
    hz_wdraw_t d;                /* a local: in bank 0 */
    d.op = op; d.c1 = c1; d.c2 = c2; d.font = 0;
    d.x = x; d.y = y; d.w = w; d.h = h;
    HZ_FAR(d.ptr, text);
    hz_win_draw(win, &d);
}

int main(void)
{
    hz_event_t ev;
    unsigned char own, clicks = 0;
    own = (unsigned char)hz_ws_start();
    wo.x = 160; wo.y = 100; wo.w = 280; wo.h = 120;
    HZ_FAR(wo.title, "C window");
    wo.flags = 0;
    win = (unsigned char)hz_win_open(&wo);
    if (hz_err) { printf("CWIN: win_open error %u\n", hz_err); return 1; }

    draw(WD_TEXT, C_BLACK, 0xFF, 12, 10, 0, 0, "Hello from C (cc816) in a window");
    draw(WD_FILL, C_RED, 0, 12, 34, 120, 40, 0);
    draw(WD_FRAME, C_BLACK, 0, 10, 32, 124, 44, 0);
    draw(WD_FILL, 16 + 36 * 1 + 6 * 3 + 5, 0, 150, 34, 110, 40, 0);   /* a cube colour */
    draw(WD_TEXT, C_BLACK, 0xFF, 12, 90, 0, 0, "Click me, then close me.");

    for (;;) {
        hz_win_event(0, &ev);
        if (ev.type == WE_CLOSE) break;
        if (ev.type == WE_BUTTON && (ev.c & 1)) {
            ++clicks;
            draw(WD_FILL, C_GREEN, 0, (int)ev.a - 3, (int)ev.b - 3, 7, 7, 0);
            sprintf(line, "CWIN: click %u at %d,%d", clicks, (int)ev.a, (int)ev.b);
            hz_puts(line);
            hz_puts("\n");
        }
    }
    hz_win_close(win);
    if (own) hz_ws_stop();
    puts("CWIN: closed");
    return 0;
}
