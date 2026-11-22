; fp_hooks.s - scanf's floating-point conversions, only for programs that use them.
;
; The compiler writes ".forceimport __cc816_scanf" into a unit that uses floating point
; and calls a scanf function (or gives a float pointer to any variadic function), so ld65
; links this module into those programs only. Its constructor (run by crt0.s before main)
; installs the float conversions in scanf (lib/cc816/scan.c: %f %e %g %a, done by
; lib/cc816/scanfp.c with strtod). Without it they fail. (fp_hookp.s is printf's.)
	.p816
	.smart	-
	.a16
	.i16
	.include "model.inc"
	.import	___hz_scanfp, ___hz_scan_float
	.export	__cc816_scanf
	.constructor fp_inits, 1

	.segment "CODE"

__cc816_scanf:
fp_inits:
	lda	#___hz_scanfp
	sta	___hz_scan_float
	RET
