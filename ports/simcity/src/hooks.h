/* hooks.h - the port's engine part (hooks.c) and what each front end gives it (the game
 * on the Atari816: ui*.c; the headless test of every build: simtest.c).
 * Copyright (C) 2026 the Atari816 project. GPL-3 with EA's additional terms. */
#ifndef MICROPOLIS_HOOKS_H
#define MICROPOLIS_HOOKS_H

#include <stdio.h>

/* what the engine asked to be drawn again (Invalidate*) */
struct port_ui {
    unsigned char maps, editors;
};
extern struct port_ui port_ui;

/* hooks.c */
void port_init(void);                   /* the arrays, an empty city */
void InitGame_port(void);
void port_tick(void);                   /* one pass of upstream's sim_loop */
unsigned long port_checksum(void);      /* the simulation's whole state */
void port_state_line(char *buf);        /* "crc ... time ... funds ..." (120 bytes) */
void port_dump(FILE *f);
struct SimView *port_view(void);        /* the view the tools are used through */

/* the front end's */
void port_eval(const char *cmd);        /* upstream's Tcl commands: "UISetMessage {...}" */
void port_sound(const char *channel, const char *sound);
long port_ticks(void);                  /* the Mac's clock: 60 a second */
unsigned port_seed(void);               /* RandomlySeedRand's clock */
void MAPFAR *port_far_alloc(unsigned size);   /* zeroed, never freed */
void port_fatal(const char *why);

#endif
