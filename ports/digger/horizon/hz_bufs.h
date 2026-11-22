/* hz_bufs.h - the sprites' save-unders (upstream drawing.c's monbufs ... firebufs) in a
 * bank of far memory (hz_vid.c allocates it at vgainit) */
#ifndef HZ_BUFS_H
#define HZ_BUFS_H
struct hz_savebufs {
    uint8_t mon[MONSTERS][480], bag[BAGS][480], bonus[BONUSES][480], dig[DIGGERS][480],
        fire[FIREBALLS][128];
};
extern struct hz_savebufs __far *hz_savebufs;
#endif
