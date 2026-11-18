// SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
// Copyright (c) 2026 Carlos Bravo
// pclink.c - the PC link engine: frames, acknowledgements, sessions, the log channel and
// the PC volume client. The protocol is described in Docs/04-pc-link.md.
//
// Frame (all multi-byte fields little-endian):
//   A8 16 | LEN(2) CHAN SEQ ACK FLAGS HCHK | payload (LEN bytes) | CRC(2)
//   HCHK = low byte of the CRC-16/CCITT-FALSE of LEN..FLAGS; CRC = the same CRC of LEN..payload.
// One reliable (DATA) frame per channel and direction is in flight at a time (stop and wait);
// the firmware's own sends are synchronous. Received frames are acknowledged at once.
//
// Hot (block RAM): the receive path that the main loop calls (pl_poll), the CRC and the
// transmit loop. Everything else runs from SDRAM (cold): it only runs while frames come or go.
// Build on a PC with -DPL_HOST for the host test (core/firmware/test/pclink_host.c).

#include "pclink.h"
#include "pcnet.h"

#ifdef PL_HOST
#include <string.h>
int      host_rx(void);                 // -1 = nothing
void     host_tx(uint8_t c);
uint32_t host_ms(void);
#define HW_RX()     host_rx()
#define HW_TX(c)    host_tx(c)
#define NOW()       host_ms()
#define HOT
#define HOTDATA
#define SDBUF
#else
#include "picorv32.h"
#define reg_blrx_div (*(volatile uint32_t *)0x020000c4)
static inline int hw_rx(void) { uint32_t v = reg_blrx; return (v & 0x100) ? (int)(v & 0xFF) : -1; }
#define HW_RX()     hw_rx()
#define HW_TX(c)    (reg_uart_data = (c))
#define NOW()       time_millis()
#define HOT         __attribute__((section(".text.hot")))
#define SDBUF       __attribute__((section(".sdbuf")))
#define HOTDATA     __attribute__((section(".data.hot")))   // read-only, but in block RAM
#include "string.h"
#endif

// control datagram ops (channel 0, payload byte 0)
#define C_HELLO     0x01    // PC -> board
#define C_HELLO_ACK 0x02    // board -> PC
#define C_PING      0x03    // PC -> board
#define C_PONG      0x04    // board -> PC
#define C_BYE       0x05    // either way
#define C_NOSESSION 0x06    // board -> PC: DATA or PING without a session
#define C_BOOT      0x07    // board -> PC: the firmware has just started

#define T_RETRY     250     // ms without an ACK: send the frame again
#define N_RETRY     14      // tries before the link is declared down (3.5 s)
#define T_SILENT    3500    // ms without any frame from the PC: the link is down
#define T_CALL      30000   // ms without progress on a PC volume request: lost
#define T_GAP       100     // ms between two bytes of one frame: start over

// ---- CRC-16/CCITT-FALSE (poly 0x1021, init 0xFFFF), a byte at a time, kept as two bytes h, l.
// The byte table T[x] is split by nibbles (the CRC is linear: T[x] = T[x & $F0] ^ T[x & $0F]):
// four 16-byte tables, 64 bytes of block RAM instead of 512, and only one 4-bit shift a byte
// (the PicoRV32 here has no barrel shifter: a shift costs a cycle per bit) ----
static const uint8_t crc_hh[16] HOTDATA = { 0x00, 0x12, 0x24, 0x36, 0x48, 0x5A, 0x6C, 0x7E, 0x91, 0x83, 0xB5, 0xA7, 0xD9, 0xCB, 0xFD, 0xEF };
static const uint8_t crc_hl[16] HOTDATA = { 0x00, 0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70, 0x81, 0x91, 0xA1, 0xB1, 0xC1, 0xD1, 0xE1, 0xF1 };
static const uint8_t crc_lh[16] HOTDATA = { 0x00, 0x31, 0x62, 0x53, 0xC4, 0xF5, 0xA6, 0x97, 0x88, 0xB9, 0xEA, 0xDB, 0x4C, 0x7D, 0x2E, 0x1F };
static const uint8_t crc_ll[16] HOTDATA = { 0x00, 0x21, 0x42, 0x63, 0x84, 0xA5, 0xC6, 0xE7, 0x08, 0x29, 0x4A, 0x6B, 0x8C, 0xAD, 0xCE, 0xEF };
#define CRC(h, l, b) do { uint32_t x_ = (uint8_t)((h) ^ (b)), u_ = x_ >> 4, v_ = x_ & 15;      \
        (h) = (l) ^ crc_hh[u_] ^ crc_hl[v_]; (l) = crc_lh[u_] ^ crc_ll[v_]; } while (0)

// ---- state ----
static uint8_t  up, svc;                       // session up; the PC's services
static uint32_t epoch, last_rx, pc_t0, pc_ms;
static uint8_t  tx_seq[PL_NCH], rx_last[PL_NCH], acked[PL_NCH];
static uint8_t  nested;                        // inside a wait (a send or a call)
static uint32_t n_rx, n_bad, n_retry;

// receive: the frame from LEN on
static uint8_t  rxf[7 + PL_MAXPAY + 2];
static uint16_t rxn, rxlen, rxend;
static uint8_t  rxst, rxhc, rxh, rxl;          // rxh, rxl: the CRC so far
static uint32_t rx_t;

// a developer request that came while the firmware was waiting (handled afterwards)
static uint8_t  park[PL_MAXPAY] SDBUF;
static uint16_t parkn;
static uint8_t  parked;

// the PC volume request in progress
static uint8_t  fw_tag, fw_op, fw_done, fw_res, fw_ctr;
static pl_sink_t fw_sink;
static void    *fw_ctx;
static uint32_t fw_t;

// the log line being collected
static char     logb[120];
static uint8_t  logn;

int      pl_up(void)       { return up; }
int      pl_files(void)    { return up && (svc & PL_SV_FILES); }
int      pl_svc(void)      { return up ? svc : 0; }
uint32_t pl_epoch(void)    { return epoch; }
uint32_t pl_rx_bytes(void) { return n_rx; }
uint32_t pl_rx_bad(void)   { return n_bad; }
uint32_t pl_retries(void)  { return n_retry; }
uint32_t pl_pc_time(void)  { return pc_t0 ? pc_t0 + (NOW() - pc_ms) / 1000 : 0; }

// ---- transmit ----
// One frame: hdr (nh bytes, block RAM), then a (na bytes), then d (nd bytes, any memory).
HOT static void tx_frame(int ch, uint8_t seq, uint8_t ack, uint8_t fl,
                         const uint8_t *a, uint32_t na, const volatile uint8_t *d, uint32_t nd)
{
    uint32_t len = na + nd;
    uint8_t  h[7] = { (uint8_t)len, (uint8_t)(len >> 8), (uint8_t)ch, seq, ack, fl, 0 };
    uint8_t  ch_ = 0xFF, cl = 0xFF;
    for (int i = 0; i < 6; i++) CRC(ch_, cl, h[i]);
    h[6] = cl;
    CRC(ch_, cl, h[6]);
    HW_TX(0xA8);
    HW_TX(0x16);
    for (int i = 0; i < 7; i++) HW_TX(h[i]);
    for (uint32_t i = 0; i < na; i++) { uint8_t b = a[i]; CRC(ch_, cl, b); HW_TX(b); }
    uintptr_t wa = 1;                          // d is read in 32-bit words (SDRAM: fewer accesses)
    uint32_t w = 0;
    for (uint32_t i = 0; i < nd; i++) {
        uintptr_t a = (uintptr_t)(d + i);
        if ((a & ~(uintptr_t)3) != wa) { wa = a & ~(uintptr_t)3; w = *(const volatile uint32_t *)wa; }
        uint8_t b = (uint8_t)(w >> ((a & 3) * 8));
        CRC(ch_, cl, b);
        HW_TX(b);
    }
    HW_TX(cl);
    HW_TX(ch_);
}

static void tx_ack(int ch, uint8_t seq) { tx_frame(ch, 0, seq, PL_F_ACK, 0, 0, 0, 0); }
static void tx_ctl(const uint8_t *p, uint32_t n) { tx_frame(PL_CH_CTL, 0, 0, 0, p, n, 0, 0); }
static void tx_ctl1(uint8_t op) { tx_ctl(&op, 1); }

HOT void pl_log_putc(int c)
{
    if (c != '\n') logb[logn++] = (char)c;
    if (c == '\n' || logn == sizeof logb) {
        if (logn) tx_frame(PL_CH_LOG, 0, 0, 0, (const uint8_t *)logb, logn, 0, 0);
        logn = 0;
    }
}

// ---- receive ----
// Bytes from the FIFO into rxf. 1 = a complete frame with a good CRC is in rxf.
HOT static int rx_drain(void)
{
    int got = 0;
    uint32_t n = rxn;                          // (in registers: the payload loop is the hot one)
    uint8_t  ch_ = rxh, cl = rxl;
    for (;;) {
        int v = HW_RX();
        if (v < 0) break;
        uint8_t b = (uint8_t)v;
        got = 1;
        n_rx++;
        switch (rxst) {
        case 0:
            if (b == 0xA8) rxst = 1;
            break;
        case 1:
            if (b == 0x16) { rxst = 2; n = 0; ch_ = cl = 0xFF; rx_t = NOW(); }
            else if (b != 0xA8) rxst = 0;
            break;
        case 2:
            rxf[n++] = b;
            if (n < 7) { CRC(ch_, cl, b); if (n == 6) rxhc = cl; break; }
            rxlen = rxf[0] | rxf[1] << 8;
            if (b != rxhc || rxlen > PL_MAXPAY || rxf[2] >= PL_NCH) { rxst = 0; n_bad++; break; }
            CRC(ch_, cl, b);
            rxend = 7 + rxlen + 2;
            rxst = 3;
            break;
        default: {
            rxf[n++] = b;
            uint32_t end = 7 + rxlen;
            if (n <= end) {
                CRC(ch_, cl, b);
                uint32_t n0 = n;
                while (n < end) {                  // the rest of the payload, as long as it is there
                    if ((v = HW_RX()) < 0) break;
                    rxf[n++] = (uint8_t)v;
                    CRC(ch_, cl, (uint32_t)v);
                }
                n_rx += n - n0;
                if (n < end) goto out;
            } else if (n == rxend) {
                rxst = 0;
                if (rxf[rxend - 2] == cl && rxf[rxend - 1] == ch_) {
                    rxh = ch_; rxl = cl; rxn = n;
                    return 1;
                }
                n_bad++;
            }
            break;
        }
        }
    }
out:
    rxh = ch_; rxl = cl; rxn = n;
    if (got) rx_t = NOW();
    else if (rxst && NOW() - rx_t > T_GAP) rxst = 0;
    return 0;
}

static void session_end(void)
{
    if (!up) return;
    up = 0;
    epoch++;
    pl_session(0);
}

static void ctl(const uint8_t *p, uint32_t n)
{
    if (!n) return;
    switch (p[0]) {
    case C_HELLO: {                                    // op ver nonce4 time4 services
        if (n < 11) return;
        if (up) session_end();
        for (int i = 0; i < PL_NCH; i++) tx_seq[i] = rx_last[i] = acked[i] = 0;
        parked = 0;                                    // (a frame of the old session)
        svc = p[10];
        pc_t0 = p[6] | p[7] << 8 | p[8] << 16 | (uint32_t)p[9] << 24;
        pc_ms = NOW();
        up = 1;
        epoch++;
        last_rx = NOW();
        static const char id[] = "Atari816 firmware " __DATE__;
        uint8_t r[8 + sizeof id];
        r[0] = C_HELLO_ACK; r[1] = PL_PROTO;
        r[2] = p[2]; r[3] = p[3]; r[4] = p[4]; r[5] = p[5];       // the nonce back
        r[6] = PL_MAXPAY & 0xFF; r[7] = PL_MAXPAY >> 8;
        for (unsigned i = 0; i < sizeof id; i++) r[8 + i] = id[i];
        tx_ctl(r, 8 + sizeof id - 1);
        pl_session(1);
        break;
    }
    case C_PING: {
        uint8_t r[5] = { C_PONG, 0, 0, 0, 0 };
        if (!up) { tx_ctl1(C_NOSESSION); break; }
        for (int i = 1; i < 5 && i < (int)n; i++) r[i] = p[i];
        tx_ctl(r, 5);
        break;
    }
    case C_BYE:
        session_end();
        break;
    }
}

// one frame is in rxf: act on it
static void rx_frame(void)
{
    uint8_t ch = rxf[2], seq = rxf[3], ack = rxf[4], fl = rxf[5];
    const uint8_t *p = rxf + 7;
    uint32_t n = rxlen;
    last_rx = NOW();
    if (fl & PL_F_ACK) acked[ch] = ack;
    if (!(fl & PL_F_DATA)) {
        if (ch == PL_CH_CTL) ctl(p, n);
        return;
    }
    if (!up) { tx_ctl1(C_NOSESSION); return; }
    if (seq == rx_last[ch]) { tx_ack(ch, seq); return; }     // a repeat: our ACK was lost
    if (seq != rx_last[ch] % 255 + 1) return;                 // not the next one: dropped
                                                              // (the PC sends it again)
    // A developer frame while busy, or while an older one is still kept: keep it (one), or drop
    // it without an ACK (the PC sends it again). Never served before the one kept: the frames
    // of a request must be taken in order (a SINK frame came after the last one, 2026-11).
    int dev_later = ch == PL_CH_DEV && (nested || parked);
    if (dev_later) {
        if (parked || n > sizeof park) return;               // no room: the PC sends it again
        for (uint32_t i = 0; i < n; i++) park[i] = p[i];
        parkn = n;
        parked = 1;
    }
    rx_last[ch] = seq;
    tx_ack(ch, seq);
    if (ch == PL_CH_FILES) {
        if (n < 4 || !fw_tag || p[1] != fw_tag || p[0] != (fw_op | 0x80) || fw_done) return;
        fw_t = NOW();
        if (fw_sink && n > 4) fw_sink(p + 4, n - 4, fw_ctx);
        if (!(p[2] & PL_RQ_MORE)) { fw_res = p[3]; fw_done = 1; }
    } else if (ch == PL_CH_DEV && !dev_later) {
        pl_dev_request(p, n);
    } else if (ch == PL_CH_NET || ch == PL_CH_FETCH) {
        ns_frame(ch, p, n);                                  // (any time: it only stores)
    }
}

// one step of the engine: a frame in, the timers. 1 = a frame was handled.
static int step(void)
{
    if (rx_drain()) { rx_frame(); return 1; }
    if (up && NOW() - last_rx > T_SILENT) session_end();
    return 0;
}

HOT void pl_poll(void)
{
    if (parked && !nested) {                               // the frame kept comes first
        pl_dev_request(park, parkn);                       // (parked stays set meanwhile: a new
        parked = 0;                                        //  developer frame waits, unacked)
    }
    if (rx_drain()) rx_frame();
    else if (up && NOW() - last_rx > T_SILENT) session_end();
}

int pl_send(int ch, const uint8_t *hdr4, const volatile uint8_t *d, uint32_t n)
{
    return pl_send3(ch, hdr4, 4, d, n);
}

int pl_send3(int ch, const uint8_t *a, uint32_t na, const volatile uint8_t *d, uint32_t n)
{
    if (!up) return -1;
    uint32_t ep = epoch;
    uint8_t seq = tx_seq[ch] + 1;
    if (!seq) seq = 1;
    tx_seq[ch] = seq;
    nested++;
    for (int t = 0; t < N_RETRY; t++) {
        if (t) n_retry++;
        tx_frame(ch, seq, 0, PL_F_DATA, a, na, d, n);
        uint32_t t0 = NOW();
        while (NOW() - t0 < T_RETRY) {
            if (epoch != ep || !up) { nested--; return -1; }
            if (acked[ch] == seq) { nested--; return 0; }
            if (!step()) pl_idle();
            else pl_busy();                            // (a stream of frames: input too)
        }
    }
    nested--;
    session_end();
    return -1;
}

int pl_call(uint8_t op, const uint8_t *args, uint32_t nargs,
            const volatile uint8_t *wdata, uint32_t nwdata, pl_sink_t sink, void *ctx)
{
    uint8_t f[4 + 264];
    if (!up || !(svc & PL_SV_FILES)) return PL_E_NOLINK;
    if (nargs > 264) return 0x82;
    uint32_t ep = epoch;
    uint8_t tag = ++fw_ctr ? fw_ctr : ++fw_ctr;
    fw_tag = tag; fw_op = op; fw_done = 0; fw_res = 0; fw_sink = sink; fw_ctx = ctx;
    f[0] = op; f[1] = tag; f[3] = 0;
    for (uint32_t i = 0; i < nargs; i++) f[4 + i] = args[i];
    uint32_t off = 0;
    int r = 0;
    do {                                               // the request: 1 frame, or 1 per KB
        uint32_t k = nwdata - off > 1024 ? 1024 : nwdata - off;
        f[2] = off + k < nwdata ? PL_RQ_MORE : 0;
        if (pl_send3(PL_CH_FILES, f, 4 + nargs, wdata + off, k)) { r = PL_E_LOST; break; }
        off += k;
    } while (off < nwdata);
    if (!r) {
        fw_t = NOW();
        nested++;
        while (!fw_done) {
            if (epoch != ep || !up || NOW() - fw_t > T_CALL) { r = PL_E_LOST; break; }
            if (!step()) pl_idle();
            else pl_busy();                            // (a stream of frames: input too)
        }
        nested--;
        if (!r) r = fw_res;
    }
    fw_tag = 0;
    return r;
}

HOT void pl_init(void)                                   // (runs before the cold image is loaded)
{
#ifndef PL_HOST
    uint32_t d = (27000000 + PL_BAUD / 2) / PL_BAUD;     // 27 for 1 Mbaud
    reg_blrx_div = d - 1;                                // receiver: bit = div + 1 clocks
    reg_uart_clkdiv = 234 | (d - 2) << 16;               // keyboard RX 115200; TX: div + 2
    reg_blrx = 1;                                        // empty the FIFO
#endif
    static const uint8_t boot = C_BOOT;
    tx_frame(PL_CH_CTL, 0, 0, 0, &boot, 1, 0, 0);
}
