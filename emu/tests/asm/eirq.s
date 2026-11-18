; Emulation-mode IRQ: the stacked P must have bit 4 (B) clear, as on a WDC 65C816.
; Before the P65C816.v fix the RTL pushed $30; now $20.
        .include "common.inc"
        .a8
        .i16
start:  clc
        xce
        rep     #$10
        sep     #$20
        ldx     #$01FF
        txs
        phk
        plb
        lda     #$5C
        sta     f:$00E000
        lda     #<irq_h
        sta     f:$00E001
        lda     #>irq_h
        sta     f:$00E002
        lda     #$01
        sta     f:$00E003
        lda     #$00
        sta     f:$00FFFE
        lda     #$E0
        sta     f:$00FFFF
        lda     #20
        sta     f:$00DE10
        lda     #0
        sta     f:$00DE11
        sta     f:$00DE12
        lda     #$04
        sta     f:$00DE09
        lda     #$01
        sta     f:$00DE13
        sec
        xce
        cli
:       bra     :-
irq_h:  clc
        xce
        rep     #$10
        sep     #$20
        lda     1,s                     ; P pushed in emulation mode
        pha
        phk
        plb
        print   m
        pla
        jsr     puthex
        jsr     crlf
        print   d
        stp
m:      .byte "E-MODE IRQ PUSHED P ", 0
d:      .byte "DONE", 10, 0
