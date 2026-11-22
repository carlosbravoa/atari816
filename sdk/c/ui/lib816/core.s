; core.s - what every cc816 shim uses: the register staging words, the failure exit,
; hz_errno.
        .p816
        .smart  off
        .include "horizon.inc"
        .include "ui.inc"
        .include "hui816.inc"
        .import ___hui_fatal, _hz_errno

        .segment "ZEROPAGE"
hui_ra: .res    2               ; A, X, Y for the routine (staged by a shim), then its results
hui_rx: .res    2
hui_ry: .res    2
hui_cy: .res    2               ; the routine's carry (0 / 1)
hui_d:  .res    2               ; xoff's X before the call

        .segment "ZPEND"                ; (hzprog.cfg: after every module's ZEROPAGE)
hui_zend: .res  2

        .segment "BSS"
hui_incb: .res  2               ; nonzero while a callback into C runs

        .segment "CODE"
        .a16
        .i16

; A = a message in the code bank ("ui_lsset"), Y = what is wrong (1: a control routine
; inside a callback): to the C program's void __hui_fatal(const char *msg, unsigned what),
; which says it in words and exits
hui_fail:
        phy
        pha
        jsr     ___hui_fatal            ; (never returns)

; A -> the C library's hz_errno (keeps A)
hui_seterr:
        sta     _hz_errno
        rts
