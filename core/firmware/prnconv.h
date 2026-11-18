// SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
// Copyright (c) 2026 Carlos Bravo
// prnconv.h - what the classic Atari prints (SIO printer, P:) turned into plain text for a print
// job. Plain C: the firmware uses it, and so do emu816 (--classic-print) and the host tests.
#ifndef PRNCONV_H
#define PRNCONV_H

#include <stdint.h>

typedef struct {
    uint8_t  esc;           // an ESC was the last byte: the next one is dropped too
    uint8_t  cr;            // a CR was the last byte: an LF right after it is the same line end
    uint8_t  last;          // the last byte written (0: none yet)
    uint16_t spaces;        // blanks held back (dropped at a line end: no trailing blanks)
} prn_conv_t;           // all 0 at the start of a job

// The record length the Atari sends for a printer write command's AUX1: 'N' (normal) 40,
// 'S' (sideways) 29, 'D' (double width) 20; anything else 40.
int prn_reclen(uint8_t aux1);

// One record (the bytes of a printer write command): text appended to out, which must hold
// n + 256 bytes (blanks held back, at most 255, come out before the next character). Returns the number of bytes written. After an EOL ($9B) the rest of the record is
// padding and is skipped. ATASCII: $9B a line end; bit 7 (inverse video) cleared; $0A LF and
// $0D CR line ends (CR LF = one), $0C a new page, $09 a tab, ESC and the byte after it dropped;
// the other graphics characters become look-alikes (+ - | / \ # * o ^ v < >).
int prn_record(prn_conv_t *c, const uint8_t *in, int n, uint8_t *out);

// The end of a job: a last line end if the text did not end with one (written to out, 1 byte
// at most). Returns the bytes written.
int prn_finish(prn_conv_t *c, uint8_t *out);

#endif
