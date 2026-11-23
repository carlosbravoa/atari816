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
#include "path.h"

struct HzPath {
    unsigned char far *wh, *wf, *wc, *wd;       /* path.c's walk tables */
    unsigned char far *cost, *from;             /* the search's */
    unsigned short far *next, *bucket;
    unsigned n, mx, my, mz, mxy, start, max_tu, occ, fly;
    int doff[8], ddx[8], ddy[8];
};
_Static_assert(offsetof(struct HzPath, n) == 32 && offsetof(struct HzPath, doff) == 50
               && sizeof(struct HzPath) == 98, "hz_path.s's H_* offsets");
struct HzPath hz_ph;
void hz_path_run(void);
extern const signed char g_dir_dx[8], g_dir_dy[8];

void hz_path_search(struct PathParams *p)
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
    hz_path_run();
    if (p->goal != 0xFFFFu && hz_ph.cost[p->goal] != 0xFF)
        p->best = p->goal;
}
#endif
