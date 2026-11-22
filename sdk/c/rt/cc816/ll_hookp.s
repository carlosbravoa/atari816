; ll_hookp.s - printf's long long conversions, only for programs that use long long.
;
; The compiler writes ".forceimport __cc816_fmtll" into a unit that uses long long and
; calls a printf function (or gives a long long to any variadic function), so ld65 links
; this module into those programs only. Its constructor (run by crt0.s before main)
; installs the conversions in the formatter (lib/cc816/fmt.c: %lld %llu %llx ..., done by
; lib/cc816/fmtll.c). Without it ll is read as l. (ll_hooks.s is scanf's.)
	.p816
	.smart	-
	.a16
	.i16
	.include "model.inc"
	.import	___hz_fmtll, ___hz_fmt_ll
	.export	__cc816_fmtll
	.constructor ll_initp, 1

	.segment "CODE"

__cc816_fmtll:
ll_initp:
	lda	#___hz_fmtll
	sta	___hz_fmt_ll
	RET
