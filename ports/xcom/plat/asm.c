/* SPDX-License-Identifier: GPL-3.0-or-later */
/* Upstream's assembly (src/*.asm, NASM, 8086) and Watcom's inline
   `#pragma aux` code, as C: what each routine is, and its state in this
   port (PORTING-NOTES.md, "The assembly"). Stage 1: the services are C,
   the rest are stubs that say once that they ran:
     XD_TODO   - needed for the VGA game, to be written in C (stage 2-4)
     XD_NEVER  - EGA, CGA, Hercules, EMS/XMS, overlays: never called in the
                 port's mode (the VGA prototype with plenty of memory) */
#include "xcompat.h"
#include "plat.h"
#include "gfx.h"
#include "input.h"
#include "render.h"

static void said(const char *kind, const char *name)
{
    static const char *seen[64];
    static int n;
    char b[96];
    int i;

    for (i = 0; i < n; i++)
        if (seen[i] == name)
            return;
    if (n < 64)
        seen[n++] = name;
    sprintf(b, "asm: %s %s", kind, name);
    plat_note(b);
}
#define XD_TODO(name)   said("not ported yet:", name)
#define XD_NEVER(name)  said("called, but never expected here:", name)

/* ---------------------------------------------------------------- Watcom #pragma aux */

/* rules.h: a x b, 16 x 16 -> 32 bits; (a x b) >> 14. */
long rl_imul(int a, int b)
{
    return (long)(short)a * (short)b;
}

int rl_mul14(int a, int b)
{
    return (int)(short)(((long)(short)a * (short)b) >> 14);
}

/* startup.c, picplan.c, xmem.c: a 286 or better (the VGA program). */
int cpu_below_286(void)
{
    return 0;
}

/* sound.c: the Sound Blaster interrupt's own stack (no interrupts here). */
void sb_stack_enter(unsigned seg, unsigned top)
{
    (void)seg;
    (void)top;
}

void sb_stack_leave(void)
{
}

/* ---------------------------------------------------------------- video.asm */
void __cdecl vid_setmode(unsigned char mode)
{
    union REGS r;

    r.h.ah = 0;
    r.h.al = mode;
    int86(0x10, &r, &r);
}

/* Hercules (video.asm stubs into hgcasm.asm's copied block): never. */
void hgc_mark(int x0, int y0, int x1, int y1) { (void)x0; (void)y0; (void)x1; (void)y1; }
void hgc_show(int x0, int y0, int x1, int y1) { (void)x0; (void)y0; (void)x1; (void)y1; }
void hgc_flush(int scan) { (void)scan; }
void hgc_runs(const void far *frame) { (void)frame; XD_NEVER("hgc_runs"); }
void hgc_buf(unsigned bufseg, unsigned rows_r0, unsigned b0, unsigned n)
{ (void)bufseg; (void)rows_r0; (void)b0; (void)n; }  /* (gfx.c calls it on every present: a no-op off Hercules) */
void hgc_white2(void far *p, unsigned n) { (void)p; (void)n; XD_NEVER("hgc_white2"); }
void hgc_set(unsigned seg, unsigned off) { (void)seg; (void)off; XD_NEVER("hgc_set"); }
unsigned char hgc_off(void) { return 3; }
unsigned __cdecl hgc_blob(unsigned seg) { (void)seg; XD_NEVER("hgc_blob"); return 0; }

/* ---------------------------------------------------------------- blit.asm (EGA): never */
void __cdecl blit_masked(const void *spr, unsigned bufseg, unsigned dest)
{ (void)spr; (void)bufseg; (void)dest; XD_NEVER("blit_masked"); }
void __cdecl blit_or(const void *spr, unsigned bufseg, unsigned dest)
{ (void)spr; (void)bufseg; (void)dest; XD_NEVER("blit_or"); }
void __cdecl blit_masked_clip(const void *spr, unsigned bufseg, unsigned dest,
                              unsigned top, unsigned bottom, unsigned wmask)
{ (void)spr; (void)bufseg; (void)dest; (void)top; (void)bottom; (void)wmask; XD_NEVER("blit_masked_clip"); }
void __cdecl blit_or_clip(const void *spr, unsigned bufseg, unsigned dest,
                          unsigned top, unsigned bottom, unsigned wmask)
{ (void)spr; (void)bufseg; (void)dest; (void)top; (void)bottom; (void)wmask; XD_NEVER("blit_or_clip"); }
void __cdecl vram_box(unsigned bufseg, unsigned off, unsigned bytes, unsigned rows, int out)
{ (void)bufseg; (void)off; (void)bytes; (void)rows; (void)out; XD_NEVER("vram_box"); }
void __cdecl vram_shift(unsigned bytes, int delta) { (void)bytes; (void)delta; XD_NEVER("vram_shift"); }
void __cdecl buf_clear(unsigned bufseg) { (void)bufseg; XD_NEVER("buf_clear"); }
void __cdecl buf_clear_rect(unsigned bufseg, unsigned col, unsigned row, unsigned cols, unsigned rows)
{ (void)bufseg; (void)col; (void)row; (void)cols; (void)rows; XD_NEVER("buf_clear_rect"); }
void __cdecl buf_present_rect(unsigned bufseg, unsigned col, unsigned row, unsigned cols, unsigned rows)
{ (void)bufseg; (void)col; (void)row; (void)cols; (void)rows; XD_NEVER("buf_present_rect"); }

/* ---------------------------------------------------------------- the VGA view (vgaasm.asm), stage 2 */
/* The CGA-named calls vga_init points at vgaasm.asm's code: here they will
   be plat/vga.c's (the 8-bit back buffer, the sprite formats of
   tools/vgasprite.py, the present to the screen). */
#if !defined(XD_HAVE_VGABAT)
void __cdecl blitc_masked(const void *spr, unsigned bufseg, unsigned dest)
{ (void)spr; (void)bufseg; (void)dest; XD_TODO("blitc_masked"); }
void __cdecl blitc_or(const void *spr, unsigned bufseg, unsigned dest)
{ (void)spr; (void)bufseg; (void)dest; XD_TODO("blitc_or"); }
void __cdecl blitc_masked_clip(const void *spr, unsigned bufseg, unsigned dest,
                               unsigned top, unsigned bottom, unsigned wmask)
{ (void)spr; (void)bufseg; (void)dest; (void)top; (void)bottom; (void)wmask; XD_TODO("blitc_masked_clip"); }
void __cdecl blitc_or_clip(const void *spr, unsigned bufseg, unsigned dest,
                           unsigned top, unsigned bottom, unsigned wmask)
{ (void)spr; (void)bufseg; (void)dest; (void)top; (void)bottom; (void)wmask; XD_TODO("blitc_or_clip"); }
void __cdecl bufc_clear_rect(unsigned bufseg, unsigned col, unsigned row, unsigned cols, unsigned rows)
{ (void)bufseg; (void)col; (void)row; (void)cols; (void)rows; XD_TODO("bufc_clear_rect"); }
void __cdecl bufc_present_rect(unsigned bufseg, unsigned col, unsigned row, unsigned cols, unsigned rows)
{ (void)bufseg; (void)col; (void)row; (void)cols; (void)rows; XD_TODO("bufc_present_rect"); }
void __cdecl buf_shift(unsigned bufseg, unsigned plane_bytes, unsigned planes, int delta)
{ (void)bufseg; (void)plane_bytes; (void)planes; (void)delta; XD_TODO("buf_shift"); }
void __cdecl buf_box(unsigned bufseg, unsigned off, unsigned stride, unsigned bytes,
                     unsigned rows, void *save, int out)
{ (void)bufseg; (void)off; (void)stride; (void)bytes; (void)rows; (void)save; (void)out; XD_TODO("buf_box"); }
void __cdecl fxtile_ega(unsigned seg, unsigned off, const unsigned char *shape, unsigned r0,
                        unsigned r1, unsigned q01, unsigned q23, unsigned colour, unsigned cols)
{ (void)seg; (void)off; (void)shape; (void)r0; (void)r1; (void)q01; (void)q23; (void)colour; (void)cols; XD_NEVER("fxtile_ega"); }
void __cdecl fxtile_cga(unsigned seg, unsigned off, const unsigned char *shape, unsigned r0,
                        unsigned r1, unsigned q01, unsigned q23, unsigned colour, unsigned cols)
{ (void)seg; (void)off; (void)shape; (void)r0; (void)r1; (void)q01; (void)q23; (void)colour; (void)cols; XD_TODO("fxtile_cga"); }
#endif /* XD_HAVE_VGABAT */

unsigned __cdecl vga_blob(unsigned seg) { (void)seg; XD_TODO("vga_blob"); return 0; }
void far * __cdecl vga_near(int k) { (void)k; XD_TODO("vga_near"); return NULL; }
unsigned __cdecl vgx_blob(unsigned seg) { (void)seg; XD_TODO("vgx_blob"); return 0; }

#if !defined(XD_HAVE_VGABAT)
/* arrow.asm: the selected unit's arrow into the back buffer. */
int g_arrow[4];
void render_arrow(int c0, int r0, int cols, int rows)
{ (void)c0; (void)r0; (void)cols; (void)rows; XD_TODO("render_arrow"); }
void vga_gfx_night(int night) { (void)night; XD_TODO("vga_gfx_night"); }
void vga_gfx_dot(int x, int y, int colour) { (void)x; (void)y; (void)colour; XD_TODO("vga_gfx_dot"); }
const int far *vga_pics_next(void) { return NULL; }
void vga_pal(void) { XD_TODO("vga_pal"); }

#endif /* XD_HAVE_VGABAT */

/* uiasm.asm: EGA night colours of the panel: never (VGA has its own). */
void __cdecl uk_remap4(unsigned char far *planes, const unsigned char far *cmap)
{ (void)planes; (void)cmap; XD_NEVER("uk_remap4"); }
void __cdecl uk_remap_vram(void) { XD_NEVER("uk_remap_vram"); }

/* heldasm.asm: the inventory's held item at the pointer. */
void __cdecl held_blit(void far *h, unsigned what) { (void)h; (void)what; XD_TODO("held_blit"); }

/* cutasm.asm: the intro's frames (VGA: the FLI chunks). */
unsigned __cdecl cut_runs(const unsigned char far *src, unsigned planes, unsigned vseg)
{ (void)src; (void)planes; (void)vseg; XD_NEVER("cut_runs"); return 0; }
unsigned __cdecl cut_fli(const unsigned char far *frame) { (void)frame; XD_TODO("cut_fli"); return 0; }

/* litasm.asm: EGA night light: never. */
void __cdecl lit_rect(unsigned bufseg, void far *now, unsigned c0, unsigned r0, unsigned cols, unsigned rows)
{ (void)bufseg; (void)now; (void)c0; (void)r0; (void)cols; (void)rows; XD_NEVER("lit_rect"); }
void __cdecl lit_disc(void) { XD_NEVER("lit_disc"); }

/* cvasm.asm: the canvas in EMS / XMS: never (no EMS, no XMS here). */
void __cdecl cv_copy(void) { XD_NEVER("cv_copy"); }
unsigned __cdecl cv_cmp(void) { XD_NEVER("cv_cmp"); return 0; }
void __cdecl cv_map(void) { XD_NEVER("cv_map"); }
unsigned __cdecl cv_seen(unsigned char far *seen, unsigned idx, int step, unsigned n)
{ (void)seen; (void)idx; (void)step; (void)n; XD_NEVER("cv_seen"); return 0; }

/* ---------------------------------------------------------------- the game's own assembly (stage 3) */
/* No C version upstream: OpenXcom's C++ and the assembly's comments are
   the reference; each will be written in C and checked against the
   original's results (vbench.c, shotcheck.py). */
#if !defined(XD_HAVE_VOX)
int __cdecl vox_run(void *r, int resume) { (void)r; (void)resume; XD_TODO("vox_run (voxasm.asm)"); return -1; }
#endif /* XD_HAVE_VOX */

#if !defined(XD_HAVE_LOS)
int __cdecl reveal_fan_asm(const void *p) { (void)p; XD_TODO("reveal_fan_asm (losasm.asm)"); return 0; }
void __cdecl reveal_reset_box(void) { XD_TODO("reveal_reset_box (losasm.asm)"); }
void __cdecl reveal_get_box(unsigned char *box) { box[0] = 1; box[1] = 0; XD_TODO("reveal_get_box (losasm.asm)"); }
#endif /* XD_HAVE_LOS */

#if !defined(XD_HAVE_REND)
void __cdecl rd_setup(int top, const void *mcd, unsigned char **spr, unsigned *late,
                      unsigned char *add, unsigned char *occ)
{ (void)top; (void)mcd; (void)spr; (void)late; (void)add; (void)occ; XD_TODO("rd_setup (rendasm.asm)"); }
int __cdecl rd_level(int z) { (void)z; XD_TODO("rd_level (rendasm.asm)"); return 0; }
#endif /* XD_HAVE_REND */

/* pathasm.asm mirrors path.c's search_c (vbench.c path_search_c): that
   one until the port has a faster one. */
void path_search_c(void *p);
void __cdecl path_search_asm(const void *p) { path_search_c((void *)p); }
#if !defined(XD_HAVE_WAY)
void __cdecl path_doors_asm(unsigned seg, unsigned n, unsigned char *map, const void *mcd)
{ (void)seg; (void)n; (void)map; (void)mcd; XD_TODO("path_doors_asm (wayasm.asm)"); }

#endif /* XD_HAVE_WAY */

/* sndasm.asm: XMS (none here) and the tight battles' picture faults
   (sprite_in: a picture paged out to the disk cache; never with the
   memory this port gives). */
unsigned long __cdecl xms_find(void) { return 0; }
void __cdecl xms_call(unsigned far *r) { (void)r; XD_NEVER("xms_call"); }
void __cdecl sprite_fault(unsigned char **e, unsigned i) { (void)e; (void)i; XD_TODO("sprite_fault"); }
void __cdecl sprite_in(unsigned char **e, unsigned i) { (void)e; (void)i; }

/* xmemres.asm, xmemhma.asm: the EMS / XMS read cache: never. */
unsigned char xmem_hstub[1], xmem_hblob[1], xmem_stub[1], xmem_blob[1];

/* rdcount.asm: the reads counted (a DOS hook): the counts stay 0. */
static unsigned rd_n;
static unsigned long rd_b;
unsigned __cdecl rd_count(void) { return rd_n; }
unsigned long __cdecl rd_bytes(void) { return rd_b; }
void __cdecl rd_count_start(void) {}
void __cdecl rd_count_stop(void) {}

/* Watcom's dynamic overlay manager: no overlays (everything resident). */
void _ovl_addarea(unsigned seg, unsigned paras) { (void)seg; (void)paras; }
