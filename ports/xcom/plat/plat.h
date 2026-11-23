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
/* the virtual clock's step a reading (PIT counts: 600 = 0.5 ms). A KEYS script's WAIT
   polls the mouse until the BIOS clock has moved on: 2,000 polls a virtual second at
   this step (20,000 at the first one's 60, which made a test run on the Atari816 take
   20 s a virtual second: its polls cost about 1 ms each) */
#define XD_TICK_STEP 600
void plat_wait_counts(unsigned long n); /* virtual: the clock moves on n */
void plat_sleep_counts(unsigned long n);/* real: n counts pass, the CPU idle where it can */

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

/* The bytes the engine has read from files so far (plat/xdos.c), and the
   platform's hook after each read: the Atari816's loading screen moves its bar
   (horizon/hz_plat.c); the host does nothing. */
extern unsigned long xd_bytes_read;
void plat_progress(void);

/* Where the game's files are ("" or "dir/"). */
extern char g_plat_dir[128];

/* Log a line on the platform's console (the engine's own LOG is a file). */
void plat_note(const char *s);

/* ---------------------------------------------------------------- the battle view
   The back buffer (plat/vgabat.c: 320 x 144 at segment g_bufseg, which
   plat/vga.c puts at D004: linear D0040, the arena's bank 13, outside the
   DOS memory) drawn by a platform that has a blitter: each call returns 1
   when the platform did it, 0 when plat/vgabat.c's C must (the host always;
   the Atari816 for what its blitter cannot do, after plat_bb_sync). The C
   is the reference: the platform's result is the same bytes. Offsets are
   vgabat.c's: VGA offsets in the buffer, 16 bits. */
#define XD_BB_SEG   0xD004u
/* the interface's clean screen (plat/vga.c uk_save / uk_restore): a 64,000-byte copy
   of the screen at E000:0000, the arena's bank 14, outside the DOS memory */
#define XD_CLEAN_SEG 0xE000u
/* a sprite (tools/vgasprite.py's formats: kind 0 masked spans, 1 OR rows)
   whose row r goes to offset (dest << 2) + r * 320, its rows [top, bottom)
   and columns [lx, rx) only (sprite coordinates; 0, 0xFFFF: all) */
int plat_bb_sprite(const unsigned char far *spr, int kind, unsigned dest, unsigned top,
                   unsigned bottom, unsigned lx, unsigned rx);
int plat_bb_fill(unsigned off, unsigned w, unsigned rows, int colour);
/* the rectangle at off to the screen (A000, the same offset); done when it returns */
int plat_bb_present(unsigned off, unsigned w, unsigned rows);
/* the view moved by dx bytes (rows * 320 + columns): the 2-D move (the strips
   the move exposes are cleared and redrawn by the engine: render_scroll) */
int plat_bb_shift(long dx);
/* the cursor's box (w x rows at off) to (out 1) or from (0) the platform's copy */
int plat_bb_box(unsigned off, unsigned w, unsigned rows, int out);
/* the selected unit's arrow (9 x 9, colour 0 clear) at x, y, inside the rectangle */
int plat_bb_arrow(const unsigned char *px, int x, int y, int qx, int qy, int qw, int qh);
/* the screen shows the battle view (rows 0-143) and its panel (144-199): 1
   when the view is presented, 0 when a picture covers the view (the
   inventory, the geoscape, ...). The Atari816 then shows the panel whole
   below 124 of the view's rows (PORTING-NOTES.md "The screen") */
void plat_view(int on);
/* before the CPU reads or writes the back buffer: what was sent is drawn */
void plat_bb_sync(void);
/* the engine's memory at p (n bytes) was written by a file read or freed: a
   platform that keeps copies of pictures (the blitter's atlases) forgets them */
void plat_mem_changed(const void far *p, unsigned long n);
/* the battle's pack is loaded (the patch: main.c before BENCH, battle.c
   battle_run before the first view): a platform that keeps copies of the
   pictures makes them now, showing that it works (the host: nothing) */
void plat_bb_prepare(void);

/* ---------------------------------------------------------------- test runs
   The virtual clock's runs are the tests (tests/check.sh): the same input
   (a KEYS script) gives the same LOG and the same pictures at the same
   virtual times on the host and on the Atari816. The pictures are taken by
   the model (plat/xdos.c xd_shot_point), at the same points of both:
   whenever the engine polls or waits for a key and the screen (A000 and
   the DAC) changed since the last look, at most every 500 ms (polls) or
   200 ms (key waits) of virtual time. The back end shows each one
   (plat_shot): the host writes it as a PPM, the Atari816 prints its line
   and holds the screen still for the emulator's picture. A run ends after
   g_plat_idle s of virtual time with no input once the script is done. */
extern int g_plat_shots;                /* 1: pictures are taken (virtual clock only) */
extern unsigned g_plat_idle;            /* seconds of no input that end a run */
unsigned long plat_now(void);           /* the clock's reading, not moved on */
void plat_shot(unsigned n, unsigned long ms, unsigned long sum, const char *why);
void plat_end(void);                    /* the run is over: leave */
/* the model's state the back ends read */
extern int xd_mode;                     /* the BIOS video mode (3, 0x13) */
extern unsigned char xd_dac_dirty;      /* the DAC was written since the back end showed it */
unsigned long xd_screen_sum(void);      /* checksum of A000 (64,000 bytes) and the DAC */
void xd_shot_point(unsigned gap_ms, const char *why);

#endif
