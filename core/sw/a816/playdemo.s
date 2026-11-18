; SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
; Copyright (c) 2026 Carlos Bravo
; Atari816, Lau (the sample player): listening demo (REV $0A). About 17 seconds; each part is announced
; in the log before it plays. The classic machine is frozen meanwhile (its sound is silent).
;   1/5  chord C4 E4 G4 (3 voices, 8-bit looped sine), 3 s
;   2/5  pan sweep: A4 from left to right, 4 s (the CPU changes the two volumes every 15 ms)
;   3/5  looped note, 16-bit: a noise attack, then a looped sine period at A3, 3 s
;   4/5  noise burst, 8-bit, one shot (16384 samples, 341 ms); the end interrupt is timed
;   5/5  C major scale on all 8 voices, one more voice every 300 ms, then all held 1.5 s
; Then AU_LATE (must be 00) and DONE.
        .p816
        .smart  -

AU_KEYON    = $00DB20
AU_KEYOFF   = $00DB21
AU_END      = $00DB23
AU_IRQEN    = $00DB24
AU_MASTER   = $00DB25
AU_LATE     = $00DB26
AU_V        = $00DB80
SV_CTRL     = $00DC00
IRQ_STATUS  = $00DE08
IRQ_EN      = $00DE09
UPTIME      = $00DE18
DBG_OUT     = $00DEF0
DBG_STAT    = $00DEF1

SINE8       = $060000           ; 256 x 8-bit
SINE16      = $060100           ; 256 x 16-bit
NOTE16      = $060400           ; 16-bit: 4800 noise attack samples, then a sine period (256)
NOISE8      = $070000           ; 16384 x 8-bit noise

p0          = $20               ; 4
t0          = $24               ; 4
t1          = $28               ; 4
cnt         = $2C               ; 2
k           = $2E               ; 2
lfsr        = $30               ; 2
amp         = $32               ; 2
tmp         = $34               ; 2

.macro print msg
        ldx     #.loword(msg)
        jsr     puts
.endmacro
.macro VP start, len, loop, pitch, vl, vr, ctl
        .faraddr start
        .faraddr len
        .faraddr loop
        .word   pitch
        .byte   vl, vr, ctl
.endmacro
.macro SETV voice, blk
        ldx     #voice
        ldy     #.loword(blk)
        jsr     setv
.endmacro
.macro WAITMS ms
        rep     #$20
        .a16
        lda     #ms
        jsr     waitms
        sep     #$20
        .a8
.endmacro

        .segment "CODE"
        .a8
        .i16
start:  clc
        xce
        rep     #$10
        sep     #$20
        ldx     #$BFFF
        txs
        pea     $0000
        pld
        phk
        plb
        sei
        lda     #0
        sta     f:IRQ_EN
        lda     #$04
        sta     f:SV_CTRL
        lda     #$FF
        sta     f:AU_KEYOFF
        sta     f:AU_END
        sta     f:AU_MASTER
        sta     f:AU_LATE
        print   m_hello
        jsr     mksamples

        print   m_1
        SETV    0, v_c4
        SETV    1, v_e4
        SETV    2, v_g4
        lda     #$07
        sta     f:AU_KEYON
        WAITMS  3000
        lda     #$07
        sta     f:AU_KEYOFF
        WAITMS  500

        print   m_2
        SETV    0, v_a4
        lda     #$01
        sta     f:AU_KEYON
        stz     k
@pan:   lda     #255
        sec
        sbc     k
        sta     f:AU_V+11               ; VOL_L
        lda     k
        sta     f:AU_V+12               ; VOL_R
        WAITMS  15
        inc     k
        bne     @pan
        lda     #$01
        sta     f:AU_KEYOFF
        WAITMS  500

        print   m_3
        SETV    3, v_note
        lda     #$08
        sta     f:AU_KEYON
        WAITMS  3000
        lda     #$08
        sta     f:AU_KEYOFF
        WAITMS  500

        print   m_4
        SETV    4, v_noise
        lda     #$10
        sta     f:AU_END
        jsr     rdup
        rep     #$20
        .a16
        lda     t1
        sta     t0
        lda     t1+2
        sta     t0+2
        sep     #$20
        .a8
        lda     #$10
        sta     f:AU_KEYON
:       lda     f:AU_END                ; (the AUDIO interrupt line, polled: IRQ_STATUS bit 5)
        and     #$10
        beq     :-
        jsr     rdup
        print   m_endus
        rep     #$20
        .a16
        sec
        lda     t1
        sbc     t0
        sta     t1
        lda     t1+2
        sbc     t0+2
        sep     #$20
        .a8
        jsr     puthex
        lda     t1+1
        jsr     puthex
        lda     t1
        jsr     puthex
        jsr     nl
        WAITMS  500

        print   m_5
        ldx     #0
@sc:    phx
        ldy     #.loword(v_scale)
        jsr     setv                    ; (X = voice)
        lda     1,s                     ; voice
        asl
        tay
        asl
        asl
        asl
        tax
        rep     #$20
        .a16
        lda     scale,y
        sta     f:AU_V+9,x
        sep     #$20
        .a8
        plx
        lda     bits,x
        sta     f:AU_KEYON
        phx
        WAITMS  300
        plx
        inx
        cpx     #8
        bne     @sc
        WAITMS  1500
        lda     #$FF
        sta     f:AU_KEYOFF
        print   m_late
        lda     f:AU_LATE
        jsr     puthex
        jsr     nl
        lda     #$C0
        sta     f:AU_MASTER
        lda     #0
        sta     f:SV_CTRL
        print   m_done
        stp

bits:   .byte   $01, $02, $04, $08, $10, $20, $40, $80
scale:  .word   22862, 25660, 28804, 30516, 34253, 38448, 43156, 45722

v_c4:   VP SINE8, 256, 0, 22862, 70, 70, 1
v_e4:   VP SINE8, 256, 0, 28804, 70, 70, 1
v_g4:   VP SINE8, 256, 0, 34253, 70, 70, 1
v_a4:   VP SINE8, 256, 0, 38448, 255, 0, 1
v_note: VP NOTE16, 4800+256, 4800, 19224, 160, 160, 3
v_scale: VP SINE8, 256, 0, 0, 40, 40, 1
v_noise: VP NOISE8, 16384, 0, $4000, 120, 120, 0

; voice X <- 14-byte block at Y
setv:   rep     #$21
        .a16
        txa
        asl
        asl
        asl
        asl
        tax
        sep     #$20
        .a8
        lda     #14
        sta     cnt
:       lda     a:0,y
        sta     f:AU_V,x
        inx
        iny
        dec     cnt
        bne     :-
        rts

; the samples
mksamples:
        rep     #$20
        .a16
        lda     #.loword(SINE8)
        sta     p0
        sep     #$20
        .a8
        lda     #^SINE8
        sta     p0+2
        ldy     #0
:       tyx
        lda     sine256,x
        sta     [p0],y
        iny
        cpy     #256
        bne     :-
        jsr     mk16
        jsr     mknoise
        rts

; SINE16 and the loop part of NOTE16: sine256 << 8; the attack of NOTE16: decaying noise
mk16:   rep     #$20
        .a16
        lda     #.loword(SINE16)
        sta     p0
        sep     #$20
        .a8
        lda     #^SINE16
        sta     p0+2
        ldx     #0
        ldy     #0
:       lda     #0
        sta     [p0],y
        iny
        lda     sine256,x
        sta     [p0],y
        iny
        inx
        cpx     #256
        bne     :-
        ; NOTE16 attack: 4800 samples of noise, amplitude falling from 32767 to 0
        rep     #$20
        .a16
        lda     #.loword(NOTE16)
        sta     p0
        lda     #$ACE1
        sta     lfsr
        lda     #4800
        sta     cnt
        ldy     #0
@a:     lda     lfsr
        lsr
        bcc     :+
        eor     #$B400
:       sta     lfsr
        ; amplitude: noise >> (cnt' scale): keep it simple: (noise AND mask), mask shrinks with time
        lda     cnt
        cmp     #3600
        bcs     @m0
        cmp     #2400
        bcs     @m1
        cmp     #1200
        bcs     @m2
        lda     lfsr
        and     #$07FF
        sec
        sbc     #$0400
        bra     @st
@m2:    lda     lfsr
        and     #$1FFF
        sec
        sbc     #$1000
        bra     @st
@m1:    lda     lfsr
        and     #$3FFF
        sec
        sbc     #$2000
        bra     @st
@m0:    lda     lfsr
        and     #$7FFF
        sec
        sbc     #$4000
@st:    sta     [p0],y
        iny
        iny
        dec     cnt
        bne     @a
        sep     #$20
        .a8
        ldx     #0                      ; then the sine period
:       lda     #0
        sta     [p0],y
        iny
        lda     sine256,x
        sta     [p0],y
        iny
        inx
        cpx     #256
        bne     :-
        rts

mknoise:
        rep     #$20
        .a16
        lda     #.loword(NOISE8)
        sta     p0
        lda     #$1D2B
        sta     lfsr
        sep     #$20
        .a8
        lda     #^NOISE8
        sta     p0+2
        ldy     #0
:       rep     #$20
        .a16
        lda     lfsr
        lsr
        bcc     :+
        eor     #$B400
:       sta     lfsr
        sep     #$20
        .a8
        sta     [p0],y
        iny
        cpy     #16384
        bne     :--
        rts

; wait A (16-bit) milliseconds
waitms: .a16
        sta     tmp
@ms:    sep     #$20
        .a8
        jsr     rdup
        rep     #$21
        .a16
        lda     t1
        adc     #1000
        sta     t0
@w:     sep     #$20
        .a8
        jsr     rdup
        rep     #$20
        .a16
        lda     t1
        cmp     t0
        bmi     @w
        dec     tmp
        bne     @ms
        rts
        .a8

rdup:   lda     f:UPTIME
        sta     t1
        lda     f:UPTIME+1
        sta     t1+1
        lda     f:UPTIME+2
        sta     t1+2
        lda     f:UPTIME+3
        sta     t1+3
        rts

nl:     lda     #10
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
puthex: pha
        lsr
        lsr
        lsr
        lsr
        jsr     nib
        pla
        and     #$0F
nib:    cmp     #10
        bcc     :+
        adc     #6
:       adc     #$30
        bra     putc

        .include "sine256.inc"

m_hello: .byte  "SAMPLE PLAYER DEMO: LISTEN", 10, 0
m_1:     .byte  "1/5 CHORD C4 E4 G4, 3 VOICES, 8-BIT LOOPED SINE, 3 S", 10, 0
m_2:     .byte  "2/5 PAN SWEEP: A4 FROM LEFT TO RIGHT, 4 S", 10, 0
m_3:     .byte  "3/5 LOOPED NOTE, 16-BIT: NOISE ATTACK THEN A LOOPED SINE AT A3, 3 S", 10, 0
m_4:     .byte  "4/5 NOISE BURST, 8-BIT, ONE SHOT, 341 MS", 10, 0
m_endus: .byte  "    END AFTER US ", 0
m_5:     .byte  "5/5 C MAJOR SCALE ON ALL 8 VOICES, ONE MORE EVERY 300 MS, HELD 1.5 S", 10, 0
m_late:  .byte  "AU_LATE ", 0
m_done:  .byte  "DONE", 10, 0
