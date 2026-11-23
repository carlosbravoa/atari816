/* SPDX-License-Identifier: GPL-3.0-or-later */
/* The voxel line in C: upstream's src/voxasm.asm vox_run, called by vox.c
   vox_line (OpenXcom's TileEngine::calculateLine with voxel checks). The
   run walks the line in OpenXcom's frame (major axis, two minor ones,
   Bresenham drifts) through the voxels and checks each against the LOFT
   shapes of the tile's four parts and the unit there; where a tile may
   hold a unit or a grav lift it returns R_CALL so that C fills in what
   counts there (vox.c tile_info), then goes on with that voxel's check
   (resume = 1). Empty layers of a plain tile are passed in one go. The
   assembly's 16-bit arithmetic is kept (u16 / short); its block is vox.c's
   struct VoxRun, read here by field. Build with -DXD_HAVE_VOX. The host runs
   this C (the reference); the Atari816 runs horizon/hz_vox.s, the same walk
   in assembly (PORTING-NOTES.md 4f), on the block itself. -DVOXCHECK (the
   Atari816): each new line run by both, differences on the console. */
#include "xcompat.h"
#include "plat.h"
#if defined(VOXCHECK)
#include <stdio.h>
#endif

typedef unsigned short u16;
typedef unsigned char u8;

#define R_OUT   5
#define R_CALL  6
#define EMPTY   (-2)

#define TF_CALL   1
#define TF_PARTS  2
#define TF_UNIT   4
#define TF_LIFT   8
#define MCD_GRAVLIFT_ 0x20

/* vox.c's block (the same declaration). */
#pragma pack(1)
struct VoxRun {
    unsigned mapseg, unitseg, voxseg, mcdseg, mcdoff;
    unsigned base, cols, tmask, tval, gen, rows;
    unsigned mx, my, mz, mxy;
    unsigned char excl, phase;
    int tx, ty, tz;
    unsigned ti;
    unsigned char ox, oy, oz, tfl;
    unsigned col[4], move[3];
    unsigned char axis[3], ext;
    int n, d[3], r1, r2;
    unsigned k, sp;
    int ubot, utop;
    unsigned char utpl, pad;
    unsigned lmask, rv[4], rva, urv;
    unsigned char key, ukey;
    int o[3], t[3], f0[3];
    int hit[3];
};
#pragma pack()

/* (speed) the block is copied in at vox_run's start and out at its end: the run reads
   and writes it all the time, and a static's fields are cheaper than a far pointer's;
   the map, MCD and unit tables' pointers are made once a call, not at every tile */
static struct VoxRun vr;
#define v (&vr)
static const u8 far *vox;               /* DS: the voxel blob's segment, offset 0 */
static const u8 far *vmap, *vmcd, *vunit;

#define VW(off)     ((u16)(vox[(u16)(off)] | vox[(u16)((off) + 1)] << 8))

static void extend(struct VoxRun far *b);

static u8 *oxyz(int a)
{
    return a == 0 ? &v->ox : a == 1 ? &v->oy : &v->oz;
}

/* The tile at v->ti: its parts' columns and whether C must add to them. */
static void enter_tile(void)
{
    const u8 far *map = vmap;
    const u8 far *mcd = vmcd;
    u16 di = (u16)(v->ti << 2), si;
    u8 dl = 0;
    int p;

    v->key = v->ukey = 0xFF;
    v->lmask = 0;
    if (!(map[di] | map[(u16)(di + 1)] | map[(u16)(di + 2)] | map[(u16)(di + 3)])) {
        v->col[0] = v->col[1] = v->col[2] = v->col[3] = 0;
    } else {
        for (p = 0; p < 4; p++) {
            u8 rec = map[(u16)(di + p)];
            v->col[p] = 0;
            if (rec) {
                u8 vcol = mcd[(u16)((rec << 4) + v->mcdoff + 6)];
                if (vcol) {
                    u16 bx = (u16)((vcol << 2) + v->cols);
                    v->lmask = (u16)(v->lmask | VW(bx + 2));
                    v->col[p] = (u16)(VW(bx) + v->base);
                    dl |= TF_PARTS;
                }
            }
        }
        if (map[di] && (mcd[(u16)(map[di] * 16 + v->mcdoff + 8)] & MCD_GRAVLIFT_)) {
            dl |= TF_CALL;
            goto done;
        }
    }
    si = (u16)v->ti;
    if (v->excl != 255) {
        const u8 far *ua = vunit;
        u8 u = ua[si];
        if (u) {
            if (u != v->excl)
                dl |= TF_CALL;
        } else if (v->tz != 0) {
            si = (u16)(si - v->mxy);
            u = ua[si];
            if (u && u != v->excl)
                dl |= TF_CALL;
        }
    }
done:
    v->tfl = dl;
}

/* One voxel along axis code c (2 * axis + backwards); 1 when it left the map. */
static int move(u8 c)
{
    switch (c) {
    case 0:
        if (++v->ox < 16)
            return 0;
        v->ox = 0;
        v->tx = (short)(v->tx + 1);
        v->ti = (u16)(v->ti + 1);
        if ((u16)v->tx >= (u16)v->mx)
            return 1;
        break;
    case 1:
        if ((signed char)--v->ox >= 0)
            return 0;
        v->ox = 15;
        v->ti = (u16)(v->ti - 1);
        v->tx = (short)(v->tx - 1);
        if ((short)v->tx < 0)
            return 1;
        break;
    case 2:
        if (++v->oy < 16)
            return 0;
        v->oy = 0;
        v->ti = (u16)(v->ti + v->mx);
        v->ty = (short)(v->ty + 1);
        if ((u16)v->ty >= (u16)v->my)
            return 1;
        break;
    case 3:
        if ((signed char)--v->oy >= 0)
            return 0;
        v->oy = 15;
        v->ti = (u16)(v->ti - v->mx);
        v->ty = (short)(v->ty - 1);
        if ((short)v->ty < 0)
            return 1;
        break;
    case 4:
        if (++v->oz < 24)
            return 0;
        v->oz = 0;
        v->ti = (u16)(v->ti + v->mxy);
        v->tz = (short)(v->tz + 1);
        if ((u16)v->tz >= (u16)v->mz)
            return 1;
        break;
    default:
        if ((signed char)--v->oz >= 0)
            return 0;
        v->oz = 23;
        v->ti = (u16)(v->ti - v->mxy);
        v->tz = (short)(v->tz - 1);
        if ((short)v->tz < 0)
            return 1;
        break;
    }
    enter_tile();
    return 0;
}

static u16 lmask_here(void)
{
    return (u16)((u16)v->lmask >> (v->oz >> 1));
}

/* The moves along the axis of code c that stay in the tile and in its
   empty layers (the voxel's own layer is empty). */
static u16 room_of(u8 c)
{
    u16 ax, dx;
    u8 bl;

    switch (c) {
    case 0: return (u16)(15 - v->ox);
    case 1: return v->ox;
    case 2: return (u16)(15 - v->oy);
    case 3: return v->oy;
    case 4:
        dx = lmask_here();
        ax = (u16)((v->oz & 1) ^ 1);
        bl = (u8)(v->oz >> 1);
        for (;;) {
            bl++;
            if (bl >= 12)
                break;
            dx >>= 1;
            if (dx & 1)
                break;
            ax += 2;
        }
        return ax;
    default:
        dx = (u16)v->lmask;
        ax = (u16)(v->oz & 1);
        bl = (u8)(v->oz >> 1);
        for (;;) {
            if (!bl)
                break;
            bl--;
            if ((dx >> bl) & 1)
                break;
            ax += 2;
        }
        return ax;
    }
}

/* al moves along the axis of role r (in the tile: no tile change). */
static void shift(int r, u16 n)
{
    u8 c = v->axis[r], al = (u8)n;
    u8 *o = oxyz(c >> 1);

    if (c & 1)
        al = (u8)-al;
    *o = (u8)(*o + al);
}

/* ROOM: the main steps that keep minor role r (delta d, drift dr) in its
   room: (room * d0 + r) / d, at most di. */
static u16 room_limit(u16 di, u16 d, u16 dr, int r)
{
    unsigned long t;
    u16 q;

    if (!d)
        return di;
    {
        /* room is at most 23: in 16 bits while d0 < 2700 (dr < d0) */
        u16 room = room_of(v->axis[r]), d0 = (u16)v->d[0];
        if (d0 < 2700u)
            q = (u16)((u16)(room * d0 + dr) / d);
        else {
            t = (unsigned long)room * d0 + dr;
            q = (u16)(t / d);
        }
    }
    return q < di ? q : di;
}

/* MINOR: minor role r (drift *dr, delta d) after di main steps. */
static void minor(u16 di, int *dr, u16 d, int r)
{
    u16 ax = (u16)(di * d), d0 = (u16)v->d[0];

    if (ax <= (u16)*dr) {
        *dr = (short)(u16)((u16)*dr - ax);
        return;
    }
    ax = (u16)(ax - (u16)*dr);
    {
        u16 c = (u16)((u16)(ax + d0 - 1) / d0);
        *dr = (short)(u16)(c * d0 - ax);
        shift(r, c);
    }
}

/* Passes the voxels of empty layers. */
static void skip(void)
{
    u16 di = room_of(v->axis[0]);

    if (di > (u16)v->n)
        di = (u16)v->n;
    if (!di)
        return;
    di = room_limit(di, (u16)v->d[1], (u16)v->r1, 1);
    di = room_limit(di, (u16)v->d[2], (u16)v->r2, 2);
    if (!di)
        return;
    v->n = (short)(u16)((u16)v->n - di);
    v->k = (u16)(v->k + di);
    shift(0, di);
    minor(di, &v->r1, (u16)v->d[1], 1);
    minor(di, &v->r2, (u16)v->d[2], 2);
}

static const u16 ybit[16] = {
    1, 2, 4, 8, 0x10, 0x20, 0x40, 0x80, 0x100, 0x200, 0x400, 0x800, 0x1000, 0x2000, 0x4000, 0x8000
};

/* Row y (oy) of template t. */
static u16 trow(u8 t)
{
    u16 di;
    u8 al;

    if (!t)
        return 0;
    if (!(VW((u16)(t * 2 + v->tmask)) & ybit[v->oy]))
        return 0;
    al = vox[(u16)(t + v->tval)];
    if (al & 0x80) {
        u16 ax = (u16)((al & 0x7F) << 4);
        ax = (u16)((ax & 0xFF00) | (u8)(ax + v->oy));
        al = vox[(u16)(ax + v->gen)];
    }
    di = (u16)(al * 2 + v->rows);
    return VW(di);
}

/* The four parts' rows at the voxel's layer and y, and all of them ORed. */
static void rows(void)
{
    u8 layer = (u8)(v->oz >> 1);
    int p;

    v->rva = 0;
    for (p = 0; p < 4; p++) {
        u16 ax = 0, di = (u16)v->col[p];
        if (di) {
            while (layer > vox[di])
                di = (u16)(di + 2);
            ax = trow(vox[(u16)(di + 1)]);
        }
        v->rv[p] = ax;
        v->rva = (u16)(v->rva | ax);
    }
}

/* Checks the voxel: EMPTY, or what the run stops with (0-3 a part, 4 a
   unit, 0 a lift's floor, R_CALL). */
static int check(void)
{
    u8 dl = v->tfl;
    u16 cx;

    if (dl & TF_CALL)
        return R_CALL;
    if (!(dl & (TF_PARTS | TF_UNIT | TF_LIFT)))
        return EMPTY;
    if ((dl & TF_LIFT) && v->oz < 2)
        return 0;
    cx = (u16)(0x8000u >> v->ox);
    if (dl & TF_PARTS) {
        u8 k = (u8)(((v->oz & 0xFE) << 3) | v->oy);
        if (k != v->key) {
            v->key = k;
            rows();
        }
        if (v->rva & cx) {
            int p;
            for (p = 0;; p++)
                if (v->rv[p] & cx)
                    return p;
        }
    }
    if (dl & TF_UNIT) {
        short h = (short)((u8)v->tz * 24 + v->oz);
        if (h <= (short)v->ubot || h > (short)v->utop)
            return EMPTY;
        if (v->oy != v->ukey) {
            v->ukey = v->oy;
            v->urv = trow(v->utpl);
        }
        if (v->urv & cx)
            return 4;
    }
    return EMPTY;
}

/* The line in OpenXcom's frame: the far end, the roles' axes and deltas,
   the drifts, the origin's tile. */
static void setup(void)
{
    int i;
    u8 t8;

    if (v->ext)
        extend(v);
    for (i = 0; i < 3; i++) {
        short d = (short)(v->t[i] - v->o[i]);
        u8 code = (u8)(2 * i);
        if (d < 0) {
            d = (short)-d;
            code++;
        }
        v->d[i] = (u16)d;
        v->axis[i] = code;
    }
    if ((u16)v->d[1] > (u16)v->d[0]) {
        int s = v->d[0];
        v->d[0] = v->d[1];
        v->d[1] = s;
        t8 = v->axis[0];
        v->axis[0] = v->axis[1];
        v->axis[1] = t8;
    }
    if ((u16)v->d[2] > (u16)v->d[0]) {
        int s = v->d[0];
        v->d[0] = v->d[2];
        v->d[2] = s;
        t8 = v->axis[0];
        v->axis[0] = v->axis[2];
        v->axis[2] = t8;
    }
    for (i = 0; i < 3; i++) {
        v->move[i] = v->axis[i];
        v->f0[i] = v->o[v->axis[i] >> 1];
    }
    v->n = v->d[0];
    v->r1 = v->r2 = (short)((u16)v->d[0] >> 1);
    v->k = 0;
    v->ox = (u8)(v->o[0] & 15);
    v->tx = (short)((u16)v->o[0] >> 4);
    v->oy = (u8)(v->o[1] & 15);
    v->ty = (short)((u16)v->o[1] >> 4);
    v->tz = (short)((u16)v->o[2] / 24);
    v->oz = (u8)((u16)v->o[2] % 24);
    v->ti = (u16)((u16)((u16)((u16)v->tz * (u16)v->my) + (u16)v->ty) * (u16)v->mx + (u16)v->tx);
    enter_tile();
}

static int finish(int r)
{
    v->hit[0] = (short)(((u16)v->tx << 4) + v->ox);
    v->hit[1] = (short)(((u16)v->ty << 4) + v->oy);
    v->hit[2] = (short)((short)v->tz * 24 + v->oz);
    return r;
}

static int run(int resume);

/* setup's first part: a line that goes on past its target, lengthened (on the
   block itself: the same result as the C's on its copy) */
static void extend(struct VoxRun far *b)
{
    u16 m = 0, n;
    int i;

    for (i = 0; i < 3; i++) {
        short d = (short)(b->t[i] - b->o[i]);
        u16 a = (u16)(d < 0 ? -d : d);
        if (a > m)
            m = a;
    }
    if (m) {
        n = (u16)((u16)(1699 + m) / m);
        for (i = 0; i < 3; i++)
            b->t[i] = (short)(u16)((u16)((short)(b->t[i] - b->o[i]) * (short)n) + b->o[i]);
    }
}

#if defined(__CC816__)
/* The Atari816: the run in assembly (horizon/hz_vox.s), on the block itself when it
   is in the main bank (vox.c's static: always), with long pointers to the blob, the
   map, the MCD records and the unit table (made again when a segment changed). */
struct HzVx { const u8 far *vox, *map, *mcd, *unit; };
struct HzVx hz_vx;
int hz_vox_run(void *block, int resume);
static unsigned vx_seg[4] = { 0xFFFFu, 0xFFFFu, 0xFFFFu, 0xFFFFu };
static unsigned char vx_probe;          /* a main-bank object */
#endif

int __cdecl vox_run(void *block, int resume)
{
    int r;

    plat_busy_poll();                   /* (an alien turn: thousands of lines) */
#if defined(__CC816__)
    if ((unsigned long)block >> 16 == (unsigned long)(void far *)&vx_probe >> 16) {
        struct VoxRun far *b = (struct VoxRun far *)block;
        if (b->voxseg != vx_seg[0] || b->mapseg != vx_seg[1] || b->mcdseg != vx_seg[2]
            || b->unitseg != vx_seg[3]) {
            vx_seg[0] = b->voxseg;
            vx_seg[1] = b->mapseg;
            vx_seg[2] = b->mcdseg;
            vx_seg[3] = b->unitseg;
            hz_vx.vox = (const u8 far *)MK_FP(b->voxseg, 0);
            hz_vx.map = (const u8 far *)MK_FP(b->mapseg, 0);
            hz_vx.mcd = (const u8 far *)MK_FP(b->mcdseg, 0);
            hz_vx.unit = (const u8 far *)MK_FP(b->unitseg, 0);
        }
        if (!resume && b->ext)
            extend(b);
#if defined(VOXCHECK)
        /* (a check: the assembly against the C on the same block, a new line's
           first run; differences on the console) */
        if (!resume) {
            static struct VoxRun in, as;
            static unsigned nbad;
            int ra, rc;
            _fmemcpy(&in, block, sizeof in);
            ra = hz_vox_run(block, 0);
            _fmemcpy(&as, block, sizeof as);
            _fmemcpy(&vr, &in, sizeof vr);
            vox = (const u8 far *)MK_FP(v->voxseg, 0);
            vmap = (const u8 far *)MK_FP(v->mapseg, 0);
            vmcd = (const u8 far *)MK_FP(v->mcdseg, 0);
            vunit = (const u8 far *)MK_FP(v->unitseg, 0);
            v->ext = 0;
            rc = run(0);
            if ((ra != rc || _fmemcmp(&as.tx, &vr.tx, 124 - 32)) && nbad++ < 20) {
                int i;
                printf("VOXCHECK %d/%d o %d,%d,%d t %d,%d,%d: hit %d,%d,%d / %d,%d,%d k %u/%u n %d/%d\n",
                       ra, rc, in.o[0], in.o[1], in.o[2], in.t[0], in.t[1], in.t[2],
                       as.hit[0], as.hit[1], as.hit[2], vr.hit[0], vr.hit[1], vr.hit[2],
                       as.k, vr.k, as.n, vr.n);
                for (i = 32; i < 124; i++)
                    if (((u8 *)&as)[i] != ((u8 *)&vr)[i])
                        printf(" @%d %02x/%02x", i, ((u8 *)&as)[i], ((u8 *)&vr)[i]);
                printf("\n");
            }
            _fmemcpy(block, &as, sizeof as);
            return ra;
        }
#endif
        return hz_vox_run(block, resume);
    }
#endif
    _fmemcpy(&vr, block, sizeof vr);
    vox = (const u8 far *)MK_FP(v->voxseg, 0);
    vmap = (const u8 far *)MK_FP(v->mapseg, 0);
    vmcd = (const u8 far *)MK_FP(v->mcdseg, 0);
    vunit = (const u8 far *)MK_FP(v->unitseg, 0);
    r = run(resume);
    _fmemcpy(block, &vr, sizeof vr);
    return r;
}

static int run(int resume)
{
    int r;

    if (resume) {
        if (v->phase == 1)
            goto chk1;
        if (v->phase == 2)
            goto chk2;
        goto chk0;
    }
    setup();
    for (;;) {
        v->phase = 0;
        if (!(v->tfl & (TF_CALL | TF_UNIT | TF_LIFT)) && !(lmask_here() & 1))
            skip();
chk0:
        if ((r = check()) != EMPTY)
            return finish(r);
        if (!v->n)
            return finish(-1);
        v->n = (short)(v->n - 1);
        v->r2 = (short)(v->r2 - v->d[2]);
        v->r1 = (short)(v->r1 - v->d[1]);
        if ((short)v->r1 < 0) {
            v->r1 = (short)(v->r1 + v->d[0]);
            if (move(v->axis[1]))
                return finish(R_OUT);
            v->phase = 1;
chk1:
            if ((r = check()) != EMPTY)
                return finish(r);
        }
        if ((short)v->r2 < 0) {
            v->r2 = (short)(v->r2 + v->d[0]);
            if (move(v->axis[2]))
                return finish(R_OUT);
            v->phase = 2;
chk2:
            if ((r = check()) != EMPTY)
                return finish(r);
        }
        v->k = (u16)(v->k + 1);
        if (move(v->axis[0]))
            return finish(R_OUT);
    }
}
