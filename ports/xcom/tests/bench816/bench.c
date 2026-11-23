/* SPDX-License-Identifier: GPL-3.0-or-later */
/* Stage 1 measurements on the Atari816 (PORTING-NOTES.md "Measured"): the
   costs of the VGA path's typical work, with the real packs on the card,
   before the engine itself can run there (it needs far data: SDK need 1).
     1. a full-screen picture streamed from UIV.PAK into the framebuffer
        (the start menu, the base, every screen's background), two ways
     2. the geoscape's world view (vgxasm.asm vx_world in C), zoom 0, 1, 2
     3. the battle view's present (320 x 144 back buffer -> screen)
     4. sprites: a 32 x 40 masked sprite in C through far pointers (the
        battle view draws its floor, walls, objects and units so)
   Each result: "bench: NAME N us". Build: hcc -o BENCH.PRG bench.c
   ../../horizon/hz_vga.s (the port's geoscape rows). */
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <hgame.h>
#include <horizon.h>

#define ROW 320
static unsigned char __far *fb;

static unsigned long now(void)
{
    return (unsigned long)hz_uptime_us();
}

static void report(const char *name, unsigned long us, unsigned n)
{
    printf("bench: %s %lu us (%u times, %lu us each)\n", name, us, n, n ? us / n : 0);
}

/* 1. the picture: entry id of UIV.PAK (plain, 320 x 200) */
static long entry_at(int fd, unsigned id)
{
    unsigned char b[4];

    lseek(fd, 8L + id * 4L, SEEK_SET);
    if (read(fd, b, 4) != 4)
        return 0;
    return b[0] | (long)b[1] << 8 | (long)b[2] << 16 | (long)b[3] << 24;
}

static void pictures(void)
{
    static unsigned char buf[512];
    unsigned long t;
    long at;
    int fd, k, i;
    unsigned done, n;

    fd = open("VGA/UIV.PAK", O_RDONLY);
    if (fd < 0) {
        printf("bench: no VGA/UIV.PAK\n");
        return;
    }
    at = entry_at(fd, 2);
    t = now();
    for (i = 0; i < 4; i++) {
        lseek(fd, at + 10, SEEK_SET);
        for (done = 0; done < 64000u; done += n) {
            n = 64000u - done > sizeof buf ? sizeof buf : 64000u - done;
            k = read(fd, buf, n);
            if (k <= 0)
                break;
            hz_far_copy(fb + done, buf, (unsigned)k);
        }
    }
    report("picture 320x200 by read(512) + far copy", now() - t, 4);
    close(fd);
    {
        int h = hz_open("VGA/UIV.PAK", 0);
        hz_io io;
        if (h < 0)
            return;
        t = now();
        for (i = 0; i < 4; i++) {
            hz_seek((unsigned)h, (unsigned long)at + 10);
            for (done = 0; done < 64000u; done += n) {
                n = 64000u - done > 32000u ? 32000u : 64000u - done;
                io.handle = (unsigned char)h;
                HZ_U24(io.buf, fb + done);
                io.len = n;
                hz_read(&io);
            }
        }
        report("picture 320x200 by hz_read into the framebuffer", now() - t, 4);
        hz_close((unsigned)h);
    }
}

/* 2. vx_world (plat/vga.c vga_vx_world) */
static void world(const unsigned char __far *map, unsigned vx, unsigned vy, unsigned zoom)
{
    unsigned char __far *d = fb;
    unsigned need = 256 >> zoom, n1 = 320 - vx < need ? 320 - vx : need, y, i, k;
    unsigned rep = 1u << zoom;

    for (y = 0; y < 160; y++, d += ROW) {
        const unsigned char __far *s = map + ((y >> zoom) + vy) * 320u;
        unsigned char __far *p = d;
        if (!zoom) {
            hz_far_copy(p, s + vx, n1);
            if (n1 < need)
                hz_far_copy(p + n1, s, need - n1);
            continue;
        }
        for (i = 0; i < need; i++) {
            unsigned char c = s[i < n1 ? vx + i : i - n1];
            for (k = 0; k < rep; k++)
                *p++ = c;
        }
    }
}

/* the same as the port does it now (plat/vga.c, horizon/hz_vga.s): a row once
   (zoom 1, 2: each byte 2 or 4 times in assembly), the rows that repeat it copied */
void hz_zoom_row(unsigned char __far *d, const unsigned char __far *s, unsigned n, unsigned zoom);

static void part2(unsigned char __far *p, const unsigned char __far *s, unsigned n, unsigned zoom)
{
    if (!zoom)
        hz_far_copy(p, s, n);
    else
        hz_zoom_row(p, s, n, zoom);
}

static void world2(const unsigned char __far *map, unsigned vx, unsigned vy, unsigned zoom)
{
    unsigned char __far *d = fb;
    unsigned need = 256 >> zoom, n1 = 320 - vx < need ? 320 - vx : need, y;

    for (y = 0; y < 160; y++, d += ROW) {
        const unsigned char __far *s = map + ((y >> zoom) + vy) * 320u;
        if (y && (y >> zoom) == ((y - 1) >> zoom)) {
            hz_far_copy(d, d - ROW, 256);
            continue;
        }
        part2(d, s + vx, n1, zoom);
        if (need > n1)
            part2(d + (n1 << zoom), s, need - n1, zoom);
    }
}

static void worlds(unsigned char __far *map)
{
    unsigned long t;
    unsigned z, i;
    char name[40];

    for (i = 0; i < 51200u; i++)
        map[i] = (unsigned char)(i * 7 >> 5);
    for (z = 0; z < 3; z++) {
        t = now();
        for (i = 0; i < 4; i++)
            world(map, 100, z ? 20 : 0, z);
        sprintf(name, "geoscape world view zoom %u", z);
        report(name, now() - t, 4);
        t = now();
        for (i = 0; i < 4; i++)
            world2(map, 100, z ? 20 : 0, z);
        sprintf(name, "geoscape world view zoom %u (port now)", z);
        report(name, now() - t, 4);
    }
}

/* 3. the battle view's present */
static void present(unsigned char __far *buf)
{
    unsigned long t = now();
    int i;

    for (i = 0; i < 4; i++)
        hz_far_copy(fb, buf, 320u * 144);
    report("battle view present 320x144 (far copy)", now() - t, 4);
}

/* 4. a 32 x 40 sprite with transparent 0s, C through far pointers, at
   CGA-offset style addressing (vgaasm.asm op_masked does spans of bytes) */
static void sprites(unsigned char __far *buf, const unsigned char __far *spr)
{
    unsigned long t = now();
    unsigned n, r, k;

    for (n = 0; n < 100; n++) {
        unsigned char __far *d = buf + (n % 9) * 32 + (n / 9) * 8u * ROW;
        const unsigned char __far *s = spr;
        for (r = 0; r < 40; r++, d += ROW)
            for (k = 0; k < 32; k++, s++)
                if (*s)
                    d[k] = *s;
    }
    report("sprite 32x40 masked, C byte loop", now() - t, 100);
    t = now();
    for (n = 0; n < 100; n++) {
        unsigned char __far *d = buf + (n % 9) * 32 + (n / 9) * 8u * ROW;
        for (r = 0; r < 40; r++, d += ROW)
            hz_far_copy(d + 4, spr + r * 32 + 4, 24);
    }
    report("sprite 32x40 as 40 spans of 24 (far copy)", now() - t, 100);
}

/* 5. the same sprites by the blitter: an hgame image (a kernel sheet in far
   memory), keyed copies queued and drawn by Ali (hg_draw, one flush) */
static void blits(void)
{
    hg_image *img = hg_image_new(32, 40, 1);
    unsigned char __far *px;
    unsigned long t;
    unsigned n, i;

    if (!img) {
        printf("bench: no image\n");
        return;
    }
    img->key = 0;
    px = hg_image_pixels(img, 0);
    for (i = 0; i < 1280; i++)
        px[i] = (unsigned char)((i & 31) > 3 && (i & 31) < 28 ? i : 0);
    hg_flush(1);
    t = now();
    for (n = 0; n < 300; n++)
        hg_draw(img, 0, (n % 9) * 32, (n / 9 % 4) * 40);
    hg_flush(1);
    report("sprite 32x40 keyed by the blitter (hg_draw, 300 in one flush)", now() - t, 300);
}

int main(void)
{
    unsigned char __far *bank1;
    unsigned char __far *bank2;
    char dir[128];

    if (hz_prog_dir(dir, sizeof dir) > 0)
        hz_chdir(dir);
    if (hg_screen_fb(HG_320X180, "bench", 320, 200) < 0)
        return 1;
    fb = (unsigned char __far *)hz_farptr(hg_fb_bank, 0);
    bank1 = hz_far_alloc();
    bank2 = hz_far_alloc();
    if (!bank1 || !bank2)
        return 1;
    hz_far_set(bank2, 0, 1280);
    {
        unsigned i;
        for (i = 0; i < 1280; i++)
            bank2[i] = (unsigned char)((i & 31) > 3 && (i & 31) < 28 ? i : 0);
    }
    pictures();
    worlds(bank1);
    present(bank1);
    sprites(bank1, bank2);
    blits();
    printf("bench: done\n");
    hg_close();
    return 0;
}
