; SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
; Copyright (c) 2026 Carlos Bravo
; Atari816 audio noise test 2: what makes the clicks while the desktop is shown?
; Classic machine frozen throughout, desktop 640x360x8 showing vertical stripes.
;   1 STATIC   nothing changes (5 s)
;   2 PALETTE  picture changes through the palette only, no memory traffic (7 s)
;   3 WRITES   memory writes to RAM that is not displayed, picture static (7 s)
;   4 BASE     picture jumps one line up and down via NV_BASE (7 s)
; 4 s of static picture between phases.
        .p816
        .smart  -
NV_CTRL     = $00D900
NV_BASE     = $00D901
PAL_IDX     = $00D910
PAL_R       = $00D911
PAL_G       = $00D912
PAL_B       = $00D913
SV_CTRL     = $00DC00
UPTIME      = $00DE18
DBG_OUT     = $00DEF0
DBG_STAT    = $00DEF1
t0      = $10
flip    = $11
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
        ; stripes: 4 banks $04..$07, byte = low address byte
        ldx     #0
:       txa
        sta     f:$040000,x
        sta     f:$050000,x
        sta     f:$060000,x
        sta     f:$070000,x
        inx
        bne     :-
        lda     #$00
        sta     f:NV_BASE
        sta     f:NV_BASE+1
        lda     #$04
        sta     f:NV_BASE+2
        lda     #$01
        sta     f:NV_CTRL

        ldx     #.loword(m1)
        jsr     puts
        lda     #76
        jsr     quiet

        ldx     #.loword(m2)
        jsr     puts
        jsr     mark
p2:     lda     flip
        eor     #$FF
        sta     flip
        lda     #$00
        sta     f:PAL_IDX
        ldx     #0
:       txa
        eor     flip
        sta     f:PAL_R
        sta     f:PAL_G
        sta     f:PAL_B
        inx
        cpx     #256
        bne     :-
        jsr     tick2
        lda     #107
        jsr     timeup
        bcc     p2
        lda     #61
        jsr     quiet

        ldx     #.loword(m3)
        jsr     puts
        jsr     mark
p3:     ldx     #0
        lda     #$00
:       sta     f:$090000,x
        eor     #$FF
        inx
        bne     :-
        lda     #107
        jsr     timeup
        bcc     p3
        lda     #61
        jsr     quiet

        ldx     #.loword(m4)
        jsr     puts
        jsr     mark
p4:     lda     #$80
        sta     f:NV_BASE
        lda     #$02
        sta     f:NV_BASE+1
        jsr     tick2
        lda     #$00
        sta     f:NV_BASE
        sta     f:NV_BASE+1
        jsr     tick2
        lda     #107
        jsr     timeup
        bcc     p4
        lda     #30
        jsr     quiet

        lda     #$00
        sta     f:NV_CTRL
        sta     f:SV_CTRL
        ldx     #.loword(m5)
        jsr     puts
        stp

mark:   lda     f:UPTIME
        lda     f:UPTIME+2
        sta     t0
        rts
; A = length in 65.5 ms units; carry set when passed
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
; wait two uptime ticks (about 130 ms)
tick2:  jsr     tick1
tick1:  lda     f:UPTIME
        lda     f:UPTIME+2
        pha
:       lda     f:UPTIME
        lda     f:UPTIME+2
        cmp     1,s
        beq     :-
        pla
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
m1:     .byte "1 STATIC", 10, 0
m2:     .byte "2 PALETTE", 10, 0
m3:     .byte "3 HIDDEN WRITES", 10, 0
m4:     .byte "4 BASE", 10, 0
m5:     .byte "DONE", 10, 0
