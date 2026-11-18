; SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
; Copyright (c) 2026 Carlos Bravo
;
; Atari816: SD card throughput through the I/O processor mailbox.
; python3 tools/atari.py run816 sw/a816/FSBENCH.BIN --seconds 40
;   WRITE  512 KB to /FSBENCH.TMP in 32 KB WRITE requests (create, write, close)
;   READ   the same 512 KB back in 32 KB READ requests (open, read, close), first 32 KB checked
;   LOAD   the whole file with one LOAD request
; Each line prints the time in microseconds (hex) for the whole phase, open and close included.
; The file is deleted at the end.
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
SRC_BUF     = $0C0000               ; 32 KB pattern
DST_BUF     = $0C8000               ; 32 KB read buffer
LOAD_BUF    = $040000               ; 512 KB: banks $04 to $0B
CHUNK       = $8000
NCHUNK      = 16

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
        ldx     #0                      ; 32 KB pattern
:       txa
        eor     #$5A
        sta     f:SRC_BUF,x
        inx
        cpx     #CHUNK
        bne     :-

; WRITE
        jsr     tstart
        ldx     #.loword(t_openc)
        jsr     mbdo
        beq     :+
        jmp     bad
:       lda     rsp+12
        sta     t_write+8
        sta     t_close+8
        lda     #NCHUNK
        sta     cnt
wloop:  ldx     #.loword(t_write)
        jsr     mbdo
        beq     :+
        jmp     bad
:       ldx     rsp+12
        cpx     #CHUNK
        beq     :+
        jmp     bad
:       dec     cnt
        bne     wloop
        ldx     #.loword(t_close)
        jsr     mbdo
        beq     :+
        jmp     bad
:       ldx     #.loword(m_write)
        jsr     tprint

; READ
        jsr     tstart
        ldx     #.loword(t_openr)
        jsr     mbdo
        beq     :+
        jmp     bad
:       lda     rsp+12
        sta     t_read+8
        sta     t_close+8
        lda     #NCHUNK
        sta     cnt
rloop:  ldx     #.loword(t_read)
        jsr     mbdo
        beq     :+
        jmp     bad
:       ldx     rsp+12
        cpx     #CHUNK
        beq     :+
        jmp     bad
:       dec     cnt
        bne     rloop
        ldx     #.loword(t_close)
        jsr     mbdo
        beq     :+
        jmp     bad
:       ldx     #.loword(m_read)
        jsr     tprint
        ldx     #0                      ; the last chunk read must be the pattern
:       lda     f:DST_BUF,x
        cmp     f:SRC_BUF,x
        beq     :+
        lda     #$EE
        jmp     bad
:       inx
        cpx     #CHUNK
        bne     :--

; LOAD
        jsr     tstart
        ldx     #.loword(t_load)
        jsr     mbdo
        beq     :+
        jmp     bad
:       ldx     #.loword(m_load)
        jsr     tprint
        ldx     #.loword(t_del)
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
        lda     rsp+8
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
t_openc: .byte  $01, 1,  0, 0,          <p_tmp, >p_tmp, $01,                      2,     0,0,0,0,    0,0,0,0
t_write: .byte  $04, 2,  <CHUNK, >CHUNK, <SRC_BUF, >.loword(SRC_BUF), ^SRC_BUF,   0,     0,0,0,0,    0,0,0,0
t_close: .byte  $02, 3,  0, 0,          0, 0, 0,                                  0,     0,0,0,0,    0,0,0,0
t_openr: .byte  $01, 4,  0, 0,          <p_tmp, >p_tmp, $01,                      0,     0,0,0,0,    0,0,0,0
t_read:  .byte  $03, 5,  <CHUNK, >CHUNK, <DST_BUF, >.loword(DST_BUF), ^DST_BUF,   0,     0,0,0,0,    0,0,0,0
t_load:  .byte  $10, 6,  0, 0,          <p_tmp, >p_tmp, $01,                      0,     <LOAD_BUF, >.loword(LOAD_BUF), ^LOAD_BUF, 0,  0,0,0,0
t_del:   .byte  $09, 7,  0, 0,          <p_tmp, >p_tmp, $01,                      0,     0,0,0,0,    0,0,0,0

p_tmp:   .byte "/FSBENCH.TMP", 0
m_hello: .byte "FS BENCH 512 KB REV ", 0
m_write: .byte "WRITE US ", 0
m_read:  .byte "READ US ", 0
m_load:  .byte "LOAD US ", 0
m_pass:  .byte "FSBENCH PASS", 10, 0
m_fail:  .byte " FSBENCH FAIL", 10, 0
mbstep:  .byte 0
cnt:     .byte 0
t0:      .byte 0
now:     .res 4
ts:      .res 4
msg:     .res 16
rsp:     .res 16
