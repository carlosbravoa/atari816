/* hz_shm.c - upstream's shapeman.c on Horizon: the shape tables of GRAPHICS.XRn, loaded
 * when upstream wants them (shm_want[], shm_do), as tools/mkdata.py translated them
 * (XSHAPES.XRn: every shape as plain rows of 8-bit pixels, placed in an atlas of 512-byte
 * rows), into far memory: the atlas, the blitter's sheets (hz_vga.c), each table at its
 * own rows. A table once loaded stays (upstream freed what a level did not use, to fit
 * DOS's 640 KB; here the whole atlas has its banks): wanted again, it is there at once.
 * Loading a table with the palette shape (64 x 12) sets the palette, as xlate_table does. */
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <hgame.h>
#include <horizon.h>
#include "gr.h"
#include "hz_plat.h"

int shm_want[shm_maxtbls];
char far *shm_tbladdr[shm_maxtbls];     /* (here: not NULL while wanted and loaded) */
int shm_tbllen[shm_maxtbls];
int shm_flags[shm_maxtbls];

extern void rexit(int num);

static char shm_fname[16];
unsigned hzshm_first[shm_maxtbls], hzshm_count[shm_maxtbls], hzshm_row0[shm_maxtbls];
unsigned char hzshm_ok[shm_maxtbls];
const unsigned char __far *hzshm_dir;
#define tfirst hzshm_first
#define tcount hzshm_count
#define trow0 hzshm_row0
static unsigned trows[shm_maxtbls], tflags[shm_maxtbls], tpal[shm_maxtbls];
static unsigned long tfile[shm_maxtbls];
static unsigned char tloaded[shm_maxtbls];
static unsigned long atlas;             /* its rows 0-1023: 8 banks (a bank's start) */
static unsigned long atlas_b;           /* rows 1024-: up to 8 more */
static unsigned long dirs;              /* the shapes' places (8 bytes each), far memory */
unsigned long hzshm_bytes;              /* loaded so far */
unsigned hzshm_rows;                    /* the atlas's rows */

static unsigned rd16(const unsigned char *p)
{
    return p[0] | (unsigned)p[1] << 8;
}

unsigned long hzshm_atlas(void)
{
    return atlas;
}

unsigned long hzshm_atlas_b(void)
{
    return atlas_b;
}

/* the address of the atlas's row r */
unsigned long hzshm_row(unsigned r)
{
    return r < 1024 ? atlas + ((unsigned long)r << 9) : atlas_b + ((unsigned long)(r - 1024) << 9);
}

/* shape ns of table nt: {u16 x, u16 y (in the table's rows), u8 w, u8 h}, or NULL */
const unsigned char __far *hzshm_shape(int nt, int ns)
{
    if ((unsigned)ns >= tcount[nt])
        return NULL;
    return (const unsigned char __far *)(dirs + ((unsigned long)(tfirst[nt] + ns) << 3));
}

/* the directory, the atlas's rows (a table never across the two sheets' boundary), its
 * banks: before the screen (hz_main.c), as the sheets need them */
void shm_init(char *fname)
{
    unsigned char h[8 + shm_maxtbls * 14];      /* (on the software stack: once) */
    const char *e = strrchr(fname, '.');
    unsigned c, row = 0, nshapes = 0, nb;
    int fd;
    hz_io io;

    strcpy(shm_fname, "XSHAPES");
    strcat(shm_fname, e ? e : "");
    for (c = 0; c < shm_maxtbls; c++) {
        shm_want[c] = 0;
        shm_tbladdr[c] = NULL;
        hzshm_ok[c] = 0;
    }
    if (atlas)
        return;                         /* (hz_main.c did it already) */
    fd = open(shm_fname, O_RDONLY);
    if (fd < 0 || read(fd, h, sizeof h) != (int)sizeof h || memcmp(h, "XSH2", 4))
        hz_fatal("no XSHAPES file (make data: tools/mkdata.py)");
    for (c = 0; c < shm_maxtbls; c++) {
        const unsigned char *p = h + 8 + c * 14;
        tfirst[c] = rd16(p);
        tcount[c] = rd16(p + 2);
        tfile[c] = rd16(p + 4) | (unsigned long)rd16(p + 6) << 16;
        trows[c] = rd16(p + 8);
        tflags[c] = rd16(p + 10);
        tpal[c] = rd16(p + 12);
        if (row < 1024 && row + trows[c] > 1024)
            row = 1024;                 /* (the second sheet) */
        trow0[c] = row;
        row += trows[c];
        if (tfirst[c] + tcount[c] > nshapes)
            nshapes = tfirst[c] + tcount[c];
    }
    hzshm_rows = row;
    /* (each sheet's banks consecutive: rows 0-1023 in 8, the rest in up to 8 more) */
    nb = row > 1024 ? 8 : (row + 127) >> 7;
    c = hg_banks(nb);
    if (!c)
        hz_fatal("not enough memory for the pictures");
    atlas = (unsigned long)c << 16;
    if (row > 1024) {
        c = hg_banks((row - 1024 + 127) >> 7);
        if (!c)
            hz_fatal("not enough memory for the pictures");
        atlas_b = (unsigned long)c << 16;
    }
    c = hg_banks(1);
    if (!c)
        hz_fatal("not enough memory for the pictures");
    dirs = (unsigned long)c << 16;
    hzshm_dir = (const unsigned char __far *)dirs;
    io.handle = (unsigned char)(fd - 3);
    io.buf.off = 0;
    io.buf.bank = (unsigned char)c;
    io.len = nshapes * 8;
    if (lseek(fd, 8 + shm_maxtbls * 14, SEEK_SET) < 0 || hz_read(&io) != (int)(nshapes * 8))
        hz_fatal("XSHAPES file damaged");
    close(fd);
}

/* table c's rows from the file into the atlas (in pieces that do not cross a bank) */
static void load(int fd, int c)
{
    hz_io io;
    unsigned long a = hzshm_row(trow0[c]), n = (unsigned long)trows[c] << 9;
    unsigned k;
    if (lseek(fd, (long)tfile[c], SEEK_SET) < 0)
        rexit(9);
    while (n) {
        k = (unsigned)(0x10000UL - (a & 0xFFFF));
        if (k == 0 || k > 0x4000)
            k = 0x4000;                 /* (hz_read's result is an int: 16 KB a call) */
        if ((unsigned long)k > n)
            k = (unsigned)n;
        io.handle = (unsigned char)(fd - 3);
        io.buf.off = (unsigned short)a;
        io.buf.bank = (unsigned char)(a >> 16);
        io.len = k;
        if (hz_read(&io) != (int)k)
            rexit(9);
        a += k;
        n -= k;
    }
    tloaded[c] = 1;
    hzshm_bytes += (unsigned long)trows[c] << 9;
}

void shm_do(void)
{
    int c, fd = -1;
    unsigned long t0 = hz_uptime(), b0 = hzshm_bytes;
    for (c = 0; c < shm_maxtbls; c++) {
        if (!shm_want[c]) {
            shm_tbladdr[c] = NULL;
            hzshm_ok[c] = 0;
            continue;
        }
        if (shm_tbladdr[c] != NULL || tcount[c] == 0)
            continue;
        if (!tloaded[c]) {
            if (fd < 0) {
                hzv_sync();             /* (the blitter may be reading the atlas) */
                fd = open(shm_fname, O_RDONLY);
                if (fd < 0)
                    rexit(9);
            }
            load(fd, c);
        }
        shm_tbladdr[c] = (char far *)hzshm_shape(c, 0);
        hzshm_ok[c] = 1;
        shm_tbllen[c] = (int)trows[c];
        shm_flags[c] = (int)(tflags[c] & shm_fontf);
        if (tflags[c] & 0x100) {        /* the palette shape (64 x 12): upstream's vgapal */
            const unsigned char __far *s = hzshm_shape(c, (int)tpal[c]);
            unsigned long a = hzshm_row(trow0[c] + (s[2] | s[3] << 8)) + (s[0] | s[1] << 8);
            unsigned r;
            for (r = 0; r < 12; r++)
                hz_far_copy((unsigned char *)vgapal + r * 64,
                            (const void __far *)(a + ((unsigned long)r << 9)), 64);
            vga_setpal();
        }
    }
    if (fd >= 0) {
        close(fd);
        if (hzf_stats)
            printf("xargon: pictures loaded: %lu bytes in %lu ms\n", hzshm_bytes - b0,
                   (unsigned long)hz_uptime() - t0);
    }
}

void shm_exit(void)
{
    int c;
    for (c = 0; c < shm_maxtbls; c++) {
        shm_tbladdr[c] = NULL;
        hzshm_ok[c] = 0;
    }
}
