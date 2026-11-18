// SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
// Copyright (c) 2026 Carlos Bravo
// Host test of the folder disk (core/firmware/fdisk.c): the firmware's own code on the PC, on
// the firmware's own FatFs over a FAT image file (made by mkfs.vfat, checked by fsck.fat in
// run_tests.sh), against a model of Atari DOS 2.0S written here (it reads and writes the disk
// image sector by sector as DOS 2 does, through the same "SIO" path the firmware has: the image
// changes, the sector is marked, the Atari's activity counted).
//
//   harness IMAGE   runs every scenario; prints PASS / FAIL lines; exit 1 on a failure
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <stdint.h>
#include "ff.h"
#include "fdisk.h"

int diskio_host_open(const char *path);

// ---- what fdisk.c needs ----
volatile uint32_t fd_act;
static char busy_path[160];             // "Horizon has this file open"
static int  poll_n, poll_bump = -1;     // fd_poll: at call number poll_bump the Atari uses the drive
int fd_busy(const char *p) { return busy_path[0] && !strcasecmp(p, busy_path); }
void fd_poll(void) { if (poll_n++ == poll_bump) fd_act++; }
uint32_t fd_fattime(void) { return (46u << 25) | (11u << 21) | (18u << 16); }
DWORD get_fattime(void) { return fd_fattime(); }

static FATFS fs;
static fd_t D;
static uint8_t IMG[FD_IMGSIZE];
static int fails;
#define CHECK(c, ...) do { if (c) printf("PASS "); else { printf("FAIL "); fails++; } printf(__VA_ARGS__); printf("\n"); } while (0)
#define SEC(s) (IMG + ((s) - 1) * 128)

// ---- the card ----
static void put_file(const char *path, const uint8_t *d, uint32_t n)
{
    FIL f; UINT bw;
    if (f_open(&f, path, FA_CREATE_ALWAYS | FA_WRITE)) { printf("put_file %s failed\n", path); exit(2); }
    f_write(&f, d, n, &bw);
    f_close(&f);
}
static int get_file(const char *path, uint8_t *d, uint32_t max, uint32_t *n)
{
    FIL f; UINT br;
    if (f_open(&f, path, FA_READ)) return 0;
    f_read(&f, d, max, &br);
    f_close(&f);
    *n = br;
    return 1;
}
static int card_has(const char *path) { FILINFO fi; return f_stat(path, &fi) == FR_OK; }
static void fill(uint8_t *d, uint32_t n, int seed) { for (uint32_t i = 0; i < n; i++) d[i] = (uint8_t)(i * 7 + seed + (i >> 8)); }
static int card_is(const char *path, const uint8_t *d, uint32_t n)
{
    static uint8_t b[200000];
    uint32_t m;
    return get_file(path, b, sizeof b, &m) && m == n && !memcmp(b, d, n);
}
static void wipe_dir(const char *dir)
{
    DIR dj; FILINFO fi; char p[200];
    if (f_opendir(&dj, dir)) return;
    while (!f_readdir(&dj, &fi) && fi.fname[0]) {
        snprintf(p, sizeof p, "%s/%s", dir, fi.fname);
        f_unlink(p);
    }
    f_closedir(&dj);
}

// ---- the Atari: SIO and a model of DOS 2.0S ----
static int writes_left = -1;            // "reset": SIO writes stop after this many (-1: never)
static int sio_write(unsigned s, const uint8_t *b)
{
    if (writes_left == 0) return 0;
    if (writes_left > 0) writes_left--;
    memcpy(SEC(s), b, 128);
    fd_mark(&D, s);
    fd_act++;
    return 1;
}
static uint8_t *ent(int i) { return SEC(361 + i / 8) + (i % 8) * 16; }
static void dos_name(const char *n, uint8_t *e)
{
    memset(e + 5, ' ', 11);
    int i = 0;
    for (int k = 5; n[i] && n[i] != '.'; i++, k++) e[k] = n[i];
    if (n[i] == '.') for (int k = 13; n[++i]; k++) e[k] = n[i];
}
static int dos_find(const char *n)
{
    uint8_t e[16];
    dos_name(n, e);
    for (int i = 0; i < 64; i++) {
        uint8_t *d = ent(i);
        if (!d[0]) break;
        if ((d[0] & 0xC0) == 0x40 && !memcmp(d + 5, e + 5, 11)) return i;
    }
    return -1;
}
static int vtoc_free(unsigned s) { return SEC(360)[10 + s / 8] & (0x80 >> (s & 7)); }
static void vtoc_set(uint8_t *v, unsigned s, int free)
{
    if (free) { v[10 + s / 8] |= 0x80 >> (s & 7); v[3]++; if (!v[3]) v[4]++; }
    else { v[10 + s / 8] &= ~(0x80 >> (s & 7)); if (!v[3]) v[4]--; v[3]--; }
}
static int write_dirsec(int i) { uint8_t b[128]; memcpy(b, SEC(361 + i / 8), 128); return sio_write(361 + i / 8, b); }
static int write_vtoc(const uint8_t *v) { return sio_write(360, v); }
static void dos_free_chain(uint8_t *v, int i)
{
    unsigned s = ent(i)[3] | ent(i)[4] << 8;
    for (unsigned k = 0; k < (unsigned)(ent(i)[1] | ent(i)[2] << 8) && s; k++) {
        vtoc_set(v, s, 1);
        s = (SEC(s)[125] & 3) << 8 | SEC(s)[126];
    }
}
static int dos_delete(const char *n)
{
    int i = dos_find(n);
    if (i < 0) return 170;
    uint8_t v[128];
    memcpy(v, SEC(360), 128);
    dos_free_chain(v, i);
    ent(i)[0] = 0x80;
    if (!write_dirsec(i)) return 138;
    return write_vtoc(v) ? 0 : 138;
}
static unsigned dos_alloc(uint8_t *v)
{
    for (unsigned s = 1; s < 720; s++)
        if (v[10 + s / 8] & (0x80 >> (s & 7))) { vtoc_set(v, s, 0); return s; }
    return 0;
}
// SAVE: as DOS 2 does it: the old file deleted, a new entry open for writing, sectors as they
// fill, then the VTOC, then the entry closed. 0 = OK, else a DOS error (the "reset": 138).
static int dos_save(const char *n, const uint8_t *d, uint32_t len)
{
    if (dos_find(n) >= 0 && dos_delete(n)) return 138;
    int i = 0;
    while (i < 64 && ent(i)[0] && !(ent(i)[0] & 0x80)) i++;
    if (i == 64) return 169;                              // directory full
    uint8_t v[128], b[128];
    memcpy(v, SEC(360), 128);
    unsigned s = dos_alloc(v), first = s, cnt = 1;
    if (!s) return 162;
    uint8_t *e = ent(i);
    e[0] = 0x43; e[1] = e[2] = 0; e[3] = s; e[4] = s >> 8;
    dos_name(n, e);
    if (!write_dirsec(i)) return 138;
    uint32_t off = 0;
    for (;;) {
        uint32_t k = len - off > 125 ? 125 : len - off;
        memset(b, 0, 128);
        memcpy(b, d + off, k);
        off += k;
        unsigned nx = 0;
        if (off < len) { nx = dos_alloc(v); if (!nx) return 162; cnt++; }
        b[125] = i << 2 | nx >> 8; b[126] = nx; b[127] = k;
        if (!sio_write(s, b)) return 138;
        if (!nx) break;
        s = nx;
    }
    if (!write_vtoc(v)) return 138;
    e[0] = 0x42; e[1] = cnt; e[2] = cnt >> 8; (void)first;
    return write_dirsec(i) ? 0 : 138;
}
static int dos_rename(const char *a, const char *b)
{
    int i = dos_find(a);
    if (i < 0) return 170;
    dos_name(b, ent(i));
    return write_dirsec(i) ? 0 : 138;
}
static int dos_lock(const char *n) { int i = dos_find(n); if (i < 0) return 170; ent(i)[0] |= 0x20; return write_dirsec(i) ? 0 : 138; }
static int dos_read(const char *n, uint8_t *d, uint32_t *len)
{
    int i = dos_find(n);
    if (i < 0) return 170;
    unsigned s = ent(i)[3] | ent(i)[4] << 8;
    *len = 0;
    while (s) {
        if ((SEC(s)[125] >> 2) != i) return 164;           // file number mismatch
        memcpy(d + *len, SEC(s), SEC(s)[127]);
        *len += SEC(s)[127];
        s = (SEC(s)[125] & 3) << 8 | SEC(s)[126];
    }
    return 0;
}
// "update" mode: a byte changed inside the file, the directory untouched
static int dos_poke(const char *n, uint32_t at, uint8_t val)
{
    int i = dos_find(n);
    unsigned s = ent(i)[3] | ent(i)[4] << 8;
    while (at >= SEC(s)[127]) { at -= SEC(s)[127]; s = (SEC(s)[125] & 3) << 8 | SEC(s)[126]; }
    uint8_t b[128];
    memcpy(b, SEC(s), 128);
    b[at] = val;
    return sio_write(s, b) ? 0 : 138;
}
static int dos_count(void) { int c = 0; for (int i = 0; i < 64 && ent(i)[0]; i++) if ((ent(i)[0] & 0xC0) == 0x40) c++; return c; }
static unsigned vtoc_count(void) { unsigned c = 0; for (unsigned s = 0; s < 720; s++) if (vtoc_free(s)) c++; return c; }

static int sync_all(void) { int r; for (int k = 0; k < 4 && (r = fd_sync(&D, IMG)); k++) ; return r; }

#define FOLDER "/Atari"
static uint8_t A[100000], B[100000], C[100000];

int main(int argc, char **argv)
{
    uint32_t n;
    if (argc < 2 || diskio_host_open(argv[1]) || f_mount(&fs, "", 1)) { printf("cannot open the image\n"); return 2; }

    // ---- 1. building ----
    f_mkdir(FOLDER);
    fill(A, 3000, 1); put_file(FOLDER "/HELLO.TXT", A, 3000);
    fill(B, 0, 2);    put_file(FOLDER "/EMPTY", B, 0);
    fill(C, 125, 3);  put_file(FOLDER "/prog.lst", C, 125);
    put_file(FOLDER "/Read me.txt", A, 10);                    // not 8.3
    put_file(FOLDER "/TOOLONGNAME.TXT", A, 10);
    put_file(FOLDER "/A.TEXT", A, 10);
    put_file(FOLDER "/1ABC.TXT", A, 10);                       // first not a letter
    put_file(FOLDER "/.HIDDEN", A, 10);
    f_mkdir(FOLDER "/SUB");                                    // folders are ignored
    fill(B, 99000, 4); put_file(FOLDER "/ZBIG.DAT", B, 99000); // 792 sectors: does not fit
    int r = fd_build(&D, IMG, FOLDER);
    CHECK(r == 0 && D.shown == 3 && D.skipped == 6, "build: 3 shown, 6 left out (r=%d shown %d skipped %d)", r, D.shown, D.skipped);
    CHECK(D.nfree == 707 - 24 - 1 - 1 && SEC(360)[0] == 2 && (SEC(360)[3] | SEC(360)[4] << 8) == D.nfree && vtoc_count() == D.nfree,
          "build: VTOC (free %d, bitmap %u)", D.nfree, vtoc_count());
    CHECK(!dos_read("HELLO.TXT", C, &n) && n == 3000 && !memcmp(C, A, 3000), "build: DOS reads HELLO.TXT back");
    CHECK(!dos_read("EMPTY", C, &n) && n == 0, "build: an empty file");
    fill(C, 125, 3);
    CHECK(!dos_read("PROG.LST", B, &n) && n == 125 && !memcmp(B, C, 125), "build: prog.lst shows as PROG.LST, one full sector");
    CHECK(SEC(1)[1] == 1 && SEC(1)[6] == 0x18, "build: the boot sector boots nothing");
    CHECK(strcmp((char *)ent(0) + 5, "") && ent(0)[0] == 0x42 && ent(3)[0] == 0, "build: entries in name order, then free");

    // ---- 2. a new file from the Atari ----
    fill(A, 5000, 9);
    CHECK(dos_save("NEW.BAS", A, 5000) == 0, "atari: SAVE NEW.BAS");
    CHECK(D.pending, "pending after the save");
    r = fd_sync(&D, IMG);
    CHECK(r == 0 && !D.pending && card_is(FOLDER "/NEW.BAS", A, 5000), "sync: NEW.BAS in the folder (r=%d)", r);
    CHECK(!card_has(FOLDER "/.A816TMP"), "sync: no temporary file left");

    // ---- 3. overwrite (bigger), keeps the folder's case ----
    fill(B, 20000, 10);
    CHECK(dos_save("PROG.LST", B, 20000) == 0 && sync_all() == 0 && card_is(FOLDER "/prog.lst", B, 20000),
          "overwrite: prog.lst replaced (20000 bytes)");
    { DIR dj; FILINFO fi; int lower = 0; f_opendir(&dj, FOLDER);
      while (!f_readdir(&dj, &fi) && fi.fname[0]) if (!strcmp(fi.fname, "prog.lst")) lower = 1;
      f_closedir(&dj); CHECK(lower, "overwrite: the name keeps its case"); }

    // ---- 4. delete, 5. rename, 6. lock ----
    CHECK(dos_delete("EMPTY") == 0 && sync_all() == 0 && !card_has(FOLDER "/EMPTY"), "delete: EMPTY gone from the folder");
    fill(A, 3000, 1);
    CHECK(dos_rename("HELLO.TXT", "GREET.TXT") == 0 && sync_all() == 0 && !card_has(FOLDER "/HELLO.TXT")
          && card_is(FOLDER "/GREET.TXT", A, 3000), "rename: HELLO.TXT -> GREET.TXT");
    CHECK(dos_lock("GREET.TXT") == 0 && sync_all() == 0 && card_is(FOLDER "/GREET.TXT", A, 3000), "lock: nothing changes in the folder");

    // ---- 7. "reset" in the middle of saving over a file: the folder keeps the old one ----
    fill(A, 5000, 9);
    for (int stop = 0; stop < 46; stop += 3) {
        fill(C, 5000, 50 + stop);
        writes_left = stop;
        int e = dos_save("NEW.BAS", C, 5000);
        writes_left = -1;
        sync_all();
        if (!card_is(FOLDER "/NEW.BAS", e ? A : C, 5000)) { CHECK(0, "reset after %d writes: NEW.BAS damaged (e=%d)", stop, e); break; }
        if (!e) fill(A, 5000, 50 + stop);                 // (it went through: the new one is the old one now)
        if (stop >= 42) CHECK(1, "reset during an overwrite (after 0..45 sector writes): the folder has the old or the new file, whole");
        // the Atari is cold started: the disk is built again from the folder
        r = fd_build(&D, IMG, FOLDER);
    }
    CHECK(!card_has(FOLDER "/.A816TMP"), "reset: no temporary file left");
    // a new file, reset half way: nothing in the folder
    writes_left = 5;
    r = dos_save("HALF.DAT", B, 20000);
    writes_left = -1;
    CHECK(r == 138 && sync_all() == 0 && !card_has(FOLDER "/HALF.DAT"), "reset during a new file: nothing in the folder");
    r = fd_build(&D, IMG, FOLDER);

    // ---- 8. the Atari uses the drive during a save: stopped, then done ----
    fill(A, 30000, 77);
    dos_save("LONG.DAT", A, 30000);
    poll_n = 0; poll_bump = 20;
    r = fd_sync(&D, IMG);
    poll_bump = -1;
    CHECK(r == 1 && D.pending && !card_has(FOLDER "/LONG.DAT") && !card_has(FOLDER "/.A816TMP"), "busy drive: the save stops, nothing left (r=%d)", r);
    CHECK(fd_sync(&D, IMG) == 0 && card_is(FOLDER "/LONG.DAT", A, 30000), "busy drive: saved on the next try");

    // ---- 9. Horizon has the file open: not replaced until it is closed ----
    fill(B, 900, 5);
    dos_save("LONG.DAT", B, 900);
    strcpy(busy_path, FOLDER "/LONG.DAT");
    r = fd_sync(&D, IMG);
    CHECK(r == 1 && D.pending && card_is(FOLDER "/LONG.DAT", A, 30000), "open in Horizon: left alone (r=%d)", r);
    busy_path[0] = 0;
    CHECK(fd_sync(&D, IMG) == 0 && card_is(FOLDER "/LONG.DAT", B, 900), "open in Horizon: replaced once closed");

    // ---- 10. a name the disk does not show is never overwritten ----
    fill(A, 1000, 33);
    CHECK(dos_save("ZBIG.DAT", A, 1000) == 0 && sync_all() == 0, "conflict: SAVE ZBIG.DAT on the Atari");
    fill(B, 99000, 4);
    CHECK(card_is(FOLDER "/ZBIG.DAT", B, 99000) && D.conflicts == 1 && !D.pending, "conflict: the folder's ZBIG.DAT kept, counted (%u)", (unsigned)D.conflicts);

    // ---- 11. update in place (the directory unchanged) ----
    fill(B, 900, 5); B[600] = 0xEE;
    CHECK(dos_poke("LONG.DAT", 600, 0xEE) == 0 && sync_all() == 0 && card_is(FOLDER "/LONG.DAT", B, 900), "update in place: saved");

    // ---- 12. rename onto a name deleted in the same pass ----
    fill(A, 3000, 1);
    dos_delete("NEW.BAS");
    dos_rename("GREET.TXT", "NEW.BAS");
    CHECK(sync_all() == 0 && !card_has(FOLDER "/GREET.TXT") && card_is(FOLDER "/NEW.BAS", A, 3000), "rename onto a deleted name");

    // ---- 13. full: 64 files, and a full disk ----
    wipe_dir(FOLDER);
    for (int i = 0; i < 70; i++) { char p[40]; snprintf(p, sizeof p, FOLDER "/F%02d.TXT", i); fill(A, 100, i); put_file(p, A, 100); }
    r = fd_build(&D, IMG, FOLDER);
    CHECK(D.shown == 64 && D.skipped == 6 && dos_count() == 64, "64 files at most (shown %d, skipped %d)", D.shown, D.skipped);
    CHECK(dos_save("MORE.TXT", A, 10) == 169 && sync_all() == 0 && !card_has(FOLDER "/MORE.TXT"), "directory full: DOS says so, nothing saved");
    CHECK(dos_delete("F00.TXT") == 0 && dos_save("MORE.TXT", A, 10) == 0 && sync_all() == 0 && card_is(FOLDER "/MORE.TXT", A, 10)
          && !card_has(FOLDER "/F00.TXT"), "a file deleted, another saved in its entry");
    wipe_dir(FOLDER);
    fill(A, 60000, 1); put_file(FOLDER "/A1.DAT", A, 60000);
    r = fd_build(&D, IMG, FOLDER);
    fill(B, 40000, 2);
    r = dos_save("B1.DAT", B, 40000);                       // 707 - 480 = 227 sectors free: 28375 bytes
    CHECK(r == 162 && sync_all() == 0 && !card_has(FOLDER "/B1.DAT") && card_is(FOLDER "/A1.DAT", A, 60000), "disk full: nothing saved, A1.DAT whole");
    r = fd_build(&D, IMG, FOLDER);
    fill(B, 28375, 3);
    CHECK(dos_save("B1.DAT", B, 28375) == 0 && sync_all() == 0 && card_is(FOLDER "/B1.DAT", B, 28375) && vtoc_count() == 0,
          "a file that fills the disk exactly");
    r = fd_build(&D, IMG, FOLDER);
    CHECK(D.shown == 2 && D.nfree == 0, "built again: both files, 0 free");

    // ---- 14. a broken directory is left alone ----
    r = fd_build(&D, IMG, FOLDER);
    uint8_t save[128];
    memcpy(save, SEC(361), 128);
    uint8_t b[128];
    memcpy(b, SEC(361), 128);
    b[3] = 0x10; b[4] = 0x01;                               // A1.DAT's first sector: nonsense
    sio_write(361, b);
    r = sync_all();
    CHECK(r == 0 && card_is(FOLDER "/A1.DAT", A, 60000), "a broken chain: the folder's file left alone");
    memcpy(b, SEC(361), 128); b[0] = 0x00; b[16] = 0x00;     // the whole directory "gone" (as a FORMAT would leave it)
    sio_write(361, b);
    memset(b, 0, 128); sio_write(360, b);                    // no VTOC
    r = sync_all();
    CHECK(card_is(FOLDER "/A1.DAT", A, 60000) && card_has(FOLDER "/B1.DAT"), "no VTOC (a format): nothing deleted");

    f_unmount("");
    printf("RESULT %s\n", fails ? "FAIL" : "PASS");
    return fails ? 1 : 0;
}
