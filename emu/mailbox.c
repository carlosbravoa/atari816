/* I/O processor mailbox — mirrors a816_mailbox() in core/firmware/firmware.c, with a host
 * directory standing in for the FAT32 SD card.
 *
 * Result codes (response ARG0): 0 OK, 1..19 FatFs FRESULT, $80 bad handle, $81 bad address,
 * $82 unsupported op. Host errno values are mapped to the FRESULT FatFs would return.
 * The I/O processor polls every MB_POLL CPU cycles and serves one request per poll.
 */

#include "machine.h"
#include <dirent.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

enum { FR_OK, FR_DISK_ERR, FR_INT_ERR, FR_NOT_READY, FR_NO_FILE, FR_NO_PATH, FR_INVALID_NAME,
       FR_DENIED, FR_EXIST, FR_INVALID_OBJECT, FR_WRITE_PROTECTED, FR_INVALID_DRIVE,
       FR_NOT_ENABLED, FR_NO_FILESYSTEM, FR_MKFS_ABORTED, FR_TIMEOUT, FR_LOCKED,
       FR_NOT_ENOUGH_CORE, FR_TOO_MANY_OPEN_FILES, FR_INVALID_PARAMETER };
enum { MB_BAD_HANDLE = 0x80, MB_BAD_ADDR = 0x81, MB_UNSUPPORTED = 0x82 };

#define MAXPATH 128                 /* the firmware's path buffer */

static void close_all(Mailbox *m)
{
    for (int i = 0; i < MB_FILES; i++) if (m->f[i]) { fclose(m->f[i]); m->f[i] = NULL; }
}

void mailbox_reset(void)
{
    Mailbox *m = &M.mb;
    const char *root = m->root;
    int restart = m->restart;
    uint8_t now[4], nm = m->kb_now_mods;               /* keys held on the host survive */
    uint8_t btn = m->ms_btn;
    memcpy(now, m->kb_now, 4);
    close_all(m);
    memset(m, 0, sizeof *m);
    m->root = root;
    m->restart = restart;
    memcpy(m->kb_now, now, 4);
    m->kb_now_mods = nm;
    m->ms_btn = m->ms_btn_sent = btn;
    m->next_poll = M.cpu.cycles + MB_POLL;
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
    Mailbox *m = &M.mb;
    if (!m->root) return FR_NOT_READY;
    if (fat[0] == '0' && fat[1] == ':') fat += 2;          /* drive prefix */
    size_t len = snprintf(out, n, "%s", m->root);
    const char *p = fat;
    while (*p) {
        while (*p == '/' || *p == '\\') p++;
        if (!*p) break;
        const char *e = p;
        while (*e && *e != '/' && *e != '\\') e++;
        size_t cl = e - p;
        if (cl == 1 && p[0] == '.') { p = e; continue; }
        if (cl == 2 && p[0] == '.' && p[1] == '.') return FR_INVALID_NAME;    /* no escaping */
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
    /* existing objects must resolve inside the root (no symlink escapes) */
    char real[4096], rroot[4096];
    if (realpath(out, real) && realpath(m->root, rroot)) {
        size_t rl = strlen(rroot);
        if (strncmp(real, rroot, rl) || (real[rl] && real[rl] != '/')) return FR_DENIED;
    }
    return FR_OK;
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

    m->n_req++;
    switch (msg[0]) {
    case 0x01: {                                         /* OPEN */
        static const char *const mode[4] = { "rb", "r+b", "w+b", "ab" };
        static const uint8_t rw[4] = { 1, 3, 3, 2 };
        int h = 0, fl = msg[7] & 3;
        while (h < MB_FILES && m->f[h]) h++;
        if (h == MB_FILES) { res = FR_TOO_MANY_OPEN_FILES; break; }
        if (!mb_path(buf, path, sizeof path)) { res = MB_BAD_ADDR; break; }
        if ((res = host_path(path, host, sizeof host))) break;
        if (!stat(host, &st) && S_ISDIR(st.st_mode)) { res = fl >= 2 ? FR_EXIST : FR_NO_FILE; break; }
        FILE *nf = fopen(host, mode[fl]);
        if (!nf) { res = errno_fr(errno, host); break; }
        m->f[h] = nf; m->fmode[h] = rw[fl]; val = h;
        break;
    }
    case 0x02:                                           /* CLOSE */
        if (!f) { res = MB_BAD_HANDLE; break; }
        if (fclose(f)) res = FR_DISK_ERR;
        m->f[arg0] = NULL;
        break;
    case 0x03: case 0x04:                                /* READ, WRITE */
        if (!f) { res = MB_BAD_HANDLE; break; }
        if (!(m->fmode[arg0] & (msg[0] == 0x04 ? 2 : 1))) { res = FR_DENIED; break; }
        fseek(f, 0, SEEK_CUR);                           /* allow switching read/write */
        val = xfer(f, buf, len, msg[0] == 0x04, &res);
        break;
    case 0x05:                                           /* SEEK */
        if (!f) { res = MB_BAD_HANDLE; break; }
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
        if ((res = host_path(path, host, sizeof host))) break;
        const char *q = path; while (*q == '/') q++;
        if (!*q) { res = FR_INVALID_NAME; break; }       /* FatFs cannot stat the root */
        if (stat(host, &st)) { res = errno_fr(errno, host); break; }
        uint32_t sz = S_ISDIR(st.st_mode) ? 0 : (uint32_t)st.st_size, t = fat_time(st.st_mtime);
        o[0] = sz; o[1] = sz >> 8; o[2] = sz >> 16; o[3] = sz >> 24;
        o[4] = fat_attr(host, &st);
        o[5] = t; o[6] = t >> 8; o[7] = t >> 16; o[8] = t >> 24;
        if (!mb_put(buf, o, 9)) res = MB_BAD_ADDR;
        val = sz;
        break;
    }
    case 0x07: {                                         /* READDIR */
        if (!mb_path(buf, path, sizeof path)) { res = MB_BAD_ADDR; break; }
        if ((res = host_path(path, host, sizeof host))) break;
        DIR *d = opendir(host);
        if (!d) { res = errno == ENOTDIR ? FR_NO_PATH : errno_fr(errno, host); break; }
        char **names = NULL;
        size_t nn = 0, cap = 0;
        struct dirent *de;
        while ((de = readdir(d))) {
            if (!strcmp(de->d_name, ".") || !strcmp(de->d_name, "..")) continue;
            if (strlen(de->d_name) > 255) continue;
            if (nn == cap) names = realloc(names, (cap = cap ? 2 * cap : 64) * sizeof *names);
            names[nn++] = strdup(de->d_name);
        }
        closedir(d);
        qsort(names, nn, sizeof *names, cmpstr);         /* deterministic order */
        uint32_t off = 0;
        for (size_t i = 0; i < nn; i++) {
            if (arg0) { arg0--; continue; }
            char hp[4400];
            snprintf(hp, sizeof hp, "%s/%s", host, names[i]);
            if (stat(hp, &st)) continue;
            uint32_t nl = strlen(names[i]), sz = S_ISDIR(st.st_mode) ? 0 : (uint32_t)st.st_size;
            uint8_t h[6] = { sz, sz >> 8, sz >> 16, sz >> 24, fat_attr(hp, &st), nl };
            if (off + 6 + nl > len) break;
            if (!mb_put(buf + off, h, 6) || !mb_put(buf + off + 6, (uint8_t *)names[i], nl)) { res = MB_BAD_ADDR; break; }
            off += 6 + nl;
            val++;
        }
        for (size_t i = 0; i < nn; i++) free(names[i]);
        free(names);
        break;
    }
    case 0x08: case 0x09:                                /* MKDIR, DELETE */
        if (!mb_path(buf, path, sizeof path)) { res = MB_BAD_ADDR; break; }
        if ((res = host_path(path, host, sizeof host))) break;
        if (msg[0] == 0x08) { if (mkdir(host, 0777)) res = errno_fr(errno, host); }
        else if (!lstat(host, &st) && S_ISDIR(st.st_mode)) { if (rmdir(host)) res = errno_fr(errno, host); }
        else if (unlink(host)) res = errno_fr(errno, host);
        break;
    case 0x0A: {                                         /* RENAME "old\0new" */
        static char to[MAXPATH], hto[4096];
        if (!mb_path(buf, path, sizeof path) || !mb_path(buf + strlen(path) + 1, to, sizeof to)) { res = MB_BAD_ADDR; break; }
        if ((res = host_path(path, host, sizeof host)) || (res = host_path(to, hto, sizeof hto))) break;
        if (lstat(host, &st)) { res = errno_fr(errno, host); break; }
        if (!lstat(hto, &st)) { res = FR_EXIST; break; }
        if (rename(host, hto)) res = errno_fr(errno, hto);
        break;
    }
    case 0x10: {                                         /* LOAD whole file to ARG0 */
        if (!mb_path(buf, path, sizeof path)) { res = MB_BAD_ADDR; break; }
        if ((res = host_path(path, host, sizeof host))) break;
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
                if (kind == 3) m->cl_cart = 0;
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
            else m->cl_cart = 1;
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
        else { close_all(m); m->restart = 1 + (int)arg0; }
        fprintf(stderr, "emu816: SYS_RESTART %u -> %02X\n", (unsigned)arg0, (unsigned)res);
        break;
    case 0x1C:                                           /* SYS_SYNC (stub) */
        /* the firmware flushes and closes everything on the card: here, close the files */
        close_all(m);
        fprintf(stderr, "emu816: SYS_SYNC -> 00\n");
        break;
    default:                                             /* MOUNT, UNMOUNT, TIME, ... */
        res = MB_UNSUPPORTED;
    }

    msg[0] |= 0x80;
    msg[8] = res; msg[9] = res >> 8; msg[10] = res >> 16; msg[11] = res >> 24;
    msg[12] = val; msg[13] = val >> 8; msg[14] = val >> 16; msg[15] = val >> 24;
}

void mailbox_key(uint8_t usage, int down)
{
    Mailbox *m = &M.mb;
    if (usage >= 0xE0 && usage <= 0xE7) {
        uint8_t b = 1 << (usage - 0xE0);
        m->kb_now_mods = down ? (m->kb_now_mods | b) : (m->kb_now_mods & ~b);
        return;
    }
    for (int i = 0; i < 4; i++) if (m->kb_now[i] == usage) { if (!down) m->kb_now[i] = 0; return; }
    if (down) for (int i = 0; i < 4; i++) if (!m->kb_now[i]) { m->kb_now[i] = usage; return; }
    /* a fifth key is dropped, like the 4-slot register the I/O processor reads */
}

void mailbox_mouse(int btn, int dx, int dy, int wheel)
{
    Mailbox *m = &M.mb;
    m->ms_btn = btn & 7;
    m->ms_dx += dx; m->ms_dy += dy; m->ms_wheel += wheel;     /* int16 like the firmware */
}

static int clamp127(int v) { return v > 127 ? 127 : v < -127 ? -127 : v; }

/* firmware "Mouse event ($E1)": only when no key event was sent in this poll */
static int mouse_event(Mailbox *m)
{
    if (M.sys.kb_route) { m->ms_dx = m->ms_dy = m->ms_wheel = 0; m->ms_btn_sent = m->ms_btn; return 0; }
    if (!m->ms_dx && !m->ms_dy && !m->ms_wheel && m->ms_btn == m->ms_btn_sent) return 0;
    int dx = clamp127(m->ms_dx), dy = clamp127(m->ms_dy), dw = clamp127(m->ms_wheel);
    uint8_t e[16] = { 0xE1, 0, 0, 0, 0, 0, 0, 0, (uint8_t)dx, (uint8_t)dy, (uint8_t)dw, 0, m->ms_btn, 0, 0, 0 };
    if (mb_put(m->rsp_base + m->rsp_head * 16u, e, 16)) {
        m->rsp_head++;
        m->ms_dx -= dx; m->ms_dy -= dy; m->ms_wheel -= dw; m->ms_btn_sent = m->ms_btn;
        m->n_mouseev++;
        machine_update_irq();
    }
    return 1;
}

/* firmware "Keyboard events": one $E0 event from the difference between the keys held
 * now and those already reported. Releases first, then modifiers, then presses. */
static int key_event(Mailbox *m)
{
    uint8_t now[4], nm = m->kb_now_mods, usage = 0, down = 0;
    memcpy(now, m->kb_now, 4);
    if (M.sys.kb_route) { memset(now, 0, 4); nm = 0; }        /* keys belong to the classic side */
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
    if (!usage) return 0;
    uint8_t e[16] = { 0xE0, 0, 0, 0, 0, 0, 0, 0, usage, 0, 0, 0, m->kb_mods, down, 0, 0 };
    if (mb_put(m->rsp_base + m->rsp_head * 16u, e, 16)) m->rsp_head++;
    m->n_keyev++;
    machine_update_irq();
    return 1;
}

void mailbox_poll(uint64_t now)
{
    Mailbox *m = &M.mb;
    if (now < m->next_poll) return;
    m->next_poll = now + MB_POLL;

    if (!m->req_base || !m->rsp_base) {                  /* not set up (or torn down) */
        if (m->ready || m->error || m->req_tail || m->rsp_head) {
            close_all(m);
            m->ready = m->error = 0;
            m->req_tail = m->rsp_head = 0;
        }
        return;
    }
    if (!m->ready) { m->ready = 1; m->error = 0; m->req_tail = m->rsp_head = 0; return; }
    if ((uint8_t)(m->rsp_head + 1) == m->rsp_tail) return;      /* no room for an answer or event */
    if (key_event(m) || mouse_event(m)) return;                 /* one event per poll */
    if (m->req_head == m->req_tail) return;
    uint8_t msg[16];
    if (!mb_get(m->req_base + m->req_tail * 16u, msg, 16)) { m->error = 1; return; }
    serve(m, msg);
    if (!mb_put(m->rsp_base + m->rsp_head * 16u, msg, 16)) { m->error = 1; return; }
    m->rsp_head++;
    m->req_tail++;
    machine_update_irq();
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
