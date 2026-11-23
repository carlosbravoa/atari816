/* SPDX-License-Identifier: GPL-3.0-or-later */
/* The battlescape's floor pass in C: upstream's src/rendasm.asm (rd_setup,
   rd_level), called by render.c draw_region. Per level, every tile whose
   sprites can touch the redraw rectangle, column by column (x, then y):
   its floor is drawn (ground floors with the OR blitter on the cleared
   area) and the tiles with walls, objects, units or the cursor are
   collected in late[] for the second pass; with cover data (packs made by
   tools/occlude.py) covered floors are left out. The assembly's block
   (B_*) is the static struct below; its arithmetic is 16-bit where the
   assembly's is (u16 / short). Build with -DXD_HAVE_REND. */
#include "xcompat.h"
#include "plat.h"
#include "gfx.h"
#include "map.h"
#include "pak.h"
#include "path.h"
#include "render.h"
#include "unit.h"

typedef unsigned short u16;

#define SEEN_BIT_   0x10
#define MAX_LATE_   400
#define LATE_HID    0x40
#define LATE_ROOF_  0x8000u
#define M_SPRITE    0
#define M_PLEVEL    3
#define M_ORSPR     14
#define OR_NONE_    0x7FFF
#define COV_COL     68

extern int g_cursor_on, g_cur_x, g_cur_y, g_cur_z;
extern unsigned g_occ_count;

#define W16(p)      ((u16)((p)[0] | (p)[1] << 8))

/* (the Atari816: horizon/hz_rend.s reads and writes it by offset: B_* there) */
#if defined(__CC816__)
#define b rd_b
#define REND_ASM 1
#else
static
#endif
struct rd_bs {
    const unsigned char far *mcd;
    unsigned char **spr;
    unsigned *late;
    unsigned char far *cov;
    int top, ega, w, xsh;
    int mx, my, bseg, cx0, cy0, cx1, cy1, camx, camy;
    int ua0, ub, vc, vd, z;
    u16 zbase;
    int curx, cury, nlate;
    int x, n, y;
    u16 idx;
    int sx, sy, zy, yend;
    unsigned orspr;
    int occ, look, covon, up1, up2;
    int c, s0, s1, s2, s3, sf;
    int xlo, xhi;
} b;

/* roof: the 13 tiles of the level above whose diamonds meet a tile's
   reach; quad: the owners of a floor's quads top, bottom, left, right on
   the level above, then the tile covering all of it two levels up. */
static const signed char rq[18][2] = {
    { 0, 0 }, { 1, 1 }, { -1, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 },
    { 2, 1 }, { 1, 2 }, { -1, -2 }, { -2, -1 }, { 2, 2 }, { -2, -2 },
    { 1, 1 }, { 2, 2 }, { 1, 2 }, { 2, 1 }, { 3, 3 }
};
#define N_ROOF  13
#define Q0      13              /* quad[] in rq[] */
#if defined(REND_ASM)
#define roofoff rd_roofoff
u16 roofoff[18];
int rd_rqx[18], rd_rqy[18];             /* rq[] for hz_rend.s */
static u16 roofmx, rooflev;
#else
static u16 roofoff[18], roofmx, rooflev;
#endif

/* sar: the assembly's arithmetic shift of a 16-bit value. */
static int sar(int v, int k)
{
    short s = (short)v;
    return s < 0 ? -(int)(((unsigned)(-(long)s) + (1u << k) - 1) >> k) : s >> k;
}

void __cdecl rd_setup(int top, const void *mcd, unsigned char **spr, unsigned *late,
                      unsigned *cov, int occ)
{
    u16 mxy;
    int i;

    b.top = top;
    b.mcd = (const unsigned char far *)mcd;
    b.spr = spr;
    b.late = late;
    b.cov = (unsigned char far *)cov;
    b.occ = occ;
    b.look = occ ? 3 : 0;
    b.mx = (int)g_mx;
    b.my = (int)g_my;
    b.bseg = (int)g_bufseg;
    b.cx0 = g_clip_x0;
    b.cy0 = g_clip_y0;
    b.cx1 = g_clip_x1;
    b.cy1 = g_clip_y1;
    b.camx = g_cam_x;
    b.camy = g_cam_y;
    if (g_video == VIDEO_EGA) {
        b.ega = 1;
        b.w = 40;
        b.xsh = 3;
    } else {
        b.ega = 0;
        b.w = 80;
        b.xsh = 2;
    }
    b.ua0 = sar(b.cx0 - 32 - b.camx, 4);
    b.ub = sar(b.cx1 - 1 - b.camx, 4);
    b.cx1 -= 32;
    mxy = (u16)(b.mx * b.my);
    if (mxy != rooflev || (u16)b.mx != roofmx) {
        rooflev = mxy;
        roofmx = (u16)b.mx;
        for (i = 0; i < 18; i++)
            roofoff[i] = (u16)(rq[i][1] * b.mx + rq[i][0] + mxy);
        roofoff[17] = (u16)(roofoff[17] + mxy);     /* two levels up */
#if defined(REND_ASM)
        for (i = 0; i < 18; i++) {
            rd_rqx[i] = rq[i][0];
            rd_rqy[i] = rq[i][1];
        }
#endif
    }
}

/* ZF clear (1) if tile index t holds a full floor that is seen. */
static int full_floor(u16 t)
{
    unsigned rec;

    if (g_seen && !(g_seen[t] & SEEN_BIT_))
        return 0;
    rec = g_map[(u16)(t << 2)];
    if (!rec)
        return 0;
    return (b.mcd[(u16)(rec << 4) + M_ORSPR + 1] & 0x80) != 0;
}

static int floor_at(u16 t)
{
    if (!g_map[(u16)(t << 2)])
        return 0;
    return full_floor(t);
}

/* Entry e of rq[]: 1 if the tile that far from b.x, b.y, b.idx holds a
   full floor that is seen. */
static int up_floor(int e)
{
    if ((unsigned)(u16)(rq[e][0] + b.x) >= (unsigned)b.mx)
        return 0;
    if ((unsigned)(u16)(rq[e][1] + b.y) >= (unsigned)b.my)
        return 0;
    return floor_at((u16)(roofoff[e] + b.idx));
}

static int roofed(void)
{
    int e;

    for (e = 0; e < N_ROOF; e++)
        if (!up_floor(e))
            return 0;
    return 1;
}

static int col_setup(int x)
{
    int ylo, yhi, t;

    b.x = x;
    ylo = x - b.ub;
    t = b.vc + 1 - x;
    if (t > ylo)
        ylo = t;
    if (ylo < 0)
        ylo = 0;
    yhi = x - b.ua0 - 1;
    t = b.vd - x;
    if (t < yhi)
        yhi = t;
    if (yhi > b.my - 1)
        yhi = b.my - 1;
    if (yhi - ylo < 0)
        return 0;
    b.n = yhi - ylo + 1;
    b.y = ylo;
    b.yend = ylo + b.n;
    b.idx = (u16)(ylo * b.mx + x + b.zbase);
    return 1;
}

static int slot_of(int col)
{
    return (col & 3) * COV_COL;
}

static void slots(void)
{
    int a, *s[3], i;

    s[0] = &b.s1;
    s[1] = &b.s2;
    s[2] = &b.s3;
    b.s0 = a = slot_of(b.c);
    for (i = 0; i < 3; i++) {
        if (a == 0)
            a += 4 * COV_COL;
        a -= COV_COL;
        *s[i] = a;
    }
    for (i = 0; i < b.n; i++)
        b.cov[b.s0 + b.y + 3 + i] = 0;
}

static void box(void)
{
    b.sx = (short)(((b.x - b.y) << 4) + b.camx);
    b.sy = (short)(((b.x + b.y) << 3) - b.zy);
}

/* The record rec of the tile's floor: draws it. */
static void floor_draw(unsigned rec)
{
    const unsigned char far *m = b.mcd + (u16)(rec << 4);
    unsigned orspr = W16(m + M_ORSPR) & OR_NONE_;

    if (orspr == OR_NONE_) {
        box();
        goto sprite;
    }
    b.orspr = orspr;
    if (b.covon) {
        unsigned open = ~b.cov[b.sf + b.y + 3] & 15, q;
        if (!open)
            goto covered;
        if (!b.up1)
            goto open_;
        for (q = 0; q < 4; q++)
            if (open >> q & 1)
                if (!up_floor(Q0 + q)) {
                    if (!b.up2)
                        goto open_;
                    if (up_floor(Q0 + 4))
                        goto covered;
                    goto open_;
                }
covered:
        g_occ_count++;
        return;
    }
open_:
    box();
    if (b.z != 0)
        goto sprite;
    {
        const unsigned char *s = b.spr[orspr];
        int r0 = b.sy + s[0], r1 = r0 + s[1];

        if (r1 <= b.cy0 || r0 >= b.cy1)
            return;
        if (b.sx < b.cx0 || b.sx > b.cx1 || r0 < b.cy0 || r1 > b.cy1) {
            gfx_sprite_or(orspr, b.sx, b.sy);
            return;
        }
        {
            u16 dest = (u16)(b.sy * b.w + sar(b.sx, b.xsh));
            if (b.ega)
                blit_or(s, (unsigned)b.bseg, dest);
            else
                blitc_or(s, (unsigned)b.bseg, dest);
        }
        return;
    }
sprite:
    gfx_sprite(W16(m + M_SPRITE), b.sx, b.sy - m[M_PLEVEL]);
}

static void col_floors(void)
{
    int i;
    u16 idx = b.idx;
    int y0 = b.y;

    b.sf = slot_of(b.x);
    for (i = 0; i < b.n; i++, idx = (u16)(idx + b.mx)) {
        unsigned rec = g_map[(u16)(idx << 2)];
        if (!rec)
            continue;
        if (g_seen && !(g_seen[idx] & SEEN_BIT_))
            continue;
        b.y = y0 + i;
        b.idx = idx;
        floor_draw(rec);
    }
}

/* A seen tile's walls' and object's cover masks mark the quads of its
   floor and of the floors behind it. */
static void scatter(const unsigned char far *t)
{
    unsigned cx = 0, cl, ch, k;
    int y3, si;

    if (!b.occ)
        return;
    for (k = 1; k <= 3; k++)
        if (t[k])
            cx |= W16(b.mcd + (u16)(t[k] << 4) + M_ORSPR);
    if (!cx)
        return;
    cl = cx & 0xFF;
    ch = cx >> 8;
    y3 = b.y + 3;
    si = b.s0 + y3;
    b.cov[si] |= (unsigned char)(cl & 15);
    if (ch & 0x20)
        b.cov[si - 1] |= 4;
    si = b.s1 + y3;
    b.cov[si - 1] |= (unsigned char)(cl >> 4);
    if (ch & 0x10)
        b.cov[si] |= 8;
    if (ch & 0x80)
        b.cov[si - 2] |= 4;
    si = b.s2 + y3;
    b.cov[si - 2] |= (unsigned char)(ch & 15);
    if (ch & 0x40)
        b.cov[si - 1] |= 8;
}

static void col_late(void)
{
    unsigned char curleft;
    int i, n = b.n, y0 = b.y;
    u16 idx = b.idx;

    curleft = (unsigned char)(b.x == b.curx ? b.yend - b.cury : 0);
    for (i = 0; i < n; i++, idx = (u16)(idx + b.mx)) {
        unsigned char left = (unsigned char)(n - i);
        const unsigned char far *t = g_map + (u16)(idx << 2);
        unsigned char u = g_unit_at ? g_unit_at[idx] : 0;
        unsigned dx;
        int hidden;

        if (left != curleft && !t[1] && !t[2] && !t[3] && !u)
            continue;
        b.y = y0 + i;
        b.idx = idx;
        hidden = g_seen && !(g_seen[idx] & SEEN_BIT_);
        if (left == curleft) {
            if (hidden)
                dx = LATE_HID;
            else {
                scatter(t);
                dx = 0;
            }
        } else {
            if (hidden)
                continue;
            if (t[1] | t[2] | t[3])
                scatter(t);
            dx = 0;
            if (b.up1 && roofed())
                dx = LATE_ROOF_;
        }
        if (b.nlate >= MAX_LATE_) {
            b.covon = 0;
            continue;
        }
        b.late[b.nlate++] = ((unsigned)(b.x & 0xFF) << 8 | (b.y & 0xFF)) | dx;
    }
    b.y = y0;
    b.idx = (u16)(b.idx);
}

#if defined(REND_ASM)
#include <stddef.h>
/* horizon/hz_rend.s: rd_level's columns (col_setup, slots, col_late with
   scatter and roofed, col_floors with floor_draw) as the C below does them */
void rd_cols(void);
_Static_assert(offsetof(struct rd_bs, cov) == 12 && offsetof(struct rd_bs, mx) == 24
               && offsetof(struct rd_bs, idx) == 66 && offsetof(struct rd_bs, orspr) == 76
               && offsetof(struct rd_bs, xhi) == 102 && sizeof(struct rd_bs) == 104,
               "hz_rend.s's B_* offsets");
#endif

int __cdecl rd_level(int z)
{
    int a, t, c;

    b.z = z;
    b.nlate = 0;
    b.curx = -1;
    if (g_cursor_on && z == g_cur_z) {
        b.curx = g_cur_x;
        b.cury = g_cur_y;
    }
    b.zbase = (u16)((u16)(z * b.mx) * b.my);
    b.zy = (short)(z * 24 - b.camy);
    b.vc = sar(b.zy + b.cy0 - 40, 3);
    b.vd = sar(b.zy + b.cy1 + 23, 3);
    b.covon = b.occ;
    b.up1 = b.up2 = 0;
    if (b.occ && z + 1 <= b.top) {
        b.up1 = 1;
        if (z + 2 <= b.top)
            b.up2 = 1;
    }
    a = b.ua0 + 1;
    t = b.vc + 2 - b.my;
    if (t > a)
        a = t;
    t = sar(b.vc + b.ua0 + 3, 1);
    if (t > a)
        a = t;
    if (a < 0)
        a = 0;
    b.xlo = a;
    a = b.mx - 1;
    if (b.vd < a)
        a = b.vd;
    t = b.ub + b.my - 1;
    if (t < a)
        a = t;
    t = sar(b.ub + b.vd, 1);
    if (t < a)
        a = t;
    b.xhi = a;
#if defined(REND_ASM)
    if (!b.ega) {
        rd_cols();                      /* the loop below, in assembly */
        return b.nlate;
    }
#endif
    for (c = b.xlo; c <= b.xhi + b.look; c++) {
        b.c = c;
        if (c <= b.xhi && col_setup(c)) {
            if (b.occ)
                slots();
            col_late();
        }
        t = c - b.look;
        if (t >= b.xlo && col_setup(t))
            col_floors();
    }
    return b.nlate;
}
