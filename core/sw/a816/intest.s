; SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
; Copyright (c) 2026 Carlos Bravo
;
; Atari816: do key and mouse events keep coming while the I/O processor serves long requests?
; Run it with core/tools/intest.py (it injects keys and mouse moves and starts a developer
; upload during phase 4), or alone: python3 tools/atari.py run816 sw/a816/INTEST.BIN.
; The keyboard is routed to the 65C816 (KB_ROUTE = 0); every KEY ($E0) and MOUSE ($E1) event
; that arrives in the response ring is counted, also while a request is in progress.
;   P0  idle 8 s
;   P1  1.5 MB written to /INTEST.TMP on the card (48 WRITE requests of CHUNK bytes)
;   P2  /INTEST.TMP copied to /PC:/INTEST.TMP (READ from the card, WRITE to the PC)
;   P3  /PC:/INTEST.TMP copied to /INTEST2.TMP (READ from the PC, WRITE to the card)
;   P4  idle 40 s (intest.py sends a 500 KB file with the developer channel meanwhile)
; Each phase prints "Pn START", then "Pn US t KD d KU u M m DX x G g" (hex): its time in us,
; key downs, key ups, mouse events, the sum of their dx, and the longest time in us between
; two mouse events (0 with fewer than two). Without a PC link P2 and P3 print "Pn SKIP".
; The files are deleted at the end; then "INTEST DONE".
        .p816
        .smart  -

DBG_OUT     = $00DEF0
DBG_STAT    = $00DEF1
UPTIME      = $00DE18
KB_ROUTE    = $00DE20
MB_REQ_BASE = $00DD00
MB_REQ_HEAD = $00DD03
MB_RSP_BASE = $00DD05
MB_RSP_HEAD = $00DD08
MB_RSP_TAIL = $00DD09
MB_STATUS   = $00DD0A
REQ_RING    = $0E0000
RSP_RING    = $0E1000
BUF         = $0C0000               ; CHUNK bytes
.ifndef CHUNK
CHUNK       = $8000
.endif
NCHUNK      = 1536 * 1024 / CHUNK

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

        lda     #$00
        sta     f:MB_REQ_BASE
        sta     f:MB_RSP_BASE
        lda     #>.loword(REQ_RING)
        sta     f:MB_REQ_BASE+1
        lda     #>.loword(RSP_RING)
        sta     f:MB_RSP_BASE+1
        lda     #^REQ_RING
        sta     f:MB_REQ_BASE+2
        sta     f:MB_RSP_BASE+2
        jsr     mark
:       lda     f:MB_STATUS             ; wait for IOP_READY
        and     #$01
        bne     :+
        jsr     late
        bcc     :-
        lda     #0
        jmp     bad
:       lda     #0
        sta     f:KB_ROUTE              ; the keyboard and the mouse to us
        ldx     #0                      ; the data pattern
:       txa
        eor     #$5A
        sta     f:BUF,x
        inx
        cpx     #CHUNK
        bne     :-

; P0: idle
        lda     #'0'
        jsr     pstart
        lda     #122                    ; 122 x 65.5 ms = 8 s
        jsr     idle
        jsr     pend

; P1: the card file
        lda     #'1'
        jsr     pstart
        ldx     #.loword(p_card)
        lda     #2
        jsr     open
        sta     h1
        lda     #NCHUNK
        sta     cnt
:       lda     h1
        ldx     #.loword(t_write)
        jsr     rw
        dec     cnt
        bne     :-
        lda     h1
        jsr     close
        jsr     pend

; P2: card -> PC
        lda     #'2'
        jsr     pstart
        ldx     #.loword(p_card)
        lda     #0
        jsr     open
        sta     h1
        ldx     #.loword(p_pc)
        lda     #2
        jsr     open0                   ; (no PC link: skip P2 and P3)
        beq     :+
        lda     h1
        jsr     close
        ldx     #.loword(m_skip2)
        jsr     puts
        bra     p4
:       lda     rsp+12
        sta     h2
        jsr     copy
        jsr     pend

; P3: PC -> card
        lda     #'3'
        jsr     pstart
        ldx     #.loword(p_pc)
        lda     #0
        jsr     open
        sta     h1
        ldx     #.loword(p_card2)
        lda     #2
        jsr     open
        sta     h2
        jsr     copy
        jsr     pend

; P4: idle while the PC uploads
p4:     lda     #'4'
        jsr     pstart
        lda     #200                    ; 200 + 200 + 210 = 610 x 65.5 ms = 40 s
        jsr     idle
        lda     #200
        jsr     idle
        lda     #210
        jsr     idle
        jsr     pend

        ldx     #.loword(p_card)        ; clean up (errors ignored)
        jsr     del
        ldx     #.loword(p_card2)
        jsr     del
        ldx     #.loword(p_pc)
        jsr     del
        ldx     #.loword(m_done)
        jsr     puts
        stp

; ---- the copy of P2 / P3: NCHUNK x (READ h1, WRITE h2), then both closed
copy:   lda     #NCHUNK
        sta     cnt
:       lda     h1
        ldx     #.loword(t_read)
        jsr     rw
        lda     h2
        ldx     #.loword(t_write)
        jsr     rw
        dec     cnt
        bne     :-
        lda     h1
        jsr     close
        lda     h2
        jmp     close

; X = path, A = mode -> A = handle (stops on an error)
open:   jsr     open0
        beq     :+
        jmp     bad
:       lda     rsp+12
        rts
; the same; Z clear = error (A = result)
open0:  sta     t_open+7
        stx     t_open+4
        ldx     #.loword(t_open)
        jmp     mbdo
; A = handle
close:  sta     t_close+8
        ldx     #.loword(t_close)
        jsr     mbdo
        beq     :+
        jmp     bad
:       rts
; X = path: DELETE (the result ignored)
del:    stx     t_del+4
        ldx     #.loword(t_del)
        jmp     mbdo
; A = handle, X = READ or WRITE template: one CHUNK (stops on an error or a short count)
rw:     sta     a:8,x
        jsr     mbdo
        beq     :+
        jmp     bad
:       ldx     rsp+12
        cpx     #CHUNK
        beq     :+
        lda     #$EC
        jmp     bad
:       rts

; ---- phases: A = digit
pstart: sta     m_p+1
        sta     m_ps+1
        ldx     #.loword(m_ps)
        jsr     puts
        rep     #$20
        .a16
        stz     kd
        stz     ku
        stz     mc
        stz     dxs
        stz     dxs+2
        stz     gmax
        stz     gmax+2
        stz     hlast
        sep     #$20
        .a8
        jsr     gettime
        rep     #$20
        .a16
        lda     now
        sta     ts
        lda     now+2
        sta     ts+2
        sep     #$20
        .a8
        rts

pend:   jsr     gettime
        rep     #$20
        .a16
        sec
        lda     now
        sbc     ts
        sta     now
        lda     now+2
        sbc     ts+2
        sta     now+2
        sep     #$20
        .a8
        ldx     #.loword(m_p)
        jsr     puts
        ldx     #.loword(now)
        jsr     put32
        ldx     #.loword(m_kd)
        jsr     puts
        ldx     #.loword(kd)
        jsr     put16
        ldx     #.loword(m_ku)
        jsr     puts
        ldx     #.loword(ku)
        jsr     put16
        ldx     #.loword(m_m)
        jsr     puts
        ldx     #.loword(mc)
        jsr     put16
        ldx     #.loword(m_dx)
        jsr     puts
        ldx     #.loword(dxs)
        jsr     put32
        ldx     #.loword(m_g)
        jsr     puts
        ldx     #.loword(gmax)
        jsr     put32
        jmp     crlf

; A = time in 65.5 ms units (1-255): take events until it has passed
idle:   sta     cnt
        jsr     gettime
        lda     now+2
        sta     t0
:       jsr     poll_ev
        jsr     gettime
        lda     now+2
        sec
        sbc     t0
        cmp     cnt
        bcc     :-
        rts

; ---- every waiting entry of the response ring: events counted, an answer copied to rsp
poll_ev:
        lda     f:MB_RSP_TAIL
        cmp     f:MB_RSP_HEAD
        bne     :+
        rts
:       rep     #$20
        .a16
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
        beq     @key
        cmp     #$E1
        beq     @mouse
        cmp     #$80
        bcc     @nx
        cmp     #$E0
        bcc     :+
@nx:    jmp     @next
:       ldy     #0                      ; an answer
:       lda     f:RSP_RING,x
        sta     rsp,y
        inx
        iny
        cpy     #16
        bne     :-
        lda     #1
        sta     got
        jmp     @next
@key:   lda     f:RSP_RING+13,x         ; 1 = down
        rep     #$20
        .a16
        beq     :+
        inc     kd
        bra     @kn
:       inc     ku
@kn:    sep     #$20
        .a8
        bra     @next
@mouse: lda     f:RSP_RING+8,x          ; dx, signed
        rep     #$20
        .a16
        and     #$00FF
        cmp     #$0080
        bcc     :+
        ora     #$FF00
:       ldy     #0
        cmp     #0
        bpl     :+
        dey
:       clc
        adc     dxs
        sta     dxs
        tya
        adc     dxs+2
        sta     dxs+2
        inc     mc
        sep     #$20
        .a8
        jsr     gettime                 ; the gap since the last mouse event
        rep     #$20
        .a16
        lda     hlast
        beq     @first
        sec
        lda     now
        sbc     tlast
        sta     tg
        lda     now+2
        sbc     tlast+2
        sta     tg+2
        cmp     gmax+2
        bcc     @keep
        bne     @new
        lda     tg
        cmp     gmax
        bcc     @keep
@new:   lda     tg
        sta     gmax
        lda     tg+2
        sta     gmax+2
@keep:
@first: lda     now
        sta     tlast
        lda     now+2
        sta     tlast+2
        lda     #1
        sta     hlast
        sep     #$20
        .a8
@next:  lda     f:MB_RSP_TAIL
        inc
        sta     f:MB_RSP_TAIL
        jmp     poll_ev

; X = 16-byte request template. Sends it and takes events until its answer is in rsp.
; A = result (Z set = OK).
mbdo:   inc     mbstep
        ldy     #0
:       lda     a:0,x
        sta     msg,y
        inx
        iny
        cpy     #16
        bne     :-
        lda     mbstep
        sta     msg+1                   ; the tag
        rep     #$20
        .a16
        lda     f:MB_REQ_HEAD
        and     #$00FF
        asl
        asl
        asl
        asl
        tax
        sep     #$20
        .a8
        ldy     #0
:       lda     msg,y
        sta     f:REQ_RING,x
        inx
        iny
        cpy     #16
        bne     :-
        stz     got
        lda     f:MB_REQ_HEAD
        inc
        sta     f:MB_REQ_HEAD           ; doorbell
        jsr     mark
:       jsr     poll_ev
        lda     got
        bne     :+
        jsr     late
        bcc     :-
        lda     #$FF                    ; timeout
        sta     rsp+8
:       lda     rsp+8
        rts

mark:   jsr     gettime                 ; remember the time (65.5 ms units)
        lda     now+2
        sta     t0
        rts
late:   jsr     gettime                 ; carry set once about 16 s have passed since mark
        lda     now+2
        sec
        sbc     t0
        cmp     #250
        rts
gettime:                                ; now = UPTIME (reading the low byte latches the rest)
        lda     f:UPTIME
        sta     now
        lda     f:UPTIME+1
        sta     now+1
        lda     f:UPTIME+2
        sta     now+2
        lda     f:UPTIME+3
        sta     now+3
        rts

bad:    jsr     puthex
        lda     mbstep
        jsr     puthex
        ldx     #.loword(m_fail)
        jsr     puts
        stp

put32:  lda     a:3,x
        jsr     puthex
        lda     a:2,x
        jsr     puthex
put16:  lda     a:1,x
        jsr     puthex
        lda     a:0,x
        jmp     puthex

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

;                op  tag  len            buf                                flags  arg0        arg1
t_open:  .byte  $01, 0,  0, 0,          0, 0, $01,                          0,     0,0,0,0,    0,0,0,0
t_close: .byte  $02, 0,  0, 0,          0, 0, 0,                            0,     0,0,0,0,    0,0,0,0
t_read:  .byte  $03, 0,  <CHUNK, >CHUNK, <BUF, >.loword(BUF), ^BUF,         0,     0,0,0,0,    0,0,0,0
t_write: .byte  $04, 0,  <CHUNK, >CHUNK, <BUF, >.loword(BUF), ^BUF,         0,     0,0,0,0,    0,0,0,0
t_del:   .byte  $09, 0,  0, 0,          0, 0, $01,                          0,     0,0,0,0,    0,0,0,0

p_card:  .byte "/INTEST.TMP", 0
p_card2: .byte "/INTEST2.TMP", 0
p_pc:    .byte "/PC:/INTEST.TMP", 0
m_hello: .byte "INTEST", 10, 0
m_ps:    .byte "PX START", 10, 0
m_p:     .byte "PX US ", 0
m_kd:    .byte " KD ", 0
m_ku:    .byte " KU ", 0
m_m:     .byte " M ", 0
m_dx:    .byte " DX ", 0
m_g:     .byte " G ", 0
m_skip2: .byte "P2 SKIP", 10, "P3 SKIP", 10, 0
m_done:  .byte "INTEST DONE", 10, 0
m_fail:  .byte " INTEST FAIL", 10, 0
mbstep:  .byte 0
cnt:     .byte 0
got:     .byte 0
h1:      .byte 0
h2:      .byte 0
t0:      .byte 0
now:     .res 4
ts:      .res 4
tg:      .res 4
tlast:   .res 4
hlast:   .res 2
gmax:    .res 4
dxs:     .res 4
kd:      .res 2
ku:      .res 2
mc:      .res 2
msg:     .res 16
rsp:     .res 16
