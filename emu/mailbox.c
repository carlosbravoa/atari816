/* I/O processor mailbox — mirrors a816_mailbox() in core/firmware/firmware.c, with a host
 * directory standing in for the FAT32 SD card.
 *
 * Result codes (response ARG0): 0 OK, 1..19 FatFs FRESULT, $80 bad handle, $81 bad address,
 * $82 unsupported op, $87 no PC link, $88 PC link lost, $89 not the same volume. Host errno
 * values are mapped to the FRESULT FatFs would return.
 *
 * The PC volume (PC link step 1): paths starting "/PC:" (then the end or '/') are served
 * from the --pc-folder directory, as the firmware serves them from the PC gateway's shared
 * folder. Without --pc-folder (or after --pc-drop-at) the volume is absent: $87.
 * The I/O processor polls every MB_POLL CPU cycles and serves one request at a time; with
 * --card-kbps / --pc-kbps a request's answer comes after its transfer time, and key and mouse
 * events keep coming meanwhile (the firmware of Horizon 0.21). A PC file opened with mode 2 is
 * written under a temporary name and moved onto its name at CLOSE (the gateway's rule).
 *
 * The internet (PC link step 2, net.c): URL paths and the stream handles 4-7 are served there.
 * The link counts as up while any PC service is given (--pc-folder, --net, --net-root).
 */

#include "machine.h"
#include "net.h"
#include <dirent.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#include <fcntl.h>

enum { FR_OK, FR_DISK_ERR, FR_INT_ERR, FR_NOT_READY, FR_NO_FILE, FR_NO_PATH, FR_INVALID_NAME,
       FR_DENIED, FR_EXIST, FR_INVALID_OBJECT, FR_WRITE_PROTECTED, FR_INVALID_DRIVE,
       FR_NOT_ENABLED, FR_NO_FILESYSTEM, FR_MKFS_ABORTED, FR_TIMEOUT, FR_LOCKED,
       FR_NOT_ENOUGH_CORE, FR_TOO_MANY_OPEN_FILES, FR_INVALID_PARAMETER };
enum { MB_BAD_HANDLE = 0x80, MB_BAD_ADDR = 0x81, MB_UNSUPPORTED = 0x82,
       MB_NO_PC = 0x87, MB_PC_LOST = 0x88, MB_NOT_SAME = 0x89 };

#define MAXPATH 128                 /* the firmware's path buffer */

/* ── The firmware's clock for file dates (SYS_TIME, $1D) ──────────────────────────────────
 * Horizon gives the time (seconds since 2000-01-01 00:00, local); the I/O processor counts on
 * from it and FatFs stamps files with it (get_fattime). Here the count is emulated time, and
 * a file the 65C816 created or wrote gets that time as its host modification time when it
 * is closed (FatFs writes the date at f_close / f_sync), so runs are deterministic. Before
 * the time is given: EMU_BUILD_DATE (the firmware uses its build date). It survives restarts
 * of the 65C816, as the I/O processor's does. */
#define EMU_BUILD_DATE 820540800u           /* 2026-01-01 00:00, in seconds since 2000-01-01 */
static int host_path(const char *fat, char *out, size_t n);
static int host_path_in(const char *root, const char *fat, char *out, size_t n, int pc);
static int      clk_set;
static uint32_t clk_base;
static uint64_t clk_cyc;
/* the cartridge (CLASSIC_STATE, $1E): survives restarts of the 65C816 as the firmware's does */
static char     cart_path[MAXPATH];
static uint32_t cart_size;
const char     *mailbox_boot_cart;          /* --boot-cart: loaded "by the firmware" at power-on */

static time_t fw_now(void)
{
    uint32_t s = clk_set ? clk_base + (uint32_t)((M.cpu.cycles - clk_cyc) / CPU_HZ) : EMU_BUILD_DATE;
    struct tm tm = { .tm_year = 100, .tm_mon = 0, .tm_mday = 1, .tm_isdst = -1 };
    time_t t0 = mktime(&tm);               /* 2000-01-01 00:00 local */
    tm = (struct tm){ 0 };
    localtime_r(&t0, &tm);
    tm.tm_sec += s;                        /* normalised by mktime, local time */
    tm.tm_isdst = -1;
    return mktime(&tm);
}

/* ── The PC volume: --pc-folder, the PC's clock (--pc-time), the link's drops ──
 * The link is up from power-on until --pc-drop-at, and again from --pc-back-at (a new
 * session: handles opened before the drop stay dead). */
const char *mailbox_pc_root;
time_t      mailbox_pc_time;
double      mailbox_pc_drop = -1, mailbox_pc_back = -1;

static double emu_sec(void) { return (double)M.cpu.cycles / CPU_HZ; }

/* the link: up while a gateway with some service is there (--pc-folder, --net, --net-root) */
static int link_up(void)
{
    if (!mailbox_pc_root && !mailbox_net && !mailbox_net_root) return 0;
    double t = emu_sec();
    if (mailbox_pc_drop < 0 || t < mailbox_pc_drop) return 1;
    return mailbox_pc_back > mailbox_pc_drop && t >= mailbox_pc_back;
}

/* the files service (the PC volume) */
static int pc_up(void) { return mailbox_pc_root && link_up(); }

static uint8_t pc_session(void)
{
    return mailbox_pc_drop >= 0 && mailbox_pc_back > mailbox_pc_drop && emu_sec() >= mailbox_pc_back ? 2 : 1;
}

/* the PC's local time: --pc-time counting on with emulated time, else the host's clock */
static time_t pc_now(void)
{
    return mailbox_pc_time ? mailbox_pc_time + (time_t)emu_sec() : time(NULL);
}

/* "/PC:" (any case), then the end or '/': a path on the PC volume */
static int is_pc(const char *p)
{
    return !strncasecmp(p, "/PC:", 4) && (!p[4] || p[4] == '/');
}

/* the part after "/PC:" names its root ("" or only '/') */
static int pc_is_root(const char *p)
{
    p += 4;
    while (*p == '/') p++;
    return !*p;
}

/* --card-date: the date STAT reports for every file not created or written in this run (the
 * test cards are fresh copies, so their host dates say nothing); the files this run stamped */
time_t        mailbox_card_date;
static char **stamped;
static time_t *stamped_t;                   /* the date each one got (a folder's host date
                                             * changes when something is put in it) */
static int    nstamped;

static int stamped_at(const char *host)
{
    for (int i = 0; i < nstamped; i++) if (!strcmp(stamped[i], host)) return i;
    return -1;
}
static int was_stamped(const char *host) { return stamped_at(host) >= 0; }

/* STAT's date: --card-date for what the run did not write, else the date it gave */
static time_t stat_date(const char *host, time_t mtime)
{
    if (!mailbox_card_date) return mtime;
    int i = stamped_at(host);
    return i < 0 ? mailbox_card_date : stamped_t[i];
}

static void stamp_at(const char *host, time_t when)
{
    if (mailbox_card_date) {
        int i = stamped_at(host);
        if (i >= 0) stamped_t[i] = when;
        else if (nstamped < 4096) {
            char **n = realloc(stamped, (nstamped + 1) * sizeof *n);
            time_t *nt = realloc(stamped_t, (nstamped + 1) * sizeof *nt);
            if (n) stamped = n;
            if (nt) stamped_t = nt;
            if (n && nt) { stamped_t[nstamped] = when; stamped[nstamped++] = strdup(host); }
        }
    }
    struct timespec ts[2];
    ts[0].tv_sec = ts[1].tv_sec = when;
    ts[0].tv_nsec = ts[1].tv_nsec = 0;
    utimensat(AT_FDCWD, host, ts, 0);
}

/* a card file gets the firmware's clock (FatFs), a PC file the PC's (the gateway writes it) */
static void stamp(const char *host, int pc) { stamp_at(host, pc ? pc_now() : fw_now()); }

static int pc_dead(Mailbox *m, int h);

/* commit = 1 (CLOSE, SYS_SYNC): a PC file opened with mode 2 is moved from its temporary
 * name onto its own (the gateway's rule); 0 (the 65C816 reset or restarted: the session
 * ends): the temporary file is deleted and an older file of that name stays as it was */
static void close_file(Mailbox *m, int i, int commit)
{
    if (!m->f[i]) return;
    int bad = fclose(m->f[i]), gone = 0;
    m->f[i] = NULL;
    if (m->ftmp[i]) {
        if (commit && !pc_dead(m, i) && m->fhost[i] && !rename(m->ftmp[i], m->fhost[i])) ;
        else { unlink(m->ftmp[i]); gone = 1; }
        free(m->ftmp[i]);
        m->ftmp[i] = NULL;
    }
    if (m->fdirty[i] && m->fhost[i] && !gone) stamp(m->fhost[i], m->fpc[i]);
    free(m->fhost[i]);
    m->fhost[i] = NULL;
    m->fdirty[i] = 0;
    m->fpc[i] = 0;
    (void)bad;
}

static void close_all(Mailbox *m, int commit)
{
    for (int i = 0; i < MB_FILES; i++) close_file(m, i, commit);
}

/* the link dropped: the temporary files of the PC files still open (mode 2) are deleted at
 * once (the session ended); their handles stay taken until CLOSE, which frees them */
static void pc_drop_tmp(Mailbox *m)
{
    for (int i = 0; i < MB_FILES; i++)
        if (m->f[i] && m->ftmp[i] && pc_dead(m, i)) {
            unlink(m->ftmp[i]);
            free(m->ftmp[i]);
            m->ftmp[i] = NULL;
            m->fdirty[i] = 0;
        }
}

void mailbox_reset(void)
{
    Mailbox *m = &M.mb;
    const char *root = m->root;
    int restart = m->restart;
    uint8_t now[4], nm = m->kb_now_mods;               /* keys held on the host survive */
    uint8_t btn = m->ms_btn;
    memcpy(now, m->kb_now, 4);
    close_all(m, 0);
    net_close_all(0);
    memset(m, 0, sizeof *m);
    m->root = root;
    m->restart = restart;
    memcpy(m->kb_now, now, 4);
    m->kb_now_mods = nm;
    m->ms_btn = btn;
    m->ms_n = 1;                                       /* one run: no motion, these buttons */
    m->ms_seg[0].btn = btn;
    m->next_poll = M.cpu.cycles + MB_POLL;
    /* power-on, or a full restart: the firmware loads the boot cartridge (boot=ash) */
    if (!M.cpu.cycles || restart == 2) {
        cart_size = 0; cart_path[0] = 0;
        char host[4096];
        struct stat st;
        if (mailbox_boot_cart && root && !host_path(mailbox_boot_cart, host, sizeof host) && !stat(host, &st)) {
            snprintf(cart_path, sizeof cart_path, "%s", mailbox_boot_cart);
            cart_size = (uint32_t)st.st_size;
            const char *e = strrchr(cart_path, '.');
            if (e && !strcasecmp(e, ".CAR") && cart_size >= 16) cart_size -= 16;
        }
    }
}

int mailbox_pending(void) { return M.mb.rsp_head != M.mb.rsp_tail; }

/* ── 65C816 memory as the I/O processor sees it (firmware mb_ptr) ──
 * Native addresses >= $80:0000 and the whole of bank $10 are out of its reach. */
static int addr_ok(uint32_t n) { return n < RAM_SIZE && (n >> 16) != 0x10; }

static int mb_get(uint32_t n, uint8_t *dst, uint32_t len)
{
    for (uint32_t i = 0; i < len; i++) { if (!addr_ok(n + i)) return 0; dst[i] = M.ram[n + i]; }
    return 1;
}
static int mb_put(uint32_t n, const uint8_t *src, uint32_t len)
{
    for (uint32_t i = 0; i < len; i++) { if (!addr_ok(n + i)) return 0; M.ram[n + i] = src[i]; }
    return 1;
}
static int mb_path(uint32_t n, char *dst, int max)
{
    for (int i = 0; i < max; i++) {
        if (!mb_get(n + i, (uint8_t *)dst + i, 1)) return 0;
        if (!dst[i]) return 1;
    }
    return 0;
}

/* ── FAT path -> host path, confined to the --sd directory ── */
static int errno_fr(int e, const char *host)
{
    switch (e) {
    case ENOENT: {
        /* FR_NO_FILE if the directory exists, FR_NO_PATH if a directory on the way is missing */
        char tmp[4096];
        snprintf(tmp, sizeof tmp, "%s", host);
        char *sl = strrchr(tmp, '/');
        struct stat st;
        if (sl) { *sl = 0; if (stat(tmp, &st) || !S_ISDIR(st.st_mode)) return FR_NO_PATH; }
        return FR_NO_FILE;
    }
    case ENOTDIR: return FR_NO_PATH;
    case EEXIST: return FR_EXIST;
    case EACCES: case EPERM: case EISDIR: case ENOTEMPTY: case EBUSY: return FR_DENIED;
    case EROFS: return FR_WRITE_PROTECTED;
    case ENAMETOOLONG: case EINVAL: return FR_INVALID_NAME;
    case EMFILE: case ENFILE: return FR_TOO_MANY_OPEN_FILES;
    }
    return FR_DISK_ERR;
}

/* Resolve each component case-insensitively (FAT is case-insensitive). Returns 0 or an
 * FRESULT. The last component may not exist yet. */
static int host_path(const char *fat, char *out, size_t n)
{
    if (fat[0] == '0' && fat[1] == ':') fat += 2;          /* drive prefix */
    return host_path_in(M.mb.root, fat, out, n, 0);
}

/* the same in any root; pc = 1: the PC volume, where ".." is "denied" (it would leave the
 * shared folder) as the gateway answers */
static int host_path_in(const char *root, const char *fat, char *out, size_t n, int pc)
{
    if (!root) return FR_NOT_READY;
    size_t len = snprintf(out, n, "%s", root);
    const char *p = fat;
    while (*p) {
        while (*p == '/' || *p == '\\') p++;
        if (!*p) break;
        const char *e = p;
        while (*e && *e != '/' && *e != '\\') e++;
        size_t cl = e - p;
        if (cl == 1 && p[0] == '.') { p = e; continue; }
        if (cl == 2 && p[0] == '.' && p[1] == '.') return pc ? FR_DENIED : FR_INVALID_NAME;   /* no escaping */
        if (cl > 255) return FR_INVALID_NAME;
        char comp[256];
        memcpy(comp, p, cl);
        comp[cl] = 0;
        if (strpbrk(comp, ":*?\"<>|")) return FR_INVALID_NAME;
        /* exact name, else a case-insensitive match in the directory */
        char cand[4096];
        struct stat st;
        snprintf(cand, sizeof cand, "%s/%s", out, comp);
        if (lstat(cand, &st)) {
            DIR *d = opendir(out);
            if (d) {
                struct dirent *de;
                while ((de = readdir(d))) if (!strcasecmp(de->d_name, comp)) { snprintf(comp, sizeof comp, "%s", de->d_name); break; }
                closedir(d);
            }
        }
        len += snprintf(out + len, len < n ? n - len : 0, "/%s", comp);
        if (len >= n) return FR_INVALID_NAME;
        p = e;
    }
    /* existing objects must resolve inside the root (no symlink escapes); a new name must
     * be in a folder inside it */
    char real[4096], rroot[4096];
    if (!realpath(root, rroot)) return FR_DISK_ERR;
    if (!realpath(out, real)) {
        struct stat ls;
        if (!lstat(out, &ls)) return FR_DENIED;          /* a dangling symlink */
        char par[4096];
        snprintf(par, sizeof par, "%s", out);
        char *sl = strrchr(par, '/');
        if (sl && sl > par) *sl = 0;
        if (!realpath(par, real)) return FR_OK;          /* the folder is missing: FR_NO_PATH later */
    }
    size_t rl = strlen(rroot);
    if (strncmp(real, rroot, rl) || (real[rl] && real[rl] != '/')) return FR_DENIED;
    return FR_OK;
}

/* any FAT path: the card, or (/PC:) the PC volume. *pc = 1 for the PC; $87 if it is absent */
static int resolve(const char *fat, char *out, size_t n, int *pc)
{
    *pc = is_pc(fat);
    if (!*pc) return host_path(fat, out, n);
    if (!pc_up()) return MB_NO_PC;
    return host_path_in(mailbox_pc_root, fat + 4, out, n, 1);
}

/* a handle of the PC volume whose link session has ended */
static int pc_dead(Mailbox *m, int h)
{
    return m->fpc[h] && (!pc_up() || m->fsess[h] != pc_session());
}

static uint32_t fat_time(time_t t)
{
    struct tm tm;
    localtime_r(&t, &tm);
    if (tm.tm_year < 80) return 0x00210000;              /* 1980-01-01 */
    uint32_t d = (tm.tm_year - 80) << 9 | (tm.tm_mon + 1) << 5 | tm.tm_mday;
    uint32_t tt = tm.tm_hour << 11 | tm.tm_min << 5 | tm.tm_sec / 2;
    return d << 16 | tt;
}

static uint8_t fat_attr(const char *host, const struct stat *st)
{
    if (S_ISDIR(st->st_mode)) return 0x10;
    return 0x20 | (access(host, W_OK) ? 0x01 : 0);
}

/* file <-> 65C816 memory (firmware mb_xfer); wr = 0: file -> memory */
static uint32_t xfer(FILE *f, uint32_t n, uint32_t len, int wr, uint32_t *res)
{
    uint32_t done = 0;
    *res = 0;
    while (len) {
        if (!addr_ok(n)) { *res = MB_BAD_ADDR; break; }
        uint32_t room = 0x100000 - (n & 0xFFFFF);        /* contiguous up to a 1 MB boundary */
        if (n + room > RAM_SIZE) room = RAM_SIZE - n;
        if (room > len) room = len;
        if (room > 0x8000) room = 0x8000;
        size_t got = wr ? fwrite(M.ram + n, 1, room, f) : fread(M.ram + n, 1, room, f);
        if (got < room && ferror(f)) *res = FR_DISK_ERR;
        done += got; n += got; len -= got;
        if (*res || got < room) break;
    }
    return done;
}

static int cmpstr(const void *a, const void *b) { return strcmp(*(char *const *)a, *(char *const *)b); }

static void serve(Mailbox *m, uint8_t *msg)
{
    static char path[MAXPATH], host[4096];
    uint32_t res = 0, val = 0;
    uint32_t len  = msg[2] | msg[3] << 8;
    uint32_t buf  = msg[4] | msg[5] << 8 | msg[6] << 16;
    uint32_t arg0 = msg[8] | msg[9] << 8 | msg[10] << 16 | (uint32_t)msg[11] << 24;
    uint32_t arg1 = msg[12] | msg[13] << 8 | msg[14] << 16 | (uint32_t)msg[15] << 24;
    FILE *f = (arg0 < MB_FILES) ? m->f[arg0] : NULL;
    struct stat st;
    int pc = 0;

    m->n_req++;
    switch (msg[0]) {
    case 0x01: {                                         /* OPEN */
        static const char *const mode[4] = { "rb", "r+b", "w+b", "ab" };
        static const uint8_t rw[4] = { 1, 3, 3, 2 };
        int h = 0, fl = msg[7] & 3;
        while (h < MB_FILES && m->f[h]) h++;
        if (h == MB_FILES) { res = FR_TOO_MANY_OPEN_FILES; break; }
        if (!mb_path(buf, path, sizeof path)) { res = MB_BAD_ADDR; break; }
        if ((res = resolve(path, host, sizeof host, &pc))) break;
        if (!stat(host, &st) && S_ISDIR(st.st_mode)) { res = fl >= 2 ? FR_EXIST : FR_NO_FILE; break; }
        FILE *nf;
        char *tmp = NULL;
        if (pc && fl == 2) {
            /* the gateway's "unfinished files": written under a temporary name in the hidden
             * folder .atari816-partial, moved onto the name at CLOSE; until then an older file
             * of that name stays as it was */
            static unsigned seq;
            char par[4096], tp[4200];
            snprintf(par, sizeof par, "%s", host);
            char *sl = strrchr(par, '/');
            if (sl) *sl = 0;
            if (stat(par, &st) || !S_ISDIR(st.st_mode)) { res = errno_fr(ENOENT, host); break; }
            if (!stat(host, &st) && access(host, W_OK)) { res = FR_DENIED; break; }
            snprintf(tp, sizeof tp, "%s/.atari816-partial", mailbox_pc_root);
            mkdir(tp, 0777);
            snprintf(tp, sizeof tp, "%s/.atari816-partial/%u-%u", mailbox_pc_root, (unsigned)getpid(), ++seq);
            nf = fopen(tp, "w+b");
            if (!nf) { res = errno_fr(errno, host); break; }
            tmp = strdup(tp);
        } else {
            nf = fopen(host, mode[fl]);
            if (!nf) { res = errno_fr(errno, host); break; }
        }
        m->f[h] = nf; m->fmode[h] = rw[fl]; val = h;
        m->ftmp[h] = tmp;
        m->fpc[h] = pc; m->fsess[h] = pc_session();
        m->fhost[h] = strdup(host);
        m->fdirty[h] = fl >= 2;                          /* created (or appended): dated at close */
        break;
    }
    case 0x02:                                           /* CLOSE */
        if (!f) { res = MB_BAD_HANDLE; break; }
        if (ferror(f) && !pc_dead(m, arg0)) res = FR_DISK_ERR;
        close_file(m, arg0, 1);                          /* (a dead PC handle: freed, OK) */
        break;
    case 0x03: case 0x04:                                /* READ, WRITE */
        if (!f) { res = MB_BAD_HANDLE; break; }
        if (pc_dead(m, arg0)) { res = MB_PC_LOST; break; }
        if (!(m->fmode[arg0] & (msg[0] == 0x04 ? 2 : 1))) { res = FR_DENIED; break; }
        fseek(f, 0, SEEK_CUR);                           /* allow switching read/write */
        val = xfer(f, buf, len, msg[0] == 0x04, &res);
        if (msg[0] == 0x04 && val) m->fdirty[arg0] = 1;
        break;
    case 0x05:                                           /* SEEK */
        if (!f) { res = MB_BAD_HANDLE; break; }
        if (pc_dead(m, arg0)) { res = MB_PC_LOST; break; }
        if (!(m->fmode[arg0] & 2)) {                     /* read-only: FatFs clips to the size */
            fseek(f, 0, SEEK_END);
            long sz = ftell(f);
            if ((long)arg1 > sz) arg1 = sz;
        }
        if (fseek(f, arg1, SEEK_SET)) res = FR_INT_ERR;
        val = ftell(f);
        break;
    case 0x06: {                                         /* STAT */
        uint8_t o[9];
        if (!mb_path(buf, path, sizeof path)) { res = MB_BAD_ADDR; break; }
        if ((res = resolve(path, host, sizeof host, &pc))) break;
        const char *q = path; while (*q == '/') q++;
        if (!*q) { res = FR_INVALID_NAME; break; }       /* FatFs cannot stat the root */
        uint32_t sz, t;
        uint8_t attr;
        if (pc && pc_is_root(path)) {                    /* the PC volume's root: the PC's clock */
            sz = 0; attr = 0x10; t = fat_time(pc_now());
        } else {
            if (stat(host, &st)) { res = errno_fr(errno, host); break; }
            sz = S_ISDIR(st.st_mode) ? 0 : (uint32_t)st.st_size;
            t = fat_time(stat_date(host, st.st_mtime));
            attr = fat_attr(host, &st);
        }
        o[0] = sz; o[1] = sz >> 8; o[2] = sz >> 16; o[3] = sz >> 24;
        o[4] = attr;
        o[5] = t; o[6] = t >> 8; o[7] = t >> 16; o[8] = t >> 24;
        if (!mb_put(buf, o, 9)) res = MB_BAD_ADDR;
        val = sz;
        break;
    }
    case 0x07: {                                         /* READDIR */
        if (!mb_path(buf, path, sizeof path)) { res = MB_BAD_ADDR; break; }
        if ((res = resolve(path, host, sizeof host, &pc))) break;
        int card_root = !strcmp(path, "/") && pc_up();   /* the card's root: "PC:" at the end */
        DIR *d = opendir(host);
        if (!d) { res = errno == ENOTDIR ? FR_NO_PATH : errno_fr(errno, host); break; }
        char **names = NULL;
        size_t nn = 0, cap = 0;
        struct dirent *de;
        while ((de = readdir(d))) {
            if (!strcmp(de->d_name, ".") || !strcmp(de->d_name, "..")) continue;
            if (strlen(de->d_name) > 255) continue;
            if (pc && de->d_name[0] == '.') continue;    /* the gateway hides dot files */
            if (nn == cap) names = realloc(names, (cap = cap ? 2 * cap : 64) * sizeof *names);
            names[nn++] = strdup(de->d_name);
        }
        closedir(d);
        qsort(names, nn, sizeof *names, cmpstr);         /* deterministic order */
        uint32_t off = 0;
        int full = 0;
        for (size_t i = 0; i < nn; i++) {
            if (arg0) { arg0--; continue; }
            char hp[4400];
            snprintf(hp, sizeof hp, "%s/%s", host, names[i]);
            if (stat(hp, &st)) continue;
            if (pc) {                                    /* a symlink out of the folder: not shown */
                char real[4096], rroot[4096];
                if (!realpath(hp, real) || !realpath(mailbox_pc_root, rroot)) continue;
                size_t rl = strlen(rroot);
                if (strncmp(real, rroot, rl) || (real[rl] && real[rl] != '/')) continue;
            }
            uint32_t nl = strlen(names[i]), sz = S_ISDIR(st.st_mode) ? 0 : (uint32_t)st.st_size;
            uint8_t h[6] = { sz, sz >> 8, sz >> 16, sz >> 24, fat_attr(hp, &st), nl };
            if (off + 6 + nl > len) { full = 1; break; }
            if (!mb_put(buf + off, h, 6) || !mb_put(buf + off + 6, (uint8_t *)names[i], nl)) { res = MB_BAD_ADDR; break; }
            off += 6 + nl;
            val++;
        }
        if (card_root && !res && !full && !arg0 && off + 9 <= len) {    /* the skip counts it too */
            static const uint8_t e[9] = { 0, 0, 0, 0, 0x10, 3, 'P', 'C', ':' };
            if (mb_put(buf + off, e, 9)) { off += 9; val++; } else res = MB_BAD_ADDR;
        }
        for (size_t i = 0; i < nn; i++) free(names[i]);
        free(names);
        break;
    }
    case 0x08: case 0x09:                                /* MKDIR, DELETE */
        if (!mb_path(buf, path, sizeof path)) { res = MB_BAD_ADDR; break; }
        if ((res = resolve(path, host, sizeof host, &pc))) break;
        if (pc && pc_is_root(path)) { res = msg[0] == 0x08 ? FR_EXIST : FR_DENIED; break; }
        if (msg[0] == 0x08) { if (mkdir(host, 0777)) res = errno_fr(errno, host); else stamp(host, pc); }
        else if (!lstat(host, &st) && S_ISDIR(st.st_mode)) { if (rmdir(host)) res = errno_fr(errno, host); }
        else if (unlink(host)) res = errno_fr(errno, host);
        break;
    case 0x0A: {                                         /* RENAME "old\0new" */
        static char to[MAXPATH], hto[4096];
        if (!mb_path(buf, path, sizeof path) || !mb_path(buf + strlen(path) + 1, to, sizeof to)) { res = MB_BAD_ADDR; break; }
        int pc2 = 0;
        int r1 = resolve(path, host, sizeof host, &pc), r2 = resolve(to, hto, sizeof hto, &pc2);
        if (r1 == MB_NO_PC || r2 == MB_NO_PC) { res = MB_NO_PC; break; }
        if (pc != pc2) { res = MB_NOT_SAME; break; }     /* the card and the PC volume */
        if ((res = r1) || (res = r2)) break;
        if (pc && (pc_is_root(path) || pc_is_root(to))) { res = FR_DENIED; break; }
        if (lstat(host, &st)) { res = errno_fr(errno, host); break; }
        if (!lstat(hto, &st)) { res = FR_EXIST; break; }
        if (rename(host, hto)) res = errno_fr(errno, hto);
        else if (mailbox_card_date && was_stamped(host))     /* FatFs keeps the date */
            stamp_at(hto, stamped_t[stamped_at(host)]);
        break;
    }
    case 0x10: {                                         /* LOAD whole file to ARG0 */
        if (!mb_path(buf, path, sizeof path)) { res = MB_BAD_ADDR; break; }
        if ((res = resolve(path, host, sizeof host, &pc))) break;
        if (!stat(host, &st) && S_ISDIR(st.st_mode)) { res = FR_NO_FILE; break; }
        FILE *lf = fopen(host, "rb");
        if (!lf) { res = errno_fr(errno, host); break; }
        fseek(lf, 0, SEEK_END);
        long sz = ftell(lf);
        fseek(lf, 0, SEEK_SET);
        val = xfer(lf, arg0 & 0xFFFFFF, (uint32_t)sz, 0, &res);
        fclose(lf);
        break;
    }
    case 0x18: case 0x19: case 0x1A: {                   /* CLASSIC_MOUNT / EJECT / BOOT */
        /* Stub of the firmware ops (there is no classic machine here): the same argument
         * checks and result codes, any existing file with a known extension mounts, BOOT
         * always succeeds. One line per op on stderr. */
        static const char *opn[3] = { "CLASSIC_MOUNT", "CLASSIC_EJECT", "CLASSIC_BOOT" };
        int kind = msg[7], s = kind == 1 ? (int)arg0 : 0;
        path[0] = 0;
        if (msg[0] == 0x1A) {
            val = m->cl_xex ? 2 : 0;
        } else {
            if (msg[0] == 0x18) {
                if (!mb_path(buf, path, sizeof path)) { res = MB_BAD_ADDR; goto cl_log; }
                if (is_pc(path)) { res = pc_up() ? MB_UNSUPPORTED : MB_NO_PC; goto cl_log; }   /* (not in step 1) */
                const char *e = strrchr(path, '.');
                if (!kind && e && strlen(e) == 4)
                    for (int i = 0; i < 8; i++) {
                        int j = 0;
                        while (j < 3 && (e[1 + j] & 0xDF) == "ATRXFDXEXCOMEXECARROMBIN"[i * 3 + j]) j++;
                        if (j == 3) { kind = i < 2 ? 1 : i < 5 ? 2 : 3; break; }
                    }
            }
            if (kind < 1 || kind > 3 || s >= 4) { res = 0x83; goto cl_log; }
            if (msg[0] == 0x19) {                        /* EJECT */
                if (kind == 3) { m->cl_cart = 0; cart_size = 0; cart_path[0] = 0; }
                else {
                    if (!s) m->cl_xex = 0;
                    if (kind == 1) m->cl_disk[s] = 0;
                }
                goto cl_log;
            }
            if ((res = host_path(path, host, sizeof host))) goto cl_log;
            if (stat(host, &st)) { res = errno_fr(errno, host); goto cl_log; }
            if (S_ISDIR(st.st_mode)) { res = FR_NO_FILE; goto cl_log; }
            if (kind == 1) { m->cl_disk[s] = 1; if (!s) m->cl_xex = 0; }
            else if (kind == 2) { m->cl_xex = 1; m->cl_disk[0] = 0; }
            else {
                m->cl_cart = 1;
                snprintf(cart_path, sizeof cart_path, "%s", path);
                cart_size = (uint32_t)st.st_size;          /* (.CAR: the firmware leaves out its 16-byte header) */
                const char *e = strrchr(path, '.');
                if (e && !strcasecmp(e, ".CAR") && cart_size >= 16) cart_size -= 16;
            }
            val = kind;
        }
    cl_log:
        fprintf(stderr, "emu816: %s kind %d slot %d %s -> %02X\n", opn[msg[0] - 0x18],
                kind, s, path[0] ? path : "-", (unsigned)res);
        break;
    }
    case 0x1B:                                           /* SYS_RESTART (stub) */
        /* ARG0 0: reload and restart Horizon; 1: full restart (the firmware re-reads
         * /atari.ini and cold boots the classic core first: nothing to do here). Answered
         * OK; main.c then restarts the 65C816 with HORIZON.SYS read again from the card. */
        if (arg0 > 1) { res = 0x83; }
        else { close_all(m, 0); net_close_all(0); m->restart = 1 + (int)arg0; }
        fprintf(stderr, "emu816: SYS_RESTART %u -> %02X\n", (unsigned)arg0, (unsigned)res);
        break;
    case 0x1C:                                           /* SYS_SYNC (stub) */
        /* the firmware flushes and closes everything on the card and closes the PC volume's
         * files: here, close the files */
        close_all(m, 1);
        net_close_all(1);                                /* every stream too */
        fprintf(stderr, "emu816: SYS_SYNC -> 00\n");
        break;
    case 0x1D:                                           /* SYS_TIME: the clock for file dates */
        clk_set = 1;
        clk_base = arg0;
        clk_cyc = M.cpu.cycles;
        break;
    case 0x1E:                                           /* CLASSIC_STATE: ARG0 5 = the cartridge */
        if (arg0 != 5) { res = 0x83; break; }
        if (!cart_size) break;
        val = cart_size;
        if (len) {
            uint32_t n = (uint32_t)strlen(cart_path);
            if (n > len - 1) n = len - 1;
            if (!mb_put(buf, (const uint8_t *)cart_path, n) || !mb_put(buf + n, (const uint8_t *)"", 1)) res = MB_BAD_ADDR;
        }
        break;
    default:                                             /* MOUNT, UNMOUNT, TIME, ... */
        res = MB_UNSUPPORTED;
    }

    msg[0] |= 0x80;
    msg[8] = res; msg[9] = res >> 8; msg[10] = res >> 16; msg[11] = res >> 24;
    msg[12] = val; msg[13] = val >> 8; msg[14] = val >> 16; msg[15] = val >> 24;
}

/* ── Keyboard and mouse events (the firmware of 0.21: they keep coming while a request is in
 * progress) ── */
void mailbox_key(uint8_t usage, int down)
{
    Mailbox *m = &M.mb;
    int changed = 0;
    if (usage >= 0xE0 && usage <= 0xE7) {
        uint8_t b = 1 << (usage - 0xE0), nm = down ? (m->kb_now_mods | b) : (m->kb_now_mods & ~b);
        changed = nm != m->kb_now_mods;
        m->kb_now_mods = nm;
    } else {
        int i, held = -1, free = -1;
        for (i = 0; i < 4; i++) { if (m->kb_now[i] == usage) held = i; if (!m->kb_now[i] && free < 0) free = i; }
        if (!down && held >= 0) { m->kb_now[held] = 0; changed = 1; }
        else if (down && held < 0 && free >= 0) { m->kb_now[free] = usage; changed = 1; }
        /* a fifth key is dropped, like the 4-slot register the I/O processor reads */
    }
    /* every change is kept in order (while the keys are Horizon's): a press and its release
     * between two polls are two events. When the queue is full the later changes are only
     * in the state above (reported as a difference) */
    if (changed && !M.sys.kb_route && m->kq_n < MB_KQ) {
        int t = (m->kq_head + m->kq_n++) % MB_KQ;
        m->kq_usage[t] = usage;
        m->kq_down[t] = down != 0;
    }
}

void mailbox_mouse(int btn, int dx, int dy, int wheel)
{
    Mailbox *m = &M.mb;
    btn &= 7;
    if (!m->ms_n) { m->ms_n = 1; m->ms_seg[m->ms_head].btn = m->ms_btn; }
    int t = (m->ms_head + m->ms_n - 1) % MB_MSEG;
    if (btn != m->ms_seg[t].btn) {                      /* a button change: a run of its own */
        if (m->ms_n < MB_MSEG) {
            t = (m->ms_head + m->ms_n++) % MB_MSEG;
            m->ms_seg[t].dx = m->ms_seg[t].dy = m->ms_seg[t].wheel = 0;
        }
        m->ms_seg[t].btn = btn;
        m->ms_seg[t].force = 1;
    }
    m->ms_btn = btn;
    /* (int16 like the firmware's accumulators) */
    int32_t *a[3] = { &m->ms_seg[t].dx, &m->ms_seg[t].dy, &m->ms_seg[t].wheel }, d[3] = { dx, dy, wheel };
    for (int i = 0; i < 3; i++) {
        int32_t v = *a[i] + d[i];
        *a[i] = v > 32767 ? 32767 : v < -32768 ? -32768 : v;
    }
}

static int clamp127(int v) { return v > 127 ? 127 : v < -127 ? -127 : v; }

static void put_event(Mailbox *m, const uint8_t *e)
{
    if (mb_put(m->rsp_base + m->rsp_head * 16u, e, 16)) { m->rsp_head++; memtime_sweep(); }
    machine_update_irq();
}

/* one $E1 event: the oldest run's motion (clamped to -127..127, the rest kept for the next
 * event) with its buttons; a run that starts with a button change is sent even without
 * motion. While KB_ROUTE = 1 the motion is dropped and the buttons count as reported. */
static int mouse_event(Mailbox *m)
{
    if (M.sys.kb_route || !m->ms_n) {
        m->ms_head = 0; m->ms_n = 1;
        memset(&m->ms_seg[0], 0, sizeof m->ms_seg[0]);
        m->ms_seg[0].btn = m->ms_btn;
        return 0;
    }
    for (;;) {
        __typeof__(m->ms_seg[0]) *g = &m->ms_seg[m->ms_head];
        if (g->dx || g->dy || g->wheel || g->force) {
            int dx = clamp127(g->dx), dy = clamp127(g->dy), dw = clamp127(g->wheel);
            uint8_t e[16] = { 0xE1, 0, 0, 0, 0, 0, 0, 0, (uint8_t)dx, (uint8_t)dy, (uint8_t)dw, 0, g->btn, 0, 0, 0 };
            put_event(m, e);
            g->dx -= dx; g->dy -= dy; g->wheel -= dw; g->force = 0;
            m->n_mouseev++;
            if (!g->dx && !g->dy && !g->wheel && m->ms_n > 1) { m->ms_head = (m->ms_head + 1) % MB_MSEG; m->ms_n--; }
            return 1;
        }
        if (m->ms_n <= 1) return 0;
        m->ms_head = (m->ms_head + 1) % MB_MSEG;          /* an empty run: the next one */
        m->ms_n--;
    }
}

/* one $E0 event: the oldest key change not yet reported (a change that is no news, such as
 * the release of a key never reported down, is skipped); with none queued, the difference
 * between the keys held now and those reported (a key held before KB_ROUTE went to 0):
 * releases first, then modifiers, then presses. While KB_ROUTE = 1 every key counts as
 * released and nothing is queued. */
static int key_event(Mailbox *m)
{
    uint8_t usage = 0, down = 0;
    if (M.sys.kb_route) m->kq_n = 0;
    while (m->kq_n && !usage) {
        uint8_t u = m->kq_usage[m->kq_head], d = m->kq_down[m->kq_head];
        m->kq_head = (m->kq_head + 1) % MB_KQ;
        m->kq_n--;
        if (u >= 0xE0 && u <= 0xE7) {
            uint8_t b = 1 << (u - 0xE0);
            if (!(m->kb_mods & b) != !d) { m->kb_mods ^= b; usage = u; down = d; }
            continue;
        }
        int held = -1, free = -1;
        for (int i = 0; i < 4; i++) { if (m->kb_held[i] == u) held = i; if (!m->kb_held[i] && free < 0) free = i; }
        if (!d && held >= 0) { m->kb_held[held] = 0; usage = u; }
        else if (d && held < 0 && free >= 0 && u > 3) { m->kb_held[free] = u; usage = u; down = 1; }
    }
    if (!usage) {
        uint8_t now[4], nm = m->kb_now_mods;
        memcpy(now, m->kb_now, 4);
        if (M.sys.kb_route) { memset(now, 0, 4); nm = 0; }    /* keys belong to the classic side */
        for (int i = 0; i < 4 && !usage; i++) {
            int still = 0;
            for (int j = 0; j < 4; j++) if (m->kb_held[i] && m->kb_held[i] == now[j]) still = 1;
            if (m->kb_held[i] && !still) { usage = m->kb_held[i]; m->kb_held[i] = 0; }
        }
        for (int i = 0; i < 8 && !usage; i++)
            if ((m->kb_mods ^ nm) & (1 << i)) { usage = 0xE0 + i; down = (nm >> i) & 1; m->kb_mods ^= 1 << i; }
        for (int i = 0; i < 4 && !usage; i++) {
            int known = 0, slot = -1;
            for (int j = 0; j < 4; j++) { if (m->kb_held[j] == now[i]) known = 1; if (!m->kb_held[j]) slot = j; }
            if (now[i] > 3 && !known && slot >= 0) { usage = now[i]; down = 1; m->kb_held[slot] = usage; }
        }
    }
    if (!usage) return 0;
    uint8_t e[16] = { 0xE0, 0, 0, 0, 0, 0, 0, 0, usage, 0, 0, 0, m->kb_mods, down, 0, 0 };
    put_event(m, e);
    m->n_keyev++;
    return 1;
}

/* ── Slow transfers (--card-kbps, --pc-kbps): how long the I/O processor takes for a request ──
 * READ, WRITE and LOAD: a fixed cost per request + the bytes / the rate; the other file ops
 * the fixed cost. Only for a volume whose option was given. */
double mailbox_card_kbps[2], mailbox_pc_kbps[2];
#define CARD_REQ_MS 1.0
#define PC_REQ_MS   6.0

static uint64_t req_cycles(Mailbox *m, const uint8_t *msg, int *pc)
{
    static char path[MAXPATH], host[4096];
    uint32_t len = msg[2] | msg[3] << 8, buf = msg[4] | msg[5] << 8 | msg[6] << 16;
    uint32_t arg0 = msg[8] | msg[9] << 8 | msg[10] << 16 | (uint32_t)msg[11] << 24;
    int op = msg[0], rd = 1, xfer = 0;
    double bytes = 0;
    *pc = 0;
    switch (op) {
    case 0x02: case 0x03: case 0x04: case 0x05:          /* CLOSE, READ, WRITE, SEEK: by the handle */
        if (arg0 >= MB_FILES || !m->f[arg0] || pc_dead(m, arg0)) return 0;     /* (refused at once) */
        *pc = m->fpc[arg0];
        if (op == 0x03 || op == 0x04) { xfer = 1; bytes = len; rd = op == 0x03; }
        break;
    case 0x01: case 0x06: case 0x07: case 0x08: case 0x09: case 0x0A: case 0x10:
        if (!mb_path(buf, path, sizeof path)) return 0;
        *pc = is_pc(path);
        if (*pc && !pc_up()) return 0;                   /* no PC link: refused at once */
        if (op == 0x10) {                                /* LOAD: the file's size */
            struct stat st;
            int p2;
            xfer = 1;
            if (!resolve(path, host, sizeof host, &p2) && !stat(host, &st) && S_ISREG(st.st_mode)) bytes = st.st_size;
        }
        break;
    default:
        return 0;
    }
    const double *k = *pc ? mailbox_pc_kbps : mailbox_card_kbps;
    if (!k[0] && !k[1]) return 0;                        /* not given: instant */
    double s = (*pc ? PC_REQ_MS : CARD_REQ_MS) / 1000.0;
    if (xfer && k[rd ? 0 : 1] > 0) s += bytes / (k[rd ? 0 : 1] * 1024.0);
    return (uint64_t)(s * CPU_HZ);
}

/* the answer of the request in msg goes into the response ring */
static void answer(Mailbox *m, uint8_t *msg)
{
    if (!mb_put(m->rsp_base + m->rsp_head * 16u, msg, 16)) { m->error = 1; return; }
    m->rsp_head++; memtime_sweep();
    m->req_tail++;
    machine_update_irq();
}

/* ── for net.c ── */
int      mbx_get(uint32_t n, uint8_t *dst, uint32_t len) { return mb_get(n, dst, len); }
int      mbx_put(uint32_t n, const uint8_t *src, uint32_t len) { return mb_put(n, src, len); }
int      mbx_path(uint32_t n, char *dst, int max) { return mb_path(n, dst, max); }
int      mbx_link_up(void) { return link_up(); }
uint8_t  mbx_link_session(void) { return pc_session(); }
uint32_t mbx_pc_fat_now(void) { return fat_time(pc_now()); }
int      mbx_resolve_in(const char *root, const char *fat, char *out, unsigned long n) { return host_path_in(root, fat, out, n, 1); }

void mailbox_poll(uint64_t now)
{
    Mailbox *m = &M.mb;
    if (now < m->next_poll) return;
    m->next_poll = now + MB_POLL;
    if (mailbox_pc_root) pc_drop_tmp(m);
    net_tick(now);

    if (!m->req_base || !m->rsp_base) {                  /* not set up (or torn down) */
        if (m->ready || m->error || m->req_tail || m->rsp_head || m->busy) {
            close_all(m, 0);
            net_close_all(0);
            m->ready = m->error = 0;
            m->req_tail = m->rsp_head = 0;
            m->busy = 0;
        }
        return;
    }
    if (!m->ready) { m->ready = 1; m->error = 0; m->req_tail = m->rsp_head = 0; m->busy = 0; return; }
    /* events: one per poll, also while a request is in progress, while the response ring has
     * at least 2 free slots (one stays free for the answer of that request) */
    int ev = 0;
    if ((uint8_t)(m->rsp_tail - m->rsp_head - 1) >= 2) {
        ev = key_event(m) || mouse_event(m);
        if (!ev) {                                       /* the answer of a request put aside, or $E4 */
            uint8_t e[16];
            if (net_output(e, now)) { put_event(m, e); ev = 1; }
        }
    }
    if ((uint8_t)(m->rsp_head + 1) == m->rsp_tail) return;      /* no room for an answer */
    if (m->busy) {                                       /* a request in progress */
        if (now < m->busy_until) return;
        m->busy = 0;
        uint8_t *msg = m->busy_msg;
        if (m->busy_pc && (!pc_up() || pc_session() != m->busy_sess)) {
            /* the link dropped while the PC served it: "link lost", nothing done */
            m->n_req++;
            msg[0] |= 0x80;
            memset(msg + 8, 0, 8);
            msg[8] = MB_PC_LOST;
        } else serve(m, msg);
        answer(m, msg);
        return;
    }
    if (ev) return;                                      /* (a poll that sent an event starts none) */
    if (m->req_head == m->req_tail) return;
    uint8_t msg[16];
    if (!mb_get(m->req_base + m->req_tail * 16u, msg, 16)) { m->error = 1; return; }
    int nr = net_take(msg, now);                         /* a URL or a stream handle (4-7) */
    if (nr) {
        m->n_req++;
        if (nr == 1) answer(m, msg);
        else m->req_tail++;                              /* put aside: its answer comes later */
        return;
    }
    int pc;
    uint64_t d = req_cycles(m, msg, &pc);
    if (d) {                                             /* served one at a time: the answer later */
        memcpy(m->busy_msg, msg, 16);
        m->busy = 1;
        m->busy_until = now + d;
        m->busy_pc = pc && pc_up();
        m->busy_sess = pc_session();
        return;
    }
    serve(m, msg);
    answer(m, msg);
}

uint8_t mailbox_read(uint32_t a)
{
    Mailbox *m = &M.mb;
    switch (a & 0xFF) {
    case 0x00: return m->req_base & 0xFF;
    case 0x01: return (m->req_base >> 8) & 0xFF;
    case 0x02: return (m->req_base >> 16) & 0xFF;
    case 0x03: return m->req_head;
    case 0x04: return m->req_tail;
    case 0x05: return m->rsp_base & 0xFF;
    case 0x06: return (m->rsp_base >> 8) & 0xFF;
    case 0x07: return (m->rsp_base >> 16) & 0xFF;
    case 0x08: blitter_flush(); return m->rsp_head;   /* (the RTL sweeps the cache first) */
    case 0x09: return m->rsp_tail;
    case 0x0A: return m->error << 1 | m->ready;
    }
    return 0;
}

void mailbox_write(uint32_t a, uint8_t v)
{
    Mailbox *m = &M.mb;
    int i = a & 0xFF;
    switch (i) {
    case 0x00: case 0x01: case 0x02:
        m->req_base = (m->req_base & ~(0xFFu << (8 * i))) | (uint32_t)v << (8 * i); break;
    case 0x05: case 0x06: case 0x07:
        m->rsp_base = (m->rsp_base & ~(0xFFu << (8 * (i - 5)))) | (uint32_t)v << (8 * (i - 5)); break;
    case 0x03: m->req_head = v; break;
    case 0x09: m->rsp_tail = v; break;
    }
}
