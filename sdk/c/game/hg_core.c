/* hg_core.c - hgame: the screen (full screen or a window), the palette, memory, the frame
 * loop, events and input, errors. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "hg_int.h"

unsigned hg_w, hg_h, hg_win = 0xFFFF, hg_fb_bank, hg_fb_stride, hg_fb_rows;
unsigned hg_frames, hg_missed, hg_pauses;
unsigned long hg_cpu_ms;
unsigned char hg__kind, hg__mode, hg__double, hg__page, hg__scroll, hg__began;
unsigned hg__pagey;
int hg__ox, hg__oy;
unsigned long hg__fbbase;
hz_fsscroll hg__scr;
unsigned char hg__scr_dirty;

void (*hg__hook_sprites)(void);
void (*hg__hook_bobs)(void);
void (*hg__hook_bobs_begin)(void);
void (*hg__hook_scroll)(void);
void (*hg__hook_sound)(void);
void (*hg__hook_close_sprites)(void);
void (*hg__hook_close_sound)(void);
void (*hg__hook_close_images)(void);
void (*hg__hook_close_map)(void);
void (*hg__hook_pause)(int on);

static unsigned char ws_own, atexit_set, quit_req, autopause = 1;
static unsigned lastf, endf;
static unsigned long t_begin;
static char title_buf[40];

/* ---------------------------------------------------------------- errors */

static unsigned nfail;

void hg__fail(const char *fn, const char *msg)
{
    if (nfail >= 16)
        return;
    ++nfail;
    hz_puts("hgame: ");
    hz_puts(fn);
    hz_puts(": ");
    hz_puts(msg);
    hz_puts("\n");
}

/* ---------------------------------------------------------------- memory */

#define MAXBANKS 64
static unsigned char fbbanks[MAXBANKS], nfbbanks;      /* the framebuffer's */
static unsigned char membanks[MAXBANKS], nmembanks;    /* far memory's (images, sounds) */
static unsigned fm_bank;
static unsigned long fm_used;

static void keep(unsigned char *list, unsigned char *n, unsigned b)
{
    if (*n < MAXBANKS)
        list[(*n)++] = (unsigned char)b;
}

/* n consecutive banks: bank_alloc gives the lowest free bank, so normally they come in a
 * row; a bank that breaks the row is kept aside and given back at the end (deepdive) */
unsigned hg_banks(unsigned n)
{
    unsigned char spare[16];
    unsigned ns = 0, first, last, b, i;

    if (n == 0 || n > 32) {
        hg__fail("hg_banks", "1-32 banks");
        return 0;
    }
    first = last = hz_bank_alloc();
    if (hz_errno)
        return 0;
    while (last - first + 1 < n) {
        b = hz_bank_alloc();
        if (hz_errno)
            goto fail;
        if (b != last + 1) {                    /* not next to it: start again from b */
            for (i = first; i <= last; i++) {
                if (ns == sizeof spare)
                    goto fail;
                spare[ns++] = (unsigned char)i;
            }
            first = b;
        }
        last = b;
    }
    for (i = 0; i < ns; i++)
        hz_bank_free(spare[i]);
    return first;
fail:
    for (i = 0; i < ns; i++)
        hz_bank_free(spare[i]);
    if (last >= first)
        for (i = first; i <= last; i++)
            hz_bank_free(i);
    return 0;
}

unsigned long hg__farmem(unsigned long n)
{
    unsigned long a;
    unsigned b, i, nb;

    n = (n + 255) & ~255UL;
    if (n == 0)
        n = 256;
    if (n > 65536UL) {                          /* whole banks in a row */
        nb = (unsigned)((n + 65535UL) >> 16);
        b = hg_banks(nb);
        if (!b)
            return 0;
        for (i = 0; i < nb; i++)
            keep(membanks, &nmembanks, b + i);
        return (unsigned long)b << 16;
    }
    if (!fm_bank || fm_used + n > 65536UL) {
        b = hz_bank_alloc();
        if (hz_errno)
            return 0;
        keep(membanks, &nmembanks, b);
        fm_bank = b;
        fm_used = 0;
    }
    a = ((unsigned long)fm_bank << 16) + fm_used;
    fm_used += n;
    return a;
}

void hg__farmem_reset(void)
{
    unsigned i;
    for (i = 0; i < nmembanks; i++)
        hz_bank_free(membanks[i]);
    nmembanks = 0;
    fm_bank = 0;
    fm_used = 0;
}

static void free_fb(void)
{
    unsigned i;
    for (i = 0; i < nfbbanks; i++)
        hz_bank_free(fbbanks[i]);
    nfbbanks = 0;
}

/* ---------------------------------------------------------------- the screen */

static int ws_and_window(unsigned w, unsigned h, int x, int y, const char *title,
                         unsigned flags)
{
    hz_winopen wo;
    int win;

    if (hg__kind != HG__NONE) {
        hg__fail("hg_screen", "already open (hg_close first)");
        return -1;
    }
    ws_own = (unsigned char)(hz_ws_start() == 1);
    strncpy(title_buf, title ? title : "Game", sizeof title_buf - 1);
    wo.x = x;
    wo.y = y;
    wo.w = w;
    wo.h = h;
    HZ_U24(wo.title, title_buf);
    wo.flags = (unsigned char)flags;
    win = hz_win_open(&wo);
    if (win < 0) {
        hg__fail("hg_screen", "no window (is the window system there?)");
        if (ws_own)
            hz_ws_stop();
        return -1;
    }
    hg_win = (unsigned)win;
    if (!atexit_set) {
        atexit(hg_close);
        atexit_set = 1;
    }
    hg_srand((unsigned)hz_uptime() | 1);
    hg_frames = hg_missed = 0;
    hg_cpu_ms = 0;
    quit_req = 0;
    hg__ox = hg__oy = 0;
    lastf = endf = hz_frame();
    return 0;
}

static void wtext(int x, int y, const char *s)
{
    hz_windraw d;
    d.op = WD_TEXT;
    d.c1 = C_BLACK;
    d.c2 = C_BODY;
    d.font = 0;
    d.x = x;
    d.y = y;
    d.w = d.h = 0;
    HZ_U24(d.ptr, s);
    d.stride = 0;
    hz_win_draw(hg_win, &d);
}

int hg__fs_enter(unsigned stride, unsigned rows, unsigned fbb)
{
    hz_fsenter fe;
    fe.mode = hg__mode;
    fe.flags = 0;
    fe.stride = stride;
    fe.rows = rows;
    HZ_U24B(fe.base, fbb, 0);
    fe.zero = 0;
    return hz_fs_enter(hg_win, &fe);
}

static unsigned fsflags;

int hg_screen(unsigned mode, const char *title)
{
    return hg_screen_fb(mode, title, 0, 0);
}

int hg_screen_fb(unsigned mode, const char *title, unsigned fbstride, unsigned fbrows)
{
    static char line[48];
    unsigned m = mode & 0xFF, stride, rows, nb, b, i;

    if (m > 2 || (mode & ~0x3FFu)) {
        hg__fail("hg_screen", "mode: HG_320X180, HG_640X360 or HG_640X360X4 (| HG_DOUBLE)");
        return -1;
    }
    if ((fbstride || fbrows) && (mode & HG_DOUBLE)) {
        hg__fail("hg_screen_fb", "a framebuffer of its own size is one page (no HG_DOUBLE)");
        return -1;
    }
    hg_w = m == FS_320X8 ? 320 : 640;
    hg_h = m == FS_320X8 ? 180 : 360;
    stride = m == FS_640X8 ? 640 : 320;
    rows = (mode & HG_DOUBLE) ? hg_h * 2 : hg_h;
    if (fbstride || fbrows) {
        if (fbstride && (fbstride < stride || fbstride > 4096 || (fbstride & 15))) {
            hg__fail("hg_screen_fb", "stride: a multiple of 16, a line (640 / 320) to 4096");
            return -1;
        }
        if (fbrows && (fbrows < hg_h || fbrows > 1024)) {
            hg__fail("hg_screen_fb", "rows: the screen's (360 / 180) to 1024");
            return -1;
        }
        if (fbstride)
            stride = fbstride;
        if (fbrows)
            rows = fbrows;
    }
    if (ws_and_window(280, 44, 180, 150, title, 0))
        return -1;
    sprintf(line, "%.30s is paused.", title_buf);
    wtext(8, 6, line);
    wtext(8, 24, "Alt+Tab or a click here: back to it.");
    hg__mode = (unsigned char)m;
    hg__double = (unsigned char)((mode & HG_DOUBLE) != 0);
    fsflags = (mode & HG_POINTER) ? FS_PTR : 0;
    nb = (unsigned)(((unsigned long)stride * rows + 65535UL) >> 16);
    b = hg_banks(nb);
    if (!b) {
        hg__fail("hg_screen", "not enough memory for the framebuffer");
        hg_close();
        return -1;
    }
    for (i = 0; i < nb; i++)
        keep(fbbanks, &nfbbanks, b + i);
    hg__kind = HG__FULL;
    if (hg__fs_enter(stride, rows, b)) {
        hg__fail("hg_screen", hz_errno == HZ_EAGAIN ? "another program is in full screen"
                 : "fs_enter refused");
        hg_close();
        return -1;
    }
    if (fsflags) {                              /* the pointer flag: enter again with it */
        hz_fsenter fe;
        fe.mode = hg__mode;
        fe.flags = (unsigned char)fsflags;
        fe.stride = stride;
        fe.rows = rows;
        HZ_U24B(fe.base, b, 0);
        fe.zero = 0;
        hz_fs_enter(hg_win, &fe);
    }
    hg_fb_bank = b;
    hg_fb_stride = stride;
    hg_fb_rows = rows;
    hg__fbbase = (unsigned long)b << 16;
    hg__page = 0;
    hg__pagey = 0;
    hg__scroll = 0;
    memset(&hg__scr, 0, sizeof hg__scr);
    hg__scr_dirty = 0;
    /* clear every row (both pages) to colour 0, then start drawing the second page */
    {
        unsigned char d = hg__double;
        hg__double = 0;                         /* (clip to the whole framebuffer) */
        hg_origin(0, 0);                        /* (every byte of every row) */
        hg_fill(0, 0, m == FS_640X4 ? stride * 2 : stride, rows, 0);
        hg__double = d;
    }
    hg_flush(1);
    if (hg__double) {
        hg__page = 1;
        hg__pagey = hg_h;
    }
    hg__clip_update();
    lastf = endf = hz_frame();
    return 0;
}

/* (also the framebuffer for hg_map: new banks, the old ones freed) */
int hg__fb_new(unsigned stride, unsigned rows)
{
    unsigned nb, b, i;
    hz_fsscroll z;
    nb = (unsigned)(((unsigned long)stride * rows + 65535UL) >> 16);
    b = hg_banks(nb);
    if (!b) {
        hg__fail("hg_map", "no memory for the framebuffer");
        return -1;
    }
    memset(&z, 0, sizeof z);                    /* (a scroll set that fits any buffer: */
    hz_fs_scroll(&z);                           /* fs_enter checks the set in use) */
    if (hg__fs_enter(stride, rows, b)) {
        hg__fail("hg_map", "fs_enter refused the new framebuffer");
        for (i = 0; i < nb; i++)
            hz_bank_free(b + i);
        return -1;
    }
    hz_list_wait(0);
    free_fb();
    for (i = 0; i < nb; i++)
        keep(fbbanks, &nfbbanks, b + i);
    hg_fb_bank = b;
    hg_fb_stride = stride;
    hg_fb_rows = rows;
    hg__fbbase = (unsigned long)b << 16;
    hg__clip_update();
    return 0;
}

int hg_window(unsigned w, unsigned h, const char *title)
{
    if (w < 16 || h < 16 || w > 636 || h > 330) {
        hg__fail("hg_window", "size: 16 x 16 to 636 x 330");
        return -1;
    }
    if (ws_and_window(w, h, (int)(640 - w - 2) / 2, 16 + (int)(344 - h - 16) / 2, title,
                      WF_HOVER))
        return -1;
    hg__kind = HG__WINDOW;
    hg__double = 0;
    hg__page = 0;
    hg__pagey = 0;
    hg_w = w;
    hg_h = h;
    hg__clip_update();
    return 0;
}

int hg_window_menu(const char *menus)
{
    if (hg__kind == HG__NONE) {
        hg__fail("hg_window_menu", "no window yet");
        return -1;
    }
    return hz_win_menu(hg_win, menus);
}

void hg_close(void)
{
    if (hg__kind == HG__NONE && hg_win == 0xFFFF)
        return;
    if (hg__listrun)
        hz_list_wait(0);
    hg__listrun = 0;
    hg__qn = 0;
    hg__qpix = 0;
    hg__nruns = 0;
    if (hg__hook_close_sound)
        hg__hook_close_sound();
    if (hg__hook_close_sprites)
        hg__hook_close_sprites();
    if (hg__hook_close_map)
        hg__hook_close_map();
    if (hg__kind == HG__FULL)
        hz_fs_leave(hg_win);
    if (hg__hook_close_images)
        hg__hook_close_images();
    if (hg_win != 0xFFFF)
        hz_win_close(hg_win);
    free_fb();
    hg__farmem_reset();
    if (ws_own)
        hz_ws_stop();
    ws_own = 0;
    hg_win = 0xFFFF;
    hg__kind = HG__NONE;
    hg__began = 0;
    hg__clip_update();
}

/* ---------------------------------------------------------------- the palette */

void hg_palette(unsigned first, unsigned count, const unsigned char *rgb)
{
    if (first > 255 || count == 0 || first + count > 256 || !rgb) {
        hg__fail("hg_palette", "entries 0-255, count 1-256, rgb not NULL");
        return;
    }
    if (hz_pal_set(first, count == 256 ? 0 : count, rgb))
        hg__fail("hg_palette", hz_errno == HZ_EAGAIN ? "an entry is another program's"
                 : "refused");
}

void hg_color(unsigned index, unsigned r, unsigned g, unsigned b)
{
    unsigned char rgb[3];
    rgb[0] = (unsigned char)r;
    rgb[1] = (unsigned char)g;
    rgb[2] = (unsigned char)b;
    hg_palette(index, 1, rgb);
}

void hg_palette_black(void)
{
    static unsigned char black[768];
    hz_pal_set(0, 0, black);
}

int hg_raster(unsigned count, const hz_raster *changes)
{
    if (hg__kind != HG__FULL) {
        hg__fail("hg_raster", "full screen only");
        return -1;
    }
    return hz_fs_raster(count, changes);
}

/* ---------------------------------------------------------------- the view */

static int view_ok(const char *fn)
{
    if (hg__kind != HG__FULL || hg__double || hg__scroll) {
        hg__fail(fn, "full screen, one page, no hg_map");
        return 0;
    }
    return 1;
}

/* does a set that starts at (x, y) and shows n rows fit the framebuffer? */
static int view_fits(int x, int y, unsigned n)
{
    unsigned line = hg__mode == FS_640X8 ? 640 : 320;     /* bytes a line shows */
    unsigned bx = hg__mode == FS_640X4 ? (unsigned)x >> 1 : (unsigned)x;
    return x >= 0 && y >= 0 && (unsigned long)(unsigned)y + n <= hg_fb_rows &&
           bx + line <= hg_fb_stride;
}

void hg_scroll(int x, int y)
{
    unsigned n;
    if (!view_ok("hg_scroll"))
        return;
    n = (hg__scr.ctrl & FSC_SPLIT) ? hg__scr.split : 360;
    if (hg__mode == FS_320X8)
        n /= 2;
    if (!view_fits(x, y, n)) {
        hg__fail("hg_scroll", "the view must stay inside the framebuffer");
        return;
    }
    hg__scr.x = (unsigned)x;
    hg__scr.y = (unsigned)y;
    hg__scr_dirty = 1;
}

void hg_split(unsigned line, int x2, int y2)
{
    unsigned n;
    if (!view_ok("hg_split"))
        return;
    if (line == 0) {
        hg__scr.ctrl &= (unsigned char)~FSC_SPLIT;
        hg__scr.split = 0;
        hg__scr_dirty = 1;
        return;
    }
    if (hg__mode == FS_320X8)
        line *= 2;                              /* (Marga counts 360 lines) */
    if (line > 359) {
        hg__fail("hg_split", "line: 1 to the screen's last");
        return;
    }
    n = 360 - line;
    if (hg__mode == FS_320X8)
        n /= 2;
    if (!view_fits(x2, y2, n) ||
        !view_fits((int)hg__scr.x, (int)hg__scr.y, hg__mode == FS_320X8 ? line / 2 : line)) {
        hg__fail("hg_split", "both views must stay inside the framebuffer");
        return;
    }
    hg__scr.split = line;
    hg__scr.x2 = (unsigned)x2;
    hg__scr.y2 = (unsigned)y2;
    hg__scr.ctrl |= FSC_SPLIT;
    hg__scr_dirty = 1;
}

/* ---------------------------------------------------------------- the frame */

static void events(void);
static void input_new_frame(void);

void hg_begin(void)
{
    unsigned f, d;

    if (hg__kind == HG__NONE) {
        hg__fail("hg_begin", "no screen (hg_screen or hg_window first)");
        exit(1);
    }
    if (hg__began)
        return;
    /* records made outside a frame (after hg_screen, before the loop): drawn now, in
     * the coming vertical blank */
    if (hg__qn)
        hg__submit(1);
    /* the next frame: wait for the vertical blank, unless one came since hg_end (then
     * only for the list) */
    if (hz_frame() == endf)
        f = hz_vsync();
    else {
        hz_list_wait(0);
        f = hz_frame();
    }
    d = f - lastf;
    if (d > 1 && hg_frames)             /* (not the set-up before the first frame) */
        hg_missed += d - 1;
    lastf = f;
    hg__listrun = 0;
    hg__vblsent = 0;
    hg__qn = 0;
    hg__qpix = 0;
    hg__nruns = 0;
    hg__arena_reset();
    if (hg__hook_bobs_begin)
        hg__hook_bobs_begin();
    ++hg_frames;
    input_new_frame();
    events();
    if (hg__hook_sound)
        hg__hook_sound();
    hg__began = 1;
    t_begin = (unsigned long)hz_uptime();
}

void hg_end(void)
{
    if (!hg__began)
        return;
    /* the frame counter now: if a vertical blank passes while the records are sent (a
     * second call waits for the first, which starts in the blank), hg_begin need not
     * wait for another */
    endf = hz_frame();
    if (hg__hook_bobs)
        hg__hook_bobs();
    if (hg__hook_sprites)
        hg__hook_sprites();
    /* the CPU time of the frame: up to here (sending may wait for the blank) */
    hg_cpu_ms += (unsigned long)hz_uptime() - t_begin;
    if (hg__double) {
        /* draw the hidden page now, wait for it, then show it from the next frame on */
        hg__submit(0);
        if (hg__listrun)
            hz_list_wait(0);
        hg__scr.y = hg__pagey;
        hz_fs_scroll(&hg__scr);
        hg__page ^= 1;
        hg__pagey = hg__page ? hg_h : 0;
        hg__clip_update();
    } else {
        if (hg__hook_scroll)
            hg__hook_scroll();
        if (hg__scr_dirty) {
            hz_fs_scroll(&hg__scr);
            hg__scr_dirty = 0;
        }
        hg__submit(1);
    }
    hg__began = 0;
}

int hg_frame(void)
{
    if (hg__began)
        hg_end();
    hg_begin();
    return !quit_req;
}

void hg_quit(void)
{
    quit_req = 1;
}

void hg_autopause(int on)
{
    autopause = (unsigned char)(on != 0);
}

static unsigned long st_last;
static unsigned st_acc;

unsigned hg_steps(unsigned hz)
{
    unsigned long now = (unsigned long)hz_uptime();
    unsigned n = 0;
    if (hz == 0)
        return 1;
    if (st_last == 0 || now - st_last > 1000)
        st_last = now - 1000 / hz;             /* the first call (or after a long pause) */
    st_acc += (unsigned)(now - st_last) * hz;
    st_last = now;
    while (st_acc >= 1000) {
        st_acc -= 1000;
        ++n;
    }
    if (n > 4)
        n = 4;
    return n;
}

void hg_stats(const char *name)
{
    unsigned long hund = hg_frames ? hg_cpu_ms * 100UL / hg_frames : 0;
    printf("%s: %u frames, %u missed, CPU %lu.%02lu ms a frame\n", name, hg_frames,
           hg_missed, hund / 100, hund % 100);
}

unsigned long hg_ms(void)
{
    return (unsigned long)hz_uptime();
}

/* ---------------------------------------------------------------- events and input */

static unsigned char kdown[32], kpress[32], krel[32];
static unsigned char chq[16], chn;
static unsigned kq[16];
static unsigned char kqn;
static unsigned mclick, mlast;
static int menupick = -1;
unsigned hg_mods;
int hg_mouse_x, hg_mouse_y;
unsigned hg_mouse_b;
static unsigned joyread, joyv, joyt, p1last;
static unsigned char joyok = 1;
static unsigned p1keys(void);

static void input_new_frame(void)
{
    memset(kpress, 0, sizeof kpress);
    memset(krel, 0, sizeof krel);
    mclick = 0;
    menupick = -1;
    /* player 1 as the last frame left it (its keys; the joystick as last read) */
    p1last = p1keys() | (joyv & 15) | ((joyt & 1) ? HG_FIRE : 0);
    joyread = 0;
}

static void keys_up(void)
{
    unsigned i;
    for (i = 0; i < 32; i++)
        krel[i] |= kdown[i];
    memset(kdown, 0, sizeof kdown);
    hg_mouse_b = 0;
}

void hg__pause(void)
{
    hz_event ev;
    ++hg_pauses;
    keys_up();
    if (hg__hook_pause)                         /* (sound in use: silence) */
        hg__hook_pause(1);
    for (;;) {
        if (hz_win_event(0, &ev))
            break;
        if (ev.type == WE_CLOSE) {
            quit_req = 1;
            break;
        }
        if (ev.type == WE_FOCUS)
            break;
    }
    if (hg__hook_pause)
        hg__hook_pause(0);
    lastf = endf = hz_frame();                  /* the pause is not missed frames */
    st_last = 0;
}

static void events(void)
{
    hz_event ev;
    unsigned k, down;

    while (!hz_win_event(1, &ev)) {
        switch (ev.type) {
        case WE_KEY:
            k = ev.a & 0xFF;
            down = ev.b >> 8;
            hg_mods = ev.b & 0xFF;
            if (down) {
                if (!(kdown[k >> 3] & (1 << (k & 7))))
                    kpress[k >> 3] |= (unsigned char)(1 << (k & 7));
                kdown[k >> 3] |= (unsigned char)(1 << (k & 7));
                {
                    unsigned c = hz_key_ascii(ev.a, ev.b);
                    if (c && chn < sizeof chq)
                        chq[chn++] = (unsigned char)c;
                    if (k && kqn < sizeof kq / sizeof kq[0])
                        kq[kqn++] = k | (c & 0xFF) << 8;
                }
            } else {
                kdown[k >> 3] &= (unsigned char)~(1 << (k & 7));
                krel[k >> 3] |= (unsigned char)(1 << (k & 7));
            }
            break;
        case WE_BUTTON:
        case WE_MOTION:
            hg_mouse_x = (int)ev.a;
            hg_mouse_y = (int)ev.b;
            if (ev.type == WE_BUTTON) {
                hg_mouse_b = ev.c & 7;
                mclick |= hg_mouse_b & ~mlast;
                mlast = hg_mouse_b;
            }
            break;
        case WE_MENU:
            menupick = (int)((ev.a << 8) | (ev.b & 0xFF));
            break;
        case WE_CLOSE:
            quit_req = 1;
            break;
        case WE_UNFOCUS:
            keys_up();
            mlast = 0;
            if (hg__kind == HG__FULL && autopause)
                hg__pause();
            break;
        }
    }
}

/* (conio.c) the events now, without a frame; 1 once the window was closed */
int hg__poll(void)
{
    if (hg__kind != HG__NONE)
        events();
    return quit_req;
}

int hg_key(unsigned k)
{
    return k < 256 && (kdown[k >> 3] & (1 << (k & 7))) != 0;
}

int hg_key_pressed(unsigned k)
{
    return k < 256 && (kpress[k >> 3] & (1 << (k & 7))) != 0;
}

int hg_key_released(unsigned k)
{
    return k < 256 && (krel[k >> 3] & (1 << (k & 7))) != 0;
}

/* (conio.c) characters waiting */
unsigned hg__chars(void)
{
    return chn;
}

unsigned hg_getchar(void)
{
    unsigned c;
    if (!chn)
        return 0;
    c = chq[0];
    --chn;
    memmove(chq, chq + 1, chn);
    return c;
}

unsigned hg_key_next(void)
{
    unsigned k;
    if (!kqn)
        return 0;
    k = kq[0];
    --kqn;
    memmove(kq, kq + 1, kqn * sizeof kq[0]);
    return k;
}

unsigned hg_mouse_clicked(void)
{
    return mclick;
}

int hg_menu(void)
{
    return menupick;
}

static void readjoy(void)
{
    if (joyread)
        return;
    joyread = 1;
    joyv = joyt = 0;
    if (!joyok)
        return;
    joyv = hz_joystick();
    if (hz_errno) {                             /* an older Horizon: no joystick call */
        joyok = 0;
        joyv = 0;
        return;
    }
    joyt = hz_x;
}

unsigned hg_joy(unsigned port)
{
    readjoy();
    if (port == 1)
        return (joyv & 15) | ((joyt & 1) ? HG_FIRE : 0);
    if (port == 2)
        return ((joyv >> 4) & 15) | ((joyt & 2) ? HG_FIRE : 0);
    hg__fail("hg_joy", "port 1 or 2");
    return 0;
}

static unsigned p1keys(void)
{
    unsigned v = 0;
    if (hg_key(HG_KEY_UP) || hg_key(HG_KEY_W))
        v |= HG_UP;
    if (hg_key(HG_KEY_DOWN) || hg_key(HG_KEY_S))
        v |= HG_DOWN;
    if (hg_key(HG_KEY_LEFT) || hg_key(HG_KEY_A))
        v |= HG_LEFT;
    if (hg_key(HG_KEY_RIGHT) || hg_key(HG_KEY_D))
        v |= HG_RIGHT;
    if (hg_key(HG_KEY_SPACE) || hg_key(HG_KEY_ENTER))
        v |= HG_FIRE;
    return v;
}

unsigned hg_p1(void)
{
    return hg_joy(1) | p1keys();
}

unsigned hg_p1_pressed(void)
{
    unsigned v = hg_p1() & ~p1last;
    /* a key pressed and let go within the frame still counts */
    if (hg_key_pressed(HG_KEY_SPACE) || hg_key_pressed(HG_KEY_ENTER))
        v |= HG_FIRE;
    if (hg_key_pressed(HG_KEY_UP) || hg_key_pressed(HG_KEY_W))
        v |= HG_UP;
    if (hg_key_pressed(HG_KEY_DOWN) || hg_key_pressed(HG_KEY_S))
        v |= HG_DOWN;
    if (hg_key_pressed(HG_KEY_LEFT) || hg_key_pressed(HG_KEY_A))
        v |= HG_LEFT;
    if (hg_key_pressed(HG_KEY_RIGHT) || hg_key_pressed(HG_KEY_D))
        v |= HG_RIGHT;
    return v;
}
