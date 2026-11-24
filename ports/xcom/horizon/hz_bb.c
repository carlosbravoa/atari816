/* SPDX-License-Identifier: GPL-3.0-or-later */
/* The battle view's back buffer drawn by the blitter (Ali): plat.h "the
   battle view", the Atari816's side of plat/vgabat.c.

   Where things are. The framebuffer (horizon/hz_plat.c) is 320 x 400 in two
   banks: rows 0-199 are mode 13h's A000 (the screen), rows 205-348 the back
   buffer (the second bank from its offset 64: the arena's bank 13 is mapped
   onto that bank, so the engine's segment D004 (plat.h XD_BB_SEG) is these
   very bytes, for the CPU and for Ali alike), rows 349-388 the cursor's box
   kept by buf_box. Ali draws into the whole framebuffer (ABI.md, "Full-screen
   mode"), so the back buffer is a target, and a sheet over rows 205-388 is a
   source (the present, the box).

   Sprites. upstream's pictures are span-coded (tools/vgasprite.py: masked
   spans, or OR rows: one opaque span a row); the C draws them byte by byte.
   Here each picture is unpacked once, the first time it is drawn, into an
   atlas (sheets of 1024 x 256 in 4 banks), as a rectangle where every pixel
   no span covers is the picture's key: a colour none of its spans uses. A
   draw is then one keyed copy record (sheet_draw: about 300 cycles of the
   CPU), clipped here to what the C would write inside the buffer: the rows
   and columns the clipped entries allow, the buffer's 144 rows, and a span
   past the right edge continued on the next row (the C's offsets are linear).
   The atlas is keyed by the picture's address: a file read into the
   engine's memory, or a block freed, over a picture kept forgets them all
   (plat_mem_changed). A picture that uses every colour (no key) is drawn by
   the C.

   Order. Records are queued (128 a call) and sent before anything that
   needs them drawn: the present (a copy to the screen, waited for: the CPU
   draws the pointer and the interface on the screen next), the CPU's own
   work on the buffer (plat_bb_sync), the scroll (a move: draw_list). */
#include "xcompat.h"
#include <hgame.h>
#include <horizon.h>
#include "plat.h"
#include "pak.h"
#include "vga.h"

#define BB_ROW0     205u                /* the buffer's first framebuffer row */
#define BB_ROWS     144u
#define BB_W        320u
#define BOX_ROW     (BB_ROWS)           /* the box's copy: sheet row 144 (framebuffer 349) */
#define BOX_ROWS    40u
#define FB_ROWS     400u

#define ATL_W       1024u               /* an atlas sheet: stride and width */
#define ATL_H       256u                /* rows (4 banks) */
#define ATL_MAX     6                   /* sheets at most (32 in the whole system) */
#define HASH_N      2048u               /* pictures kept at most (a power of 2): 32 KB */

/* a kept picture: 16 bytes (horizon/hz_bbs.s reads them by offset) */
typedef struct {
    unsigned short lo;                  /* the picture's address: offset, */
    unsigned char bank, used;           /* bank; 1 (0: a free slot) */
    unsigned char sheet, key;
    unsigned short ax, ay;              /* its rectangle in the atlas */
    unsigned char x0, first;            /* its first column (sprite x), first row */
    unsigned short w;                   /* columns x0 .. x0 + w - 1 */
    unsigned char rows;                 /* rows first .. first + rows - 1 */
    unsigned char kind;
} Pic;
HZ_STATIC_ASSERT(sizeof(Pic) == 16, pic16);

static Pic *pics;                       /* HASH_N, in a bank of its own */
unsigned hzb_picbank;                   /* its bank (hz_bbs.s) */
static unsigned npics;
static unsigned long lo_addr = 0xFFFFFFFFUL, hi_addr;   /* what the kept pictures span */

static unsigned char atl_sheet[ATL_MAX];
static unsigned long atl_addr[ATL_MAX];
static unsigned natl;
static unsigned shelf_x, shelf_y, shelf_h, cur;  /* the packing: sheet cur's shelf */

static int bb_sheet;                    /* the buffer + box sheet */
static int shade_sheet;                 /* the night's tables (below): > 0 the sheet; 0 not
                                           made yet; -1 no colour remap */
static unsigned shade_rows;             /* bit k: row k holds level k's table */
static int failed;
/* the record path's state, shared with horizon/hz_bbs.s (plat_bb_sprite's
   fast path: a kept picture's record, in assembly) */
int hzb_ready;
hz_sheetrec hzb_q[128];
unsigned hzb_qn;
unsigned long hzb_qpx;                  /* pixels in q (a call: 460,800 at most) */
unsigned char hzb_yof[768];             /* buffer offset >> 6 -> its row (offset / 320) */
#define ready hzb_ready
#define q hzb_q
#define qn hzb_qn
#define qpx hzb_qpx
static int pending;                     /* records sent and not waited for */

unsigned long g_bb_draws, g_bb_unpacked, g_bb_flushes, g_bb_cpu;
int g_bb_wait;                          /* /S: every operation drawn before it returns (the
                                           CPU may then read the buffer at any time: BENCH's
                                           own checks do) */

/* how much of the atlas was used (a test run's end) */
void hz_bb_stats(void)
{
    if (g_bb_draws)
        printf("xcom: blitter: %lu draws, %lu pictures unpacked (%u kept), %u atlas sheets of "
               "%u KB, %lu sends, %lu drawn by the C\n", g_bb_draws, g_bb_unpacked, npics, natl,
               (unsigned)(ATL_W / 1024u * ATL_H), g_bb_flushes, g_bb_cpu);
}

static void note(const char *s)
{
    static int n;
    if (n++ < 8)
        printf("xcom: blitter: %s\n", s);
}

/* the framebuffer is up (hz_plat.c): the sheet over the buffer */
void hz_bb_screen(int on)
{
    hz_sheetnew sn;
    unsigned long a;
    unsigned i;

    for (i = 0; i < sizeof hzb_yof; i++)
        hzb_yof[i] = (unsigned char)(i / 5u);   /* (64 i + r) / 320, r < 64 */
    ready = 0;
    qn = 0;
    qpx = 0;
    pending = 0;
    if (!on) {
        if (bb_sheet > 0)
            hz_sheet_free((unsigned)bb_sheet);
        bb_sheet = 0;
        if (shade_sheet > 0) {
            hz_sheet_free((unsigned)shade_sheet);
            shade_sheet = 0;            /* (no remap stays -1: the answer does not change) */
        }
        return;
    }
    a = ((unsigned long)hg_fb_bank << 16) + (unsigned long)BB_ROW0 * BB_W;
    HZ_U24B(sn.addr, (unsigned)(a >> 16), (unsigned)a);
    sn.zero = 0;
    sn.stride = BB_W;
    sn.w = BB_W;
    sn.h = BB_ROWS + BOX_ROWS;
    bb_sheet = hz_sheet_new(&sn);
    if (bb_sheet <= 0 || bb_sheet > 32) {
        note("no sheet for the back buffer: the C draws it");
        failed = 1;
        return;
    }
    if (!pics) {
        /* a bank of its own: not the engine's malloc (the DOS memory, xdos.h) */
        pics = (Pic *)hz_far_alloc();
        if (!pics) {
            note("no memory for the pictures' table: the C draws");
            failed = 1;
            return;
        }
        memset(pics, 0, HASH_N * sizeof(Pic));
        hzb_picbank = HZ_BANK(pics);
    }
    ready = !failed;
}

void hzb_send(void)
{
    if (!qn)
        return;
    if (hz_sheet_draw(hg_win, qn, q) < 0) {
        unsigned i;
        unsigned long px = 0;
        note("sheet_draw refused");
        for (i = 0; i < qn; i++) {
            hz_sheetrec *r = &q[i];
            unsigned sw = r->sheet == (unsigned char)bb_sheet ? BB_W : ATL_W;
            unsigned shh = r->sheet == (unsigned char)bb_sheet ? BB_ROWS + BOX_ROWS : ATL_H;
            px += (unsigned long)r->w * r->h;
            if (r->op != SH_FILL && ((unsigned long)r->sx + r->w > sw || (unsigned long)r->sy + r->h > shh))
                printf("xcom: blitter: record %u: sheet %u op %u %u,%u %ux%u to %d,%d\n", i, r->sheet,
                       r->op, r->sx, r->sy, r->w, r->h, r->x, r->y);
        }
        printf("xcom: blitter: %u records, %lu pixels\n", qn, px);
    }
    g_bb_flushes++;
    qn = 0;
    qpx = 0;
    pending = 1;
}

#define send hzb_send

static void wait_done(void)
{
    send();
    if (pending) {
        PERF_T0(pt0);
        hz_list_wait(0);
        pending = 0;
        PERF_ADD(PF_BLIT, pt0);
    }
}

void plat_bb_sync(void)
{
    if (ready)
        wait_done();
}

/* a record of w x h pixels (the kernel counts 256 for one up to 16 x 16) */
static hz_sheetrec *rec(unsigned w, unsigned h)
{
    unsigned long n = (unsigned long)w * h;

    if (n < 256)
        n = 256;
    if (qn == 128 || qpx + n > 460800UL)
        send();
    qpx += n;
    return &q[qn++];
}

/* a copy (key: keyed) of sheet sh's (sx, sy) w x h to buffer (x, y) */
static void put(unsigned sh, int op, unsigned c, unsigned sx, unsigned sy, unsigned w,
                unsigned h, int x, int y)
{
    hz_sheetrec *r = rec(w, h);

    r->sheet = (unsigned char)sh;
    r->op = (unsigned char)op;
    r->c = (unsigned char)c;
    r->zero = 0;
    r->sx = (unsigned short)sx;
    r->sy = (unsigned short)sy;
    r->w = (unsigned short)w;
    r->h = (unsigned short)h;
    r->x = (short)x;
    r->y = (short)(y + (int)BB_ROW0);
}

/* the buffer offset o (16 bits) as a position: rows above the buffer are the
   offsets from C000 (the C writes them past its end: never seen) */
static void pos_of(unsigned o, int *x, int *y)
{
    unsigned k, r;

    if (o < 0xC000u) {
        r = o / 320u;
        *y = (int)r;
        *x = (int)(o - r * 320u);
    } else {
        k = 0u - o;                     /* the offset is -k */
        r = (k + 319u) / 320u;
        *y = -(int)r;
        *x = (int)(r * 320u - k);
    }
}

/* ---------------------------------------------------------------- the atlas */

static Pic arrow_pic;
static int prepared, preloading, arrow_making;
static unsigned long t_prep, t_view;    /* the battle's start (the console's line) */

static void forget_all(void)
{
    if (g_perf && npics)
        printf("xcom: blitter: atlas forgotten (%u pictures)\n", npics);
    wait_done();
    arrow_pic.used = 0;
    prepared = 0;
    if (pics)
        memset(pics, 0, HASH_N * sizeof(Pic));
    npics = 0;
    lo_addr = 0xFFFFFFFFUL;
    hi_addr = 0;
    cur = 0;
    shelf_x = shelf_y = shelf_h = 0;
}

/* The kept pictures' lengths (in the table's bank, after the table, the OR map and the
   bar's pixels): a file read or a free between two of them (the battle's start reads
   into a block among the pictures) leaves them all kept; one over a picture forgets
   them all, as before. */
#define PLEN ((unsigned short far *)((unsigned char far *)pics + 40960u))

void plat_mem_changed(const void far *p, unsigned long n)
{
    unsigned long a = (unsigned long)p, b;
    unsigned i;

    if (!npics || !n || a > hi_addr || a + n <= lo_addr)
        return;
    for (i = 0; i < HASH_N; i++)
        if (pics[i].used && PLEN[i]) {
            b = (unsigned long)pics[i].bank << 16 | pics[i].lo;
            if (b < a + n && b + PLEN[i] > a) {
                forget_all();
                return;
            }
        }
}

/* the slot of picture s: kept (fresh 0) or the free one to fill (fresh 1);
   NULL when the table is full. The hash is hz_bbs.s's. */
static Pic *find(const unsigned char far *s, int *fresh)
{
    unsigned lo = HZ_OFF(s), bank = HZ_BANK(s), k;
    unsigned h = ((lo >> 4) ^ (lo >> 13) ^ (bank << 3)) & (HASH_N - 1);
    Pic *p;

    for (k = 0; k < HASH_N; k++) {
        p = &pics[(h + k) & (HASH_N - 1)];
        if (!p->used) {
            *fresh = 1;
            return npics < HASH_N * 3 / 4 ? p : NULL;
        }
        if (p->lo == lo && p->bank == (unsigned char)bank) {
            *fresh = 0;
            return p;
        }
    }
    return NULL;
}

/* room for w x h in the atlas: the sheet and corner, 0 if none */
static int place(unsigned w, unsigned h, unsigned *sh, unsigned *ax, unsigned *ay)
{
    for (;;) {
        if (cur < natl) {
            if (shelf_x + w > ATL_W) {
                shelf_y += shelf_h;
                shelf_x = shelf_h = 0;
            }
            if (shelf_y + h <= ATL_H) {
                *sh = cur;
                *ax = shelf_x;
                *ay = shelf_y;
                shelf_x += w;
                if (h > shelf_h)
                    shelf_h = h;
                return 1;
            }
            cur++;
            shelf_x = shelf_y = shelf_h = 0;
            continue;
        }
        if (natl < ATL_MAX) {
            hz_sheetnew sn;
            unsigned b = hg_banks(4);
            int s;
            if (!b && xc_release()) {
                /* the packs' cache gives its banks back (plat/xdos.c), then once more */
                while (xc_release())
                    ;
                b = hg_banks(4);
            }
            if (!b)
                return 0;
            atl_addr[natl] = (unsigned long)b << 16;
            HZ_U24B(sn.addr, b, 0);
            sn.zero = 0;
            sn.stride = ATL_W;
            sn.w = ATL_W;
            sn.h = ATL_H;
            s = hz_sheet_new(&sn);
            if (s <= 0 || s > 32)
                return 0;
            atl_sheet[natl++] = (unsigned char)s;
            continue;
        }
        return 0;
    }
}

unsigned hzb_scan(const unsigned char far *s, int kind);
extern unsigned char hzb_used[256];
extern unsigned hzb_x0, hzb_x1;

/* Unpacks picture s into the atlas: its box, a key, the spans. */
static Pic *unpack(Pic *p, const unsigned char far *s, int kind)
{
    const unsigned char far *t = s + 2;
    unsigned first = s[0], rows = s[1], r, n, x, len, x0 = 0xFFFF, x1 = 0, key, sh, ax, ay;
    unsigned long len_all;
    unsigned char far *row;

    if (!rows)
        return NULL;
    /* pass 1: the box and the colours (horizon/hz_bbs.s) */
    len_all = hzb_scan(s, kind);
    x0 = hzb_x0;
    x1 = hzb_x1;
    if (x0 >= x1)
        x0 = x1 = 0;
    for (key = 0; key < 256 && hzb_used[key]; key++)
        ;
    if (key == 256) {
        note("a picture with every colour: drawn by the C");
        return NULL;
    }
    if (!place(x1 > x0 ? x1 - x0 : 1, rows, &sh, &ax, &ay)) {
        if (!preloading)
            forget_all();               /* full: start again (the caller tries once more) */
        return NULL;
    }
    /* pass 2: the rectangle in the key, the spans over it */
    t = s + 2;
    for (r = 0; r < rows; r++) {
        row = (unsigned char far *)(atl_addr[sh] + (unsigned long)(ay + r) * ATL_W + ax);
        if (x1 > x0)
            memset(row, (int)key, x1 - x0);
        if (kind == 0) {
            for (n = *t++; n; n--) {
                x = t[0];
                len = t[1];
                t += 2;
                if (x & 0x80)
                    t++;
                x &= 0x7F;
                if (len)
                    memcpy(row + (x - x0), t, len);
                t += len;
            }
        } else {
            x = t[0];
            len = (unsigned)t[1] * 2;
            t += 2;
            if (len)
                memcpy(row + (x - x0), t, len);
            t += len;
        }
    }
    p->lo = HZ_OFF(s);
    p->bank = (unsigned char)HZ_BANK(s);
    p->used = 1;
    p->sheet = atl_sheet[sh];
    p->key = (unsigned char)key;
    p->ax = (unsigned short)ax;
    p->ay = (unsigned short)ay;
    p->x0 = (unsigned char)(x0 > 255 ? 255 : x0);
    p->w = (unsigned short)(x1 - x0);
    p->first = (unsigned char)first;
    p->rows = (unsigned char)rows;
    p->kind = (unsigned char)kind;
    npics++;
    g_bb_unpacked++;
    PLEN[p - pics] = arrow_making ? 0 : (unsigned short)(len_all > 65535UL ? 65535UL : len_all);
    if (arrow_making)
        ;                               /* (the arrow's static picture: never read into) */
    else if ((unsigned long)s < lo_addr)
        lo_addr = (unsigned long)s;
    if ((unsigned long)s + len_all > hi_addr)
        hi_addr = (unsigned long)s + len_all;
    return p;
}

/* rows [r0, r1) and the buffer's columns [c0, c1) of the atlas rectangle
   (ax, ay) to buffer (x, y): what the C's linear offsets do, inside the
   buffer (a part past column 320 goes on the next row) */
static void put_linear(unsigned sh, unsigned key, unsigned ax, unsigned ay, unsigned w,
                       unsigned h, int x, int y)
{
    unsigned cut;

    while (x >= (int)BB_W) {
        x -= (int)BB_W;
        y++;
    }
    if (x + (int)w > (int)BB_W) {
        cut = (unsigned)((int)BB_W - x);
        put_linear(sh, key, ax + cut, ay, w - cut, h, 0, y + 1);
        w = cut;
    }
    /* the buffer's rows */
    if (y < 0) {
        if ((int)h <= -y)
            return;
        ay += (unsigned)-y;
        h -= (unsigned)-y;
        y = 0;
    }
    if (y + (int)h > (int)BB_ROWS) {
        if (y >= (int)BB_ROWS)
            return;
        h = BB_ROWS - (unsigned)y;
    }
    if (!w || !h)
        return;
    put(sh, SH_KEY, key, ax, ay, w, h, x, y);
}

/* plat_bb_sprite (plat.h) is horizon/hz_bbs.s: a kept picture's record in
   assembly; a picture not kept yet, and every case it leaves (/S, a
   destination above the buffer), comes here with the same arguments. */
int hzb_sprite_c(const unsigned char far *spr, int kind, unsigned dest, unsigned top,
                 unsigned bottom, unsigned lx, unsigned rx)
{
    Pic *p;
    int fresh, bx, by;
    unsigned r0, r1, c0, c1;

    if (!ready)
        return 0;
    p = find(spr, &fresh);
    if (!p) {
        forget_all();
        p = find(spr, &fresh);
        if (!p)
            return 0;
    }
    if (fresh) {
        PERF_T0(pt0);
        Pic *u = unpack(p, spr, kind);
        if (!u && !npics) {             /* the atlas was full: once more, empty */
            p = find(spr, &fresh);
            u = p ? unpack(p, spr, kind) : NULL;
        }
        PERF_ADD(PF_UNPACK, pt0);
        plat_busy_tick();               /* (an unpack is milliseconds) */
        p = u;
        if (!p) {
            plat_bb_sync();             /* the C draws this one, after what was sent */
            g_bb_cpu++;
            return 0;
        }
    }
    g_bb_draws++;
    if (!p->w)
        return 1;
    /* the rows and columns drawn, in the picture's coordinates */
    r0 = p->first;
    r1 = r0 + p->rows;
    if (top > r0) r0 = top;
    if (bottom < r1) r1 = bottom;
    c0 = p->x0;
    c1 = c0 + p->w;
    if (lx > c0) c0 = lx;
    if (rx < c1) c1 = rx;
    if (r0 >= r1 || c0 >= c1)
        return 1;
    /* row r of the picture is at buffer offset (dest << 2) + r * 320 */
    pos_of((unsigned)(dest << 2), &bx, &by);
    put_linear(p->sheet, p->key, p->ax + (c0 - p->x0), p->ay + (r0 - p->first), c1 - c0,
               r1 - r0, bx + (int)c0, by + (int)r0);
    if (g_bb_wait)
        wait_done();
    return 1;
}

int plat_bb_fill(unsigned off, unsigned w, unsigned rows, int colour)
{
    int x, y;
    hz_sheetrec *r;

    if (!ready)
        return 0;
    pos_of(off, &x, &y);
    if (x + (int)w > (int)BB_W || y < 0 || y + (int)rows > (int)BB_ROWS) {
        plat_bb_sync();
        return 0;
    }
    if (!w || !rows)
        return 1;
    r = rec(w, rows);
    memset(r, 0, sizeof *r);
    r->op = SH_FILL;
    r->c = (unsigned char)colour;
    r->w = (unsigned short)w;
    r->h = (unsigned short)rows;
    r->x = (short)x;
    r->y = (short)(y + (int)BB_ROW0);
    if (g_bb_wait)
        wait_done();
    return 1;
}

/* ---------------------------------------------------------------- the night's shade
   Ali's colour remap (REV $0D, Horizon 0.31: ABI.md "Colour remap"): the night's present is
   a copy through vgabat.c's shade table instead of the CPU's 115 ms. The tables are a sheet
   of 256 x 16 (row k: level k's), in the pictures' bank past PLEN; a row is written the
   first time its level is shown, after a wait (a table is a source: never written while a
   list may read it). Each call that remaps starts with its SH_TABLE record (Ali's table is
   shared). One probe (a call of one SH_TABLE record) says whether the remap is there:
   ENODEV (an older board, the blitter off) or EINVAL (Horizon before 0.31): the CPU shades
   (vgabat.c: hz_shade_rect), as before. */
#define SHADE_OFF   49152u              /* the tables: pics + 49152 .. + 53247 */

static int shade_ready(unsigned lev, const unsigned char *tab)
{
    unsigned char far *t;

    if (lev > 15 || shade_sheet < 0)
        return 0;
    t = (unsigned char far *)pics + SHADE_OFF;
    if (!shade_sheet) {
        hz_sheetnew sn;
        hz_sheetrec r;
        unsigned long a = (unsigned long)t;
        int e;
        wait_done();
        hz_far_set(t, 0, 256u * 16u);
        HZ_U24B(sn.addr, (unsigned)(a >> 16), (unsigned)a);
        sn.zero = 0;
        sn.stride = 256;
        sn.w = 256;
        sn.h = 16;
        e = hz_sheet_new(&sn);
        if (e <= 0 || e > 32) {
            shade_sheet = -1;
            printf("xcom: night shade: no sheet for the tables: by the CPU\n");
            return 0;
        }
        memset(&r, 0, sizeof r);
        r.sheet = (unsigned char)e;
        r.op = SH_TABLE;
        r.w = 256;
        r.h = 1;
        if (hz_sheet_draw(hg_win, 1, &r) < 0) {
            unsigned err = hz_errno;
            hz_sys_info();
            hz_sheet_free((unsigned)e);
            shade_sheet = -1;
            printf("xcom: night shade: no colour remap (error %u, REV $%02X): by the CPU\n",
                   err, hz_x);
            return 0;
        }
        hz_list_wait(0);
        shade_sheet = e;
        shade_rows = 0;
        printf("xcom: night shade: by the blitter's colour remap\n");
    }
    if (!(shade_rows >> lev & 1)) {
        wait_done();
        hz_far_copy(t + lev * 256u, (const unsigned char far *)tab, 256);
        shade_rows |= 1u << lev;
    }
    return 1;
}

static int present(unsigned off, unsigned w, unsigned rows, unsigned lev,
                   const unsigned char *tab)
{
    int x, y;
    hz_sheetrec *r;
    PERF_T0(pt0);

    if (!ready)
        return 0;
    pos_of(off, &x, &y);
    if (x + (int)w > (int)BB_W || y < 0 || y + (int)rows > (int)BB_ROWS) {
        plat_bb_sync();
        return 0;
    }
    if (tab && !shade_ready(lev, tab))
        return 0;
    if (w && rows) {
        if (tab) {
            /* the table's record and the copy in one call */
            if (qn > 126 || qpx + 256u + (unsigned long)w * rows > 460800UL)
                send();
            r = rec(256, 1);
            memset(r, 0, sizeof *r);
            r->sheet = (unsigned char)shade_sheet;
            r->op = SH_TABLE;
            r->sy = (unsigned short)lev;
            r->w = 256;
            r->h = 1;
        }
        r = rec(w, rows);
        r->sheet = (unsigned char)bb_sheet;
        r->op = tab ? SH_COPY | SH_REMAP : SH_COPY;
        r->c = 0;
        r->zero = 0;
        r->sx = (unsigned short)x;
        r->sy = (unsigned short)y;
        r->w = (unsigned short)w;
        r->h = (unsigned short)rows;
        r->x = (short)x;
        r->y = (short)y;                /* the screen: framebuffer rows 0-199 */
    }
    wait_done();
    PERF_ADD(PF_PRES, pt0);
    if (t_view && w == BB_W && rows == BB_ROWS) {
        printf("xcom: battle: the view shown at %lu ms\n", hz_uptime_us() / 1000);
        t_view = 0;
    }
    return 1;
}

int plat_bb_present(unsigned off, unsigned w, unsigned rows)
{
    return present(off, w, rows, 0, NULL);
}

int plat_bb_present_shade(unsigned off, unsigned w, unsigned rows, unsigned lev,
                          const unsigned char *tab)
{
    return present(off, w, rows, lev, tab);
}

int plat_bb_shift(long dx)
{
    hz_drawrec m;
    int dr, dc, sx, sy, w, h;

    if (!ready)
        return 0;
    if (!dx)
        return 1;
    /* (x, y) -> (x + dc, y + dr): the part that stays inside */
    dr = (int)(dx / 320);
    dc = (int)(dx - (long)dr * 320);
    if (dc > 160) {
        dc -= 320;
        dr++;
    } else if (dc < -160) {
        dc += 320;
        dr--;
    }
    sx = dc < 0 ? -dc : 0;
    sy = dr < 0 ? -dr : 0;
    w = (int)BB_W - (dc < 0 ? -dc : dc);
    h = (int)BB_ROWS - (dr < 0 ? -dr : dr);
    wait_done();
    if (w <= 0 || h <= 0)
        return 1;
    memset(&m, 0, sizeof m);
    m.op = LS_MOVE;
    m.x = (short)(sx + dc);
    m.y = (short)(sy + dr + (int)BB_ROW0);
    m.w = (unsigned short)w;
    m.h = (unsigned short)h;
    m.u.m.sx = (short)sx;
    m.u.m.sy = (short)(sy + (int)BB_ROW0);
    if (hz_draw_list(hg_win, 1, &m) < 0)
        note("draw_list (move) refused");
    hz_list_wait(0);
    return 1;
}

int plat_bb_box(unsigned off, unsigned w, unsigned rows, int out)
{
    int x, y;
    unsigned full, part;

    if (!ready)
        return 0;
    pos_of(off, &x, &y);
    /* the C keeps 32 x 40 bytes in order: whole rows, then part of one */
    full = w ? 1280u / w : 0;
    if (full > rows)
        full = rows;
    part = full < rows ? 1280u - full * w : 0;
    if (full + (part != 0) > BOX_ROWS || x + (int)w > (int)BB_W || y < 0 || y + (int)rows > (int)BB_ROWS || w > 320
        || (part && part >= w)) {
        plat_bb_sync();
        return 0;
    }
    if (!full && !part)
        return 1;
    /* the box's copy: sheet rows 144.., packed as the C's bytes would be when w
       is the row's width: row k at sheet row 144 + k */
    if (out) {
        if (full)
            put(bb_sheet, SH_COPY, 0, (unsigned)x, (unsigned)y, w, full, 0, (int)BOX_ROW);
        if (part)
            put(bb_sheet, SH_COPY, 0, (unsigned)x, (unsigned)y + full, part, 1, 0,
                (int)(BOX_ROW + full));
    } else {
        if (full)
            put(bb_sheet, SH_COPY, 0, 0, BOX_ROW, w, full, x, y);
        if (part)
            put(bb_sheet, SH_COPY, 0, 0, BOX_ROW + full, part, 1, x, y + (int)full);
    }
    if (g_bb_wait)
        wait_done();
    return 1;
}

/* the arrow: an atlas picture made from its pixels (its non-zero runs) */
int plat_bb_arrow(const unsigned char *px, int x, int y, int qx, int qy, int qw, int qh)
{
    int c0, c1, r0, r1;

    if (!ready)
        return 0;
    if (!arrow_pic.used) {
        /* the masked format: each row's runs of non-zero pixels (0 is clear) */
        static unsigned char spr[2 + 9 * (1 + 5 * 2 + 9)];
        unsigned k = 0, r, c, e, nk;
        Pic *p;
        int fresh;
        spr[k++] = 0;
        spr[k++] = 9;
        for (r = 0; r < 9; r++) {
            nk = k++;
            spr[nk] = 0;
            for (c = 0; c < 9; c = e) {
                for (; c < 9 && !px[r * 9 + c]; c++)
                    ;
                for (e = c; e < 9 && px[r * 9 + e]; e++)
                    ;
                if (e > c) {
                    spr[nk]++;
                    spr[k++] = (unsigned char)c;
                    spr[k++] = (unsigned char)(e - c);
                    memcpy(spr + k, px + r * 9 + c, e - c);
                    k += e - c;
                }
            }
        }
        p = find((const unsigned char far *)spr, &fresh);
        if (p && fresh) {
            arrow_making = 1;           /* (out of lo_addr..hi_addr: a read into the main
                                           bank would forget the whole atlas) */
            p = unpack(p, spr, 0);
            arrow_making = 0;
        }
        if (!p) {
            plat_bb_sync();
            return 0;
        }
        arrow_pic = *p;
        arrow_pic.ax = (unsigned short)(p->ax - p->x0);     /* (column 0 of the 9) */
    }
    /* inside [qx, qx + qw) x [qy, qy + qh), the buffer */
    c0 = x > qx ? x : qx;
    c1 = x + 9 < qx + qw ? x + 9 : qx + qw;
    r0 = y > qy ? y : qy;
    r1 = y + 9 < qy + qh ? y + 9 : qy + qh;
    if (c0 < 0) c0 = 0;
    if (c1 > (int)BB_W) c1 = (int)BB_W;
    if (r0 < 0) r0 = 0;
    if (r1 > (int)BB_ROWS) r1 = (int)BB_ROWS;
    if (c0 >= c1 || r0 >= r1)
        return 1;
    put(arrow_pic.sheet, SH_KEY, arrow_pic.key, arrow_pic.ax + (unsigned)(c0 - x),
        arrow_pic.ay + (unsigned)(r0 - y), (unsigned)(c1 - c0), (unsigned)(r1 - r0), c0, r0);
    if (g_bb_wait)
        wait_done();
    return 1;
}

/* ---------------------------------------------------------------- the battle's start
   plat_bb_prepare (plat.h): every picture of the battle's pack unpacked into
   the atlas now, with a bar on the screen moving, instead of during the
   first redraws (which then took 0.4 s instead of 0.2 and the next ones a
   hitch each time a new kind of tile came into view). The bar's pixels are
   put back after: the screen is the model's (the test pictures). */
#define BAR_X   80
#define BAR_Y   96
#define BAR_W   160
#define BAR_H   6

void plat_bb_prepare(void)
{
    /* (in the pictures' bank, after the table's 32 KB: the main bank is full) */
    unsigned char far *isor = (unsigned char far *)pics + HASH_N * sizeof(Pic);    /* 512 bytes: */
    unsigned char far *under = isor + 512;      /* the OR-format pictures; the bar's pixels */
    unsigned char far *scr = (unsigned char far *)hz_farptr(hg_fb_bank, BAR_Y * BB_W + BAR_X);
    unsigned n = g_pak.n_sprites, i, r, shown = 0, fill;
    unsigned char lit = g_vmap[15], dim = g_vmap[8];
    int fresh;

    if (!ready || prepared || !g_pak.sprite || !n)
        return;
    t_prep = hz_uptime_us();
    if (n > 512 * 8)
        n = 512 * 8;
    memset(isor, 0, 512);
    for (i = 1; i < g_pak.n_mcd; i++) {
        const Mcd *m = &g_pak.mcd[i];
        unsigned k = OR_SPRITE(m);
        if (MCD_PART(m) == PART_FLOOR && k != OR_NONE && k < n)
            isor[k >> 3] |= (unsigned char)(1 << (k & 7));
    }
    wait_done();
    for (r = 0; r < BAR_H; r++) {
        hz_far_copy(under + r * BAR_W, scr + r * BB_W, BAR_W);
        hz_far_set(scr + r * BB_W, r == 0 || r == BAR_H - 1 ? dim : 0, BAR_W);
        scr[r * BB_W] = scr[r * BB_W + BAR_W - 1] = dim;
    }
    preloading = 1;
    for (i = 0; i < n; i++) {
        const unsigned char far *s = (const unsigned char far *)g_pak.sprite[i];
        Pic *p;
        if (!s)
            continue;
        p = find(s, &fresh);
        if (!p)
            break;                      /* the table is full: the rest as they come */
        if (fresh && !unpack(p, s, isor[i >> 3] >> (i & 7) & 1) && natl == ATL_MAX)
            break;                      /* the atlas is full: the same */
        fill = (unsigned)((unsigned long)(i + 1) * (BAR_W - 4) / n);
        if (fill > shown + 3 || i + 1 == n) {
            for (r = 2; r < BAR_H - 2; r++)
                hz_far_set(scr + r * BB_W + 2 + shown, lit, fill - shown);
            shown = fill;
        }
    }
    preloading = 0;
    prepared = 1;
    t_view = hz_uptime_us();
    printf("xcom: battle: %u pictures ready at %lu ms (%lu ms)\n", npics, t_view / 1000,
           (t_view - t_prep) / 1000);
    for (r = 0; r < BAR_H; r++)
        hz_far_copy(scr + r * BB_W, under + r * BAR_W, BAR_W);
}
