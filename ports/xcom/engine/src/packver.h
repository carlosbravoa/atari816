/* SPDX-License-Identifier: GPL-3.0-or-later */
/* Pack format version: the one place to bump it.
   tools/xcomconv.py (and the other converters) write it to PACKS.VER next to
   the packs; the engine (startup.c) refuses packs whose PACKS.VER differs or
   is missing. Raise the number whenever a change to the pack formats (the
   converter or the pack readers in pak.c, geo.c, pedia.c ...) makes older
   packs wrong or unreadable. The tools read the number from this line, so
   keep it as `#define PACK_FORMAT_VERSION <digits>`. */
#ifndef PACKVER_H
#define PACKVER_H

/* 5: SOUNDS.PAK has the interface's three effects (the fork, engine/FORK.md)
   6: SOUNDS.PAK the battle's footsteps and other samples, the small explosion
      SOUND1.CAT 2 (not 0, the slither); mission packs "XFS1" (footsteps) */
#define PACK_FORMAT_VERSION 6

/* PACKS.VER holds PACK_MARKER_TEXT, the number and a line end. */
#define PACK_MARKER_FILE "PACKS.VER"
#define PACK_MARKER_TEXT "XCOM-XT PACKS "

#endif
