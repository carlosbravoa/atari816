/* gt_nightx.c - the blitter's colour remap (REV $0D) as the X-COM port's night view uses it,
 * checked pixel by pixel against the CPU's result. For the emulator's test suite and for the
 * board: it needs no data and prints one PASS or FAIL line a case.
 *
 * The framebuffer is 320 x 400 (hg_screen_fb), as X-COM's: the screen is rows 0-199, the
 * "back buffer" rows 205-388 (a sheet of 320 x 184 over them, as horizon/hz_bb.c's), the
 * 16 shade tables a sheet of 256 x 16 at offset 49,152 of a bank of their own. The back
 * buffer holds a known pattern; every case fills the screen with SENTINEL, draws with
 * sheet_draw and then compares each screen row with the row the CPU computes: a pixel a
 * record covers is table[level][source] (level 0: the source), any other pixel SENTINEL.
 *
 * Cases:
 *   whole       a SH_TABLE record and one remapped copy of the 320 x 144 view (section 4j)
 *   cells-*     the night lights (section 4k): 20 x 18 cells of 16 x 8 pixels, each at a
 *               level; records made as plat/vgabat.c lit_recs makes them: a row's runs of one
 *               level, grouped by level, a run under its level's last record at the same
 *               columns joined to it (tall records), level 0 a plain copy, a SH_TABLE record
 *               where the level changes and at the start of every call of 128
 *               (random levels, columns of alternating levels, a lit disc in the dark, rows)
 *   cells-busy  cells-random while the CPU copies memory until the list is done (the SDRAM
 *               port shared)
 *   align       remapped copies at every source and destination byte offset (0-3), widths
 *               1-100: not used by X-COM (its records start at multiples of 16 pixels)
 *   inplace     a remapped copy whose source is its destination (the screen through a table)
 *   keyed       SH_KEY + SH_REMAP: the key colour tested on the source pixel
 *   reload      the table sheet's rows changed by the CPU between calls, then loaded again
 *
 * A FAIL line gives the number of wrong pixels, the first one (x, y, the value read, the
 * value wanted, the record that drew it: its level, source and destination rectangle) and
 * how the wrong pixels fall on the columns: by x mod 4 (the byte lane of a 32-bit word) and
 * by x mod 16 (X-COM's cell). Older boards (before REV $0D) have no remap: nothing to test. */
#include <stdio.h>
#include <string.h>
#include <hgame.h>

#define W           320
#define VIEW_H      144                 /* X-COM's battle view */
#define SCR_H       200                 /* the screen rows checked */
#define BB_ROW0     205u                /* the back buffer's first framebuffer row */
#define BB_H        184u
#define SENTINEL    0xEE
#define KEY         0x55
#define NREC        400
#define COLS        20
#define ROWS        18

static unsigned fails;
static unsigned rev;
static int bb_sheet, tab_sheet, scr_sheet;
static unsigned char __far *tabs;       /* the 16 tables (the table sheet's memory) */
static unsigned char __far *spare;      /* a bank for the CPU's copies (cells-busy) */

/* the records of a case, and what the CPU must find: for record k its level (0 a plain
 * copy, 255 a SH_TABLE record) and whether its source is the screen (in place) */
static hz_sheetrec rec[NREC];
static unsigned char rlev[NREC];
static unsigned nrec;
static unsigned char lev[ROWS][COLS];
static unsigned char want_row[W], got_row[W], scr_row[W];
static int keyed_case;

/* the back buffer's pattern at (x, row of the sheet), the screen's before an in-place copy,
 * and table l (1-15) */
static unsigned bb_px(unsigned x, unsigned y)
{
    return (x * 3u + y * 7u + (x >> 4) * 11u) & 255u;
}

static unsigned scr_px(unsigned x, unsigned y)
{
    return (x * 5u + y * 3u + 101u) & 255u;
}

static unsigned tv(unsigned l, unsigned c)
{
    return (c * (2u * l + 1u) + 37u * l) & 255u;
}

static unsigned char __far *fb_row(unsigned y)
{
    return (unsigned char __far *)(((unsigned long)hg_fb_bank << 16) + (unsigned long)y * W);
}

static void table_rec(unsigned l)
{
    hz_sheetrec *r = &rec[nrec];

    memset(r, 0, sizeof *r);
    r->sheet = (unsigned char)tab_sheet;
    r->op = SH_TABLE;
    r->sy = (unsigned short)l;
    r->w = 256;
    r->h = 1;
    rlev[nrec++] = 255;
}

static void copy_rec(unsigned l, int from_screen, unsigned sx, unsigned sy, unsigned w, unsigned h,
                     int x, int y)
{
    hz_sheetrec *r = &rec[nrec];

    memset(r, 0, sizeof *r);
    r->sheet = (unsigned char)(from_screen ? scr_sheet : bb_sheet);
    r->op = (unsigned char)((keyed_case ? SH_KEY : SH_COPY) | (l ? SH_REMAP : 0));
    r->c = keyed_case ? KEY : 0;
    r->sx = (unsigned short)sx;
    r->sy = (unsigned short)sy;
    r->w = (unsigned short)w;
    r->h = (unsigned short)h;
    r->x = (short)x;
    r->y = (short)y;
    rlev[nrec++] = (unsigned char)l;
}

/* the screen filled with SENTINEL by the CPU (or with scr_px for an in-place case) */
static void clear_screen(int pattern)
{
    unsigned x, y;

    hz_list_wait(0);
    for (y = 0; y < SCR_H; y++) {
        if (pattern)
            for (x = 0; x < W; x++)
                scr_row[x] = (unsigned char)scr_px(x, y);
        else
            memset(scr_row, SENTINEL, W);
        hz_far_copy(fb_row(y), (const unsigned char __far *)scr_row, W);
    }
}

/* the records sent as X-COM sends them: calls of 128, then a wait (which also flushes the
 * CPU's cache); with busy, the CPU copies 4 KB blocks in a bank of its own meanwhile */
static int send(int busy)
{
    unsigned i, k;
    unsigned long copies = 0;

    for (i = 0; i < nrec; i += k) {
        k = nrec - i < 128 ? nrec - i : 128;
        if (hz_sheet_draw(hg_win, k, &rec[i]) != (int)k) {
            printf("FAIL nightx: sheet_draw refused records %u-%u (error %u)\n", i, i + k - 1,
                   hz_errno);
            ++fails;
            hz_list_wait(0);
            return 0;
        }
        while (busy && hz_list_wait(1)) {
            hz_far_copy(spare, spare + 8192, 4096);
            copies++;
        }
    }
    hz_list_wait(0);
    if (busy)
        printf("nightx: %lu copies of 4 KB by the CPU while the lists ran\n", copies);
    return 1;
}

/* the CPU's screen row y: the records in order (a later one over an earlier one) */
static void want(unsigned y)
{
    unsigned k, x, cur = 0;

    memset(want_row, SENTINEL, W);
    for (k = 0; k < nrec; k++) {
        const hz_sheetrec *r = &rec[k];
        unsigned l = rlev[k];
        if (l == 255) {
            cur = r->sy;                /* the table loaded */
            continue;
        }
        if (y < (unsigned)r->y || y >= (unsigned)r->y + r->h)
            continue;
        for (x = 0; x < r->w; x++) {
            unsigned sx = r->sx + x, sy = r->sy + (y - (unsigned)r->y), c;
            c = r->sheet == (unsigned char)scr_sheet ? scr_px(sx, sy) : bb_px(sx, sy);
            if (keyed_case && c == KEY)
                continue;
            want_row[(unsigned)r->x + x] = (unsigned char)(l ? tv(cur, c) : c);
        }
    }
}

/* the record that drew (x, y) last, for the FAIL line */
static int who(unsigned x, unsigned y)
{
    int k, found = -1;

    for (k = 0; k < (int)nrec; k++) {
        const hz_sheetrec *r = &rec[k];
        if (rlev[k] != 255 && x >= (unsigned)r->x && x < (unsigned)r->x + r->w
            && y >= (unsigned)r->y && y < (unsigned)r->y + r->h)
            found = k;
    }
    return found;
}

static void check(const char *what)
{
    unsigned x, y, bad = 0, fx = 0, fy = 0, fg = 0, fw = 0, m4[4], m16[16], i;
    int k;

    memset(m4, 0, sizeof m4);
    memset(m16, 0, sizeof m16);
    for (y = 0; y < SCR_H; y++) {
        want(y);
        hz_far_copy((unsigned char __far *)got_row, fb_row(y), W);
        for (x = 0; x < W; x++)
            if (got_row[x] != want_row[x]) {
                if (!bad++) {
                    fx = x;
                    fy = y;
                    fg = got_row[x];
                    fw = want_row[x];
                }
                m4[x & 3]++;
                m16[x & 15]++;
            }
    }
    if (!bad) {
        printf("PASS nightx: %s (%u records)\n", what, nrec);
        return;
    }
    ++fails;
    printf("FAIL nightx: %s (%u records): %u pixels wrong, the first at %u,%u: %02X, wanted %02X\n",
           what, nrec, bad, fx, fy, fg, fw);
    k = who(fx, fy);
    if (k >= 0)
        printf("      its record %d: level %u, source %u,%u (%s), %u x %u, to %d,%d\n", k,
               rlev[k], rec[k].sx, rec[k].sy, rec[k].sheet == (unsigned char)scr_sheet ?
               "the screen" : "the back buffer", rec[k].w, rec[k].h, rec[k].x, rec[k].y);
    else
        printf("      no record covers it (should be %02X)\n", SENTINEL);
    printf("      wrong by x mod 4:");
    for (i = 0; i < 4; i++)
        printf(" %u", m4[i]);
    printf("; by x mod 16:");
    for (i = 0; i < 16; i++)
        printf(" %u", m16[i]);
    printf("\n");
}

/* plat/vgabat.c lit_recs for the whole view (cells of 16 x 8 at lev[][]) */
static void cell_recs(void)
{
    static unsigned short rx[COLS * ROWS], rw[COLS * ROWS], ry[COLS * ROWS], rl[COLS * ROWS];
    static unsigned short jx[W / 4];
    unsigned n = 0, r, c, l, i, cur = 0xFFFF;
    unsigned k0 = nrec;

    for (r = 0; r < ROWS; r++)
        for (c = 0; c < COLS; c++) {
            l = lev[r][c];
            if (c && n && rl[n - 1] == l && ry[n - 1] == r * 8 && rx[n - 1] + rw[n - 1] == c * 16) {
                rw[n - 1] += 16;
                continue;
            }
            rx[n] = (unsigned short)(c * 16);
            rw[n] = 16;
            ry[n] = (unsigned short)(r * 8);
            rl[n] = (unsigned short)l;
            n++;
        }
    for (l = 0; l < 16; l++) {
        for (i = 0; i < W / 4; i++)
            jx[i] = 0xFFFF;
        for (i = 0; i < n; i++) {
            unsigned j;
            if (rl[i] != l)
                continue;
            j = jx[rx[i] >> 2];
            if (j != 0xFFFF && rec[j].w == rw[i] && (unsigned)rec[j].y + rec[j].h == ry[i]) {
                rec[j].h += 8;          /* (its source grows with it) */
                continue;
            }
            if (!((nrec - k0) & 127))
                cur = 0xFFFF;
            if (l && cur != l) {
                for (;;) {
                    table_rec(l);
                    if ((nrec - k0) & 127)
                        break;
                }
                cur = l;
            }
            copy_rec(l, 0, rx[i], ry[i], rw[i], 8, (int)rx[i], (int)ry[i]);
            jx[rx[i] >> 2] = (unsigned short)(nrec - 1);
        }
    }
}

static unsigned long seed = 12345;

static unsigned rnd16(void)
{
    seed = seed * 1103515245UL + 12345UL;
    return (unsigned)(seed >> 16) & 0x7FFF;
}

static void cells_case(const char *what, int kind, int busy)
{
    unsigned r, c;

    for (r = 0; r < ROWS; r++)
        for (c = 0; c < COLS; c++) {
            unsigned l;
            if (kind == 0)
                l = rnd16() & 15;
            else if (kind == 1)
                l = (c & 1) ? 10 : 0;
            else if (kind == 2) {
                int dx = (int)c - 9, dy = (int)r * 2 - 17;
                unsigned d = (unsigned)(dx * dx + dy * dy / 4);
                l = d < 100 ? d / 10 : 10;
            } else
                l = r & 15;
            lev[r][c] = (unsigned char)l;
        }
    clear_screen(0);
    nrec = 0;
    cell_recs();
    if (send(busy))
        check(what);
}

int main(void)
{
    hz_sheetnew sn;
    hz_sheetrec probe;
    unsigned x, y, l, s, d, w;
    unsigned long a;
    unsigned char __far *bank;
    static const unsigned char widths[] = { 1, 2, 3, 4, 5, 7, 8, 13, 16, 17, 31, 32, 33, 64, 100 };

    if (hg_screen_fb(HG_320X180, "gt_nightx", W, 400) < 0) {
        printf("FAIL nightx: hg_screen_fb\n");
        return 1;
    }
    hz_sys_info();
    rev = hz_x;
    printf("nightx: REV $%02X, framebuffer in banks %02X-%02X\n", rev, hg_fb_bank, hg_fb_bank + 1);
    hg_flush(1);

    /* the back buffer's pattern (rows 205-388: one bank, row 205 at offset 64) */
    for (y = 0; y < BB_H; y++) {
        for (x = 0; x < W; x++)
            got_row[x] = (unsigned char)bb_px(x, y);
        hz_far_copy(fb_row(BB_ROW0 + y), (const unsigned char __far *)got_row, W);
    }
    /* the tables: a bank of their own, at offset 49,152 as X-COM's */
    bank = (unsigned char __far *)hz_far_alloc();
    spare = (unsigned char __far *)hz_far_alloc();
    if (!bank || !spare) {
        printf("FAIL nightx: no bank for the tables\n");
        return 1;
    }
    tabs = bank + 49152u;
    for (l = 0; l < 16; l++) {
        for (x = 0; x < 256; x++)
            got_row[x] = (unsigned char)tv(l, x);
        hz_far_copy(tabs + l * 256u, (const unsigned char __far *)got_row, 256);
    }
    /* the sheets: the back buffer, the tables, the screen */
    a = ((unsigned long)hg_fb_bank << 16) + (unsigned long)BB_ROW0 * W;
    HZ_U24B(sn.addr, (unsigned)(a >> 16), (unsigned)a);
    sn.zero = 0;
    sn.stride = W;
    sn.w = W;
    sn.h = BB_H;
    bb_sheet = hz_sheet_new(&sn);
    a = (unsigned long)tabs;
    HZ_U24B(sn.addr, (unsigned)(a >> 16), (unsigned)a);
    sn.stride = 256;
    sn.w = 256;
    sn.h = 16;
    tab_sheet = hz_sheet_new(&sn);
    HZ_U24B(sn.addr, hg_fb_bank, 0);
    sn.stride = W;
    sn.w = W;
    sn.h = SCR_H;
    scr_sheet = hz_sheet_new(&sn);
    if (bb_sheet <= 0 || tab_sheet <= 0 || scr_sheet <= 0) {
        printf("FAIL nightx: sheet_new (%d %d %d)\n", bb_sheet, tab_sheet, scr_sheet);
        return 1;
    }
    /* the probe X-COM makes: one SH_TABLE record */
    memset(&probe, 0, sizeof probe);
    probe.sheet = (unsigned char)tab_sheet;
    probe.op = SH_TABLE;
    probe.w = 256;
    probe.h = 1;
    if (hz_sheet_draw(hg_win, 1, &probe) < 0) {
        printf("nightx: no colour remap (error %u, REV $%02X): nothing to test\n", hz_errno, rev);
        printf("gt_nightx: 0 failed\n");
        return 0;
    }
    hz_list_wait(0);

    /* whole: the view through table 9 */
    clear_screen(0);
    nrec = 0;
    table_rec(9);
    copy_rec(9, 0, 0, 0, W, VIEW_H, 0, 0);
    if (send(0))
        check("whole: one table, the 320 x 144 view through it");

    cells_case("cells-random: random levels", 0, 0);
    cells_case("cells-columns: columns of levels 0 and 10", 1, 0);
    cells_case("cells-disc: a lit disc in the dark", 2, 0);
    cells_case("cells-rows: a level a cell row", 3, 0);
    seed = 12345;
    cells_case("cells-busy: random levels, the CPU copying meanwhile", 0, 1);

    /* align: every source and destination offset, the widths; 2 rows each, table 5 */
    clear_screen(0);
    nrec = 0;
    table_rec(5);
    y = 0;
    for (s = 0; s < 4; s++)
        for (d = 0; d < 4; d++) {
            x = 0;
            for (w = 0; w < sizeof widths; w++) {
                if (x + 3 + widths[w] > W) {
                    x = 0;
                    y += 2;
                }
                copy_rec(5, 0, s + x, y % 180, widths[w], 2, (int)(x + d), (int)y);
                x += 106;
            }
            y += 2;
        }
    if (send(0))
        check("align: source and destination offsets 0-3, widths 1-100");

    /* inplace: the screen through table 3, onto itself (aligned and not) */
    clear_screen(1);
    nrec = 0;
    table_rec(3);
    copy_rec(3, 1, 0, 0, W, 60, 0, 0);
    copy_rec(3, 1, 33, 70, 101, 20, 33, 70);
    if (send(0)) {
        /* (want: the screen's pattern, then the table; untouched pixels keep scr_px) */
        unsigned bad = 0, fx = 0, fy = 0, fg = 0, fw = 0;
        for (y = 0; y < SCR_H; y++) {
            hz_far_copy((unsigned char __far *)got_row, fb_row(y), W);
            for (x = 0; x < W; x++) {
                unsigned wv = scr_px(x, y);
                if (y < 60 || (y >= 70 && y < 90 && x >= 33 && x < 134))
                    wv = tv(3, wv);
                if (got_row[x] != wv && !bad++) {
                    fx = x;
                    fy = y;
                    fg = got_row[x];
                    fw = wv;
                }
            }
        }
        if (bad) {
            ++fails;
            printf("FAIL nightx: inplace: %u pixels wrong, the first at %u,%u: %02X, wanted %02X\n",
                   bad, fx, fy, fg, fw);
        } else
            printf("PASS nightx: inplace: the screen through a table onto itself\n");
    }

    /* keyed: SH_KEY + SH_REMAP, the key on the source */
    clear_screen(0);
    nrec = 0;
    keyed_case = 1;
    table_rec(12);
    copy_rec(12, 0, 0, 0, W, 40, 0, 0);
    copy_rec(12, 0, 3, 50, 77, 30, 41, 60);
    if (send(0))
        check("keyed: SH_KEY + SH_REMAP, key $55 on the source");
    keyed_case = 0;

    /* reload: the table rows changed by the CPU, loaded again */
    for (l = 1; l < 16; l++) {
        for (x = 0; x < 256; x++)
            got_row[x] = (unsigned char)tv(16 - l, x);
        hz_far_copy(tabs + l * 256u, (const unsigned char __far *)got_row, 256);
    }
    clear_screen(0);
    nrec = 0;
    for (l = 1; l < 16; l++) {
        table_rec(l);
        copy_rec(l, 0, l * 16, l * 8, 64, 8, (int)(l * 16), (int)(l * 8));
    }
    if (send(0)) {
        /* (want() takes table row l as tv(l, c): row l is now tv(16 - l, c)) */
        for (x = 0; x < nrec; x++)
            if (rlev[x] == 255)
                rec[x].sy = (unsigned short)(16 - rec[x].sy);
        check("reload: the table sheet changed by the CPU, loaded again");
    }

    printf("gt_nightx: %u failed\n", fails);
    for (x = 0; x < 300; x++)
        if (!hg_frame())
            break;
    return 0;
}
