/* gt_sprites.c - hgame's test: hardware sprites in full screen: 16 x 16 and 16 x 32 images,
 * flips, twice the size, hidden and shown, moved, behind the bitmap; the box test; bad
 * arguments refused with a message. Checked by the screenshots (Marga draws sprites: the
 * framebuffer does not have them). */
#include <stdio.h>
#include <string.h>
#include <hgame.h>

static unsigned fails;

static void check(const char *what, int ok)
{
    printf("%s sprites: %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        ++fails;
}

static unsigned char arrow[16 * 16], tall[16 * 32];

int main(void)
{
    hg_image *a, *t;
    unsigned long t0 = hg_ms();
    unsigned i, k;

    if (hg_screen(HG_320X180, "gt_sprites") < 0) {
        printf("FAIL sprites: hg_screen\n");
        return 1;
    }
    /* an arrow pointing right (asymmetric: flips show), 0 transparent */
    for (i = 0; i < 16; i++)
        for (k = 0; k < 16; k++)
            arrow[i * 16 + k] = (k < 10 && i >= 6 && i < 10) || (k >= 10 && (int)(k - 10) <=
                                (int)(i < 8 ? i : 15 - i) - 2) ? 200 : (i == 0 ? 30 : 0);
    for (i = 0; i < 16 * 32; i++)
        tall[i] = (i / 16) & 4 ? 46 : 0;
    a = hg_image_from(arrow, 16, 16, 1, 0);
    t = hg_image_from(tall, 16, 32, 1, 0);
    check("hg_sprites(6)", hg_sprites(6) == 6);
    hg_frame();
    hg_clear(0);
    hg_fill(160, 0, 160, 180, 17);          /* the right half: not colour 0 */
    hg_text(8, 4, "sprites: plain, flipped, x2, tall, hidden, behind", 1);
    hg_sprite_set(0, a, 0, 0);
    hg_sprite_pos(0, 20, 40);
    hg_sprite_set(1, a, 0, HG_HFLIP);
    hg_sprite_pos(1, 50, 40);
    hg_sprite_set(2, a, 0, HG_VFLIP | HG_MAG);
    hg_sprite_pos(2, 80, 40);
    hg_sprite_set(3, t, 0, 0);
    hg_sprite_pos(3, 130, 40);
    hg_sprite_set(4, a, 0, HG_HIDE);        /* set, hidden */
    hg_sprite_pos(4, 20, 100);
    hg_sprite_set(5, a, 0, HG_BEHIND);      /* over colour 0 only: its right half hidden */
    hg_sprite_pos(5, 152, 100);
    check("box test: apart", !hg_sprite_hit(0, 1, 0));
    hg_sprite_pos(1, 30, 44);
    check("box test: overlapping", hg_sprite_hit(0, 1, 0));
    check("box test: margin", !hg_sprite_hit(0, 1, 6));
    check("box test: a hidden one never hits", !hg_sprite_hit(0, 4, 0));
    hg_sprite_pos(1, 50, 40);
    hg_sprite_set(9, a, 0, 0);              /* bad: messages, nothing else */
    hg_sprite_show(4, 1);
    hg_sprite_show(4, 0);
    hg_sprite_set(0, 0, 0, 0);
    while (hg_ms() - t0 < 2500 && hg_frame())        /* shot 1 at 2 s */
        ;
    hg_sprite_show(4, 1);                   /* shown now */
    for (i = 0; i < 30 && hg_frame(); i++)
        hg_sprite_pos(0, 20 + (int)i * 2, 40 + (int)i);      /* moved */
    while (hg_ms() - t0 < 4500 && hg_frame())        /* shot 2 at 4 s */
        ;
    printf("gt_sprites: %u failed\n", fails);
    return 0;
}
