/* SPDX-License-Identifier: GPL-3.0-or-later */
/* xdos.h: the DOS machine the engine was written for, as a small model in
   C (plat/xdos.c): no x86 is emulated, only what the C code touches.
   - Memory: real mode's first megabyte is one arena (xd_mem): segment s,
     offset o is byte s * 16 + o of it. The engine's heap (malloc and
     _dos_allocmem alike) is a DOS memory chain in its first 640 KB, so
     that segment arithmetic on heap pointers (FP_SEG(p) + 1, MK_FP(seg,
     0)) works as on DOS; A000 is the VGA picture, B800 the CGA page,
     0040:006C the BIOS clock, the PSP and the program's MCB are where
     the engine reads them. On the Atari816 the arena is 16 banks: a
     block never crosses a bank, as a DOS block never passes 64 KB.
   - Interrupts (int86, intdos): the services the engine asks for, each
     answered by a function (xd_int); ports (inp, outp): the VGA DAC, the
     OPL2, the PIT, the keyboard controller, the rest ignored.
   - Files: DOS names (case, backslashes, the mode folder rdcount.asm
     added) over the platform's files. */
#ifndef XDOS_H
#define XDOS_H

/* ---------------------------------------------------------------- memory */
#if defined(__CC816__)
typedef unsigned char __far *xd_ptr;
#else
typedef unsigned char *xd_ptr;
#endif
extern xd_ptr xd_mem;                   /* the arena: linear 0 */
#define XD_ARENA        0x110000UL      /* 1 MB + the HMA's 64 KB */
#define XD_HEAP_SEG     0x0100u         /* the engine's DOS chain starts here */
#define XD_HEAP_END     0xA000u         /* ... and ends at 640 KB */

#if defined(__CC816__)
void __far *xd_mkfp(unsigned seg, unsigned off);
unsigned xd_seg(const void __far *p);
unsigned xd_off(const void __far *p);
#define MK_FP(s, o)     xd_mkfp((unsigned)(s), (unsigned)(o))
#define FP_SEG(p)       xd_seg((const void __far *)(p))
#define FP_OFF(p)       xd_off((const void __far *)(p))
#else
void *xd_mkfp(unsigned seg, unsigned off);
unsigned xd_seg(const void *p);
unsigned xd_off(const void *p);
#define MK_FP(s, o)     xd_mkfp((unsigned)(s), (unsigned)(o))
#define FP_SEG(p)       xd_seg((const void *)(p))
#define FP_OFF(p)       xd_off((const void *)(p))
#endif

/* The engine's heap (Watcom's large model: malloc is the far heap, made of
   DOS blocks). Every block starts at offset 0 of its own segment. On the
   Atari816 this needs pointers that are far by default (cc816 has none
   yet: PORTING-NOTES.md, SDK need 1); until then the engine's malloc is
   the SDK's (the main bank) and only _dos_allocmem gives arena memory. */
#if !defined(__CC816__) || defined(XD_FAR_DATA)
#define XD_HEAP_IN_ARENA 1
#endif
void *xd_malloc(size_t n);
void *xd_calloc(size_t n, size_t k);
void *xd_realloc(void *p, size_t n);
void xd_free(void *p);
#if defined(XD_HEAP_IN_ARENA)
#define malloc(n)       xd_malloc(n)
#define calloc(n, k)    xd_calloc(n, k)
#define realloc(p, n)   xd_realloc(p, n)
#define free(p)         xd_free(p)
#endif
#define _nmalloc(n)     malloc(n)
#define _fmalloc(n)     malloc(n)
#define _ffree(p)       free(p)
#define _fheapshrink()  ((void)0)
#define _nheapshrink()  ((void)0)
extern unsigned _amblksiz;
extern unsigned _psp;
extern int __argc;
extern char **__argv;

unsigned _dos_allocmem(unsigned paras, unsigned *seg);
unsigned _dos_freemem(unsigned seg);
unsigned _dos_setblock(unsigned paras, unsigned seg, unsigned *max);

#define _fmemcpy        memcpy
#define _fmemmove       memmove
#define _fmemset        memset
#define _fmemcmp        memcmp
#define _fstrcpy        strcpy
#define _fstrlen        strlen

/* ---------------------------------------------------------------- registers */
struct WORDREGS { unsigned short ax, bx, cx, dx, si, di, cflag; };
struct BYTEREGS { unsigned char al, ah, bl, bh, cl, ch, dl, dh; };
union REGS { struct WORDREGS x; struct WORDREGS w; struct BYTEREGS h; };
struct SREGS { unsigned short es, cs, ss, ds; };

int int86(int n, union REGS *in, union REGS *out);
int int86x(int n, union REGS *in, union REGS *out, struct SREGS *s);
int intdos(union REGS *in, union REGS *out);
int intdosx(union REGS *in, union REGS *out, struct SREGS *s);
void segread(struct SREGS *s);
/* intr: all registers (hud.c asks the BIOS for its font). */
union REGPACK {
    struct { unsigned short ax, bx, cx, dx, bp, si, di, ds, es, flags; } w;
    struct { unsigned short ax, bx, cx, dx, bp, si, di, ds, es, flags; } x;
    struct { unsigned char al, ah, bl, bh, cl, ch, dl, dh; } h;
};
void intr(int n, union REGPACK *r);

/* Ports. */
unsigned inp(unsigned port);
unsigned outp(unsigned port, unsigned value);
unsigned outpw(unsigned port, unsigned value);
unsigned inpw(unsigned port);
#define _enable()       ((void)0)
#define _disable()      ((void)0)
void delay(unsigned ms);
void sound(unsigned hz);
void nosound(void);

/* Interrupt vectors: kept, never called (no code runs in interrupts on
   the platforms; the timer hook is called from xd_poll). */
typedef void (*xd_isr)(void);
xd_isr _dos_getvect(unsigned n);
void _dos_setvect(unsigned n, xd_isr f);
void _chain_intr(xd_isr f);

/* The BIOS keyboard. */
#define _KEYBRD_READ        0
#define _KEYBRD_READY       1
#define _KEYBRD_SHIFTSTATUS 2
unsigned _bios_keybrd(unsigned cmd);
int kbhit(void);
int getch(void);

/* ---------------------------------------------------------------- files */
#define _A_NORMAL   0x00
#define _A_RDONLY   0x01
#define _A_HIDDEN   0x02
#define _A_SYSTEM   0x04
#define _A_SUBDIR   0x10
#define _A_ARCH     0x20
#ifndef O_BINARY
#define O_BINARY    0
#endif
struct find_t {
    char reserved[21];
    char attrib;
    unsigned short wr_time, wr_date;
    unsigned long size;
    char name[13];
};
unsigned _dos_findfirst(const char *path, unsigned attr, struct find_t *f);
unsigned _dos_findnext(struct find_t *f);
unsigned _dos_findclose(struct find_t *f);
unsigned _dos_open(const char *path, unsigned mode, int *handle);
unsigned _dos_creat(const char *path, unsigned attr, int *handle);
unsigned _dos_close(int handle);
#if defined(__CC816__)
unsigned _dos_read(int handle, void __far *buf, unsigned n, unsigned *got);
unsigned _dos_write(int handle, const void __far *buf, unsigned n, unsigned *put);
#else
unsigned _dos_read(int handle, void *buf, unsigned n, unsigned *got);
unsigned _dos_write(int handle, const void *buf, unsigned n, unsigned *put);
#endif

/* stdio and POSIX names over DOS names (case, '\\', the mode folder). */
FILE *xd_fopen(const char *name, const char *mode);
int xd_open(const char *name, int flags, ...);
int xd_access(const char *name, int mode);
int xd_remove(const char *name);
int xd_rename(const char *a, const char *b);
#define fopen(n, m)     xd_fopen(n, m)
#define open            xd_open
#define access(n, m)    xd_access(n, m)
#define remove(n)       xd_remove(n)
#define rename(a, b)    xd_rename(a, b)
#define unlink(n)       xd_remove(n)
#define stricmp         strcasecmp
#define strnicmp        strncasecmp
char *strupr(char *s);
char *strlwr(char *s);
char *xd_getenv(const char *name);
#define getenv(n)       xd_getenv(n)
/* The mode folder's letter (rdcount.asm's rd_dir): read-only opens try
   "<x>GA/name" first. */
extern char rd_dir;

#if !defined(__CC816__)
/* The printf family with "%ld" etc. read as the 32-bit int `long` is
   here (xcompat.h). */
int xd_printf(const char *fmt, ...);
int xd_sprintf(char *buf, const char *fmt, ...);
int xd_fprintf(FILE *f, const char *fmt, ...);
int xd_vsprintf(char *buf, const char *fmt, va_list ap);
int xd_vfprintf(FILE *f, const char *fmt, va_list ap);
int xd_snprintf(char *buf, size_t n, const char *fmt, ...);
int xd_vsnprintf(char *buf, size_t n, const char *fmt, va_list ap);
#define printf          xd_printf
#define sprintf         xd_sprintf
#define fprintf         xd_fprintf
#define vsprintf        xd_vsprintf
#define vfprintf        xd_vfprintf
#define snprintf        xd_snprintf
#define vsnprintf       xd_vsnprintf
#endif

/* ---------------------------------------------------------------- the platform */
/* Called by the model whenever the engine waits or polls (BIOS keyboard,
   the clock, the mouse): the platform's events, the timer hook. */
void xd_poll(void);

#endif
