; SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
; Copyright (c) 2026 Carlos Bravo
; Atari816, OPL2 (YM3812) listening demo (REV $0C). About 14 seconds; each part is announced
; in the log before it plays. The classic machine is frozen meanwhile.
;   1/4  FM electric piano chord progression: C -> Am -> F -> G (4-voice arpeggiated chords)
;   2/4  AdLib FM synth bass + brass lead melody (2 channels)
;   3/4  OPL2 waveform showcase: WS 0 (sine), 1 (half-sine), 2 (abs-sine), 3 (quarter-sine)
;   4/4  OPL2 FM chord + Lau PCM sine playing together (stereo pan on Lau)
; Run on the board: python3 tools/atari.py run816 sw/a816/OPLDEMO.BIN
        .p816
        .smart  -

OPL_ADDR    = $00DB30
OPL_STAT    = $00DB30
OPL_DATA    = $00DB31
AU_KEYON    = $00DB20
AU_KEYOFF   = $00DB21
AU_MASTER   = $00DB25
AU_LATE     = $00DB26
AU_V        = $00DB80
SV_CTRL     = $00DC00
SYS_REV     = $00DE01
UPTIME      = $00DE18
DBG_OUT     = $00DEF0
DBG_STAT    = $00DEF1

SINE8       = $060000

t0          = $20               ; 4 bytes
t1          = $24               ; 4 bytes
tmp         = $28               ; 2 bytes
ch          = $2A               ; 1 byte
mod_off     = $2B               ; 1 byte
car_off     = $2C               ; 1 byte
idx         = $2E               ; 2 bytes
cnt         = $30               ; 2 bytes

; Note F-numbers (10-bit) for standard OPL2 49.7 kHz sample rate:
FN_C = $159
FN_D = $183
FN_E = $1B2
FN_F = $1CC
FN_G = $205
FN_A = $244
FN_B = $28B

.macro print msg
        ldx     #.loword(msg)
        jsr     puts
.endmacro

.macro OPL reg, val
        lda     #reg
        ldy     #val
        jsr     opl_wr
.endmacro

.macro WAITMS ms
        ldx     #ms
        jsr     wait_ms
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
        phk
        plb

        ; Freeze classic Atari so only OPL2 / Lau play
        lda     #$04
        sta     f:SV_CTRL

        print   m_hdr
        lda     f:SYS_REV
        jsr     puthex
        print   m_stat
        lda     f:OPL_STAT
        jsr     puthex
        lda     #10
        jsr     putc

        jsr     opl_reset
        OPL     $01, $20                ; enable OPL2 waveform select

        ; ── 1/4: FM Electric Piano chord progression (C -> Am -> F -> G) ──
        print   m_p1
        ldx     #0
@ep_i:  phx
        txa
        jsr     patch_epiano
        plx
        inx
        cpx     #4
        bne     @ep_i

        ldx     #0
@ch_lp: stx     idx
        ; Arpeggiate 4 notes of chord (ch 0..3)
        lda     #0
        sta     ch
@n_lp:  ldx     idx
        lda     f:chords_lo,x
        sta     tmp
        lda     f:chords_hi,x
        sta     tmp+1
        inx
        stx     idx
        lda     ch
        jsr     note_on
        WAITMS  85
        inc     ch
        lda     ch
        cmp     #4
        bne     @n_lp
        WAITMS  660
        ; Key-off all 4 channels
        lda     #0
        jsr     note_off
        lda     #1
        jsr     note_off
        lda     #2
        jsr     note_off
        lda     #3
        jsr     note_off
        WAITMS  120
        ldx     idx
        cpx     #16
        bne     @ch_lp

        WAITMS  300

        ; ── 2/4: AdLib FM Synth Bass (ch 0) + Brass Lead (ch 1) ──
        print   m_p2
        jsr     patch_bass              ; ch 0
        jsr     patch_brass             ; ch 1

        ldx     #0
@m_lp:  stx     idx
        ; Bass note (ch 0)
        lda     f:bass_lo,x
        sta     tmp
        lda     f:bass_hi,x
        beq     @no_b
        sta     tmp+1
        lda     #0
        jsr     note_on
@no_b:  ; Lead note (ch 1)
        ldx     idx
        lda     f:lead_lo,x
        sta     tmp
        lda     f:lead_hi,x
        beq     @no_l
        sta     tmp+1
        lda     #1
        jsr     note_on
@no_l:  WAITMS  210
        lda     #0
        jsr     note_off
        lda     #1
        jsr     note_off
        WAITMS  60
        ldx     idx
        inx
        cpx     #16
        bne     @m_lp

        WAITMS  300

        ; ── 3/4: OPL2 Waveform Showcase (WS 0..3 on ch 0, A4 440 Hz) ──
        print   m_p3
        jsr     patch_pure              ; ch 0: modulator muted, pure carrier
        lda     #0
        sta     cnt
@ws_lp: print   m_ws
        lda     cnt
        clc
        adc     #'0'
        jsr     putc
        lda     #10
        jsr     putc
        lda     cnt
        tay
        lda     #$E3                    ; ch 0 carrier waveform select
        jsr     opl_wr
        lda     #.lobyte(FN_A)
        sta     tmp
        lda     #$30 | .hibyte(FN_A)    ; block 4 + key-on
        sta     tmp+1
        lda     #0
        jsr     note_on
        WAITMS  500
        lda     #0
        jsr     note_off
        WAITMS  150
        inc     cnt
        lda     cnt
        cmp     #4
        bne     @ws_lp

        WAITMS  250

        ; ── 4/4: OPL2 FM Chord + Lau PCM Sine Mixed Together ──
        print   m_p4
        ; Copy 256-byte sine table to SDRAM $06:0000 for Lau
        ldx     #0
@cp:    lda     f:sine256,x
        sta     f:SINE8,x
        inx
        cpx     #256
        bne     @cp

        ; Configure Lau voice 0: 256-sample looped 8-bit sine at ~523 Hz (pitch = 523*256/48000 * 16384 = $B2F6)
        lda     #$C0
        sta     f:AU_MASTER
        lda     #0
        sta     f:AU_LATE               ; clear AU_LATE
        ldx     #0
@sv:    lda     f:lau_v0,x
        sta     f:AU_V,x
        inx
        cpx     #14
        bne     @sv

        ; Set up OPL2 warm E-piano chord C4-E4-G4 on ch 0-2
        lda     #0
        jsr     patch_epiano
        lda     #1
        jsr     patch_epiano
        lda     #2
        jsr     patch_epiano
        lda     #.lobyte(FN_C)
        sta     tmp
        lda     #$30 | .hibyte(FN_C)
        sta     tmp+1
        lda     #0
        jsr     note_on
        lda     #.lobyte(FN_E)
        sta     tmp
        lda     #$30 | .hibyte(FN_E)
        sta     tmp+1
        lda     #1
        jsr     note_on
        lda     #.lobyte(FN_G)
        sta     tmp
        lda     #$30 | .hibyte(FN_G)
        sta     tmp+1
        lda     #2
        jsr     note_on

        ; Start Lau voice 0 and pan it smoothly left -> right over ~2.5 s
        lda     #$01
        sta     f:AU_KEYON
        ldx     #0
@pan:   txa
        sta     f:AU_V+$0C              ; VOL_R = 0..255
        eor     #$FF
        sta     f:AU_V+$0B              ; VOL_L = 255..0
        phx
        WAITMS  10
        plx
        inx
        cpx     #256
        bne     @pan

        ; Silence both Lau and OPL2
        lda     #$FF
        sta     f:AU_KEYOFF
        lda     #0
        jsr     note_off
        lda     #1
        jsr     note_off
        lda     #2
        jsr     note_off
        WAITMS  300

        print   m_late
        lda     f:AU_LATE
        jsr     puthex
        lda     #10
        jsr     putc
        print   m_done
        stp

; ── OPL2 helpers ──────────────────────────────────────────────────────────────
opl_reset:
        ; Zero registers $01..$F5
        ldx     #1
@rl:    txa
        ldy     #0
        jsr     opl_wr
        inx
        cpx     #$F6
        bne     @rl
        rts

; Set channel A (0..3) to warm FM Electric Piano
patch_epiano:
        jsr     ch_ops                  ; sets mod_off, car_off, ch
        ; Modulator: mult=14 (tine shimmer), TL=28, AR=15, DR=7, SL=5, RR=5, WS=0
        lda     #$20
        clc
        adc     mod_off
        ldy     #$0E
        jsr     opl_wr
        lda     #$40
        clc
        adc     mod_off
        ldy     #$5C                    ; KSL=1, TL=28
        jsr     opl_wr
        lda     #$60
        clc
        adc     mod_off
        ldy     #$F7
        jsr     opl_wr
        lda     #$80
        clc
        adc     mod_off
        ldy     #$55
        jsr     opl_wr
        lda     #$E0
        clc
        adc     mod_off
        ldy     #$00
        jsr     opl_wr
        ; Carrier: mult=1, TL=6, AR=15, DR=3, SL=4, RR=5, WS=0
        lda     #$20
        clc
        adc     car_off
        ldy     #$01
        jsr     opl_wr
        lda     #$40
        clc
        adc     car_off
        ldy     #$06
        jsr     opl_wr
        lda     #$60
        clc
        adc     car_off
        ldy     #$F3
        jsr     opl_wr
        lda     #$80
        clc
        adc     car_off
        ldy     #$45
        jsr     opl_wr
        lda     #$E0
        clc
        adc     car_off
        ldy     #$00
        jsr     opl_wr
        ; Feedback=3, FM mode (con=0)
        lda     #$C0
        clc
        adc     ch
        ldy     #$06
        jsr     opl_wr
        rts

; Channel 0: punchy FM Synth Bass (uses OPL2 half-sine on modulator)
patch_bass:
        OPL     $20, $01                ; mod: mult=1
        OPL     $40, $10                ; mod: bright FM index (TL=16)
        OPL     $60, $F8                ; mod: fast attack, snappy decay
        OPL     $80, $56                ; mod: SL=5, RR=6
        OPL     $E0, $01                ; mod: OPL2 half-sine
        OPL     $23, $01                ; car: mult=1
        OPL     $43, $04                ; car: loud (TL=4)
        OPL     $63, $F4                ; car: fast attack, medium decay
        OPL     $83, $37                ; car: SL=3, RR=7
        OPL     $E3, $00                ; car: sine
        OPL     $C0, $0A                ; feedback=5, FM
        rts

; Channel 1: classic AdLib FM Brass Lead (vibrato + modulator swell)
patch_brass:
        OPL     $21, $61                ; mod: VIB + EGT + mult=1
        OPL     $41, $14                ; mod: TL=20
        OPL     $61, $B4                ; mod: brass swell attack (AR=11, DR=4)
        OPL     $81, $26                ; mod: SL=2, RR=6
        OPL     $E1, $00                ; mod: sine
        OPL     $24, $61                ; car: VIB + EGT + mult=1
        OPL     $44, $06                ; car: TL=6
        OPL     $64, $D2                ; car: AR=13, DR=2
        OPL     $84, $16                ; car: SL=1, RR=6
        OPL     $E4, $01                ; car: OPL2 half-sine
        OPL     $C1, $08                ; feedback=4, FM
        rts

; Channel 0: pure carrier (modulator muted) for waveform comparison
patch_pure:
        OPL     $20, $01
        OPL     $40, $3F                ; mod muted
        OPL     $60, $F0
        OPL     $80, $0F
        OPL     $E0, $00
        OPL     $23, $21                ; car: sustain, mult=1
        OPL     $43, $08                ; car: TL=8
        OPL     $63, $F0
        OPL     $83, $07
        OPL     $C0, $00
        rts

; A = channel (0..3) -> stores ch, mod_off, car_off
ch_ops: sta     ch
        rep     #$20
        .a16
        and     #$00FF
        tax
        sep     #$20
        .a8
        lda     f:op_mod,x
        sta     mod_off
        lda     f:op_car,x
        sta     car_off
        rts

; Key-on channel A with F-num/block in tmp (lo), tmp+1 (hi with bit 5 = keyon)
note_on:
        sta     ch
        clc
        adc     #$A0
        ldy     #0
        pha
        lda     tmp
        tay
        pla
        jsr     opl_wr
        lda     ch
        clc
        adc     #$B0
        pha
        lda     tmp+1
        tay
        pla
        jsr     opl_wr
        rts

; Key-off channel A (clears key-on bit in $B0+ch)
note_off:
        clc
        adc     #$B0
        ldy     #$00
        jsr     opl_wr
        rts

; Write OPL2 reg A = low byte of Y with real YM3812 timing (4 us + 24 us)
opl_wr: sta     f:OPL_ADDR
        phy
        ldy     #5
        jsr     wait_us
        ply
        tya
        sta     f:OPL_DATA
        ldy     #26
        jsr     wait_us
        rts

; Wait X milliseconds (in -D SIM builds, 10 us per "ms" so full demo runs in ~150 ms)
wait_ms:
.ifdef SIM
@ml:    ldy     #10
.else
@ml:    ldy     #1000
.endif
        jsr     wait_us
        dex
        bne     @ml
        rts

; Wait Y microseconds (UPTIME low 16 bits)
wait_us:
        lda     f:UPTIME
        sta     t0
        lda     f:UPTIME+1
        sta     t0+1
        rep     #$20
        .a16
        tya
        clc
        adc     t0
        sta     t0
        sep     #$20
        .a8
@wl:    lda     f:UPTIME
        sta     t0+2
        lda     f:UPTIME+1
        sta     t0+3
        rep     #$20
        .a16
        lda     t0+2
        sec
        sbc     t0
        sep     #$20
        .a8
        bmi     @wl
        rts

puts:   lda     f:$010000,x
        beq     @pd
        jsr     putc
        inx
        bra     puts
@pd:    rts

putc:   pha
@pw:    lda     f:DBG_STAT
        bmi     @pw
        pla
        sta     f:DBG_OUT
        rts

puthex: pha
        lsr
        lsr
        lsr
        lsr
        jsr     putnib
        pla
        and     #$0F
putnib: cmp     #10
        bcc     @pn1
        adc     #6
@pn1:   adc     #'0'
        jmp     putc

; ── Tables ────────────────────────────────────────────────────────────────────
op_mod: .byte $00, $01, $02, $08
op_car: .byte $03, $04, $05, $0B

; 4 chords x 4 notes: C (C4 E4 G4 C5), Am (A3 E4 A4 C5), F (F3 C4 F4 A4), G (G3 D4 G4 B4)
chords_lo:
        .byte .lobyte(FN_C), .lobyte(FN_E), .lobyte(FN_G), .lobyte(FN_C)
        .byte .lobyte(FN_A), .lobyte(FN_E), .lobyte(FN_A), .lobyte(FN_C)
        .byte .lobyte(FN_F), .lobyte(FN_C), .lobyte(FN_F), .lobyte(FN_A)
        .byte .lobyte(FN_G), .lobyte(FN_D), .lobyte(FN_G), .lobyte(FN_B)
chords_hi:
        .byte $30|.hibyte(FN_C), $30|.hibyte(FN_E), $30|.hibyte(FN_G), $34|.hibyte(FN_C)
        .byte $2C|.hibyte(FN_A), $30|.hibyte(FN_E), $30|.hibyte(FN_A), $34|.hibyte(FN_C)
        .byte $2C|.hibyte(FN_F), $30|.hibyte(FN_C), $30|.hibyte(FN_F), $30|.hibyte(FN_A)
        .byte $2C|.hibyte(FN_G), $30|.hibyte(FN_D), $30|.hibyte(FN_G), $30|.hibyte(FN_B)

; 16-step synth bass (block 2 = $28) + brass lead (block 4/5 = $30/$34)
bass_lo:
        .byte .lobyte(FN_C), .lobyte(FN_C), .lobyte(FN_G), .lobyte(FN_C)
        .byte .lobyte(FN_A), .lobyte(FN_A), .lobyte(FN_E), .lobyte(FN_A)
        .byte .lobyte(FN_F), .lobyte(FN_F), .lobyte(FN_C), .lobyte(FN_F)
        .byte .lobyte(FN_G), .lobyte(FN_G), .lobyte(FN_D), .lobyte(FN_G)
bass_hi:
        .byte $28|.hibyte(FN_C), $28|.hibyte(FN_C), $28|.hibyte(FN_G), $28|.hibyte(FN_C)
        .byte $28|.hibyte(FN_A), $28|.hibyte(FN_A), $28|.hibyte(FN_E), $28|.hibyte(FN_A)
        .byte $28|.hibyte(FN_F), $28|.hibyte(FN_F), $28|.hibyte(FN_C), $28|.hibyte(FN_F)
        .byte $28|.hibyte(FN_G), $28|.hibyte(FN_G), $28|.hibyte(FN_D), $28|.hibyte(FN_G)

lead_lo:
        .byte .lobyte(FN_C), .lobyte(FN_E), .lobyte(FN_G), .lobyte(FN_C)
        .byte .lobyte(FN_A), .lobyte(FN_G), .lobyte(FN_E), .lobyte(FN_C)
        .byte .lobyte(FN_F), .lobyte(FN_A), .lobyte(FN_C), .lobyte(FN_A)
        .byte .lobyte(FN_G), .lobyte(FN_B), .lobyte(FN_D), .lobyte(FN_C)
lead_hi:
        .byte $30|.hibyte(FN_C), $30|.hibyte(FN_E), $30|.hibyte(FN_G), $34|.hibyte(FN_C)
        .byte $30|.hibyte(FN_A), $30|.hibyte(FN_G), $30|.hibyte(FN_E), $30|.hibyte(FN_C)
        .byte $30|.hibyte(FN_F), $30|.hibyte(FN_A), $34|.hibyte(FN_C), $30|.hibyte(FN_A)
        .byte $30|.hibyte(FN_G), $30|.hibyte(FN_B), $34|.hibyte(FN_D), $34|.hibyte(FN_C)

; Lau voice 0 block: START=$060000, LEN=256, LOOP=0, PITCH=$B2F6 (~523 Hz), VOL_L=$FF, VOL_R=0, CTRL=1 (LOOP, 8-bit)
lau_v0: .faraddr SINE8
        .faraddr 256
        .faraddr 0
        .word   $B2F6
        .byte   $FF, $00, $01

        .include "sine256.inc"

m_hdr:  .byte "OPL2 DEMO REV ", 0
m_stat: .byte " STAT ", 0
m_p1:   .byte "1/4 FM electric piano chords (C Am F G)", 10, 0
m_p2:   .byte "2/4 AdLib synth bass + brass lead", 10, 0
m_p3:   .byte "3/4 OPL2 waveforms (0..3)", 10, 0
m_ws:   .byte "  WS ", 0
m_p4:   .byte "4/4 OPL2 FM chord + Lau PCM pan", 10, 0
m_late: .byte "AU_LATE ", 0
m_done: .byte "DONE", 10, 0
