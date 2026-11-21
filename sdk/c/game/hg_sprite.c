/* hg_sprite.c - hgame: Marga's hardware sprites, changed together at hg_end (one spr_set
 * for new images and flags, one spr_move of many for moves). */
#include <string.h>
#include "hg_int.h"

static unsigned first, count;
static hz_sprite tab[16];
static unsigned char hasimg[16], dset[16], dmove[16];
static hz_sprite sprset[16];
static hz_sprmove sprmv[16];

static void end(void)
{
    unsigned i, ns = 0, nm = 0;
    for (i = 0; i < count; i++) {
        if (dset[i]) {
            /* (memcpy: vbcc 65816 miscompiles "a[i] = b[j]" for structures at -O1) */
            memcpy(&sprset[ns++], &tab[i], sizeof(hz_sprite));
            dset[i] = dmove[i] = 0;
        } else if (dmove[i]) {
            sprmv[nm].sprite = tab[i].sprite;
            sprmv[nm].zero = 0;
            sprmv[nm].x = tab[i].x;
            sprmv[nm].y = tab[i].y;
            ++nm;
            dmove[i] = 0;
        }
    }
    if (ns && hz_spr_set(ns, sprset))
        hg__fail("hg_sprite_set", hz_errno == HZ_EFAULT ? "the image is not the game's memory"
                 : "spr_set refused (image not 16-byte aligned?)");
    if (nm == 1)
        hz_spr_move(sprmv[0].sprite, sprmv[0].x, sprmv[0].y);
    else if (nm)
        hz_spr_move_many(nm, sprmv);
}

static void close_sprites(void)
{
    if (count)
        hz_spr_free(0xFFFF, 0);
    count = 0;
}

int hg_sprites(unsigned n)
{
    int f;
    unsigned i;
    if (hg__kind == HG__NONE) {
        hg__fail("hg_sprites", "no screen (hg_screen or hg_window first)");
        return -1;
    }
    if (n == 0 || n > 16) {
        hg__fail("hg_sprites", "1-16 sprites");
        return -1;
    }
    if (count)
        close_sprites();
    f = hz_spr_alloc(n, hg_win);
    if (f < 0) {
        hg__fail("hg_sprites", hz_errno == HZ_EAGAIN ? "not that many free (other programs"
                 " hold some)" : "no sprites on this machine (REV $0B is needed)");
        return -1;
    }
    first = (unsigned)f;
    count = n;
    memset(tab, 0, sizeof tab);
    memset(hasimg, 0, sizeof hasimg);
    memset(dset, 0, sizeof dset);
    memset(dmove, 0, sizeof dmove);
    for (i = 0; i < n; i++)
        tab[i].sprite = (unsigned char)(first + i);
    hg__hook_sprites = end;
    hg__hook_close_sprites = close_sprites;
    return (int)n;
}

static int ok(const char *fn, unsigned n)
{
    if (n >= count) {
        hg__fail(fn, count ? "no such sprite (hg_sprites took fewer)" : "hg_sprites first");
        return 0;
    }
    return 1;
}

void hg_sprite_set(unsigned n, const hg_image *img, unsigned frame, unsigned flags)
{
    unsigned ctrl;
    unsigned long a;
    if (!ok("hg_sprite_set", n))
        return;
    if (!img || frame >= img->n) {
        hg__fail("hg_sprite_set", img ? "no such frame" : "no image (NULL)");
        return;
    }
    ctrl = flags & (SPR_HFLIP | SPR_VFLIP | SPR_MAG | SPR_BEHIND);
    if (img->bpp == 8) {
        if (img->w != 16 || (img->h != 16 && img->h != 32)) {
            hg__fail("hg_sprite_set", "8 bpp sprites are 16 x 16 or 16 x 32");
            return;
        }
    } else {
        if ((img->w != 16 && img->w != 32) || (img->h != 16 && img->h != 32)) {
            hg__fail("hg_sprite_set", "4 bpp sprites are 16 or 32 wide and high");
            return;
        }
        ctrl |= SPR_BPP4;
        if (img->w == 32)
            ctrl |= SPR_WIDE;
    }
    if (img->h == 32)
        ctrl |= SPR_TALL;
    a = hg_image_addr(img, frame);
    if (a & 15) {
        hg__fail("hg_sprite_set", "the image is not 16-byte aligned");
        return;
    }
    if (!(flags & HG_HIDE))
        ctrl |= SPR_EN;
    if (hasimg[n] && tab[n].ctrl == ctrl && tab[n].image.off == (unsigned short)a &&
        tab[n].image.bank == (unsigned char)(a >> 16))
        return;                         /* (no change: nothing to send) */
    tab[n].ctrl = (unsigned char)ctrl;
    tab[n].image.off = (unsigned short)a;
    tab[n].image.bank = (unsigned char)(a >> 16);
    tab[n].pal = 0;
    hasimg[n] = 1;
    dset[n] = 1;
}

void hg_sprite_pos(unsigned n, int x, int y)
{
    if (!ok("hg_sprite_pos", n))
        return;
    if (tab[n].x != x || tab[n].y != y) {
        tab[n].x = x;
        tab[n].y = y;
        dmove[n] = 1;
    }
}

void hg_sprite_show(unsigned n, int on)
{
    unsigned char c;
    if (!ok("hg_sprite_show", n))
        return;
    if (on && !hasimg[n]) {
        hg__fail("hg_sprite_show", "no image yet (hg_sprite_set)");
        return;
    }
    c = (unsigned char)(on ? tab[n].ctrl | SPR_EN : tab[n].ctrl & ~SPR_EN);
    if (c != tab[n].ctrl) {
        tab[n].ctrl = c;
        dset[n] = 1;
    }
}

static void box(unsigned n, int *x, int *y, int *w, int *h)
{
    unsigned c = tab[n].ctrl;
    *x = tab[n].x;
    *y = tab[n].y;
    *w = (c & SPR_WIDE) ? 32 : 16;
    *h = (c & SPR_TALL) ? 32 : 16;
    if (c & SPR_MAG) {
        *w *= 2;
        *h *= 2;
    }
}

int hg_sprite_hit(unsigned a, unsigned b, unsigned margin)
{
    int ax, ay, aw, ah, bx, by, bw, bh, m = (int)margin;
    if (!ok("hg_sprite_hit", a) || !ok("hg_sprite_hit", b))
        return 0;
    if (!(tab[a].ctrl & SPR_EN) || !(tab[b].ctrl & SPR_EN))
        return 0;
    box(a, &ax, &ay, &aw, &ah);
    box(b, &bx, &by, &bw, &bh);
    return hg_overlap(ax + m, ay + m, (unsigned)(aw - 2 * m), (unsigned)(ah - 2 * m),
                      bx + m, by + m, (unsigned)(bw - 2 * m), (unsigned)(bh - 2 * m));
}
