; ECHO - a TCP client: connect, send a line, print the answer. Horizon 0.22 (Atari816).
;
;   > echo tcp://192.168.1.20:7 "Hello there"
;   echo: connected to tcp://192.168.1.20:7
;   sent: Hello there
;   answer: Hello there
;
; Shows: tcp://host:port opens a connection (on handles 4-7) with the normal open call.
; Its read and write never wait: write takes what fits (maybe 0 bytes: try again), read
; gives what has come (0 = nothing yet) and E_CLOSED after the other end closed. A program
; without windows polls: read, and if nothing came, sleep 10 ms and read again (here at
; most 5 s). A window program would wait for WE_NET instead (see the SDK's internet page).
;
; The connection is made by the PC (the gateway, tools/atari816-link): any host the PC can
; reach, on the internet or the home network. tls://host:port is the same with TLS.
; Build: make; test in the emulator: make test (an echo server on this PC).

        .include "horizon.inc"

        .segment "CODE"
        .a16
        .i16

URLMAX  = 127
MSGMAX  = 100
ANSMAX  = 200
TICKS   = 500                           ; 500 x 10 ms = give up after 5 s

start:  sta     z:alen
        jsr     args_init

        ptr     url
        lda     #URLMAX + 3
        jsr     next_arg                ; the URL
        bcc     :+
        print   "usage: echo tcp://host:port [text]\n"
        exit    2
:       cmp     #URLMAX + 1
        bcc     :+
        print   "echo: the URL is too long (127 characters at most)\n"
        exit    1
:       ptr     msg                     ; the text to send (default: a greeting)
        lda     #MSGMAX
        jsr     next_arg
        bcc     @have
        ldx     #0                      ; copy the default text
:       lda     hello,x
        sta     msg,x
        inx
        inx
        cpx     #HELLOLEN + 2
        bcc     :-
        lda     #HELLOLEN
@have:  sta     z:mlen

; ---- connect: open waits until connected or failed (about 20 s at most)
        ptr     url
        lda     #O_READ
        sys     SYS_OPEN                ; -> A = handle 4-7
        bcc     :+
        jsr     show_err                ; E_REFUSED, E_NONAME, E_TIMEOUT, ...
        exit    1
:       sta     z:fh
        print   "echo: connected to "
        ptr     url
        jsr     out_str
        jsr     put_nl

        print   "sent: "
        ptr     msg
        jsr     out_str
        jsr     put_nl
        ldx     z:mlen                  ; the line ends with LF
        lda     #10
        sta     msg,x                   ; (16-bit store: a 0 after it, fine)
        inc     z:mlen

; ---- send: write never waits; it takes what fits and returns the count
        stz     z:sent
        stz     z:ticks
@wr:    lda     z:fh
        sta     iob
        lda     #.loword(msg)
        clc
        adc     z:sent                  ; from the first byte not yet taken
        sta     iob+1
        sep     #$20
        .a8
        lda     #^msg
        sta     iob+3
        rep     #$20
        .a16
        lda     z:mlen
        sec
        sbc     z:sent
        sta     iob+4
        ptr     iob
        sys     SYS_WRITE               ; -> A = bytes taken (maybe 0)
        jcs     fail
        clc
        adc     z:sent
        sta     z:sent
        cmp     z:mlen
        bcs     @rdstart                ; all sent
        jsr     tick                    ; not all taken: wait 10 ms and try again
        jcs     timeout
        bra     @wr

; ---- the answer: read never waits; 0 = nothing yet, E_CLOSED = the other end closed
@rdstart:
        stz     z:got
        stz     z:ticks
@rd:    lda     z:fh
        sta     iob
        lda     #.loword(ans)
        clc
        adc     z:got
        sta     iob+1
        sep     #$20
        .a8
        lda     #^ans
        sta     iob+3
        rep     #$20
        .a16
        lda     #ANSMAX
        sec
        sbc     z:got
        sta     iob+4
        ptr     iob
        sys     SYS_READ                ; -> A = bytes that had come (0: none yet)
        bcc     @data
        cmp     #E_CLOSED
        jne     fail
        lda     z:got                   ; closed: show what came before
        jne     @show
        print   "echo: the server closed the connection without an answer\n"
        jmp     closex
@data:  cmp     #0                      ; (a syscall does not set Z from A)
        bne     @some
        jsr     tick                    ; nothing yet: sleep 10 ms, then read again
        jcs     timeout
        jmp     @rd                     ; (too far for a BRA)
@some:  clc
        adc     z:got
        sta     z:got
        cmp     #ANSMAX
        bcs     @show                   ; the buffer is full
        ldx     #0                      ; a whole line yet?
:       lda     ans,x
        and     #$00FF
        cmp     #10
        beq     @show
        inx
        cpx     z:got
        bcc     :-
        jmp     @rd                     ; (too far for a BRA)

@show:  ldx     #0                      ; cut at the first CR / LF, end with a 0
:       cpx     z:got
        bcs     :+
        lda     ans,x
        and     #$00FF
        cmp     #10
        beq     :+
        cmp     #13
        beq     :+
        inx
        bra     :-
:       sep     #$20
        .a8
        stz     ans,x
        rep     #$20
        .a16
        print   "answer: "
        ptr     ans
        jsr     out_str
        jsr     put_nl
        lda     z:fh
        sys     SYS_CLOSE               ; ends the connection
        exit    0

timeout:
        print   "echo: no answer within 5 s\n"
closex: lda     z:fh
        sys     SYS_CLOSE
        exit    1

fail:   jsr     show_err
        bra     closex

; Sleep 10 ms. C set when the 5 s are over.
tick:   lda     #10
        sys     SYS_SLEEP
        inc     z:ticks
        lda     z:ticks
        cmp     #TICKS
        rts

; Print "echo: " and the message for the error in A.
show_err:
        sta     z:err
        print   "echo: "
        ldx     #0
@l:     lda     errtab,x
        beq     @unknown
        cmp     z:err
        beq     @found
        inx
        inx
        inx
        inx
        bra     @l
@found: lda     errtab+2,x
        tax
        ldy     #^errtab
        jsr     out_str
        jmp     put_nl
@unknown:
        print   "error $"
        lda     z:err
        jsr     put_hex8
        jmp     put_nl

        .segment "RODATA"
hello:  .byte   "Hello from the Atari816"
HELLOLEN = * - hello
        .byte   0, 0
errtab: .word   E_NOLINK,  m_nolink
        .word   E_LOST,    m_lost
        .word   E_NOSVC,   m_nosvc
        .word   E_BADADDR, m_badaddr
        .word   E_NONAME,  m_noname
        .word   E_REFUSED, m_refused
        .word   E_TIMEOUT, m_timeout
        .word   E_CLOSED,  m_closed
        .word   E_TLS,     m_tls
        .word   E_PCBUSY,  m_pcbusy
        .word   E_NET,     m_net
        .word   E_NSTREAM, m_nstream
        .word   EIO + 6,   m_badname
        .word   EINVAL,    m_inval
        .word   0
m_nolink:  .byte "no PC link: start the gateway (tools/atari816-link) on the PC", 0
m_lost:    .byte "the PC link was lost", 0
m_nosvc:   .byte "no internet service: the gateway is older, or was started with --no-net", 0
m_badaddr: .byte "bad address (tcp://host:port, port 1-65535)", 0
m_noname:  .byte "name not found (no such host)", 0
m_refused: .byte "refused or unreachable (is the server running?)", 0
m_timeout: .byte "timeout: no connection", 0
m_closed:  .byte "the connection was closed", 0
m_tls:     .byte "TLS failed (a bad certificate?)", 0
m_pcbusy:  .byte "too many connections on the PC", 0
m_net:     .byte "network error", 0
m_nstream: .byte "all four internet handles are in use", 0
m_badname: .byte "bad name (a firmware without the internet?)", 0
m_inval:   .byte "bad path (127 characters at most)", 0

        .segment "BSS"
url:    .res    URLMAX + 4
msg:    .res    MSGMAX + 2
ans:    .res    ANSMAX + 2
iob:    .res    6

        .segment "ZEROPAGE"
alen:   .res    2
fh:     .res    2
mlen:   .res    2
sent:   .res    2
got:    .res    2
ticks:  .res    2
err:    .res    2
