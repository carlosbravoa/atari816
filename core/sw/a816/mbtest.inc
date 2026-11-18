; SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
; Copyright (c) 2026 Carlos Bravo
; I/O processor mailbox test: create, write, read back, stat, delete, load, list.
; Included by freddie2.s; entered at mbtest in kernel state, leaves through mb_done.
MB_REQ_BASE = $00DD00
MB_REQ_HEAD = $00DD03
MB_RSP_BASE = $00DD05
MB_RSP_HEAD = $00DD08
MB_RSP_TAIL = $00DD09
MB_STATUS   = $00DD0A
REQ_RING    = $0E0000
RSP_RING    = $0E1000
SRC_BUF     = $0D0000
DST_BUF     = $0D1000
PATH_BUF    = $0D2000
LOAD_BUF    = $0C0000
TESTLEN     = 300

        .a8
        .i16
mbtest: ldx     #.loword(m_mb)
        jsr     puts
        stz     mbstep
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
        jsr     mb_mark
:       lda     f:MB_STATUS             ; wait for IOP_READY
        and     #$01
        bne     mb_go
        jsr     mb_late
        bcc     :-
        ldx     #.loword(m_noiop)       ; no I/O processor (simulation): not a failure
        jsr     puts
        jmp     mb_done

mb_go:  ldx     #0                      ; source pattern; destination filled and read (cached)
:       txa
        asl
        adc     #3
        sta     f:SRC_BUF,x
        lda     #$EE
        sta     f:DST_BUF,x
        lda     f:DST_BUF,x
        inx
        cpx     #TESTLEN
        bne     :-

        ldx     #.loword(t_openc)       ; 1 create
        jsr     mbdo
        bne     mb_bad
        ldx     #.loword(t_write)       ; 2 write
        jsr     mbdo
        bne     mb_bad
        ldx     rsp+12
        cpx     #TESTLEN
        bne     mb_bad
        ldx     #.loword(t_close)       ; 3
        jsr     mbdo
        bne     mb_bad
        ldx     #.loword(t_openr)       ; 4 open for reading
        jsr     mbdo
        bne     mb_bad
        ldx     #.loword(t_read)        ; 5 read: more asked than there is
        jsr     mbdo
        bne     mb_bad
        ldx     rsp+12
        cpx     #TESTLEN
        bne     mb_bad
        ldx     #0
:       lda     f:DST_BUF,x             ; must be the file, not the cached $EE
        cmp     f:SRC_BUF,x
        bne     mb_bad
        inx
        cpx     #TESTLEN
        bne     :-
        ldx     #.loword(t_close)       ; 6
        jsr     mbdo
        bne     mb_bad
        jsr     mb_setpath
        ldx     #.loword(t_stat)        ; 7 stat: size comes back in the buffer
        jsr     mbdo
        bne     mb_bad
        rep     #$20
        .a16
        lda     f:PATH_BUF
        cmp     #TESTLEN
        sep     #$20
        .a8
        bne     mb_bad
        ldx     #.loword(t_del)         ; 8 delete
        jsr     mbdo
        bne     mb_bad
        jsr     mb_setpath
        ldx     #.loword(t_stat)        ; 9 stat again: no such file
        jsr     mbdo
        cmp     #4
        bne     mb_bad
        bra     mb_load
mb_bad: lda     mbstep
        jsr     puthex
        lda     rsp+8
        jsr     puthex
        jsr     fail
        jmp     mb_done

mb_load:
        ldx     #.loword(t_load)        ; 10 load this very program and compare
        jsr     mbdo
        bne     mb_bad
        ldx     #0
:       lda     f:LOAD_BUF,x
        cmp     f:$010000,x
        bne     mb_bad
        inx
        cpx     #256
        bne     :-
        lda     #'/'
        sta     f:PATH_BUF
        lda     #0
        sta     f:PATH_BUF+1
        ldx     #.loword(t_dir)         ; 11 list the root directory
        jsr     mbdo
        bne     mb_bad
        ldx     #.loword(m_files)
        jsr     puts
        lda     rsp+12
        jsr     puthex
        jsr     crlf
        jmp     mb_done

mb_setpath:                             ; copy the test file name to PATH_BUF
        ldx     #0
:       lda     p_tmp,x
        sta     f:PATH_BUF,x
        inx
        cmp     #0
        bne     :-
        rts

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
        jsr     mb_mark
:       lda     f:MB_RSP_HEAD
        cmp     f:MB_RSP_TAIL
        bne     :+
        jsr     mb_late
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

mb_mark:                                ; remember the time (65 ms units)
        jsr     gettime
        lda     now+2
        sta     mbt0
        rts
mb_late:                                ; carry set once about 3 s have passed since mb_mark
        jsr     gettime
        lda     now+2
        sec
        sbc     mbt0
        cmp     #46
        rts

;                op  tag  len            buf                                      flags  arg0        arg1
t_openc: .byte  $01, 1,  0, 0,          <p_tmp, >p_tmp, $01,                      2,     0,0,0,0,    0,0,0,0
t_write: .byte  $04, 2,  <TESTLEN, >TESTLEN, <SRC_BUF, >.loword(SRC_BUF), ^SRC_BUF, 0,   0,0,0,0,    0,0,0,0
t_close: .byte  $02, 3,  0, 0,          0, 0, 0,                                  0,     0,0,0,0,    0,0,0,0
t_openr: .byte  $01, 4,  0, 0,          <p_tmp, >p_tmp, $01,                      0,     0,0,0,0,    0,0,0,0
t_read:  .byte  $03, 5,  0, 2,          <DST_BUF, >.loword(DST_BUF), ^DST_BUF,    0,     0,0,0,0,    0,0,0,0
t_stat:  .byte  $06, 6,  0, 0,          <PATH_BUF, >.loword(PATH_BUF), ^PATH_BUF, 0,     0,0,0,0,    0,0,0,0
t_del:   .byte  $09, 7,  0, 0,          <p_tmp, >p_tmp, $01,                      0,     0,0,0,0,    0,0,0,0
t_load:  .byte  $10, 8,  0, 0,          <p_self, >p_self, $01,                    0,     <LOAD_BUF, >.loword(LOAD_BUF), ^LOAD_BUF, 0,  0,0,0,0
t_dir:   .byte  $07, 9,  0, 2,          <PATH_BUF, >.loword(PATH_BUF), ^PATH_BUF, 0,     0,0,0,0,    0,0,0,0

p_tmp:   .byte "/A816TEST.TMP", 0
p_self:  .byte "/A816.BIN", 0
m_mb:    .byte "MAILBOX ", 0
m_noiop: .byte "NO IOP", 10, 0
m_files: .byte "OK FILES ", 0
mbstep:  .byte 0
mbt0:    .byte 0
msg:     .res 16
rsp:     .res 16
