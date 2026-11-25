/* gt_wrap.c - hgame's test: the ring (hg_scroll_wrap, hg_split_wrap) for a game that draws
 * its own world into a framebuffer that wraps, as the Micropolis port does by hand: a
 * world of 120 x 100 tiles of 16 x 16 in a ring of 21 x 12 slots (336 x 192 pixels) with a
 * panel's rows below it (192-207). Each frame the slots whose tile changed are drawn (the
 * game's work); the library reduces the camera to the ring. Checked: the scroll values sent
 * (x modulo 336, y modulo 192, negative ones too), the slots in the framebuffer, a panel at
 * the top (split, the ring in the second set) and at the bottom (the ring in the first),
 * the views refused (rows past the framebuffer, vheight too large, hg_split_wrap without
 * the ring). The pictures (Marga's wrap) at the states the program prints. */
#include <stdio.h>
#include <string.h>
#include <hgame.h>

extern hz_fsscroll hg__scr;     /* (the library's: the scroll registers sent at hg_end) */

#define RC 21
#define RR 12
#define VH (RR * 16)

static unsigned fails;
static unsigned shown[RC * RR];
static int cx, cy, top;

static void check(const char *what, int ok)
{
    printf("%s wrap: %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        ++fails;
}

static unsigned tile(unsigned c, unsigned r)
{
    return 16 + (c * 7u + r * 3u) % 200;
}

/* the game's own ring: the slots in view whose tile is not there drawn (tile t: its colour,
 * a dark corner and its column number) */
static void draw_view(void)
{
    unsigned c, r, c0 = (unsigned)cx / 16, r0 = (unsigned)cy / 16, t, i;
    static char s[4];
    hg_origin(0, 0);
    for (r = r0; r <= ((unsigned)cy + 163) / 16; r++)
        for (c = c0; c <= ((unsigned)cx + 319) / 16; c++) {
            i = (r % RR) * RC + c % RC;
            t = tile(c, r);
            if (shown[i] != t) {
                shown[i] = t;
                hg_fill((int)(c % RC) * 16, (int)(r % RR) * 16, 16, 16, t);
                hg_fill((int)(c % RC) * 16, (int)(r % RR) * 16, 2, 2, 1);
                sprintf(s, "%u", c % 100);
                hg_text((int)(c % RC) * 16, (int)(r % RR) * 16 + 4, s, 1);
            }
        }
}

static int slots_ok(void)
{
    unsigned c, r;
    hg_flush(1);
    for (r = (unsigned)cy / 16; r <= ((unsigned)cy + 163) / 16; r++)
        for (c = (unsigned)cx / 16; c <= ((unsigned)cx + 319) / 16; c++)
            if (hg_peek((int)(c % RC) * 16 + 8, (int)(r % RR) * 16 + 1) != (int)tile(c, r) ||
                hg_peek((int)(c % RC) * 16, (int)(r % RR) * 16) != 1)
                return 0;
    return 1;
}

/* the camera to (x, y): the ring's view sent with the frame */
static void camera(int x, int y)
{
    cx = x;
    cy = y;
    draw_view();
    if (top)
        hg_split_wrap(16, cx, cy);              /* the ring from line 16 on */
    else
        hg_scroll_wrap(cx, cy, VH);
}

static int sent_ok(void)
{
    unsigned x = top ? hg__scr.x2 : hg__scr.x, y = top ? hg__scr.y2 : hg__scr.y;
    return x == (unsigned)(cx % 336) && y == (unsigned)(cy % VH) && hg__scr.vheight == VH &&
           (hg__scr.ctrl & FSC_HWRAP);
}

static void shot(unsigned k)
{
    unsigned i;
    printf("gt_wrap: shot %u\n", k);
    for (i = 0; i < 40 && hg_frame(); i++)
        ;
}

int main(void)
{
    unsigned i, ok;

    if (hg_screen_fb(HG_320X180, "gt_wrap", RC * 16, VH + 16) < 0) {
        printf("FAIL wrap: hg_screen_fb\n");
        return 1;
    }
    hg_split_wrap(16, 0, 0);                    /* refused: no ring yet */
    check("hg_split_wrap without the ring: nothing", !(hg__scr.ctrl & FSC_SPLIT));
    hg_scroll_wrap(0, 0, 300);                  /* refused: more rows than the framebuffer */
    check("vheight past the framebuffer refused", !(hg__scr.ctrl & FSC_HWRAP));
    memset(shown, 0xFF, sizeof shown);

    /* the panel at the top: rows 192-207 shown on lines 0-15 (set 1), the ring below */
    hg_scroll_wrap(0, 0, VH);
    hg_split_wrap(16, 0, 0);
    hg_scroll(0, VH);
    check("panel at the top: set 1 the panel's rows, the split at 32 lines",
          hg__scr.y == VH && hg__scr.split == 32 && (hg__scr.ctrl & FSC_SPLIT));
    hg_fill(0, VH, 336, 16, 9);
    hg_text(4, VH + 3, "ring: panel at the top", 1);
    top = 1;
    camera(0, 0);
    hg_frame();
    check("the first view", sent_ok() && slots_ok());
    /* right and down 7 / 5 pixels a frame: across the ring's edges, x past 336 and y past
     * 192 several times */
    ok = 1;
    for (i = 1; i <= 120 && hg_frame(); i++) {
        camera((int)i * 7, (int)i * 5);
        if (!sent_ok())
            ok = 0;
    }
    check("right and down: the values sent modulo the ring", ok && slots_ok());
    /* 40 / 24 pixels a frame (2.5 / 1.5 tiles), then back left and up */
    ok = 1;
    for (i = 1; i <= 12 && hg_frame(); i++) {
        camera(840 + (int)i * 40, 600 + (int)i * 24);
        if (!sent_ok() || !slots_ok())
            ok = 0;
    }
    check("40 / 24 pixels a frame right and down", ok);
    shot(1);
    ok = 1;
    for (i = 1; i <= 30 && hg_frame(); i++) {
        camera(1320 - (int)i * 41, 888 - (int)i * 27);
        if (!sent_ok() || !slots_ok())
            ok = 0;
    }
    check("41 / 27 pixels a frame left and up, past the ring's left and top", ok &&
          cx == 90 && cy == 78);
    shot(2);

    /* the panel at the bottom: the ring in set 1, the panel from line 164 * 2 */
    top = 0;
    hg_split(0, 0, 0);
    hg_scroll_wrap(-5, -7, VH);
    check("negative values: from the ring's end (331, 185)", hg__scr.x == 331 &&
          hg__scr.y == 185);
    hg_split(164, 0, VH);
    check("panel at the bottom: the split's view the panel's rows", hg__scr.y2 == VH &&
          hg__scr.split == 328);
    hg_split(164, 0, VH + 4);                   /* refused: 16 rows past the framebuffer */
    check("a panel past the framebuffer refused", hg__scr.y2 == VH);
    hg_scroll(0, VH + 1);                       /* refused: 164 rows from 193 */
    check("a view below the ring past the framebuffer refused", hg__scr.y == 185);
    hg_fill(0, VH, 336, 16, 12);
    hg_text(4, VH + 3, "ring: panel at the bottom", 1);
    ok = 1;
    for (i = 1; i <= 20 && hg_frame(); i++) {
        camera(1000 - (int)i * 45, 50 + (int)i * 33);
        if (!sent_ok() || !slots_ok())
            ok = 0;
    }
    check("45 / 33 pixels a frame, the ring in the first set", ok);
    shot(3);
    printf("gt_wrap: %u failed\n", fails);
    return 0;
}
