/* platform.h - what the game (src/) asks of the machine it runs on. Not in the C++, which
 * called the C++ standard library and SDL directly: a C translation meant for platforms
 * with nothing but a C compiler needs the few machine-dependent things in one place.
 *
 * Two back ends: host/ (a PC: stdio, and SDL2 for the window, keys and sound when it is
 * there) and horizon/ (the Atari816). Memory: sr.h (plat_alloc ...). The game's main loop
 * itself is the back end's (upstream's was in src/platform/main.cpp). */
#ifndef PLATFORM_H
#define PLATFORM_H

#include "sr.h"

/* ---- files */

/* the path of the game's file `name` in the folder `root` (DOS names: any case). The
 * result is a static buffer, good until the next call. */
const char *plat_asset_path(const char *root, const char *name);
/* a whole file into a buffer from plat_alloc_big: false if it cannot be read */
bool plat_read_file(const char *path, Bytes *out);
/* write n bytes (a small file: skyroads.cfg) */
bool plat_write_file(const char *path, const void *data, unsigned n);

/* ---- memory blocks (far on the Atari816) */
void plat_fill(uint8_t SR_FAR *dst, uint8_t value, unsigned n);
void plat_copy(uint8_t SR_FAR *dst, const uint8_t SR_FAR *src, unsigned n);

/* ---- misc */
/* a random byte (the original read the timer chip: there is no sequence to keep) */
uint8_t plat_random_byte(void);

#endif
