; hui816.inc - the cc816 binding's own symbols (ui/lib816/*.s, the generated shims of
; tools/genhui.py --shims816). ca65 syntax, included after horizon.inc and ui.inc.
;
; With cc816 the controls library is linked straight into the program by ld65 (no block):
; its routines, its zero page and its data sit beside the program's. Every cc816 data
; pointer is an offset in the code bank, where the library reads its structures (DBR).

.global hui_fail                ; A = message, Y = 1: the C program's __hui_fatal (never returns)
.global hui_seterr              ; A -> hz_errno (keeps A)
.global hui_incb                ; nonzero inside a callback into C
.global hui_rowtramp            ; the list row callback (row.s)
.global hui_setwin, hui_setcpcb ; ui_setwin, ui_setcpcb (setwin.s, cpcb.s)
.globalzp hui_ra, hui_rx, hui_ry, hui_cy, hui_d

; ZSAVE / ZRESTORE: the direct page of the library, ulib and this binding (from the end
; of cc816's registers, __hz_zpend, crt0.s, to hui_zend, the ZPEND segment: words)
; pushed on the stack and pulled back around a call into C, which may itself call the
; library (ui_rect, ui_text ...). A, X clobbered.
.globalzp __hz_zpend, hui_zend
.macro  ZSAVE
        .local  lp
        ldx     #hui_zend - 2
lp:     lda     z:0,x
        pha
        dex
        dex
        cpx     #__hz_zpend
        bcs     lp
.endmacro
.macro  ZRESTORE
        .local  lp
        ldx     #__hz_zpend
lp:     pla
        sta     z:0,x
        inx
        inx
        cpx     #hui_zend
        bcc     lp
.endmacro
