; SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
; Copyright (c) 2026 Carlos Bravo
; Atari816 native sound test (REV 07). With the classic machine frozen, POKEY 2 is at
; $00:DB00-$DB0F and four 8-bit DACs at $00:DB10-$DB13 (0,1 left; 2,3 right).
;   1 TONE     POKEY 2 pure tone, both sides, 3 s
;   2 CHORD    three POKEY voices, 3 s
;   3 DAC L    sawtooth on DAC 0 (left only), 2 s
;   4 DAC R    sawtooth on DAC 2 (right only), 2 s
        .p816
        .smart  -
SND         = $00DB00
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
        lda     #$00
        sta     f:SND+8                 ; AUDCTL
        lda     #$03
        sta     f:SND+15                ; SKCTL: out of reset
        ldx     #.loword(m1)
        jsr     puts
        lda     #$79
        sta     f:SND+0
        lda     #$A8
        sta     f:SND+1
        lda     #46
        jsr     quiet
        ldx     #.loword(m2)
        jsr     puts
        lda     #$60
        sta     f:SND+2
        lda     #$A8
        sta     f:SND+3
        lda     #$50
        sta     f:SND+4
        lda     #$A8
        sta     f:SND+5
        lda     #46
        jsr     quiet
        lda     #$00
        sta     f:SND+1
        sta     f:SND+3
        sta     f:SND+5
        ldx     #.loword(m3)
        jsr     puts
        ldx     #$0010
        jsr     saw
        ldx     #.loword(m4)
        jsr     puts
        ldx     #$0012
        jsr     saw
        lda     #$00
        sta     f:SV_CTRL
        ldx     #.loword(m5)
        jsr     puts
        stp

; sawtooth on DAC register X for 2 s
saw:    stx     z:$14
        jsr     mark
@l:     ldy     #0
@s:     tya
        asl
        asl
        ldx     z:$14
        sta     f:SND,x
        ldx     #40
:       dex
        bne     :-
        iny
        cpy     #64
        bne     @s
        lda     #30
        jsr     timeup
        bcc     @l
        lda     #$00
        ldx     z:$14
        sta     f:SND,x
        rts

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
m1:     .byte "1 TONE", 10, 0
m2:     .byte "2 CHORD", 10, 0
m3:     .byte "3 DAC LEFT", 10, 0
m4:     .byte "4 DAC RIGHT", 10, 0
m5:     .byte "DONE", 10, 0
