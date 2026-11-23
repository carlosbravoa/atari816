/* SPDX-License-Identifier: GPL-3.0-or-later */
/* Fog of war in C: upstream's src/losasm.asm (reveal_fan_asm,
   reveal_reset_box, reveal_get_box), called by los.c los_reveal. The fan
   of sight rays that uncovers the map in front of a unit: a ray to every
   ring tile RANGE away in the view cone, on the unit's level, the one
   above and the one below; see losasm.asm's comments for the geometry.
   The assembly patches its walk's constants into its own instructions per
   octant; here they are the variables p_* of the same names. Coordinates
   and the step bookkeeping are bytes, offsets into the tables 16 bits, as
   in the assembly. Build with -DXD_HAVE_LOS. */
#include "xcompat.h"
#include "plat.h"
#include "los.h"

typedef unsigned short u16;
typedef unsigned char u8;

#define LF_WEST   0x01
#define LF_NORTH  0x02
#define LF_OBJECT 0x04
#define LF_FLOOR  0x08
#define SEEN_BIT_ 0x10
#define RANGE     20

/* los.c's parameter block (the same declaration). */
struct RevealFan {
    unsigned lfseg, seenseg, pi, mxy;
    unsigned char mx, my, x, y, z, up;
    signed char vx, vy, sx, sy;
};

static const u8 far *lf;                /* DS: the sight flags */
static u8 far *seen;                    /* ES: the seen table */
static u16 pi, mxy;
static u8 mxb, myb, ux, uy, uz, up;
static signed char vx, vy, sx, sy;
static int revealed;
static u8 key, majstep, c0[2], ends[2], zcur;
static u8 box[6] = { 255, 0, 255, 0, 255, 0 };     /* x0 x1 y0 y1 z0 z1 */

/* the patched constants */
static u8 p_neg, p_pos, p_end, p_mstep, p_lim, p_h, p_h2;
static u16 p_add, p_addd, p_a1, p_a2, p_a3, p_b1, p_b2, p_b3;
static u8 p_a1b, p_a3b, p_b1b, p_b3b;

/* the walk's registers */
static u16 si, dxr, bpr, cxr;
static u8 bl, bh, ah;

void __cdecl reveal_reset_box(void)
{
    box[0] = box[2] = box[4] = 255;
    box[1] = box[3] = box[5] = 0;
}

void __cdecl reveal_get_box(unsigned char *b)
{
    int i;

    for (i = 0; i < 6; i++)
        b[i] = box[i];
}

/* A tile becomes seen: table offset di, the ray's major and minor
   coordinate mj, mn; under: the tile under the ray's level. */
static void seen_new(u16 di, u8 mj, u8 mn, int under)
{
    u8 x = mj, y = mn, z = (u8)(zcur - (under ? 1 : 0));

    if (key & 1) {
        x = mn;
        y = mj;
    }
    seen[di] |= SEEN_BIT_;
    revealed = 1;
    if (x < box[0]) box[0] = x;
    if (x > box[1]) box[1] = x;
    if (y < box[2]) box[2] = y;
    if (y > box[3]) box[3] = y;
    if (z < box[4]) box[4] = z;
    if (z > box[5]) box[5] = z;
}

/* Walks a ray on one level until its major coordinate is p_end: 0 when
   it got there, 1 when the ray stopped before. Entered at .wall (the
   assembly's walk.wall) with wall_al >= 0: the tile at si with flags
   wall_al is seen through a wall or floor and ends the ray. */
static int walk_from(int wall_al)
{
    u8 al;
    unsigned long sum;

    if (wall_al >= 0) {
        al = (u8)wall_al;
        goto wall;
    }
    for (;;) {
        bl = (u8)(bl + ah);
        sum = (unsigned long)dxr + bpr;
        dxr = (u16)sum;
        if (sum > 0xFFFFUL)
            goto diag;
        if (lf[si] & p_neg)
            return 1;
        si = (u16)(si + p_add);
        al = lf[si];
        if (!(al & p_pos))
            goto mark;
wall:
        al |= LF_OBJECT;
mark:
        if (!(seen[si] & SEEN_BIT_))
            seen_new(si, bl, bh, 0);
        if (!(al & LF_FLOOR) && cxr) {
            u16 di = (u16)(si - cxr);
            if (!(seen[di] & SEEN_BIT_))
                seen_new(di, bl, bh, 1);
        }
        if (al & LF_OBJECT)
            return 1;
        if (bl != p_end)
            continue;
        return 0;
diag:
        bh = (u8)(bh + p_mstep);
        if (bh >= p_lim)
            return 1;
        {
            u8 dh = (u8)(dxr >> 8);
            int closed;
            if (dh > p_h)
                goto route_b;
            if ((lf[(u16)(si + p_a1)] & p_a1b) || (lf[(u16)(si + p_a2)] & LF_OBJECT)
                || (lf[(u16)(si + p_a3)] & p_a3b)) {
                if (dh != p_h2) {
                    closed = 1;
                    goto to;
                }
                goto route_b;
            }
            closed = 0;
            goto to;
route_b:
            closed = (lf[(u16)(si + p_b1)] & p_b1b) || (lf[(u16)(si + p_b2)] & LF_OBJECT)
                     || (lf[(u16)(si + p_b3)] & p_b3b);
to:
            al = closed ? LF_OBJECT : 0;
            si = (u16)(si + p_addd);
            al |= lf[si];
            goto mark;
        }
    }
}

static int walk(void)
{
    return walk_from(-1);
}

/* Sets the walk up for the rays of octant k. */
static void octant(u8 k)
{
    u8 al = ux, ahh = uy, dl = mxb, dh = myb, cl = LF_WEST, ch = LF_NORTH, t, bhh;
    u16 ax = 1, dx = mxb, s = 0, d = 0, w;

    key = k;
    if (k & 1) {
        t = al; al = ahh; ahh = t;
        t = dl; dl = dh; dh = t;
    }
    c0[0] = al;
    c0[1] = ahh;
    p_lim = dh;
    if (k & 2) {
        majstep = 0xFF;
        dl = al;
    } else {
        majstep = 1;
        dl = (u8)(dl - al - 1);
    }
    dh = dl;
    if (dl > RANGE / 2)
        dl = RANGE / 2;
    if (dh > RANGE)
        dh = RANGE;
    if (k & 2) {
        dl = (u8)-dl;
        dh = (u8)-dh;
    }
    ends[0] = (u8)(dl + al);
    ends[1] = (u8)(dh + al);
    if (k & 1) {
        w = ax; ax = dx; dx = w;
        t = cl; cl = ch; ch = t;
    }
    if (k & 2) {
        ax = (u16)-ax;
        p_neg = cl;
        p_pos = 0;
    } else {
        s = ax;
        p_neg = 0;
        p_pos = cl;
    }
    bhh = 1;
    if (k & 4) {
        dx = (u16)-dx;
        bhh = 0xFF;
    } else
        d = dx;
    p_mstep = bhh;
    p_add = ax;
    p_a1 = s;
    p_a1b = cl;
    p_a2 = ax;
    p_b1 = d;
    p_b1b = ch;
    p_b2 = dx;
    d = (u16)(d + ax);
    p_a3 = d;
    p_a3b = ch;
    s = (u16)(s + dx);
    p_b3 = s;
    p_b3b = cl;
    p_addd = (u16)(ax + dx);
}

static void level(u16 di);

/* The rays to one ring tile (vx, vy). */
static void ray(void)
{
    signed char a = vx, h = vy, t;
    u8 k = 0, al, ahh;

    if (a != RANGE && a != -RANGE) {
        t = a; a = h; h = t;
        k = 1;
    }
    if (a < 0)
        k |= 2;
    if (h < 0) {
        k |= 4;
        h = (signed char)-h;
    }
    if (k != key)
        octant(k);
    al = (u8)h;
    if (al >= RANGE) {
        bpr = 0xFFFF;
        dxr = 0xFFFF;
        al = ahh = 0xFF;
    } else {
        static u8 steps[RANGE];
        static int made;
        if (!made) {
            int i;
            for (i = 0; i < RANGE; i++)
                steps[i] = (u8)(i * 256 / RANGE);
            made = 1;
        }
        ahh = steps[al];
        bpr = (u16)(ahh << 8);
        al = ahh;
        dxr = 0x8000;
        if (key & 4) {
            dxr = 0x7F00;
            al = (u8)(al - 2);
        }
        {
            int carry = al & 1;
            al >>= 1;
            ahh = carry ? 0xFF : al;
        }
    }
    p_h = al;
    p_h2 = ahh;
    bl = c0[0];
    bh = c0[1];
    if (ends[0] == bl)
        return;
    p_end = ends[0];
    si = pi;
    zcur = uz;
    cxr = uz ? mxy : 0;
    ah = majstep;
    if (walk())
        return;
    if (ends[1] == bl)
        return;
    p_end = ends[1];
    {
        u16 s_si = si, s_dx = dxr, s_cx = cxr;
        u8 s_bl = bl, s_bh = bh;
        walk();
        if (up) {
            si = s_si; dxr = s_dx; cxr = s_cx; bl = s_bl; bh = s_bh;
            cxr = mxy;
            zcur++;
            level(mxy);
            zcur--;
        }
        si = s_si; dxr = s_dx; cxr = s_cx; bl = s_bl; bh = s_bh;
    }
    if (!cxr)
        return;
    {
        u16 di = (u16)-cxr;
        zcur--;
        if (!zcur)
            cxr = 0;
        level(di);
    }
}

/* The rest of a ray that changes level with its next step: di = from a
   tile to the one above or below it; zcur and cxr are the new level's. */
static void level(u16 di)
{
    p_add = (u16)(p_add + di);
    p_addd = (u16)(p_addd + di);
    if (!(di & 0x8000)) {
        unsigned long sum = (unsigned long)dxr + bpr;
        u16 to = (u16)(si + (sum > 0xFFFFUL ? p_addd : p_add));
        if (lf[to] & LF_FLOOR) {
            bl = (u8)(bl + ah);
            dxr = (u16)sum;
            if (sum > 0xFFFFUL) {
                bh = (u8)(bh + p_mstep);
                if (bh >= p_lim)
                    goto end;
            }
            si = to;
            walk_from(lf[si]);
            goto end;
        }
    } else if (lf[si] & LF_FLOOR)
        goto end;
    {
        u8 old = p_end;
        int r;
        p_end = (u8)(bl + ah);
        r = walk();
        p_end = old;
        if (r || bl == old)
            goto end;
        p_add = (u16)(p_add - di);
        p_addd = (u16)(p_addd - di);
        walk();
        return;
    }
end:
    p_add = (u16)(p_add - di);
    p_addd = (u16)(p_addd - di);
}

int __cdecl reveal_fan_asm(const struct RevealFan *p)
{
    int left;

    pi = (u16)p->pi;
    mxy = (u16)p->mxy;
    mxb = p->mx;
    myb = p->my;
    ux = p->x;
    uy = p->y;
    uz = p->z;
    up = p->up;
    vx = p->vx;
    vy = p->vy;
    sx = p->sx;
    sy = p->sy;
    revealed = 0;
    key = 0xFF;
    lf = (const u8 far *)MK_FP(p->lfseg, 0);
    seen = (u8 far *)MK_FP(p->seenseg, 0);
    for (left = 2 * RANGE + 1; left; left--) {
        ray();
        vx = (signed char)(vx + sx);
        vy = (signed char)(vy + sy);
        if (vx == vy || vx == -vy) {
            signed char t = sx;
            sx = (signed char)-sy;
            sy = t;
        }
    }
    return revealed;
}
