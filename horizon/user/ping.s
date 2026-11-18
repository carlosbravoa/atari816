; PING - creates a port, starts PONG with the port number as its argument string, receives PONG's
; port in a hello message, then sends three pings and checks the replies.
; Message: word 0 = type ('H' hello, 'P' ping, 'R' reply, 'Q' quit), word 2 = value.
        .include "horizon.inc"
        .segment "CODE"
        .a16
        .i16
start:  sys     SYS_PCREATE
        jcs     @bad
        sta     z:myport
        cmp     #10                     ; argument string: the port in decimal
        bcc     :+
        sbc     #10
        pha
        lda     #'1'
        sta     argbuf
        pla
        ora     #'0'
        sta     argbuf+1                ; (16-bit: writes the terminator too)
        bra     :++
:       ora     #'0'
        sta     argbuf
:       lda     #.loword(argbuf)
        sta     z:u_arg
        lda     #^argbuf
        sta     z:u_arg+2
        ptr     pong
        lda     #2
        jsr     spawn
        jcs     @bad
        sta     z:pongid
        jsr     getmsg                  ; hello: PONG's port
        lda     msg
        cmp     #'H'
        jne     @bad
        lda     msg+2
        sta     z:peer
        print   "ping: pong is on port "
        lda     z:peer
        jsr     put_dec
        jsr     put_nl
        lda     #1
        sta     z:n
@loop:  lda     #'P'
        sta     msg
        lda     z:n
        sta     msg+2
        lda     z:peer
        ptr     msg
        sys     SYS_SEND
        jcs     @bad
        jsr     getmsg
        print   "ping: sent "
        lda     z:n
        jsr     put_dec
        print   ", reply "
        lda     msg+2
        jsr     put_dec
        jsr     put_nl
        inc     z:n
        lda     z:n
        cmp     #4
        bcc     @loop
        lda     #'Q'
        sta     msg
        lda     z:peer
        ptr     msg
        sys     SYS_SEND
        lda     z:pongid
        sys     SYS_WAIT
        pha
        print   "ping: pong exit "
        pla
        jsr     put_hex16
        jsr     put_nl
        lda     z:myport
        sys     SYS_PCLOSE
        exit    0
@bad:   print   "ping: FAILED\n"
        exit    1

getmsg: lda     z:myport
        ptr     msg
        sys     SYS_RECV
        rts

        .segment "RODATA"
pong:   .byte   "/SYSTEM/TESTS/PONG.PRG", 0
        .segment "BSS"
msg:    .res    16
argbuf: .res    4
        .segment "ZEROPAGE"
myport: .res    2
pongid: .res    2
peer:   .res    2
n:      .res    2
