/* gt_util.c - hgame's test: the helpers (random numbers, sine, cosine, atan2, fixed
 * point, rectangles, the clock, fixed steps), an .HGI file from the card (made by
 * img2c.py), and bad arguments: a message each ("hgame: ..."), no crash. */
#include <stdio.h>
#include <string.h>
#include <hgame.h>

static unsigned fails;

static void check(const char *what, int ok)
{
    printf("%s util: %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        ++fails;
}

int main(void)
{
    unsigned i, r, lo = 0xFFFF, hi = 0, hits[4] = { 0, 0, 0, 0 }, ok;
    unsigned long t;
    hg_image *im;
    unsigned char __far *p;

    hg_srand(1234);
    r = hg_rand();
    hg_srand(1234);
    check("rand: the same seed, the same numbers", hg_rand() == r);
    for (i = 0; i < 400; i++) {
        r = hg_rand_n(4);
        if (r < 4)
            ++hits[r];
        r = hg_rand();
        if (r < lo)
            lo = r;
        if (r > hi)
            hi = r;
    }
    check("rand_n: 0-3, each about a quarter", hits[0] > 60 && hits[1] > 60 && hits[2] > 60 &&
          hits[3] > 60 && hits[0] + hits[1] + hits[2] + hits[3] == 400);
    check("rand: spread", lo < 2000 && hi > 63000);
    check("sin, cos", hg_sin(0) == 0 && hg_sin(64) == 256 && hg_sin(128) == 0 &&
          hg_sin(192) == -256 && hg_cos(0) == 256 && hg_sin(32) == 181 && hg_cos(96) == -181);
    check("atan2", hg_atan2(0, 10) == 0 && hg_atan2(10, 0) == 64 && hg_atan2(0, -10) == 128 &&
          hg_atan2(-10, 0) == 192 && hg_atan2(10, 10) == 32 && hg_atan2(-5, 5) == 224);
    check("fix8", HG_FIX8_MUL(HG_FIX8(3), HG_FIX8(2)) == HG_FIX8(6) &&
          HG_FIX8_DIV(HG_FIX8(3), HG_FIX8(2)) == 384 && HG_FIX8_INT(HG_FIX8(5) + 200) == 5);
    check("fix16 multiply", hg_fix16_mul(HG_FIX16(3), HG_FIX16(-7)) == HG_FIX16(-21) &&
          hg_fix16_mul(0x18000L, 0x18000L) == 0x24000L &&
          hg_fix16_mul(HG_FIX16(300), HG_FIX16(100)) == HG_FIX16(30000));
    check("fix16 divide", hg_fix16_div(HG_FIX16(1), HG_FIX16(4)) == 0x4000L &&
          hg_fix16_div(HG_FIX16(-21), HG_FIX16(7)) == HG_FIX16(-3) &&
          hg_fix16_div(HG_FIX16(1000), 0x8000L) == HG_FIX16(2000));
    check("overlap", hg_overlap(0, 0, 10, 10, 9, 9, 5, 5) && !hg_overlap(0, 0, 10, 10, 10, 0, 5, 5)
          && hg_overlap(-5, -5, 10, 10, 0, 0, 1, 1) && !hg_overlap(0, 0, 0, 0, 0, 0, 5, 5));
    t = hg_ms();
    hz_sleep(100);
    check("the clock", hg_ms() - t >= 90 && hg_ms() - t <= 130);
    if (hg_screen(HG_320X180, "gt_util") < 0) {
        printf("FAIL util: hg_screen\n");
        return 1;
    }
    /* fixed steps: 50 a second over a second of frames */
    hg_frame();
    hg_steps(50);
    t = hg_ms();
    r = 0;
    while (hg_ms() - t < 1000 && hg_frame())
        r += hg_steps(50);
    printf("gt_util: %u steps in a second\n", r);
    check("50 steps a second", r >= 47 && r <= 53);
    /* an .HGI file: 2 frames of 4 x 2, key 7 (".": transparent), colours 40 and 41 */
    im = hg_image_load("/TEST.HGI");
    check(".HGI loaded", im && im->w == 4 && im->h == 2 && im->n == 2 && im->key == 7 &&
          im->bpp == 8);
    if (im) {
        p = hg_image_pixels(im, 0);
        ok = p[0] == 40 && p[1] == 40 && p[2] == 41 && p[3] == 7 && p[4] == 40;
        p = hg_image_pixels(im, 1);
        check(".HGI pixels", ok && p[0] == 41 && p[2] == 40 && p[4] == 7 && p[5] == 40);
        hg_clear(0);
        hg_draw(im, 1, 10, 10);
        hg_flush(1);
        check(".HGI drawn", hg_peek(10, 10) == 41 && hg_peek(12, 10) == 40 &&
              hg_peek(10, 11) == 0);
    }
    check("a missing file: NULL", hg_image_load("/NONE.HGI") == 0);
    /* bad arguments: each a message, nothing breaks */
    hg_draw(0, 0, 0, 0);
    hg_draw(im, 5, 0, 0);
    hg_draw_part(0, 0, 0, 1, 1, 0, 0);
    hg_sprite_set(0, im, 0, 0);
    hg_bob(40, im, 0, 0, 0);
    hg_palette(250, 10, (const unsigned char *)"x");
    hg_joy(3);
    hg_sfx(7, 0, 0, 0, 0, 0, 0);
    hg_camera(0, 0);
    hg_image_draw(0, im, 0, 0, 0);
    check("hg_window refused while a screen is open", hg_window(100, 100, "x") < 0);
    check("hg_banks(0) refused", hg_banks(0) == 0);
    hg_frame();
    check("still running after the bad calls", hg_frames > 50);
    printf("gt_util: %u failed\n", fails);
    return 0;
}
