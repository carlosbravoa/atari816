/* gt_draw.c - hgame's test: drawing in full screen 320 x 180 (fills, outlines, lines,
 * pixels, text and its clipping, moves, the origin, images: sheet and draw_list paths,
 * keyed and opaque, parts, CPU composition, tile maps), each checked by reading the
 * framebuffer back (hg_peek). Prints "PASS draw: ..." / "FAIL draw: ..." lines; the last
 * frame is left on the screen for the screenshot. */
#include <stdio.h>
#include <string.h>
#include <hgame.h>

static unsigned fails;

static void check(const char *what, int ok)
{
    printf("%s draw: %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        ++fails;
}

/* every pixel of the rectangle has colour c */
static int all(int x, int y, int w, int h, unsigned c)
{
    int i, j;
    for (j = 0; j < h; j++)
        for (i = 0; i < w; i++)
            if (hg_peek(x + i, y + j) != c)
                return 0;
    return 1;
}

static unsigned char px[16 * 16 * 2];   /* two 16 x 16 frames */
static unsigned char tmap[4 * 3] = { 0, 1, 0, 1, 1, 0, 1, 0, 0, 0, 1, 1 };

int main(void)
{
    hg_image *im, *op, *nosheet = 0, *bg, *list[40];
    unsigned long t0 = hg_ms();
    unsigned i, n = 0;
    int ok;

    if (hg_screen(HG_320X180, "gt_draw") < 0) {
        printf("FAIL draw: hg_screen\n");
        return 1;
    }
    /* the art: frame 0 a 16 x 16 square of 40 with a key-coloured (7) centre, frame 1 all 41 */
    for (i = 0; i < 256; i++)
        px[i] = (i / 16 >= 4 && i / 16 < 12 && i % 16 >= 4 && i % 16 < 12) ? 7 : 40;
    memset(px + 256, 41, 256);
    im = hg_image_from(px, 16, 16, 2, 7);           /* keyed: 7 is transparent */
    op = hg_image_from(px, 16, 16, 2, HG_NONE);     /* opaque */
    check("images made, as sheets", im && op && im->sheet && op->sheet);
    /* an image the kernel has no sheet for (all 32 taken): the draw_list path */
    while (n < 40) {
        list[n] = hg_image_from(px, 16, 16, 2, 7);
        if (!list[n])
            break;
        if (!list[n]->sheet) {
            nosheet = list[n++];
            break;
        }
        ++n;
    }
    check("an image without a sheet", nosheet != 0);

    hg_frame();
    hg_clear(1);
    hg_fill(10, 10, 30, 20, 2);
    hg_rect(50, 10, 30, 20, 3);
    hg_hline(90, 10, 30, 4);
    hg_vline(90, 12, 18, 4);
    hg_fill(-5, -5, 10, 10, 5);                     /* cut at the left and the top */
    hg_fill(315, 175, 10, 10, 6);                   /* cut at the right and the bottom */
    hg_flush(1);
    check("clear", hg_peek(200, 100) == 1 && hg_peek(0, 179) == 1);
    check("fill", all(10, 10, 30, 20, 2) && hg_peek(9, 10) == 1 && hg_peek(40, 30) == 1);
    check("rect", hg_peek(50, 10) == 3 && hg_peek(79, 29) == 3 && hg_peek(65, 20) == 1 &&
          hg_peek(50, 20) == 3 && hg_peek(79, 20) == 3);
    check("hline, vline", all(90, 10, 30, 1, 4) && all(90, 12, 1, 18, 4) && hg_peek(91, 12) == 1);
    check("fill cut at the top left", all(0, 0, 5, 5, 5) && hg_peek(5, 0) == 1);
    check("fill cut at the bottom right", all(315, 175, 5, 5, 6));

    /* lines and pixels (the CPU) */
    hg_line(130, 10, 159, 39, 8);
    hg_line(170, 39, 199, 10, 9);
    hg_pixel(210, 10, 10);
    hg_pixel(-1, 0, 11);                            /* outside: nothing */
    ok = 1;
    for (i = 0; i < 30; i++)
        if (hg_peek(130 + (int)i, 10 + (int)i) != 8 || hg_peek(170 + (int)i, 39 - (int)i) != 9)
            ok = 0;
    check("diagonal lines", ok);
    check("pixel", hg_peek(210, 10) == 10 && hg_peek(211, 10) == 1);
    hg_line(220, 10, 240, 10, 12);                  /* horizontal: a fill */
    hg_flush(1);
    check("horizontal line", all(220, 10, 21, 1, 12));

    /* images */
    hg_draw(op, 0, 10, 40);
    hg_draw(im, 0, 30, 40);
    hg_draw(im, 1, 50, 40);
    hg_draw(nosheet, 0, 70, 40);
    hg_draw(op, 0, -8, 60);                         /* cut: the right half shows */
    hg_draw_part(op, 2, 2, 4, 4, 90, 40);
    hg_draw_part(im, 0, 16, 16, 16, 110, 40);       /* frame 1 by rows */
    hg_flush(1);
    check("opaque copy (sheet)", hg_peek(10, 40) == 40 && hg_peek(18, 48) == 7);
    check("keyed copy (sheet)", hg_peek(30, 40) == 40 && hg_peek(38, 48) == 1);
    check("frame 1", all(50, 40, 16, 16, 41));
    check("keyed copy (draw_list)", hg_peek(70, 40) == 40 && hg_peek(78, 48) == 1);
    check("image cut at the left", hg_peek(0, 64) == 7 && hg_peek(3, 64) == 7 &&
          hg_peek(4, 64) == 40 && hg_peek(0, 75) == 40 && hg_peek(8, 64) == 1);
    check("part", all(90, 40, 2, 2, 40) && hg_peek(92, 42) == 7 && hg_peek(94, 40) == 1);
    check("part across frames", all(110, 40, 16, 16, 41));

    /* text: ink only, on paper, cut at the left (the source's bit offset) and the top */
    hg_text(10, 90, "Hg", 14);
    hg_text_bg(40, 90, "Hg", 15, 16);
    hg_text_bg(-3, 110, "HHH", 17, 18);
    hg_text_bg(60, -4, "H", 19, 20);
    hg_flush(1);
    /* 'H' rows 1-7: columns 1 and 6 set (bit 6, bit 1 of the byte), row 4 all */
    check("text, ink only", hg_peek(11, 92) == 14 && hg_peek(16, 92) == 14 &&
          hg_peek(12, 92) == 1 && hg_peek(11, 94) == 14 && hg_peek(13, 94) == 14);
    check("text on paper", hg_peek(41, 92) == 15 && hg_peek(42, 92) == 16 &&
          hg_peek(40, 90) == 16 && hg_peek(47, 99) == 16);
    check("text cut at the left", hg_peek(0, 112) == 18 && hg_peek(3, 112) == 17 &&
          hg_peek(4, 112) == 18 && hg_peek(6, 112) == 17);
    check("text cut at the top", hg_peek(60, 0) == 20 && hg_peek(61, 0) == 19 &&
          hg_peek(62, 0) == 19 && hg_peek(61, 1) == 19 && hg_peek(62, 1) == 20 &&
          hg_peek(60, 5) == 20);
    check("text width", hg_text_width("abc") == 24);
    hg_textf(10, 130, 27, "%s%d", "H", 7);         /* printf-style: "H7" */
    hg_flush(1);
    check("textf", hg_peek(11, 132) == 27 && hg_peek(16, 134) == 27 && hg_peek(12, 132) == 1);

    /* the origin, and a move */
    hg_origin(200, 60);
    hg_fill(0, 0, 10, 10, 21);
    hg_origin(0, 0);
    hg_move(200, 60, 10, 10, 220, 60);
    hg_flush(1);
    check("origin", all(200, 60, 10, 10, 21) && hg_peek(199, 60) == 1);
    check("move", all(220, 60, 10, 10, 21));

    /* the CPU: image to image, a fill in an image, a map into an image, a map on screen */
    bg = hg_image_new(64, 48, 1);
    hg_image_fill(bg, 0, 0, 64, 48, 22);
    hg_image_draw(bg, im, 0, 8, 8);                 /* keyed: the centre stays 22 */
    hg_image_draw(bg, op, 1, -8, 30);               /* cut */
    hg_draw(bg, 0, 240, 100);
    hg_flush(1);
    check("image_fill, image_draw keyed", hg_peek(240, 100) == 22 && hg_peek(248, 108) == 40 &&
          hg_peek(256, 116) == 22);
    check("image_draw cut", hg_peek(240, 130) == 41 && hg_peek(247, 145) == 41 &&
          hg_peek(248, 130) == 22);
    hg_map_image(bg, tmap, 4, 3, op);
    hg_draw(bg, 0, 240, 100);
    hg_map_draw(tmap, 4, 3, op, 160, 100);
    hg_flush(1);
    check("map_image", hg_peek(240, 100) == 40 && hg_peek(256, 100) == 41 &&
          hg_peek(256, 116) == 40 && hg_peek(272, 116) == 41 && hg_peek(288, 132) == 41);
    check("map_draw", hg_peek(160, 100) == 40 && hg_peek(176, 100) == 41 &&
          hg_peek(176, 116) == 40 && hg_peek(192, 116) == 41 && hg_peek(208, 132) == 41);

    /* a frame with records of both kinds in several runs */
    hg_frame();
    hg_fill(10, 150, 10, 10, 23);
    hg_text(30, 150, "runs", 24);
    hg_fill(70, 150, 10, 10, 25);
    hg_text(90, 150, "ok", 26);
    hg_frame();
    hg_flush(1);
    check("runs of both kinds in one frame", all(10, 150, 10, 10, 23) &&
          all(70, 150, 10, 10, 25) && hg_peek(31, 152) == 24);
    check("frames counted", hg_frames == 3);

    hg_text(130, 150, fails ? "SOME FAILED" : "ALL PASSED", fails ? 11 : 13);
    hg_flush(1);
    while (hg_ms() - t0 < 4000 && hg_frame())       /* (the screenshot at 3 s) */
        ;
    printf("gt_draw: %u failed\n", fails);
    for (i = 0; i < n; i++)
        hg_image_free(list[i]);
    return 0;
}
