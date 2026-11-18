; FETCH - print a web page (or any URL) on the console. Horizon 0.22 (Atari816).
;
;   > fetch http://example.com/
;   <!doctype html>
;   ...
;   fetch: 1256 bytes
;
; Shows: a URL is a path. http://, https:// and ftp:// open as read-only files with the
; normal calls: open (mode 0), read until a short read (the end), close. The PC link's
; gateway (tools/atari816-link) fetches the URL on the PC. Every error has its own message;
; for an HTTP error (E_HTTP) open returns the status (404, ...) in X.
;
; A local file path works too ("fetch /docs/README.TXT"): it is the same call.
; Build: make; test in the emulator: make test (URLs served from a folder: --net-root).

        .include "horizon.inc"

        .segment "CODE"
        .a16
        .i16

URLMAX  = 127                           ; Horizon's path limit (the scheme counts)
BUFLEN  = 512

start:  sta     z:alen
        jsr     args_init               ; ulib's u_p points at the argument string

        ptr     url
        lda     #URLMAX + 3             ; room to see that it is too long
        jsr     next_arg                ; -> A = length; C set when there is none
        bcc     :+
        print   "usage: fetch URL   (http://, https://, ftp://)\n"
        exit    2
:       cmp     #URLMAX + 1
        bcc     :+
        print   "fetch: the URL is too long (127 characters at most)\n"
        exit    1

; ---- open: waits until the server has answered (or failed)
:       ptr     url
        lda     #O_READ                 ; URLs are read-only: mode 0
        sys     SYS_OPEN                ; -> A = handle 4-7; C set: A = error, X = HTTP status
        bcc     :+
        stx     z:status                ; (only meaningful for E_HTTP)
        jsr     show_err
        exit    1
:       sta     z:fh
        stz     z:cnt
        stz     z:cnt+2
        lda     #10
        sta     z:last                  ; "the last character printed was a new line"

; ---- read in pieces of BUFLEN bytes; fewer bytes than asked = the end
        lda     z:fh
        sta     iob                     ; {u8 handle, u24 buffer, u16 length}
        lda     #.loword(buf)           ; (the high byte of the handle lands in iob+1 and
        sta     iob+1                   ;  is overwritten here)
        sep     #$20
        .a8
        lda     #^buf
        sta     iob+3
        rep     #$20
        .a16
        lda     #BUFLEN
        sta     iob+4
@rd:    ptr     iob
        sys     SYS_READ                ; waits until BUFLEN bytes came or the page ended
        bcc     :+
        stz     z:status
        jsr     show_err                ; the link was lost, a timeout, ...
        lda     z:fh
        sys     SYS_CLOSE
        exit    1
:       sta     z:n
        clc                             ; count the bytes (32 bits)
        adc     z:cnt
        sta     z:cnt
        bcc     :+
        inc     z:cnt+2
:       jsr     show_buf
        lda     z:n
        cmp     #BUFLEN
        beq     @rd                     ; a full piece: there may be more

        lda     z:fh
        sys     SYS_CLOSE
        lda     z:last
        cmp     #10
        beq     :+
        jsr     put_nl                  ; the page did not end with a new line
:       print   "fetch: "
        jsr     put_dec32
        print   " bytes\n"
        exit    0

; Print the z:n bytes in buf. CR and NUL bytes are left out (puts ends at a NUL; the
; console moves to a new line on LF).
show_buf:
        stz     z:i
@l:     lda     z:i
        cmp     z:n
        bcs     @done
        tax
        lda     buf,x
        and     #$00FF
        inc     z:i
        cmp     #13
        beq     @l
        cmp     #0
        beq     @l
        sta     z:last
        jsr     out_char                ; buffered; sent at each LF (or when the buffer is full)
        bra     @l
@done:  rts

; Print "fetch: " and the message for the error in A (z:status: the HTTP status).
show_err:
        sta     z:err
        print   "fetch: "
        lda     z:err
        cmp     #E_HTTP
        bne     @find
        print   "HTTP status "          ; 404 not found, 403 forbidden, 500 server error ...
        lda     z:status
        jsr     put_dec
        jmp     put_nl
@find:  ldx     #0
@l:     lda     errtab,x
        beq     @unknown                ; the table ends with 0
        cmp     z:err
        beq     @found
        inx
        inx
        inx
        inx
        bra     @l
@found: lda     errtab+2,x              ; the message's address (in this bank)
        tax
        ldy     #^errtab
        jsr     out_str
        jmp     put_nl
@unknown:
        print   "error $"
        lda     z:err
        jsr     put_hex8
        jmp     put_nl

; z:cnt (32 bits) in decimal. Divides by 10 until the quotient is 0; the digits go on
; the stack and come off in the right order.
put_dec32:
        lda     z:cnt
        sta     z:q
        lda     z:cnt+2
        sta     z:t
        stz     z:i                     ; digits on the stack
@div:   lda     #0                      ; remainder
        ldx     #32
@bit:   asl     z:q                     ; the dividend t:q shifts through the remainder
        rol     z:t
        rol     a
        cmp     #10
        bcc     :+
        sbc     #10                     ; (C is set here)
        inc     z:q                     ; a quotient bit
:       dex
        bne     @bit
        pha
        inc     z:i
        lda     z:q
        ora     z:t
        bne     @div
@out:   pla
        clc
        adc     #'0'
        jsr     out_char
        dec     z:i
        bne     @out
        rts

        .segment "RODATA"
; {u16 error code, u16 message} pairs. The E_* names are in horizon.inc.
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
        .word   EIO + 4,   m_nofile     ; $44, $45: a local path that is not there
        .word   EIO + 5,   m_nofile
        .word   EIO + 6,   m_badname    ; $46: an older firmware does not know URLs
        .word   EIO + 7,   m_denied     ; $47
        .word   EINVAL,    m_inval
        .word   0
m_nolink:  .byte "no PC link: start the gateway (tools/atari816-link) on the PC", 0
m_lost:    .byte "the PC link was lost", 0
m_nosvc:   .byte "no internet service: the gateway is older, or was started with --no-net", 0
m_badaddr: .byte "bad address (check the URL)", 0
m_noname:  .byte "name not found (no such host)", 0
m_refused: .byte "refused or unreachable", 0
m_timeout: .byte "timeout: the server did not answer", 0
m_closed:  .byte "the connection was closed", 0
m_tls:     .byte "TLS failed (a bad certificate?)", 0
m_pcbusy:  .byte "too many connections on the PC", 0
m_net:     .byte "network error", 0
m_nstream: .byte "all four internet handles are in use", 0
m_nofile:  .byte "no such file", 0
m_badname: .byte "bad name (a firmware without the internet?)", 0
m_denied:  .byte "denied", 0
m_inval:   .byte "bad path (127 characters at most)", 0

        .segment "BSS"
url:    .res    URLMAX + 4
buf:    .res    BUFLEN
iob:    .res    6

        .segment "ZEROPAGE"
alen:   .res    2
fh:     .res    2
n:      .res    2
i:      .res    2
cnt:    .res    4
q:      .res    2
t:      .res    2
err:    .res    2
status: .res    2
last:   .res    2
