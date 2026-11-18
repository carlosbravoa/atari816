// SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
// Copyright (c) 2026 Carlos Bravo
// Host test of the firmware's PC link engine (core/firmware/pclink.c, compiled with
// -DPL_HOST): the engine talks through a pseudo terminal to the real Python gateway
// (tools/pclink.py), run by run_tests.py. The harness plays the board: it serves the
// developer channel (ECHO, SOURCE, SINK) and, once the session is up, runs PC volume
// requests against the gateway's shared folder and prints PASS / FAIL lines.
#define _XOPEN_SOURCE 700
#define _DEFAULT_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <termios.h>
#include <time.h>
#include "../../firmware/pclink.h"

static int fd;
static unsigned long drop_every;     // tests: lose one byte in every N received
static unsigned long nrx;

int host_rx(void)
{
    unsigned char c;
    for (;;) {
        if (read(fd, &c, 1) != 1) return -1;
        if (drop_every && ++nrx % drop_every == 0) continue;
        return c;
    }
}
void host_tx(uint8_t c)
{
    while (write(fd, &c, 1) != 1) usleep(100);
}
uint32_t host_ms(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (uint32_t)(t.tv_sec * 1000 + t.tv_nsec / 1000000);
}

#include "../../firmware/pclink.c"

static int sessions;
void pl_session(int up) { if (up) sessions++; printf("session %s\n", up ? "up" : "down"); fflush(stdout); }
void pl_idle(void) { usleep(50); }

static uint8_t outb[1024];
void pl_dev_request(const uint8_t *p, uint32_t n)
{
    static uint32_t sink_bytes;
    uint8_t h[4] = { (uint8_t)(p[0] | 0x80), p[1], 0, 0 };
    if (n < 4) return;
    switch (p[0]) {
    case 0x0F:                                         // ECHO
        memcpy(outb, p + 4, n - 4);
        pl_send(PL_CH_DEV, h, outb, n - 4);
        break;
    case 0x10: {                                       // SOURCE len u32
        uint32_t len = p[4] | p[5] << 8 | p[6] << 16 | (uint32_t)p[7] << 24, off = 0, x = 1;
        while (off < len) {
            uint32_t k = len - off > 1024 ? 1024 : len - off;
            for (uint32_t i = 0; i < k; i++) outb[i] = (uint8_t)(off + i);
            h[2] = off + k < len ? PL_RQ_MORE : 0;
            if (pl_send(PL_CH_DEV, h, outb, k)) break;
            off += k;
            (void)x;
        }
        break;
    }
    case 0x11:                                         // SINK
        sink_bytes += n - 4;
        if (!(p[2] & PL_RQ_MORE)) {
            uint8_t r[4] = { (uint8_t)sink_bytes, (uint8_t)(sink_bytes >> 8), (uint8_t)(sink_bytes >> 16), (uint8_t)(sink_bytes >> 24) };
            sink_bytes = 0;
            pl_send(PL_CH_DEV, h, r, 4);
        }
        break;
    default:
        h[3] = 0x82;
        pl_send(PL_CH_DEV, h, 0, 0);
    }
}

// ---- PC volume requests ----
static uint8_t got[70000];
static uint32_t gotn;
static void sink(const uint8_t *p, uint32_t n, void *ctx) { (void)ctx; if (gotn + n <= sizeof got) memcpy(got + gotn, p, n); gotn += n; }
static int fails;
#define CHECK(c, ...) do { if (c) printf("PASS "); else { printf("FAIL "); fails++; } printf(__VA_ARGS__); printf("\n"); fflush(stdout); } while (0)

static int call(uint8_t op, const void *a, uint32_t na, const void *w, uint32_t nw)
{
    gotn = 0;
    return pl_call(op, a, na, w, nw, sink, 0);
}

static void run_files(void)
{
    static uint8_t big[60000];
    for (unsigned i = 0; i < sizeof big; i++) big[i] = (uint8_t)(i * 7 + (i >> 9));
    uint8_t a[64];
    // OPEN /T.BIN create
    memset(a, 0, sizeof a); a[0] = 2; strcpy((char *)a + 4, "/T.BIN");
    int r = call(1, a, 4 + 7, 0, 0);
    CHECK(r == 0 && gotn >= 8, "open create (r=%d)", r);
    uint8_t h = got[0];
    memset(a, 0, 8); a[0] = h;
    r = call(4, a, 4, big, sizeof big);
    uint32_t wn = got[0] | got[1] << 8 | got[2] << 16 | (uint32_t)got[3] << 24;
    CHECK(r == 0 && wn == sizeof big, "write 60000 (r=%d n=%u)", r, wn);
    a[4] = 0; a[5] = a[6] = a[7] = 0;
    r = call(5, a, 8, 0, 0);
    CHECK(r == 0, "seek 0");
    a[4] = 0x60; a[5] = 0xEA; a[6] = 0; a[7] = 0;            // 60000
    r = call(3, a, 8, 0, 0);
    CHECK(r == 0 && gotn == sizeof big && !memcmp(got, big, sizeof big), "read back 60000 (r=%d n=%u)", r, gotn);
    a[0] = h;
    r = call(2, a, 4, 0, 0);
    CHECK(r == 0, "close");
    strcpy((char *)a, "/t.bin");
    r = call(6, a, 7, 0, 0);
    uint32_t sz = got[0] | got[1] << 8 | got[2] << 16 | (uint32_t)got[3] << 24;
    CHECK(r == 0 && sz == sizeof big && (got[4] & 0x10) == 0, "stat (case-insensitive) size %u attr %02x", sz, got[4]);
    r = call(8, "/SUB", 5, 0, 0);
    CHECK(r == 0, "mkdir");
    r = call(8, "/SUB", 5, 0, 0);
    CHECK(r == 8, "mkdir again: exists (r=%d)", r);
    memcpy(a, "/T.BIN\0/SUB/U.BIN", 18);
    r = call(10, a, 18, 0, 0);
    CHECK(r == 0, "rename into folder (r=%d)", r);
    a[0] = 0; a[1] = 0; a[2] = 0; a[3] = 4; strcpy((char *)a + 4, "/SUB");   // skip 0, room 1024
    r = call(7, a, 9, 0, 0);
    uint32_t cnt = got[0] | got[1] << 8;
    CHECK(r == 0 && cnt == 1 && got[9] == 5 && !memcmp(got + 10, "U.BIN", 5), "readdir (r=%d count %u)", r, cnt);
    r = call(0x10, "/SUB/U.BIN", 11, 0, 0);
    CHECK(r == 0 && gotn == sizeof big && !memcmp(got, big, sizeof big), "load (r=%d n=%u)", r, gotn);
    r = call(6, "/../etc/passwd", 15, 0, 0);
    CHECK(r == 6, "'..' refused (r=%d)", r);
    r = call(6, "/OUT/passwd", 12, 0, 0);
    CHECK(r == 7, "symlink out refused (r=%d)", r);
    r = call(9, "/SUB", 5, 0, 0);
    CHECK(r == 7, "delete non-empty folder refused (r=%d)", r);
    r = call(9, "/SUB/U.BIN", 11, 0, 0);
    CHECK(r == 0, "delete file");
    r = call(9, "/SUB", 5, 0, 0);
    CHECK(r == 0, "delete folder");
    r = call(6, "/NOPE", 6, 0, 0);
    CHECK(r == 4, "stat missing: no file (r=%d)", r);
    // a big transfer for speed (host pty: no meaning for the board)
    uint32_t t0 = host_ms();
    memset(a, 0, sizeof a); a[0] = 2; strcpy((char *)a + 4, "/SPEED.BIN");
    r = call(1, a, 4 + 11, 0, 0); h = got[0];
    for (int i = 0; i < 10; i++) { memset(a, 0, 8); a[0] = h; call(4, a, 4, big, sizeof big); }
    a[0] = h; call(2, a, 4, 0, 0);
    printf("INFO 600000 bytes written in %u ms\n", host_ms() - t0);
}

int main(int argc, char **argv)
{
    fd = posix_openpt(O_RDWR | O_NOCTTY);
    grantpt(fd); unlockpt(fd);
    struct termios t;
    int sfd = open(ptsname(fd), O_RDWR | O_NOCTTY);         // set raw mode on the slave side
    tcgetattr(sfd, &t); cfmakeraw(&t); tcsetattr(sfd, TCSANOW, &t);
    close(sfd);
    fcntl(fd, F_SETFL, O_NONBLOCK);
    printf("PTY %s\n", ptsname(fd));
    fflush(stdout);
    if (argc > 1) drop_every = strtoul(argv[1], 0, 0);
    pl_init();
    uint32_t t0 = host_ms(), done = 0;
    for (;;) {
        pl_poll();
        if (!done && pl_files()) { run_files(); done = 1; printf("FILES DONE %d\n", fails); fflush(stdout); }
        if (host_ms() - t0 > 120000) break;
        usleep(20);
    }
    return fails != 0;
}
