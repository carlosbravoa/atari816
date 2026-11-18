// SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
// Copyright (c) 2026 Carlos Bravo
// pcnet.c - the internet through the PC link (step 2): streams on channel 4 (Net: TCP
// connections, "tcp://host:port", "tls://host:port") and channel 5 (Fetch: "http://...",
// "https://...", "ftp://..." read as files). Protocol and mailbox rules: Docs/04-pc-link.md,
// "Channels 4 and 5" and "What the 65C816 sees (step 2)".
//
// Each stream keeps NS_RING bytes in SDRAM; the PC never sends more than the credit the board
// gave (the ring's room), so the board is never flooded. A request that has to wait for the
// internet (OPEN, STAT, a READ of a URL) is put aside: the request ring moves on, other
// requests are served meanwhile, and ns_service() writes its answer when it is due (answers
// are matched by TAG).
//
// All of this is cold (SDRAM): it runs only when a frame comes, a mailbox op is served or
// ns_work is set. The data copies use the hot helpers (memcpy, ns_put816 = pc_put816).
// Build on a PC with -DPL_HOST for the host test (core/test/pclink_host).

#include "pclink.h"
#include "pcnet.h"

#ifdef PL_HOST
#include <string.h>
uint32_t host_ms(void);
#define NOW()       host_ms()
#define SDBUF
#else
#include "picorv32.h"
#include "string.h"
#define NOW()       time_millis()
#define SDBUF       __attribute__((section(".sdbuf")))
#endif

// stream ops (payload byte 0)
#define S_OPEN      0x01
#define S_SEND      0x02
#define S_CREDIT    0x03
#define S_CLOSE     0x04
#define S_OPENED    0x81
#define S_DATA      0x82
#define S_SCREDIT   0x83
#define S_END       0x84

// stream states
#define ST_FREE     0
#define ST_OPENING  1           // OPEN sent, no OPENED yet
#define ST_OPEN     2
#define ST_ENDED    3           // END 0: the whole body / the other end closed
#define ST_FAILED   4           // an error (err)
#define ST_LOST     5           // the session ended

// what a request put aside waits for
#define P_NONE      0
#define P_OPEN      1
#define P_STAT      2
#define P_READ      3

typedef struct {
    uint8_t  st, ch, sid, err, claimed, armed, pend, gen;
    uint16_t status;
    uint32_t size, head, tail, freed, scredit, ep, t;
    uint32_t pbuf, plen, pdone, pt;         // the request put aside: buffer, length, done, since
    uint8_t  m[16];
} ns_t;

static ns_t     ns[NS_N] SDBUF;
static uint8_t  ring[NS_N][NS_RING] SDBUF;
static char     url[NS_N][128] SDBUF;       // a URL's stream: its path (STAT -> OPEN reuse)
volatile uint8_t ns_work;
uint8_t  ns_npend;
static uint8_t  ns_ready;

static uint32_t le32(const uint8_t *p) { return p[0] | p[1] << 8 | p[2] << 16 | (uint32_t)p[3] << 24; }

static void ns_init(void)
{
    if (ns_ready) return;
    memset(ns, 0, sizeof ns);
    ns_ready = 1;
}

// "scheme://" with a letter-only scheme: 1 http/https/ftp, 2 tcp/tls, 0 not a URL
static int scheme(const char *p, int *tls)
{
    int n = 0;
    char s[8];
    while (n < 7 && ((p[n] | 0x20) >= 'a' && (p[n] | 0x20) <= 'z')) { s[n] = p[n] | 0x20; n++; }
    if (n < 2 || p[n] != ':' || p[n + 1] != '/' || p[n + 2] != '/') return 0;
    s[n] = 0;
    if (tls) *tls = !strcmp(s, "tls");
    if (!strcmp(s, "tcp") || !strcmp(s, "tls")) return 2;
    return 1;                                            // (the PC says if it knows the scheme)
}
int ns_kind(const char *path) { return scheme(path, 0); }

// the service for a kind: 0 OK, else the result
static uint32_t svc_ok(int kind)
{
    if (!pl_up()) return PL_E_NOLINK;
    return (pl_svc() & (kind == 2 ? PL_SV_NET : PL_SV_FETCH)) ? 0 : NS_E_NOSVC;
}

static void ns_free(int s)
{
    ns_t *x = &ns[s];
    if (x->pend) ns_npend--;
    x->st = ST_FREE; x->pend = P_NONE; x->claimed = 0; url[s][0] = 0;
}

static void send_close(int s)
{
    ns_t *x = &ns[s];
    if ((x->st == ST_OPENING || x->st == ST_OPEN) && x->ep == pl_epoch()) {
        uint8_t h[4] = { S_CLOSE, x->sid, 0, 0 };
        pl_send(x->ch, h, 0, 0);
    }
}

// a free stream (or one a STAT kept that nobody claimed and nobody waits on), -1: none
static int ns_alloc(void)
{
    for (int s = 0; s < NS_N; s++) if (ns[s].st == ST_FREE) return s;
    for (int s = 0; s < NS_N; s++)
        if (!ns[s].claimed && !ns[s].pend) { send_close(s); ns_free(s); return s; }
    return -1;
}

// OPEN on the PC: 0 sent, else the result
static uint32_t ns_start(int s, int ch, const uint8_t *data, uint32_t n)
{
    ns_t *x = &ns[s];
    x->gen = (x->gen + 1) % 63;
    x->sid = (uint8_t)(1 + s + 4 * x->gen);
    x->ch = ch; x->st = ST_OPENING; x->err = 0; x->status = 0; x->size = 0xFFFFFFFF;
    x->head = x->tail = x->freed = x->scredit = 0;
    x->claimed = 0; x->armed = 0; x->pend = P_NONE;
    x->ep = pl_epoch(); x->t = NOW();
    uint8_t h[4] = { S_OPEN, x->sid, 0, 0 };
    if (pl_send3(ch, h, 4, data, n)) { x->st = ST_FREE; return PL_E_LOST; }
    return 0;
}

static void put_aside(int s, int kind, const uint8_t *m)
{
    ns_t *x = &ns[s];
    memcpy(x->m, m, 16);
    x->pend = kind; x->pt = NOW();
    ns_npend++;
}

// the URL's stream a STAT left (not claimed, nobody waiting), -1: none
static int ns_find_url(const char *path)
{
    for (int s = 0; s < NS_N; s++)
        if (ns[s].st != ST_FREE && ns[s].ch == PL_CH_FETCH && !ns[s].claimed && !ns[s].pend &&
            ns[s].ep == pl_epoch() && NOW() - ns[s].t < NS_T_KEEP && !strcmp(url[s], path)) return s;
    return -1;
}

// a URL's stream: the one a STAT left, or a new one (OPEN sent). -1 with *res set: failed.
static int fetch_stream(const char *path, uint32_t *res)
{
    int s = ns_find_url(path);
    if (s >= 0) return s;
    uint32_t n = strlen(path);
    if (n > 127) { *res = NS_E_ADDR; return -1; }
    if ((s = ns_alloc()) < 0) { *res = 18; return -1; }   // FR_TOO_MANY_OPEN_FILES
    static uint8_t d[4 + 128] SDBUF;
    d[0] = NS_RING & 0xFF; d[1] = NS_RING >> 8; d[2] = d[3] = 0;
    memcpy(d + 4, path, n + 1);
    if ((*res = ns_start(s, PL_CH_FETCH, d, 4 + n + 1))) return -1;
    memcpy(url[s], path, n + 1);
    return s;
}

int ns_open(const char *path, const uint8_t *m, uint32_t *res, uint32_t *val)
{
    int tls = 0, kind = scheme(path, &tls), s;
    ns_init();
    *val = 0;
    if ((*res = svc_ok(kind))) return NS_NOW;
    if (kind == 1) {
        if (m[7] & 3) { *res = 7; return NS_NOW; }       // FR_DENIED: read only
        if ((s = fetch_stream(path, res)) < 0) return NS_NOW;
        ns[s].claimed = 1;
        if (ns[s].st == ST_OPENING) { put_aside(s, P_OPEN, m); return NS_LATER; }
        ns_work = 1;                                     // (answered by ns_service, below)
        put_aside(s, P_OPEN, m);
        return NS_LATER;
    }
    // tcp://host:port, tls://host:port
    const char *h = path + 6;                            // after "tcp://"
    const char *c = strrchr(h, ':');
    uint32_t port = 0, hl = c ? (uint32_t)(c - h) : 0;
    if (c) for (const char *q = c + 1; *q; q++) {
        if (*q < '0' || *q > '9' || port > 65535) { port = 0; break; }
        port = port * 10 + (*q - '0');
    }
    if (!hl || hl > 100 || !port || port > 65535) { *res = NS_E_ADDR; return NS_NOW; }
    if ((s = ns_alloc()) < 0) { *res = 18; return NS_NOW; }
    uint8_t d[5 + 101];
    d[0] = NS_RING & 0xFF; d[1] = NS_RING >> 8; d[2] = port; d[3] = port >> 8; d[4] = tls;
    memcpy(d + 5, h, hl); d[5 + hl] = 0;
    if ((*res = ns_start(s, PL_CH_NET, d, 5 + hl + 1))) return NS_NOW;
    ns[s].claimed = 1;
    put_aside(s, P_OPEN, m);
    return NS_LATER;
}

int ns_stat(const char *path, uint32_t buf, const uint8_t *m, uint32_t *res, uint32_t *val)
{
    int s;
    ns_init();
    *val = 0;
    if (scheme(path, 0) != 1) { *res = 0x82; return NS_NOW; }
    if ((*res = svc_ok(1))) return NS_NOW;
    if ((s = fetch_stream(path, res)) < 0) return NS_NOW;
    ns[s].pbuf = buf;
    put_aside(s, P_STAT, m);
    ns_work = 1;                                         // (answered by ns_service)
    return NS_LATER;
}

// ring -> 65C816 memory, at most n bytes: the count
static uint32_t ns_out(int s, uint32_t dst, uint32_t n)
{
    ns_t *x = &ns[s];
    uint32_t got = 0;
    while (got < n && x->tail != x->head) {
        uint32_t o = x->tail % NS_RING, k = x->head - x->tail;
        if (k > NS_RING - o) k = NS_RING - o;
        if (k > n - got) k = n - got;
        if (!ns_put816(dst + got, ring[s] + o, k)) break;
        x->tail += k; got += k;
    }
    x->freed += got;
    return got;
}

// give credit back once a step's worth was read
static void ns_credit(int s)
{
    ns_t *x = &ns[s];
    if (x->st != ST_OPEN || x->freed < NS_STEP || x->ep != pl_epoch()) return;
    uint32_t k = x->freed;
    uint8_t h[4] = { S_CREDIT, x->sid, 0, 0 }, d[2] = { k, k >> 8 };
    x->freed = 0;
    if (pl_send3(x->ch, h, 4, d, 2)) x->freed += k;
}

static uint32_t st_result(ns_t *x) { return x->st == ST_LOST ? PL_E_LOST : x->err; }

static int handle_slot(int h)
{
    int s = h - NS_H0;
    return (s >= 0 && s < NS_N && ns_ready && ns[s].st != ST_FREE && ns[s].claimed) ? s : -1;
}

int ns_read(int h, uint32_t buf, uint32_t len, const uint8_t *m, uint32_t *res, uint32_t *val)
{
    int s = handle_slot(h);
    *res = 0; *val = 0;
    if (s < 0) { *res = 0x80; return NS_NOW; }
    ns_t *x = &ns[s];
    if (x->st == ST_OPEN && x->ep != pl_epoch()) x->st = ST_LOST;
    uint32_t got = ns_out(s, buf, len);
    *val = got;
    if (x->ch == PL_CH_NET) {
        x->armed = 1;
        if (!got && x->st == ST_ENDED) *res = NS_E_CLOSED;
        else if (!got && x->st >= ST_FAILED) *res = st_result(x);
        ns_credit(s);
        return NS_NOW;
    }
    if (got < len && x->st == ST_OPEN) {                 // a URL: wait for the rest
        x->pbuf = buf; x->plen = len; x->pdone = got;
        put_aside(s, P_READ, m);
        ns_credit(s);
        return NS_LATER;
    }
    if (x->st >= ST_FAILED) *res = st_result(x);
    ns_credit(s);
    return NS_NOW;
}

void ns_write(int h, uint32_t buf, uint32_t len, uint32_t *res, uint32_t *val)
{
    int s = handle_slot(h);
    *res = 0; *val = 0;
    if (s < 0) { *res = 0x80; return; }
    ns_t *x = &ns[s];
    if (x->ch != PL_CH_NET) { *res = 7; return; }
    if (x->st == ST_OPEN && x->ep != pl_epoch()) x->st = ST_LOST;
    if (x->st == ST_ENDED) { *res = NS_E_CLOSED; return; }
    if (x->st != ST_OPEN) { *res = st_result(x); return; }
    uint32_t sent = 0;
    while (sent < len && x->scredit) {
        uint32_t k = len - sent;
        if (k > 1024) k = 1024;
        if (k > x->scredit) k = x->scredit;
        const volatile uint8_t *p = ns_ptr816(buf + sent, k);
        if (!p) { if (!sent) *res = 0x81; break; }
        uint8_t hd[4] = { S_SEND, x->sid, 0, 0 };
        if (pl_send3(x->ch, hd, 4, p, k)) { x->st = ST_LOST; if (!sent) *res = PL_E_LOST; break; }
        sent += k; x->scredit -= k;
    }
    *val = sent;
}

uint32_t ns_close(int h)
{
    int s = handle_slot(h);
    if (s < 0) return 0x80;
    send_close(s);
    ns_free(s);
    return 0;
}

void ns_close_all(void)
{
    if (!ns_ready) return;
    for (int s = 0; s < NS_N; s++) if (ns[s].st != ST_FREE) { send_close(s); ns_free(s); }
    ns_npend = 0;
}

static void news(int s)                                  // the event, if the program has read
{
    ns_t *x = &ns[s];
    ns_work = 1;
    if (x->ch == PL_CH_NET && x->claimed && x->armed) { x->armed = 0; ns_event(NS_H0 + s); }
}

// a DATA frame on channel 4 or 5 (from pclink.c's receive path, also while it waits: no sends)
void ns_frame(int ch, const uint8_t *p, uint32_t n)
{
    if (n < 4 || !ns_ready) return;
    int s;
    for (s = 0; s < NS_N; s++)
        if (ns[s].st != ST_FREE && ns[s].ch == ch && ns[s].sid == p[1]) break;
    if (s == NS_N) return;                               // a stream that is gone
    ns_t *x = &ns[s];
    switch (p[0]) {
    case S_OPENED:
        if (x->st != ST_OPENING) break;
        if (n >= 10) x->status = p[8] | p[9] << 8;
        if (p[3]) { x->st = ST_FAILED; x->err = p[3]; }
        else {
            x->st = ST_OPEN;
            if (n >= 8) x->size = le32(p + 4);
            if (n >= 12) x->scredit = p[10] | p[11] << 8;
        }
        news(s);
        break;
    case S_DATA: {
        if (x->st != ST_OPEN) break;
        p += 4; n -= 4;
        if (x->pend == P_READ && x->pdone < x->plen) {   // straight into the waiting READ
            uint32_t k = x->plen - x->pdone;
            if (k > n) k = n;
            if (x->tail == x->head && ns_put816(x->pbuf + x->pdone, p, k)) {
                x->pdone += k; x->freed += k; p += k; n -= k;
            }
        }
        while (n && x->head - x->tail < NS_RING) {       // the rest into the ring
            uint32_t o = x->head % NS_RING, k = NS_RING - o;
            if (k > n) k = n;
            if (k > NS_RING - (x->head - x->tail)) k = NS_RING - (x->head - x->tail);
            memcpy(ring[s] + o, p, k);
            x->head += k; p += k; n -= k;
        }
        if (x->pend == P_READ) x->pt = NOW();            // (progress: the 40 s start again)
        news(s);
        break;
    }
    case S_SCREDIT:
        if (n >= 6) x->scredit += p[4] | p[5] << 8;
        break;
    case S_END:
        if (x->st != ST_OPEN && x->st != ST_OPENING) break;
        x->st = p[3] ? ST_FAILED : ST_ENDED;
        x->err = p[3];
        news(s);
        break;
    }
}

void ns_session(int up)
{
    (void)up;
    if (!ns_ready) return;
    for (int s = 0; s < NS_N; s++)
        if (ns[s].st != ST_FREE && ns[s].ep != pl_epoch() && ns[s].st != ST_LOST) {
            ns[s].st = ST_LOST;
            news(s);
        }
}

// write the answer of the request put aside on stream s; 1 = done
static int answer(int s, uint32_t res, uint32_t val)
{
    ns_t *x = &ns[s];
    uint8_t *m = x->m;
    m[0] |= 0x80;
    m[8] = res; m[9] = res >> 8; m[10] = res >> 16; m[11] = res >> 24;
    m[12] = val; m[13] = val >> 8; m[14] = val >> 16; m[15] = val >> 24;
    if (!ns_answer(m)) { m[0] &= 0x7F; ns_work = 1; return 0; }
    x->pend = P_NONE;
    ns_npend--;
    return 1;
}

void ns_service(void)
{
    ns_work = 0;
    if (!ns_ready) return;
    uint32_t now = NOW();
    for (int s = 0; s < NS_N; s++) {
        ns_t *x = &ns[s];
        if (x->st == ST_FREE) continue;
        if (x->st != ST_LOST && x->ep != pl_epoch()) x->st = ST_LOST;
        int late = x->pend && now - x->pt > NS_T_WAIT;
        switch (x->pend) {
        case P_OPEN:
            if (x->st == ST_OPEN || x->st == ST_ENDED) {
                if (answer(s, 0, NS_H0 + s)) x->armed = 1;
            } else if (x->st >= ST_FAILED) {
                if (answer(s, st_result(x), x->status)) ns_free(s);
            } else if (late) {
                if (answer(s, NS_E_TIME, 0)) { send_close(s); ns_free(s); }
            }
            continue;
        case P_STAT:
            if (x->st == ST_OPEN || x->st == ST_ENDED) {
                uint32_t z = x->size == 0xFFFFFFFF ? 0 : x->size, t = ns_fattime();
                uint8_t o[9] = { z, z >> 8, z >> 16, z >> 24, 0x21, t, t >> 8, t >> 16, t >> 24 };
                uint32_t r = ns_put816(x->pbuf, o, 9) ? 0 : 0x81;
                if (answer(s, r, z)) x->t = now;         // kept for an OPEN (15 s)
            } else if (x->st >= ST_FAILED) {
                if (answer(s, st_result(x), x->status)) ns_free(s);
            } else if (late) {
                if (answer(s, NS_E_TIME, 0)) { send_close(s); ns_free(s); }
            }
            continue;
        case P_READ:
            if (x->pdone < x->plen) x->pdone += ns_out(s, x->pbuf + x->pdone, x->plen - x->pdone);
            if (x->pdone == x->plen || x->st == ST_ENDED) {
                answer(s, 0, x->pdone);
            } else if (x->st >= ST_FAILED) {
                answer(s, st_result(x), x->pdone);
            } else if (late) {
                answer(s, NS_E_TIME, x->pdone);
            }
            ns_credit(s);
            continue;
        }
        if (!x->claimed && now - x->t > NS_T_KEEP) { send_close(s); ns_free(s); continue; }
        ns_credit(s);
    }
}
