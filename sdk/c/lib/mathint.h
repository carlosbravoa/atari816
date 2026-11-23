/* mathint.h - what the cc816 C library's math files share (not for programs).
 *
 * float, double and long double are one format (IEEE 754 single), so the math functions
 * are written once, in float, and named with the double names (math.h maps sinf and
 * sinl to sin). The algorithms are those of fdlibm (Sun Microsystems, 1993: "Developed at
 * SunPro, a Sun Microsystems, Inc. business. Permission to use, copy, modify, and
 * distribute this software is freely granted, provided that this notice is preserved.")
 * in their single-precision form; the reduction of large arguments of sin, cos and tan is
 * cc816's own (exact integer arithmetic, math_trig.c). The integer types are explicit (int is
 * 16 bits here), so the same files give the same results, bit for bit, built for the host
 * (tests/fpu/mathhost.sh).
 */
#include <stdint.h>

#ifdef __CC816__
/* cc816's builtins: a float's 32 bits as an unsigned long and back, no code */
#define GETW(i, x) ((i) = __builtin_fbits(x))
#define SETW(x, i) ((x) = __builtin_bitsf((uint32_t)(i)))
#else
/* the same on the PC (tests/fpu/mathhost.sh builds this library with the PC's compiler) */
typedef union { float f; uint32_t u; } __fw;
#define GETW(i, x) do { __fw t_; t_.f = (x); (i) = t_.u; } while (0)
#define SETW(x, i) do { __fw t_; t_.u = (uint32_t)(i); (x) = t_.f; } while (0)
#endif
#define ABSW(i) ((i) & 0x7FFFFFFFUL)
#define IS_NAN(w) (ABSW(w) > 0x7F800000UL)
#define IS_INF(w) (ABSW(w) == 0x7F800000UL)
#define IS_FINITE(w) (ABSW(w) < 0x7F800000UL)
#define IS_ZERO(w) (ABSW(w) == 0)
#define IS_SUB(w) (ABSW(w) < 0x00800000UL)

double __hz_scalb(double x, long n);
