/* SPDX-License-Identifier: GPL-3.0-or-later */
/* plat.h: what a back end gives the DOS model (plat/xdos.c) and the port's
   replacements of upstream's assembly (plat/vga.c, ...). Two back ends:
   host/ (Linux: headless, pictures to files, the engine's own KEYS
   scripts) and horizon/ (the Atari816). */
#ifndef PLAT_H
#define PLAT_H

/* The arena (xdos.h): host: one allocation; Atari816: 17 banks. Called
   once, first thing. 0 = ok. */
int plat_arena(void);

/* Time in PIT counts (1,193,182 a second) since the start. The model's
   clock: real time when playing, or a virtual clock in test runs (each
   read moves it on by XD_TICK_STEP counts, a wait by its length), so that
   a run is the same on every machine (PORTING-NOTES.md "Time"). */
unsigned long plat_counts(void);
extern int g_plat_virtual;              /* 1: the virtual clock */
void plat_wait_counts(unsigned long n); /* virtual: the clock moves on n */

/* Events: keys, mouse, window. Called by xd_poll. */
void plat_poll(void);
/* The next key typed, BIOS form (scan << 8 | ASCII), 0 if none. */
unsigned plat_key(void);
/* Pointer in 320 x 200 pixels and buttons (bit 0 left, 1 right). */
void plat_mouse(int *x, int *y, int *buttons);
void plat_mouse_set(int x, int y);
/* Presses of button b (0 left, 1 right) since the last call, and where. */
int plat_mouse_press(int b, int *x, int *y);

/* Video: BIOS mode (0x13 the VGA's, 3 text); the VGA picture is the
   arena's A000 (64,000 bytes) and xd_dac[] (6-bit DAC values): shown by
   plat_present (the rectangle that changed). */
void plat_setmode(int mode);
void plat_present(int x0, int y0, int x1, int y1);
extern unsigned char xd_dac[768];

/* The OPL2 (ports 388h / 389h). */
void plat_opl(int reg, int val);

/* Where the game's files are ("" or "dir/"). */
extern char g_plat_dir[128];

/* Log a line on the platform's console (the engine's own LOG is a file). */
void plat_note(const char *s);

#endif
