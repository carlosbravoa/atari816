/* hz_plat.h - the Horizon back end's own interface (between its files) */
#ifndef HZ_PLAT_H
#define HZ_PLAT_H

#include "renderer/renderer.h"

/* ---- the screen (hz_video.c)
 * One framebuffer of 320-byte rows holds three pages of 320 x 200, each inside a bank of
 * its own (rows 0, 206 and 410: 64,000 bytes from offsets 0, $180 and $80 of three
 * consecutive banks), so the CPU draws a page with 16-bit offsets. Marga shows 180 rows of
 * the page last finished (hzv_show); the renderer draws the next frame into a page that
 * is neither shown nor waiting to be (three pages: no waiting for the blank). */
#define HZV_PAGES 3
extern unsigned hzv_fbbank;
extern FrameBuffer320x200 hzv_page[HZV_PAGES];
extern PagePrime hzv_prime[HZV_PAGES];

int hzv_init(void);
/* a page the next frame may be drawn into */
unsigned hzv_free_page(void);
/* show page p from its row view_y (0..20) at the next vertical blank */
void hzv_show(unsigned p, unsigned view_y);
/* the palette, sent when it differs from the one shown */
void hzv_palette(const Palette256 *pal);
/* the underlay of the play scene: an image the blitter restores from */
void hzv_underlay(PlaySceneCache *cache);   /* (and its dashboard band cache) */
/* make an image of a fragment for the blitter (the dashboard): drawn by blits after */
void hzv_register_fragment(const ImageFrame SR_FAR *fragment, unsigned palette_base);
extern unsigned long hzv_blits;
extern bool hzv_nofast;

/* ---- hz_spans.s */
void hz_spans(const PreparedSpan SR_FAR *spans, unsigned count, unsigned right, unsigned index,
              unsigned bank, unsigned base);

void hz_span_jobs(const SpanJob SR_FAR *jobs, unsigned n, unsigned bank, unsigned base);
unsigned long hz_sum(const void SR_FAR *p, unsigned nwords);

/* ---- hz_probe.s */
unsigned hz_inside_tile(const LevelRow SR_FAR *row, unsigned x, int y);
void hz_shadow(uint8_t SR_FAR *page, const uint32_t *mask, int left, int top);

/* ---- hz_road.s */
unsigned hz_road_row(const uint16_t SR_FAR *ptr24, const uint16_t *current, const uint16_t *nearer,
                     const PreparedShape SR_FAR *prepared, unsigned shape_count, SpanJob *jobs);

void hz_keyed(const uint8_t SR_FAR *src, unsigned sstride, uint8_t SR_FAR *dst, unsigned rows,
              unsigned cols, unsigned add);

/* ---- hz_plat.c */
extern unsigned hzp_banks_used;

#endif
