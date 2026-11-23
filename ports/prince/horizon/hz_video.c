/* hz_video.c - Prince of Persia's drawing on the Atari816: what upstream's seg009.c did
 * with SDL surfaces, done by the blitter (Ali) on one 8-bit framebuffer.
 *
 * The DOS game drew 16-colour images into a 256-colour VGA screen, each image set (chtab)
 * with its own palette row; tools/mkdata.py kept that: an image's pixels are already the
 * VGA colours (row * 16 + colour, 0 transparent), so the palette here is the DOS game's.
 * Every image is in one atlas in far memory (a kernel sheet); the screens the game draws
 * into (onscreen_surface_, offscreen_surface, the peels) are rectangles of the framebuffer,
 * which is a sheet too. So every blit is one sheet_draw record (a copy, or a keyed copy
 * skipping 0), a fill is one record, and a one-colour blit (text, masks, blood) is a
 * draw_list "expand" record of the image's 1-bit mask; they are queued and sent in order.
 * The shadow's XOR and nothing else is done by the CPU.
 *
 * The screen is 320 x 180: the room (192 rows) is shown 172 rows at a time, following the
 * kid, and the status line (rows 192-199) is below a split. Pictures of the whole screen
 * (the title, the story, the cut scenes) are shown from row 20. */
#include <string.h>
#include <stdio.h>
#include <hgame.h>
#include "common.h"
#include "hz_plat.h"

unsigned char hzv_fb_sheet, hzv_part_sheet[HZD_PARTS];
unsigned hzv_fbbank;
unsigned char hzv_view_game;
static unsigned char flipped;           /* flip_screen: the offscreen buffer upside down */

static SDL_Surface on_s = {320, 200, 0, HZ_ON_Y};
static SDL_Surface off_s = {320, 200, 0, HZ_OFF_Y};

/* where a surface's pixels are: its sheet and place in it */
static unsigned char src_pos(const SDL_Surface *s, unsigned *x, unsigned *y)
{
    if (s->b >= HZS_MIRROR) {
        const unsigned __far *r = (const unsigned __far *)(hzd_dir + s->a);
        unsigned yy;
        if (s->b == HZS_MIRROR && r[4] != 0xFFFF) {
            *x = r[4];
            yy = r[5];
        } else {
            *x = r[2];
            yy = r[3];
        }
        *y = yy & 255;                  /* (parts of 256 rows: hzd_init checks) */
        return hzv_part_sheet[yy >> 8];
    }
    *x = s->a;
    *y = s->b;
    return hzv_fb_sheet;
}

/* ---------------------------------------------------------------- the queues */

#define QN 32
static hz_sheetrec q[QN];
static unsigned qn;
static hz_sheetrec *qp = q;             /* &q[qn], &dq[dqn]: (an index costs a multiply) */
static hz_drawrec dq[8];
static unsigned dqn;
static hz_drawrec *dqp = dq;
static unsigned char ali;               /* sent, maybe not drawn yet */
unsigned long hzv_recs;                 /* (statistics) */

static void send_sheet(void)
{
    if (qn) {
        static unsigned char told;
        int r = hz_sheet_draw(hg_win, qn, q);
        if (r < 0 && told < 8) {        /* (a bad record: the whole call is refused) */
            unsigned i;
            ++told;
            {
                unsigned long px = 0;
                for (i = 0; i < qn; i++)
                    px += (unsigned long)q[i].w * q[i].h;
                printf("prince: sheet_draw refused (%u), %u records, %lu pixels\n", hz_errno, qn, px);
            }
            for (i = 0; i < qn; i++) {
                if (hz_sheet_draw(hg_win, 1, &q[i]) < 0)
                    printf("  bad (%u): sheet %u op %u c %u sx %u sy %u w %u h %u x %d y %d (fb %u)\n",
                           hz_errno, q[i].sheet, q[i].op, q[i].c, q[i].sx, q[i].sy, q[i].w, q[i].h,
                           q[i].x, q[i].y, hzv_fb_sheet);
            }
        }
        qn = 0;
        qp = q;
        ali = 1;
    }
}

static void send_draw(void)
{
    if (dqn) {
        hz_draw_list(hg_win, dqn, dq);
        dqn = 0;
        dqp = dq;
        ali = 1;
    }
}

void hzv_flush(void)
{
    send_sheet();
    send_draw();
}

void hzv_sync(void)
{
    hzv_flush();
    if (ali) {
        hz_list_wait(0);
        ali = 0;
    }
}

static hz_sheetrec *srec(void)
{
    if (dqn)
        send_draw();
    if (qn == QN)
        send_sheet();
    ++hzv_recs;
    ++qn;
    return qp++;
}

static hz_drawrec *drec(void)
{
    if (qn)
        send_sheet();
    if (dqn == 8)
        send_draw();
    ++hzv_recs;
    ++dqn;
    return dqp++;
}

/* ---------------------------------------------------------------- clipping */

static const SDL_Surface *clip_surf;    /* set_clip_rect's surface and rectangle */
static rect_type clip;

void set_clip_rect(const rect_type *rect)
{
    clip_surf = current_target_surface;
    clip = *rect;
}

void reset_clip_rect(void)
{
    clip_surf = NULL;
}

/* the rectangle (x, y, w, h) in target coordinates cut to the target and its clip
 * rectangle: 0 if nothing is left; *dx, *dy what was cut on the left and the top */
static int cut(const SDL_Surface *t, int *x, int *y, int *w, int *h, int *dx, int *dy)
{
    int l = 0, tp = 0, r = t->w, b = t->h;
    if (t == clip_surf) {
        if (clip.left > l) l = clip.left;
        if (clip.top > tp) tp = clip.top;
        if (clip.right < r) r = clip.right;
        if (clip.bottom < b) b = clip.bottom;
    }
    *dx = *dy = 0;
    if (*x < l) { *dx = l - *x; *w -= *dx; *x = l; }
    if (*y < tp) { *dy = tp - *y; *h -= *dy; *y = tp; }
    if (*x + *w > r) *w = r - *x;
    if (*y + *h > b) *h = b - *y;
    return *w > 0 && *h > 0;
}

/* a copy (key 0xFFFF) or a keyed copy of src's rectangle to the target */
static void blit_to(const SDL_Surface *t, const SDL_Surface *src, int sx, int sy, int w, int h,
                    int x, int y, unsigned key)
{
    int dx, dy;
    hz_sheetrec *r;
    if (!t || !src || !cut(t, &x, &y, &w, &h, &dx, &dy))
        return;
    {
        unsigned px, py;
        unsigned char sh = src_pos(src, &px, &py);
        r = srec();
        r->sheet = sh;
        r->sx = px + sx + dx;
        r->sy = py + sy + dy;
    }
    r->op = key == 0xFFFF ? SH_COPY : SH_KEY;
    r->c = (unsigned char)key;
    r->zero = 0;
    r->w = w;
    r->h = h;
    r->x = (short)(t->a + x);
    r->y = (short)(t->b + y);
}

static void fill_to(const SDL_Surface *t, int x, int y, int w, int h, unsigned c)
{
    int dx, dy;
    hz_sheetrec *r;
    if (!t || !cut(t, &x, &y, &w, &h, &dx, &dy))
        return;
    r = srec();
    memset(r, 0, sizeof *r);
    r->op = SH_FILL;
    r->c = (unsigned char)c;
    r->w = w;
    r->h = h;
    r->x = (short)(t->a + x);
    r->y = (short)(t->b + y);
}

/* ---------------------------------------------------------------- set-up */

/* The full screen at once (before the data is loaded): hgame's framebuffer of 768 rows of
 * 512 bytes, also a sheet; and the loading screen in hgame's own font (the game's is in
 * the data being loaded), its bar moved by hzd_read_far. */
static unsigned char screen_up;
static unsigned bar_w;
#define BAR_X 60
#define BAR_Y (20 + 118)
#define BAR_W 200

static void text_c(int y, const char *s, unsigned ink)
{
    hg_text((int)(320 - hg_text_width(s)) / 2, 20 + y, s, ink);
}

int hzv_screen(void)
{
    hz_sheetnew sn;
    int r;
    static const unsigned char rgb[] = {168, 168, 168, 252, 252, 252, 252, 252, 84};
    if (screen_up)
        return 0;
    if (hg_screen_fb(HG_320X180, "Prince of Persia", HZ_STRIDE, HZ_ROWS) < 0)
        return -1;
    hg_palette_black();
    hzv_fbbank = hg_fb_bank;
    /* the framebuffer as a sheet (copies inside it) */
    HZ_U24B(sn.addr, hzv_fbbank, 0);
    sn.zero = 0;
    sn.stride = HZ_STRIDE;
    sn.w = HZ_STRIDE;
    sn.h = HZ_ROWS;
    r = hz_sheet_new(&sn);
    if (r <= 0)
        return -1;
    hzv_fb_sheet = (unsigned char)r;
    hzv_show();                         /* (rows 20-199, as the pictures) */
    /* the loading screen: colours 7 and 15 as the game's (light grey, white), 14 yellow */
    hg_palette(7, 1, rgb);
    hg_palette(15, 1, rgb + 3);
    hg_palette(14, 1, rgb + 6);
    text_c(40, "PRINCE OF PERSIA", 15);
    text_c(56, "for the Atari816", 7);
    text_c(100, "Loading the game...", 7);
    hg_rect(BAR_X - 2, BAR_Y - 2, BAR_W + 4, 12, 7);
    hg_flush(1);
    screen_up = 1;
    return 0;
}

void hzv_loading(unsigned long done, unsigned long total)
{
    unsigned w;
    if (!screen_up || !total)
        return;
    if (done > total)
        done = total;
    w = (unsigned)((done >> 8) * BAR_W / ((total >> 8) + 1));
    if (w > bar_w) {
        hg_fill(BAR_X + (int)bar_w, BAR_Y, w - bar_w, 8, 14);
        hg_flush(0);
        bar_w = w;
    }
}

/* the rest, once the data is in memory (set_gr_mode) */
int hzv_init(void)
{
    hz_sheetnew sn;
    unsigned k;
    int r;

    if (hzv_screen() < 0)
        return -1;
    hg_flush(1);
    /* the atlas's parts (hz_data.c has loaded them) */
    for (k = 0; k < hzd_nparts; k++) {
        HZ_U24B(sn.addr, (unsigned)(hzd_part_addr[k] >> 16), 0);
        sn.zero = 0;
        sn.stride = hzd_atlas_w;
        sn.w = hzd_atlas_w;
        sn.h = hzd_atlas_h - k * hzd_part < hzd_part ? hzd_atlas_h - k * hzd_part : hzd_part;
        r = hz_sheet_new(&sn);
        if (r <= 0)
            return -1;
        hzv_part_sheet[k] = (unsigned char)r;
    }
    /* black below the screen (the loading screen stays until the first screen's) */
    for (k = HZ_OFF_Y; k < HZ_ROWS; k += 256) {
        hz_sheetrec *f = srec();
        memset(f, 0, sizeof *f);
        f->w = HZ_STRIDE;
        f->h = HZ_ROWS - k > 256 ? 256 : HZ_ROWS - k;
        f->y = (short)k;
    }
    hzv_sync();
    onscreen_surface_ = &on_s;
    hzv_show();
    return 0;
}

/* ---------------------------------------------------------------- the palette */

static unsigned dirty_lo = 0xFFFF, dirty_hi;
static unsigned char flash_on;
static unsigned char flash_rgb[3];

static unsigned pal_gen;                /* +1 at every change of the game's palette */

static void pal_dirty(unsigned first, unsigned n)
{
    if (first < dirty_lo)
        dirty_lo = first;
    if (first + n > dirty_hi)
        dirty_hi = first + n;
}

void hzv_pal_dirty(unsigned first, unsigned n)
{
    ++pal_gen;
    if (first < dirty_lo)
        dirty_lo = first;
    if (first + n > dirty_hi)
        dirty_hi = first + n;
}

void set_pal(int index, int red, int green, int blue)
{
    palette[index].r = (byte)red;
    palette[index].g = (byte)green;
    palette[index].b = (byte)blue;
    hzv_pal_dirty((unsigned)index, 1);
}

/* the shadow palette to the hardware (after a change), 6-bit components as the VGA's */
static void send_palette(void)
{
    unsigned char *rgb = hzd_buf;
    unsigned i, n, first;
    if (dirty_lo == 0xFFFF)
        return;
    for (first = dirty_lo; first < dirty_hi; first += n) {
        n = dirty_hi - first;
        if (n > 160)
            n = 160;
        for (i = 0; i < n; i++) {
            const rgb_type *c = &palette[first + i];
            rgb[3 * i] = (unsigned char)(c->r << 2);
            rgb[3 * i + 1] = (unsigned char)(c->g << 2);
            rgb[3 * i + 2] = (unsigned char)(c->b << 2);
        }
        if (first == 0 && flash_on)
            memcpy(rgb, flash_rgb, 3);
        hg_palette(first, n, rgb);
    }
    dirty_lo = 0xFFFF;
    dirty_hi = 0;
}

/* A flash (set_bg_attr): the DOS game changes the background colour, entry 0; every pixel
 * of colour 0 (the black of the rooms) takes the flash's colour. */
void set_bg_attr(int vga_pal_index, int hc_pal_index)
{
    if (!enable_flash || vga_pal_index != 0)
        return;
    flash_on = hc_pal_index != 0;
    flash_rgb[0] = (unsigned char)(palette[hc_pal_index].r << 2);
    flash_rgb[1] = (unsigned char)(palette[hc_pal_index].g << 2);
    flash_rgb[2] = (unsigned char)(palette[hc_pal_index].b << 2);
    hzv_pal_dirty(0, 1);
}

/* ---------------------------------------------------------------- the view */

static hz_fsscroll cur;
int hzv_view_y = 20;
unsigned char hzv_snap;               /* the view at its place at once (the tests' pictures) */
#define view_y hzv_view_y
static unsigned view_f;

void hzv_show(void)
{
    hz_fsscroll s;
    unsigned f = hz_frame(), steps = f - view_f;
    int target = view_y;
    view_f = f;
    /* a room: the game made its offscreen buffer the room's height (rect_top, 192 rows);
     * the title, the story and the cut scenes use the whole 200 rows */
    hzv_view_game = off_s.h == 192 && !is_cutscene;
    if (hzv_view_game) {
        if (Kid.room == drawn_room && Kid.room != 0) {
            target = Kid.y - 25 - 86;
            if (target < 0) target = 0;
            if (target > 20) target = 20;
        }
        if (steps > 10)
            steps = 10;
        while (steps-- && view_y != target)
            view_y += view_y < target ? 1 : -1;
        if (different_room || need_full_redraw || hzv_snap)
            view_y = target;
    } else {
        view_y = 20;                    /* (pictures: their top 20 rows are a border) */
    }
    send_palette();
    memset(&s, 0, sizeof s);
    s.y = HZ_ON_Y + (unsigned)view_y;
    if (hzv_view_game) {
        s.y2 = HZ_ON_Y + 192;
        s.split = 172 * 2;              /* (Marga counts 360 lines) */
        s.ctrl = 2;                     /* FSC_SPLIT */
    }
    if (memcmp(&s, &cur, sizeof s)) {
        hz_fs_scroll(&s);
        cur = s;
    }
}

void update_screen(void)
{
    hzv_flush();
    hzv_show();
}

/* ---------------------------------------------------------------- SDLPoP's drawing calls */

surface_type *make_offscreen_buffer(const rect_type *rect)
{
    off_s.w = rect->right;
    off_s.h = rect->bottom;
    return &off_s;
}

void free_surface(surface_type *surface)
{
    (void)surface;
}

SDL_Surface *get_final_surface(void)
{
    return onscreen_surface_;
}

void flip_screen(surface_type *surface)
{
    if (surface == &off_s)
        flipped ^= 1;
}

void method_1_blit_rect(surface_type *target_surface, surface_type *source_surface,
                        const rect_type *target_rect, const rect_type *source_rect, int blit)
{
    int w = source_rect->right - source_rect->left, h = source_rect->bottom - source_rect->top;
    unsigned key = blit == blitters_0_no_transp ? 0xFFFF : 0;
    if (source_surface == &off_s && flipped) {
        /* upside down: row by row from the mirrored rows */
        int y;
        for (y = 0; y < h; y++)
            blit_to(target_surface, source_surface, source_rect->left,
                    off_s.h - 1 - (source_rect->top + y), w, 1,
                    target_rect->left, target_rect->top + y, key);
        return;
    }
    blit_to(target_surface, source_surface, source_rect->left, source_rect->top, w, h,
            target_rect->left, target_rect->top, key);
}

/* the image in one colour where it is not transparent: its mask expanded by the blitter */
image_type *method_3_blit_mono(image_type *image, int xpos, int ypos, int blitter, byte color)
{
    const SDL_Surface *t = current_target_surface;
    int x = xpos, y = ypos, w = image->w, h = image->h, dx, dy;
    unsigned stride = ((unsigned)image->w + 7) >> 3;
    unsigned long a;
    hz_drawrec *r;
    (void)blitter;
    if (image->b != HZS_IMAGE || !t || !cut(t, &x, &y, &w, &h, &dx, &dy))
        return image;
    a = hzd_masks + *(const unsigned long __far *)(hzd_dir + image->a + 12) +
        (unsigned long)dy * stride + (unsigned)(dx >> 3);
    r = drec();
    memset(r, 0, sizeof *r);
    r->op = LS_EXPANDK;
    r->flags = (unsigned char)((dx & 7) << 4);
    r->c1 = color;
    r->x = (short)(t->a + x);
    r->y = (short)(t->b + y);
    r->w = w;
    r->h = h;
    HZ_U24B(r->u.s.src, (unsigned)(a >> 16), (unsigned)a);
    r->stride = stride;
    return image;
}

const rect_type *method_5_rect(const rect_type *rect, int blit, byte color)
{
    (void)blit;
    fill_to(current_target_surface, rect->left, rect->top, rect->right - rect->left,
            rect->bottom - rect->top, color);
    return rect;
}

void draw_rect_with_alpha(const rect_type *rect, byte color, byte alpha)
{
    (void)alpha;
    method_5_rect(rect, 0, color);
}

void draw_rect_contours(const rect_type *rect, byte color)
{
    (void)rect; (void)color;
}

image_type *method_6_blit_img_to_scr(image_type *image, int xpos, int ypos, int blit)
{
    if (image == NULL)
        return NULL;
    if (blit == blitters_9_black)
        return method_3_blit_mono(image, xpos, ypos, blitters_9_black, 0);
    if (blit == blitters_3_xor) {
        hzv_xor(image, xpos, ypos);
        return image;
    }
    blit_to(current_target_surface, image, 0, 0, image->w, image->h, xpos, ypos,
            blit == blitters_0_no_transp ? 0xFFFF : 0);
    return image;
}

void draw_image_transp(image_type *image, image_type *mask, int xpos, int ypos)
{
    (void)mask;
    method_6_blit_img_to_scr(image, xpos, ypos, blitters_10h_transp);
}

void draw_image_transp_vga(image_type *image, int xpos, int ypos)
{
    method_6_blit_img_to_scr(image, xpos, ypos, blitters_10h_transp);
}

/* the mirrored copy of an image (tools/mkdata.py made one for each image set drawn facing
 * both ways): seg008's draw_mid asks for it as upstream's hflip() made one */
image_type *hz_hflip(image_type *image)
{
    static SDL_Surface m[4];
    static unsigned char k;
    SDL_Surface *r = &m[k++ & 3];
    *r = *image;
    if (image->b == HZS_IMAGE)
        r->b = HZS_MIRROR;
    return r;
}

/* XOR (the shadow's second blit), by the CPU, as SDLPoP does it: in RGB. SDLPoP xors the
 * image's colours (24 bits) into the screen's, so the result is a colour of no palette
 * (the shadow's outline: blue, green, yellow over a red and white kid's). Here each pair
 * (the screen's colour index, the image's colour) gets a palette entry of the colour
 * rgb(screen) ^ rgb(image): an entry that already has it, else one of the 32 the game never
 * uses (rows 4 and 15), else (all 32 taken in one palette) the nearest. The pairs are
 * remembered until the palette changes (a fade, a level's colours): about 20 in a frame.
 * (The port xored the low 4 bits of the indices before: the outline in the kid's colours,
 * 114 pixels of a shadow standing differed from the PC's picture.) */
static unsigned char __far xlut[4096];  /* (screen index << 4 | image colour) -> entry, 0 */
static unsigned xlut_gen = 0xFFFF;
static unsigned char xlut_row, pool_n;
static const unsigned char pool_row[2] = {4, 15};

static unsigned char xor_entry(unsigned d, unsigned p)
{
    const rgb_type *a = &palette[d], *b = &palette[p];
    unsigned char r = (unsigned char)(a->r ^ b->r), g = (unsigned char)(a->g ^ b->g),
                  bl = (unsigned char)(a->b ^ b->b);
    unsigned i, best = 1;
    unsigned long bd = 0xFFFFFFFFUL;
    for (i = 1; i < 256; i++) {         /* (0: the flashes' entry) */
        const rgb_type *c = &palette[i];
        if (c->r == r && c->g == g && c->b == bl)
            return (unsigned char)i;
    }
    if (pool_n < 32) {
        i = pool_row[pool_n >> 4] * 16 + (pool_n & 15);
        ++pool_n;
        palette[i].r = r;
        palette[i].g = g;
        palette[i].b = bl;
        pal_dirty(i, 1);
        return (unsigned char)i;
    }
    for (i = 1; i < 256; i++) {
        const rgb_type *c = &palette[i];
        int dr = (int)c->r - r, dg = (int)c->g - g, db = (int)c->b - bl;
        unsigned long e = (unsigned long)(dr * dr) + (unsigned long)(dg * dg) + (unsigned long)(db * db);
        if (e < bd) {
            bd = e;
            best = i;
        }
    }
    return (unsigned char)best;
}

void hzv_xor(const SDL_Surface *img, int xpos, int ypos)
{
    const SDL_Surface *t = current_target_surface;
    int x = xpos, y = ypos, w = img->w, h = img->h, dx, dy, i, j;
    if (!t || !cut(t, &x, &y, &w, &h, &dx, &dy))
        return;
    unsigned px, py, part = 0;
    unsigned char sh = src_pos(img, &px, &py);
    for (i = 0; i < (int)hzd_nparts; i++)
        if (hzv_part_sheet[i] == sh)
            part = (unsigned)i;
    hzv_sync();
    for (j = 0; j < h; j++) {
        unsigned long sa = hzd_part_addr[part] + (unsigned long)(py + dy + j) * hzd_atlas_w + px + dx;
        unsigned long da = ((unsigned long)hzv_fbbank << 16) +
                           ((unsigned long)(t->b + y + j) << 9) + t->a + x;
        const unsigned char __far *s = (const unsigned char __far *)sa;
        unsigned char __far *d = (unsigned char __far *)da;
        for (i = 0; i < w; i++) {
            unsigned char p = s[i];
            if (p) {
                unsigned k;
                unsigned char e;
                if (xlut_gen != pal_gen || (p >> 4) != xlut_row) {
                    hz_far_set(xlut, 0, sizeof xlut);
                    xlut_gen = pal_gen;
                    xlut_row = (unsigned char)(p >> 4);
                    pool_n = 0;
                }
                k = (unsigned)d[i] << 4 | (p & 15);
                e = xlut[k];
                if (!e)
                    e = xlut[k] = xor_entry(d[i], p);
                d[i] = e;
            }
        }
    }
}

/* ---------------------------------------------------------------- peels (save-unders) */

/* The peels' area (rows HZ_PEEL_Y..): a stack of shelves. The game frees its peels in the
 * reverse order (restore_peels), the start-up dialog's stays for good: a peel freed on top
 * pops the stack, one freed below waits until those above it go. */
#define NPEELS 64
static struct pst { unsigned x, y, h; SDL_Surface *s; unsigned char freed; } pstack[NPEELS];
static unsigned pn;                     /* peels on the stack */
static unsigned peel_x, peel_y = HZ_PEEL_Y, peel_h;

peel_type *read_peel_from_screen(const rect_type *rect)
{
    peel_type *p = calloc(1, sizeof(peel_type));
    SDL_Surface *s = malloc(sizeof(SDL_Surface));
    int w = rect->right - rect->left, h = rect->bottom - rect->top;
    if (!p || !s) {
        printf("prince: no memory for a peel\n");
        quit(1);
    }
    if (w < 0) w = 0;
    if (h < 0) h = 0;
    if (pn == NPEELS) {
        printf("prince: too many peels\n");
        quit(1);
    }
    pstack[pn].x = peel_x;
    pstack[pn].y = peel_y;
    pstack[pn].h = peel_h;
    pstack[pn].s = s;
    pstack[pn].freed = 0;
    ++pn;
    if (peel_x + (unsigned)w > HZ_STRIDE) {
        peel_x = 0;
        peel_y += peel_h;
        peel_h = 0;
    }
    if (peel_y + (unsigned)h > HZ_ROWS) {
        printf("prince: the peels' area is full\n");
        quit(1);
    }
    s->w = w;
    s->h = h;
    s->a = peel_x;
    s->b = peel_y;
    peel_x += (unsigned)w;
    if ((unsigned)h > peel_h)
        peel_h = (unsigned)h;
    p->rect = *rect;
    p->peel = s;
    /* the screen's rectangle into it: only the part on the screen (the rest is never
     * restored: drawing is cut at the screen's edges) */
    if (current_target_surface) {
        const SDL_Surface *t = current_target_surface;
        int l = rect->left, tp = rect->top, r = rect->right, b = rect->bottom;
        SDL_Surface whole;
        if (l < 0) l = 0;
        if (tp < 0) tp = 0;
        if (r > t->w) r = t->w;
        if (b > t->h) b = t->h;
        whole.a = 0;
        whole.b = 0;
        whole.w = HZ_STRIDE;
        whole.h = HZ_ROWS;
        if (r > l && b > tp)
            blit_to(&whole, t, l, tp, r - l, b - tp, (int)s->a + (l - rect->left),
                    (int)s->b + (tp - rect->top), 0xFFFF);
    }
    return p;
}

void restore_peel(peel_type *peel_ptr)
{
    method_6_blit_img_to_scr(peel_ptr->peel, peel_ptr->rect.left, peel_ptr->rect.top, 0);
    free_peel(peel_ptr);
}

void free_peel(peel_type *peel_ptr)
{
    unsigned i;
    for (i = 0; i < pn; i++)
        if (pstack[i].s == peel_ptr->peel)
            pstack[i].freed = 1;
    while (pn && pstack[pn - 1].freed) {
        --pn;
        peel_x = pstack[pn].x;
        peel_y = pstack[pn].y;
        peel_h = pstack[pn].h;
    }
    free(peel_ptr->peel);
    free(peel_ptr);
}

/* ---------------------------------------------------------------- fades (the palette's) */

/* fade_in_2 and fade_out_2's buffer (1.5 KB of the 12 KB heap): a key in their loop can
 * start the game (do_paused, process_key, start_game: a longjmp), which never comes back
 * to free it (upstream leaks it too); start_game calls hzv_fade_abandoned */
static palette_fade_type *fade2;

void hzv_fade_abandoned(void)
{
    if (fade2) {
        set_pal_256(fade2->original_pal);
        free(fade2);
        fade2 = NULL;
    }
}

void fade_in_2(surface_type *source_surface, int which_rows)
{
    palette_fade_type *b = make_pal_buffer_fadein(source_surface, which_rows, 2);
    fade2 = b;
    while (fade_in_frame(b) == 0) {
        process_events();
        do_paused();
    }
    fade2 = NULL;
    pal_restore_free_fadein(b);
}

palette_fade_type *make_pal_buffer_fadein(surface_type *source_surface, int which_rows, int wait_time)
{
    palette_fade_type *b = malloc(sizeof(palette_fade_type));
    word row, mask;
    (void)source_surface;
    b->which_rows = (word)which_rows;
    b->wait_time = (word)wait_time;
    b->fade_pos = 0x40;
    b->proc_restore_free = &pal_restore_free_fadein;
    b->proc_fade_frame = &fade_in_frame;
    read_palette_256(b->original_pal);
    memcpy(b->faded_pal, b->original_pal, sizeof(b->faded_pal));
    for (row = 0, mask = 1; row < 16; ++row, mask <<= 1) {
        if (which_rows & mask) {
            memset(b->faded_pal + (row << 4), 0, sizeof(rgb_type[16]));
            set_pal_arr(row << 4, 16, NULL);
        }
    }
    /* the picture onto the screen once; the palette brings it up */
    method_1_blit_rect(onscreen_surface_, offscreen_surface, &screen_rect, &screen_rect, 0);
    return b;
}

void pal_restore_free_fadein(palette_fade_type *b)
{
    set_pal_256(b->original_pal);
    free(b);
    method_1_blit_rect(onscreen_surface_, offscreen_surface, &screen_rect, &screen_rect, 0);
}

int fade_in_frame(palette_fade_type *b)
{
    word start, mask, col;
    start_timer(timer_1, b->wait_time);
    --b->fade_pos;
    for (start = 0, mask = 1; start < 0x100; start += 0x10, mask <<= 1) {
        if (b->which_rows & mask) {
            rgb_type *o = b->original_pal + start, *f = b->faded_pal + start;
            for (col = 0; col < 16; ++col) {
                if (o[col].r > b->fade_pos) ++f[col].r;
                if (o[col].g > b->fade_pos) ++f[col].g;
                if (o[col].b > b->fade_pos) ++f[col].b;
            }
            set_pal_arr(start, 16, f);
        }
    }
    do_simple_wait(1);
    return b->fade_pos == 0;
}

void fade_out_2(int rows)
{
    palette_fade_type *b = make_pal_buffer_fadeout(rows, 2);
    fade2 = b;
    while (fade_out_frame(b) == 0) {
        process_events();
        do_paused();
    }
    fade2 = NULL;
    pal_restore_free_fadeout(b);
}

palette_fade_type *make_pal_buffer_fadeout(int which_rows, int wait_time)
{
    palette_fade_type *b = malloc(sizeof(palette_fade_type));
    b->which_rows = (word)which_rows;
    b->wait_time = (word)wait_time;
    b->fade_pos = 0;
    b->proc_restore_free = &pal_restore_free_fadeout;
    b->proc_fade_frame = &fade_out_frame;
    read_palette_256(b->original_pal);
    memcpy(b->faded_pal, b->original_pal, sizeof(b->faded_pal));
    method_1_blit_rect(onscreen_surface_, offscreen_surface, &screen_rect, &screen_rect, 0);
    return b;
}

void pal_restore_free_fadeout(palette_fade_type *b)
{
    surface_type *s = current_target_surface;
    current_target_surface = onscreen_surface_;
    draw_rect(&screen_rect, color_0_black);
    current_target_surface = s;
    hzv_flush();
    set_pal_256(b->original_pal);
    free(b);
}

int fade_out_frame(palette_fade_type *b)
{
    word done = 1, start, mask, col;
    ++b->fade_pos;
    start_timer(timer_1, b->wait_time);
    for (start = 0, mask = 1; start < 0x100; start += 0x10, mask <<= 1) {
        if (b->which_rows & mask) {
            rgb_type *f = b->faded_pal + start;
            for (col = 0; col < 16; ++col) {
                if (f[col].r) { --f[col].r; done = 0; }
                if (f[col].g) { --f[col].g; done = 0; }
                if (f[col].b) { --f[col].b; done = 0; }
            }
            set_pal_arr(start, 16, f);
        }
    }
    do_simple_wait(timer_1);
    return done;
}

void read_palette_256(rgb_type *target)
{
    memcpy(target, palette, sizeof(rgb_type[256]));
}

void set_pal_256(rgb_type *source)
{
    memcpy(palette, source, sizeof(rgb_type[256]));
    hzv_pal_dirty(0, 256);
}

void set_hc_pal(void)
{
    set_pal_arr(0, 16, custom->vga_palette);
}

/* the guards' colours, the level colours (1.3), the title's colour 14: the image set's
 * palette row (the VGA's way) */
void set_chtab_palette(chtab_type *chtab, byte *colors, int n_colors)
{
    int row, i;
    if (chtab == NULL || !chtab->chtab_palette_bits)
        return;
    row = find_first_pal_row(chtab->chtab_palette_bits);
    for (i = 1; i < n_colors && i < 16; i++)
        set_pal(row * 16 + i, colors[3 * i], colors[3 * i + 1], colors[3 * i + 2]);
}
