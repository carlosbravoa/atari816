/* hz_video.c - the screen on Horizon (see hz_plat.h): three pages in one framebuffer,
 * page flips by Marga's scroll registers, the palette, and the renderer's fast paths
 * (FbOps): the spans by hz_spans.s, the copies from the underlay and the dashboard by
 * Ali (the blitter). */
#include <string.h>
#include <hgame.h>
#include <horizon.h>

#include "hz_plat.h"

#define PAGE_ROWS 200u
static const unsigned page_row[HZV_PAGES] = {0, 206, 410};
#define FB_ROWS 610u

unsigned hzv_fbbank;
FrameBuffer320x200 hzv_page[HZV_PAGES];
PagePrime hzv_prime[HZV_PAGES];
unsigned long hzv_blits;
bool hzv_nofast;                     /* /NOFAST: the C road pass (hz_main.c) */

static unsigned shown = 0, pending = 0xFFFF, pending_frame;
static hz_fsscroll scr;
static unsigned char pal_shown[768];
static bool pal_valid;

static hg_image *under_img;             /* the underlay (PlaySceneCache) */
static const uint8_t SR_FAR *under_px;
static hg_image *dash_img;              /* its dashboard band cache */
static const uint8_t SR_FAR *dash_px;
static hg_image *frag_img[4];           /* registered fragments (the dashboard) */
static const ImageFrame SR_FAR *frag_src[4];
static unsigned frag_base[4];
static unsigned nfrag;

static int page_of(const FrameBuffer320x200 *f)
{
    unsigned p;
    for (p = 0; p < HZV_PAGES; ++p)
        if (f->pixels == hzv_page[p].pixels)
            return (int)p;
    return -1;
}

static void hz_fb_spans(FrameBuffer320x200 *f, const PreparedSpan SR_FAR *spans, unsigned count,
                        bool right, uint8_t index)
{
    const uint32_t a = (uint32_t)f->pixels;
    hz_spans(spans, count, right ? 1 : 0, index, (unsigned)(a >> 16), (unsigned)a);
}

/* (Horizon 0.30) the spans by the blitter, one call for a pass (fill_runs with FR_GROUPS):
 * a job is a group, its shape's own PreparedSpan array in its colour, so the CPU writes 8
 * bytes a job and the kernel reads the spans where they are; Ali fills them while the
 * renderer goes on. The CPU path where the call is missing (before 0.30, REV $08 and older)
 * or with /NORUNS */
static hg_rungroup SR_FAR *grp;
static bool use_runs;
bool hzv_noruns;
static bool blits_out;                  /* records sent that may not be drawn yet */

static void hz_fb_span_jobs(FrameBuffer320x200 *f, const SpanJob *jobs, unsigned n)
{
    const uint32_t a = (uint32_t)f->pixels;
    if (use_runs) {
        const unsigned g = hz_span_groups(jobs, n, grp);
        if (g)
            hg_fill_groups_at(a, 64000u, grp, g);
        blits_out = true;
        return;
    }
    hz_span_jobs(jobs, n, (unsigned)(a >> 16), (unsigned)a);
}

unsigned long hzv_wait_ms, hzv_syncs;

static void blit_sync(FrameBuffer320x200 *f)
{
    (void)f;
    if (blits_out) {
        unsigned long t = (unsigned long)hz_uptime();
        hg_flush(1);
        hzv_wait_ms += (unsigned long)hz_uptime() - t;
        hzv_syncs++;
        blits_out = false;
    }
}

/* the image of a source framebuffer the blitter can copy from */
static hg_image *source_img(const FrameBuffer320x200 *u)
{
    if (under_img && u->pixels == under_px)
        return under_img;
    if (dash_img && u->pixels == dash_px)
        return dash_img;
    return 0;
}

static void hz_copy_rows(FrameBuffer320x200 *f, const FrameBuffer320x200 *u, unsigned y0,
                         unsigned y1)
{
    const int p = page_of(f);
    hg_image *img = source_img(u);
    if (p < 0 || !img) {
        unsigned y;
        blit_sync(f);
        for (y = y0; y < y1; ++y)
            hz_far_copy(f->pixels + y * 320u, u->pixels + y * 320u, 320);
        return;
    }
    hg_draw_part(img, 0, y0, 320, y1 - y0, 0, (int)(page_row[p] + y0));
    hg_flush(0);
    blits_out = true;
    ++hzv_blits;
}

static void hz_copy_rect(FrameBuffer320x200 *f, const FrameBuffer320x200 *u, unsigned x0,
                         unsigned y0, unsigned x1, unsigned y1)
{
    const int p = page_of(f);
    hg_image *img = source_img(u);
    if (p < 0 || !img) {
        unsigned y;
        blit_sync(f);
        for (y = y0; y < y1; ++y)
            hz_far_copy(f->pixels + y * 320u + x0, u->pixels + y * 320u + x0, x1 - x0);
        return;
    }
    hg_draw_part(img, x0, y0, x1 - x0, y1 - y0, (int)x0, (int)(page_row[p] + y0));
    hg_flush(0);
    blits_out = true;
    ++hzv_blits;
}

static bool hz_fragment(FrameBuffer320x200 *f, const ImageFrame SR_FAR *fragment,
                        unsigned palette_base)
{
    const int p = page_of(f);
    unsigned i;
    if (p < 0)
        return false;
    for (i = 0; i < nfrag; ++i)
        if (frag_src[i] == fragment && frag_base[i] == palette_base) {
            hg_draw(frag_img[i], 0, fragment->x_offset, (int)(page_row[p] + fragment->y_offset));
            hg_flush(0);
            blits_out = true;
            ++hzv_blits;
            return true;
        }
    return false;
}

/* the fragment as draw_fragment draws it: index base + p, 0 (the key) where it draws
 * nothing */
void hzv_register_fragment(const ImageFrame SR_FAR *fragment, unsigned palette_base)
{
    const unsigned max_index = SR_MIN(fragment->palette.color_count,
                                      palette_base <= 0xFF ? 0x100 - palette_base : 0);
    hg_image *img;
    uint8_t SR_FAR *px;
    unsigned y, x;
    if (nfrag == 4 || fragment->x_offset + fragment->width > 320)
        return;
    img = hg_image_new(fragment->width, fragment->height, 1);
    if (!img)
        return;
    img->key = 0;
    px = hg_image_pixels(img, 0);
    for (y = 0; y < fragment->height; ++y)
        for (x = 0; x < fragment->width; ++x) {
            const uint8_t v = fragment->pixels.data[(uint32_t)y * fragment->width + x];
            px[(uint32_t)y * img->stride + x] =
                (fragment->transparent_zero && v == 0) || v >= max_index ? 0
                                                                         : (uint8_t)(palette_base + v);
        }
    frag_img[nfrag] = img;
    frag_src[nfrag] = fragment;
    frag_base[nfrag] = palette_base;
    nfrag++;
}

void hzv_underlay(PlaySceneCache *cache)
{
    if (!under_img) {
        under_img = hg_image_new(320, 200, 1);
        if (!under_img)
            return;
        under_px = hg_image_pixels(under_img, 0);
    }
    cache->underlay.width = 320;
    cache->underlay.height = 200;
    cache->underlay.pixels = (uint8_t SR_FAR *)under_px;
    if (!dash_img) {
        dash_img = hg_image_new(320, 200, 1);
        if (dash_img)
            dash_px = hg_image_pixels(dash_img, 0);
    }
    cache->dash.width = 320;
    cache->dash.height = 200;
    cache->dash.pixels = (uint8_t SR_FAR *)dash_px;
}

static void hzv_shadow(FrameBuffer320x200 *f, const uint32_t *mask, int32_t left, int32_t top)
{
    blit_sync(f);
    hz_shadow(f->pixels, mask, (int)left, (int)top);
}

static bool hz_inside_tile_c(const LevelRow SR_FAR *row, uint16_t x, int y)
{
    return hz_inside_tile(row, x, y) != 0;
}

/* FbOps.sprite: hz_keyed over the clipped rectangle */
static bool hzv_sprite(FrameBuffer320x200 *f, const uint8_t SR_FAR *pixels, unsigned w, unsigned h,
                      int32_t x, int32_t y, uint8_t add)
{
    const int32_t x0 = SR_MAX(x, 0), y0 = SR_MAX(y, 0);
    const int32_t x1 = SR_MIN(x + (int32_t)w, 320), y1 = SR_MIN(y + (int32_t)h, 200);
    blit_sync(f);
    if (x1 <= x0 || y1 <= y0)
        return true;
    hz_keyed(pixels + (unsigned)(y0 - y) * w + (unsigned)(x0 - x), w,
             f->pixels + (unsigned)y0 * 320u + (unsigned)x0, (unsigned)(y1 - y0),
             (unsigned)(x1 - x0), add);
    return true;
}

int hzv_init(void)
{
    unsigned p;
    if (hg_screen_fb(HG_320X180, "SkyRoads", 320, FB_ROWS) < 0)
        return -1;
    hzv_fbbank = hg_fb_bank;
    for (p = 0; p < HZV_PAGES; ++p) {
        const uint32_t a = ((uint32_t)hzv_fbbank << 16) + (uint32_t)page_row[p] * 320u;
        hzv_page[p].width = 320;
        hzv_page[p].height = 200;
        hzv_page[p].pixels = (uint8_t SR_FAR *)a;
    }
    if (!hzv_noruns) {                  /* fill_runs answers (0 runs: nothing drawn)? */
        hz_fillruns probe;
        memset(&probe, 0, sizeof probe);
        if (hz_fill_runs(0, &probe) >= 0) {
            grp = (hg_rungroup SR_FAR *)plat_alloc(512u * sizeof(hg_rungroup));  /* PASS_JOBS */
            use_runs = grp != 0;
        }
    }
    fb_ops.spans = hz_fb_spans;
    fb_ops.span_jobs = hz_fb_span_jobs;
    fb_ops.copy_rows = hz_copy_rows;
    fb_ops.copy_rect = hz_copy_rect;
    fb_ops.fragment = hz_fragment;
    fb_ops.sync = blit_sync;
    fb_ops.sprite = hzv_sprite;
    fb_ops.shadow = hzv_shadow;
    level_inside_tile16_fast = hz_inside_tile_c;
    if (!hzv_nofast)
        fb_ops.road_row = hz_road_row;
    memset(&scr, 0, sizeof scr);
    return 0;
}

/* the page waiting to be shown is shown once a blank has passed */
static void flips_done(void)
{
    if (pending != 0xFFFF && hz_frame() != pending_frame) {
        shown = pending;
        pending = 0xFFFF;
    }
}

unsigned hzv_free_page(void)
{
    unsigned p;
    flips_done();
    for (p = 0; p < HZV_PAGES; ++p)
        if (p != shown && p != pending)
            return p;
    return 0;
}

void hzv_show(unsigned p, unsigned view_y)
{
    blit_sync(&hzv_page[p]);
    flips_done();
    scr.y = (unsigned short)(page_row[p] + view_y);
    hz_fs_scroll(&scr);
    /* a page still waiting is never shown: it is free again */
    pending = p;
    pending_frame = hz_frame();
}

void hzv_palette(const Palette256 *pal)
{
    if (pal_valid && memcmp(pal_shown, pal->colors, 768) == 0)
        return;
    memcpy(pal_shown, pal->colors, 768);
    pal_valid = true;
    hg_palette(0, 256, pal_shown);
}
