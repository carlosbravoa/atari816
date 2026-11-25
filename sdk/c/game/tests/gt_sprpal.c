/* gt_sprpal.c - hgame's test: the palette bank of 4 bpp hardware sprites (hg_sprite_pal).
 * One 16 x 16 image of 4 bpp (SPRPAL.HGI, pixels 1-15 in stripes) shown by five sprites:
 * bank 0 (entries 1-15: shades of red), bank 8 (129-143: green, the Micropolis port's
 * case), bank 15 (241-255: blue), a bank set before the image, and a bank kept when the
 * image is set again. Bad arguments refused. Checked by the screenshot (Marga draws the
 * sprites: the framebuffer does not have them). */
#include <stdio.h>
#include <hgame.h>

static unsigned fails;

static void check(const char *what, int ok)
{
    printf("%s sprpal: %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        ++fails;
}

int main(void)
{
    hg_image *a;
    unsigned i;

    if (hg_screen(HG_320X180, "gt_sprpal") < 0) {
        printf("FAIL sprpal: hg_screen\n");
        return 1;
    }
    for (i = 1; i < 16; i++) {
        hg_color(i, 60 + i * 12, 0, 0);             /* bank 0: red */
        hg_color(128 + i, 0, 60 + i * 12, 0);       /* bank 8: green */
        hg_color(240 + i, 0, 0, 60 + i * 12);       /* bank 15: blue */
        hg_color(48 + i, 60 + i * 12, 60 + i * 12, 0);  /* bank 3: yellow */
    }
    a = hg_image_load("/SPRPAL.HGI");
    check("a 4 bpp image of 16 x 16", a && a->bpp == 4 && a->w == 16 && a->h == 16);
    if (!a)
        return 1;
    check("hg_sprites(5)", hg_sprites(5) == 5);
    hg_frame();
    hg_clear(17);
    hg_text(8, 4, "4 bpp sprites: banks 0, 8, 15, 3, 8", 1);
    hg_sprite_set(0, a, 0, HG_MAG);
    hg_sprite_pos(0, 20, 60);
    hg_sprite_set(1, a, 0, HG_MAG);
    hg_sprite_pal(1, 8);
    hg_sprite_pos(1, 80, 60);
    hg_sprite_pal(2, 15);                       /* (first) */
    hg_sprite_set(2, a, 0, HG_MAG);
    hg_sprite_pos(2, 140, 60);
    hg_sprite_set(3, a, 0, HG_MAG);
    hg_sprite_pal(3, 3);
    hg_sprite_pos(3, 200, 60);
    hg_sprite_set(4, a, 0, HG_MAG);
    hg_sprite_pal(4, 8);
    hg_sprite_pos(4, 260, 60);
    hg_frame();
    hg_sprite_set(4, a, 0, HG_MAG | HG_VFLIP);  /* the image again: the bank stays 8 */
    hg_sprite_pal(9, 1);                        /* refused: no such sprite */
    hg_sprite_pal(0, 16);                       /* refused: banks 0-15 */
    check("bad arguments refused (messages, nothing else)", 1);
    hg_frame();
    printf("gt_sprpal: shot 1\n");
    for (i = 0; i < 40 && hg_frame(); i++)
        ;
    printf("gt_sprpal: %u failed\n", fails);
    return 0;
}
