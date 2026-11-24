/* data.c - the art (MICROPOL.GFX, made by tools/mkdata.py from upstream's XPM pictures)
 * and the sounds (SND/*.WAV) from the app's folder into far memory.
 * Copyright (C) 2026 the Atari816 project. GPL-3 with EA's additional terms. */
#include <stdio.h>
#include <string.h>
#include <horizon.h>
#include "ui.h"

hg_image *img_big, *img_small;
unsigned char __far *mini_tiles;
unsigned char sound_on = 1;

static unsigned char buf[512];

struct sprtype {
    unsigned long addr;         /* the first frame's first image */
    unsigned char frames, size, parts;
};
static struct sprtype spr[9];

/* n bytes of f to the 24-bit address a (never across a bank: a and n in 512s) */
static int read_far(FILE *f, unsigned long a, unsigned long n)
{
    unsigned k;
    while (n) {
        k = n > sizeof buf ? sizeof buf : (unsigned)n;
        if (fread(buf, 1, k, f) != k)
            return -1;
        hz_far_copy(hz_farptr((unsigned)(a >> 16), (unsigned)a), buf, k);
        a += k;
        n -= k;
    }
    return 0;
}

static unsigned long rd32(const unsigned char *p)
{
    return (unsigned long)p[0] | ((unsigned long)p[1] << 8) | ((unsigned long)p[2] << 16) |
           ((unsigned long)p[3] << 24);
}

int data_load(void)
{
    FILE *f;
    unsigned char hdr[32];
    unsigned long off[6], need, bank_addr = 0, bank_used = 0x10000UL;
    unsigned t;

    f = fopen("MICROPOL.GFX", "rb");
    if (!f) {
        printf("micropolis: no MICROPOL.GFX in %s\n", app_dir);
        return -1;
    }
    if (fread(hdr, 1, 32, f) != 32 || memcmp(hdr, "MPGX", 4) != 0) {
        fclose(f);
        return -1;
    }
    for (t = 0; t < 6; t++)
        off[t] = rd32(hdr + 8 + 4 * t);
    /* the palette: entries 16-255 */
    {
        if (fread(scratch, 1, 720, f) != 720)
            goto bad;
        hg_palette(16, 240, scratch);
    }
    img_big = hg_image_new(4096, 64, 1);
    img_small = hg_image_new(4096, 16, 1);
    if (!img_big || !img_small)
        goto bad;
    if (read_far(f, hg_image_addr(img_big, 0), 4096UL * 64) ||
        read_far(f, hg_image_addr(img_small, 0), 4096UL * 16))
        goto bad;
    mini_tiles = hz_far_alloc();
    if (!mini_tiles || read_far(f, (unsigned long)HZ_BANK(mini_tiles) << 16, 960UL * 9))
        goto bad;
    /* the sprites: each type's frames together in one bank */
    for (t = 1; t <= 8; t++) {
        unsigned char h[2];
        if (fread(h, 1, 2, f) != 2)
            goto bad;
        spr[t].frames = h[0];
        spr[t].size = h[1];
        spr[t].parts = h[1] == 48 ? 5 : 2;      /* the full-size images + the half one */
        need = (unsigned long)h[0] * spr[t].parts * 512;
        if (bank_used + need > 0x10000UL) {
            unsigned char __far *b = hz_far_alloc();
            if (!b)
                goto bad;
            bank_addr = (unsigned long)HZ_BANK(b) << 16;
            bank_used = 0;
        }
        spr[t].addr = bank_addr + bank_used;
        if (read_far(f, spr[t].addr, need))
            goto bad;
        bank_used += need;
    }
    fclose(f);
    return 0;
bad:
    fclose(f);
    printf("micropolis: MICROPOL.GFX is damaged, or no memory\n");
    return -1;
}

unsigned long data_sprite(unsigned type, unsigned frame, unsigned part)
{
    const struct sprtype *s;
    if (type < 1 || type > 8)
        return 0;
    s = &spr[type];
    if (frame >= s->frames)
        return 0;
    if (part == 4)
        part = s->parts - 1;
    else if (part >= s->parts - 1)
        return 0;
    return s->addr + ((unsigned long)frame * s->parts + part) * 512;
}

unsigned data_sprite_size(unsigned type)
{
    return type >= 1 && type <= 8 ? spr[type].size : 32;
}

/* ---------------------------------------------------------------- sounds */

static const char *const snd_names[] = {
    "Explosion-High", "EXPHI", "Explosion-Low", "EXPLO", "HeavyTraffic", "TRAFFIC",
    "HonkHonk-High", "HONKHI", "HonkHonk-Med", "HONKMED", "HonkHonk-Low", "HONKLO",
    "Siren", "SIREN", "Monster", "MONSTER", "Rumble", "RUMBLE", "O", "O", "A", "A", "E", "E",
    "UhUh", "UHUH", "Sorry", "SORRY", "Boing", "BOING", "Oop", "OOP", "Aaah", "AAAH",
    "Woosh", "WOOSH", "Skid", "SKID", "QuackQuack", "QUACK", NULL
};
#define NSND 20
static hg_sound *snd[NSND];
static unsigned char snd_tried;

void snd_play(const char *name, int semis)
{
    unsigned i, n;
    char word[24];

    if (!sound_on || !hg_has_lau())
        return;
    for (n = 0; name[n] && name[n] != ' ' && n < sizeof word - 1; n++)
        word[n] = name[n];
    word[n] = 0;
    for (i = 0; snd_names[2 * i]; i++)
        if (strcmp(snd_names[2 * i], word) == 0)
            break;
    if (!snd_names[2 * i])
        return;
    if (!snd[i] && !(snd_tried & 0)) {
        char path[32];
        sprintf(path, "SND/%s.WAV", snd_names[2 * i + 1]);
        snd[i] = hg_sound_load(path);
        if (!snd[i])
            return;
    }
    hg_play_ex(snd[i], 200, 0, semis);
}
