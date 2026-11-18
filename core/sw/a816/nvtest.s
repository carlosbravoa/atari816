; SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
; Copyright (c) 2026 Carlos Bravo
; Atari816 test of Marga, the video chip: shows a test picture on the desktop (640x360x8 at $02:0000), then the
; pointer, then the 4 bpp and 320x180 modes, and reports lines that were fetched too late.
; Picture: white 1-pixel frame at the very edge, hue bars 32 pixels wide, brightness steps
; every 8 lines. With -D SIM the picture is not drawn (the testbench checks memory junk).
        .p816
        .smart  -
NV_CTRL     = $00D900
NV_BASE     = $00D901
NV_LATE     = $00D90B
SV_CTRL     = $00DC00
PTR_X       = $00D920
PTR_Y       = $00D922
PTR_HOT     = $00D924
PTR_IMG     = $00D925
PTR_C1      = $00D928
IRQ_STATUS  = $00DE08
DBG_OUT     = $00DEF0
DBG_STAT    = $00DEF1
FB          = $020000
PIMG        = $060000

p       = $10           ; 24-bit pointer
ly      = $14
tmp     = $16
px      = $18
cnt     = $1A

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
        ldx     #.loword(m_hello)
        jsr     puts

.ifndef SIM
        ; ── picture ──
        stz     p
        stz     p+1
        lda     #^FB
        sta     p+2
        rep     #$20
        .a16
        stz     ly
line:   ldx     #0
pix:    lda     ly
        beq     white
        cmp     #359
        beq     white
        cpx     #0
        beq     white
        cpx     #639
        beq     white
        lsr
        lsr
        lsr
        and     #$000F
        sta     tmp
        txa
        lsr
        and     #$00F0
        ora     tmp
        bra     put
white:  lda     #$000F
put:    sep     #$20
        .a8
        sta     [p]
        rep     #$20
        .a16
        inc     p
        bne     :+
        inc     p+2             ; (high byte of p+2 is scratch)
:       inx
        cpx     #640
        bne     pix
        inc     ly
        lda     ly
        cmp     #360
        bne     line
        sep     #$20
        .a8
.endif

        ; ── pointer image: a small staircase triangle ──
        ldx     #0
pimg:   txa
        lsr
        lsr
        lsr
        sta     tmp             ; row
        cmp     #16
        bcs     pz
        txa
        and     #$07
        asl
        asl
        cmp     tmp
        bcc     pfull
        sec
        sbc     #4
        bcc     pedge
        cmp     tmp
        bcc     pedge
pz:     lda     #$00
        bra     pput
pfull:  lda     #$AA
        bra     pput
pedge:  lda     #$70
pput:   sta     f:PIMG,x
        inx
        cpx     #256
        bne     pimg

        lda     #$00
        sta     f:NV_BASE
        sta     f:NV_BASE+1
        lda     #^FB
        sta     f:NV_BASE+2
        lda     #$01
        sta     f:NV_CTRL
        sta     f:NV_LATE
        jsr     wait3
        jsr     late                    ; 8 bpp with the classic machine running: late
        lda     #$04
        sta     f:SV_CTRL               ; freeze the classic machine: 16-byte bursts
        jsr     wait3
        sta     f:NV_LATE
        jsr     wait3
        jsr     late                    ; must be 00

        rep     #$20
        .a16
        lda     #100
        sta     f:PTR_X
        sta     px
        lda     #50
        sta     f:PTR_Y
        lda     #.loword(PIMG)
        sta     f:PTR_IMG
        sep     #$20
        .a8
        lda     #^PIMG
        sta     f:PTR_IMG+2
        lda     #$00
        sta     f:PTR_HOT
        sta     f:PTR_C1
        lda     #$0F
        sta     f:PTR_C1+1
        lda     #$46
        sta     f:PTR_C1+2
        lda     #$09
        sta     f:NV_CTRL
        jsr     wait3
        jsr     late

.ifndef SIM
        ; pointer walks right for about 20 s
        rep     #$20
        .a16
        lda     #1200
        sta     cnt
walk:   sep     #$20
        .a8
        jsr     vbl
        rep     #$20
        .a16
        lda     px
        inc
        cmp     #650
        bcc     :+
        lda     #0
:       sta     px
        sta     f:PTR_X
        dec     cnt
        bne     walk
        sep     #$20
        .a8
        jsr     late
.ifndef SIM                             ; the simulation checks these modes with 16-byte bursts
        lda     #$00
        sta     f:SV_CTRL               ; classic machine running again for the lighter modes
.endif
        lda     #$0B            ; 4 bpp
        sta     f:NV_CTRL
        ldx     #300
:       jsr     vbl
        dex
        bne     :-
        jsr     late
        lda     #$0D            ; 320x180
        sta     f:NV_CTRL
        ldx     #300
:       jsr     vbl
        dex
        bne     :-
        jsr     late
        lda     #$00
        sta     f:NV_CTRL
.endif
        lda     #$00
        sta     f:SV_CTRL               ; classic machine runs again
        ldx     #.loword(m_done)
        jsr     puts
        stp

wait3:  jsr     vbl
        jsr     vbl
vbl:    lda     #$01
        sta     f:IRQ_STATUS
:       lda     f:IRQ_STATUS
        and     #$01
        beq     :-
        rts

late:   ldx     #.loword(m_late)
        jsr     puts
        lda     f:NV_LATE
        jsr     puthex
        lda     #10
        jsr     putc
        sta     f:NV_LATE
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

m_hello: .byte "NVC TEST", 10, 0
m_late:  .byte "LATE ", 0
m_done:  .byte "DONE", 10, 0
