; SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
; Copyright (c) 2026 Carlos Bravo
;
; Atari816: the internet through the PC link (step 2): speed of a URL read and the round trip
; of one byte on a connection, through the I/O processor mailbox. Needs the gateway and, on
; the PC, a web server on 127.0.0.1:8816 serving /big.bin and an echo server on 127.0.0.1:8817
; (core/tools/netbench_servers.py starts both).
; python3 tools/atari.py run816 sw/a816/NETBENCH.BIN --seconds 90 --until NETBENCH
;   URL    OPEN http://127.0.0.1:8816/big.bin, READ in 32 KB requests to the end, CLOSE:
;          prints the bytes (hex) and the time in microseconds (hex)
;   ECHO   OPEN tcp://127.0.0.1:8817, then 100 times: WRITE 1 byte, READ until it is back
;          (polling): prints the time in microseconds (hex) for the 100 round trips
        .p816
        .smart  -

SYS_REV     = $00DE01
DBG_OUT     = $00DEF0
DBG_STAT    = $00DEF1
UPTIME      = $00DE18
MB_REQ_BASE = $00DD00
MB_REQ_HEAD = $00DD03
MB_RSP_BASE = $00DD05
MB_RSP_HEAD = $00DD08
MB_RSP_TAIL = $00DD09
MB_STATUS   = $00DD0A
REQ_RING    = $0E0000
RSP_RING    = $0E1000
DST_BUF     = $0C8000               ; 32 KB read buffer
CHUNK       = $8000

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
        lda     f:SYS_REV
        jsr     puthex
        jsr     crlf
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
:
; URL
        jsr     tstart
        ldx     #.loword(t_openu)
        jsr     mbdo
        beq     :+
        jmp     bad
:       lda     rsp+12
        sta     t_read+8
        sta     t_close+8
        stz     total
        stz     total+1
        stz     total+2
uloop:  ldx     #.loword(t_read)
        jsr     mbdo
        beq     :+
        jmp     bad
:       rep     #$20
        .a16
        clc
        lda     rsp+12
        adc     total
        sta     total
        sep     #$20
        .a8
        lda     total+2
        adc     #0
        sta     total+2
        ldx     rsp+12
        cpx     #CHUNK
        beq     uloop
        ldx     #.loword(t_close)
        jsr     mbdo
        beq     :+
        jmp     bad
:       ldx     #.loword(m_bytes)
        jsr     puts
        lda     total+2
        jsr     puthex
        lda     total+1
        jsr     puthex
        lda     total
        jsr     puthex
        jsr     crlf
        ldx     #.loword(m_url)
        jsr     tprint

; ECHO
        ldx     #.loword(t_opent)
        jsr     mbdo
        beq     :+
        jmp     bad
:       lda     rsp+12
        sta     t_wr1+8
        sta     t_rd1+8
        sta     t_close+8
        jsr     tstart
        lda     #100
        sta     cnt
eloop:  ldx     #.loword(t_wr1)
        jsr     mbdo
        beq     :+
        jmp     bad
:       ldx     #.loword(t_rd1)
        jsr     mbdo
        beq     :+
        jmp     bad
:       lda     rsp+12
        beq     :--
        dec     cnt
        bne     eloop
        ldx     #.loword(m_echo)
        jsr     tprint
        ldx     #.loword(t_close)
        jsr     mbdo
        beq     :+
        jmp     bad
:       ldx     #.loword(m_pass)
        jsr     puts
        stp

bad:    jsr     puthex
        lda     mbstep
        jsr     puthex
        ldx     #.loword(m_fail)
        jsr     puts
        stp

tstart: jsr     gettime
        rep     #$20
        .a16
        lda     now
        sta     ts
        lda     now+2
        sta     ts+2
        sep     #$20
        .a8
        rts
tprint: jsr     puts                    ; X = label; prints the time since tstart
        jsr     gettime
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
        lda     now+3
        jsr     puthex
        lda     now+2
        jsr     puthex
        lda     now+1
        jsr     puthex
        lda     now
        jsr     puthex
        jmp     crlf

; X = 16-byte request template. Sends it, waits for the answer in rsp. A = result (Z set = OK).
mbdo:   inc     mbstep
        ldy     #0
:       lda     a:0,x
        sta     msg,y
        inx
        iny
        cpy     #16
        bne     :-
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
        lda     f:MB_REQ_HEAD
        inc
        sta     f:MB_REQ_HEAD           ; doorbell
        jsr     mark
:       lda     f:MB_RSP_HEAD
        cmp     f:MB_RSP_TAIL
        bne     :+
        jsr     late
        bcc     :-
        lda     #$FF                    ; timeout
        sta     rsp+8
        rts
:       rep     #$20
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
        ldy     #0
:       lda     f:RSP_RING,x
        sta     rsp,y
        inx
        iny
        cpy     #16
        bne     :-
        lda     f:MB_RSP_TAIL
        inc
        sta     f:MB_RSP_TAIL
        lda     rsp
        cmp     #$E0                    ; an event (NET $E4): not our answer
        bcc     :+
        jmp     :---
:       lda     rsp+8
        rts

mark:   jsr     gettime                 ; remember the time (65 ms units)
        lda     now+2
        sta     t0
        rts
late:   jsr     gettime                 ; carry set once about 10 s have passed since mark
        lda     now+2
        sec
        sbc     t0
        cmp     #153
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

;                op  tag  len            buf                                      flags  arg0        arg1
t_openu: .byte  $01, 1,  0, 0,          <p_url, >p_url, $01,                      0,     0,0,0,0,    0,0,0,0
t_read:  .byte  $03, 2,  <CHUNK, >CHUNK, <DST_BUF, >.loword(DST_BUF), ^DST_BUF,   0,     0,0,0,0,    0,0,0,0
t_close: .byte  $02, 3,  0, 0,          0, 0, 0,                                  0,     0,0,0,0,    0,0,0,0
t_opent: .byte  $01, 4,  0, 0,          <p_tcp, >p_tcp, $01,                      1,     0,0,0,0,    0,0,0,0
t_wr1:   .byte  $04, 5,  1, 0,          <onebyte, >onebyte, $01,                  0,     0,0,0,0,    0,0,0,0
t_rd1:   .byte  $03, 6,  1, 0,          <DST_BUF, >.loword(DST_BUF), ^DST_BUF,    0,     0,0,0,0,    0,0,0,0

p_url:   .byte "http://127.0.0.1:8816/big.bin", 0
p_tcp:   .byte "tcp://127.0.0.1:8817", 0
onebyte: .byte "A"
m_hello: .byte "NET BENCH REV ", 0
m_bytes: .byte "URL BYTES ", 0
m_url:   .byte "URL US ", 0
m_echo:  .byte "ECHO100 US ", 0
m_pass:  .byte "NETBENCH PASS", 10, 0
m_fail:  .byte " NETBENCH FAIL", 10, 0
mbstep:  .byte 0
cnt:     .byte 0
t0:      .byte 0
total:   .res 3
now:     .res 4
ts:      .res 4
msg:     .res 16
rsp:     .res 16
