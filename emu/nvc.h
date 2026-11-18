/* Marga (the video chip, "NVC" in the code): framebuffer, palette, pointer ($00:D900-$D92A), and from
 * REV $0B fine scrolling ($D930-$D93A) and 16 sprites ($D940-$D944, records at $D980-$D9FF).
 * Mirrors core/src/a816/a816_nvc.sv: 640x360 (or 320x180) shown 2x (4x) in the 1280x720 output. */
#ifndef NVC_H
#define NVC_H
#include <stdint.h>

#define NV_OUT_W 1280
#define NV_FB_W  640                 /* bytes fetched per line in mode 0 */
#define NV_OUT_H 720

typedef struct Nvc {
    uint8_t  ctrl;                   /* 0 ENABLE, 2:1 MODE, 3 POINTER_EN */
    uint16_t base_pend, base_act;    /* address bits 23:8 (as written; taken at trigger 0) */
    uint8_t  base_pending;
    uint16_t stride, line_cmp, nv_line;
    uint8_t  pal_idx, pal_r, pal_g;
    uint8_t  pal[256][3];
    uint16_t ptr_x, ptr_y;
    uint8_t  ptr_hot;
    uint32_t ptr_img;
    uint8_t  ptr_c[4];               /* [1..3] = PTR_C1..C3 */
    uint32_t row_addr;               /* start of the line being fetched */
    uint8_t  lbuf[2][NV_FB_W];           /* the two-line buffer, written at the fetch trigger: one palette
                                          * index per picture pixel (pointer and sprites merged) */
    int      trig_n;                 /* next trigger: 0..365 */
    uint64_t next_trig;              /* CPU cycle of that trigger */
    uint64_t frame_start;            /* CPU cycle of output line 0 of the current frame */
    uint64_t frames;
    uint32_t *out;                   /* NV_OUT_W x NV_OUT_H, 0x00RRGGBB */
    uint8_t  want;                   /* 0: nobody looks at the output, skip fetch and display */
    uint8_t  disp[360][NV_FB_W];         /* lines as they reached the screen ... */
    uint8_t  disp_ctrl[360];         /* ... with NV_CTRL at that moment */
    uint8_t  dirty[360];             /* shown but not yet converted to RGB */
    int      ndirty;
    void   (*on_frame)(void);        /* called at trigger 360 (VBLANK), after the last line */
    /* REV $09 raster events (beam): NV_LINE, LINE, VBLANK, NV_FRAME come BEAM_PIX pixel
     * clocks after trigger n (before REV $09: at the trigger itself) */
    int      beam_n;                 /* next beam event: 0..365 */
    uint64_t next_beam;              /* CPU cycle of that event */
    uint64_t beam_fs;                /* frame start of the beam events (lags frame_start at the wrap) */
    uint16_t frame;                  /* NV_FRAME */
    uint8_t  frame_hi, line_hi;      /* read latches */
    /* REV $0B fine scrolling: written (_p), taken at trigger 0 (_a) */
    uint16_t scx_p, scx2_p, scx_a, scx2_a;   /* 12 bits */
    uint16_t scy_p, scy2_p, scy2_a, vh_p, vh_a, rl;  /* 10 bits */
    uint8_t  sctl_p, sctl_a;         /* 0 HWRAP, 1 SPLIT */
    uint16_t split_l;                /* NV_LINE_CMP taken at trigger 0 */
    uint8_t  reg2;                   /* lines from the split on */
    /* REV $0B sprites */
    uint8_t  spr_en, cm_req, vbl_win, spr_ovf;
    uint8_t  spr_sh[128], spr_ac[128];  /* records as written; the set in use */
    uint8_t  pk_a, pk_d;
} Nvc;

void    nvc_reset(void);
uint64_t nvc_next_event(void);       /* earliest trigger or beam event */
uint64_t nvc_vbl_after(uint64_t t);  /* CPU cycle of the first VBLANK event after cycle t */
void    nvc_update(uint64_t now);
uint8_t nvc_read(uint32_t a);
void    nvc_write(uint32_t a, uint8_t v);
void    nvc_render(void);            /* convert the lines shown so far to RGB in out */
int     nvc_write_ppm(const char *path);

#endif
