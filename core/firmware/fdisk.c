// SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
// Copyright (c) 2026 Carlos Bravo
// fdisk.c - a folder on the card as an Atari DOS 2.0S disk (see fdisk.h).
//
// Saving (fd_sync) follows these rules, so that a half-done change on the Atari never costs a
// file in the folder:
//  - Only a file the Atari has closed is saved: its directory entry is in use and not open for
//    writing, its name fits the 8.3 rule, and its sector chain is complete and consistent (every
//    sector in range and not a system sector, the file number right, at most 125 bytes used, the
//    chain as long as the entry says, ending with 0). Anything else is left alone.
//  - A file is replaced in one step: written under a temporary name in the folder, then put in
//    place (the old one removed, the new one renamed).
//  - A file of the folder is deleted only when no directory entry (closed, open or odd) carries
//    its name any more (or only another file renamed onto it): a delete on the Atari, never a
//    file being saved again (DOS 2 marks the old entry deleted and writes the new one open until
//    it closes). A directory without a DOS 2 VTOC (byte 0 = 2) is not looked at at all.
//  - A file Horizon has open is not replaced, renamed or deleted now (tried again later).
//  - When the Atari uses the drive during a save, the save stops (the temporary file goes) and
//    is tried again when the drive is idle.
//  - Names the disk does not show (a folder file left out) are never overwritten: such a change
//    is counted as a conflict and not saved.
//  - Locking (flag bit 5) is kept in the image only.
#include "fdisk.h"
#include "fatfs/ff.h"
#ifdef FD_HOST
#include <string.h>
#else
#include "string.h"
#endif

#define SEC(img, s)   ((img) + ((uint32_t)(s) - 1) * 128)
#define FD_VTOC       360
#define FD_DIR0       361
#define TMPNAME       "/.A816TMP"

static int fd_up(int c) { return c >= 'a' && c <= 'z' ? c - 32 : c; }
static int fd_alnum(int c) { return (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9'); }
static int sysec(unsigned s) { return s < 4 || (s >= FD_VTOC && s <= 368) || s >= FD_NSEC; }
static unsigned nexts(unsigned s) { s++; return s == FD_VTOC ? 369 : s; }

int fd_atari_name(const char *n, char *out)
{
    int i = 0, k = 0, b = 0, e = 0;
    while (n[i] && n[i] != '.') {
        int c = fd_up((uint8_t)n[i++]);
        if (!fd_alnum(c) || b == 8 || (!b && c < 'A')) return 0;
        out[k++] = c; b++;
    }
    if (!b) return 0;
    if (n[i] == '.') {
        out[k++] = n[i++];
        while (n[i]) {
            int c = fd_up((uint8_t)n[i++]);
            if (!fd_alnum(c) || e == 3) return 0;
            out[k++] = c; e++;
        }
        if (!e) return 0;
    }
    out[k] = 0;
    return 1;
}

// a directory entry's name -> "NAME.EXT"; 0 if it does not fit the rule (also: blanks inside
// a field, lower case)
static int ent_name(const uint8_t *ent, char *out)
{
    char t[13];
    int k = 0, nb = 8, ne = 3;
    while (nb && ent[4 + nb] == ' ') nb--;
    while (ne && ent[12 + ne] == ' ') ne--;
    for (int i = 0; i < nb; i++) t[k++] = ent[5 + i];
    if (ne) {
        t[k++] = '.';
        for (int i = 0; i < ne; i++) t[k++] = ent[13 + i];
    }
    t[k] = 0;
    return fd_atari_name(t, out) && !strcmp(t, out);
}

static void name_ent(const char *n, uint8_t *ent)
{
    int i = 0;
    for (int k = 5; k < 16; k++) ent[k] = ' ';
    for (int k = 5; n[i] && n[i] != '.'; i++, k++) ent[k] = n[i];
    if (n[i] == '.') for (int k = 13; n[++i]; k++) ent[k] = n[i];
}

static int path_join(char *p, const char *dir, const char *name)
{
    int n = strlen(dir), m = strlen(name);
    if (n + 1 + m > 127) return 0;
    memcpy(p, dir, n);
    p[n] = '/';
    memcpy(p + n + 1, name, m + 1);
    return 1;
}

static void put16(uint8_t *p, unsigned v) { p[0] = v; p[1] = v >> 8; }
static unsigned get16(const uint8_t *p) { return p[0] | p[1] << 8; }

// ---------------------------------------------------------------- build
int fd_build(fd_t *d, uint8_t *img, const char *dir)
{
    static const uint8_t boot[9] = { 0x00, 0x01, 0x00, 0x07, 0x08, 0x07, 0x18, 0x60, 0x60 };
    DIR dj;
    FILINFO fi;
    FIL f;
    int nc = 0, r;
    unsigned cur = 4, nfree = FD_FREE0;

    for (uint32_t i = 0; i < FD_IMGSIZE; i += 4) *(uint32_t *)(img + i) = 0;
    if (strlen(dir) > 120) return FR_INVALID_NAME;
    strcpy(d->dir, dir);
    d->shown = d->skipped = 0;
    d->pending = d->fail = 0;
    d->conflicts = 0;
    memset(d->dirty, 0, sizeof d->dirty);
    memset(d->known, 0, sizeof d->known);

    // the empty disk: a boot sector that boots nothing (CLC RTS), the VTOC
    for (int i = 0; i < 9; i++) SEC(img, 1)[i] = boot[i];
    r = f_mkdir(dir);
    if (r == FR_OK || r == FR_EXIST) r = f_opendir(&dj, dir);
    if (r == FR_OK) {
        for (;;) {
            char nm[13];
            if (f_readdir(&dj, &fi) || !fi.fname[0]) break;
            if (fi.fattrib & AM_DIR) continue;
            if (!fd_atari_name(fi.fname, nm) || strlen(fi.fname) > 12) { d->skipped++; continue; }
            int i = nc;                                  // in name order, the first FD_NCAND
            while (i > 0 && strcmp(d->cand[i - 1].name, nm) > 0) i--;
            if (i == FD_NCAND) { d->skipped++; continue; }
            if (nc == FD_NCAND) { d->skipped++; nc--; }
            for (int m = nc; m > i; m--) d->cand[m] = d->cand[m - 1];
            strcpy(d->cand[i].name, nm);
            strcpy(d->cand[i].host, fi.fname);
            d->cand[i].size = fi.fsize;
            nc++;
        }
        f_closedir(&dj);
    }
    for (int c = 0; c < nc; c++) {
        fd_cand_t *k = &d->cand[c];
        unsigned need = k->size ? (k->size + 124) / 125 : 1, first = cur, n = 0, fno = d->shown;
        char p[128];
        if (fno == FD_NFILE || need > nfree || !path_join(p, dir, k->host) || f_open(&f, p, FA_READ)) {
            d->skipped++;
            continue;
        }
        unsigned s = cur, ok = 1;
        for (n = 0; n < need; n++) {                     // the file into its sectors, in order
            UINT br = 0;
            uint8_t *q = SEC(img, s);
            if (f_read(&f, q, 125, &br) || (br < 125 && n + 1 < need)) { ok = 0; break; }
            unsigned nx = n + 1 < need ? nexts(s) : 0;
            q[125] = fno << 2 | nx >> 8;
            q[126] = nx;
            q[127] = br;
            s = nx;
            fd_poll();
        }
        f_close(&f);
        if (!ok) {                                       // (it changed meanwhile, or the card)
            for (unsigned t = first, m = 0; m < need; m++, t = nexts(t))
                for (int i = 0; i < 128; i++) SEC(img, t)[i] = 0;
            d->skipped++;
            continue;
        }
        uint8_t *e = SEC(img, FD_DIR0 + fno / 8) + (fno % 8) * 16;
        e[0] = 0x42;
        put16(e + 1, need);
        put16(e + 3, first);
        name_ent(k->name, e);
        d->known[fno].used = 1;
        memcpy(d->known[fno].ent, e, 16);
        strcpy(d->known[fno].host, k->host);
        for (n = 0; n < need; n++) cur = nexts(cur);
        nfree -= need;
        d->shown++;
    }
    uint8_t *v = SEC(img, FD_VTOC);
    v[0] = 2;
    put16(v + 1, FD_FREE0);
    put16(v + 3, nfree);
    for (unsigned s = cur; s < FD_NSEC; s = nexts(s)) v[10 + s / 8] |= 0x80 >> (s & 7);
    d->nfree = nfree;
    d->t_saved = fd_fattime();
    return r == FR_EXIST ? 0 : r;
}

// ---------------------------------------------------------------- save
enum { S_NONE, S_FILE, S_OPEN, S_ODD, S_OTHER };
enum { A_NONE, A_RENAME, A_WRITE, A_SKIP };

// the entry's chain: 1 if complete and consistent (nsec sectors, file number fno)
static int chain_ok(const uint8_t *img, const uint8_t *e, int fno)
{
    unsigned s = get16(e + 3), n = get16(e + 1);
    if (!n || n > FD_FREE0) return 0;
    for (unsigned k = 0; k < n; k++) {
        if (sysec(s)) return 0;
        const uint8_t *q = SEC(img, s);
        if ((q[125] >> 2) != fno || q[127] > 125) return 0;
        s = (q[125] & 3) << 8 | q[126];
    }
    return s == 0;
}

static int chain_dirty(const fd_t *d, const uint8_t *img, const uint8_t *e)
{
    unsigned s = get16(e + 3), n = get16(e + 1);
    for (unsigned k = 0; k < n && !sysec(s); k++) {
        if (d->dirty[s >> 3] & (1 << (s & 7))) return 1;
        const uint8_t *q = SEC(img, s);
        s = (q[125] & 3) << 8 | q[126];
    }
    return 0;
}

static void chain_clean(fd_t *d, const uint8_t *img, const uint8_t *e)
{
    unsigned s = get16(e + 3), n = get16(e + 1);
    for (unsigned k = 0; k < n && !sysec(s); k++) {
        d->dirty[s >> 3] &= ~(1 << (s & 7));
        const uint8_t *q = SEC(img, s);
        s = (q[125] & 3) << 8 | q[126];
    }
}

// the same entry apart from the lock bit
static int same_ent(const uint8_t *a, const uint8_t *b)
{
    if ((a[0] & ~0x20) != (b[0] & ~0x20)) return 0;
    for (int i = 1; i < 16; i++) if (a[i] != b[i]) return 0;
    return 1;
}

static int exists(const char *p)
{
    FILINFO fi;
    return f_stat(p, &fi) == FR_OK;
}

// the file of entry e (closed and consistent) -> the folder as name (via the temporary file).
// 0 OK, 1 the Atari used the drive meanwhile, 2 a card error
static int save_file(fd_t *d, const uint8_t *img, const uint8_t *e, const char *target, uint32_t act0)
{
    char tmp[128];
    FIL f;
    int r = 0;
    strcpy(tmp, d->dir);
    strcat(tmp, TMPNAME);
    if (f_open(&f, tmp, FA_CREATE_ALWAYS | FA_WRITE)) return 2;
    unsigned s = get16(e + 3), n = get16(e + 1);
    for (unsigned k = 0; k < n && !r; k++) {
        const uint8_t *q = SEC(img, s);
        UINT bw;
        unsigned c = q[127];
        s = (q[125] & 3) << 8 | q[126];
        if (c && (f_write(&f, q, c, &bw) || bw != c)) r = 2;
        fd_poll();
        if (fd_act != act0) r = 1;
    }
    if (f_close(&f) && !r) r = 2;
    if (!r && fd_act != act0) r = 1;
    if (!r && exists(target) && f_unlink(target)) r = 2;
    if (!r && f_rename(tmp, target)) r = 2;
    if (r) f_unlink(tmp);
    return r;
}

int fd_sync(fd_t *d, uint8_t *img)
{
    uint8_t (*ent)[16] = d->s_ent, *st = d->s_st, *act = d->s_act;
    char (*nm)[13] = d->s_nm, (*kn)[13] = d->s_kn;
    uint32_t act0 = fd_act;
    int wait = 0;
    char p[128], q[128];

    if (!d->dir[0] || !d->pending) return 0;
    d->pending = 0;
    if (SEC(img, FD_VTOC)[0] != 2) { d->pending = 1; return 1; }   // not a DOS 2 disk now: wait

    // the directory as it is now
    int end = 0;
    for (int i = 0; i < FD_NFILE; i++) {
        const uint8_t *e = SEC(img, FD_DIR0 + i / 8) + (i % 8) * 16;
        memcpy(ent[i], e, 16);
        uint8_t fl = e[0];
        if (!fl) end = 1;                                // DOS 2 stops at a never used entry
        if (end || (fl & 0x80)) st[i] = S_NONE;
        else if (!(fl & 0x40) || (fl & 0x10)) st[i] = S_OTHER;   // (a MyDOS folder: left alone)
        else if (!ent_name(e, nm[i])) st[i] = S_ODD;
        else if (fl & 0x01) st[i] = S_OPEN;
        else st[i] = chain_ok(img, e, i) ? S_FILE : S_ODD;
        if (st[i] == S_OTHER) nm[i][0] = 0;
        if (st[i] == S_ODD && !ent_name(e, nm[i])) nm[i][0] = 0;
        kn[i][0] = 0;
        if (d->known[i].used) ent_name(d->known[i].ent, kn[i]);
    }
    if (fd_act != act0) { d->pending = 1; return 1; }

    // what to do with each closed file
    for (int i = 0; i < FD_NFILE; i++) {
        fd_known_t *k = &d->known[i];
        act[i] = A_NONE;
        if (st[i] != S_FILE) continue;
        int dirty = chain_dirty(d, img, ent[i]);
        if (k->conflict && !memcmp(k->ent, ent[i], 16) && !dirty) act[i] = A_SKIP;
        else if (k->used && !dirty && get16(k->ent + 1) == get16(ent[i] + 1)
                 && get16(k->ent + 3) == get16(ent[i] + 3))
            act[i] = !strcmp(kn[i], nm[i]) ? (same_ent(k->ent, ent[i]) ? A_NONE : A_SKIP) : A_RENAME;
        else act[i] = A_WRITE;
        if (act[i] == A_SKIP && !k->conflict) { memcpy(k->ent, ent[i], 16); act[i] = A_NONE; }   // (lock)
    }

    // 1. deleted on the Atari: no entry carries the name any more
    for (int j = 0; j < FD_NFILE; j++) {
        fd_known_t *k = &d->known[j];
        if (!k->used || act[j] == A_RENAME) continue;
        int present = 0;
        for (int i = 0; i < FD_NFILE && !present; i++)
            if ((st[i] == S_FILE || st[i] == S_OPEN || st[i] == S_ODD) && !strcmp(nm[i], kn[j])
                && (i == j || act[i] != A_RENAME)) present = 1;   // (renamed onto it: replaced)
        if (present) continue;
        if (!path_join(p, d->dir, k->host)) { k->used = 0; continue; }
        if (fd_busy(p)) { wait = 1; continue; }
        int r = f_unlink(p);
        if (r && r != FR_NO_FILE) { wait = 2; continue; }
        k->used = 0;
        fd_poll();
    }
    // 2. renamed
    for (int i = 0; i < FD_NFILE; i++) {
        fd_known_t *k = &d->known[i];
        if (act[i] != A_RENAME) continue;
        if (!path_join(p, d->dir, k->host) || !path_join(q, d->dir, nm[i])) continue;
        int taken = exists(q) && strcasecmp(k->host, nm[i]);
        if (taken) {                                     // a name in the way
            k->conflict = 1; d->conflicts++;
            memcpy(k->ent, ent[i], 16);
            continue;
        }
        if (fd_busy(p)) { wait = 1; continue; }
        if (f_rename(p, q)) { wait = 2; continue; }
        strcpy(k->host, nm[i]);
        memcpy(k->ent, ent[i], 16);
        k->conflict = 0;
        fd_poll();
    }
    // 3. written
    for (int i = 0; i < FD_NFILE; i++) {
        fd_known_t *k = &d->known[i];
        if (act[i] != A_WRITE) continue;
        const char *host = nm[i];
        int owner = -1;                                  // a file of the disk had that name
        for (int j = 0; j < FD_NFILE; j++)
            if (d->known[j].used && !strcmp(kn[j], nm[i])) { owner = j; host = d->known[j].host; break; }
        if (!path_join(q, d->dir, host)) continue;
        if (owner < 0 && exists(q)) {                    // a folder file the disk does not show
            k->used = 0; k->conflict = 1; d->conflicts++;
            memcpy(k->ent, ent[i], 16);
            continue;
        }
        if (fd_busy(q)) { wait = 1; continue; }
        char h[13];
        strcpy(h, host);
        int r = save_file(d, img, ent[i], q, act0);
        if (r) { wait = r; if (r == 1) break; continue; }
        if (owner >= 0 && owner != i) d->known[owner].used = 0;
        k->used = 1; k->conflict = 0;
        memcpy(k->ent, ent[i], 16);
        strcpy(k->host, h);
        chain_clean(d, img, ent[i]);
    }
    if (wait) {
        d->pending = 1;
        d->fail = wait == 2;
        return 1;
    }
    // everything saved: the sectors of files not saved (open, odd) stay marked
    uint8_t keep[FD_NSEC / 8];
    memset(keep, 0, sizeof keep);
    for (int i = 0; i < FD_NFILE; i++)
        if (st[i] == S_OPEN || st[i] == S_ODD) {
            unsigned s = get16(ent[i] + 3), n = get16(ent[i] + 1);
            for (unsigned k = 0; k < n && !sysec(s); k++) {
                keep[s >> 3] |= 1 << (s & 7);
                const uint8_t *qq = SEC(img, s);
                s = (qq[125] & 3) << 8 | qq[126];
            }
        }
    for (unsigned i = 0; i < sizeof keep; i++) d->dirty[i] &= keep[i];
    d->fail = 0;
    d->t_saved = fd_fattime();
    return 0;
}
