/* xload.c - the large code model's loader (hcc --code large; sdk/docs/c/reference.md, "The
 * two code models").
 *
 * Horizon loads a program's main bank (the .PRG: an ordinary o65 file, below 64 KB). A
 * large program's other code banks are in a second file next to it, NAME.PRX, which hcc
 * writes with the .PRG. crt0.s calls __hz_xload before the constructors; it
 *   1. opens NAME.PRX: in the current folder, then in each folder hcc wrote into the program
 *      (hcc --prx-path; by default /APPS, /BIN, /SYSTEM, /SYSTEM/TESTS, /GAMES): Horizon
 *      does not tell a program where its file is;
 *   2. checks it: "HZPX", version 1, the number of banks and the stamp of this very link
 *      (a .PRX left from another build is refused);
 *   3. takes a bank for each image (hz_bank_alloc) and reads the image into it;
 *   4. patches the bank bytes (JSL operands, MVN banks): the relocations, in groups of
 *      {u8 where, u8 to which bank, u16 count, count x u16 offset}; bank 0 is the main bank.
 * Then the program runs as one. Horizon frees the banks when the program ends.
 *
 * The .PRX file: a 12-byte header {"HZPX", u8 1, u8 n, u16 0, u32 stamp}, n x u32 the
 * images' sizes, the images, u16 the number of relocation groups, the groups.
 *
 * Any failure (no file, a wrong file, no memory, a read error) prints one line on the
 * console (and shows it in a small window when the window system runs) and ends the
 * program with exit code 1 (nothing else of it has run yet).
 *
 * hcc writes the symbols this reads (its glue module): __hz_xbanks (n; 0 = everything is
 * in the main bank, nothing to load), __hz_xstamp, __hz_xname (the .PRX's name),
 * __hz_xdirs (the folders, each ending in '/', separated by ':'), __hz_xbank[n + 1] (the
 * banks: [0] the main bank).
 */
#include <horizon.h>

extern const unsigned __hz_xbanks;
extern const unsigned long __hz_xstamp;
extern const char __hz_xname[];
extern const char __hz_xdirs[];
extern unsigned char __hz_xbank[];

static int xh;
static unsigned char buf[256];
static unsigned long sizes[64];

static char msg[200];
static unsigned mlen;

static void add(const char *t)
{
    while (t && *t && mlen < sizeof msg - 1)
        msg[mlen++] = *t++;
    msg[mlen] = 0;
}

/* the length of the row of the message that starts at k */
static unsigned row(unsigned k)
{
    unsigned n = mlen - k > 64 ? 64 : mlen - k;
    if (k + n < mlen)
        while (n > 20 && msg[k + n] != ' ')
            n--;
    return n;
}

/* the message in a window too, when the window system runs (a program started from the
 * Desktop has no console in sight): closed by a key, a click or its close box */
static void show(void)
{
    hz_winopen w;
    hz_windraw d;
    hz_event ev;
    static char line[72];
    unsigned i = 0, n, k, rows = 0, y = 8;
    int win;
    for (k = 0; k < mlen; k += n) {         /* the rows: at most 64 characters, cut at spaces */
        n = row(k);
        rows++;
    }
    w.x = 80;
    w.y = 120;
    w.w = 460;
    w.h = 11 * rows + 30;
    HZ_U24(w.title, __hz_xname);
    w.flags = WF_MODAL;
    win = hz_win_open(&w);
    if (win < 0)
        return;
    d.op = WD_TEXT;
    d.c1 = C_BLACK;
    d.c2 = 0xFF;
    d.font = 0;
    d.x = 8;
    d.w = d.h = 0;
    for (k = 0; k < mlen; k += n) {
        n = row(k);
        while (msg[k] == ' ')
            k++, n--;
        for (i = 0; i < n; i++)
            line[i] = msg[k + i];
        line[n] = 0;
        d.y = y;
        y += 11;
        HZ_U24(d.ptr, line);
        hz_win_draw((unsigned)win, &d);
    }
    d.y = y + 5;
    HZ_U24(d.ptr, "(a key or a click closes this)");
    hz_win_draw((unsigned)win, &d);
    for (;;) {
        if (hz_win_event(0, &ev) < 0)
            break;
        if (ev.type == WE_KEY || ev.type == WE_CLOSE || ev.type == WE_BUTTON)
            break;
    }
    hz_win_close((unsigned)win);
}

static void fail(const char *why, const char *b, const char *c)
{
    mlen = 0;
    add(__hz_xname);
    add(": ");
    add(why);
    if (b == __hz_xdirs) {                  /* the folders: "/APPS, /BIN, ..." */
        const char *d;
        for (d = b; *d && mlen < sizeof msg - 3; d++) {
            if (*d == '/' && (d[1] == ':' || !d[1]) && d != b)
                continue;
            if (*d == ':') {
                add(", ");
                continue;
            }
            msg[mlen++] = *d;
            msg[mlen] = 0;
        }
        b = 0;
    }
    add(b);
    add(c);
    hz_puts(msg);
    hz_puts("\n");
    if (xh >= 0)
        hz_close(xh);
    show();
    hz_exit(1);
}

/* n bytes of the file into bank:off (n <= 32768) */
static void rd(unsigned bank, unsigned off, unsigned n)
{
    hz_io io;
    io.handle = (unsigned char)xh;
    HZ_U24B(io.buf, bank, off);
    io.len = n;
    if (hz_read(&io) != (int)n)
        fail("cannot read the file (cut short, or a card error)", 0, 0);
}

static unsigned mainbank(void)
{
    return HZ_BANK((const void __far *)&xh);
}

static void rdbuf(unsigned n)
{
    rd(mainbank(), (unsigned)buf, n);
}

static int try_open(const char *dir, unsigned dl)
{
    static char path[128];
    unsigned i = 0, k;
    for (k = 0; k < dl && i < 100; k++)
        path[i++] = dir[k];
    for (k = 0; __hz_xname[k] && i < 126; k++)
        path[i++] = __hz_xname[k];
    path[i] = 0;
    return hz_open(path, HZ_O_READ);
}

void __hz_xload(void)
{
    unsigned n = __hz_xbanks, i, g, k;
    const char *d, *e;
    xh = -1;
    if (n == 0)
        return;
    if (n > 64)
        fail("more than 64 code banks", 0, 0);
    xh = try_open("", 0);                   /* the current folder first */
    for (d = __hz_xdirs; xh < 0 && *d; d = *e ? e + 1 : e) {
        for (e = d; *e && *e != ':'; e++)
            ;
        xh = try_open(d, (unsigned)(e - d));
    }
    if (xh < 0)
        fail("not found (the program's code banks): keep it next to the .PRG, in the "
             "current folder or in ", __hz_xdirs, 0);
    rdbuf(12);
    if (buf[0] != 'H' || buf[1] != 'Z' || buf[2] != 'P' || buf[3] != 'X' || buf[4] != 1)
        fail("not a .PRX file (the code banks of a program hcc --code large built)", 0, 0);
    if (buf[5] != n || *(unsigned long *)(buf + 8) != __hz_xstamp)
        fail("made by another build of the program: copy the .PRG and the .PRX of the same "
             "build", 0, 0);
    __hz_xbank[0] = (unsigned char)mainbank();
    for (i = 1; i <= n; i++) {
        unsigned b = hz_bank_alloc();
        if (hz_errno)
            fail("not enough memory: no free 64 KB bank for the program's code", 0, 0);
        __hz_xbank[i] = (unsigned char)b;
    }
    rd(mainbank(), (unsigned)sizes, 4 * n);
    /* the images: each straight into its bank, in pieces of at most 32 KB */
    for (i = 1; i <= n; i++) {
        unsigned long left = sizes[i - 1];
        unsigned off = 0;
        while (left) {
            unsigned piece = left > 0x8000 ? 0x8000 : (unsigned)left;
            rd(__hz_xbank[i], off, piece);
            off += piece;
            left -= piece;
        }
    }
    /* the relocations */
    rdbuf(2);
    g = *(unsigned *)buf;
    while (g--) {
        unsigned where, cnt;
        unsigned char to;
        rdbuf(4);
        where = buf[0];
        to = __hz_xbank[buf[1]];
        cnt = *(unsigned *)(buf + 2);
        while (cnt) {
            unsigned m = cnt > 128 ? 128 : cnt;
            unsigned *o = (unsigned *)buf;
            rdbuf(2 * m);
            if (where == 0) {
                for (k = 0; k < m; k++)
                    *(unsigned char *)o[k] = to;
            } else {
                unsigned char __far *p = (unsigned char __far *)hz_farptr(__hz_xbank[where], 0);
                for (k = 0; k < m; k++)
                    p[o[k]] = to;
            }
            cnt -= m;
        }
    }
    hz_close(xh);
    xh = -1;
}
