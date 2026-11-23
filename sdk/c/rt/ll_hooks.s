; ll_hooks.s - scanf's long long conversions, only for programs that use long long.
;
; The compiler writes ".forceimport __cc816_scanll" into a unit that uses long long and
; calls a scanf function (or gives a long long pointer to any variadic function), so ld65
; links this module into those programs only. Its constructor (run by crt0.s before main)
; installs the conversions in scanf (lib/scan.c: %lld %llu %llx ..., done by
; lib/scanll.c). Without it ll is read as l. (ll_hookp.s is printf's.)
	.p816
	.smart	-
	.a16
	.i16
	.include "model.inc"
	.import	___hz_scanll, ___hz_scan_ll
	.export	__cc816_scanll
	.constructor ll_inits, 1

	.segment "CODE"

__cc816_scanll:
ll_inits:
	; (a function pointer: in the large code model its 16-bit address is __T<name>, the
	; function itself or a thunk when hcc puts it in another bank)
.if LARGE
	.import	__T___hz_scanll
	lda	#__T___hz_scanll
.else
	lda	#___hz_scanll
.endif
	sta	___hz_scan_ll
	RET
