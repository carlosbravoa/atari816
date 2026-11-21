/* window.c - a window program on Horizon's raw window calls, in C.
 *
 * Opens a window, draws text, a filled rectangle, a frame and a line; every left click in
 * the content draws a small green square there and is counted in the window; the close
 * box (or ctrl+W, Alt+F4) ends it. Started from the Desktop's Programs menu (make run).
 *
 * The calls (ABI.md, "Window system"): ws_start (the window system: already running on
 * the Desktop), win_open with a hz_winopen block, win_draw with hz_windraw blocks,
 * win_event into a hz_event, win_close. Their blocks may be anywhere: globals (in the
 * code bank) or locals (on the stack, in the window bank 0): the stubs pass the bank.
 * The program's console output (printf) goes to the console log.
 */
#include <stdio.h>
#include <horizon.h>

static unsigned char win;

/* one win_draw call: op, ink c1, paper / second colour c2, a rectangle, a text */
static void draw(unsigned op, unsigned c1, unsigned c2, int x, int y, int w, int h,
                 const char *text)
{
    hz_windraw d;
    d.op = (unsigned char)op;
    d.c1 = (unsigned char)c1;
    d.c2 = (unsigned char)c2;
    d.font = 0;                         /* 0 the UI font, 1 fixed 8x12 */
    d.x = x;
    d.y = y;
    d.w = w;
    d.h = h;
    HZ_U24(d.ptr, text);                /* a u24 pointer: offset and bank */
    d.stride = 0;
    hz_win_draw(win, &d);
}

int main(void)
{
    hz_winopen wo;
    hz_event ev;
    char line[40];
    unsigned own, clicks = 0;
    int w;

    own = hz_ws_start();                /* 1 if this program started the window system */
    wo.x = 160;
    wo.y = 100;
    wo.w = 300;
    wo.h = 130;
    HZ_U24(wo.title, "C window");
    wo.flags = 0;                       /* WF_RESIZE, WF_PLAIN, ... */
    w = hz_win_open(&wo);
    if (w < 0) {
        printf("CWIN: win_open: %s\n", hz_strerror(hz_errno));
        return 1;
    }
    win = (unsigned char)w;

    draw(WD_TEXT, C_BLACK, 0xFF, 12, 10, 0, 0, "Hello from C in a window");
    draw(WD_FILL, C_RED, 0, 12, 34, 120, 40, 0);
    draw(WD_FRAME, C_BLACK, 0, 10, 32, 124, 44, 0);
    draw(WD_FILL, 16 + 36 * 1 + 6 * 3 + 5, 0, 150, 34, 110, 40, 0);   /* a colour-cube entry */
    draw(WD_LINE, C_DARK, 0, 150, 80, 260, 80, 0);
    draw(WD_TEXT, C_BLACK, 0xFF, 12, 90, 0, 0, "Click me, then close me.");

    for (;;) {
        if (hz_win_event(0, &ev))       /* 0: wait for the next event */
            break;
        if (ev.type == WE_CLOSE)
            break;
        if (ev.type == WE_BUTTON && (ev.c & 1)) {     /* a left press: a, b = position */
            ++clicks;
            draw(WD_FILL, C_GREEN, 0, (int)ev.a - 3, (int)ev.b - 3, 7, 7, 0);
            sprintf(line, "clicks: %u   ", clicks);
            draw(WD_TEXT, C_BLACK, C_BODY, 12, 108, 0, 0, line);
            printf("CWIN: click %u at %d,%d\n", clicks, (int)ev.a, (int)ev.b);
        }
    }
    hz_win_close(win);
    if (own)
        hz_ws_stop();
    printf("CWIN: closed after %u clicks\n", clicks);
    return 0;
}
