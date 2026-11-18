// SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
// Copyright (c) 2026 Carlos Bravo
// fdisk.h - a folder on the card as an Atari DOS 2.0S disk for the classic Atari (step 3).
//
// The disk is an image in memory (720 sectors of 128 bytes, 92,160 bytes; SDRAM on the board),
// built from the folder's files (fd_build) and served sector by sector by the SIO code. What
// the Atari writes changes only the image; fd_sync copies the files the Atari closed back into
// the folder. Plain C over FatFs: the firmware uses it, and so does the host test
// (core/test/fdisk_host), which compiles the same FatFs on a disk image file.
//
// DOS 2.0S single density: sectors 1-3 boot, 360 VTOC, 361-368 the directory (8 entries of 16
// bytes a sector: flags, u16 sector count, u16 first sector, name 8, extension 3), data sectors
// 4-359 and 369-719 (707), 125 data bytes + 3 link bytes each (byte 125: file number << 2 |
// next sector >> 8, byte 126: next sector low byte, byte 127: bytes used).
#ifndef FDISK_H
#define FDISK_H

#include <stdint.h>

#define FD_NSEC     720
#define FD_IMGSIZE  (FD_NSEC * 128)
#define FD_NFILE    64          // directory entries
#define FD_FREE0    707         // data sectors of an empty disk
#define FD_NCAND    128         // valid names considered at a build (in name order)

typedef struct {
    uint8_t  used;              // the entry is a file of the folder (as last built or saved)
    uint8_t  conflict;          // the Atari's change could not be saved (a name the disk does
                                // not show is in the way): not tried again until it changes
    uint8_t  ent[16];           // the directory entry as last built or saved
    char     host[13];          // its name in the folder (as the card has it)
} fd_known_t;

typedef struct {
    char       name[13];        // "NAME.EXT" (upper case)
    char       host[13];        // the name in the folder
    uint32_t   size;
} fd_cand_t;

typedef struct {
    char       dir[128];        // the folder ("" = no folder disk)
    uint8_t    shown, skipped;  // files on the disk, files of the folder left out
    uint16_t   nfree;           // free sectors
    uint8_t    pending;         // the Atari changed something not yet saved into the folder
    uint8_t    fail;            // the last save failed (the card): wait longer before trying again
    uint32_t   t_saved;         // FAT time of the last build or save
    uint32_t   conflicts;       // changes not saved because of a name in the way (meter)
    uint8_t    dirty[FD_NSEC / 8];   // sectors written by the Atari since the last save
    fd_known_t known[FD_NFILE];
    fd_cand_t  cand[FD_NCAND];  // (scratch of fd_build)
    uint8_t    s_ent[FD_NFILE][16], s_st[FD_NFILE], s_act[FD_NFILE];   // (scratch of fd_sync)
    char       s_nm[FD_NFILE][13], s_kn[FD_NFILE][13];
} fd_t;

// Build the image from the folder dir (created if missing). Returns 0 or a FatFs code (the
// image is then an empty disk). Fills shown, skipped, nfree; clears pending and dirty.
int  fd_build(fd_t *d, uint8_t *img, const char *dir);

// Save into the folder what the Atari changed: files it closed (written, renamed, deleted).
// Returns 0 when everything is saved; 1 when something must wait (a file still open for
// writing on the Atari, a file Horizon has open, the Atari used the disk meanwhile, a card
// error); pending says whether anything is left.
int  fd_sync(fd_t *d, uint8_t *img);

// Mark a sector written by the Atari (the SIO code does this inline on the board).
static inline void fd_mark(fd_t *d, unsigned sector) { if (sector < FD_NSEC) d->dirty[sector >> 3] |= 1 << (sector & 7); d->pending = 1; }

// The 8.3 rule: the folder's name n as an Atari DOS name ("NAME.EXT", upper case) into out
// (13 bytes); 0 if it has no such form.
int  fd_atari_name(const char *n, char *out);

// ---- given by the user (firmware.c, or the host test) ----
extern volatile uint32_t fd_act;           // +1 at every Atari access to the drive
int      fd_busy(const char *path);        // 1 = the file is open elsewhere (do not replace it now)
void     fd_poll(void);                    // called between steps (the SIO, the input)
uint32_t fd_fattime(void);                 // now, FAT format

#endif
