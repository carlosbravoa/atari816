/* SPDX-License-Identifier: GPL-3.0-or-later */
/* cutasm.asm's VGA half in C: cut_fli, one frame of the DOS intro movie as
   UFOINT.FLI has it (tools/intro.py --vga writes INTROV.PAK: per frame u16
   chunks, then the chunks, each u32 size (with its 6-byte head), u16 type,
   its data), into A000 and the DAC:
     11 COLOR  u16 packets; each u8 skip, u8 n (0: 256), n x RGB (6 bits)
     12 LC     u16 lines skipped, u16 lines; per line u8 packets; each
               u8 skip, s8 size: n bytes copied, -n one byte n times
     13 BLACK  the screen cleared
     15 BRUN   200 lines; per line u8 (unused), then s8 counts until 320
               pixels: n one byte n times, -n bytes copied
     16 COPY   64,000 bytes
   Others are skipped. Returns the number of runs (LC and BRUN packets), as
   the assembly. The runs are memcpy / memset (MVN on the Atari816: a run
   costs a call, not a byte loop). cut_runs (EGA, CGA) stays plat/asm.c's
   stub: never called in the VGA mode. */
#include "xcompat.h"
#include "plat.h"

#define SCREEN ((unsigned char far *)MK_FP(0xA000, 0))

static unsigned u16(const unsigned char far *p)
{
    return p[0] | (unsigned)p[1] << 8;
}

unsigned __cdecl cut_fli(const unsigned char far *frame)
{
    const unsigned char far *s = frame;
    unsigned char far *scr = SCREEN;
    unsigned chunks = u16(s), runs = 0;

    s += 2;
    while (chunks--) {
        const unsigned char far *next = s + u16(s);     /* (the size's high word: 0) */
        const unsigned char far *p = s + 6;
        unsigned type = u16(s + 4);

        if (type == 11) {                               /* COLOR */
            unsigned packets = u16(p), idx = 0;
            p += 2;
            while (packets--) {
                unsigned n;
                idx += *p++;
                n = *p++;
                if (!n)
                    n = 256;
                outp(0x3C8, idx & 0xFF);
                idx += n;
                for (n *= 3; n; n--)
                    outp(0x3C9, *p++);
            }
        } else if (type == 12) {                        /* LC */
            unsigned row = u16(p) * 320u, lines = u16(p + 2);
            p += 4;
            for (; lines; lines--, row += 320) {
                unsigned packets = *p++, x = row;
                for (; packets; packets--) {
                    int n;
                    x += *p++;
                    n = (signed char)*p++;
                    if (n >= 0) {
                        _fmemcpy(scr + x, p, (unsigned)n);
                        p += n;
                        x += (unsigned)n;
                    } else {
                        _fmemset(scr + x, *p++, (unsigned)-n);
                        x += (unsigned)-n;
                    }
                    runs++;
                }
            }
        } else if (type == 15) {                        /* BRUN */
            unsigned row = 0, line;
            for (line = 0; line < 200; line++, row += 320) {
                int left = 320;
                unsigned x = row;
                p++;
                while (left > 0) {
                    int n = (signed char)*p++;
                    if (n >= 0) {
                        _fmemset(scr + x, *p++, (unsigned)n);
                    } else {
                        n = -n;
                        _fmemcpy(scr + x, p, (unsigned)n);
                        p += n;
                    }
                    x += (unsigned)n;
                    left -= n;
                    runs++;
                }
            }
        } else if (type == 13) {                        /* BLACK */
            _fmemset(scr, 0, 64000u);
        } else if (type == 16) {                        /* COPY */
            _fmemcpy(scr, p, 64000u);
        }
        s = next;
    }
    /* a test run's picture now and then (cut.c's scripted intro never polls:
       no other point would take one); nothing when not testing */
    xd_shot_point(1000, "intro");
    return runs;
}
