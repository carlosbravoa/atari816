/* hg_bob.c - hgame: blitter sprites ("bobs") over a background image: at hg_end, the old
 * places of the bobs that changed are put back from the background, then every shown bob
 * is drawn, all in the frame's list (in the vertical blank: no flicker). */
#include "hg_int.h"

typedef struct {
    const hg_image *img;
    unsigned frame;
    int x, y;                   /* now */
    int ox, oy;                 /* where it was drawn */
    unsigned ow, oh;
    unsigned char on, drawn, changed;
} bob;

static bob bobs[HG_BOBS];
static const hg_image *bg;
static int bgx, bgy;
static unsigned char anychange, redraw;

static unsigned reserved, gen;

/* the background of the screen rectangle (x, y, w, h): its part over the background
 * image (outside it nothing is put back) */
static void restore(int x, int y, unsigned w, unsigned h)
{
    int x0 = x, y0 = y, x1 = x + (int)w, y1 = y + (int)h;
    int bx1, by1;
    unsigned key;
    if (!bg)
        return;
    bx1 = bgx + (int)bg->w;
    by1 = bgy + (int)(bg->h * bg->n);
    if (x0 < bgx)
        x0 = bgx;
    if (y0 < bgy)
        y0 = bgy;
    if (x1 > bx1)
        x1 = bx1;
    if (y1 > by1)
        y1 = by1;
    if (x0 >= x1 || y0 >= y1)
        return;
    key = bg->key;                      /* (the background is copied, never keyed) */
    ((hg_image *)bg)->key = HG_NONE;
    hg_draw_part(bg, (unsigned)(x0 - bgx), (unsigned)(y0 - bgy), (unsigned)(x1 - x0),
                 (unsigned)(y1 - y0), x0, y0);
    ((hg_image *)bg)->key = key;
}

/* an empty sheet record (the kernel leaves it out) */
static void empty(unsigned i)
{
    hz_sheetrec __far *r = &hg__sq[i];
    r->sheet = 0;
    r->op = SH_FILL;
    r->c = 0;
    r->zero = 0;
    r->sx = r->sy = r->w = r->h = 0;
    r->x = r->y = 0;
}

/* hg_begin: the frame's first records are kept for putting back the background under
 * the bobs drawn now, so that what the game draws this frame goes over them */
static void begin(void)
{
    unsigned i, k = 0;
    reserved = 0;
    if (!bg || !bg->sheet)
        return;
    for (i = 0; i < HG_BOBS; i++)
        if (bobs[i].drawn)
            ++k;
    if (!k || hg__qn)
        return;
    for (i = 0; i < k; i++)
        empty(i);
    hg__qn = k;
    hg__nruns = 1;
    hg__runs[0] = 0x8000;
    hg__runkind = 1;
    reserved = k;
    gen = hg__flushes;
}

static void end(void)
{
    unsigned i, qn, nruns, kind, n;
    bob *b;
    int drawn_over = hg__qn > reserved;

    if (!anychange && !redraw && !drawn_over) {
        if (reserved && hg__qn == reserved && gen == hg__flushes) {
            hg__qn = 0;                         /* nothing changed: nothing to send */
            hg__nruns = 0;
            hg__qpix = 0;
        }
        return;
    }
    if (reserved && gen == hg__flushes) {
        /* the old places into the kept records (then empty ones, if fewer) */
        qn = hg__qn;
        nruns = hg__nruns;
        kind = hg__runkind;
        hg__qn = 0;
        hg__nruns = 0;
        for (i = 0, b = bobs; i < HG_BOBS; i++, b++)
            if (b->drawn && hg__qn < reserved)
                restore(b->ox, b->oy, b->ow, b->oh);
        for (n = hg__qn; n < reserved; n++)
            empty(n);
        hg__qn = qn;
        hg__nruns = nruns;
        hg__runs[0] = 0x8000;
        hg__runkind = kind;
    } else {
        for (i = 0, b = bobs; i < HG_BOBS; i++, b++)
            if (b->drawn)
                restore(b->ox, b->oy, b->ow, b->oh);
    }
    for (i = 0, b = bobs; i < HG_BOBS; i++, b++) {
        b->changed = 0;
        b->drawn = 0;
        if (!b->on)
            continue;
        hg_draw(b->img, b->frame, b->x, b->y);
        b->ox = b->x;
        b->oy = b->y;
        b->ow = b->img->w;
        b->oh = b->img->h;
        b->drawn = 1;
    }
    anychange = redraw = 0;
}

static void hooks(void)
{
    hg__hook_bobs = end;
    hg__hook_bobs_begin = begin;
}

void hg_bob_background(const hg_image *img, int x, int y)
{
    bg = img;
    bgx = x;
    bgy = y;
    hooks();
}

void hg_bob(unsigned n, const hg_image *img, unsigned frame, int x, int y)
{
    bob *b;
    if (n >= HG_BOBS || !img || frame >= img->n) {
        hg__fail("hg_bob", n >= HG_BOBS ? "bobs are 0-31" : "no image or no such frame");
        return;
    }
    hooks();
    b = &bobs[n];
    if (b->on && b->img == img && b->frame == frame && b->x == x && b->y == y)
        return;
    b->img = img;
    b->frame = frame;
    b->x = x;
    b->y = y;
    b->on = 1;
    b->changed = 1;
    anychange = 1;
}

void hg_bob_hide(unsigned n)
{
    if (n >= HG_BOBS) {
        hg__fail("hg_bob_hide", "bobs are 0-31");
        return;
    }
    if (bobs[n].on) {
        bobs[n].on = 0;
        bobs[n].changed = 1;
        anychange = 1;
    }
}

void hg_bob_redraw(void)
{
    redraw = 1;
}
