/* port.h - the Atari816 port of Micropolis (ports/simcity): what sim.h takes from the
 * system, X11, Tcl and Tk in upstream, for the three builds of the engine:
 *
 *   the Atari816 (cc816: int 16 bits, long 32, plain char unsigned),
 *   host16 (gcc on the PC, the sources rewritten by tools/host16.py: int -> short, so
 *     that the PC computes as the Atari816 does; long 32 bits by the #define below),
 *   host32 (gcc on the PC, upstream's own types: int 32 bits, long 32 bits as on the
 *     32-bit machines upstream was written for).
 *
 * Copyright (C) 2026 the Atari816 project. GPL-3 with Electronic Arts' additional terms,
 * as the engine (engine/COPYING, engine/README).
 */
#ifndef MICROPOLIS_PORT_H
#define MICROPOLIS_PORT_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <errno.h>
#include <math.h>

#if defined(__CC816__)
#include <horizon.h>
/* the big maps live in far memory (port_alloc.c): Map 24,000 bytes, the 2 x 2 and
 * 4 x 4 maps 22,500, the power scan's stack 12,000 */
#define MAPFAR __far
#else
#define MAPFAR
/* 32-bit long on the PC too: QUAD (funds, the city's time) and the file format's longs
 * (host16: native) */
#include <stdint.h>
#define long int    /* host16: native */
#endif

#define rindex strrchr

/* ---------------------------------------------------------------- the views upstream
 * keeps in X windows: only what the engine's code still touches */

typedef struct SimView {
  struct SimView *next;
  short map_state;
  short tool_state;
  short tool_state_save;
  short tool_x, tool_y;
  int last_x, last_y;           /* world pixels (16 a tile), as upstream's */
  int invalid;
  int skip;
  short super_user;             /* (0: zones may not be built over others) */
  void *tkwin;                  /* (none: Tk_PathName below) */
} SimView;

/* the Tk window's name in upstream's Tcl commands */
#define Tk_PathName(w) "."
/* a view's pixel to world pixels: the port's views give world pixels already */
#define ViewToPixelCoords(view, x, y, px, py) (*(px) = (x), *(py) = (y))

typedef struct SimGraph {
  struct SimGraph *next;
  int range, mask;
} SimGraph;

typedef struct SimDate {
  struct SimDate *next;
} SimDate;

/* the moving things (w_sprite.c), as upstream */
typedef struct SimSprite {
  struct SimSprite *next;
  char *name;
  int type;
  int frame;
  int x, y;
  int width, height;
  int x_offset, y_offset;
  int x_hot, y_hot;
  int orig_x, orig_y;
  int dest_x, dest_y;
  int count, sound_count;
  int dir, new_dir;
  int step, flag, control;
  int turn;
  int accel;
  int speed;
} SimSprite;

typedef struct Sim {
  int editors;
  SimView *editor;
  int maps;
  SimView *map;
  int graphs;
  SimGraph *graph;
  int dates;
  SimDate *date;
  int sprites;
  SimSprite *sprite;
} Sim;

/* ---------------------------------------------------------------- the front end's hooks
 * (src/hooks.c on the Atari816 and the PC's headless test; src/ui*.c the game's) */

/* upstream's Tcl commands ("UISetMessage {...}", "UIDidLoadCity", ...) go to the front
 * end as they are: port_eval reads the command's name and its arguments */
int Eval(char *buf);
/* a sound: upstream's names ("city", "Explosion-High") */
void MakeSound(char *channel, char *sound);
#define MakeSoundOn(view, channel, sound) MakeSound(channel, sound)
/* memory for the engine (malloc, or a far bank for the maps on the Atari816) */
#define ckalloc(n) malloc(n)
#define ckfree(p) free(p)

/* the clock upstream reads with gettimeofday: the port's (port_seed for the random
 * numbers of a new game) */
unsigned port_seed(void);
/* far memory for the maps (zeroed, never freed), and the end when there is none */
void MAPFAR *port_far_alloc(unsigned size);
void port_fatal(const char *why);
void port_rand_init(void);
void port_animate_band(void);
extern short aniTile[];
#if defined(__CC816__)
/* fast.s: the hot loops in assembly */
void port_animate(unsigned short __far *map, unsigned n, const short __far *table);
#endif

#endif
