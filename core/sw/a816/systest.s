; SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
; Copyright (c) 2026 Carlos Bravo
; Atari816: firmware system services test, SYS_SYNC ($1C) and SYS_RESTART ($1B).
; Loaded at $01:0000 (python3 tools/atari.py run816 sw/a816/SYSTEST.BIN --seconds 15).
;   1. a /SYSTEST.TMP left by the previous run must be there with 300 bytes: it was written
;      and never closed, so only SYS_SYNC can have put its size on the card. Then deleted.
;   2. SYS_RESTART with ARG0 = 2 must answer $83 (and not restart).
;   3. create /SYSTEST.TMP, write 300 bytes, leave it open.
;   4. SYS_SYNC: OK, ARG1 = 1 handle closed.  5. STAT now answers $86.  6. SYS_SYNC again: OK.
;   7. SYS_RESTART 0 (SYSTEST.BIN) or 1 (SYSTEST1.BIN, built with -D FULL): OK. The test prints
;      its last line, waits until the firmware has taken it, then takes the reply and spins;
;      the firmware then restarts Horizon (mode 1: after /atari.ini and a classic cold boot).
; Run it twice: the first run has no previous file ("PREV NONE").
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
SRC_BUF     = $0D0000
PATH_BUF    = $0D2000
TESTLEN     = 300
.ifdef FULL
RMODE       = 1
.else
RMODE       = 0
.endif

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
        ldx     #.loword(m_mode)
        jsr     puts
        lda     #RMODE
        jsr     puthex
        jsr     crlf

        lda     #$00                    ; rings at $0E:0000 / $0E:1000
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
        ldx     #0                      ; source pattern
:       txa
        asl
        adc     #3
        sta     f:SRC_BUF,x
        inx
        cpx     #TESTLEN
        bne     :-

; 1 file from the previous run
        jsr     setpath
        ldx     #.loword(t_stat)
        jsr     mbdo
        cmp     #4                      ; no such file
        bne     :+
        ldx     #.loword(m_none)
        jsr     puts
        bra     s2
:       cmp     #0
        beq     :+
        jmp     bad
:       ldx     #.loword(m_prev)
        jsr     puts
        lda     f:PATH_BUF+1
        jsr     puthex
        lda     f:PATH_BUF
        jsr     puthex
        rep     #$20
        .a16
        lda     f:PATH_BUF
        cmp     #TESTLEN
        sep     #$20
        .a8
        beq     :+
        jsr     fail
        bra     s1d
:       jsr     ok
s1d:    ldx     #.loword(t_del)
        jsr     mbdo
        beq     s2
        jmp     bad

; 2 bad restart mode
s2:     ldx     #.loword(t_rbad)
        jsr     mbdo
        cmp     #$83
        beq     :+
        jmp     bad
:       ldx     #.loword(m_badarg)
        jsr     puts
        jsr     ok

; 3 create, write, leave open
        ldx     #.loword(t_openc)
        jsr     mbdo
        beq     :+
        jmp     bad
:       lda     rsp+12                  ; the handle
        sta     t_write+8
        ldx     #.loword(t_write)
        jsr     mbdo
        beq     :+
        jmp     bad
:       ldx     rsp+12
        cpx     #TESTLEN
        beq     :+
        jmp     bad

; 4 sync: OK, one handle closed
:       ldx     #.loword(t_sync)
        jsr     mbdo
        beq     :+
        jmp     bad
:       lda     rsp+12
        cmp     #1
        beq     :+
        jmp     bad
:       ldx     #.loword(m_sync)
        jsr     puts
        jsr     ok

; 5 file ops refused
        jsr     setpath
        ldx     #.loword(t_stat)
        jsr     mbdo
        cmp     #$86
        beq     :+
        jmp     bad
:       ldx     #.loword(m_locked)
        jsr     puts
        jsr     ok

; 6 sync again
        ldx     #.loword(t_sync)
        jsr     mbdo
        beq     :+
        jmp     bad
:       lda     rsp+12
        beq     :+
        jmp     bad
:
; 7 restart: send, wait for the reply, print, let the firmware take the output, then take it
        ldx     #.loword(t_rst)
        jsr     mbsend
        jsr     mark
:       lda     f:MB_RSP_HEAD
        cmp     f:MB_RSP_TAIL
        bne     :+
        jsr     late
        bcc     :-
        lda     #$FF
        sta     rsp+8
        bra     bad
:       jsr     mbget
        lda     rsp+8
        bne     bad
        ldx     #.loword(m_rst)
        jsr     puts
        jsr     ok
        ldx     #.loword(m_done)
        jsr     puts
:       lda     f:DBG_STAT              ; last byte taken by the firmware
        bmi     :-
        lda     f:MB_RSP_TAIL           ; now take the reply: the firmware restarts us
        inc
        sta     f:MB_RSP_TAIL
spin:   bra     spin

bad:    jsr     puthex                  ; result or step
        lda     mbstep
        jsr     puthex
        jsr     fail
        ldx     #.loword(m_done)
        jsr     puts
        stp

setpath:                                ; test file name -> PATH_BUF (STAT writes there)
        ldx     #0
:       lda     p_tmp,x
        sta     f:PATH_BUF,x
        inx
        cmp     #0
        bne     :-
        rts

; X = 16-byte request template. Sends it, waits for the answer in rsp. A = result (Z set = OK).
mbdo:   jsr     mbsend
        jsr     mark
:       lda     f:MB_RSP_HEAD
        cmp     f:MB_RSP_TAIL
        bne     :+
        jsr     late
        bcc     :-
        lda     #$FF                    ; timeout
        sta     rsp+8
        rts
:       jsr     mbget
        lda     f:MB_RSP_TAIL
        inc
        sta     f:MB_RSP_TAIL
        lda     rsp+8
        rts

mbsend: inc     mbstep
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
        rts

mbget:  rep     #$20                    ; response at MB_RSP_TAIL -> rsp (tail not moved)
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
        rts

mark:   jsr     gettime                 ; remember the time (65 ms units)
        lda     now+2
        sta     t0
        rts
late:   jsr     gettime                 ; carry set once about 3 s have passed since mark
        lda     now+2
        sec
        sbc     t0
        cmp     #46
        rts
gettime:                                ; now = UPTIME (reading the low byte latches the rest)
        lda     f:UPTIME
        sta     now
        lda     f:UPTIME+1
        sta     now+1
        lda     f:UPTIME+2
        sta     now+2
        rts

ok:     ldx     #.loword(m_ok)
        bra     puts
fail:   ldx     #.loword(m_fail)
        bra     puts
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
t_stat:  .byte  $06, 1,  0, 0,          <PATH_BUF, >.loword(PATH_BUF), ^PATH_BUF, 0,     0,0,0,0,    0,0,0,0
t_del:   .byte  $09, 2,  0, 0,          <p_tmp, >p_tmp, $01,                      0,     0,0,0,0,    0,0,0,0
t_rbad:  .byte  $1B, 3,  0, 0,          0, 0, 0,                                  0,     2,0,0,0,    0,0,0,0
t_openc: .byte  $01, 4,  0, 0,          <p_tmp, >p_tmp, $01,                      2,     0,0,0,0,    0,0,0,0
t_write: .byte  $04, 5,  <TESTLEN, >TESTLEN, <SRC_BUF, >.loword(SRC_BUF), ^SRC_BUF, 0,   0,0,0,0,    0,0,0,0
t_sync:  .byte  $1C, 6,  0, 0,          0, 0, 0,                                  0,     0,0,0,0,    0,0,0,0
t_rst:   .byte  $1B, 7,  0, 0,          0, 0, 0,                                  0,     RMODE,0,0,0, 0,0,0,0

p_tmp:   .byte "/SYSTEST.TMP", 0
m_hello: .byte "SYS TEST REV ", 0
m_mode:  .byte " RESTART MODE ", 0
m_none:  .byte "PREV NONE", 10, 0
m_prev:  .byte "PREV SIZE ", 0
m_badarg: .byte "BAD MODE", 0
m_sync:  .byte "SYNC", 0
m_locked: .byte "LOCKED", 0
m_rst:   .byte "RESTART", 0
m_ok:    .byte " OK", 10, 0
m_fail:  .byte " FAIL", 10, 0
m_done:  .byte "DONE", 10, 0
mbstep:  .byte 0
t0:      .byte 0
now:     .res 4
msg:     .res 16
rsp:     .res 16
