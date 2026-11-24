/* SPDX-License-Identifier: GPL-3.0-or-later */
/* upstream's src/wayasm.asm in C (aiway.c way_doors): the passable doors
   become walls, or back: WF_WEST and WF_NORTH flip in path.c's walk flags
   for the west and north walls whose MCD record has a door flag and is no
   wall already (DOS: isBlocked with a missile target). The walk flags are
   at walkseg:WF (10000), a byte per tile. Build with -DXD_HAVE_WAY. */
#include "xcompat.h"
#include "plat.h"

#define WF       10000u
#define WF_WEST  0x01
#define WF_NORTH 0x02

/* A passable door: an MCD record (16 bytes) with a door flag, walkable. */
static int door(const unsigned char far *mcd, unsigned char rec)
{
    const unsigned char far *m;

    if (!rec)
        return 0;
    m = mcd + ((unsigned)rec << 4);
    if (m[5] == 255)                    /* Mcd.tu_walk */
        return 0;
    return (m[8] & 0x18) != 0;          /* Mcd.flags: MCD_DOOR, MCD_UFO_DOOR */
}

void __cdecl path_doors_asm(unsigned walkseg, unsigned ntiles, const void *map, const void *mcd)
{
    unsigned char far *wf = (unsigned char far *)MK_FP(walkseg, WF);
    const unsigned char far *t = (const unsigned char far *)map;
    const unsigned char far *m = (const unsigned char far *)mcd;
    unsigned short si = 0, n = (unsigned short)ntiles;

    do {
        if (t[1] | t[2]) {
            if (door(m, t[1]))
                wf[si] ^= WF_WEST;
            if (door(m, t[2]))
                wf[si] ^= WF_NORTH;
        }
        t += 4;
        si++;
    } while (--n);
}

#if defined(__CC816__)
/* The path search on the Atari816 (the patch: path.c search calls it where
   it called path_search_asm): upstream's path_search_c with path.c's step
   rules in assembly, horizon/hz_path.s, on this block. */
#include <stddef.h>
#include <hgame.h>
#include "path.h"

struct HzPath {
    unsigned char far *wh, *wf, *wc, *wd;       /* path.c's walk tables */
    unsigned char far *cost, *from;             /* the search's */
    unsigned short far *next, *bucket;
    unsigned n, mx, my, mz, mxy, start, max_tu, occ, fly;
    int doff[8], ddx[8], ddy[8];
    unsigned goal, gx, gy, gmode;               /* the goal's early ends (below) */
    unsigned slice, cc, paused, resume;         /* a search in slices (hz_path_begin) */
};
_Static_assert(offsetof(struct HzPath, n) == 32 && offsetof(struct HzPath, doff) == 50
               && offsetof(struct HzPath, goal) == 98 && offsetof(struct HzPath, slice) == 106
               && sizeof(struct HzPath) == 114, "hz_path.s's H_* offsets");
struct HzPath hz_ph;
void hz_path_run(void);
extern const signed char g_dir_dx[8], g_dir_dy[8];

static void setup(struct PathParams *p);

void hz_path_search(struct PathParams *p)
{
    PERF_T0(pt0);

    hz_ph.slice = 0;
    hz_ph.resume = 0;
    setup(p);
    hz_path_run();
    PERF_ADD(PF_PATH, pt0);
    if (p->goal != 0xFFFFu && hz_ph.cost[p->goal] != 0xFF)
        p->best = p->goal;
}

/* A whole search (no goal: path.c path_search_begin, the player's turn) in slices of
   about ms milliseconds: hz_path.s stops at a tile's end when the slice's time is up
   (hz_path_over, every 8th tile) and goes on from there at the next call: the same
   tiles expanded in the same order as in one run (the tables and the buckets are the
   search's whole state, and nothing else changes them meanwhile: path.c). 1 when it
   is done. */
static unsigned long slice_end;

int hz_path_over(void)
{
    return hg_us() - slice_end < 0x80000000UL;
}

int hz_path_begin(struct PathParams *p, unsigned ms)
{
    hz_ph.slice = 1;
    hz_ph.resume = 0;
    hz_ph.paused = 0;
    setup(p);
    slice_end = hg_us() + (unsigned long)ms * 1000UL;
    {
        PERF_T0(pt0);
        hz_path_run();
        PERF_ADD(PF_PATH, pt0);
    }
    return !hz_ph.paused;
}

int hz_path_more(unsigned ms)
{
    if (!hz_ph.paused)
        return 1;
    hz_ph.resume = 1;
    hz_ph.paused = 0;
    slice_end = hg_us() + (unsigned long)ms * 1000UL;
    {
        PERF_T0(pt0);
        hz_path_run();
        PERF_ADD(PF_PATH, pt0);
    }
    hz_ph.resume = 0;
    return !hz_ph.paused;
}

static void setup(struct PathParams *p)
{
    unsigned char far *w = (unsigned char far *)xd_mkfp_raw(p->walkseg, 0);
    unsigned char far *s = (unsigned char far *)xd_mkfp_raw(p->searchseg, 0);
    int d;

    hz_ph.wh = w;
    hz_ph.wf = w + 10000u;
    hz_ph.wc = w + 20000u;
    hz_ph.wd = w + 30000u;
    hz_ph.cost = s;
    hz_ph.from = s + 10000u;
    hz_ph.next = (unsigned short far *)(s + 20000u);
    hz_ph.bucket = (unsigned short far *)(s + 40000u);
    hz_ph.n = p->n;
    hz_ph.mx = p->mx;
    hz_ph.my = p->my;
    hz_ph.mz = p->mz;
    hz_ph.mxy = p->mxy;
    hz_ph.start = p->start;
    hz_ph.max_tu = p->max_tu;
    hz_ph.occ = p->occ;
    hz_ph.fly = p->fly;
    for (d = 0; d < 8; d++) {
        hz_ph.ddx[d] = g_dir_dx[d];
        hz_ph.ddy[d] = g_dir_dy[d];
        hz_ph.doff[d] = g_dir_dx[d] + g_dir_dy[d] * (int)p->mx;
    }
    /* A search toward a goal (path_search_to; not a missile's, whose failed search
       ai_way reads all of: aiway.c) ends as soon as its outcome is known, with the
       same answer and the same path as the whole search (the C reference's):
       - reached: when no tile waiting in a bucket costs less than the goal, nothing
         can lower the goal's cost or any cost on its path (a step costs 0 or more,
         and from[] changes only with a lower cost), so path_build follows the same
         path. (A tile whose cost fell while it waited stays in its later bucket: the
         test looks at every waiting tile's cost, not at the bucket.)
       - not reached: path.c's A* estimate (2 * the longer + the shorter axis
         distance, x 2: hs 1, while no tile costs less than 4 to enter, so a straight
         step costs 4 or more and a diagonal one 6 or more) is a lower bound of the
         rest of any path and changes by at most a step's cost from tile to tile;
         when every waiting tile has cost + estimate > max_tu, no tile reached from
         them can reach the goal within max_tu: it is never reached.
       What the callers read after a search toward a goal: whether it was reached
       (best) and path_build's path to it; a failed one's tables only ai_way's
       missile search (excluded). Every other search runs whole, as before. */
    hz_ph.goal = p->goal;
    hz_ph.gx = p->gx;
    hz_ph.gy = p->gy;
    hz_ph.gmode = p->goal == 0xFFFFu || p->mis ? 0 : p->hs == 1 ? 3 : 1;
}
#endif
