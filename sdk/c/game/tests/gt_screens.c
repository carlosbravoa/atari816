/* gt_screens.c - hgame's test: the full-screen modes one after another in one program
 * (each held 2 s for a screenshot): 320 x 180 with two pages (HG_DOUBLE), 640 x 360 x 8,
 * 640 x 360 x 4; the palette and the raster table; the pause (Alt+Esc / Alt+Tab from the
 * script) and the screen coming back as it was. */
#include <stdio.h>
#include <string.h>
#include <hgame.h>

static unsigned fails;

static void check(const char *what, int ok)
{
    printf("%s screens: %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        ++fails;
}

/* hold the screen until t ms after the start */
static void until(unsigned long t0, unsigned long t)
{
    while (hg_ms() - t0 < t && hg_frame())
        ;
}

static const hz_raster ras[2] = { { 200, 0, 0, 0, 120 }, { 300, 0, 0, 90, 0 } };

int main(void)
{
    unsigned long t0 = hg_ms();
    unsigned i, f0;
    static unsigned char grey[16 * 3];
    hg_image *im;
    static unsigned char px[16];

    /* 1. 320 x 180, two pages: everything redrawn every frame, shown whole */
    if (hg_screen(HG_320X180 | HG_DOUBLE, "gt_screens") < 0) {
        printf("FAIL screens: hg_screen double\n");
        return 1;
    }
    check("double: framebuffer rows for two pages", hg_fb_rows == 360 && hg_fb_stride == 320);
    for (i = 0; i < 40 && hg_frame(); i++) {
        hg_clear(17);
        hg_fill(10 + (int)i * 4, 60, 40, 40, 196);
        hg_text(8, 8, "two pages", 1);
    }
    hg_frame();
    hg_clear(17);
    hg_fill(100, 60, 120, 60, 196);
    hg_rect(98, 58, 124, 64, 1);
    hg_text(8, 8, "HG_DOUBLE: drawn unseen", 1);
    hg_flush(1);
    check("double: drawing goes to the hidden page", hg_peek(150, 90) == 196 &&
          hg_peek(5, 170) == 17);
    hg_frame();                                         /* now shown */
    hg_clear(17);
    hg_fill(100, 60, 120, 60, 196);
    hg_rect(98, 58, 124, 64, 1);
    hg_text(8, 8, "HG_DOUBLE: drawn unseen", 1);
    until(t0, 2000);                                    /* shot 1 at 1.5 s */
    hg_close();

    /* 2. 640 x 360, 256 colours, its own palette and a raster table */
    if (hg_screen(HG_640X360, "gt_screens") < 0) {
        printf("FAIL screens: hg_screen 640\n");
        return 1;
    }
    check("640 x 360: size", hg_w == 640 && hg_h == 360);
    hg_frame();
    hg_clear(0);
    hg_fill(20, 40, 600, 280, 2);
    for (i = 0; i < 16; i++)
        hg_fill(40 + (int)i * 36, 80, 30, 200, 232 + i);
    hg_text(24, 16, "640 x 360 x 8: a palette of its own, a raster table from line 200", 1);
    hg_line(20, 40, 619, 319, 1);
    hg_flush(1);
    check("640 x 360: fill, peek", hg_peek(20, 40) == 1 && hg_peek(619, 41) == 2 &&
          hg_peek(40, 80) == 232 && hg_peek(41 + 36 * 15, 279) == 247);
    hg_color(2, 40, 40, 90);
    hg_raster(2, ras);
    hg_frame();
    until(t0, 4000);                                    /* shot 2 at 3.5 s */
    /* 3. the pause: Alt+Esc at 4.3 s, Alt+Tab at 5.3 s (shot 3 on the desktop between) */
    f0 = hg_pauses;
    until(t0, 6500);
    check("paused and resumed", hg_pauses == f0 + 1);
    hg_flush(1);
    check("the screen is kept across the pause", hg_peek(20, 40) == 1 && hg_peek(40, 80) == 232);
    until(t0, 7500);                                    /* shot 4 at 7 s: back */
    hg_close();

    /* 4. 640 x 360 x 4 (16 colours): fills, the CPU's text and pixels */
    if (hg_screen(HG_640X360X4, "gt_screens") < 0) {
        printf("FAIL screens: hg_screen 640x4\n");
        return 1;
    }
    for (i = 0; i < 16; i++) {
        grey[i * 3] = (unsigned char)(i * 16);
        grey[i * 3 + 1] = (unsigned char)(i * 12);
        grey[i * 3 + 2] = (unsigned char)(255 - i * 16);
    }
    hg_palette(0, 16, grey);
    hg_frame();
    hg_clear(0);
    for (i = 0; i < 16; i++)
        hg_fill(32 + (int)i * 36, 60, 32, 200, i);
    hg_text_bg(32, 20, "H 640 x 360 x 4: 16 colours, text by the CPU", 15, 1);
    hg_pixel(33, 300, 9);
    hg_pixel(34, 300, 10);
    hg_flush(1);
    check("16 colours: fills", hg_peek(32 + 36 * 5, 100) == 5 && hg_peek(32 + 36 * 15, 259) == 15);
    check("16 colours: pixels (nibbles)", hg_peek(33, 300) == 9 && hg_peek(34, 300) == 10 &&
          hg_peek(32, 300) == 0);
    {
        int x, y, ink = 0, paper = 0;
        for (y = 20; y < 30; y++)               /* the first character's cell: H */
            for (x = 32; x < 40; x++)
                if (hg_peek(x, y) == 15)
                    ++ink;
                else if (hg_peek(x, y) == 1)
                    ++paper;
        check("16 colours: text", ink == 18 && paper == 62);
    }
    im = hg_image_from(px, 4, 4, 1, HG_NONE);
    hg_draw(im, 0, 0, 0);                               /* an 8 bpp image here: refused */
    hg_flush(1);
    check("16 colours: an 8 bpp image refused, nothing drawn", hg_peek(0, 0) == 0);
    hg_frame();
    until(t0, 9500);                                    /* shot 5 at 9 s */
    hg_close();
    printf("gt_screens: %u failed\n", fails);
    return 0;
}
