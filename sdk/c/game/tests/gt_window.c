/* gt_window.c - hgame's test: a game in a window: drawing into it, bobs over a background
 * image (moving, hidden, drawn over), the window's menu, the mouse and keys (the script
 * clicks, types and picks a menu item). */
#include <stdio.h>
#include <string.h>
#include <hgame.h>

static unsigned fails;

static void check(const char *what, int ok)
{
    printf("%s window: %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        ++fails;
}

static unsigned char ball[16 * 16];

int main(void)
{
    hg_image *bg, *b;
    unsigned long t0 = hg_ms();
    unsigned i, clicks = 0, typed = 0, menu = 0, xs = 0;
    int mx = 0, my = 0, m;

    if (hg_window(240, 160, "gt_window") < 0) {
        printf("FAIL window: hg_window\n");
        return 1;
    }
    check("size", hg_w == 240 && hg_h == 160);
    check("menu", hg_window_menu("Test\0One\0Two\0\0") == 0);
    for (i = 0; i < 256; i++)               /* a ball: colour 196, key 231 around it */
        ball[i] = ((int)(i % 16) - 8) * ((int)(i % 16) - 8) + ((int)(i / 16) - 8) *
                  ((int)(i / 16) - 8) < 40 ? 196 : 231;
    b = hg_image_from(ball, 16, 16, 1, 231);
    bg = hg_image_new(240, 144, 1);
    for (i = 0; i < 12; i++)                /* stripes */
        hg_image_fill(bg, 0, (int)i * 12, 240, 12, (i & 1) ? 22 : 23);
    hg_bob_background(bg, 0, 16);
    hg_frame();
    hg_fill(0, 0, 240, 16, C_BLACK);
    hg_text(4, 3, "bobs over a background", C_WHITE);
    hg_draw(bg, 0, 0, 16);
    while (hg_ms() - t0 < 6000 && hg_frame()) {
        ++i;
        hg_bob(0, b, 0, 20 + (int)(i % 200), 40);
        hg_bob(1, b, 0, 100, 60 + (int)(i % 60));
        if ((i / 30) & 1)
            hg_bob_hide(2);
        else
            hg_bob(2, b, 0, 200, 120);
        if (hg_mouse_clicked() & 1) {
            ++clicks;
            mx = hg_mouse_x;
            my = hg_mouse_y;
            hg_fill(mx - 2, my - 2, 5, 5, C_RED);       /* drawn over the bobs' layer */
        }
        while ((m = (int)hg_getchar()) != 0)
            if (m == 'x')
                ++xs;
        if (hg_key_pressed(HG_KEY_A + ('x' - 'a')))
            ++typed;
        m = hg_menu();
        if (m >= 0) {
            menu = (unsigned)m + 1;
            printf("gt_window: menu %d\n", m);
        }
    }
    /* the script: a click at content (60, 79), x typed twice, Test: Two picked */
    printf("gt_window: click at %d,%d\n", mx, my);
    check("a click, at its place", clicks == 1 && mx == 60 && my == 79);
    check("keys: pressed, and typed", typed == 2 && xs == 2);
    check("the menu item (Test: Two)", menu == 2);
    check("frames ran", hg_frames > 300);
    printf("gt_window: %u failed\n", fails);
    return 0;
}
