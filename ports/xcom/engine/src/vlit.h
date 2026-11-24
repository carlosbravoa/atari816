/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef VLIT_H
#define VLIT_H

/* The VGA night lights' levels in portable C (src/vlit.c): the model of
   vgaasm.asm "Night lights" (the DOS VGA build's lit_present, which stays
   upstream's: this file is for the builds without it, XCOM_PORT). At
   night the map view is shown through 20 x 18 cells of 16 x 8 pixels,
   each through the shade of its tile (StandardShade: index + level in its
   16-colour ramp): 15 less the most light on that map column (OpenXcom
   Tile::getShade): the night sky's 15 - VL_NIGHT_SHADE, and every light's
   power less its distance rounded (TileEngine::addLight): the X-COM
   units' own light, burning units, fires and electro-flares on the ground
   15, the terrain's light sources (MCD) their own. The platform shows the
   cells (plat/vgabat.c); this keeps their levels up to date, recomputed
   only when a light came, went or moved, or the camera or the view's
   level moved. */

#define VL_COLS     20
#define VL_ROWS     18
#define VL_CELLS    (VL_COLS * VL_ROWS)
#define VL_NIGHT_SHADE 10                   /* the night sky (vgaasm.asm NIGHT_SHADE) */
#define VL_SUN      (15 - VL_NIGHT_SHADE)

/* each cell's level (0 lit to 15 black), row by row */
extern unsigned char far g_vl_lev[VL_CELLS];
/* counts: light maps made, cell levels made (BENCH, the console) */
extern unsigned long g_vl_maps, g_vl_levels;

#define VL_CHANGED  1                       /* some cell's level changed */
#define VL_MOVED    2                       /* the camera or the view's level moved */

/* The night begins (again): the cells' levels made anew at the next update. */
void vl_night(void);
/* Brings g_vl_lev up to date: VL_CHANGED and VL_MOVED as they apply. */
int vl_update(void);
/* The light on map column x, y (0-15, the night sky's at least) as the
   cells see it: after vl_update. */
int vl_light(int x, int y);

#endif
