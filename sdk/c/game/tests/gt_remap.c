/* gt_remap.c - hgame's test: colour remapping (REV $0D: the blitter's table through
 * sheet_draw's SH_TABLE and SH_REMAP records; older boards: the CPU, the same pictures).
 * Full screen 320 x 180 on a framebuffer of 400 rows (rows 200-399 off the screen): remapped
 * image draws (opaque, keyed: the key tested on the image's pixel), two tables in one frame,
 * a clipped draw, the framebuffer through a table (hg_remap_rect: to the screen, in place),
 * a plain draw after remapped ones, a table changed between frames, a table needed again
 * after a draw_list record (text), many remapped draws in a row (the kernel's fast path), the
 * kernel's refusals, and the time of a 320 x 180 hg_remap_rect against a plain copy. Each
 * checked by reading the framebuffer back (hg_peek). The last frame stays for the shot. */
#include <stdio.h>
#include <string.h>
#include <hgame.h>

static unsigned fails;

static void check(const char *what, int ok)
{
    printf("%s remap: %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        ++fails;
}

static unsigned char px[16 * 16 * 2];   /* frame 0: 40 with a 7 (key) centre; frame 1: 41..56 */
static unsigned char tabs[3 * 256];

/* table 0: c + 1; table 1: 255 - c; table 2: c + 100 */
static unsigned tv(unsigned k, unsigned c)
{
    return (k == 0 ? c + 1 : k == 1 ? 255 - c : c + 100) & 255;
}

/* the 16 x 16 frame f of the art drawn at (x, y) through table k (key: 7 skipped, bg there) */
static int drawn(int x, int y, unsigned f, int k, int keyed, unsigned bg)
{
    unsigned i, j, c, want;
    for (j = 0; j < 16; j++)
        for (i = 0; i < 16; i++) {
            c = px[f * 256 + j * 16 + i];
            want = keyed && c == 7 ? bg : k < 0 ? c : tv((unsigned)k, c);
            if (hg_peek(x + (int)i, y + (int)j) != want)
                return 0;
        }
    return 1;
}

/* the ramp at framebuffer row 200 + r, column c */
static unsigned ramp(unsigned c, unsigned r)
{
    return (c + 3 * r) & 255;
}

int main(void)
{
    hg_image *im, *op, *t, *rimg;
    hz_sheetrec r;
    unsigned i, j, rev, ok, hw;
    unsigned long t0, t1;
    unsigned char __far *p;

    if (hg_screen_fb(HG_320X180, "gt_remap", 320, 400) < 0) {
        printf("FAIL remap: hg_screen_fb\n");
        return 1;
    }
    rev = (hz_sys_info(), hz_x);
    for (i = 0; i < 256; i++)
        px[i] = (i / 16 >= 4 && i / 16 < 12 && i % 16 >= 4 && i % 16 < 12) ? 7 : 40;
    for (i = 0; i < 256; i++)
        px[256 + i] = (unsigned char)(41 + i % 16);
    for (j = 0; j < 3; j++)
        for (i = 0; i < 256; i++)
            tabs[j * 256 + i] = (unsigned char)tv(j, i);
    im = hg_image_from(px, 16, 16, 2, 7);
    op = hg_image_from(px, 16, 16, 2, HG_NONE);
    t = hg_remap_new(tabs, 3);
    check("images and three tables made, as sheets", im && op && t && im->sheet && op->sheet &&
          t->sheet && t->w == 256 && t->n == 3);
    hw = (unsigned)hg_remap_hw(t);
    printf("gt_remap: REV $%02X, remapped by %s\n", rev, hw ? "the blitter" : "the CPU");
    check("by the blitter exactly from REV $0D", hw == (rev >= 0x0D));
    /* the ramp off the screen: rows 200-399 (an image drawn there) */
    rimg = hg_image_new(320, 200, 1);
    check("the ramp's image", rimg != 0);
    if (!rimg)
        return 1;
    p = hg_image_pixels(rimg, 0);
    for (j = 0; j < 200; j++)
        for (i = 0; i < 320; i++)
            p[j * 320 + i] = (unsigned char)ramp(i, j);
    hg_draw(rimg, 0, 0, 200);
    hg_flush(1);

    /* frame 1 */
    hg_frame();
    hg_clear(99);
    hg_draw_remap(op, 0, 10, 10, t, 0);                 /* opaque, table 0 */
    hg_draw_remap(im, 0, 30, 10, t, 1);                 /* keyed, table 1: the centre stays 99 */
    hg_draw_remap(op, 1, 50, 10, t, 2);                 /* table 2 in the same call */
    hg_draw_remap(op, 1, 70, 10, t, 0);                 /* back to table 0 */
    hg_draw_remap(im, 0, -8, 40, t, 1);                 /* clipped at the left */
    hg_draw_part_remap(op, 4, 20, 8, 8, 90, 10, t, 1);  /* a part of frame 1 */
    hg_text(100, 40, "TEXT", 15);                       /* a draw_list record between them */
    hg_draw_remap(op, 1, 110, 10, t, 1);                /* table 1 needed again */
    hg_draw(op, 1, 130, 10);                            /* a plain draw after them */
    for (i = 0; i < 12; i++)                            /* the fast path: one sheet and op */
        hg_draw_remap(op, 1, 10 + 18 * (int)i, 60, t, 2);
    hg_remap_rect(0, 200, 64, 10, 150, 10, t, 1);      /* the framebuffer, through table 1 */
    hg_remap_rect(0, 200, 64, 10, 150, 30, t, 2);
    hg_remap_rect(150, 30, 64, 10, 150, 30, t, 0);     /* in place: + 1 again */
    hg_remap_rect(-10, 200, 64, 10, 230, 10, t, 1);    /* the source cut at the left */
    hg_flush(1);
    check("opaque, table 0", drawn(10, 10, 0, 0, 0, 99));
    check("keyed: the key on the image's pixel, table 1", drawn(30, 10, 0, 1, 1, 99));
    check("table 2 in the same call", drawn(50, 10, 1, 2, 0, 99));
    check("table 0 again", drawn(70, 10, 1, 0, 0, 99));
    ok = 1;
    for (j = 0; j < 16; j++)
        for (i = 0; i < 8; i++) {
            unsigned c = px[j * 16 + 8 + i];
            if (hg_peek((int)i, 40 + (int)j) != (c == 7 ? 99 : tv(1, c)))
                ok = 0;
        }
    check("clipped at the left (the source moves with the cut)", ok);
    ok = 1;
    for (j = 0; j < 8; j++)
        for (i = 0; i < 8; i++)
            if (hg_peek(90 + (int)i, 10 + (int)j) != tv(1, px[256 + (4 + j) * 16 + 4 + i]))
                ok = 0;
    check("a part", ok);
    check("a table needed again after a draw_list record", drawn(110, 10, 1, 1, 0, 99));
    check("a plain draw after remapped ones", drawn(130, 10, 1, -1, 0, 99));
    ok = 1;
    for (i = 0; i < 12; i++)
        if (!drawn(10 + 18 * (int)i, 60, 1, 2, 0, 99))
            ok = 0;
    check("12 remapped draws in a row", ok);
    ok = 1;
    for (j = 0; j < 10; j++)
        for (i = 0; i < 64; i++) {
            if (hg_peek(150 + (int)i, 10 + (int)j) != tv(1, ramp(i, j)))
                ok = 0;
            if (hg_peek(150 + (int)i, 30 + (int)j) != tv(0, tv(2, ramp(i, j))))
                ok = 0;
        }
    check("hg_remap_rect from rows off the screen, and in place", ok);
    ok = hg_peek(239, 10) == 99;
    for (j = 0; j < 10; j++)
        for (i = 0; i < 54; i++)
            if (hg_peek(240 + (int)i, 10 + (int)j) != tv(1, ramp(i, j)))
                ok = 0;
    check("hg_remap_rect: the source cut at the left (the destination moves)", ok);

    /* frame 2: a table changed between frames */
    hg_frame();
    for (i = 0; i < 256; i++)
        tabs[i] = (unsigned char)(200 - i);
    hg_remap_set(t, 0, tabs);
    hg_draw_remap(op, 1, 10, 100, t, 0);
    hg_flush(1);
    ok = 1;
    for (j = 0; j < 16; j++)
        for (i = 0; i < 16; i++)
            if (hg_peek(10 + (int)i, 100 + (int)j) != ((200 - px[256 + j * 16 + i]) & 255))
                ok = 0;
    check("hg_remap_set: the new table from the next draw", ok);
    for (i = 0; i < 256; i++)
        tabs[i] = (unsigned char)tv(0, i);
    hg_remap_set(t, 0, tabs);

    /* the kernel's refusals (the blitter's path only) */
    if (hw) {
        memset(&r, 0, sizeof r);
        r.sheet = t->sheet;
        r.op = SH_TABLE;
        r.w = 0;
        r.h = 1;
        check("SH_TABLE w 0: EINVAL", hz_sheet_draw(hg_win, 1, &r) < 0 && hz_errno == HZ_EINVAL);
        r.w = 200;
        r.x = 100;
        check("SH_TABLE x + w past 256: EINVAL", hz_sheet_draw(hg_win, 1, &r) < 0 &&
              hz_errno == HZ_EINVAL);
        r.w = 256;
        r.x = 0;
        r.sy = 3;
        check("SH_TABLE past the sheet: EINVAL", hz_sheet_draw(hg_win, 1, &r) < 0 &&
              hz_errno == HZ_EINVAL);
        r.sy = 0;
        r.h = 2;
        check("SH_TABLE h 2: EINVAL", hz_sheet_draw(hg_win, 1, &r) < 0 && hz_errno == HZ_EINVAL);
        r.op = SH_FILL | SH_REMAP;
        r.h = 1;
        check("SH_FILL + SH_REMAP: EINVAL", hz_sheet_draw(hg_win, 1, &r) < 0 &&
              hz_errno == HZ_EINVAL);
    } else if (rev < 0x0D && rev >= 0x09) {
        memset(&r, 0, sizeof r);
        r.sheet = t->sheet;
        r.op = SH_TABLE;
        r.w = 256;
        r.h = 1;
        check("before REV $0D: SH_TABLE refused (ENODEV)", hz_sheet_draw(hg_win, 1, &r) < 0 &&
              hz_errno == HZ_ENODEV);
    }

    /* the time of a 320 x 180 copy of rows 200-379 to the screen: plain, and through a table
     * (the frame's first records wait for the vertical blank: a pixel sent first) */
    hg_frame();
    hg_fill(319, 179, 1, 1, 0);
    hg_flush(1);
    t0 = hg_us();
    hg_move(0, 200, 320, 180, 0, 0);
    hg_flush(1);
    t1 = hg_us();
    printf("gt_remap: 320 x 180 plain copy (hg_move) %lu us\n", t1 - t0);
    t0 = hg_us();
    hg_remap_rect(0, 200, 320, 180, 0, 0, t, 1);
    hg_flush(1);
    t1 = hg_us();
    printf("gt_remap: 320 x 180 through a table (hg_remap_rect, %s) %lu us\n",
           hw ? "the blitter" : "the CPU", t1 - t0);
    ok = 1;
    for (j = 0; j < 180; j += 7)
        for (i = 0; i < 320; i += 5)
            if (hg_peek((int)i, (int)j) != tv(1, ramp(i, j)))
                ok = 0;
    check("320 x 180 through a table", ok);

    /* the picture for the shot: the ramp, its lower half through table 1 in place, sprites */
    hg_frame();
    hg_move(0, 200, 320, 180, 0, 0);
    hg_remap_rect(0, 90, 320, 90, 0, 90, t, 1);
    for (i = 0; i < 8; i++) {
        hg_draw_remap(im, 0, 20 + 36 * (int)i, 40, t, i % 3);
        hg_draw_remap(op, 1, 20 + 36 * (int)i, 120, t, i % 3);
    }
    hg_text(8, 4, "REMAP", 255);
    hg_flush(1);
    printf("gt_remap: %u failed\n", fails);
    for (i = 0; i < 300; i++)
        if (!hg_frame())
            break;
    return 0;
}
