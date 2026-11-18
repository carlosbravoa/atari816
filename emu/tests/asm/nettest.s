; emu816 test of the internet through the PC link (step 2): URL paths, the stream handles
; 4-7, requests put aside (answers matched by TAG), the $E4 NET event, link drops.
; Built three times (ca65 -D RUN=n): RUN 1 the Fetch service (--net-root, --pc-kbps 16:16),
; RUN 2 the Net service (--net, a loopback echo server), RUN 3 a link drop with a connection
; and a slow Fetch read open. The run script loads the connection URLs at $0D:6000 (A) and
; $0D:6080 (B) (their ports are chosen when the test runs) and compares the output with
; tests/expected/nettestN.txt.
;
; A list of steps. Kinds:
;   K_REQ      one request, its answer awaited: "LABEL RR VVVVVVVV" [" T OK" / " T tttt"]
;   K_READALL  READ LEN at a time until fewer come: the data, then "LABEL RR total"
;   K_WAITNET  wait for an $E4 event: "LABEL NET hh"
;   K_DRAIN    READ until an error: the data (waiting for $E4 when 0 came), then "LABEL RR ..."
;   K_SEND     a request sent; its answer not awaited (kept by TAG)
;   K_WAITTAG  the answer of the request sent with this TAG: as K_REQ, timed from the SEND
;   K_READN    READ until ARG1 bytes came (waiting for $E4 when 0 came): the data, "LABEL RR total"
; Time in 256 us units (UPTIME bytes 1-2); tmax 0 = not checked.
        .include "common.inc"

MB_REQ_BASE = $00DD00
MB_REQ_HEAD = $00DD03
MB_RSP_BASE = $00DD05
MB_RSP_HEAD = $00DD08
MB_RSP_TAIL = $00DD09
MB_STATUS   = $00DD0A
REQ_RING    = $0E0000
RSP_RING    = $0E1000
DATA        = $0C0000
WORK        = $0D4000
URLA        = $0D6000
URLB        = $0D6080

K_REQ     = 0
K_READALL = 1
K_WAITNET = 2
K_DRAIN   = 3
K_SEND    = 4
K_WAITTAG = 5
K_READN   = 6
K_END     = $FF

PA          = $FFF0             ; path: URL A / URL B (loaded)
PB          = $FFF1
H1          = $F1               ; ARG0: the handle kept in h1 / h2
H2          = $F2
HF_H1       = 1                 ; hflags: keep ARG1 of the answer in h1 / h2
HF_H2       = 2
HF_QUIET    = 4                 ; do not print the data

step        = $10
t0          = $12
dt          = $14
tsend       = $16
total       = $18
wtag        = $1A
h1          = $1C
h2          = $1D
netflag     = $1E
neth        = $1F

        .macro  STEP kind, tag, label, path, tmin, tmax, hf, op, len, buf, flags, arg0, arg1
        .byte   kind, tag
        .word   .loword(label), .loword(path), tmin, tmax
        .byte   hf, 0
        .byte   op, tag
        .word   len
        .faraddr buf
        .byte   flags
        .dword  arg0
        .dword  arg1
        .endmacro
STEPLEN = 28
S_MSG   = 12

        .segment "CODE"
        .a8
        .i16
start:  clc
        xce
        rep     #$10
        sep     #$20
        ldx     #$01FF
        txs
        phk
        plb
        lda     #0
        xba
        print   m_hello
        stz     netflag
        ldx     #0
:       stz     got,x
        inx
        cpx     #8
        bne     :-
        lda     #$00                    ; rings at $0E:0000 and $0E:1000
        sta     f:MB_REQ_BASE
        sta     f:MB_REQ_BASE+1
        sta     f:MB_RSP_BASE
        lda     #$10
        sta     f:MB_RSP_BASE+1
        lda     #$0E
        sta     f:MB_REQ_BASE+2
        sta     f:MB_RSP_BASE+2
:       lda     f:MB_STATUS
        and     #$01
        beq     :-
        sei
        lda     #$40                    ; IOP interrupt: with I set, WAI only waits for it
        sta     f:IRQ_EN

        ldx     #.loword(steps)
        stx     step
next:   ldx     step
        lda     a:0,x
        cmp     #K_END
        bne     :+
        print   m_done
        stp
:       rep     #$20
        .a16
        and     #$00FF
        asl
        tax
        sep     #$20
        .a8
        jsr     (kinds,x)
        rep     #$20
        .a16
        lda     step
        clc
        adc     #STEPLEN
        sta     step
        sep     #$20
        .a8
        bra     next

kinds:  .word   .loword(do_req), .loword(do_readall), .loword(do_waitnet), .loword(do_drain)
        .word   .loword(do_send), .loword(do_waittag), .loword(do_readn)

; ── the kinds ──
do_req: jsr     build
        jsr     send
        jsr     wait_mine
        jsr     elapsed
        jsr     keep_h
        jmp     result

do_send:
        jsr     build
        jsr     send
        ldx     t0
        stx     tsend
        rts

do_waittag:
        ldx     step
        lda     a:1,x
        jsr     wait_tag
        jsr     now
        rep     #$20
        .a16
        txa
        sec
        sbc     tsend
        sta     dt
        sep     #$20
        .a8
        jsr     keep_h
        jmp     result

do_waitnet:
        jsr     wait_net
        ldx     step
        ldy     a:2,x
        tyx
        jsr     puts
        print   m_net
        lda     neth
        jsr     puthex
        jmp     crlf

do_readall:
        ldx     #0
        stx     total
        jsr     build
        jsr     now
        stx     tsend
@loop:  jsr     send
        jsr     wait_mine
        lda     rsp+8
        bne     @end
        jsr     data_out
        rep     #$20
        .a16
        lda     rsp+12
        cmp     msg+2                   ; fewer than LEN: the end
        sep     #$20
        .a8
        bcs     @loop
@end:   jsr     now
        rep     #$20
        .a16
        txa
        sec
        sbc     tsend
        sta     dt
        lda     total
        sta     rsp+12
        stz     rsp+14
        sep     #$20
        .a8
        jmp     result

do_drain:
        ldx     #0
        stx     total
        jsr     build
@loop:  jsr     send
        jsr     wait_mine
        lda     rsp+8
        bne     @end
        jsr     data_out
        lda     rsp+12
        ora     rsp+13
        bne     @loop
        jsr     wait_net                ; nothing yet: wait for news
        bra     @loop
@end:   stz     dt
        stz     dt+1
        rep     #$20
        .a16
        lda     total
        sta     rsp+12
        stz     rsp+14
        sep     #$20
        .a8
        jmp     result

do_readn:
        ldx     #0
        stx     total
        jsr     build
@loop:  rep     #$20
        .a16
        lda     total
        cmp     msg+12                  ; ARG1: the bytes wanted
        sep     #$20
        .a8
        bcs     @done
        jsr     send
        jsr     wait_mine
        lda     rsp+8
        bne     @end
        jsr     data_out
        lda     rsp+12
        ora     rsp+13
        bne     @loop
        jsr     wait_net
        bra     @loop
@done:  stz     rsp+8
@end:   stz     dt
        stz     dt+1
        rep     #$20
        .a16
        lda     total
        sta     rsp+12
        stz     rsp+14
        sep     #$20
        .a8
        jmp     result

; ── helpers ──
; the data of a READ answer (ARG1 bytes at DATA) printed unless HF_QUIET; total += ARG1
data_out:
        rep     #$20
        .a16
        lda     total
        clc
        adc     rsp+12
        sta     total
        sep     #$20
        .a8
        ldx     step
        lda     a:10,x
        and     #HF_QUIET
        bne     @r
        ldx     #0
@l:     cpx     rsp+12
        beq     @r
        lda     f:DATA,x
        jsr     putc
        inx
        bra     @l
@r:     rts

; "LABEL RR VVVVVVVV" and the time check of the step
result: ldx     step
        ldy     a:2,x
        tyx
        jsr     puts
        lda     #' '
        jsr     putc
        lda     rsp+8
        jsr     puthex
        lda     #' '
        jsr     putc
        ldx     rsp+14
        jsr     puthex16
        ldx     rsp+12
        jsr     puthex16
        ldx     step
        ldy     a:8,x
        beq     @nl
        print   m_t
        ldx     step
        rep     #$20
        .a16
        lda     dt
        cmp     a:6,x
        bcc     @bad
        cmp     a:8,x
        beq     @ok
        bcs     @bad
@ok:    sep     #$20
        .a8
        print   m_ok
        bra     @nl
        .a16
@bad:   sep     #$20
        .a8
        ldx     dt
        jsr     puthex16
@nl:    jmp     crlf

; HF_H1 / HF_H2: keep ARG1 of the answer
keep_h: ldx     step
        lda     a:10,x
        and     #HF_H1
        beq     :+
        lda     rsp+12
        sta     h1
:       lda     a:10,x
        and     #HF_H2
        beq     :+
        lda     rsp+12
        sta     h2
:       rts

; the step's request into msg: its path to WORK (BUF = WORK), its TAG, the kept handle in ARG0
build:  ldx     step
        ldy     a:4,x
        beq     @msg
        ldx     #0
        cpy     #PA
        beq     @a
        cpy     #PB
        beq     @b
@p:     lda     a:0,y
        sta     f:WORK,x
        iny
        inx
        cpx     #128
        bne     @p
        bra     @msg
@a:     lda     f:URLA,x
        sta     f:WORK,x
        inx
        cpx     #128
        bne     @a
        bra     @msg
@b:     lda     f:URLB,x
        sta     f:WORK,x
        inx
        cpx     #128
        bne     @b
@msg:   ldx     step
        ldy     #0
:       lda     a:S_MSG,x
        sta     msg,y
        inx
        iny
        cpy     #16
        bne     :-
        ldx     step
        lda     a:4,x
        ora     a:5,x
        beq     :+
        lda     #<WORK
        sta     msg+4
        lda     #>WORK
        sta     msg+5
        lda     #^WORK
        sta     msg+6
:       lda     msg+8
        cmp     #H1
        bne     :+
        lda     h1
        sta     msg+8
        bra     :++
:       cmp     #H2
        bne     :+
        lda     h2
        sta     msg+8
:       rts

; msg into the request ring, the doorbell; t0 = now
send:   rep     #$20
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
        jsr     now
        stx     t0
        lda     f:MB_REQ_HEAD
        inc
        sta     f:MB_REQ_HEAD
        rts

elapsed:
        jsr     now
        rep     #$20
        .a16
        txa
        sec
        sbc     t0
        sta     dt
        sep     #$20
        .a8
        rts

; one entry of the response ring, if there is one: $E4 sets netflag / neth; an answer is kept
; by its TAG (1-7) in answers, got[tag] = 1
pump:   lda     f:MB_RSP_HEAD
        cmp     f:MB_RSP_TAIL
        bne     :+
        wai                             ; nothing: wait for the IOP interrupt
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
        cmp     #$E4
        bne     :+
        lda     rsp+8
        sta     neth
        lda     #1
        sta     netflag
        rts
:       cmp     #$E0                    ; other events: ignored
        bcs     @r
        lda     rsp+1
        and     #7
        sta     wtag+1                  ; (scratch)
        rep     #$20
        .a16
        and     #$0007
        asl
        asl
        asl
        asl
        tax
        sep     #$20
        .a8
        ldy     #0
:       lda     rsp,y
        sta     answers,x
        inx
        iny
        cpy     #16
        bne     :-
        rep     #$20
        .a16
        lda     wtag+1
        and     #$0007
        tax
        sep     #$20
        .a8
        lda     #1
        sta     got,x
@r:     rts

wait_mine:
        ldx     step
        lda     a:1,x
; the answer with TAG A into rsp
wait_tag:
        sta     wtag
@l:     rep     #$20
        .a16
        lda     wtag
        and     #$0007
        tax
        sep     #$20
        .a8
        lda     got,x
        bne     @got
        jsr     pump
        bra     @l
@got:   stz     got,x
        rep     #$20
        .a16
        txa
        asl
        asl
        asl
        asl
        tax
        sep     #$20
        .a8
        ldy     #0
:       lda     answers,x
        sta     rsp,y
        inx
        iny
        cpy     #16
        bne     :-
        rts

wait_net:
:       lda     netflag
        bne     :+
        jsr     pump
        bra     :-
:       stz     netflag
        rts

; X = UPTIME bytes 1-2 (256 us units)
now:    lda     f:UPTIME
        rep     #$20
        .a16
        lda     f:UPTIME+1
        tax
        sep     #$20
        .a8
        rts

;            kind       tag label     path        tmin  tmax  hflags   op   len    buf    fl arg0 arg1
steps:
.if RUN = 1
        ; Fetch (--net-root, --pc-kbps 16:16: 6 ms an OPEN / STAT, 16 KB/s)
        STEP K_REQ,     1, l_stat,    p_hello,    22,   26,   0,       $06, 0,     0,     0, 0,   0
        STEP K_REQ,     1, l_open,    p_hello,    0,    2,    HF_H1,   $01, 0,     0,     0, 0,   0
        STEP K_READALL, 1, l_readall, 0,          0,    0,    0,       $03, 10,    DATA,  0, H1,  0
        STEP K_REQ,     1, l_readend, 0,          0,    0,    0,       $03, 10,    DATA,  0, H1,  0
        STEP K_REQ,     1, l_write,   0,          0,    0,    0,       $04, 4,     DATA,  0, H1,  0
        STEP K_REQ,     1, l_seek,    0,          0,    0,    0,       $05, 0,     0,     0, H1,  0
        STEP K_REQ,     1, l_close,   0,          0,    0,    0,       $02, 0,     0,     0, H1,  0
        STEP K_REQ,     1, l_readcl,  0,          0,    0,    0,       $03, 10,    DATA,  0, H1,  0
        STEP K_REQ,     1, l_404,     p_missing,  22,   26,   0,       $06, 0,     0,     0, 0,   0
        STEP K_REQ,     1, l_ftp404,  p_ftpmiss,  22,   26,   0,       $01, 0,     0,     0, 0,   0
        STEP K_REQ,     1, l_nohost,  p_nohost,   22,   26,   0,       $06, 0,     0,     0, 0,   0
        STEP K_REQ,     1, l_mode2,   p_hello,    0,    2,    0,       $01, 0,     0,     2, 0,   0
        STEP K_REQ,     1, l_opendir, p_dir,      22,   26,   HF_H1,   $01, 0,     0,     0, 0,   0
        STEP K_READALL, 1, l_readall, 0,          0,    0,    0,       $03, 5,     DATA,  0, H1,  0
        STEP K_REQ,     1, l_close,   0,          0,    0,    0,       $02, 0,     0,     0, H1,  0
        STEP K_REQ,     1, l_mkdir,   p_hello,    0,    2,    0,       $08, 0,     0,     0, 0,   0
        STEP K_REQ,     1, l_rename,  p_ren,      0,    2,    0,       $0A, 0,     0,     0, 0,   0
        STEP K_REQ,     1, l_readdir, p_dir,      0,    2,    0,       $07, 256,   0,     0, 0,   0
        STEP K_REQ,     1, l_load,    p_hello,    0,    2,    0,       $10, 0,     0,     0, DATA, 0
        STEP K_REQ,     1, l_tcp,     p_tcp,      0,    2,    0,       $01, 0,     0,     0, 0,   0
        STEP K_REQ,     1, l_tls,     p_tls,      0,    2,    0,       $01, 0,     0,     0, 0,   0
        STEP K_REQ,     1, l_scheme,  p_gopher,   0,    2,    0,       $01, 0,     0,     0, 0,   0
        STEP K_REQ,     1, l_pc,      p_pc,       0,    2,    0,       $06, 0,     0,     0, 0,   0
        ; requests put aside: a slow READ (8 KB at 16 KB/s), a card STAT answered meanwhile
        STEP K_REQ,     1, l_openbig, p_big,      22,   26,   HF_H1,   $01, 0,     0,     0, 0,   0
        STEP K_SEND,    2, l_none,    0,          0,    0,    0,       $03, $2000, DATA,  0, H1,  0
        STEP K_REQ,     1, l_card,    p_card,     0,    2,    0,       $06, 0,     0,     0, 0,   0
        STEP K_WAITTAG, 2, l_bigread, 0,          1930, 1975,  0,       0,   0,     0,     0, 0,   0
        ; every stream handle taken: 18
        STEP K_REQ,     1, l_open,    p_hello,    0,    30,   0,       $01, 0,     0,     0, 0,   0
        STEP K_REQ,     1, l_open,    p_hello,    0,    30,   0,       $01, 0,     0,     0, 0,   0
        STEP K_REQ,     1, l_open,    p_hello,    0,    30,   0,       $01, 0,     0,     0, 0,   0
        STEP K_REQ,     1, l_open5,   p_hello,    0,    2,    0,       $01, 0,     0,     0, 0,   0
.endif
.if RUN = 2
        ; Net (--net): URL A = the echo server, URL B = a closed port
        STEP K_REQ,     1, l_open,    PA,         0,    0,    HF_H1,   $01, 0,     0,     0, 0,   0
        STEP K_REQ,     1, l_write,   0,          0,    0,    0,       $04, 6,     w_hello, 0, H1, 0
        STEP K_WAITNET, 0, l_event,   0,          0,    0,    0,       0,   0,     0,     0, 0,   0
        STEP K_READN,   1, l_readn,   0,          0,    0,    0,       $03, 256,   DATA,  0, H1,  6
        STEP K_REQ,     1, l_readnone,0,          0,    0,    0,       $03, 256,   DATA,  0, H1,  0
        STEP K_REQ,     1, l_stat,    PA,         0,    0,    0,       $06, 0,     0,     0, 0,   0
        STEP K_REQ,     1, l_seek,    0,          0,    0,    0,       $05, 0,     0,     0, H1,  0
        STEP K_REQ,     1, l_refused, PB,         0,    0,    0,       $01, 0,     0,     0, 0,   0
        STEP K_REQ,     1, l_tls,     p_tlsa,     0,    0,    0,       $01, 0,     0,     0, 0,   0
        STEP K_REQ,     1, l_fetch,   p_hello,    0,    0,    0,       $01, 0,     0,     0, 0,   0
        STEP K_REQ,     1, l_noport,  p_noport,   0,    0,    0,       $01, 0,     0,     0, 0,   0
        STEP K_REQ,     1, l_write,   0,          0,    0,    0,       $04, 5,     w_quit, 0, H1,  0
        STEP K_DRAIN,   1, l_drain,   0,          0,    0,    0,       $03, 256,   DATA,  0, H1,  0
        STEP K_REQ,     1, l_write,   0,          0,    0,    0,       $04, 5,     w_quit, 0, H1,  0
        STEP K_REQ,     1, l_close,   0,          0,    0,    0,       $02, 0,     0,     0, H1,  0
        STEP K_REQ,     1, l_pc,      p_pc,       0,    0,    0,       $06, 0,     0,     0, 0,   0
.endif
.if RUN = 3
        ; a drop (--pc-drop-at 1.5) with a connection and a slow Fetch READ (1 KB/s) open
        STEP K_REQ,     1, l_open,    PA,         0,    0,    HF_H1,   $01, 0,     0,     0, 0,   0
        STEP K_REQ,     1, l_openbig, p_big,      22,   26,   HF_H2,   $01, 0,     0,     0, 0,   0
        STEP K_SEND,    2, l_none,    0,          0,    0,    0,       $03, $2000, DATA,  0, H2,  0
        STEP K_REQ,     1, l_write,   0,          0,    0,    0,       $04, 5,     w_ping, 0, H1,  0
        STEP K_WAITNET, 0, l_event,   0,          0,    0,    0,       0,   0,     0,     0, 0,   0
        STEP K_READN,   1, l_readn,   0,          0,    0,    0,       $03, 256,   DATA,  0, H1,  5
        STEP K_WAITNET, 0, l_drop,    0,          0,    0,    0,       0,   0,     0,     0, 0,   0
        STEP K_WAITTAG, 2, l_bigread, 0,          5300, 5870, 0,       0,   0,     0,     0, 0,   0
        STEP K_REQ,     1, l_readcl,  0,          0,    0,    0,       $03, 10,    DATA,  0, H1,  0
        STEP K_REQ,     1, l_write,   0,          0,    0,    0,       $04, 5,     w_ping, 0, H1,  0
        STEP K_REQ,     1, l_seek,    0,          0,    0,    0,       $05, 0,     0,     0, H1,  0
        STEP K_REQ,     1, l_close,   0,          0,    0,    0,       $02, 0,     0,     0, H1,  0
        STEP K_REQ,     1, l_close,   0,          0,    0,    0,       $02, 0,     0,     0, H2,  0
        STEP K_REQ,     1, l_open,    PA,         0,    2,    0,       $01, 0,     0,     0, 0,   0
        STEP K_REQ,     1, l_stat,    p_hello,    0,    2,    0,       $06, 0,     0,     0, 0,   0
.endif
        .byte   K_END

p_hello:   .byte "http://example.test/hello.txt", 0
p_missing: .byte "http://example.test/missing.txt", 0
p_ftpmiss: .byte "ftp://anonymous@example.test:21/missing", 0
p_nohost:  .byte "https://nowhere.test/x", 0
p_dir:     .byte "HTTP://Example.Test/docs?sort=name#top", 0
p_ren:     .byte "/HELLO.TXT", 0, "http://example.test/x", 0
p_tcp:     .byte "tcp://127.0.0.1:1", 0
p_tls:     .byte "tls://127.0.0.1:1", 0
p_gopher:  .byte "gopher://example.test/", 0
p_pc:      .byte "/PC:/x", 0
p_big:     .byte "ftp://example.test/big.bin", 0
p_card:    .byte "/HELLO.TXT", 0
p_tlsa:    .byte "tls://127.0.0.1:7", 0
p_noport:  .byte "tcp://127.0.0.1", 0
w_hello:   .byte "hello", 10
w_quit:    .byte "quit", 10
w_ping:    .byte "ping", 10
l_none:    .byte 0
l_stat:    .byte "STAT", 0
l_open:    .byte "OPEN", 0
l_readall: .byte "READALL", 0
l_readend: .byte "READEND", 0
l_write:   .byte "WRITE", 0
l_seek:    .byte "SEEK", 0
l_close:   .byte "CLOSE", 0
l_readcl:  .byte "READ", 0
l_404:     .byte "STAT404", 0
l_ftp404:  .byte "OPENFTP404", 0
l_nohost:  .byte "STATNOHOST", 0
l_mode2:   .byte "OPENMODE2", 0
l_opendir: .byte "OPENDIR", 0
l_mkdir:   .byte "MKDIR", 0
l_rename:  .byte "RENAME", 0
l_readdir: .byte "READDIR", 0
l_load:    .byte "LOAD", 0
l_tcp:     .byte "OPENTCP", 0
l_tls:     .byte "OPENTLS", 0
l_scheme:  .byte "OPENGOPHER", 0
l_pc:      .byte "STATPC", 0
l_openbig: .byte "OPENBIG", 0
l_card:    .byte "STATCARD", 0
l_bigread: .byte "READBIG", 0
l_open5:   .byte "OPEN5TH", 0
l_event:   .byte "ECHO", 0
l_readn:   .byte "READN", 0
l_readnone:.byte "READNONE", 0
l_refused: .byte "OPENREFUSED", 0
l_fetch:   .byte "OPENHTTP", 0
l_noport:  .byte "OPENNOPORT", 0
l_drain:   .byte "DRAIN", 0
l_drop:    .byte "DROP", 0
m_hello:   .byte "NETTEST", 10, 0
m_net:     .byte " NET ", 0
m_t:       .byte " T ", 0
m_ok:      .byte "OK", 0
m_done:    .byte "DONE", 10, 0
msg:       .res 16
rsp:       .res 16
answers:   .res 128
got:       .res 8
