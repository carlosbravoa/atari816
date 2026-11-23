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
/* (round 2) the same in two: wait for the page's drawing (the blitter's), and show it */
void hzv_ready(unsigned p);
void hzv_flip(unsigned p, unsigned view_y);
extern unsigned hzv_held;               /* a page drawn and kept to be shown later: not free */
extern void (*hzv_poll_hook)(void);     /* called now and then while a frame is drawn */
/* the palette, sent when it differs from the one shown */
void hzv_palette(const Palette256 *pal);
/* the underlay of the play scene: an image the blitter restores from */
void hzv_underlay(PlaySceneCache *cache);   /* (and its dashboard band cache) */
/* make an image of a fragment for the blitter (the dashboard): drawn by blits after */
void hzv_register_fragment(const ImageFrame SR_FAR *fragment, unsigned palette_base);
extern unsigned long hzv_blits, hzv_groups;
/* the runs sent to fill_runs (16 bits, wraps: take differences) */
extern unsigned hz_span_total;
#define hzv_runs ((unsigned long)hz_span_total)
extern bool hzv_nofast;
extern bool hzv_noruns;                 /* /NORUNS: the spans by the CPU (hz_span_jobs) */

/* ---- hz_spans.s */
void hz_spans(const PreparedSpan SR_FAR *spans, unsigned count, unsigned right, unsigned index,
              unsigned bank, unsigned base);

void hz_span_jobs(const SpanJob SR_FAR *jobs, unsigned n, unsigned bank, unsigned base);
/* (Horizon 0.30) the jobs as fill_runs groups (FR_GROUPS) at out -> how many */
unsigned hz_span_groups(const SpanJob SR_FAR *jobs, unsigned n, void SR_FAR *out);
unsigned long hz_sum(const void SR_FAR *p, unsigned nwords);

/* ---- hz_probe.s, hz_sim.c (the simulation's fast paths) */
bool hz_probe(const Level *level, int32_t x_128, int32_t y_128, int32_t z_fp16);
bool hz_probe16(const Level *level, uint16_t x_128, int y_128, unsigned zrow);
bool hz_move16(Ship *s, const Ship *dest, const Level *level);
unsigned hz_scan16(const Level *level, uint16_t x, int y, unsigned zrow, int step);
void hzp_tables(void);
unsigned long hzm_check(const Level *levels, unsigned count, unsigned long n);
unsigned long hzp_check(const Level *levels, unsigned count, unsigned long n);
void hz_shadow(uint8_t SR_FAR *page, const uint32_t *mask, int left, int top);

/* ---- hz_road.s */
unsigned hz_road_row(const uint16_t SR_FAR *ptr24, const uint16_t SR_FAR *current,
                     const uint16_t SR_FAR *nearer,
                     const PreparedShape SR_FAR *prepared, unsigned shape_count, SpanJob *jobs);

unsigned hz_road_pass(const RoadPass *pass, void *out, unsigned cap);
/* (its groups: hz_video.c's hzr_groups, hg_rungroup records) */

void hz_keyed(const uint8_t SR_FAR *src, unsigned sstride, uint8_t SR_FAR *dst, unsigned rows,
              unsigned cols, unsigned add);

/* ---- hz_plat.c */
extern unsigned hzp_banks_used;

#endif
