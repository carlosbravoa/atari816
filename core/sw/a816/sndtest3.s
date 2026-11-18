; SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
; Copyright (c) 2026 Carlos Bravo
; Atari816 audio noise test 3: does debug log output make the clicks?
; 5 s quiet, 8 s of continuous DBG_OUT bytes, 4 s quiet. Classic machine frozen, shown.
        .p816
        .smart  -
SV_CTRL     = $00DC00
UPTIME      = $00DE18
DBG_OUT     = $00DEF0
DBG_STAT    = $00DEF1
t0      = $10
len     = $12
        .segment "CODE"
        .a8
        .i16
start:  clc
        xce
        rep     #$10
        sep     #$20
        ldx     #$BFFF
        txs
        phk
        plb
        lda     #$04
        sta     f:SV_CTRL
        lda     #76
        jsr     quiet
        jsr     mark
p2:     ldx     #60
:       lda     #'U'
        jsr     putc
        dex
        bne     :-
        lda     #10
        jsr     putc
        lda     #122
        jsr     timeup
        bcc     p2
        lda     #61
        jsr     quiet
        lda     #$00
        sta     f:SV_CTRL
        ldx     #.loword(m5)
        jsr     puts
        stp
mark:   lda     f:UPTIME
        lda     f:UPTIME+2
        sta     t0
        rts
timeup: sta     len
        lda     f:UPTIME
        lda     f:UPTIME+2
        sec
        sbc     t0
        cmp     len
        rts
quiet:  pha
        jsr     mark
        pla
        sta     len
:       lda     len
        jsr     timeup
        bcc     :-
        rts
putc:   pha
:       lda     f:DBG_STAT
        bmi     :-
        pla
        sta     f:DBG_OUT
        rts
puts:   lda     a:0,x
        beq     :+
        jsr     putc
        inx
        bra     puts
:       rts
m5:     .byte "DONE", 10, 0
