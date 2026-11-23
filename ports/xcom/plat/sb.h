/* SPDX-License-Identifier: GPL-3.0-or-later */
/* plat/sb.c: the Sound Blaster model, and what the back ends give it */
#ifndef SB_H
#define SB_H

int sb_outp(unsigned port, unsigned v);         /* -1: not the card's or the DMA's port */
int sb_inp(unsigned port);
void sb_poll(unsigned long now);                /* the clock was read: the IRQ when due */
unsigned xd_sound_umb(unsigned *paras);
extern unsigned g_sfx_count;                    /* blocks started */

/* a block starts: bytes at src (linear address lin in the arena, a checksum sum), rate
   samples a second; kind 0 8-bit unsigned PCM (14h), 1 4-bit ADPCM with its reference
   byte (75h), 2 ADPCM going on (74h) */
void plat_sfx(const unsigned char far *src, unsigned bytes, unsigned rate, int kind,
              unsigned long lin, unsigned sum);
void plat_sfx_stop(void);                       /* the DSP halted it (D0h) */
/* the samples of a block, signed 8-bit, into out: their number (kind 1: 2 * bytes - 1) */
unsigned sb_decode(const unsigned char far *src, unsigned bytes, int kind, signed char far *out);

/* plat/timer.c: the music driver's ticks run (the timer hook's calls) */
extern unsigned long g_hook_ticks;
/* music.c's hooks (patches/src-0002-sound.patch) and the sound's on/off (the battle's S
   key, g_sound_on: plat/timer.c at each tick): the Atari816's music task plays them */
void plat_mus_play(int track, int loop, unsigned char *buf, unsigned len);
void plat_mus_stop(void);
void plat_mus_fx(int sfx);
void plat_mus_sound(int on);

#endif
