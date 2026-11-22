; fp_hookp.s - printf's floating-point conversions, only for programs that use them.
;
; The compiler writes ".forceimport __cc816_fmtf" into a unit that uses floating point
; and calls a printf function (or gives a float to any variadic function: a printf
; wrapper), so ld65 links this module into those programs only. Its constructor (run by
; crt0.s before main) installs the float conversions in the formatter (lib/cc816/fmt.c:
; %f %F %e %E %g %G %a %A, done by lib/cc816/fmtfp.c). Without it they print as written.
; (fp_hooks.s is scanf's.)
	.p816
	.smart	-
	.a16
	.i16
	.include "model.inc"
	.import	___hz_fmtfp, ___hz_fmt_float
	.export	__cc816_fmtf
	.constructor fp_initp, 1

	.segment "CODE"

__cc816_fmtf:
fp_initp:
	lda	#___hz_fmtfp
	sta	___hz_fmt_float
	RET
