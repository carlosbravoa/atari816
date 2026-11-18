; SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
; Copyright (c) 2026 Carlos Bravo
; Atari816 input test: takes the keyboard for 20 seconds and prints every KEY event,
; system key (F12) NMIs and the joystick ports, then gives the keyboard back.
        .p816
        .smart  -
MB_REQ_BASE = $00DD00
MB_RSP_BASE = $00DD05
MB_RSP_HEAD = $00DD08
MB_RSP_TAIL = $00DD09
MB_STATUS   = $00DD0A
NMI_STATUS  = $00DE0A
UPTIME      = $00DE18
KB_ROUTE    = $00DE20
JOY_PORT    = $00DE21
JOY_TRIG    = $00DE22
DBG_OUT     = $00DEF0
DBG_STAT    = $00DEF1
RSP_RING    = $0E1000

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
        lda     #$5C                    ; NMI -> nmi_h
        sta     f:$00E00C
        lda     #$01
        sta     f:$00E00F
        rep     #$20
        .a16
        lda     #.loword(nmi_h)
        sta     f:$00E00D
        lda     #$E00C
        sta     f:$00FFEA
        sep     #$20
        .a8
        lda     #$00
        sta     f:MB_REQ_BASE
        sta     f:MB_RSP_BASE
        sta     f:MB_REQ_BASE+1
        lda     #$10
        sta     f:MB_RSP_BASE+1
        lda     #$0E
        sta     f:MB_REQ_BASE+2
        sta     f:MB_RSP_BASE+2
        lda     #$00
        sta     f:KB_ROUTE              ; keys to us
        ldx     #.loword(m_hello)
        jsr     puts
        lda     f:JOY_PORT
        jsr     puthex
        lda     f:JOY_TRIG
        jsr     puthex
        jsr     crlf
        lda     f:UPTIME
        lda     f:UPTIME+2
        sta     t0

loop:   lda     nmist
        beq     :+
        stz     nmist
        ldx     #.loword(m_sys)
        jsr     puts
:       lda     f:MB_RSP_HEAD
        cmp     f:MB_RSP_TAIL
        bne     :+
        jmp     idle
:
        rep     #$20
        .a16
        lda     f:MB_RSP_TAIL
        and     #$00FF
        asl
        asl
        asl
        asl
        tax
        sep     #$20
        .a8
        lda     f:RSP_RING,x
        cmp     #$E0
        beq     :+
        pha                             ; not a key event: show what it is
        lda     #'?'
        jsr     putc
        pla
        jsr     puthex
        jsr     crlf
        bra     next
:
        phx
        ldx     #.loword(m_key)
        jsr     puts
        plx
        lda     f:RSP_RING+8,x          ; usage
        jsr     puthex
        lda     #' '
        jsr     putc
        lda     f:RSP_RING+12,x         ; modifiers
        jsr     puthex
        lda     #' '
        jsr     putc
        lda     f:RSP_RING+13,x         ; 1 = down
        jsr     puthex
        jsr     crlf
next:   lda     f:MB_RSP_TAIL
        inc
        sta     f:MB_RSP_TAIL
idle:   lda     f:UPTIME
        lda     f:UPTIME+2              ; 65 ms units
        sec
        sbc     t0
        cmp     #230                    ; about 15 s
        bcs     :+
        jmp     loop
:
        lda     #$01
        sta     f:KB_ROUTE
        ldx     #.loword(m_done)
        jsr     puts
        stp

nmi_h:  sep     #$20
        pha
        lda     f:NMI_STATUS
        sta     f:nmist
        sta     f:NMI_STATUS
        pla
        rti

crlf:   lda     #10
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
:       adc     #'0'
        bra     putc

m_hello: .byte "INPUT TEST 15 S, JOY ", 0
m_key:   .byte "KEY ", 0
m_sys:   .byte "SYSTEM KEY", 10, 0
m_done:  .byte "DONE", 10, 0
nmist:   .byte 0
t0:      .byte 0
