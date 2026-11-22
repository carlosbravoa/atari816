; cpcb.s - ui_setcpcb for cc816: a C function as the copy routines' callback (ui_cpcb).
; The library calls ui_cpcb with JSR (uicopy.s) and reads the carry: set = cancel. The C
; function: int fn(const char *name, unsigned k, unsigned long size), nonzero = cancel.
        .p816
        .smart  off
        .include "horizon.inc"
        .include "ui.inc"
        .include "hui816.inc"

        .segment "BSS"
cpfn:   .res    2
cres:   .res    2

        .segment "CODE"
        .a16
        .i16

; A = the C function (0: none)
hui_setcpcb:
        sta     cpfn
        cmp     #0
        beq     :+
        lda     #tramp
:       sta     ui_cpcb
        rts

tramp:  ZSAVE
        inc     hui_incb
        lda     ui_cpsize+2             ; unsigned long size
        pha
        lda     ui_cpsize
        pha
        lda     ui_cpk                  ; unsigned k
        pha
        lda     ui_cpname               ; const char *name
        pha
        ldx     #0
        jsr     (cpfn,x)
        sta     cres
        ply
        ply
        ply
        ply
        dec     hui_incb
        ZRESTORE
        lda     cres
        cmp     #1                      ; C set: nonzero, cancel
        rts
