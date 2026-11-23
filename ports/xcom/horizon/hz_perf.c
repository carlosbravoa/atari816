/* SPDX-License-Identifier: GPL-3.0-or-later */
/* /M: XCOM.PRG times itself (app/README.TXT "Measuring", PORTING-NOTES.md "On the
   board"). For a machine that gives no profiler: counters of where the time goes
   (file calls, blitter waits, the vertical-blank sleeps that are the idle time, the
   view and palette sends, the pointer drawn by the CPU) and histograms of the gaps a
   player feels (between the engine's looks at the keyboard, from a pointer move to the
   arrow drawn, between arrow draws, between the battle view's presents), plus the
   music task's lateness as it sees it (mus/musd.c 'R').

   A line every 5 s (the timeline), a block every 30 s (counters and histograms of the
   period) and the totals at the exit, appended to NAME.TXT in the program's folder
   (NAME: XCOMPERF, or /MN's) and to /PC:/NAME.TXT (the PC link's folder: silently
   nothing without it). /C FILE copies FILE to /PC:/ at the exit (BENCH.TXT).
   /Q n ends the program after n seconds (a measuring run that ends by itself).

   The clock: hg_us (a syscall, about 40 us): two readings for each measured call, so
   /M costs a little itself (its own share is the REPORT line). */
#include "xcompat.h"
#include <hgame.h>
#include <horizon.h>
#include <fcntl.h>
#include <stdarg.h>
#include <unistd.h>
#include "plat.h"
#undef open
#undef close
#undef read
#undef lseek
#undef printf

unsigned char g_perf;
char g_perf_name[16] = "XCOMPERF";
unsigned g_perf_quit;                   /* /Q: seconds */
const char *g_perf_copy[4];             /* /C: files for /PC:/ at the exit */
int g_perf_ncopy;
char g_perf_args[200];                  /* the options, for the report's head */
int hz_snd_stats(int on, unsigned char *r);
unsigned perf_screen(void);             /* hz_plat.c: 'B' battle view, 'S' a screen; pan */

static const char *const slot_name[PF_N] = {
    "poll", "idle", "view", "palette", "blitwait", "present", "pointer", "open", "read",
    "seek", "close", "write", "sfx", "keypoll", "report", "card", "sfxdecode"
};

typedef struct {
    unsigned long n, us, max, bytes;
} Ctr;

static Ctr __far line[PF_N], period[PF_N], total[PF_N];

/* histograms of gaps, ms: bucket upper bounds */
enum { H_KEY, H_POLL, H_PLAG, H_PGAP, H_PRES, H_N };
static const char *const hist_name[H_N] = {
    "between the engine's keyboard looks (> 8 ms)",
    "between event polls (> 8 ms)",
    "pointer moved -> arrow drawn",
    "between arrow draws (< 1 s)",
    "between battle view presents (< 1 s)"
};
#define NB 13
static const unsigned bound[NB - 1] = { 8, 17, 25, 34, 50, 75, 100, 150, 200, 300, 500, 1000 };
static unsigned long __far hp[H_N][NB], ht[H_N][NB];
static unsigned long __far hmax_p[H_N], hmax_t[H_N], hmax_l[H_N];

/* the files: by name, totals */
#define NF 24
static struct {
    char name[14];
    unsigned long opens, reads, bytes, us;
} __far ftab[NF];
static int nf;

static unsigned long t_start, t_line, t_period, last_key, last_poll, last_draw, last_pres;
static unsigned long ptr_t;
static unsigned char ptr_pending, started;
static unsigned nline, nperiod;
static char __far text[6144];
static unsigned ntext;
static unsigned char pc_bad;

static unsigned long readings;          /* /M's own clock readings (its cost) */
static unsigned us_reading;             /* one reading's cost, measured at the start (ns / 100) */

static unsigned long now_us(void)
{
    readings++;
    return hg_us();
}

unsigned long perf_now(void)
{
    return now_us();
}

static void hist(int h, unsigned long us)
{
    unsigned long ms = us / 1000UL;
    int b = 0;

    while (b < NB - 1 && ms >= bound[b])
        b++;
    hp[h][b]++;
    ht[h][b]++;
    if (us > hmax_p[h]) hmax_p[h] = us;
    if (us > hmax_t[h]) hmax_t[h] = us;
    if (us > hmax_l[h]) hmax_l[h] = us;
}

static void count(int s, unsigned long d, unsigned long bytes)
{
    Ctr __far *c[3];
    int i;

    c[0] = &line[s];
    c[1] = &period[s];
    c[2] = &total[s];
    for (i = 0; i < 3; i++) {
        c[i]->n++;
        c[i]->us += d;
        c[i]->bytes += bytes;
        if (d > c[i]->max)
            c[i]->max = d;
    }
}

void perf_add(int slot, unsigned long t0)
{
    unsigned long now = now_us();

    count(slot, now - t0, 0);
    if (slot == PF_POLL) {
        if (last_poll && t0 - last_poll > 8000UL)
            hist(H_POLL, t0 - last_poll);
        last_poll = t0;
    } else if (slot == PF_PRES) {
        if (last_pres && now - last_pres < 1000000UL)
            hist(H_PRES, now - last_pres);
        last_pres = now;
    }
}

/* the engine looked at the keyboard (plat_key): counted, the gap from the clock already
   read (no reading of its own: they cost about 100 us each) */
void perf_key(unsigned long now)
{
    count(PF_KEY, 0, 0);
    if (last_key && now - last_key > 8000UL)
        hist(H_KEY, now - last_key);
    last_key = now;
}

void perf_io(int slot, const char *name, unsigned long bytes, unsigned long t0)
{
    static int last = -1;
    unsigned long d = now_us() - t0;
    int i;

    count(slot, d, bytes);
    if (!name)
        return;
    if (last >= 0 && !strncmp(ftab[last].name, name, 13))
        i = last;                       /* (the same file again: most reads) */
    else
        for (i = 0; i < nf; i++)
            if (!strncmp(ftab[i].name, name, 13))
                break;
    if (i == nf) {
        if (nf == NF)
            i = NF - 1;                 /* (the last row takes the rest) */
        else {
            nf++;
            strncpy(ftab[i].name, name, 13);
            ftab[i].name[13] = 0;
        }
    }
    last = i;
    if (slot == PF_OPEN)
        ftab[i].opens++;
    else {
        ftab[i].reads++;
        ftab[i].bytes += bytes;
    }
    ftab[i].us += d;
}

/* the pointer: plat_poll saw it move (perf_ptr_moved), the engine drew it */
void perf_ptr_moved(unsigned long t)
{
    if (!ptr_pending) {
        ptr_pending = 1;
        ptr_t = t;
    }
}

void perf_ptr_drawn(void)
{
    unsigned long now = now_us();

    if (ptr_pending) {
        hist(H_PLAG, now - ptr_t);
        ptr_pending = 0;
    }
    if (last_draw && now - last_draw < 1000000UL)
        hist(H_PGAP, now - last_draw);
    last_draw = now;
}

/* ---------------------------------------------------------------- the text */

static void put(const char *s)
{
    unsigned n = (unsigned)strlen(s);

    if (ntext + n >= sizeof text)
        return;                         /* (full: the next write empties it) */
    memcpy(text + ntext, s, n);
    ntext += n;
}

static void putf(const char *fmt, ...)
{
    char b[200];
    va_list ap;

    va_start(ap, fmt);
    vsnprintf(b, sizeof b, fmt, ap);
    va_end(ap);
    put(b);
}

static unsigned long ms10(unsigned long us)     /* tenths of ms */
{
    return us / 100UL;
}

/* appends the text to the card's file and the PC's */
static void write_out(int first)
{
    char path[40];
    int fd, k;
    int flags = O_WRONLY | O_CREAT | (first ? O_TRUNC : O_APPEND);

    if (!ntext)
        return;
    sprintf(path, "%s.TXT", g_perf_name);
    fd = open(path, flags);
    if (fd >= 0) {
        write(fd, text, ntext);
        close(fd);
    }
    if (!pc_bad) {
        sprintf(path, "/PC:/%s.TXT", g_perf_name);
        fd = open(path, flags);
        if (fd >= 0) {
            k = (int)write(fd, text, ntext);
            close(fd);
            if (k != (int)ntext)
                pc_bad = 1;
        } else
            pc_bad = 1;                 /* (no link: tried again only at the exit) */
    }
    ntext = 0;
}

static void line_out(unsigned long now)
{
    unsigned long wall = now - t_line;
    unsigned sc = perf_screen();
    unsigned long io = line[PF_OPEN].n + line[PF_READ].n + line[PF_SEEK].n + line[PF_CLOSE].n;
    unsigned long iou = line[PF_OPEN].us + line[PF_READ].us + line[PF_SEEK].us + line[PF_CLOSE].us;

    if (!wall)
        wall = 1;
    putf("%5lu %c%3u idle%3lu%% keys/s%4lu ptr%4lu lag%4lu gap%4lu pres%3lu gap%4lu blit%5lu io%4lu/%5luK/%5lu card%4lu/%5lu vw%3lu pal%2lu sfx%2lu poll%4lu\n",
         (now - t_start) / 1000000UL, (char)(sc >> 8), sc & 0xFFu,
         line[PF_IDLE].us * 100UL / wall, line[PF_KEY].n * 1000000UL / wall,
         line[PF_PTR].n, hmax_l[H_PLAG] / 1000UL, hmax_l[H_PGAP] / 1000UL,
         line[PF_PRES].n, hmax_l[H_PRES] / 1000UL, line[PF_BLIT].us / 1000UL,
         io, line[PF_READ].bytes / 1024UL, iou / 1000UL, line[PF_CARD].n, line[PF_CARD].us / 1000UL,
         line[PF_VIEW].n, line[PF_PAL].n,
         line[PF_SFX].n, line[PF_POLL].max / 1000UL);
    memset(line, 0, sizeof line);
    hmax_l[H_PLAG] = hmax_l[H_PGAP] = hmax_l[H_PRES] = hmax_l[H_KEY] = hmax_l[H_POLL] = 0;
    t_line = now;
    nline++;
}

static void ctr_out(Ctr __far *c, unsigned long wall)
{
    int s;

    putf("  %-9s %8s %10s %9s %9s %10s\n", "what", "calls", "ms", "avg ms", "max ms", "KB");
    for (s = 0; s < PF_N; s++)
        if (c[s].n)
            putf("  %-9s %8lu %8lu.%lu %7lu.%02lu %7lu.%lu %10lu\n", slot_name[s], c[s].n,
                 ms10(c[s].us) / 10, ms10(c[s].us) % 10,
                 c[s].us / c[s].n / 1000UL, c[s].us / c[s].n / 10UL % 100UL,
                 ms10(c[s].max) / 10, ms10(c[s].max) % 10, c[s].bytes / 1024UL);
    putf("  wall %lu ms, idle (vertical-blank sleeps) %lu %%, the engine's keyboard looks %lu/s\n",
         wall / 1000UL, wall >= 1000UL ? c[PF_IDLE].us / 1000UL * 100UL / (wall / 1000UL) : 0UL,
         wall ? c[PF_KEY].n * 1000000UL / wall : 0UL);
    putf("  /M's own clock readings so far: %lu, about %lu ms (%u.%u us each)\n", readings,
         readings * us_reading / 10000UL, us_reading / 10, us_reading % 10);
}

static void hist_out(unsigned long (*h)[NB], unsigned long *hmax)
{
    int k, b;

    putf("  gaps, ms:%-38s", "");
    for (b = 0; b < NB - 1; b++)
        putf(" <%-4u", bound[b]);
    putf(" >=1000   max   p95\n");
    for (k = 0; k < H_N; k++) {
        unsigned long n = 0, acc = 0;
        int p95 = 0;
        for (b = 0; b < NB; b++)
            n += h[k][b];
        if (!n)
            continue;
        for (b = 0; b < NB; b++) {
            acc += h[k][b];
            if (acc * 100UL >= n * 95UL) {
                p95 = b;
                break;
            }
        }
        putf("  %-46s", hist_name[k]);
        for (b = 0; b < NB; b++)
            putf(" %5lu", h[k][b]);
        putf(" %5lu %5s%u\n", hmax[k] / 1000UL, p95 < NB - 1 ? "<" : ">=",
             p95 < NB - 1 ? bound[p95] : 1000u);
    }
}

static void music_out(void)
{
    unsigned char r[16];

    if (!hz_snd_stats(0, r)) {
        put("  music task: no answer (not running?)\n");
        return;
    }
    putf("  music task: %u wake-ups, %u late (more than one tick due), at most %u ticks at once, longest gap %u ms, gaps > 30 ms %u, > 100 ms %u\n",
         r[1] | r[2] << 8, r[3] | r[4] << 8, r[5], r[6] | r[7] << 8, r[8] | r[9] << 8,
         r[10] | r[11] << 8);
}

unsigned perf_banks(void);              /* hz_plat.c: the banks this program holds */
extern int xc_nbanks_now(void);         /* plat/xdos.c: the packs' cache's banks */

static void period_out(unsigned long now, const char *what)
{
    putf("\n== %s: %lu-%lu s\n", what, (t_period - t_start) / 1000000UL, (now - t_start) / 1000000UL);
    ctr_out(period, now - t_period);
    hist_out(hp, hmax_p);
    music_out();
    putf("  memory: %u banks held (of them %u the packs' cache), %u free in the machine\n",
         perf_banks(), (unsigned)xc_nbanks_now(), hz_mem_info());
    put("\n");
    memset(period, 0, sizeof period);
    memset(hp, 0, sizeof hp);
    memset(hmax_p, 0, sizeof hmax_p);
    t_period = now;
    nperiod++;
}

static void timeline_head(void)
{
    put("    s sc pan idle keys/s ptr lag(max ms) gap(max) pres gap(max) blit(ms) io(calls/KB/ms) card(the card's own calls/ms) vw(view sends) pal sfx poll(max ms)\n");
}

static void report(unsigned long now, int final)
{
    unsigned long t0 = now_us();

    if (final) {
        int i;
        period_out(now, "last period");
        putf("\n== TOTAL: %lu s\n", (now - t_start) / 1000000UL);
        ctr_out(total, now - t_start);
        hist_out(ht, hmax_t);
        put("  files: name, opens, reads, KB, ms\n");
        for (i = 0; i < nf; i++)
            putf("    %-13s %5lu %6lu %7lu %7lu\n", ftab[i].name, ftab[i].opens, ftab[i].reads,
                 ftab[i].bytes / 1024UL, ftab[i].us / 1000UL);
        put("== end\n");
        pc_bad = 0;                     /* (the PC tried again) */
    } else {
        period_out(now, "period");
        timeline_head();
    }
    write_out(0);
    count(PF_REPORT, now_us() - t0, 0);
}

static void copy_to_pc(const char *name)
{
    static char __far buf[2048];
    char path[40];
    int a, b, k;

    a = open(name, O_RDONLY);
    if (a < 0)
        return;
    sprintf(path, "/PC:/%s", name);
    b = open(path, O_WRONLY | O_CREAT | O_TRUNC);
    if (b >= 0) {
        while ((k = (int)read(a, buf, sizeof buf)) > 0)
            if (write(b, buf, (unsigned)k) != k)
                break;
        close(b);
    }
    close(a);
}

static void at_exit(void)
{
    int i;
    unsigned long now = now_us();

    if (!started)
        return;
    started = 0;
    g_perf = 0;
    line_out(now);
    report(now, 1);
    for (i = 0; i < g_perf_ncopy; i++)
        copy_to_pc(g_perf_copy[i]);
}

/* one clock reading's cost */
static void measure_reading(void)
{
    int i;
    unsigned long a = hg_us(), b;

    for (i = 0; i < 99; i++)
        hg_us();
    b = hg_us();
    us_reading = (unsigned)((b - a) / 10UL);    /* 100 readings: tenths of a us each */
}

/* the start: the head, then the timeline */
void perf_start(void)
{
    unsigned long now = now_us();

    measure_reading();
    t_start = t_line = t_period = now;
    started = 1;
    putf("XCOM-XT on the Atari816: /M (horizon/hz_perf.c)\noptions: %s\nmachine on %lu s\n",
         g_perf_args, (unsigned long)hz_uptime() / 1000UL);
    put("a line every 5 s: sc = B the battle view / S a screen, then the pan (rows);\n"
        "idle = the CPU asleep in vertical-blank waits; keys/s = the engine's keyboard looks;\n"
        "ptr = arrow draws, lag = the longest pointer move -> arrow drawn, gap = the longest\n"
        "between arrow draws; pres = battle view presents; io = the engine's file calls/KB read/ms;\n"
        "card = the calls that reached the card (the packs are cached: plat/xdos.c)\n\n");
    timeline_head();
    write_out(1);
    hz_snd_stats(1, NULL);
    atexit(at_exit);                    /* (after hz_snd.c's: run before the music task quits) */
}

/* from plat_poll: the 5 s lines, the 30 s blocks, /Q */
void perf_tick(unsigned long now)
{
    if (!started)
        return;
    if (now - t_line >= 5000000UL) {
        line_out(now);
        if (now - t_period >= 30000000UL - 1000000UL)
            report(now, 0);
    }
    if (g_perf_quit && now - t_start >= (unsigned long)g_perf_quit * 1000000UL) {
        printf("xcom: /Q: %u s, the end\n", g_perf_quit);
        exit(0);
    }
}

/* ---------------------------------------------------------------- /IOB: the card's costs
   Each kind of file request timed alone (Horizon's calls, not the C library's), N times,
   to IOBENCH.TXT (and /PC:/IOBENCH.TXT), then the program ends: the figures the
   emulator's card model is checked against (emu/README.md "The card's speed"). Run in the
   program's folder (the packs: VGA/UIV.PAK, 4.8 MB). */
static void iob_line(const char *what, unsigned n, unsigned long us)
{
    putf("%-44s %4u x  avg %6lu.%02lu ms\n", what, n, us / n / 1000UL, us / n / 10UL % 100UL);
}

static unsigned long rnd_state = 12345;
static unsigned long rnd(void)
{
    rnd_state = rnd_state * 1103515245UL + 12345UL;
    return rnd_state >> 8;
}

void perf_iobench(void)
{
    static unsigned char __far buf[32768];
    static const unsigned sizes[] = { 16, 512, 2048, 4096, 8192, 16384, 32768 };
    hz_fileinfo st;
    hz_io io;
    unsigned long t, sz;
    int h, i, k;
    char line[80];

    measure_reading();
    putf("XCOM-XT /IOB: the card's request costs (Horizon calls, hg_us; one reading %u.%u us)\n",
         us_reading / 10, us_reading % 10);
#define TIME(what, n, body) do { t = hg_us(); for (i = 0; i < (n); i++) { body; } \
        iob_line(what, n, hg_us() - t); } while (0)
    TIME("stat VGA/UIV.PAK (in a folder of 82)", 20, hz_stat_path("VGA/UIV.PAK", &st));
    TIME("stat PACKS.VER (the app's folder)", 20, hz_stat_path("PACKS.VER", &st));
    TIME("stat VGA/MISSING.PAK (not there)", 20, hz_stat_path("VGA/MISSING.PAK", &st));
    TIME("stat /APPS/XCOM/VGA/UIV.PAK (absolute)", 20, hz_stat_path("/APPS/XCOM/VGA/UIV.PAK", &st));
    t = 0;
    for (i = 0; i < 20; i++) {
        unsigned long a = hg_us(), b;
        h = hz_open("VGA/UIV.PAK", HZ_O_READ);
        b = hg_us();
        t += b - a;
        if (h >= 0)
            hz_close((unsigned)h);
    }
    iob_line("open VGA/UIV.PAK (read)", 20, t);
    t = 0;
    for (i = 0; i < 20; i++) {
        unsigned long a;
        h = hz_open("PACKS.VER", HZ_O_READ);
        a = hg_us();
        if (h >= 0)
            hz_close((unsigned)h);
        t += hg_us() - a;
    }
    iob_line("close (a file opened to read)", 20, t);
    TIME("open PACKS.VER + close", 20, if ((h = hz_open("PACKS.VER", HZ_O_READ)) >= 0) hz_close((unsigned)h));
    TIME("C library open() + close() VGA/UIV.PAK", 20, if ((k = open("VGA/UIV.PAK", O_RDONLY)) >= 0) close(k));
    h = hz_open("VGA/UIV.PAK", HZ_O_READ);
    if (h < 0) {
        put("cannot open VGA/UIV.PAK\n");
        return;
    }
    sz = 4000000UL;
    TIME("seek to a random place", 40, hz_seek((unsigned)h, rnd() % sz));
    TIME("seek to the same place", 40, hz_seek((unsigned)h, 1000UL));
    io.handle = (unsigned char)h;
    HZ_U24(io.buf, buf);
    for (k = 0; k < (int)(sizeof sizes / sizeof sizes[0]); k++) {
        unsigned n = sizes[k] >= 16384 ? 8 : 20;
        unsigned long tr = 0;
        io.len = (unsigned short)sizes[k];
        for (i = 0; i < (int)n; i++) {
            unsigned long a;
            hz_seek((unsigned)h, (rnd() % sz) & ~511UL);
            a = hg_us();
            hz_read(&io);
            tr += hg_us() - a;
        }
        sprintf(line, "read %u bytes at a random place (after a seek)", sizes[k]);
        iob_line(line, n, tr);
        hz_seek((unsigned)h, 0);
        t = hg_us();
        for (i = 0; i < (int)n; i++)
            hz_read(&io);
        sprintf(line, "read %u bytes, the next ones", sizes[k]);
        iob_line(line, n, hg_us() - t);
    }
    hz_close((unsigned)h);
    TIME("create IOB.TMP + write 64 + close", 10, if ((h = hz_open("IOB.TMP", HZ_O_CREATE)) >= 0) {
             io.handle = (unsigned char)h; io.len = 64; hz_write(&io); hz_close((unsigned)h); });
    TIME("append IOB.TMP + write 64 + close (a LOG line)", 10, if ((h = hz_open("IOB.TMP", HZ_O_APPEND)) >= 0) {
             io.handle = (unsigned char)h; io.len = 64; hz_write(&io); hz_close((unsigned)h); });
    hz_delete("IOB.TMP");
#undef TIME
    strcpy(g_perf_name, "IOBENCH");
    write_out(1);
}
