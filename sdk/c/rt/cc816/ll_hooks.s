; ll_hooks.s - scanf's long long conversions, only for programs that use long long.
;
; The compiler writes ".forceimport __cc816_scanll" into a unit that uses long long and
; calls a scanf function (or gives a long long pointer to any variadic function), so ld65
; links this module into those programs only. Its constructor (run by crt0.s before main)
; installs the conversions in scanf (lib/cc816/scan.c: %lld %llu %llx ..., done by
; lib/cc816/scanll.c). Without it ll is read as l. (ll_hookp.s is printf's.)
	.p816
	.smart	-
	.a16
	.i16
	.import	___hz_scanll, ___hz_scan_ll
	.export	__cc816_scanll
	.constructor ll_inits, 1

	.segment "CODE"

__cc816_scanll:
ll_inits:
	lda	#___hz_scanll
	sta	___hz_scan_ll
	rts
