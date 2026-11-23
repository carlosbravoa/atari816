/* SPDX-License-Identifier: GPL-3.0-or-later */
/* What upstream's music.c needs of DOS, in the music task (mus/musd.c): the
   ports (the OPL2 at 388h/389h: hz_opl_write), and stubs for the track
   loading it does not use there (mus_play_mem takes the game's copy) */
#ifndef MUSD_H
#define MUSD_H

union REGS {
    struct { unsigned short ax, bx, cx, dx, si, di, cflag; } x;
    struct { unsigned char al, ah, bl, bh, cl, ch, dl, dh; } h;
};
int intdos(union REGS *in, union REGS *out);
unsigned inp(unsigned port);
unsigned outp(unsigned port, unsigned v);
unsigned _dos_freemem(unsigned seg);
#define MK_FP(s, o)     ((void *)0)
#define FP_SEG(p)       0u
#define _fheapshrink()  ((void)0)
int mus_play_mem(unsigned char *buf, unsigned len, int loop);

#endif
