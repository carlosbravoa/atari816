/* xload.c - the large code model's loader (hcc --code large; sdk/docs/c/reference.md, "The
 * two code models").
 *
 * A large program is one file, NAME.PRG: the main bank as an ordinary o65 file, which Horizon
 * loads, then the other code banks (hcc writes them after the o65; Horizon 0.28 and later
 * load such a file and never look at what follows the o65). crt0.s calls __hz_xload before
 * the constructors; it
 *   1. asks Horizon for the program's own path (task_path, Horizon 0.28) and opens that file;
 *   2. reads the trailer, the file's last 8 bytes {u32 the block's offset, "HZPX"}, and
 *      the block's header there: "HZPX", version 1, the number of banks and the stamp of this
 *      very link (a block from another build is refused);
 *   3. takes a bank for each image (hz_bank_alloc) and reads the image into it;
 *   4. patches the bank bytes (JSL operands, MVN banks): the relocations, in groups of
 *      {u8 where, u8 to which bank, u16 count, count x u16 offset}; bank 0 is the main bank;
 *   5. checks that the block ends just before the trailer.
 * Then the program runs as one. Horizon frees the banks when the program ends.
 *
 * The block: a 12-byte header {"HZPX", u8 1, u8 n, u16 0, u32 stamp}, n x u32 the images'
 * sizes, the images, u16 the number of relocation groups, the groups. Then the trailer.
 *
 * Any failure (an old Horizon, a cut or damaged file, no memory, a read error) prints one
 * line on the console (and shows it in a small window when the window system runs) and ends
 * the program with exit code 1 (nothing else of it has run yet).
 *
 * hcc writes the symbols this reads (its glue module): __hz_xbanks (n; 0 = everything is
 * in the main bank, nothing to load), __hz_xstamp, __hz_xname (the program's file name, for
 * the messages), __hz_xbank[n + 1] (the banks: [0] the main bank).
 */
#include <horizon.h>

extern const unsigned __hz_xbanks;
extern const unsigned long __hz_xstamp;
extern const char __hz_xname[];
extern unsigned char __hz_xbank[];

static int xh;
static unsigned long left;          /* bytes of the block not read yet */
static char path[128];
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
    add(b);
    add(c);
    hz_puts(msg);
    hz_puts("\n");
    if (xh >= 0)
        hz_close(xh);
    show();
    hz_exit(1);
}

#define CUT "the program file is cut short or damaged (its code banks): copy it again"

/* n bytes of the file into bank:off (n <= 32768), within the block */
static void rd(unsigned bank, unsigned off, unsigned n)
{
    hz_io io;
    if (n > left)
        fail(CUT, 0, 0);
    io.handle = (unsigned char)xh;
    HZ_U24B(io.buf, bank, off);
    io.len = n;
    if (hz_read(&io) != (int)n)
        fail("cannot read the program file (a card error)", 0, 0);
    left -= n;
}

static unsigned mainbank(void)
{
    return HZ_BANK((const void __far *)&xh);
}

static void rdbuf(unsigned n)
{
    rd(mainbank(), (unsigned)buf, n);
}

void __hz_xload(void)
{
    unsigned n = __hz_xbanks, i, g, k;
    hz_fileinfo st;
    unsigned long at;
    xh = -1;
    if (n == 0)
        return;
    if (n > 64)
        fail("more than 64 code banks", 0, 0);
    if (hz_task_path(path, sizeof path) < 0)
        fail("needs Horizon 0.28 or later (a program with several code banks)", 0, 0);
    if (hz_stat_path(path, &st) < 0 || st.size < 20)
        fail("cannot find its own file ", path, 0);
    xh = hz_open(path, HZ_O_READ);
    if (xh < 0)
        fail("cannot open its own file ", path, 0);
    /* the trailer: the block's offset, "HZPX" */
    left = 8;
    if (hz_seek((unsigned)xh, st.size - 8) < 0)
        fail(CUT, 0, 0);
    rdbuf(8);
    at = *(unsigned long *)buf;
    if (buf[4] != 'H' || buf[5] != 'Z' || buf[6] != 'P' || buf[7] != 'X' || at < 26 ||
        at > st.size - 8 - 14)
        fail(CUT, 0, 0);
    left = st.size - 8 - at;
    if (hz_seek((unsigned)xh, at) < 0)
        fail(CUT, 0, 0);
    rdbuf(12);
    if (buf[0] != 'H' || buf[1] != 'Z' || buf[2] != 'P' || buf[3] != 'X' || buf[4] != 1)
        fail(CUT, 0, 0);
    if (buf[5] != n || *(unsigned long *)(buf + 8) != __hz_xstamp)
        fail("its code banks are of another build of the program: build it again", 0, 0);
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
        unsigned long size = sizes[i - 1];
        unsigned off = 0;
        if (size > 0x10000UL)
            fail(CUT, 0, 0);
        while (size) {
            unsigned piece = size > 0x8000 ? 0x8000 : (unsigned)size;
            rd(__hz_xbank[i], off, piece);
            off += piece;
            size -= piece;
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
        if (where > n || buf[1] > n)
            fail(CUT, 0, 0);
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
    if (left)                               /* the block must end at the trailer */
        fail(CUT, 0, 0);
    hz_close(xh);
    xh = -1;
}
