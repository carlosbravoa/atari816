/* conio.c - cc65's conio on hgame: a grid of character cells (a character and a colour
 * pair each); the rows that changed are drawn as runs of one colour pair, one text record
 * each (LS_EXPAND with paper), when the program looks at the keyboard or waits. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "hg_int.h"
#include <conio.h>

#define MAXC 80
#define MAXR 36

static unsigned char cols, rows, opened, want_c, want_r, want_full;
static unsigned char cx, cy, fg = COLOR_WHITE, bg = COLOR_BLACK, rev, curs, drawn_curs;
static unsigned char cell[MAXC * MAXR], colr[MAXC * MAXR], dirty[MAXR];
static unsigned anydirty, since;

/* the 16 colours: system palette entries in a window, entries 0-15 in full screen */
static const unsigned char syscol[16] = {
    0, 1, 160, 123, 134, 77, 62, 228, 208, 94, 210, 237, 242, 157, 105, 248
};
static const unsigned char rgb[16 * 3] = {
    0, 0, 0,        255, 255, 255,  136, 0, 0,      170, 255, 238,
    204, 68, 204,   0, 204, 85,     0, 0, 170,      238, 238, 119,
    221, 136, 85,   102, 68, 0,     255, 119, 119,  51, 51, 51,
    119, 119, 119,  170, 255, 102,  0, 136, 255,    187, 187, 187
};
static unsigned char ink[16];

void conio_screen(unsigned char c, unsigned char r, unsigned char full)
{
    want_c = c;
    want_r = r;
    want_full = full;
}

static void open_screen(void)
{
    unsigned i, maxc, maxr;
    int ok;
    if (opened)
        return;
    opened = 1;
    if (want_full) {
        ok = hg_screen(want_full == 2 ? HG_640X360 : HG_320X180, "conio");
        maxc = hg_w / 8;
        maxr = hg_h / 10;
    } else {
        maxc = 79;
        maxr = 33;
        cols = want_c ? want_c : 40;
        rows = want_r ? want_r : 25;
        if (cols > maxc)
            cols = (unsigned char)maxc;
        if (rows > maxr)
            rows = (unsigned char)maxr;
        ok = hg_window(cols * 8u, rows * 10u, "conio");
    }
    if (ok < 0)
        exit(1);
    if (want_full) {
        cols = (unsigned char)(want_c && want_c < maxc ? want_c : maxc);
        rows = (unsigned char)(want_r && want_r < maxr ? want_r : maxr);
        hg_palette(0, 16, rgb);
        for (i = 0; i < 16; i++)
            ink[i] = (unsigned char)i;
    } else
        memcpy(ink, syscol, 16);
    memset(cell, ' ', sizeof cell);
    memset(colr, (bg << 4) | fg, sizeof colr);
    memset(dirty, 1, rows);
    anydirty = 1;
}

/* the changed rows into the frame's records, then sent */
static void flush(void)
{
    static char buf[MAXC + 1];
    unsigned r, i, j, n, base;
    unsigned char c, k;
    if (!opened)
        open_screen();
    if (drawn_curs) {                           /* the cursor's row again (without it) */
        dirty[drawn_curs - 1] = 1;
        drawn_curs = 0;
        anydirty = 1;
    }
    if (!anydirty)
        return;
    for (r = 0; r < rows; r++) {
        if (!dirty[r])
            continue;
        dirty[r] = 0;
        base = r * cols;
        for (i = 0; i < cols; i = j) {
            c = colr[base + i];
            for (j = i; j < cols && colr[base + j] == c; j++) {
                k = cell[base + j];
                if (k >= CH_HLINE && k <= CH_CROSS)
                    k = k == CH_HLINE ? '-' : k == CH_VLINE ? '|' : '+';
                buf[j - i] = (char)k;
            }
            n = j - i;
            buf[n] = 0;
            hg_text_bg((int)i * 8, (int)r * 10, buf, ink[c & 15], ink[c >> 4]);
        }
    }
    anydirty = 0;
    since = 0;
    hg_flush(0);
}

static void poll(void)
{
    if (hg__poll())
        exit(0);                                /* the window was closed */
}

static void put(unsigned char k)
{
    unsigned i;
    if (!opened)
        open_screen();
    if (k == '\n') {
        cx = 0;
        ++cy;
    } else if (k == '\r')
        cx = 0;
    else {
        if (cx >= cols) {
            cx = 0;
            ++cy;
        }
        if (cy >= rows) {
            memmove(cell, cell + cols, (rows - 1u) * cols);    /* scroll up a line */
            memmove(colr, colr + cols, (rows - 1u) * cols);
            memset(cell + (rows - 1u) * cols, ' ', cols);
            memset(colr + (rows - 1u) * cols, (bg << 4) | fg, cols);
            memset(dirty, 1, rows);
            anydirty = 1;
            cy = rows - 1;
        }
        i = cy * cols + cx;
        cell[i] = k;
        colr[i] = (unsigned char)(rev ? (fg << 4) | bg : (bg << 4) | fg);
        dirty[cy] = 1;
        anydirty = 1;
        ++cx;
    }
    if (cy >= rows) {
        memmove(cell, cell + cols, (rows - 1u) * cols);
        memmove(colr, colr + cols, (rows - 1u) * cols);
        memset(cell + (rows - 1u) * cols, ' ', cols);
        memset(colr + (rows - 1u) * cols, (bg << 4) | fg, cols);
        memset(dirty, 1, rows);
        anydirty = 1;
        cy = rows - 1;
    }
    if (++since >= 64 && hz_frame() != 0) {     /* now and then: show what was printed */
        flush();
        poll();
    }
}

void clrscr(void)
{
    if (!opened)
        open_screen();
    memset(cell, ' ', cols * rows);
    memset(colr, (bg << 4) | fg, cols * rows);
    memset(dirty, 1, rows);
    anydirty = 1;
    cx = cy = 0;
}

void gotoxy(unsigned char x, unsigned char y)
{
    if (!opened)
        open_screen();
    cx = x < cols ? x : cols - 1;
    cy = y < rows ? y : rows - 1;
}

void gotox(unsigned char x)
{
    gotoxy(x, cy);
}

void gotoy(unsigned char y)
{
    gotoxy(cx, y);
}

unsigned char wherex(void)
{
    return cx;
}

unsigned char wherey(void)
{
    return cy;
}

void cputc(char c)
{
    put((unsigned char)c);
}

void cputcxy(unsigned char x, unsigned char y, char c)
{
    gotoxy(x, y);
    put((unsigned char)c);
}

void cputs(const char *s)
{
    while (*s)
        put((unsigned char)*s++);
}

void cputsxy(unsigned char x, unsigned char y, const char *s)
{
    gotoxy(x, y);
    cputs(s);
}

int vcprintf(const char *format, va_list ap)
{
    char buf[160];
    int n = vsnprintf(buf, sizeof buf, format, ap);
    cputs(buf);
    return n;
}

int cprintf(const char *format, ...)
{
    va_list ap;
    int n;
    va_start(ap, format);
    n = vcprintf(format, ap);
    va_end(ap);
    return n;
}

unsigned char kbhit(void)
{
    flush();
    poll();
    return hg__chars() != 0;
}

char cgetc(void)
{
    unsigned c;
    flush();
    for (;;) {
        poll();
        c = hg_getchar();
        if (c)
            break;
        if (curs && !drawn_curs && cy < rows) { /* the cursor: a line under the cell */
            hg_fill(cx * 8, cy * 10 + 9, 8, 1, ink[fg]);
            hg_flush(0);
            drawn_curs = (unsigned char)(cy + 1);
        }
        hz_vsync();
    }
    if (drawn_curs)
        flush();
    if (c == '\r')
        c = '\n';
    else if (c == KEY_HOME)
        c = CH_HOME;
    else if (c == KEY_DEL)
        c = 127;
    return (char)c;
}

unsigned char cursor(unsigned char onoff)
{
    unsigned char o = curs;
    curs = onoff;
    return o;
}

unsigned char revers(unsigned char onoff)
{
    unsigned char o = rev;
    rev = onoff ? 1 : 0;
    return o;
}

unsigned char textcolor(unsigned char color)
{
    unsigned char o = fg;
    fg = color & 15;
    return o;
}

unsigned char bgcolor(unsigned char color)
{
    unsigned char o = bg;
    bg = color & 15;
    return o;
}

unsigned char bordercolor(unsigned char color)
{
    return 0;
}

static void line(unsigned char k, unsigned char n, int down)
{
    unsigned char x = cx;
    while (n--) {
        put(k);
        if (down) {
            cx = x;
            if (cy + 1 < rows)
                ++cy;
        }
    }
}

void chline(unsigned char length)
{
    line(CH_HLINE, length, 0);
}

void chlinexy(unsigned char x, unsigned char y, unsigned char length)
{
    gotoxy(x, y);
    chline(length);
}

void cvline(unsigned char length)
{
    line(CH_VLINE, length, 1);
}

void cvlinexy(unsigned char x, unsigned char y, unsigned char length)
{
    gotoxy(x, y);
    cvline(length);
}

void cclear(unsigned char length)
{
    line(' ', length, 0);
}

void cclearxy(unsigned char x, unsigned char y, unsigned char length)
{
    gotoxy(x, y);
    cclear(length);
}

void screensize(unsigned char *x, unsigned char *y)
{
    if (!opened)
        open_screen();
    *x = cols;
    *y = rows;
}

void waitvsync(void)
{
    flush();
    hz_vsync();
    poll();
}
