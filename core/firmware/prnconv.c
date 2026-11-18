// SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
// Copyright (c) 2026 Carlos Bravo
// prnconv.c - the classic Atari's printer output (ATASCII) to plain text. See prnconv.h.
#include "prnconv.h"

// ATASCII $00-$1F as text (the printer control codes $09 $0A $0C $0D $1B are handled first)
static const char gfx[32] = {
    '*', '+', '|', '+', '+', '+', '/', '\\', '#', '#', '#', '#', '#', '-', '_', '#',
    '*', '+', '-', '+', 'o', '#', '|', '+', '+', '|', '+',  0,  '^', 'v', '<', '>'
};

int prn_reclen(uint8_t aux1)
{
    return aux1 == 'S' ? 29 : aux1 == 'D' ? 20 : 40;
}

static int put(prn_conv_t *c, uint8_t ch, uint8_t *out)
{
    int k = 0;
    if (ch == ' ' && c->spaces < 255) { c->spaces++; return 0; }
    if (ch != '\n' && ch != '\f')                        // blanks before a line end are dropped
        while (c->spaces) { out[k++] = ' '; c->spaces--; }
    c->spaces = 0;
    out[k++] = ch;
    c->last = ch;
    return k;
}

int prn_record(prn_conv_t *c, const uint8_t *in, int n, uint8_t *out)
{
    int k = 0;
    for (int i = 0; i < n; i++) {
        uint8_t b = in[i];
        if (b == 0x9B) {                                 // EOL: the rest is padding
            c->esc = 0; c->cr = 0;
            k += put(c, '\n', out + k);
            break;
        }
        if (c->esc) { c->esc = 0; continue; }
        if (c->cr) { c->cr = 0; if (b == 0x0A) continue; }   // CR LF: one line end
        b &= 0x7F;                                       // inverse video
        if (b == 0x1B) { c->esc = 1; continue; }
        if (b == 0x0D) { c->cr = 1; k += put(c, '\n', out + k); continue; }
        if (b == 0x0A) { k += put(c, '\n', out + k); continue; }
        if (b == 0x0C) { k += put(c, '\f', out + k); continue; }
        if (b == 0x09 || b == 0x7F) { k += put(c, '\t', out + k); continue; }
        if (b < 0x20) b = gfx[b];
        else if (b == 0x60 || b == 0x7B) b = '*';        // diamond, spade
        else if (b == 0x7D || b == 0x7E) b = 0;          // clear screen, backspace: nothing
        if (b) k += put(c, b, out + k);
    }
    return k;
}

int prn_finish(prn_conv_t *c, uint8_t *out)
{
    c->spaces = 0;
    if (c->last && c->last != '\n' && c->last != '\f') { out[0] = '\n'; c->last = '\n'; return 1; }
    return 0;
}
