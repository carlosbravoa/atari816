; core.s - what every shim uses: the register staging words, the failure exit, hz_errno.
        .p816
        .smart  off
        .include "horizon.inc"
        .include "ui.inc"
        .include "huidefs.inc"

        .segment "ZEROPAGE"
hui_ra: .res    2               ; A, X, Y for the routine (staged by a shim), then its results
hui_rx: .res    2
hui_ry: .res    2
hui_cy: .res    2               ; the routine's carry (0 / 1)
hui_s:  .res    4               ; a C pointer (offset, bank)
hui_d:  .res    2               ; str.s: the destination
hui_fn: .res    4               ; a C function's address (CALLC)

        .segment "ZPEND"                ; (blob.cfg: after every module's ZEROPAGE)
hui_zend: .res  2

        .segment "BSS"
hui_incb: .res  2               ; nonzero while a callback into C runs

        .segment "CODE"
        .a16
        .i16

; A = a message in the code bank ("ui_draw: ctl"), Y = what is wrong (0: an object not in
; the code bank, 1: a control routine inside a callback): to the C program's __hui_fatal,
; which says it in words and exits
hui_fail:
        phy                             ; (its second argument)
        ldx     #^hui_fail
        jsl     HUI_FATAL               ; (JML ___hui_fatal: as if called, never returns)

; A -> the C library's hz_errno (keeps A)
hui_seterr:
        ldx     HUI_ERRNO
        sta     a:0,x
        rts
