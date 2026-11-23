/* SPDX-License-Identifier: GPL-3.0-or-later */
/* xport.h: the port's functions that upstream's patched files call (the
   VGA prototype's entries, plat/vga.c and plat/vgabat.c): where upstream
   patches a resident routine's first bytes into a far jump to the
   copied assembly, the port's patch calls these when g_vga is set. */
#ifndef XPORT_H
#define XPORT_H

void vga_uk_pic(const void *head, int x, int y, int to_save);   /* entry 9 + vx_pic */
int vga_uk_cga_c(int c);                                        /* 10 */
void vga_uk_glyph(int x, int y, const unsigned char far *g, int h, int bpr, int c); /* 11 */
int vga_uk_pic_clean(unsigned id);                              /* 12 */
void vga_uk_save(int y0, int y1);                               /* 13 */
void vga_uk_restore(int x, int y, int w, int h);                /* 14 */
void vga_uk_fill(int x, int y, int w, int h, int c);            /* 15 + vx_fill */
void vga_uk_theme(int t);                                       /* 16 + vx_theme */
void vga_uk_copy(int sx, int sy, int dx, int dy, int w, int h); /* 17 */
void vga_hud_text(int col, int row, int colour, const char *s, int len);   /* 18 */
void vga_hud_clear(int row, int count);                         /* 19 */
void vga_ms_draw(int x, int y);                                 /* 20 */
void vga_ms_erase(int x, int y);                                /* 21 */
void vga_gfx_night(int night);                                  /* 24 */
void vga_gfx_dot(int x, int y, int colour);                     /* 25 */
const int far *vga_pics_next(void);                             /* 26 */
void vga_vx_world(const unsigned char far *map, unsigned vx, unsigned vy, unsigned zoom);
void vga_vx_xor(int x0, int y0, int x1, int y1, int colour);
void vga_vx_battle(void);
void vga_vx_slide(const unsigned char far *dac, int caption);
extern unsigned char g_vmap[16];

#endif
