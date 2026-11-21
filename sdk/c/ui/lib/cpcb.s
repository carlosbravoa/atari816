; cpcb.s - ui_setcpcb: a C function as the copy routines' callback (ui_cpcb). The library
; calls ui_cpcb with JSR (uicopy.s) and reads the carry: set = cancel. The C function:
; int fn(const char *name, unsigned k, unsigned long size), nonzero = cancel.
        .p816
        .smart  off
        .include "horizon.inc"
        .include "ui.inc"
        .include "huidefs.inc"

        .segment "BSS"
cpfn:   .res    4
cres:   .res    2


        .segment "CODE"
        .a16
        .i16

; A = the C function's offset, X = its bank (0, 0: none)
hui_setcpcb:
        sta     cpfn
        stx     cpfn+2
        ora     cpfn+2
        beq     :+
        lda     #.loword(tramp)
:       sta     ui_cpcb
        rts

tramp:  ZSAVE
        lda     cpfn
        sta     z:hui_fn
        lda     cpfn+2
        sta     z:hui_fn+2
        inc     hui_incb
        lda     ui_cpsize+2             ; unsigned long size
        pha
        lda     ui_cpsize
        pha
        lda     ui_cpk                  ; unsigned k
        pha
        lda     ui_cpname               ; const char *name: A = offset, X = bank
        ldx     #^cpfn
        CALLC
        ply
        ply
        ply
        dec     hui_incb
        sta     cres
        ZRESTORE
        lda     cres
        cmp     #1                      ; C set: nonzero, cancel
        rts
