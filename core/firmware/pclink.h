// SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
// Copyright (c) 2026 Carlos Bravo
// pclink.h - the PC link: framed packets over the USB serial (BL616 bridge) to a gateway
// on the PC. Protocol: Docs/04-pc-link.md. The engine is in pclink.c; firmware.c gives it
// the mailbox side (the PC volume) and the developer channel.
#ifndef PCLINK_H
#define PCLINK_H

#include <stdint.h>

#define PL_BAUD     1500000     // the link's rate: 27 MHz / 18 (Docs/04-pc-link.md, "Physical layer")
#define PL_MAXPAY   1040        // largest payload of a frame
#define PL_PROTO    1           // protocol version in HELLO / HELLO_ACK

// channels
#define PL_CH_CTL   0           // control: HELLO, PING, BYE (datagrams)
#define PL_CH_LOG   1           // the firmware's log, board -> PC (datagrams)
#define PL_CH_FILES 2           // the PC volume: requests board -> PC
#define PL_CH_DEV   3           // developer tools: requests PC -> board
#define PL_NCH      16

// frame flags
#define PL_F_DATA   0x01        // sequenced payload, must be acknowledged
#define PL_F_ACK    0x02        // the ACK field acknowledges a DATA frame of this channel

// request / response payload header: op, tag, flags, 0
#define PL_RQ_MORE  0x01        // more frames of this request (or response) follow

// HELLO service bits
#define PL_SV_FILES 0x01
#define PL_SV_DEV   0x02

// mailbox result codes of the PC volume
#define PL_E_NOLINK 0x87        // no PC link (or the peer serves no files)
#define PL_E_LOST   0x88        // the link dropped during the operation / stale handle
#define PL_E_XVOL   0x89        // RENAME between the card and the PC volume

// ---- engine (pclink.c) ----
void     pl_init(void);                     // at boot: the rate, the FIFO, the BOOT datagram
void     pl_poll(void);                     // main loop: frames in, timers (hot, cheap when idle)
void     pl_log_putc(int c);                // uart_printf goes here: log datagrams per line
int      pl_up(void);                       // a peer is connected (session up)
int      pl_files(void);                    // ... and it serves the PC volume
uint32_t pl_epoch(void);                    // +1 at every session start and end
uint32_t pl_pc_time(void);                  // PC local time, seconds since 2000-01-01 (0: none)
uint32_t pl_rx_bytes(void), pl_rx_bad(void), pl_retries(void);   // counters

// Reliable send of one frame on a channel (waits for the ACK, retransmits). The payload is
// a 4-byte header and then n bytes at d (d may point into 65C816 memory). 0 = acked.
int      pl_send(int ch, const uint8_t *hdr4, const volatile uint8_t *d, uint32_t n);
int      pl_send3(int ch, const uint8_t *a, uint32_t na, const volatile uint8_t *d, uint32_t n);

// The PC volume client. A request: hdr (op, tag, flags, 0) + args; the response stream (the
// data of all response frames) goes to the sink; returns the result byte of the last frame,
// or PL_E_NOLINK / PL_E_LOST.
typedef void (*pl_sink_t)(const uint8_t *p, uint32_t n, void *ctx);
int      pl_call(uint8_t op, const uint8_t *args, uint32_t nargs,
                 const volatile uint8_t *wdata, uint32_t nwdata,
                 pl_sink_t sink, void *ctx);

// ---- given by the firmware (firmware.c) ----
void     pl_dev_request(const uint8_t *p, uint32_t n);   // one frame of the developer channel
void     pl_session(int up);                // a session started (1) or ended (0)
void     pl_idle(void);                     // called while waiting (keyboard, SIO)
void     pl_busy(void);                     // called after each frame while waiting (keyboard)

#endif
