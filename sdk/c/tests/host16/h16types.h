/* h16types.h - types behind macros and typedefs (host16.py's test) */
#define QUAD long
#define WORD int
typedef unsigned short u16;
typedef unsigned QUAD u32;
struct rec { char tag; int value; long big; };
