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
