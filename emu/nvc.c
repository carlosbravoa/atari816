/* Marga, the video chip (first called NVC, native video controller), a model of core/src/a816/a816_nvc.sv.
 *
 * Raster: 1572 pixel clocks x 760 output lines per frame at 71.71875 MHz (2.5 clk_core,
 * 5 pixel clocks per CPU cycle): one output line is 314.4 CPU cycles and a frame exactly
 * 238,944 CPU cycles (60.03 Hz). Positions are counted in pixel clocks. The
 * frame phase is 0 at CPU reset (the real raster is genlocked to the Atari and free-running).
 *
 * Trigger n (n = 0..365) fires at the start of output line 28 + 2n (every 628.8 CPU
 * cycles); output lines 0..27 have none. At trigger n: NV_LINE = n, VBLANK pulse at n == 360, LINE pulse
 * at n == NV_LINE_CMP; at n == 0 NV_BASE is taken and the row address restarts, otherwise
 * it advances by NV_STRIDE (mode 2: every second trigger). If ENABLE and n < 360 the line
 * is fetched from RAM into half n&1 of the two-line buffer, with the pointer merged in at
 * that moment (registers and image as they are then).
 * Line n is shown on output lines 30+2n and 31+2n, i.e. from trigger n+1 on; the emulator
 * converts it to RGB at trigger n+1 with the palette and NV_CTRL of that moment.
 *
 * REV $0B: the row of line 0 is NV_BASE + NV_SCROLLY * NV_STRIDE, rows wrap at NV_VHEIGHT, a line
 * starts NV_SCROLLX pixels into its row (HWRAP: wrapping at NV_STRIDE bytes), and with SPLIT the
 * line NV_LINE_CMP (as at trigger 0) restarts at row NV_SCROLLY2 with NV_SCROLLX2. Sprites are
 * chosen and drawn at the fetch, from the record set in use; COMMIT copies the written records
 * to it in vertical blank (from trigger 360 to trigger 0: at once). Bit-exact with the RTL as
 * long as the RTL is never late (NV_SPR_STATUS.LATE stays 0); the line buffer holds the final
 * palette index of each picture pixel.
 *
 * REV $09 moves NV_LINE, the LINE and VBLANK pulses (and the new NV_FRAME) to the beam
 * event: 2852 pixel clocks (1572 + 1280) after trigger n, i.e. the horizontal blank at the
 * end of output line 29 + 2n, just before line n is drawn. Below REV $09 the beam event is
 * the trigger itself. Reading NV_LINE ($D906) latches $D907 and NV_FRAME ($D90C) $D90D.
 */
#include "machine.h"
#include <string.h>
#include <stdlib.h>
#include "nvc_palette.h"

#define LINE_PIX   1572u                      /* one output line, pixel clocks */
#define FRAME_PIX  (760u * LINE_PIX)          /* 1,194,720 pixel clocks */
#define FRAME_CYC  (FRAME_PIX / 5)            /* 238,944 CPU cycles */
#define AMASK      (RAM_SIZE - 1)             /* the fetcher's SDRAM address is AW bits */

/* first CPU cycle at or after the pixel clock that starts output line 28 + 2t */
static uint64_t trig_cycle(Nvc *n, int t) { return n->frame_start + ((uint64_t)(28 + 2 * t) * LINE_PIX + 4) / 5; }

#define BEAM_PIX   (LINE_PIX + 1280u)
static uint32_t beam_off(void) { return M.sys.rev >= 9 ? BEAM_PIX : 0; }
static uint64_t beam_cycle(uint64_t frame_start, int t)
{
    return frame_start + ((uint64_t)(28 + 2 * t) * LINE_PIX + beam_off() + 4) / 5;
}

uint64_t nvc_next_event(void) { return M.nvc.next_trig < M.nvc.next_beam ? M.nvc.next_trig : M.nvc.next_beam; }

/* frame starts are multiples of FRAME_CYC (nvc_reset) */
uint64_t nvc_vbl_after(uint64_t t)
{
    uint64_t fs = t - t % FRAME_CYC;
    for (;;) {
        uint64_t e = beam_cycle(fs, 360);
        if (e > t) return e;
        fs += FRAME_CYC;
    }
}

void nvc_reset(void)
{
    Nvc *n = &M.nvc;
    uint32_t *out = n->out;
    void (*cb)(void) = n->on_frame;
    uint8_t want = n->want;
    memset(n, 0, sizeof *n);
    n->out = out;
    n->on_frame = cb;
    n->want = want;
    n->stride = 640;
    n->line_cmp = 511;
    n->nv_line = 360;
    n->ptr_c[1] = 0x00; n->ptr_c[2] = 0x0F; n->ptr_c[3] = 0x08;
    for (int i = 0; i < 256; i++) {
        n->pal[i][0] = nvc_reset_palette[i] >> 16;
        n->pal[i][1] = nvc_reset_palette[i] >> 8;
        n->pal[i][2] = nvc_reset_palette[i];
    }
    n->frame_start = M.cpu.cycles - M.cpu.cycles % FRAME_CYC;
    n->trig_n = 0;
    n->next_trig = trig_cycle(n, 0);
    if (n->next_trig < M.cpu.cycles) { n->frame_start += FRAME_CYC; n->next_trig = trig_cycle(n, 0); }
    n->beam_n = 0;
    n->beam_fs = n->frame_start;
    n->next_beam = beam_cycle(n->beam_fs, 0);
}

/* pointer pixel p (0..31) of an 8-byte row: leftmost pixel in bits 7:6 of byte 0 */
static inline int ptr_px(const uint8_t *row, unsigned p) { return (row[p >> 2] >> (6 - 2 * (p & 3))) & 3; }

static inline int sext(unsigned v, int bits) { return (int)(v << (32 - bits)) >> (32 - bits); }

/* sprites of picture line ly into spr[] ({BEHIND, index}, 0 = none); OVERFLOW */
static void sprites(Nvc *n, int ly, int w, uint16_t *spr, int draw)
{
    int sel[16], used = 0;
    for (int i = 0; i < 16; i++) {
        const uint8_t *r = n->spr_ac + 8 * i;
        uint8_t c = r[7];
        int y = sext(r[2] | (r[3] & 3) << 8, 10), mag = (c >> 3) & 1;
        int hd = (16 << ((c >> 5) & 1)) << mag, wide = (c >> 4) & (c >> 6) & 1;
        int dy = ly - y, units = (1 << wide) << mag;
        sel[i] = 0;
        if (!(c & 1) || dy < 0 || dy >= hd) continue;
        if (used + units <= 32) { sel[i] = 1; used += units; }
        else n->spr_ovf = 1;
    }
    if (!draw) return;
    for (int i = 15; i >= 0; i--) {
        if (!sel[i]) continue;
        const uint8_t *r = n->spr_ac + 8 * i;
        uint8_t c = r[7];
        int x = sext(r[0] | (r[1] & 7) << 8, 11), y = sext(r[2] | (r[3] & 3) << 8, 10);
        int mag = (c >> 3) & 1, b4 = (c >> 6) & 1, wide = (c >> 4) & b4 & 1;
        int hh = 16 << ((c >> 5) & 1), ww = 16 << wide, rb = b4 ? (wide ? 16 : 8) : 16;
        int row = (ly - y) >> mag;
        if (c & 4) row = hh - 1 - row;
        uint32_t img = ((uint32_t)r[6] << 16 | r[5] << 8 | (r[4] & 0xF0)) + (uint32_t)(row * rb);
        for (int d = 0; d < (ww << mag); d++) {
            int j = d >> mag, col = x + d;
            if (c & 2) j = ww - 1 - j;
            uint8_t pix;
            if (b4) {
                uint8_t by = M.ram[(img + j / 2) & AMASK];
                pix = (j & 1) ? by & 15 : by >> 4;
                if (pix) pix |= (r[4] & 15) << 4;
            } else pix = M.ram[(img + j) & AMASK];
            if (pix && col >= 0 && col < w) spr[col] = (uint16_t)((c & 0x80) << 1 | pix);
        }
    }
}

static void fetch(Nvc *n, int t)
{
    int mode = (n->ctrl >> 1) & 3, w = mode == 2 ? NV_FB_W / 2 : NV_FB_W;
    int ly = mode == 2 ? t >> 1 : t;
    uint8_t *lb = n->lbuf[t & 1];
    uint16_t spr[NV_FB_W];
    int draw = n->want, sp = n->spr_en && M.sys.rev >= 11;
    if (sp) {
        if (draw) memset(spr, 0, sizeof spr);
        sprites(n, ly, w, spr, draw);
    }
    if (!draw) return;
    unsigned x0 = n->reg2 ? n->scx2_a : n->scx_a;
    for (int x = 0; x < w; x++) {
        unsigned px = x0 + x, b = mode == 1 ? px >> 1 : px;
        if ((n->sctl_a & 1) && n->stride) b %= n->stride;
        uint8_t v = M.ram[(n->row_addr + b) & AMASK];
        lb[x] = mode == 1 ? ((px & 1) ? v & 15 : v >> 4) : v;
    }
    if (sp) for (int x = 0; x < w; x++)
        if ((spr[x] & 0xFF) && !((spr[x] & 0x100) && lb[x])) lb[x] = (uint8_t)spr[x];

    unsigned f_line = (unsigned)ly;
    unsigned ptr_top = (n->ptr_y - ((n->ptr_hot >> 4) << 1)) & 0x3FF;
    unsigned dy = (f_line - ptr_top) & 0x3FF;
    if (!(n->ctrl & 8) || dy >= 32) return;
    uint8_t row[8];
    for (int i = 0; i < 8; i++) row[i] = M.ram[((n->ptr_img & ~7u) + dy * 8 + i) & AMASK];
    unsigned left = (n->ptr_x - ((n->ptr_hot & 15) << 1)) & 0x7FF;
    for (int col = 0; col < w; col++) {
        unsigned d = ((unsigned)col - left) & 0x7FF;
        int c = d < 32 ? ptr_px(row, d) : 0;
        if (c) lb[col] = mode == 1 ? n->ptr_c[c] & 15 : n->ptr_c[c];
    }
}

/* line l (0..359) reaches the screen with NV_CTRL of now; it is converted to RGB with the
 * palette of now, lazily: before the next palette write or when the picture is needed */
static void display(Nvc *n, int l)
{
    memcpy(n->disp[l], n->lbuf[l & 1], NV_FB_W);
    n->disp_ctrl[l] = n->ctrl;
    if (!n->dirty[l]) { n->dirty[l] = 1; n->ndirty++; }
}

static void convert(Nvc *n, int l)
{
    uint32_t *o = n->out + (2 * l) * NV_OUT_W;
    uint8_t ctrl = n->disp_ctrl[l];
    int mode = (ctrl >> 1) & 3;
    const uint8_t *lb = n->disp[l];
    if (!(ctrl & 1)) memset(o, 0, NV_OUT_W * 4);
    else for (int x = 0; x < NV_OUT_W; x++) {
        uint8_t idx = mode == 2 ? lb[x >> 2] : lb[x >> 1];
        o[x] = n->pal[idx][0] << 16 | n->pal[idx][1] << 8 | n->pal[idx][2];
    }
    memcpy(o + NV_OUT_W, o, NV_OUT_W * 4);
}

void nvc_render(void)
{
    Nvc *n = &M.nvc;
    if (!n->ndirty || !n->out) return;
    for (int l = 0; l < 360; l++) if (n->dirty[l]) { convert(n, l); n->dirty[l] = 0; }
    n->ndirty = 0;
}

static void copy_records(Nvc *n) { memcpy(n->spr_ac, n->spr_sh, 128); n->cm_req = 0; }

static void trigger(Nvc *n, int t)
{
    int mode = (n->ctrl >> 1) & 3;
    if (n->want && t >= 1 && t <= 360) display(n, t - 1);
    if (t == 0) {
        n->base_pending = 0;
        n->scx_a = n->scx_p; n->scx2_a = n->scx2_p; n->scy2_a = n->scy2_p; n->vh_a = n->vh_p; n->sctl_a = n->sctl_p;
        n->split_l = n->line_cmp; n->reg2 = 0;
        n->row_addr = (((uint32_t)n->base_pend << 8) + (uint32_t)n->scy_p * n->stride) & 0xFFFFFF;
        n->rl = n->scy_p;
    } else if ((n->sctl_a & 2) && t == n->split_l) {
        n->reg2 = 1;
        n->row_addr = (((uint32_t)n->base_act << 8) + (uint32_t)n->scy2_a * n->stride) & 0xFFFFFF;
        n->rl = n->scy2_a;
    } else if (mode != 2 || !(t & 1)) {
        if (n->vh_a && ((n->rl + 1) & 0x3FF) == n->vh_a) { n->rl = 0; n->row_addr = (uint32_t)n->base_act << 8; }
        else { n->rl = (n->rl + 1) & 0x3FF; n->row_addr = (n->row_addr + n->stride) & 0xFFFFFF; }
    }
    if (t == 0) n->base_act = n->base_pend;
    n->vbl_win = t >= 360;
    if (n->vbl_win && n->cm_req) copy_records(n);
    if ((n->ctrl & 1) && t < 360 && (n->want || (n->spr_en && M.sys.rev >= 11))) fetch(n, t);
    if (t == 360) {
        n->frames++;
        if (n->on_frame) n->on_frame();
    }
}

static void beam(Nvc *n, int t)
{
    n->nv_line = t;
    if (t == 360) { M.sys.irq_status |= IRQ_VBLANK; n->frame++; }
    if (t == n->line_cmp) M.sys.irq_status |= IRQ_LINE;
}

/* triggers and beam events in time order (a trigger first when both fall on one cycle) */
void nvc_update(uint64_t now)
{
    Nvc *n = &M.nvc;
    for (;;) {
        if (now >= n->next_trig && n->next_trig <= n->next_beam) {
            trigger(n, n->trig_n);
            if (++n->trig_n == 366) { n->trig_n = 0; n->frame_start += FRAME_CYC; }
            n->next_trig = trig_cycle(n, n->trig_n);
        } else if (now >= n->next_beam) {
            beam(n, n->beam_n);
            if (++n->beam_n == 366) { n->beam_n = 0; n->beam_fs += FRAME_CYC; }
            n->next_beam = beam_cycle(n->beam_fs, n->beam_n);
        } else break;
    }
}

uint8_t nvc_read(uint32_t a)
{
    Nvc *n = &M.nvc;
    switch (a & 0xFF) {
    case 0x00: return n->ctrl;
    case 0x02: return n->base_pend & 0xFF;
    case 0x03: return n->base_pend >> 8;
    case 0x04: return n->stride & 0xFF;
    case 0x05: return n->stride >> 8;
    case 0x06: n->line_hi = n->nv_line >> 8; return n->nv_line & 0xFF;
    case 0x07: return M.sys.rev >= 9 ? n->line_hi : n->nv_line >> 8;   /* REV $09: latched */
    case 0x08: return n->line_cmp & 0xFF;
    case 0x09: return n->line_cmp >> 8;
    case 0x0A: return n->base_pending << 1 | (n->nv_line >= 360);
    case 0x0B: return 0;                          /* NV_LATE: the emulator is never late */
    case 0x0C: if (M.sys.rev < 9) return 0; n->frame_hi = n->frame >> 8; return n->frame & 0xFF;
    case 0x0D: return M.sys.rev >= 9 ? n->frame_hi : 0;
    case 0x10: return n->pal_idx;
    case 0x11: return n->pal_r;
    case 0x12: return n->pal_g;
    case 0x20: return n->ptr_x & 0xFF;
    case 0x21: return n->ptr_x >> 8;
    case 0x22: return n->ptr_y & 0xFF;
    case 0x23: return n->ptr_y >> 8;
    case 0x24: return n->ptr_hot;
    case 0x25: return n->ptr_img & 0xFF;
    case 0x26: return (n->ptr_img >> 8) & 0xFF;
    case 0x27: return n->ptr_img >> 16;
    case 0x28: case 0x29: case 0x2A: return n->ptr_c[(a & 0xFF) - 0x27];
    }
    if (M.sys.rev < 11) return 0;
    switch (a & 0xFF) {                           /* REV $0B */
    case 0x30: return n->scx_p & 0xFF;
    case 0x31: return n->scx_p >> 8;
    case 0x32: return n->scy_p & 0xFF;
    case 0x33: return n->scy_p >> 8;
    case 0x34: return n->scx2_p & 0xFF;
    case 0x35: return n->scx2_p >> 8;
    case 0x36: return n->scy2_p & 0xFF;
    case 0x37: return n->scy2_p >> 8;
    case 0x38: return n->vh_p & 0xFF;
    case 0x39: return n->vh_p >> 8;
    case 0x3A: return n->sctl_p;
    case 0x40: return n->spr_en;
    case 0x41: return n->cm_req;
    case 0x42: return n->spr_ovf;
    case 0x43: return n->pk_a;
    case 0x44: return n->pk_d;
    }
    return 0;                                     /* $D901, PAL_B, the records and the rest */
}

void nvc_write(uint32_t a, uint8_t v)
{
    Nvc *n = &M.nvc;
    switch (a & 0xFF) {
    case 0x00: n->ctrl = v & 0x0F; break;
    case 0x02: n->base_pend = (n->base_pend & 0xFF00) | v; n->base_pending = 1; break;
    case 0x03: n->base_pend = (n->base_pend & 0x00FF) | v << 8; n->base_pending = 1; break;
    case 0x04: n->stride = (n->stride & 0xFF00) | v; break;
    case 0x05: n->stride = (n->stride & 0x00FF) | v << 8; break;
    case 0x08: n->line_cmp = (n->line_cmp & 0x100) | v; break;
    case 0x09: n->line_cmp = (n->line_cmp & 0x0FF) | (v & 1) << 8; break;
    case 0x10: n->pal_idx = v; break;
    case 0x11: n->pal_r = v; break;
    case 0x12: n->pal_g = v; break;
    case 0x13:
        nvc_render();                             /* lines already shown keep the old colour */
        n->pal[n->pal_idx][0] = n->pal_r;
        n->pal[n->pal_idx][1] = n->pal_g;
        n->pal[n->pal_idx][2] = v;
        n->pal_idx++;
        break;
    case 0x20: n->ptr_x = (n->ptr_x & 0x300) | v; break;
    case 0x21: n->ptr_x = (n->ptr_x & 0x0FF) | (v & 3) << 8; break;
    case 0x22: n->ptr_y = (n->ptr_y & 0x100) | v; break;
    case 0x23: n->ptr_y = (n->ptr_y & 0x0FF) | (v & 1) << 8; break;
    case 0x24: n->ptr_hot = v; break;
    case 0x25: n->ptr_img = (n->ptr_img & 0xFFFF00) | v; break;
    case 0x26: n->ptr_img = (n->ptr_img & 0xFF00FF) | v << 8; break;
    case 0x27: n->ptr_img = (n->ptr_img & 0x00FFFF) | (uint32_t)v << 16; break;
    case 0x28: case 0x29: case 0x2A: n->ptr_c[(a & 0xFF) - 0x27] = v; break;
    }                                             /* $D901, NV_LATE ($D90B): ignored */
    if (M.sys.rev < 11) return;
    unsigned r = a & 0xFF;
    if (r >= 0x80) { n->spr_sh[r - 0x80] = v; return; }
    switch (r) {                                  /* REV $0B */
    case 0x30: n->scx_p = (n->scx_p & 0xF00) | v; break;
    case 0x31: n->scx_p = (n->scx_p & 0x0FF) | (v & 15) << 8; break;
    case 0x32: n->scy_p = (n->scy_p & 0x300) | v; break;
    case 0x33: n->scy_p = (n->scy_p & 0x0FF) | (v & 3) << 8; break;
    case 0x34: n->scx2_p = (n->scx2_p & 0xF00) | v; break;
    case 0x35: n->scx2_p = (n->scx2_p & 0x0FF) | (v & 15) << 8; break;
    case 0x36: n->scy2_p = (n->scy2_p & 0x300) | v; break;
    case 0x37: n->scy2_p = (n->scy2_p & 0x0FF) | (v & 3) << 8; break;
    case 0x38: n->vh_p = (n->vh_p & 0x300) | v; break;
    case 0x39: n->vh_p = (n->vh_p & 0x0FF) | (v & 3) << 8; break;
    case 0x3A: n->sctl_p = v & 3; break;
    case 0x40: n->spr_en = v & 1; break;
    case 0x41: n->cm_req = 1; if (n->vbl_win) copy_records(n); break;
    case 0x42: if (v & 1) n->spr_ovf = 0; break;
    case 0x43: n->pk_a = v; n->pk_d = v < 128 ? n->spr_sh[v] : n->spr_ac[v - 128]; break;
    }
}


int nvc_write_ppm(const char *path)
{
    Nvc *n = &M.nvc;
    FILE *f = fopen(path, "wb");
    if (!f) return -1;
    fprintf(f, "P6\n%d %d\n255\n", NV_OUT_W, NV_OUT_H);
    for (int i = 0; i < NV_OUT_W * NV_OUT_H; i++) {
        uint32_t p = n->out[i];
        fputc(p >> 16, f); fputc((p >> 8) & 0xFF, f); fputc(p & 0xFF, f);
    }
    return fclose(f);
}
