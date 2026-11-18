// SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
// Copyright (c) 2026 Carlos Bravo
// pcnet.h - the internet through the PC link (step 2): streams on channels 4 (Net, TCP) and 5
// (Fetch, URLs), and their mailbox side (Docs/04-pc-link.md, "Channels 4 and 5"). The engine is
// pcnet.c; firmware.c routes the mailbox ops on URL paths and on handles 4-7 to it.
#ifndef PCNET_H
#define PCNET_H

#include <stdint.h>

#define NS_N        4           // streams (mailbox handles NS_H0 .. NS_H0 + NS_N - 1)
#define NS_H0       4
#define NS_RING     4096        // bytes kept per stream (the window given to the PC)
#define NS_STEP     1024        // credit is given back in steps of this many bytes
#define NS_T_WAIT   40000       // ms: a request put aside with no answer from the PC: $8E
#define NS_T_KEEP   15000       // ms: a STAT's stream kept for an OPEN of the same URL

// results (mailbox ARG0), see Docs/04-pc-link.md
#define NS_E_NOSVC  0x8A
#define NS_E_ADDR   0x8B
#define NS_E_TIME   0x8E
#define NS_E_CLOSED 0x90

// what a mailbox op did
#define NS_NOW      0           // answer now with *res, *val
#define NS_LATER    1           // put aside: the request ring moves on, the answer comes later

int      ns_kind(const char *path);         // 1 = a URL (Fetch), 2 = tcp:// or tls:// (Net), 0 = no
// m = the 16-byte request (kept when the answer comes later)
int      ns_open(const char *path, const uint8_t *m, uint32_t *res, uint32_t *val);
int      ns_stat(const char *path, uint32_t buf, const uint8_t *m, uint32_t *res, uint32_t *val);
int      ns_read(int h, uint32_t buf, uint32_t len, const uint8_t *m, uint32_t *res, uint32_t *val);
void     ns_write(int h, uint32_t buf, uint32_t len, uint32_t *res, uint32_t *val);
uint32_t ns_close(int h);                   // 0, or $80 not open
void     ns_close_all(void);                // (65C816 reset, SYS_SYNC) every stream, no answers
void     ns_frame(int ch, const uint8_t *p, uint32_t n);   // a DATA frame from the PC (pclink.c)
void     ns_session(int up);                // the link session started / ended
void     ns_service(void);                  // answers put aside, credit, timers (when ns_work)
extern volatile uint8_t ns_work;            // ns_service has something to do
extern uint8_t  ns_npend;                   // requests put aside

// ---- given by the firmware (or the host test) ----
int      ns_put816(uint32_t dst, const uint8_t *src, uint32_t n);   // into 65C816 memory; 0 = bad address
const volatile uint8_t *ns_ptr816(uint32_t a, uint32_t n);         // 65C816 memory to read n bytes, or 0
uint32_t ns_fattime(void);                  // the PC's clock now, FAT format
int      ns_answer(uint8_t *m16);           // write an answer into the response ring; 0 = no room yet
void     ns_event(int handle);              // queue the event $E4 NET (ARG0 = handle)

#endif
