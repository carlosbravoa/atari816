; SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
; Copyright (c) 2026 Carlos Bravo
; Atari816 audio noise test. Four phases of 6 s each, announced on the log. The screen shows
; the classic machine throughout (desktop off). Listen for clicks in each phase:
;   1 idle            65C816 waits, classic machine runs
;   2 memory traffic  65C816 writes RAM flat out, classic machine runs
;   3 traffic+frozen  same traffic, classic machine frozen (its sound output cannot change)
;   4 idle+frozen     65C816 waits, classic machine frozen
        .p816
        .smart  -
SV_CTRL     = $00DC00
UPTIME      = $00DE18
DBG_OUT     = $00DEF0
DBG_STAT    = $00DEF1
t0      = $10
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
        ldx     #.loword(m1)
        jsr     puts
        jsr     idle
        ldx     #.loword(m2)
        jsr     puts
        jsr     traffic
        lda     #$04
        sta     f:SV_CTRL
        ldx     #.loword(m3)
        jsr     puts
        jsr     traffic
        ldx     #.loword(m4)
        jsr     puts
        jsr     idle
        lda     #$00
        sta     f:SV_CTRL
        ldx     #.loword(m5)
        jsr     puts
        stp

mark:   lda     f:UPTIME
        lda     f:UPTIME+2
        sta     t0
        rts
; carry set when 6 s (92 x 65.5 ms) have passed
timeup: lda     f:UPTIME
        lda     f:UPTIME+2
        sec
        sbc     t0
        cmp     #92
        rts

idle:   jsr     mark
:       jsr     timeup
        bcc     :-
        rts

; write 64 KB of bank $03 over and over (every write is an SDRAM write)
traffic:
        jsr     mark
tl:     ldx     #0
        lda     #$00
:       sta     f:$030000,x
        eor     #$FF
        inx
        bne     :-
        jsr     timeup
        bcc     tl
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
m1:     .byte "1 IDLE", 10, 0
m2:     .byte "2 TRAFFIC", 10, 0
m3:     .byte "3 TRAFFIC, CLASSIC FROZEN", 10, 0
m4:     .byte "4 IDLE, CLASSIC FROZEN", 10, 0
m5:     .byte "DONE", 10, 0
