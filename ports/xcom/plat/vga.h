/* SPDX-License-Identifier: GPL-3.0-or-later */
/* The VGA prototype in C (upstream's src/vgainit.c + vgaasm.asm +
   vgageo.c + vgxasm.asm): shared by plat/vga.c (start, the interface:
   entries 9-21, the geoscape's vgx entries) and plat/vgabat.c (the battle
   view: entries 0-8, 22-26). The back buffer is upstream's: g_bufseg, 320
   x VIEW_H bytes at offset 0 of its segment (+ 256 bytes: the night's shade
   table at VGA_SHADE - BYTES), a CGA offset (y * 80 + x / 4) is a quarter
   of the buffer's. The screen is A000 (mode 13h). */
#ifndef PLAT_VGA_H
#define PLAT_VGA_H

extern unsigned char g_vpal[768];       /* the battlescape palette (vgaasm.asm PAL) */
extern unsigned char g_vmap[16];        /* EGA colour -> palette index (VMAP) */
extern unsigned g_vshade;               /* the night's shade, 0 by day (V_SHADE) */
void vga_dac(const unsigned char far *pal, int first, int n);  /* 6-bit values to the DAC */

/* plat/vgabat.c */
void vga_pal(void);                     /* entry 8: g_vpal to the DAC */
void vga_gfx_night(int night);          /* entry 24 (gfx.c gfx_night's VGA hook) */
int vga_lit_shown(unsigned cell);       /* the night lights: the level a cell (of 20 x 18) is
                                           shown at, -1 not shown yet; 0 by day */
void vga_gfx_dot(int x, int y, int colour);     /* entry 25 */
const int far *vga_pics_next(void);     /* entry 26: the rectangle to redraw, or NULL */
void vga_smoke_load(void);              /* SMOKEV.PAK: DOS's smoke and fire pictures */
int vga_pics_loaded(void);              /* (BENCH: the pictures' step) */
void vga_pics_start(void);
int vga_pics_over(void);

#endif
