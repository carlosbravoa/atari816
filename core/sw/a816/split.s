; SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
; Copyright (c) 2026 Carlos Bravo
; Atari816: palette split at raster lines (REV $09), for the eye and the log.
;
; 640x360x8 desktop (classic machine frozen) of vertical stripes in colours 1 and 2. Colour 1
; is set by interrupts: blue from VBLANK, red from the LINE interrupt at line 120, green from
; the LINE interrupt at line 240. The handler writes the palette first (within the 4 us
; horizontal blank), then reads NV_LINE and sets the next NV_LINE_CMP. A stable picture
; shows three bands, blue / red / green, with straight edges at 1/3 and 2/3 of the height.
; Log, once a second: VBL and LINE interrupts in that second, lines read in the handler that
; were not the compare value. At the end (SECS seconds): totals and the microseconds they
; took, then DONE. Marga is switched off and the classic machine resumed at the end.
        .p816
        .smart  -

NV_CTRL     = $D900
NV_BASE     = $D901
NV_STRIDE   = $D904
NV_LINE     = $D906
NV_CMP      = $D908
PAL_IDX     = $D910
PAL_R       = $D911
PAL_G       = $D912
PAL_B       = $D913
BL_SRC      = $DA00
BL_DST      = $DA05
BL_DSTR     = $DA08
BL_W        = $DA0A
BL_H        = $DA0C
BL_FG       = $DA0E
BL_OP       = $DA11
BL_FLAGS    = $DA12
BL_CTRL     = $DA13
SV_CTRL     = $DC00
IRQ_STATUS  = $DE08
IRQ_EN      = $DE09
UPTIME      = $DE18
DBG_OUT     = $DEF0
DBG_STAT    = $DEF1

FB          = $050000
SECS        = 20
L1          = 120
L2          = 240

; direct page (the data bank is $00 throughout)
nr          = $20               ; next colour for entry 1: r, g, b
ng          = $21
nb          = $22
state       = $23               ; 0: next LINE at L1, 1: next LINE at L2, 2: next is VBLANK
n_vbl       = $24               ; 2: this second
n_line      = $26               ; 2
n_bad       = $28               ; 2
t_vbl       = $2A               ; 2: totals
t_line      = $2C               ; 2
t_bad       = $2E               ; 2
t0          = $30               ; 4: UPTIME at the start
t1          = $34               ; 4
tsec        = $38               ; 4: UPTIME of the next report
secs        = $3C               ; 1
lv          = $3E               ; 2: NV_LINE read in the handler

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
        pea     $0000
        plb
        plb
        ldx     #.loword(m_hello)
        jsr     puts
        lda     #$04                    ; classic machine frozen: 640x360x8 is fetched in time
        sta     SV_CTRL
        ; picture: stripes 40 pixels wide, colours 1 and 2
        lda     #0
        sta     BL_FLAGS
        sta     BL_OP                   ; FILL
        rep     #$20
        .a16
        lda     #640
        sta     BL_DSTR
        lda     #40
        sta     BL_W
        lda     #360
        sta     BL_H
        sep     #$20
        .a8
        ldx     #0
@st:    rep     #$21
        .a16
        txa
        adc     #.loword(FB)
        sta     BL_DST
        sep     #$20
        .a8
        lda     #^FB
        adc     #0
        sta     BL_DST+2
        rep     #$20
        .a16
        txa
        sep     #$20
        .a8
        jsr     stripe_col
        sta     BL_FG
        lda     #$01
        sta     BL_CTRL
:       lda     BL_CTRL
        lsr
        bcs     :-
        rep     #$21
        .a16
        txa
        adc     #40
        tax
        sep     #$20
        .a8
        cpx     #640
        bne     @st
        lda     #2                      ; colour 2: grey
        sta     PAL_IDX
        lda     #$60
        sta     PAL_R
        sta     PAL_G
        sta     PAL_B
        lda     #<(FB >> 8)
        sta     NV_BASE+1
        lda     #^FB
        sta     NV_BASE+2
        rep     #$20
        .a16
        lda     #640
        sta     NV_STRIDE
        sep     #$20
        .a8
        lda     #$01                    ; 640x360x8, no pointer
        sta     NV_CTRL
        ; interrupts
        sei
        lda     #$5C                    ; trampoline at $00:E008: JML irq_h
        sta     $E008
        rep     #$20
        .a16
        lda     #.loword(irq_h)
        sta     $E009
        lda     #$E008
        sta     $FFEE
        stz     n_vbl
        stz     n_line
        stz     n_bad
        stz     t_vbl
        stz     t_line
        stz     t_bad
        sep     #$20
        .a8
        lda     #^irq_h
        sta     $E00B
        lda     #2                      ; the first VBLANK sets blue and arms L1
        sta     state
        lda     #0
        sta     nr
        sta     ng
        lda     #$FF
        sta     nb
        lda     #<511
        sta     NV_CMP
        lda     #>511
        sta     NV_CMP+1
        lda     #$FF
        sta     IRQ_STATUS
        lda     #$03                    ; VBLANK, LINE
        sta     IRQ_EN
        stz     secs
        jsr     rdup
        rep     #$21
        .a16
        lda     t1
        sta     t0
        adc     #.loword(1000000)
        sta     tsec
        lda     t1+2
        sta     t0+2
        adc     #.hiword(1000000)
        sta     tsec+2
        sep     #$20
        .a8
        cli
@main:  wai
        jsr     rdup
        rep     #$20
        .a16
        sec
        lda     t1
        sbc     tsec
        lda     t1+2
        sbc     tsec+2
        sep     #$20
        .a8
        bmi     @main
        ; a second is over: report and restart the counters
        sei
        rep     #$21
        .a16
        lda     tsec
        adc     #.loword(1000000)
        sta     tsec
        lda     tsec+2
        adc     #.hiword(1000000)
        sta     tsec+2
        lda     n_vbl
        pha
        lda     n_line
        pha
        lda     n_bad
        pha
        stz     n_vbl
        stz     n_line
        stz     n_bad
        sep     #$20
        .a8
        cli
        inc     secs
        ldx     #.loword(m_sec)
        jsr     puts
        lda     secs
        jsr     puthex
        ldx     #.loword(m_vbl)
        jsr     puts
        rep     #$20
        .a16
        lda     5,s
        sep     #$20
        .a8
        jsr     put16
        ldx     #.loword(m_line)
        jsr     puts
        rep     #$20
        .a16
        lda     3,s
        sep     #$20
        .a8
        jsr     put16
        ldx     #.loword(m_bad)
        jsr     puts
        rep     #$20
        .a16
        lda     1,s
        sep     #$20
        .a8
        jsr     put16
        ldx     #.loword(m_last)
        jsr     puts
        rep     #$20
        .a16
        lda     lv
        sep     #$20
        .a8
        jsr     put16
        jsr     nl
        rep     #$20
        .a16
        pla
        pla
        pla
        sep     #$20
        .a8
        lda     secs
        cmp     #SECS
        beq     @end
        jmp     @main
@end:   sei
        lda     #0
        sta     IRQ_EN
        jsr     rdup
        ldx     #.loword(m_tot)
        jsr     puts
        rep     #$20
        .a16
        lda     t_vbl
        sep     #$20
        .a8
        jsr     put16
        ldx     #.loword(m_line)
        jsr     puts
        rep     #$20
        .a16
        lda     t_line
        sep     #$20
        .a8
        jsr     put16
        ldx     #.loword(m_bad)
        jsr     puts
        rep     #$20
        .a16
        lda     t_bad
        sep     #$20
        .a8
        jsr     put16
        ldx     #.loword(m_us)
        jsr     puts
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
        jsr     put16
        rep     #$20
        .a16
        lda     t1
        sep     #$20
        .a8
        jsr     put16
        jsr     nl
        lda     #0
        sta     NV_CTRL
        lda     #1                      ; colour 1 back to the reset palette's $01 (near black)
        sta     PAL_IDX
        lda     #$11
        sta     PAL_R
        sta     PAL_G
        sta     PAL_B
        lda     #0
        sta     SV_CTRL
        ldx     #.loword(m_done)
        jsr     puts
        stp

; A (16) = x -> colour 1 or 2 (alternating every 40 pixels)
stripe_col:
        rep     #$20
        .a16
        ldy     #0
:       cmp     #40
        bcc     :+
        sbc     #40
        iny
        bra     :-
:       tya
        sep     #$20
        .a8
        and     #1
        inc
        rts

; ── the handler: palette first ───────────────────────────────────────────────
; (the interrupt may come in 8- or 16-bit mode; RTI restores it; X and Y are not touched)
irq_h:  rep     #$20
        .a16
        pha
        sep     #$20
        .a8
        lda     #1
        sta     PAL_IDX
        lda     nr
        sta     PAL_R
        lda     ng
        sta     PAL_G
        lda     nb
        sta     PAL_B
        lda     IRQ_STATUS
        sta     IRQ_STATUS
        and     #$03
        cmp     #$02
        beq     @line
        cmp     #$01
        beq     @vbl
        bra     @bd                     ; both or none: counted as bad
@vbl:   rep     #$20
        .a16
        inc     n_vbl
        inc     t_vbl
        sep     #$20
        .a8
        lda     state
        cmp     #2
        beq     @arm
        bra     @bd                     ; a LINE was missed
@line:  lda     NV_LINE
        sta     lv
        lda     NV_LINE+1
        sta     lv+1
        rep     #$20
        .a16
        inc     n_line
        inc     t_line
        sep     #$20
        .a8
        lda     state
        beq     @l1
        cmp     #1
        bne     @bd
        rep     #$20
        .a16
        lda     lv
        cmp     #L2
        sep     #$20
        .a8
        beq     @arm
        bra     @bd
@l1:    rep     #$20
        .a16
        lda     lv
        cmp     #L1
        sep     #$20
        .a8
        beq     @arm
@bd:    rep     #$20
        .a16
        inc     n_bad
        inc     t_bad
        sep     #$20
        .a8
@arm:   lda     state                   ; the next event and its colour
        inc
        cmp     #3
        bcc     :+
        lda     #0
:       sta     state
        beq     @s0
        cmp     #1
        beq     @s1
        lda     #0                      ; state 2: VBLANK next, blue
        sta     nr
        sta     ng
        lda     #$FF
        sta     nb
        lda     #<511
        sta     NV_CMP
        lda     #>511
        sta     NV_CMP+1
        bra     @x
@s0:    lda     #$FF                    ; LINE at L1 next, red
        sta     nr
        lda     #0
        sta     ng
        sta     nb
        lda     #<L1
        sta     NV_CMP
        lda     #>L1
        sta     NV_CMP+1
        bra     @x
@s1:    lda     #0                      ; LINE at L2 next, green
        sta     nr
        sta     nb
        lda     #$FF
        sta     ng
        lda     #<L2
        sta     NV_CMP
        lda     #>L2
        sta     NV_CMP+1
@x:     rep     #$20
        .a16
        pla
        rti
        .a8

rdup:   lda     UPTIME
        sta     t1
        lda     UPTIME+1
        sta     t1+1
        lda     UPTIME+2
        sta     t1+2
        lda     UPTIME+3
        sta     t1+3
        rts

; ── output (A 16-bit value in A/B: high byte in B) ───────────────────────────
put16:  xba
        jsr     puthex
        xba
        jmp     puthex
nl:     lda     #10
putc:   pha
:       lda     DBG_STAT
        bmi     :-
        pla
        sta     DBG_OUT
        rts
puts:   lda     f:$010000,x             ; (strings are in bank 1, the data bank is 0)
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

m_hello: .byte  "PALETTE SPLIT: BLUE / RED AT LINE 120 / GREEN AT LINE 240", 10, 0
m_sec:   .byte  "SEC ", 0
m_vbl:   .byte  " VBL ", 0
m_line:  .byte  " LINE ", 0
m_bad:   .byte  " BAD ", 0
m_last:  .byte  " LAST LINE ", 0
m_tot:   .byte  "TOTAL VBL ", 0
m_us:    .byte  " US ", 0
m_done:  .byte  "DONE", 10, 0
