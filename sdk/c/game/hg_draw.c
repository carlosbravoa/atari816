/* hg_draw.c - hgame: the frame's draw records (one draw_list or sheet_draw call a frame),
 * fills, lines, pixels, text. */
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include "hg_int.h"

hz_drawrec __far *hg__dq;
hz_sheetrec __far *hg__sq;
unsigned hg__runs[HG__Q], hg__nruns, hg__runkind;
unsigned hg__qn, hg__flushes;
unsigned char hg__listrun, hg__vblsent;
int hg__cutx, hg__cuty;
unsigned long hg__sheet_addr[33];
unsigned hg__sheet_stride[33];

/* ---------------------------------------------------------------- records */

/* the clip rectangle and the offset hg__rec (hg_fast.s) uses: set by hg__clip_update
 * whenever the screen, the page or the origin changes */
int hg__offx, hg__offy, hg__clx1, hg__cly0, hg__cly1;
unsigned hg__four;
unsigned long hg__qpix;

void hg__clip_update(void)
{
    hg__offx = hg__ox;
    hg__offy = hg__oy + (int)hg__pagey;
    hg__four = hg__kind == HG__FULL && hg__mode == FS_640X4;
    if (hg__kind == HG__WINDOW) {
        hg__clx1 = (int)hg_w;
        hg__cly0 = 0;
        hg__cly1 = (int)hg_h;
    } else if (hg__kind == HG__NONE) {
        hg__clx1 = hg__cly0 = hg__cly1 = 0;
    } else if (hg__double) {
        hg__clx1 = (int)hg_w;
        hg__cly0 = (int)hg__pagey;
        hg__cly1 = hg__cly0 + (int)hg_h;
    } else {
        hg__clx1 = (int)(hg__four ? hg_fb_stride * 2 : hg_fb_stride);
        hg__cly0 = 0;
        hg__cly1 = (int)hg_fb_rows;
    }
}

int hg__queue_new(void)
{
    unsigned long a = hg__farmem((unsigned long)HG__Q * (sizeof(hz_drawrec) +
                                                         sizeof(hz_sheetrec)));
    if (!a)
        return -1;
    hg__dq = (hz_drawrec __far *)HG__PTR(a);
    hg__sq = (hz_sheetrec __far *)HG__PTR(a + HG__Q * sizeof(hz_drawrec));
    hg__qn = 0;
    hg__qpix = 0;
    hg__nruns = 0;
    return 0;
}

/* draw_list / sheet_draw of n records at the far address a (the C stubs take near ones) */
static unsigned sys(unsigned n, unsigned count, unsigned long a)
{
    return hz_syscall(n, (hg_win & 0xFF) | count << 8, (unsigned)a, (unsigned)(a >> 16));
}

void hg__submit(int vbl)
{
    unsigned k, start, n;
    int first;

    if (!hg__qn) {
        hg__qpix = 0;
        hg__nruns = 0;
        return;
    }
    first = vbl && !hg__vblsent && !hg__double;
    if (first)
        hg__vblsent = 1;
    /* the records in runs of one kind, in order: sheet records (about four times cheaper
     * for the kernel) and draw_list records; a call after the first waits for the one
     * before it (the kernel's rule), so the frame's first goes in the vertical blank */
    for (k = 0; k < hg__nruns; k++) {
        start = hg__runs[k] & 0x7FFF;
        n = (k + 1 < hg__nruns ? hg__runs[k + 1] & 0x7FFF : hg__qn) - start;
        if (hg__runs[k] & 0x8000) {
            if (first)
                hg__sq[start].op |= SH_VBL;
            if (sys(SYS_SHEETDRAW, n, (unsigned long)(hg__sq + start)) == 0xFFFF)
                hg__fail("hg_end", "sheet_draw refused (a bad sheet?)");
        } else {
            if (first)
                hg__dq[start].flags |= LS_VBL;
            if (sys(SYS_DRAWLIST, n, (unsigned long)(hg__dq + start)) == 0xFFFF)
                hg__fail("hg_end", hz_errno == HZ_EFAULT ? "draw_list: a source is not the"
                         " game's memory" : "draw_list refused");
        }
        first = 0;
    }
    hg__listrun = 1;
    hg__qn = 0;
    hg__qpix = 0;
    hg__nruns = 0;
    ++hg__flushes;
}

void hg_flush(int wait)
{
    hg__submit(1);
    if (wait && hg__listrun) {
        hz_list_wait(0);
        hg__listrun = 0;
    }
}

void hg__cpu_sync(void)
{
    if (hg__qn)
        hg__submit(0);
    if (hg__listrun) {
        hz_list_wait(0);
        hg__listrun = 0;
    }
}

void hg_origin(int x, int y)
{
    hg__ox = x;
    hg__oy = y;
    hg__clip_update();
}

/* ---------------------------------------------------------------- the arena */

#define ARENA 2048
static unsigned char arena[ARENA];
static unsigned arena_used;

void *hg__arena(unsigned n)
{
    void *p;
    if (n > ARENA)
        return 0;
    if (arena_used + n > ARENA) {
        hg__cpu_sync();                 /* the records reading it are done: start again */
        arena_used = 0;
    }
    p = arena + arena_used;
    arena_used += (n + 1) & ~1u;
    return p;
}

void hg__arena_reset(void)
{
    arena_used = 0;
}

/* ---------------------------------------------------------------- fills and lines */

/* hg_fill: hg_fast.s */

void hg_clear(unsigned c)
{
    int ox = hg__ox, oy = hg__oy;
    hg_origin(0, 0);
    hg_fill(0, 0, hg_w, hg_h, c);
    hg_origin(ox, oy);
}

void hg_hline(int x, int y, unsigned w, unsigned c)
{
    hg_fill(x, y, w, 1, c);
}

void hg_vline(int x, int y, unsigned h, unsigned c)
{
    hg_fill(x, y, 1, h, c);
}

void hg_rect(int x, int y, unsigned w, unsigned h, unsigned c)
{
    if (w == 0 || h == 0)
        return;
    hg_fill(x, y, w, 1, c);
    if (h > 1)
        hg_fill(x, y + (int)h - 1, w, 1, c);
    if (h > 2) {
        hg_fill(x, y + 1, 1, h - 2, c);
        if (w > 1)
            hg_fill(x + (int)w - 1, y + 1, 1, h - 2, c);
    }
}

void hg_move(int sx, int sy, unsigned w, unsigned h, int x, int y)
{
    hz_drawrec __far *r;
    sx += hg__ox;
    sy += hg__oy + (int)hg__pagey;
    r = hg__rec(LS_MOVE, x, y, w, h);
    if (!r)
        return;
    sx += hg__cutx;
    sy += hg__cuty;
    if (hg__mode == FS_640X4 && hg__kind == HG__FULL)
        sx >>= 1;
    r->u.m.sx = sx;
    r->u.m.sy = sy;
}

/* ---------------------------------------------------------------- pixels (the CPU) */

unsigned long hg__fbaddr(unsigned x, unsigned y)
{
    return hg__fbbase + hg__umul(y, hg_fb_stride) + x;
}

/* screen (x, y) -> framebuffer, 0 if outside the target */
static int fbxy(int *x, int *y)
{
    int cy0, cy1, cx1;
    *x += hg__ox;
    *y += hg__oy + (int)hg__pagey;
    if (hg__double) {
        cx1 = (int)hg_w;
        cy0 = (int)hg__pagey;
        cy1 = cy0 + (int)hg_h;
    } else {
        cx1 = (int)(hg__mode == FS_640X4 ? hg_fb_stride * 2 : hg_fb_stride);
        cy0 = 0;
        cy1 = (int)hg_fb_rows;
    }
    return *x >= 0 && *x < cx1 && *y >= cy0 && *y < cy1;
}

static void put(unsigned x, unsigned y, unsigned c)
{
    unsigned char __far *p;
    if (hg__mode == FS_640X4) {
        p = HG__PTR(hg__fbaddr(x >> 1, y));
        if (x & 1)
            *p = (unsigned char)((*p & 0xF0) | (c & 15));
        else
            *p = (unsigned char)((*p & 0x0F) | (c << 4));
    } else
        *HG__PTR(hg__fbaddr(x, y)) = (unsigned char)c;
}

void hg_pixel(int x, int y, unsigned c)
{
    if (hg__kind != HG__FULL) {
        hg_fill(x, y, 1, 1, c);
        return;
    }
    if (!fbxy(&x, &y))
        return;
    hg__cpu_sync();
    put((unsigned)x, (unsigned)y, c);
}

unsigned hg_peek(int x, int y)
{
    unsigned v;
    if (hg__kind != HG__FULL || !fbxy(&x, &y))
        return 0;
    hg__cpu_sync();
    if (hg__mode == FS_640X4) {
        v = *HG__PTR(hg__fbaddr((unsigned)x >> 1, (unsigned)y));
        return (x & 1) ? v & 15 : v >> 4;
    }
    return *HG__PTR(hg__fbaddr((unsigned)x, (unsigned)y));
}

void hg_line(int x0, int y0, int x1, int y1, unsigned c)
{
    int dx, dy, sx, sy, err, e2, rx, ry, run;

    if (y0 == y1) {
        if (x1 < x0) {
            dx = x0; x0 = x1; x1 = dx;
        }
        hg_fill(x0, y0, (unsigned)(x1 - x0 + 1), 1, c);
        return;
    }
    if (x0 == x1) {
        if (y1 < y0) {
            dy = y0; y0 = y1; y1 = dy;
        }
        hg_fill(x0, y0, 1, (unsigned)(y1 - y0 + 1), c);
        return;
    }
    dx = x1 > x0 ? x1 - x0 : x0 - x1;
    dy = y1 > y0 ? y1 - y0 : y0 - y1;
    sx = x0 < x1 ? 1 : -1;
    sy = y0 < y1 ? 1 : -1;
    err = dx - dy;
    if (hg__kind == HG__FULL) {
        hg__cpu_sync();
        for (;;) {
            rx = x0;
            ry = y0;
            if (fbxy(&rx, &ry))
                put((unsigned)rx, (unsigned)ry, c);
            if (x0 == x1 && y0 == y1)
                break;
            e2 = 2 * err;
            if (e2 > -dy) {
                err -= dy;
                x0 += sx;
            }
            if (e2 < dx) {
                err += dx;
                y0 += sy;
            }
        }
        return;
    }
    /* a window: one fill record per horizontal (or vertical) run of pixels */
    rx = x0;
    ry = y0;
    run = 1;
    for (;;) {
        if (x0 == x1 && y0 == y1)
            break;
        e2 = 2 * err;
        if (e2 > -dy) {
            err -= dy;
            x0 += sx;
        }
        if (e2 < dx) {
            err += dx;
            y0 += sy;
        }
        if (dx >= dy ? y0 == ry : x0 == rx)
            ++run;
        else {
            if (dx >= dy)
                hg_fill(sx > 0 ? rx : rx - run + 1, ry, (unsigned)run, 1, c);
            else
                hg_fill(rx, sy > 0 ? ry : ry - run + 1, 1, (unsigned)run, c);
            rx = x0;
            ry = y0;
            run = 1;
        }
    }
    if (dx >= dy)
        hg_fill(sx > 0 ? rx : rx - run + 1, ry, (unsigned)run, 1, c);
    else
        hg_fill(rx, sy > 0 ? ry : ry - run + 1, 1, (unsigned)run, c);
}

/* ---------------------------------------------------------------- text */

/* the 1 bpp picture of a string: n bytes a row, 10 rows (hg_text.s) */
void hg__strip(unsigned char *dst, const char *s, unsigned n);

static void text4(int x, int y, const char *s, unsigned ink, unsigned paper)
{
    /* 16 colours: the CPU, pixel by pixel (Ali's expand writes whole bytes) */
    unsigned r, b, g;
    int px, py;
    const unsigned char *f;
    hg__cpu_sync();
    for (; *s; s++, x += 8) {
        g = (unsigned char)*s;
        f = hg__font + ((g >= 32 && g < 127) ? (g - 32) * 10 : 0);
        for (r = 0; r < 10; r++)
            for (b = 0; b < 8; b++) {
                px = x + (int)b;
                py = y + (int)r;
                if ((f[r] << b) & 0x80) {
                    if (fbxy(&px, &py))
                        put((unsigned)px, (unsigned)py, ink);
                } else if (paper != HG_NONE && fbxy(&px, &py))
                    put((unsigned)px, (unsigned)py, paper);
            }
    }
}

static void text(int x, int y, const char *s, unsigned ink, unsigned paper)
{
    unsigned n, max;
    unsigned char *buf;
    hz_drawrec __far *r;
    unsigned long a;

    if (!s)
        return;
    if (hg__kind == HG__FULL && hg__mode == FS_640X4) {
        text4(x, y, s, ink, paper);
        return;
    }
    n = strlen(s);
    max = (hg__kind == HG__WINDOW ? hg_w : hg_fb_stride) / 8 + 1;
    if (n > max)
        n = max;
    if (!n)
        return;
    buf = (unsigned char *)hg__arena(n * 10);  /* (first: it may send the records) */
    if (!buf)
        return;
    r = hg__rec(paper == HG_NONE ? LS_EXPANDK : LS_EXPAND, x, y, n * 8, 10);
    if (!r)
        return;
    hg__strip(buf, s, n);
    r->c1 = (unsigned char)ink;
    r->c2 = (unsigned char)paper;
    a = (unsigned long)buf + (unsigned)hg__cuty * n + ((unsigned)hg__cutx >> 3);
    *(unsigned long __far *)&r->u.s = a;
    r->flags = (unsigned char)((hg__cutx & 7) << 4);
    r->stride = n;
}

void hg_text(int x, int y, const char *s, unsigned ink)
{
    text(x, y, s, ink, HG_NONE);
}

void hg_text_bg(int x, int y, const char *s, unsigned ink, unsigned paper)
{
    text(x, y, s, ink, paper);
}

unsigned hg_text_width(const char *s)
{
    return s ? strlen(s) * 8 : 0;
}
