; BBS - a terminal for bulletin board systems over telnet (/BIN/BBS.PRG, 0.22). The PC link
; makes the TCP connection (tcp://host:port: ABI.md, "The internet"); this program is the
; screen, the keyboard and a minimal telnet.
;   Two display modes (the Mode menu): ATASCII, 40 x 24 cells of 16 x 16 pixels (an 8x8 font
;   drawn twice as large: the Atari character set with its graphics characters, bit 7 =
;   inverse video; the screen editor's control codes: cursor moves $1C-$1F, clear $7D,
;   backspace $7E, tab $7F, EOL $9B, delete / insert line $9C / $9D, bell $FD, delete /
;   insert character $FE / $FF, ESC = show the next code as a character) and ASCII, 80 x 24
;   cells of 8 x 16 (Horizon's 8x12 console font): CR, LF, BS, TAB, BEL, VT52 (ESC A B C D H J
;   K E, ESC Y row column) and a small ANSI subset (ESC [ row ; col H or f, A B C D, J, K, m
;   with 0 1 7 22 27, s u; other sequences are read and ignored).
;   Keys: ATASCII mode Return $9B, Backspace $7E, Tab $7F, Delete $FE, the arrows $1C-$1F,
;   Esc $1B, ctrl + letter $01-$1A; ASCII mode Return CR NUL (telnet's plain carriage return),
;   Backspace $08, Delete $7F, the arrows ESC [ A-D.
;   Telnet (RFC 854): IAC IAC is a data byte 255 (and 255 is sent doubled); options are
;   refused (DO -> WONT, WILL -> DONT), except TERMINAL-TYPE (24), answered "ATASCII" or
;   "ANSI" by the mode, and the server's ECHO (1) and SUPPRESS-GO-AHEAD (3), which a
;   character-at-a-time terminal needs; a request that changes nothing gets no answer (no
;   loops). Sub-negotiations other than TERMINAL-TYPE SEND are ignored.
;   The Connection menu: Connect... (host, host:port, telnet://host[:port] or
;   tcp://host:port; port 23 by default), Disconnect, the address book, Close. The address
;   book is /SYSTEM/BBS.TXT: one "Name=host[:port]" per line, '#' starts a comment.
;   Waiting: win_event (WE_NET wakes it when bytes come; a timer every 0.5 s while connected,
;   every 50 ms while bytes wait to be sent); reads never wait. A remote close, a lost PC link
;   or a failed connection is said on the screen ("*** ..."). An argument "[-ascii] host[:port]"
;   (or the name of an address book entry, which is then shown instead of its address)
;   connects at once.
;   Not yet: file transfers, capture to a file, colours, scroll-back.
        .include "horizon.inc"
        .include "ui.inc"

NROW    = 24                            ; the content: ATASCII 40 x 24 cells of 8 x 8 (320 x
STRIDE  = 80                            ; 192), ASCII 80 x 24 of 7 x 12 (560 x 288); cells
                                        ; per row in chars / attrs
NCELL   = NROW * STRIDE
NBOOK   = 12                            ; address book entries
NAMEMAX = 31
HOSTMAX = 100
IBUFSZ  = 512
OBUFSZ  = 256
FBUFSZ  = 2048
A_INV   = 1                             ; attrs (ASCII mode)
A_BOLD  = 2
IAC     = 255
T_SB    = 250
T_SE    = 240
T_WILL  = 251
T_WONT  = 252
T_DO    = 253
T_DONT  = 254
O_ECHO  = 1
O_SGA   = 3
O_TTYPE = 24
A_PAPER = 16 + 0 * 36 + 1 * 6 + 3       ; the colours: ATASCII blue,
A_INK   = 16 + 3 * 36 + 4 * 6 + 5
S_PAPER = C_BLACK                       ; ASCII grey on black
S_INK   = 250

        .segment "CODE"
        .a16
        .i16
start:  sta     argl
        stx     argx
        sys     SYS_WSSTART
        bcc     :+
        print   "bbs: no window system\n"
        exit    1
:       sta     wsown
        jsr     ui_init
        ptr     wblk
        sys     SYS_WOPEN
        bcc     :+
        jsr     stopws
        print   "bbs: no window\n"
        exit    1
:       sta     win
        lda     #$FFFF
        sta     hnd
        sta     curdy
        stz     mode
        stz     tper
        jsr     loadbook
        jsr     setmenu
        stz     hostbuf
        lda     argl                    ; [-ascii] host[:port]
        beq     @noarg
        ldx     argx
        jsr     args_init
        ldx     #.loword(hostbuf)
        ldy     #^hostbuf
        lda     #HOSTMAX + 1
        jsr     next_arg
        ldx     #.loword(w_ascii)
        jsr     hosteq
        bne     @one
        lda     #1
        sta     mode
        ldx     #.loword(hostbuf)
        ldy     #^hostbuf
        lda     #HOSTMAX + 1
        jsr     next_arg
@one:   jsr     findbook                ; a name of the address book: its address
@noarg: jsr     setmenu
        lda     mode
        beq     :+
        jsr     wsize
:       jsr     clrscr
        ldx     #.loword(m_hello)
        jsr     lmsg
        ldx     #.loword(m_hello2)
        jsr     lmsg
        jsr     render
        lda     hostbuf
        and     #$00FF
        beq     loop
        jsr     connect

loop:   jsr     render
        jsr     settimer
        lda     #0
        jsr     ui_getev
        bcs     loop
        lda     ui_ev
        and     #$00FF
        cmp     #WE_KEY
        bne     :+
        jsr     onkey
        bra     loop
:       cmp     #WE_NET
        bne     :+
        jsr     pump
        bra     loop
:       cmp     #WE_TICK
        bne     :+
        jsr     flushout
        jsr     pump
        bra     loop
:       cmp     #WE_MENU
        bne     :+
        jsr     onmenu
        bra     loop
:       cmp     #WE_CLOSE
        bne     loop
quit:   jsr     hangup
        lda     win
        sys     SYS_WCLOSE
        jsr     stopws
        exit    0

stopws: lda     wsown
        beq     :+
        sys     SYS_WSSTOP
:       rts

; the timer: 50 ms while bytes wait to be sent or to be read, 0.5 s while connected, else off
settimer:
        ldx     #0
        lda     hnd
        bmi     :+
        ldx     #50
        lda     olen
        ora     more
        beq     :+
        ldx     #5
:       cpx     tper
        beq     :+
        stx     tper
        lda     win
        sys     SYS_WTIMER
:       rts

; X = word (lower case): Z set if hostbuf is it
hosteq: ldy     #0
:       lda     a:0,x
        and     #$00FF
        sta     tmp
        lda     hostbuf,y
        and     #$00FF
        cmp     tmp
        bne     :+
        cmp     #0
        beq     :+
        inx
        iny
        bra     :-
:       rts

; ---------------------------------------------------------------- menus
; Connection: Connect..., Disconnect, -, the address book, -, Close; Mode: ATASCII, ASCII, -,
; Clear screen
setmenu:
        ldy     #0
        ldx     #.loword(mn_conn)
        jsr     mput
        ldx     #.loword(mi_connect)
        jsr     mput
        lda     #MS_STATE | MS_DIM      ; Disconnect: dimmed when not connected
        ldx     hnd
        bmi     :+
        lda     #MS_STATE
:       jsr     mbyte
        ldx     #.loword(mi_disc)
        jsr     mput
        ldx     #.loword(mi_sep)
        jsr     mput
        lda     nbook
        bne     :+
        ldx     #.loword(mi_nobook)
        jsr     mput
        bra     @close
:       stz     tmp
:       lda     tmp
        cmp     nbook
        bcs     @close
        jsr     bookent
        jsr     mput
        inc     tmp
        bra     :-
@close: ldx     #.loword(mi_sep)
        jsr     mput
        ldx     #.loword(mi_close)
        jsr     mput
        lda     #0                      ; (the menu's end)
        jsr     mbyte
        ldx     #.loword(mn_mode)
        jsr     mput
        lda     #MS_STATE | MS_CHECK
        ldx     mode
        beq     :+
        lda     #MS_STATE
:       jsr     mbyte
        ldx     #.loword(mi_atascii)
        jsr     mput
        lda     #MS_STATE
        ldx     mode
        beq     :+
        lda     #MS_STATE | MS_CHECK
:       jsr     mbyte
        ldx     #.loword(mi_ascii)
        jsr     mput
        ldx     #.loword(mi_sep)
        jsr     mput
        ldx     #.loword(mi_clear)
        jsr     mput
        lda     #0
        jsr     mbyte
        lda     #0
        jsr     mbyte
        lda     win
        ptr     menus
        sys     SYS_WMENU
        rts
; Y = position in menus: the string X appended with its 0 (the 0 makes the item's end)
mput:   lda     a:0,x
        and     #$00FF
        jsr     mbyte
        inx
        cmp     #0
        bne     mput
        rts
mbyte:  sep     #$20
        .a8
        sta     menus,y
        rep     #$20
        .a16
        iny
        rts

; A = address book entry -> X = its name (A, Y kept)
bookent:
        pha
        xba                             ; * 128
        lsr     a
        clc
        adc     #.loword(book)
        tax
        pla
        rts

onmenu: lda     ui_ev+2
        bne     @mode
        lda     ui_ev+4                 ; Connection
        bne     :+
        jmp     askconn
:       cmp     #1
        bne     :+
        jsr     hangup
        ldx     #.loword(m_bye)
        jmp     lmsg
:       sec
        sbc     #3                      ; an entry of the book?
        bcc     @out
        cmp     nbook
        bcs     :+
        jsr     bookent                 ; its address: after the name (64 bytes in)
        stx     bookname
        txa
        clc
        adc     #64
        tax
        ldy     #.loword(hostbuf)
        jsr     ui_strcpy
        jmp     connect
:       pla                             ; Close
        jmp     quit
@mode:  lda     ui_ev+4
        cmp     #2
        bcs     :+
        cmp     mode
        beq     @out
        sta     mode
        jsr     setmenu
        jsr     wsize
        jsr     clrscr
        ldx     #.loword(m_atascii)
        lda     mode
        beq     @say
        ldx     #.loword(m_ascii)
@say:   jmp     lmsg
:       cmp     #3                      ; Clear screen
        bne     @out
        jmp     clrscr
@out:   rts

; ---------------------------------------------------------------- the address book
; /SYSTEM/BBS.TXT: "Name=host[:port]" lines ('#': a comment) -> book (NBOOK entries of 128
; bytes: the name at 0, the address at 64), nbook
loadbook:
        stz     nbook
        ptr     p_book
        lda     #O_READ
        sys     SYS_OPEN
        bcc     :+
        rts
:       sta     rwb
        lda     #.loword(fbuf)
        sta     rwb+1
        sep     #$20
        .a8
        lda     #^fbuf
        sta     rwb+3
        rep     #$20
        .a16
        lda     #FBUFSZ - 1
        sta     rwb+4
        ptr     rwb
        sys     SYS_READ
        bcc     :+
        lda     #0
:       tax
        sep     #$20
        .a8
        stz     fbuf,x
        rep     #$20
        .a16
        lda     rwb
        and     #$00FF
        sys     SYS_CLOSE
        ldx     #0                      ; X: the next line
@line:  lda     nbook
        cmp     #NBOOK
        jcs     @out
        jsr     @skipsp
        lda     fbuf,x
        and     #$00FF
        jeq     @out
        cmp     #'#'
        jeq     @skip
        cmp     #' '                    ; (an empty line)
        jcc     @skip
        stx     lstart                  ; its end, its '='
        lda     #$FFFF
        sta     leq
:       lda     fbuf,x
        and     #$00FF
        beq     :+
        cmp     #10
        beq     :+
        cmp     #'='
        bne     @ne
        ldy     leq
        bpl     @ne
        stx     leq
@ne:    inx
        bra     :-
:       stx     lend
        lda     leq                     ; the name: up to '=' (no '=': the whole line)
        bpl     :+
        lda     lend
:       sta     fend
        lda     nbook
        jsr     bookent
        txy
        ldx     lstart
        lda     #NAMEMAX
        sta     tmp3
        jsr     cpfield
        lda     nbook                   ; the address: after '=' (or the whole line)
        jsr     bookent
        txa
        clc
        adc     #64
        tay
        ldx     leq
        bpl     :+
        ldx     lstart
        dex
:       inx
        lda     lend
        sta     fend
        lda     #63
        sta     tmp3
        jsr     cpfield
        lda     nbook                   ; kept if it has an address (no name: the address)
        jsr     bookent
        lda     a:64,x
        and     #$00FF
        beq     @next
        lda     a:0,x
        and     #$00FF
        bne     :+
        txa
        tay
        clc
        adc     #64
        tax
        lda     fend                    ; (cpfield from the address, NAMEMAX at most)
        lda     #NAMEMAX
        sta     tmp3
        jsr     @cpname
:       inc     nbook
@next:  ldx     lend
@skip:  lda     fbuf,x                  ; to the next line
        and     #$00FF
        beq     @out
        inx
        cmp     #10
        bne     @skip
        jmp     @line
@out:   rts
@cpname:                                ; X -> Y, tmp3 characters at most
        lda     a:0,x
        and     #$00FF
        beq     :+
        dec     tmp3
        bmi     :+
        sep     #$20
        .a8
        sta     a:0,y
        rep     #$20
        .a16
        inx
        iny
        bra     @cpname
:       sep     #$20
        .a8
        lda     #0
        sta     a:0,y
        rep     #$20
        .a16
        rts
@skipsp:
        lda     fbuf,x
        and     #$00FF
        cmp     #' '
        beq     :+
        cmp     #9
        bne     :++
:       inx
        bra     @skipsp
:       rts

; fbuf from X to fend, without the spaces around it, -> Y (tmp3 characters at most)
cpfield:
        sty     lastnb
:       cpx     fend                    ; leading spaces
        bcs     @e
        lda     fbuf,x
        and     #$00FF
        cmp     #' ' + 1
        bcs     @l
        inx
        bra     :-
@l:     cpx     fend
        bcs     @e
        lda     tmp3
        beq     @e
        lda     fbuf,x
        and     #$00FF
        sep     #$20
        .a8
        sta     a:0,y
        rep     #$20
        .a16
        iny
        inx
        dec     tmp3
        cmp     #' ' + 1
        bcc     @l
        sty     lastnb
        bra     @l
@e:     ldy     lastnb
        sep     #$20
        .a8
        lda     #0
        sta     a:0,y
        rep     #$20
        .a16
        rts

; hostbuf the name of an entry (ignoring case): hostbuf = its address, bookname = the entry
findbook:
        stz     bookname
        stz     tmp2
@e:     lda     tmp2
        cmp     nbook
        bcs     @out
        jsr     bookent
        stx     tmp3
        ldy     #0
:       lda     a:0,x
        jsr     @low
        sta     tmp
        lda     hostbuf,y
        jsr     @low
        cmp     tmp
        bne     @n
        cmp     #0
        beq     @yes
        inx
        iny
        bra     :-
@n:     inc     tmp2
        bra     @e
@yes:   lda     tmp3
        sta     bookname
        clc
        adc     #64
        tax
        ldy     #.loword(hostbuf)
        jmp     ui_strcpy
@out:   rts
@low:   and     #$00FF
        cmp     #'A'
        bcc     :+
        cmp     #'Z' + 1
        bcs     :+
        ora     #$20
:       rts

; ---------------------------------------------------------------- connecting
askconn:
        stz     bookname
        ldx     #.loword(ak_conn)
        jsr     ui_ask
        bcc     connect
        rts

; hostbuf (host, host:port, telnet://host[:port], tcp://host:port) -> the connection
connect:
        jsr     parsehost
        bcc     :+
        ldx     #.loword(m_badhost)
        jmp     lmsg
:       lda     bookname                ; (from the address book: its name is shown)
        beq     :+
        tax
        ldy     #.loword(dispbuf)
        jsr     ui_strcpy
:       jsr     hangup
        ldx     #.loword(m_conn1)       ; "Connecting to host:port..."
        ldy     #.loword(msgbuf)
        jsr     ui_strcpy
        ldx     #.loword(dispbuf)
        jsr     msgapp
        ldx     #.loword(m_dots)
        jsr     msgapp
        ldx     #.loword(msgbuf)
        jsr     lmsg
        jsr     render
        sys     SYS_WSSYNC              ; (shown before the wait)
        ptr     pathbuf
        lda     #O_READ
        sys     SYS_OPEN
        bcc     @ok
        jsr     neterr                  ; "Cannot connect: ..."
        ldx     #.loword(m_cannot)
        ldy     #.loword(msgbuf)
        jsr     ui_strcpy
        ldx     z:sx
        jsr     msgapp
        ldx     #.loword(msgbuf)
        jmp     lmsg
@ok:    sta     hnd
        stz     tstate
        stz     o_ttype
        stz     o_echo
        stz     o_sga
        stz     olen
        stz     more
        stz     estate
        jsr     setmenu
        ldx     #.loword(t_title2)      ; the title: "BBS - host:port"
        ldy     #.loword(msgbuf)
        jsr     ui_strcpy
        ldx     #.loword(dispbuf)
        jsr     msgapp
        lda     win
        ptr     msgbuf
        sys     SYS_WTITLE
        ldx     #.loword(m_conn2)       ; "Connected."
        jsr     lmsg
        jmp     pump                    ; (a first READ: the $E4 events come after it)

; hostbuf -> pathbuf "tcp://host:port", dispbuf "host:port". C set: not an address
parsehost:
        ldx     #0                      ; leading spaces, a scheme
:       lda     hostbuf,x
        and     #$00FF
        cmp     #' '
        bne     :+
        inx
        bra     :-
:       txy
        ldx     #.loword(w_telnet)
        jsr     prefix
        bcs     :+
        ldx     #.loword(w_tcp)
        jsr     prefix
:       sty     z:sx                    ; the host: up to ':', '/', ' ' or the end
        ldx     #0
@h:     lda     hostbuf,y
        and     #$00FF
        beq     @hend
        cmp     #':'
        beq     @hend
        cmp     #'/'
        beq     @hend
        cmp     #' '
        beq     @hend
        sep     #$20
        .a8
        sta     dispbuf,x
        rep     #$20
        .a16
        inx
        iny
        cpx     #HOSTMAX
        bcc     @h
        sec
        rts
@hend:  cpx     #0
        bne     :+
        sec
        rts
:       stx     z:sy                    ; the host's length
        lda     #23                     ; the port
        sta     port
        lda     hostbuf,y
        and     #$00FF
        cmp     #':'
        bne     @pdone
        iny
        stz     port
        stz     tmp                     ; digits seen
@p:     lda     hostbuf,y
        and     #$00FF
        sec
        sbc     #'0'
        cmp     #10
        bcs     @pend
        sta     tmp2
        lda     port                    ; port * 10 + digit
        cmp     #6554
        bcs     @bad
        asl     a
        sta     tmp3
        asl     a
        asl     a
        clc
        adc     tmp3
        clc
        adc     tmp2
        bcs     @bad
        sta     port
        inc     tmp
        iny
        bra     @p
@pend:  lda     tmp
        beq     @bad
        lda     port
        beq     @bad
@pdone: lda     hostbuf,y               ; then only a '/' or spaces
        and     #$00FF
        beq     @good
        cmp     #'/'
        beq     :+
        cmp     #' '
        bne     @bad
:       iny
        bra     @pdone
@bad:   sec
        rts
@good:  ldx     z:sy                    ; dispbuf: host ":" port
        lda     #':'
        jsr     @dput
        lda     port
        jsr     @dec
        lda     #0
        jsr     @dput
        ldx     #.loword(w_tcpu)        ; pathbuf: "tcp://" + dispbuf
        ldy     #.loword(pathbuf)
        jsr     ui_strcpy
        clc
        adc     #.loword(pathbuf)
        tay
        ldx     #.loword(dispbuf)
        jsr     ui_strcpy
        clc
        rts
@dput:  sep     #$20
        .a8
        sta     dispbuf,x
        rep     #$20
        .a16
        inx
        rts
@dec:   stz     tmp                     ; A (1-65535) in decimal at X
        ldy     #0
@d:     stz     tmp2
:       cmp     pow,y
        bcc     :+
        sbc     pow,y
        inc     tmp2
        bra     :-
:       pha
        lda     tmp2
        ora     tmp
        beq     :+
        sta     tmp
        lda     tmp2
        clc
        adc     #'0'
        jsr     @dput
:       pla
        iny
        iny
        cpy     #10
        bcc     @d
        rts

; X = a lower-case word: if hostbuf from Y starts with it (ignoring case), Y after it and C
; set; else C clear, Y kept
prefix: phy
:       lda     a:0,x
        and     #$00FF
        beq     @yes
        sta     tmp
        lda     hostbuf,y
        and     #$00FF
        cmp     #'A'
        bcc     :+
        cmp     #'Z' + 1
        bcs     :+
        ora     #$20
:       cmp     tmp
        bne     @no
        inx
        iny
        bra     :--
@yes:   pla
        sec
        rts
@no:    ply
        clc
        rts

; the connection closed (if open)
hangup: lda     hnd
        bmi     :+
        sys     SYS_CLOSE
        lda     #$FFFF
        sta     hnd
        stz     olen
        stz     more
        jsr     setmenu
        lda     win
        ptr     t_title
        sys     SYS_WTITLE
:       rts

; A = an error -> z:sx = its sentence
neterr: ldx     #0
:       ldy     errtab,x
        beq     :+
        cmp     errtab,x
        beq     :++
        inx
        inx
        inx
        inx
        bra     :-
:       ldy     #.loword(m_eunknown)
        sty     z:sx
        rts
:       ldy     errtab+2,x
        sty     z:sx
        rts

; ---------------------------------------------------------------- the connection
; read what came (never waits), through telnet to the screen; the answers sent
pump:   lda     hnd
        bpl     :+
        rts
:       stz     more
        lda     #8                      ; batches, at most (the timer brings the rest)
        sta     batch
@rd:    lda     hnd
        sta     rwb
        lda     #.loword(ibuf)
        sta     rwb+1
        sep     #$20
        .a8
        lda     #^ibuf
        sta     rwb+3
        rep     #$20
        .a16
        lda     #IBUFSZ
        sta     rwb+4
        ptr     rwb
        sys     SYS_READ
        bcs     @err
        cmp     #0
        beq     @done
        sta     ilen
        stz     ipos
:       ldx     ipos
        lda     ibuf,x
        and     #$00FF
        jsr     telnet
        inc     ipos
        lda     ipos
        cmp     ilen
        bcc     :-
        dec     batch
        bne     @rd
        lda     #1
        sta     more
@done:  jmp     flushout
@err:   pha
        jsr     hangup
        pla
        cmp     #E_CLOSED
        bne     :+
        ldx     #.loword(m_closed)
        jmp     lmsg
:       cmp     #E_LOST
        bne     :+
        ldx     #.loword(m_lost)
        jmp     lmsg
:       jsr     neterr
        ldx     #.loword(m_ended)
        ldy     #.loword(msgbuf)
        jsr     ui_strcpy
        ldx     z:sx
        jsr     msgapp
        ldx     #.loword(msgbuf)
        jmp     lmsg

; the bytes waiting in obuf sent (as many as the PC takes now)
flushout:
        lda     olen
        beq     @out
        lda     hnd
        bmi     @drop
        sta     rwb
        lda     #.loword(obuf)
        sta     rwb+1
        sep     #$20
        .a8
        lda     #^obuf
        sta     rwb+3
        rep     #$20
        .a16
        lda     olen
        sta     rwb+4
        ptr     rwb
        sys     SYS_WRITE
        bcs     @out                    ; (the next READ tells what happened)
        sta     tmp
        cmp     olen
        bcs     @drop
        ldx     tmp                     ; the rest to the front
        ldy     #0
:       lda     obuf,x
        sep     #$20
        .a8
        sta     obuf,y
        rep     #$20
        .a16
        inx
        iny
        cpx     olen
        bcc     :-
        sty     olen
@out:   rts
@drop:  stz     olen
        rts

; A = a byte for the remote (255 doubled: telnet)
senddata:
        and     #$00FF
        cmp     #IAC
        bne     sendraw
        jsr     sendraw
        lda     #IAC
; A = a byte for obuf as it is
sendraw:
        ldx     olen
        cpx     #OBUFSZ
        bcs     :+
        sep     #$20
        .a8
        sta     obuf,x
        rep     #$20
        .a16
        inc     olen
:       rts

; three bytes: IAC, A, X
sendcmd:
        phx
        pha
        lda     #IAC
        jsr     sendraw
        pla
        jsr     sendraw
        pla
        jmp     sendraw

; ---------------------------------------------------------------- telnet
; A = a byte from the remote
telnet: ldx     tstate
        jmp     (ttab,x)
t_data: cmp     #IAC
        beq     :+
        jmp     emit
:       lda     #2
        sta     tstate
        rts
t_iac:  stz     tstate
        cmp     #IAC                    ; IAC IAC: the byte 255
        bne     :+
        jmp     emit
:       cmp     #T_WILL
        bcc     :+
        sta     tcmd
        lda     #4
        sta     tstate
        rts
:       cmp     #T_SB
        bne     :+
        stz     sblen
        lda     #6
        sta     tstate
:       rts                             ; (NOP, GA, ... : nothing)
t_opt:  stz     tstate
        sta     topt
        lda     tcmd
        cmp     #T_DO
        beq     @do
        cmp     #T_DONT
        beq     @dont
        cmp     #T_WILL
        beq     @will
        lda     topt                    ; WONT: the server's ECHO / SGA off
        jsr     remopt
        bcs     @out
        lda     a:0,x
        beq     @out
        stz     a:0,x
        lda     #T_DONT
        bra     @send
@will:  lda     topt
        jsr     remopt
        bcc     :+
        lda     #T_DONT                 ; refused
        bra     @send
:       lda     a:0,x
        bne     @out                    ; (on already: no answer)
        inc     a:0,x
        lda     #T_DO
        bra     @send
@do:    lda     topt
        cmp     #O_TTYPE
        beq     :+
        lda     #T_WONT                 ; refused
        bra     @send
:       lda     o_ttype
        bne     @out
        inc     o_ttype
        lda     #T_WILL
        bra     @send
@dont:  lda     topt
        cmp     #O_TTYPE
        bne     @out
        lda     o_ttype
        beq     @out
        stz     o_ttype
        lda     #T_WONT
@send:  ldx     topt
        jmp     sendcmd
@out:   rts
; A = an option -> C clear and X = its flag if the server may have it (ECHO, SGA)
remopt: ldx     #.loword(o_echo)
        cmp     #O_ECHO
        beq     :+
        ldx     #.loword(o_sga)
        cmp     #O_SGA
        beq     :+
        sec
        rts
:       clc
        rts
t_sb:   cmp     #IAC
        bne     :+
        lda     #8
        sta     tstate
        rts
t_sbput:
:       ldx     sblen
        cpx     #16
        bcs     :+
        sep     #$20
        .a8
        sta     sbbuf,x
        rep     #$20
        .a16
        inc     sblen
:       rts
t_sbiac:
        ldx     #6
        stx     tstate
        cmp     #IAC                    ; IAC IAC inside: 255
        beq     t_sbput
        stz     tstate
        cmp     #T_SE
        bne     @out
        lda     sbbuf                   ; TERMINAL-TYPE SEND: IAC SB 24 IS name IAC SE
        and     #$00FF
        cmp     #O_TTYPE
        bne     @out
        lda     sbbuf+1
        and     #$00FF
        cmp     #1
        bne     @out
        lda     o_ttype
        beq     @out
        lda     #T_SB
        ldx     #O_TTYPE
        jsr     sendcmd
        lda     #0
        jsr     sendraw
        ldx     #.loword(w_ttatascii)
        lda     mode
        beq     :+
        ldx     #.loword(w_ttansi)
:       lda     a:0,x
        and     #$00FF
        beq     :+
        phx
        jsr     sendraw
        plx
        inx
        bra     :-
:       lda     #IAC
        jsr     sendraw
        lda     #T_SE
        jmp     sendraw
@out:   rts

; ---------------------------------------------------------------- the keyboard
onkey:  lda     ui_ev+4
        cmp     #$0100                  ; (a release: nothing)
        bcs     :+
        rts
:       ldx     ui_ev+4
        lda     ui_ev+2
        jsr     key_ascii
        cmp     #0
        bne     :+
        rts
:       ldx     hnd
        bpl     @conn
        cmp     #13                     ; not connected: Enter asks where to
        bne     :+
        jmp     askconn
:       rts
@conn:  ldx     mode
        bne     @ascii
        ldx     #0                      ; ATASCII: the keys that differ
:       ldy     akeys,x
        beq     :+
        cmp     akeys,x
        beq     @map
        inx
        inx
        inx
        inx
        bra     :-
:       cmp     #$80                    ; (other non-ASCII keys: nothing)
        bcs     @out
        bra     @one
@map:   lda     akeys+2,x
@one:   jsr     senddata
        jmp     flushout
@ascii: cmp     #13                     ; Return: CR NUL
        bne     :+
        jsr     sendraw
        lda     #0
        bra     @one
:       cmp     #KEY_DEL
        bne     :+
        lda     #$7F
        bra     @one
:       cmp     #KEY_RIGHT              ; the arrows: ESC [ A-D
        bcc     @one
        cmp     #KEY_UP + 1
        bcs     @out
        sec
        sbc     #KEY_RIGHT
        tax
        lda     arrows,x
        and     #$00FF
        pha
        lda     #27
        jsr     sendraw
        lda     #'['
        jsr     sendraw
        pla
        bra     @one
@out:   rts

; ---------------------------------------------------------------- the screen
; A = a byte to show (the mode's codes)
emit:   ldx     mode
        beq     :+
        jmp     emit_s
:       ldx     aesc                    ; ATASCII: after ESC, the code as a character
        beq     :+
        stz     aesc
        jmp     aput
:       ldx     #0
:       ldy     actl,x
        beq     aput
        cmp     actl,x
        beq     :+
        inx
        inx
        inx
        inx
        bra     :-
:       jmp     (actl+2,x)

; ATASCII: A shown at the cursor, which moves on (to the next line after column 39)
aput:   jsr     cellx
        sep     #$20
        .a8
        sta     chars,x
        rep     #$20
        .a16
        jsr     dirtyrow
        inc     cx
        lda     cx
        cmp     #40
        bcc     :+
        stz     cx
        jmp     down
:       rts
a_esc:  lda     #1
        sta     aesc
        rts
a_up:   lda     cy
        bne     :+
        lda     #NROW
:       dec     a
        sta     cy
        rts
a_down: lda     cy
        inc     a
        cmp     #NROW
        bcc     :+
        lda     #0
:       sta     cy
        rts
a_left: lda     cx
        bne     :+
        lda     #40
:       dec     a
        sta     cx
        rts
a_right:
        lda     cx
        inc     a
        cmp     #40
        bcc     :+
        lda     #0
:       sta     cx
        rts
a_bs:   lda     cx                      ; back one, the character there erased
        beq     :+
        dec     cx
        jsr     cellx
        sep     #$20
        .a8
        lda     #' '
        sta     chars,x
        rep     #$20
        .a16
        jsr     dirtyrow
:       rts
a_tab:  lda     cx                      ; the next multiple of 8
        ora     #7
        inc     a
        cmp     #40
        bcc     :+
        stz     cx
        jmp     down
:       sta     cx
        rts
a_eol:  stz     cx
        jmp     down
a_delln:
        lda     cy
        jmp     delline
a_insln:
        lda     cy
        jmp     insline
a_bell: jmp     bell
a_delch:
        jsr     cellx                   ; the rest of the line left by one
        lda     #39
        sec
        sbc     cx
        tay
        sep     #$20
        .a8
:       dey
        bmi     :+
        lda     chars+1,x
        sta     chars,x
        inx
        bra     :-
:       lda     #' '
        sta     chars,x
        rep     #$20
        .a16
        jmp     dirtyrow
a_insch:
        lda     cy                      ; the rest of the line right by one
        jsr     rowbase
        clc
        adc     #39
        tax
        lda     #39
        sec
        sbc     cx
        tay
        sep     #$20
        .a8
:       dey
        bmi     :+
        lda     chars-1,x
        sta     chars,x
        dex
        bra     :-
:       lda     #' '
        sta     chars,x
        rep     #$20
        .a16
        jmp     dirtyrow
a_nop:  rts

; ASCII: A through the escape-sequence state
emit_s: ldx     estate
        jmp     (etab,x)
e_norm: cmp     #' '
        bcc     @ctl
        cmp     #$7F
        bne     sput
        rts
@ctl:   cmp     #27
        bne     :+
        lda     #2
        sta     estate
        rts
:       cmp     #13
        bne     :+
        stz     cx
        rts
:       cmp     #10
        bcc     :+
        cmp     #13
        bcs     :+
        jmp     down                    ; LF, VT, FF
:       cmp     #8
        bne     :+
        jsr     cxfix
        lda     cx
        beq     @out
        dec     cx
        rts
:       cmp     #9
        bne     :+
        jsr     cxfix
        lda     cx
        ora     #7
        inc     a
        cmp     #80
        bcc     @tab
        lda     #79
@tab:   sta     cx
        rts
:       cmp     #7
        bne     @out
        jmp     bell
@out:   rts

; ASCII: A shown at the cursor with the attributes (a pending wrap first)
sput:   pha
        lda     cx
        cmp     #80
        bcc     :+
        stz     cx
        jsr     down
:       jsr     cellx
        pla
        sep     #$20
        .a8
        sta     chars,x
        lda     attr
        sta     attrs,x
        rep     #$20
        .a16
        jsr     dirtyrow
        inc     cx                      ; (80: the wrap waits for the next character)
        rts
; a pending wrap undone (the cursor on column 79; A kept)
cxfix:  pha
        lda     cx
        cmp     #80
        bcc     :+
        lda     #79
        sta     cx
:       pla
        rts

e_esc:  stz     estate                  ; after ESC
        cmp     #'['
        bne     :+
        stz     npar
        stz     par
        stz     par+2
        stz     pdig
        lda     #4
        sta     estate
        rts
:       cmp     #'Y'
        bne     :+
        lda     #6
        sta     estate
        rts
:       ldx     #1                      ; VT52 moves: one step
        stx     par
        jsr     cxfix
        cmp     #'A'
        jeq     c_up
        cmp     #'B'
        jeq     c_down
        cmp     #'C'
        jeq     c_right
        cmp     #'D'
        jeq     c_left
        cmp     #'H'
        bne     :+
        stz     cx
        stz     cy
        rts
:       cmp     #'J'
        bne     :+
        jmp     eos
:       cmp     #'K'
        bne     :+
        jmp     eol
:       cmp     #'E'
        beq     :+
        cmp     #'c'
        bne     :++
:       jmp     clrscr
:       cmp     #'7'
        bne     :+
        jmp     c_save
:       cmp     #'8'
        bne     :+
        jmp     c_rest
:       rts
e_y1:   sec                             ; ESC Y row
        sbc     #32
        sta     yrow
        lda     #8
        sta     estate
        rts
e_y2:   stz     estate                  ; ESC Y row column
        sec
        sbc     #32
        cmp     #80
        bcc     :+
        lda     #79
:       sta     cx
        lda     yrow
        cmp     #NROW
        bcc     :+
        lda     #NROW - 1
:       sta     cy
        rts
e_csi:  cmp     #'0'                    ; ESC [ parameters, then the command
        bcc     @nd
        cmp     #'9' + 1
        bcs     @nd
        sbc     #'0' - 1                ; (C clear: - '0')
        sta     tmp
        ldx     npar
        cpx     #8
        bcs     @out
        lda     par,x                   ; * 10 + digit (at most 9999)
        cmp     #1000
        bcs     @out
        asl     a
        sta     tmp2
        asl     a
        asl     a
        clc
        adc     tmp2
        adc     tmp
        sta     par,x
        lda     #1
        sta     pdig
@out:   rts
@nd:    cmp     #';'
        bne     :+
        lda     npar
        cmp     #14
        bcs     @out
        inc     npar
        inc     npar
        ldx     npar
        stz     par,x
        rts
:       cmp     #'@'                    ; (intermediate and private bytes: read, ignored)
        bcc     @out
        stz     estate
        cmp     #$7F
        bcs     @out
        jsr     cxfix
        ldx     #0                      ; the command
:       ldy     ctab,x
        beq     @out
        cmp     ctab,x
        beq     :+
        inx
        inx
        inx
        inx
        bra     :-
:       jmp     (ctab+2,x)
; CSI commands (par = the first parameter, par+2 the second, 0 = none)
c_up:   jsr     cnt
:       lda     cy
        beq     @o
        dec     cy
        dec     tmp
        bne     :-
@o:     rts
c_down: jsr     cnt
:       lda     cy
        cmp     #NROW - 1
        bcs     @o
        inc     cy
        dec     tmp
        bne     :-
@o:     rts
c_right:
        jsr     cnt
:       lda     cx
        cmp     #79
        bcs     @o
        inc     cx
        dec     tmp
        bne     :-
@o:     rts
c_left: jsr     cnt
:       lda     cx
        beq     @o
        dec     cx
        dec     tmp
        bne     :-
@o:     rts
cnt:    lda     par                     ; tmp = the count (at least 1)
        bne     :+
        inc     a
:       sta     tmp
        rts
c_pos:  lda     par                     ; row ; column (1-based; 0 = 1)
        beq     :+
        dec     a
:       cmp     #NROW
        bcc     :+
        lda     #NROW - 1
:       sta     cy
        lda     par+2
        beq     :+
        dec     a
:       cmp     #80
        bcc     :+
        lda     #79
:       sta     cx
        rts
c_ed:   lda     par                     ; J: 0 to the end, 1 from the start, 2 all
        bne     :+
        jmp     eos
:       cmp     #1
        bne     :+
        jmp     bos
:       jmp     clrall
c_el:   lda     par                     ; K: 0 to the end, 1 from the start, 2 the line
        bne     :+
        jmp     eol
:       cmp     #1
        bne     :+
        jmp     bol
:       lda     cy
        jmp     clrrow
c_sgr:  ldx     #0                      ; m: each parameter
@p:     lda     par,x
        bne     :+
        stz     attr                    ; 0: plain
        bra     @n
:       cmp     #1
        bne     :+
        lda     #A_BOLD
        tsb     attr
        bra     @n
:       cmp     #7
        bne     :+
        lda     #A_INV
        tsb     attr
        bra     @n
:       cmp     #22
        bne     :+
        lda     #A_BOLD
        trb     attr
        bra     @n
:       cmp     #27
        bne     @n
        lda     #A_INV
        trb     attr
@n:     inx
        inx
        cpx     npar
        bcc     @p
        beq     @p
        rts
c_save: lda     cx
        sta     savex
        lda     cy
        sta     savey
        lda     attr
        sta     savea
        rts
c_rest: lda     savex
        sta     cx
        lda     savey
        sta     cy
        lda     savea
        sta     attr
        rts

; ---------------------------------------------------------------- screen helpers
; the cursor down one row (scrolling at the bottom)
down:   lda     cy
        inc     a
        cmp     #NROW
        bcs     :+
        sta     cy
        rts
:       lda     #0
        jmp     delline

; A = row: the rows below it move up, the last row blank
delline:
        jsr     rowbase
        tax
:       cpx     #NCELL - STRIDE
        bcs     :+
        lda     chars+STRIDE,x
        sta     chars,x
        lda     attrs+STRIDE,x
        sta     attrs,x
        inx
        inx
        bra     :-
:       lda     #NROW - 1
        jsr     clrrow
        jmp     dirtyall

; A = row: it and the rows below move down (the last one goes), it is blank
insline:
        pha
        jsr     rowbase
        sta     tmp
        ldx     #NCELL - STRIDE - 2
:       cpx     tmp
        bmi     :+
        bcc     :+
        lda     chars,x
        sta     chars+STRIDE,x
        lda     attrs,x
        sta     attrs+STRIDE,x
        dex
        dex
        bra     :-
:       pla
        jsr     clrrow
        jmp     dirtyall

; A = row: blank (spaces, plain)
clrrow: pha
        jsr     rowbase
        tax
        ldy     #STRIDE / 2
:       lda     #' ' | (' ' << 8)
        sta     chars,x
        stz     attrs,x
        inx
        inx
        dey
        bne     :-
        pla
        jmp     dirtya

; the whole screen blank, the cursor home, plain
clrscr: stz     cx
        stz     cy
        stz     attr
        stz     estate
        stz     aesc
clrall: lda     #0
:       pha
        jsr     clrrow
        pla
        inc     a
        cmp     #NROW
        bcc     :-
        rts

; from the cursor to the end of the line / screen; from the start of the line / screen
eol:    jsr     cellx
        lda     #80
        sec
        sbc     cx
        tay
        bra     blank
bol:    lda     cy
        jsr     rowbase
        tax
        lda     cx
        inc     a
        tay
        bra     blank
eos:    jsr     eol
        lda     cy
:       inc     a
        cmp     #NROW
        bcs     :+
        pha
        jsr     clrrow
        pla
        bra     :-
:       rts
bos:    jsr     bol
        lda     #0
:       cmp     cy
        bcs     :+
        pha
        jsr     clrrow
        pla
        inc     a
        bra     :-
:       rts
; Y cells from X blank, the cursor's row redrawn
blank:  cpy     #0
        beq     :++
        sep     #$20
        .a8
:       lda     #' '
        sta     chars,x
        stz     attrs,x
        inx
        dey
        bne     :-
        rep     #$20
        .a16
:       jmp     dirtyrow

; X = the cursor's cell (A kept)
cellx:  pha
        lda     cy
        jsr     rowbase
        clc
        adc     cx
        tax
        pla
        rts
; A = row -> A = row * 80
rowbase:
        asl     a
        asl     a
        asl     a
        asl     a
        sta     tmp4
        asl     a
        asl     a
        clc
        adc     tmp4
        rts

dirtyrow:
        pha
        lda     cy
        jsr     dirtya
        pla
        rts
; A = row: drawn again at the next render (A, X, Y kept)
dirtya: cmp     #NROW
        bcs     :+
        phx
        tax
        sep     #$20
        .a8
        lda     #1
        sta     dirty,x
        rep     #$20
        .a16
        plx
:       rts
dirtyall:
        ldx     #NROW - 2
        lda     #$0101
:       sta     dirty,x
        dex
        dex
        bpl     :-
        rts

bell:   lda     #$40                    ; a short beep
        ldx     #6
        ldy     #8
        sys     SYS_BEEP
        rts

; ---------------------------------------------------------------- local messages
; X = text: "*** text" on a line of its own, in either mode
lmsg:   phx
        stz     estate
        stz     aesc
        lda     cx
        beq     :+
        jsr     lnl
:       ldx     #.loword(m_stars)
        jsr     @str
        plx
        jsr     @str
        jmp     lnl
@str:   lda     a:0,x
        and     #$00FF
        beq     :+
        phx
        jsr     emit
        plx
        inx
        bra     @str
:       rts
; a new line in either mode
lnl:    lda     mode
        bne     :+
        lda     #$9B
        jmp     emit
:       lda     #13
        jsr     emit
        lda     #10
        jmp     emit

; X = string appended to msgbuf
msgapp: phx
        ldx     #.loword(msgbuf)
        jsr     ui_strlen
        clc
        adc     #.loword(msgbuf)
        tay
        plx
        jmp     ui_strcpy

; ---------------------------------------------------------------- drawing
; the rows that changed (and the cursor's old and new rows) drawn
render: lda     curdy
        jsr     dirtya
        lda     cy
        jsr     dirtya
        lda     cy
        sta     curdy
        lda     cx                      ; the cursor's cell (a pending wrap: column 79)
        cmp     #80
        bcc     :+
        lda     #79
:       sta     curdx
        stz     row
@r:     ldx     row
        lda     dirty,x
        and     #$00FF
        beq     @n
        sep     #$20
        .a8
        stz     dirty,x
        rep     #$20
        .a16
        lda     mode
        bne     @s
        jsr     rowa                    ; ATASCII: 320 x 8 at y = row * 8
        ldx     #A_INK | (A_PAPER << 8)
        lda     #320
        sta     dblk+8
        lda     #8
        sta     dblk+10
        lda     #40
        sta     dblk+15
        lda     row
        asl     a
        asl     a
        asl     a
        bra     @draw
@s:     jsr     rows                    ; ASCII: 560 x 12 at y = row * 12
        ldx     #S_INK | (S_PAPER << 8)
        lda     #560
        sta     dblk+8
        lda     #12
        sta     dblk+10
        lda     #70
        sta     dblk+15
        lda     row                     ; (row * 12)
        asl     a
        sta     tmp
        asl     a
        clc
        adc     tmp
        asl     a
@draw:  sta     dblk+6
        stx     dblk+1
        lda     win
        ptr     dblk
        sys     SYS_WDRAW
@n:     inc     row
        lda     row
        cmp     #NROW
        bcc     @r
        rts

; the row bitmap of an ATASCII row: 40 cells of 8 x 8 (bit 7 of the code: inverse)
rowa:   lda     row
        jsr     rowbase
        sta     cell
        stz     col
@c:     ldx     cell
        lda     chars,x
        and     #$00FF
        stz     inv
        cmp     #$80
        bcc     :+
        dec     inv
:       ldx     col                     ; the cursor: inverted
        cpx     curdx
        bne     :+
        ldx     row
        cpx     curdy
        bne     :+
        pha
        lda     inv
        eor     #$FFFF
        sta     inv
        pla
:       and     #$007F
        asl     a
        asl     a
        asl     a
        tay
        ldx     col
        sep     #$20
        .a8
        .repeat 8, K
        lda     atascii_font + K,y
        eor     inv
        sta     rowbm + K * 40,x
        .endrepeat
        rep     #$20
        .a16
        inc     cell
        inc     col
        lda     col
        cmp     #40
        bcs     :+
        jmp     @c
:       rts

; the row bitmap of an ASCII row: 80 cells of 7 x 12 (the 8x12 console font without its
; right column, which no glyph uses), packed: 8 cells = 7 bytes, 70 bytes a line
rows:   lda     row                     ; first each cell's glyph, inverse mask and bold
        jsr     rowbase
        sta     cell
        ldx     #0
@g:     phx
        ldx     cell
        lda     attrs,x
        sta     tmp
        lda     chars,x
        and     #$00FF
        sec
        sbc     #' '
        cmp     #$7F - ' '
        bcc     :+
        lda     #0                      ; (not printable ASCII: a space)
:       sta     tmp2                    ; * 12
        asl     a
        clc
        adc     tmp2
        asl     a
        asl     a
        plx
        sta     gofs,x
        lda     tmp
        and     #A_BOLD
        sta     gbold,x
        lda     tmp
        and     #A_INV
        beq     :+
        lda     #$FE
:       sta     ginv,x
        txa                             ; the cursor: inverted
        lsr     a
        cmp     curdx
        bne     :+
        lda     row
        cmp     curdy
        bne     :+
        lda     ginv,x
        eor     #$FE
        sta     ginv,x
:       inc     cell
        inx
        inx
        cpx     #160
        bcc     @g
        stz     line                    ; then line by line, 8 cells at a time
        stz     lpos
@l:     stz     col
        lda     lpos
        sta     bpos
@grp:   ldy     #0                      ; gt = the 8 cells' bytes of this line
@gc:    phy
        lda     col
        asl     a
        tax
        lda     gofs,x
        clc
        adc     line
        tay
        lda     font12,y
        and     #$00FF
        ldy     gbold,x
        beq     :+
        sta     tmp
        lsr     a
        ora     tmp
:       eor     ginv,x
        and     #$00FE
        ply
        sep     #$20
        .a8
        sta     gt,y
        rep     #$20
        .a16
        inc     col
        iny
        cpy     #8
        bcc     @gc
        ldx     bpos                    ; byte K = gt[K] << K | gt[K + 1] >> (7 - K)
        sep     #$20
        .a8
        .repeat 7, K
        lda     gt + K + 1
        .repeat 7 - K
        lsr     a
        .endrepeat
        sta     tb
        lda     gt + K
        .repeat K
        asl     a
        .endrepeat
        ora     tb
        sta     rowbm + K,x
        .endrepeat
        rep     #$20
        .a16
        lda     bpos
        clc
        adc     #7
        sta     bpos
        lda     col
        cmp     #80
        bcs     :+
        jmp     @grp
:       lda     lpos
        clc
        adc     #70
        sta     lpos
        inc     line
        lda     line
        cmp     #12
        bcs     :+
        jmp     @l
:       rts

; the window's size for the mode (ATASCII 320 x 192, ASCII 560 x 288), everything drawn again
wsize:  ldx     #.loword(geoa)
        lda     mode
        beq     :+
        ldx     #.loword(geos)
:       ldy     #^geoa
        lda     win
        sys     SYS_WGEOM
        jmp     dirtyall

        .segment "RODATA"
font12: .include "../kernel/font.inc"
        .include "atascii.inc"
t_title: .byte  "BBS", 0
t_title2: .byte "BBS - ", 0
p_book: .byte   "/SYSTEM/BBS.TXT", 0
w_ascii: .byte  "-ascii", 0
w_telnet: .byte "telnet://", 0
w_tcp:  .byte   "tcp://", 0
w_tcpu: .byte   "tcp://", 0
w_ttatascii: .byte "ATASCII", 0
w_ttansi: .byte "ANSI", 0
mn_conn: .byte  "Connection", 0
mi_connect: .byte "Connect...", 0
mi_disc: .byte  "Disconnect", 0
mi_sep: .byte   "-", 0
mi_nobook: .byte MS_STATE | MS_DIM, "(the address book: /SYSTEM/BBS.TXT)", 0
mi_close: .byte "Close", 0
mn_mode: .byte  "Mode", 0
mi_atascii: .byte "ATASCII, 40 columns", 0
mi_ascii: .byte "ASCII, VT52 / ANSI, 80 columns", 0
mi_clear: .byte "Clear screen", 0
m_stars: .byte  "*** ", 0
m_hello: .byte  "BBS: a telnet terminal through the PC link.", 0
m_hello2: .byte "Press Return (or Connection > Connect...) to connect.", 0
m_atascii: .byte "Mode: ATASCII, 40 columns.", 0
m_ascii: .byte  "Mode: ASCII (VT52 / ANSI), 80 columns.", 0
m_badhost: .byte "Not an address: host, host:port or telnet://host:port.", 0
m_conn1: .byte  "Connecting to ", 0
m_dots: .byte   "...", 0
m_conn2: .byte  "Connected.", 0
m_cannot: .byte "Cannot connect: ", 0
m_ended: .byte  "The connection ended: ", 0
m_closed: .byte "The remote host closed the connection.", 0
m_lost: .byte   "The PC link was lost: the connection ended.", 0
m_bye:  .byte   "Disconnected.", 0
m_eunknown: .byte "an error.", 0
t_conn: .byte   "Connect", 0
s_cprompt: .byte "Host, host:port or telnet://host:port (port 23 if none):", 0
s_cok:  .byte   "Connect", 0
errtab: .word   E_NOLINK, m_nolink, E_LOST, m_lost2, E_NOSVC, m_nosvc, E_BADADDR, m_badaddr
        .word   E_NONAME, m_noname, E_REFUSED, m_refused, E_TIMEOUT, m_timeout
        .word   E_TLS, m_tls, E_PCBUSY, m_pcbusy, E_NET, m_net, E_NSTREAM, m_nstream
        .word   E_CLOSED, m_closed2, 0
m_nolink: .byte "no PC link (start the gateway on the PC).", 0
m_lost2: .byte  "the PC link was lost.", 0
m_nosvc: .byte  "no such service: the gateway has no internet (--no-net?).", 0
m_badaddr: .byte "bad address.", 0
m_noname: .byte "name not found.", 0
m_refused: .byte "refused or unreachable.", 0
m_timeout: .byte "timeout.", 0
m_tls:  .byte   "TLS failed.", 0
m_pcbusy: .byte "too many connections on the PC.", 0
m_net:  .byte   "network error.", 0
m_nstream: .byte "too many files or connections open.", 0
m_closed2: .byte "closed.", 0
pow:    .word   10000, 1000, 100, 10, 1
arrows: .byte   "CDBA"                  ; KEY_RIGHT, LEFT, DOWN, UP
; ATASCII keys: key_ascii's code, the byte sent
akeys:  .word   13, $9B, 8, $7E, 9, $7F, KEY_DEL, $FE
        .word   KEY_UP, $1C, KEY_DOWN, $1D, KEY_LEFT, $1E, KEY_RIGHT, $1F, 0
; ATASCII control codes shown: the code, the routine (others: shown as characters)
actl:   .word   $1B, a_esc, $1C, a_up, $1D, a_down, $1E, a_left, $1F, a_right
        .word   $7D, clrscr, $7E, a_bs, $7F, a_tab, $9B, a_eol, $9C, a_delln
        .word   $9D, a_insln, $9E, a_nop, $9F, a_nop, $FD, a_bell, $FE, a_delch
        .word   $FF, a_insch, 0
; CSI commands
ctab:   .word   'A', c_up, 'B', c_down, 'C', c_right, 'D', c_left, 'H', c_pos, 'f', c_pos
        .word   'J', c_ed, 'K', c_el, 'm', c_sgr, 's', c_save, 'u', c_rest, 0
ttab:   .addr   t_data, t_iac, t_opt, t_sb, t_sbiac
etab:   .addr   e_norm, e_esc, e_csi, e_y1, e_y2

        .segment "DATA"
wblk:   .word   150, 60, 320, 192
        .faraddr t_title
        .byte   0
geoa:   .word   150, 60, 320, 192       ; the window by mode (SYS_WGEOM)
geos:   .word   36, 30, 560, 288
dblk:   .byte   WD_EXPAND, A_INK, A_PAPER, 0
        .word   0, 0, 320, 8
        .faraddr rowbm
        .word   40
ak_conn: .addr  t_conn, s_cprompt, hostbuf
        .word   HOSTMAX + 1
        .addr   s_cok

        .segment "BSS"
argl:   .res    2
argx:   .res    2
wsown:  .res    2
win:    .res    2
mode:   .res    2                       ; 0 ATASCII, 1 ASCII
hnd:    .res    2                       ; the connection's handle ($FFFF: none)
tper:   .res    2                       ; the timer's period now
olen:   .res    2
more:   .res    2                       ; bytes may be waiting still (read again at the tick)
batch:  .res    2
ilen:   .res    2
ipos:   .res    2
tstate: .res    2                       ; telnet: 0 data, 2 IAC, 4 option, 6 SB, 8 SB IAC
tcmd:   .res    2
topt:   .res    2
sblen:  .res    2
o_ttype: .res   2                       ; we do TERMINAL-TYPE
o_echo: .res    2                       ; the server echoes
o_sga:  .res    2                       ; the server suppresses go-ahead
estate: .res    2                       ; ASCII: 0 normal, 2 ESC, 4 CSI, 6 ESC Y, 8 ESC Y row
aesc:   .res    2                       ; ATASCII: the next code shown as a character
npar:   .res    2                       ; CSI: the parameter being read * 2
pdig:   .res    2
par:    .res    16
yrow:   .res    2
cx:     .res    2
cy:     .res    2
attr:   .res    2
savex:  .res    2
savey:  .res    2
savea:  .res    2
curdx:  .res    2
curdy:  .res    2                       ; the row the cursor was drawn in
row:    .res    2
col:    .res    2
cell:   .res    2
inv:    .res    2
port:   .res    2
nbook:  .res    2
tmp:    .res    2
tmp2:   .res    2
tmp3:   .res    2
tmp4:   .res    2
bookname: .res  2                       ; connecting to an address book entry: its name
lstart: .res    2                       ; the address book's parsing
lend:   .res    2
leq:    .res    2
fend:   .res    2
lastnb: .res    2
gw:     .res    16
rwb:    .res    6
sbbuf:  .res    16
hostbuf: .res   HOSTMAX + 2
dispbuf: .res   HOSTMAX + 8
pathbuf: .res   HOSTMAX + 16
msgbuf: .res    200
dirty:  .res    NROW
chars:  .res    NCELL
attrs:  .res    NCELL
rowbm:  .res    70 * 12
gofs:   .res    160                     ; ASCII rows: each cell's glyph (font12 offset),
gbold:  .res    160                     ; bold, inverse mask
ginv:   .res    160
gt:     .res    8
tb:     .res    2
line:   .res    2
lpos:   .res    2
bpos:   .res    2
ibuf:   .res    IBUFSZ
obuf:   .res    OBUFSZ
menus:  .res    1200
book:   .res    NBOOK * 128
fbuf:   .res    FBUFSZ

        .segment "ZEROPAGE"
sx:     .res    2
sy:     .res    2
