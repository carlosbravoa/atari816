/* SPDX-License-Identifier: GPL-3.0-or-later */
/* The VGA night lights' levels (vlit.h): vgaasm.asm "Night lights"
   (sources, terrain, levels) in portable C, for the builds without
   vgaasm.asm's battle view (XCOM_PORT: the Atari816 and the host; the DOS
   VGA build keeps upstream's lit_present, the same model).

   The rules are OpenXcom's (TileEngine::calculateTerrainLighting,
   calculateUnitLighting, addLight; Tile::getShade), as upstream's: a light
   of power p gives p - round(distance) to every map column within 9 tiles
   each way (every level: light is not stopped by floors or walls), a
   column's light is the most of them and of the night sky's
   (VL_SUN), and its shade 15 less that. Sources: the X-COM units that are
   up (their personal light, 15), burning units (15), fires (15),
   electro-flares on the ground (15: items.rul power), the terrain's floors
   and objects that are light sources (their MCD light, pak.c
   Pack.lights). A cell's tile is the one under the cell's centre at the
   view's level (vgaasm.asm levels: a level below is drawn 24 pixels
   lower, so its tiles' cells are up to 1.5 tiles off).

   How. The light of every map column (and 9 columns round the map) is
   kept in a map: the terrain's part in tmap, made again only when the
   terrain's light map changed (pak.c pak_light_map: at the setup, after
   a light source broke; its sources are looked for in the columns it
   lights only), all lights in lmap: when only a few of the other sources
   moved (a walk's step) only their old and new discs' squares are made
   again (the terrain's, then every source's part in them), else all of
   it (tmap and every disc). The cells' levels are then read from it; a
   scroll by whole cells moves them with the cells and reads only the
   cells that came into the view (vgaasm.asm vshift), another move of the
   camera or of the view's level reads all 360. Unlike upstream's
   assembly (which keeps 48 sources that can reach the view, 24 of the
   terrain's, 8 kinds of terrain lights, a tile's first light part, in its
   768-byte work area) every source counts, the floor's and the object's
   light both (OpenXcom); the picture is otherwise the same. Light above
   15 (a terrain source of 16) counts as 15. On the Atari816 the discs,
   the squares and the cells are horizon/hz_lit.s's (the C here is the
   host's, the reference). */
#if defined(XCOM_PORT)

#include <string.h>
#include "vlit.h"
#include "fx_in.h"
#include "map.h"
#include "pak.h"
#include "render.h"
#include "unit.h"

#define M       9               /* a light's reach, each way (vgaasm.asm addsrc) */
#define LMAP    16384u          /* the light map's room: maps up to 110 x 110 with the margin */
#define NSRC    520             /* sources kept of each kind (units 60, fires 384, devices 72) */

typedef struct {
    unsigned char x, y, p;
} Src;

unsigned char far g_vl_lev[VL_CELLS];
unsigned long g_vl_maps, g_vl_levels;

static unsigned char far tmap[LMAP];
static unsigned char far lmap[LMAP];
static Src far tsrc[NSRC];
static Src far dsrc[NSRC];
static Src far nsrc[NSRC];
static unsigned nt, nd;
static unsigned mw, mh;                 /* the map with its margin; 0: too big (no map) */
static unsigned char rt[M + 1][M + 1];  /* round(sqrt(dx * dx + dy * dy)) */
static unsigned char rt_ok, cells_ok, terr_ok, relight_was;
static const unsigned char *map_was;
static const unsigned char *lit_was;
static unsigned tkey, mx_was, my_was, mz_was;
static int cam_x, cam_y, view_z;

static void mk_rt(void)
{
    unsigned a, b, d2, r;

    for (a = 0; a <= M; a++)
        for (b = 0; b <= M; b++) {
            d2 = a * a + b * b;
            for (r = 0; r * r + r < d2; r++)
                ;
            rt[a][b] = (unsigned char)r;
        }
    rt_ok = 1;
}

/* A light of power p's disc: p less the distance, 0 where that is the night
   sky's or less (it adds nothing), 15 at most (vl_light's bound). */
static unsigned char far disc15[(2 * M + 1) * (2 * M + 1)];
static unsigned char far discp[(2 * M + 1) * (2 * M + 1)];
static int discp_p = -1;

static const unsigned char far *disc(int p)
{
    unsigned char far *d = p == 15 ? disc15 : discp;
    int dy, dx, l;

    if (p == 15 ? d[M * (2 * M + 1) + M] == 15 : discp_p == p)
        return d;
    for (dy = 0; dy <= 2 * M; dy++)
        for (dx = 0; dx <= 2 * M; dx++) {
            l = p - rt[dy < M ? M - dy : dy - M][dx < M ? M - dx : dx - M];
            *d++ = (unsigned char)(l <= VL_SUN ? 0 : l > 15 ? 15 : l);
        }
    if (p != 15)
        discp_p = p;
    return p == 15 ? disc15 : discp;
}

#if defined(__CC816__)
/* horizon/hz_lit.s: the same loops in assembly (the C is the host's, the reference) */
void hz_lit_stamp(unsigned char far *m, unsigned stride, const unsigned char far *disc,
                  unsigned w, unsigned h);
void hz_lit_rows(unsigned char far *d, const unsigned char far *s, unsigned stride, unsigned w,
                 unsigned h);
int hz_lit_cells(unsigned char far *lev, const unsigned char far *lmap,
                 const unsigned short far *rowoff, unsigned mw, unsigned mh, int a0, int b0,
                 int c0, int c1, int r0, int r1);
static unsigned short far rowoff[LMAP / (2 * M + 1)];  /* row k of the light map: k * mw */
static unsigned rows_mw, rows_mh;
#endif

#define D   (2 * M + 1)         /* a disc's side */

/* A source's disc into the map m (the most of what is there and the disc), the part in
   columns x0..x1 - 1 and rows y0..y1 - 1 of the map with its margin (a disc's are s->x
   .. s->x + D - 1). */
static void stamp(unsigned char far *m, const Src far *s, int x0, int y0, int x1, int y1)
{
    unsigned char far *row;
    const unsigned char far *d = disc(s->p);

    if (x0 < s->x)
        x0 = s->x;
    if (y0 < s->y)
        y0 = s->y;
    if (x1 > s->x + D)
        x1 = s->x + D;
    if (y1 > s->y + D)
        y1 = s->y + D;
    if (x0 >= x1 || y0 >= y1)
        return;
    row = m + (unsigned)y0 * mw + (unsigned)x0;
    d += (y0 - s->y) * D + (x0 - s->x);
#if defined(__CC816__)
    hz_lit_stamp(row, mw, d, x1 - x0, y1 - y0);
#else
    {
        int dy, dx;
        for (dy = y0; dy < y1; dy++, row += mw, d += D)
            for (dx = 0; dx < x1 - x0; dx++)
                if (d[dx] > row[dx])
                    row[dx] = d[dx];
    }
#endif
}

#define ALL     0, 0, 0x7FFF, 0x7FFF

/* The map anew in the disc's square at x, y (map with margin): the terrain's light,
   every other source's part in it. */
static void square(int x, int y)
{
    unsigned i;

#if defined(__CC816__)
    hz_lit_rows(lmap + (unsigned)y * mw + x, tmap + (unsigned)y * mw + x, mw, D, D);
#else
    unsigned r;
    for (r = 0; r < D; r++)
        memcpy(lmap + (unsigned)(y + r) * mw + x, tmap + (unsigned)(y + r) * mw + x, D);
#endif
    for (i = 0; i < nd; i++)
        stamp(lmap, &dsrc[i], x, y, x + D, y + D);
}

/* The light at x, y from the lists (a map too big for the room). */
static int direct(int x, int y)
{
    int best = 0, i, k, dx, dy, l;
    const Src far *s;

    for (k = 0; k < 2; k++)
        for (s = k ? dsrc : tsrc, i = 0; i < (int)(k ? nd : nt); i++, s++) {
            dx = x - s->x;
            dy = y - s->y;
            if (dx < 0)
                dx = -dx;
            if (dy < 0)
                dy = -dy;
            if (dx > M || dy > M)
                continue;
            l = s->p - rt[dx][dy];
            if (l > best)
                best = l;
        }
    return best;
}

int vl_light(int x, int y)
{
    int l;

    if (!mw)
        l = direct(x, y);
    else if ((unsigned)(x + M) < mw && (unsigned)(y + M) < mh)
        l = lmap[(unsigned)(y + M) * mw + (unsigned)(x + M)];
    else
        l = 0;                  /* (out of every light's reach) */
    if (l > 15)
        l = 15;
    return l < VL_SUN ? VL_SUN : l;
}

/* The terrain's sources and tmap again when the terrain's light map
   (g_pak.lit: its sum, as vgaasm.asm terrain), the map or a light source
   broke (g_pak.relight set: the map's parts changed). 1 when made. */
static int terrain(void)
{
    unsigned key = 0, n = 0, i, x, y, z, k, part;
    const unsigned char *t;

    if (g_pak.lit) {
        n = (g_mx * g_my + 7) / 8;
        for (i = 0; i < n; i++)
            key = (key << 1 | key >> 15) + g_pak.lit[i];
    }
    if (terr_ok && key == tkey && g_map == map_was && g_pak.lit == lit_was && g_mx == mx_was
        && g_my == my_was && g_mz == mz_was && !(g_pak.relight && !relight_was)) {
        relight_was = g_pak.relight;
        return 0;
    }
    relight_was = g_pak.relight;
    terr_ok = 1;
    tkey = key;
    map_was = g_map;
    lit_was = g_pak.lit;
    mx_was = g_mx;
    my_was = g_my;
    mz_was = g_mz;
    mw = g_mx + 2 * M;
    mh = g_my + 2 * M;
    if ((unsigned long)mw * mh > LMAP)
        mw = mh = 0;
    nt = 0;
    /* (none by day, or no light sources.) Only the columns g_pak.lit says are lit: a
       source that lights its own column less than 6 adds nothing to the night sky's 5 */
    if (g_pak.lit && g_map)
        for (y = 0, i = 0; y < g_my; y++)
            for (x = 0; x < g_mx; x++, i++)
                if (g_pak.lit[i >> 3] & (1 << (i & 7)))
                    for (z = 0; z < g_mz; z++)
                        for (t = TILE(x, y, z), part = PART_FLOOR; part <= PART_OBJECT;
                             part += PART_OBJECT - PART_FLOOR)
                            if (t[part])
                                for (k = 0; k < g_pak.n_lights; k++)
                                    if (t[part] == g_pak.lights[k][0]) {
                                        if (nt < NSRC) {
                                            tsrc[nt].x = (unsigned char)x;
                                            tsrc[nt].y = (unsigned char)y;
                                            tsrc[nt].p = g_pak.lights[k][1];
                                            nt++;
                                        }
                                        break;
                                    }
    if (mw) {
        memset(tmap, 0, mw * mh);
        for (i = 0; i < nt; i++)
            stamp(tmap, &tsrc[i], ALL);
    }
    return 1;
}

static unsigned add(unsigned n, int x, int y)
{
    if (n < NSRC && (unsigned)x < g_mx && (unsigned)y < g_my) {
        nsrc[n].x = (unsigned char)x;
        nsrc[n].y = (unsigned char)y;
        nsrc[n].p = 15;
        n++;
    }
    return n;
}

/* The levels of cells c0..c1, r0..r1 (vgaasm.asm levels): 1 when one changed. Cell
   (c, row)'s centre: x - y and x + y in 16ths of a tile, A and B. */
static int cells(int c0, int c1, int r0, int r1)
{
    int a0 = -8 - g_cam_x, b0 = 48 * g_view_z - 56 - 2 * g_cam_y, r = 0, row, c;

#if defined(__CC816__)
    if (mw) {
        if (rows_mw != mw || rows_mh != mh) {
            unsigned k;
            for (k = 0; k < sizeof rowoff / sizeof rowoff[0]; k++)
                rowoff[k] = k < mh ? k * mw : 0;
            rows_mw = mw;
            rows_mh = mh;
        }
        return hz_lit_cells(g_vl_lev, lmap, rowoff, mw, mh, a0, b0, c0, c1, r0, r1);
    }
#endif
    for (row = r0; row < r1; row++) {
        int b = b0 + 16 * row, a = a0 + 16 * c0;
        unsigned char far *lev = g_vl_lev + row * VL_COLS + c0;
        for (c = c0; c < c1; c++, a += 16, lev++) {
            int s = a + b + 16, t = b - a + 16, x, y;
            unsigned char v;
            x = s >= 0 ? s >> 5 : -((-s + 31) >> 5);
            y = t >= 0 ? t >> 5 : -((-t + 31) >> 5);
            v = (unsigned char)(15 - vl_light(x, y));
            if (v != *lev) {
                *lev = v;
                r = 1;
            }
        }
    }
    return r;
}

void vl_night(void)
{
    cells_ok = 0;
}

int vl_update(void)
{
    unsigned n = 0, i;
    int lit, moved, r = 0;
    const Unit *u;
    const Spot __near *f;
    const Device __near *d;

    if (!rt_ok)
        mk_rt();
    lit = terrain();
    /* the other sources (vgaasm.asm sources): units, flares, fires */
    for (u = g_units; u < g_units + g_nunits; u++)
        if (u->alive && (u->faction == FACTION_XCOM || (u->burning & ~UB_HIT)))
            n = add(n, u->x, u->y);
    for (d = dev; d < dev + n_dev; d++)
        if (d->kind == DEV_FLARE)
            n = add(n, d->x, d->y);
    for (f = fire; f < fire + n_fire; f++)
        n = add(n, f->x, f->y);
    if (n != nd || memcmp(nsrc, dsrc, n * sizeof(Src))) {
        /* a few of them moved (a walk's step): the map anew only in their old and new
           discs' squares (the rest is as it was) */
        unsigned sq[8], nm = 0;
        if (!lit && mw && n == nd) {
            for (i = 0; i < n && nm <= 8; i++)
                if (nsrc[i].x != dsrc[i].x || nsrc[i].y != dsrc[i].y || nsrc[i].p != dsrc[i].p) {
                    if (nm < 8) {
                        sq[nm++] = dsrc[i].x | dsrc[i].y << 8;
                        sq[nm++] = nsrc[i].x | nsrc[i].y << 8;
                    } else
                        nm = 9;
                }
        } else
            nm = 9;
        memcpy(dsrc, nsrc, n * sizeof(Src));
        nd = n;
        if (nm <= 8) {
            for (i = 0; i < nm; i++)
                square(sq[i] & 255, sq[i] >> 8);
            g_vl_maps++;
            lit = 2;
        } else
            lit = 1;
    }
    if (lit == 1) {
        if (mw) {
            memcpy(lmap, tmap, mw * mh);
            for (i = 0; i < nd; i++)
                stamp(lmap, &dsrc[i], ALL);
        }
        g_vl_maps++;
    }
    moved = !cells_ok || cam_x != g_cam_x || cam_y != g_cam_y || view_z != g_view_z;
    if (lit || moved) {
        int dx = g_cam_x - cam_x, dy = g_cam_y - cam_y, dc = dx / 16, dr = dy / 8;
        if (!lit && cells_ok && view_z == g_view_z && !(dx & 15) && !(dy & 7) && dc > -VL_COLS
            && dc < VL_COLS && dr > -VL_ROWS && dr < VL_ROWS) {
            /* a scroll by whole cells (vgaasm.asm vshift): the levels move with the
               cells, only those that came into the view are made (cell c, row shows
               what c - dc, row - dr showed; the cells a row's end wraps into are among
               those made) */
            int k = dr * VL_COLS + dc;
            if (k > 0)
                memmove(g_vl_lev + k, g_vl_lev, VL_CELLS - k);
            else if (k < 0)
                memmove(g_vl_lev, g_vl_lev - k, VL_CELLS + k);
            if (dc > 0)
                cells(0, dc, 0, VL_ROWS);
            else if (dc < 0)
                cells(VL_COLS + dc, VL_COLS, 0, VL_ROWS);
            if (dr > 0)
                cells(0, VL_COLS, 0, dr);
            else if (dr < 0)
                cells(0, VL_COLS, VL_ROWS + dr, VL_ROWS);
        } else if (cells(0, VL_COLS, 0, VL_ROWS))
            r = VL_CHANGED;
        cam_x = g_cam_x;
        cam_y = g_cam_y;
        view_z = g_view_z;
        g_vl_levels++;
    }
    if (moved)
        r |= VL_MOVED;
    cells_ok = 1;
    return r;
}

#else
typedef int vlit_not_in_this_build;    /* (the DOS VGA build: vgaasm.asm lit_present) */
#endif
