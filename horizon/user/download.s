; DOWNLOAD - the Downloader (/BIN/DOWNLOAD.PRG, 0.22): gets a file from the internet through
; the PC link (the gateway on the PC fetches http://, https:// and ftp:// URLs; Horizon reads
; a URL like a file: ABI.md, "The internet").
;   The window: the address (a text field), "Save as" (a path: the folder last used, then
;   the URL's last part, ui_urlname; Choose... opens the file dialog), the progress (a bar
;   and "123 of 456 KB (27%)", or "123 KB" when the server gives no size), a status line
;   (done, or what went wrong), and the buttons Recent... (the last 8 addresses that
;   worked, kept in /SYSTEM/URLS, one per line), Cancel and Download (Enter).
;   The copy is the controls library's ui_cptree in pieces of 4 KB (a URL's read waits
;   until the piece is full): between two pieces the window looks at its events, so Cancel,
;   Esc and the close box work during a download; a cancelled or failed download leaves no
;   partial file. Starting it with an argument puts that address in the field
;   ("download http://..." in the shell).
        .include "horizon.inc"
        .include "ui.inc"

W       = 440                           ; content size
H       = 196
BX      = 12                            ; the left of everything
BW      = W - 2 * BX
BARY    = 122                           ; the bar
BARH    = 14
BARIN   = BW - 2                        ; its inside
NREC    = 8                             ; addresses remembered
URLSZ   = 128                           ; a path (a URL too) is at most 127 characters
RBUFSZ  = NREC * URLSZ + 16
EVMAX   = 32                            ; events looked at between two pieces, at most

        .segment "CODE"
        .a16
        .i16
start:  sta     argl
        stx     argx
        sys     SYS_WSSTART
        bcc     :+
        print   "download: no window system\n"
        exit    1
:       sta     wsown
        jsr     ui_init
        ptr     wblk
        sys     SYS_WOPEN
        bcc     :+
        jsr     stopws
        print   "download: no window\n"
        exit    1
:       sta     win
        ptr     menus
        sys     SYS_WMENU
        ldy     #0                      ; the controls are in it
:       ldx     allc,y
        beq     :+
        sep     #$20
        .a8
        lda     win
        sta     a:CT_WIN,x
        rep     #$20
        .a16
        iny
        iny
        bra     :-
:       jsr     loadrec
        ldx     #.loword(dstbuf)        ; Save as: the current folder, then the name
        ldy     #^dstbuf
        lda     #URLSZ
        sys     SYS_GETCWD
        jsr     slashend
        stz     urlbuf
        lda     argl                    ; an address given
        beq     :+
        ldx     argx
        jsr     args_init
        ldx     #.loword(urlbuf)
        ldy     #^urlbuf
        lda     #URLSZ
        jsr     next_arg
:       jsr     newname
        stz     stbuf
        stz     prbuf
        ldx     #.loword(allc)
        jsr     ui_drawall
        ldx     #.loword(f_url)
        ldy     #.loword(urlbuf)
        jsr     ui_fdset
        ldx     #.loword(f_dest)
        ldy     #.loword(dstbuf)
        jsr     ui_fdset
        jsr     barempty

loop:   lda     #0
        jsr     ui_getev
        bcs     loop
        ldx     #.loword(allc)
        jsr     ui_event
        cmp     #UA_CLICK
        bne     @chg
        cpx     #.loword(b_dl)
        bne     :+
        jsr     download
        lda     quit
        bne     done
        bra     loop
:       cpx     #.loword(b_choose)
        bne     :+
        jsr     choose
        bra     loop
:       cpx     #.loword(b_recent)
        bne     loop
        jsr     recent
        bra     loop
@chg:   cmp     #UA_CHANGE
        bne     @none
        cpx     #.loword(f_url)         ; a new address: a new name in the same folder
        bne     :+
        jsr     newname
        ldx     #.loword(f_dest)
        ldy     #.loword(dstbuf)
        jsr     ui_fdset
:       stz     asked                   ; (Save as changed: ask again before replacing)
        bra     loop
@none:  cmp     #UA_NONE
        jne     loop
        lda     ui_ev
        and     #$00FF
        cmp     #WE_MENU                ; File: Download, Recent..., -, Close
        bne     @cl
        lda     ui_ev+4
        bne     :+
        jsr     download
        lda     quit
        bne     done
        jmp     loop
:       cmp     #1
        bne     :+
        jsr     recent
        jmp     loop
:       cmp     #3
        beq     done
        jmp     loop
@cl:    cmp     #WE_CLOSE
        jne     loop
done:   lda     win
        sys     SYS_WCLOSE
        jsr     stopws
        exit    0

stopws: lda     wsown
        beq     :+
        sys     SYS_WSSTOP
:       rts

; ---------------------------------------------------------------- download
download:
        lda     urlbuf
        and     #$00FF
        bne     :+
        ldx     #.loword(m_nourl)
        jmp     failmsg
:       ldx     #.loword(urlbuf)        ; only URLs: a card file is the Files program's
        jsr     ui_isurl
        bcs     :+
        ldx     #.loword(m_noturl)
        jmp     failmsg
:       lda     dstbuf
        and     #$00FF
        bne     :+
        jsr     newname
:       ldx     #.loword(dstbuf)        ; Save as a folder: the name goes inside it
        jsr     dstat
        bcs     @new
        lda     stbuf2+4
        and     #$0010
        beq     @exists
        jsr     slashend
        ldx     #.loword(urlbuf)
        ldy     #.loword(namebuf)
        jsr     ui_urlname
        ldx     #.loword(namebuf)
        jsr     dstapp
        ldx     #.loword(f_dest)
        ldy     #.loword(dstbuf)
        jsr     ui_fdset
        ldx     #.loword(dstbuf)
        jsr     dstat
        bcs     @new
        lda     stbuf2+4
        and     #$0010
        beq     @exists
        ldx     #.loword(m_isdir)
        jmp     failmsg
@exists:
        lda     asked                   ; (the file dialog asked already)
        bne     @new
        ldx     #.loword(m_repl1)       ; "NAME is there already. Replace it?"
        ldy     #.loword(albuf)
        jsr     ui_strcpy
        ldx     #.loword(dstbuf)
        jsr     alapp
        ldx     #.loword(m_repl2)
        jsr     alapp
        ldx     #.loword(al_repl)
        jsr     ui_alert
        cmp     #0
        beq     @new
        rts
@new:   lda     #UF_DIM                 ; busy: Cancel only
        tsb     b_dl+CT_FLAGS
        tsb     b_choose+CT_FLAGS
        tsb     b_recent+CT_FLAGS
        trb     b_cancel+CT_FLAGS
        jsr     drawbtns
        ldx     #.loword(m_conn)
        jsr     setstat
        stz     prbuf
        ldx     #.loword(l_prog)
        jsr     ui_draw
        jsr     barempty
        stz     cancel
        stz     quit
        lda     #$FFFF
        sta     lastk
        lda     #.loword(dlcb)
        sta     ui_cpcb
        lda     #4096
        sta     ui_cpblk
        ldx     #.loword(urlbuf)
        ldy     #.loword(dstbuf)
        jsr     ui_cptree
        sta     err
        stz     ui_cpcb
        lda     #16384
        sta     ui_cpblk
        lda     #UF_DIM                 ; idle again
        trb     b_dl+CT_FLAGS
        trb     b_choose+CT_FLAGS
        trb     b_recent+CT_FLAGS
        tsb     b_cancel+CT_FLAGS
        php
        jsr     drawbtns
        plp
        bcs     @err
        jsr     showprog                ; (the last piece)
        ldx     #.loword(m_saved)       ; "Saved NAME (12 KB)."
        ldy     #.loword(albuf)
        jsr     ui_strcpy
        ldx     #.loword(dstbuf)
        jsr     alapp
        ldx     #.loword(m_lpar)
        jsr     alapp
        lda     ui_cpk
        jsr     decapp
        ldx     #.loword(m_kbdot)
        jsr     alapp
        ldx     #.loword(albuf)
        jsr     setstat
        jsr     addrec
        stz     asked
        lda     #CH_INFO
        jmp     ui_chime
@err:   lda     err
        cmp     #ECANCELED
        bne     :+
        ldx     #.loword(m_cancel)
        jmp     setstat
:       cmp     #E_HTTP                 ; "HTTP error 404"
        bne     :+
        ldx     #.loword(m_http)
        ldy     #.loword(albuf)
        jsr     ui_strcpy
        lda     ui_cpx
        jsr     decapp
        ldx     #.loword(albuf)
        jmp     failmsg
:       ldx     #0                      ; the others: a sentence each
:       lda     errtab,x
        beq     :+
        cmp     err
        beq     :++
        inx
        inx
        inx
        inx
        bra     :-
:       ldx     #.loword(m_errn)        ; "Error $xx."
        ldy     #.loword(albuf)
        jsr     ui_strcpy
        lda     err
        jsr     hexapp
        ldx     #.loword(albuf)
        jmp     failmsg
:       lda     errtab+2,x
        tax
failmsg:
        jsr     setstat
        jmp     ui_beep

; X = path -> stbuf2 (STAT). C set: not there (or an error)
dstat:  stx     sblk
        lda     #.loword(stbuf2)
        sta     sblk+3
        sep     #$20
        .a8
        lda     #^stbuf2
        sta     sblk+2
        sta     sblk+5
        rep     #$20
        .a16
        ptr     sblk
        sys     SYS_STAT
        rts

; ui_cpcb: after every piece (and when the file starts): the progress shown, the events
; looked at. C set: cancel
dlcb:   lda     ui_cpk
        bne     :+
        ldx     #.loword(m_dling)       ; the server answered: "Downloading..."
        jsr     setstat
:       jsr     showprog
        lda     #EVMAX
        sta     evn
@get:   dec     evn
        bmi     @no
        lda     #1                      ; (SYS_WEVENT, not ui_getev: nothing is put aside)
        ptr     ui_ev
        sys     SYS_WEVENT
        bcs     @no
        lda     ui_ev+1
        and     #$00FF
        cmp     win
        bne     @get
        lda     ui_ev
        and     #$00FF
        cmp     #WE_CLOSE               ; the close box: cancel, then quit
        bne     :+
        lda     #1
        sta     quit
        bra     @yes
:       ldx     #.loword(busyc)
        jsr     ui_event
        cmp     #UA_CLICK
        bne     @get
@yes:   lda     #1
        sta     cancel
        sec
        rts
@no:    lda     cancel
        beq     :+
        sec
        rts
:       clc
        rts

; the progress: "123 of 456 KB (27%)" or "123 KB", and the bar (only when it changed)
showprog:
        lda     ui_cpk
        cmp     lastk
        bne     :+
        rts
:       sta     lastk
        lda     ui_cpsize               ; total K = (size + 1023) / 1024
        ora     ui_cpsize+2
        sta     known
        lda     ui_cpsize
        clc
        adc     #1023
        sta     tmp
        lda     ui_cpsize+2
        adc     #0
        xba
        and     #$FF00
        lsr     a
        lsr     a
        sta     tot
        lda     tmp
        xba
        and     #$00FF
        lsr     a
        lsr     a
        ora     tot
        sta     tot
        lda     ui_cpk
        ldx     known
        beq     :+
        cmp     tot
        bcc     :+
        lda     tot
:       sta     kdone
        stz     prbuf
        ldy     #.loword(prbuf)
        lda     kdone
        jsr     decat
        lda     known
        bne     :+
        ldx     #.loword(m_kb)
        jsr     strat
        bra     @draw
:       ldx     #.loword(m_of)
        jsr     strat
        lda     tot
        jsr     decat
        ldx     #.loword(m_kbp)
        jsr     strat
        phy
        lda     kdone
        ldx     #100
        ldy     tot
        jsr     ui_muldiv
        ply
        jsr     decat
        ldx     #.loword(m_pct)
        jsr     strat
@draw:  ldx     #.loword(l_prog)
        jsr     ui_draw
        lda     known                   ; the size unknown: no bar
        beq     @out
        lda     kdone
        ldx     #BARIN
        ldy     tot
        jsr     ui_muldiv
        cmp     #0
        beq     @out
        sta     z:ui_w
        lda     win
        sta     z:ui_win
        lda     #BX + 1
        sta     z:ui_x
        lda     #BARY + 1
        sta     z:ui_y
        lda     #BARH - 2
        sta     z:ui_h
        lda     #WD_FILL | (C_SELECT << 8)
        jsr     ui_rect
@out:   rts

; the bar: white, sunken
barempty:
        lda     win
        sta     z:ui_win
        lda     #BX
        sta     z:ui_x
        lda     #BARY
        sta     z:ui_y
        lda     #BW
        sta     z:ui_w
        lda     #BARH
        sta     z:ui_h
        lda     #WD_FILL | (C_WHITE << 8)
        jsr     ui_rect
        lda     #1
        jmp     ui_bevel

drawbtns:
        ldx     #.loword(b_dl)
        jsr     ui_draw
        ldx     #.loword(b_choose)
        jsr     ui_draw
        ldx     #.loword(b_recent)
        jsr     ui_draw
        ldx     #.loword(b_cancel)
        jmp     ui_draw

; X = message: the status line
setstat:
        ldy     #.loword(stbuf)
        jsr     ui_strcpy
        ldx     #.loword(l_stat)
        jmp     ui_draw

; ---------------------------------------------------------------- Save as
; dstbuf = its folder (up to its last '/') + the URL's name
newname:
        ldx     #0                      ; cut after the last '/'
        ldy     #0
:       lda     dstbuf,x
        and     #$00FF
        beq     :++
        inx
        cmp     #'/'
        bne     :+
        txy
:       bra     :--
:       sep     #$20
        .a8
        lda     #0
        sta     dstbuf,y
        rep     #$20
        .a16
        lda     urlbuf
        and     #$00FF
        beq     :+
        ldx     #.loword(urlbuf)
        ldy     #.loword(namebuf)
        jsr     ui_urlname
        ldx     #.loword(namebuf)
        jmp     dstapp
:       rts

; dstbuf ends with '/' (unless empty)
slashend:
        ldx     #.loword(dstbuf)
        jsr     ui_strlen
        tax
        beq     :+
        lda     dstbuf-1,x
        and     #$00FF
        cmp     #'/'
        beq     :+
        ldx     #.loword(s_slash)
        jmp     dstapp
:       rts

; X = string appended to dstbuf (cut at 127 characters)
dstapp: phx
        ldx     #.loword(dstbuf)
        jsr     ui_strlen
        tay
        plx
:       cpy     #URLSZ - 1
        bcs     :+
        lda     a:0,x
        and     #$00FF
        beq     :+
        sep     #$20
        .a8
        sta     dstbuf,y
        rep     #$20
        .a16
        inx
        iny
        bra     :-
:       sep     #$20
        .a8
        lda     #0
        sta     dstbuf,y
        rep     #$20
        .a16
        rts

; Choose...: the file dialog (save), starting with the name
choose: ldx     #.loword(urlbuf)
        ldy     #.loword(dlgbuf)
        jsr     ui_urlname
        lda     #1
        ldx     #.loword(dlgbuf)
        ldy     #.loword(t_choose)
        jsr     ui_filedlg
        bcs     :+
        ldx     #.loword(dlgbuf)
        ldy     #.loword(dstbuf)
        jsr     ui_strcpy
        ldx     #.loword(f_dest)
        ldy     #.loword(dstbuf)
        jsr     ui_fdset
        lda     #1                      ; (the dialog asked before replacing)
        sta     asked
:       rts

; ---------------------------------------------------------------- recent addresses
; /SYSTEM/URLS -> rec (NREC entries of URLSZ bytes; nrec)
loadrec:
        stz     nrec
        ptr     p_urls
        lda     #O_READ
        sys     SYS_OPEN
        bcs     @out
        sta     rwb
        lda     #.loword(rbuf)
        sta     rwb+1
        sep     #$20
        .a8
        lda     #^rbuf
        sta     rwb+3
        rep     #$20
        .a16
        lda     #RBUFSZ - 1
        sta     rwb+4
        ptr     rwb
        sys     SYS_READ
        bcc     :+
        lda     #0
:       tay
        sep     #$20
        .a8
        lda     #0
        sta     rbuf,y
        rep     #$20
        .a16
        lda     rwb
        and     #$00FF
        sys     SYS_CLOSE
        ldx     #0                      ; the lines
@line:  lda     nrec
        cmp     #NREC
        bcs     @out
        jsr     recptr                  ; Y = the entry
        stz     tmp
:       lda     rbuf,x
        and     #$00FF
        beq     @last
        inx
        cmp     #10
        beq     @eol
        cmp     #' '                    ; (CR and other control characters left out)
        bcc     :-
        pha
        lda     tmp
        cmp     #URLSZ - 1
        pla
        bcs     :-
        sep     #$20
        .a8
        sta     a:0,y
        rep     #$20
        .a16
        iny
        inc     tmp
        bra     :-
@eol:   jsr     @end
        bra     @line
@last:  jsr     @end
@out:   rts
@end:   sep     #$20
        .a8
        lda     #0
        sta     a:0,y
        rep     #$20
        .a16
        lda     tmp
        beq     :+
        inc     nrec
:       rts

; Y = the address of entry nrec (A, X kept)
recptr: pha
        lda     nrec
        jsr     recat
        pla
        rts
; A = an entry -> Y = its address (* 128)
recat:  xba
        lsr     a
        clc
        adc     #.loword(rec)
        tay
        rts

; urlbuf first in the list (once), then the list written to /SYSTEM/URLS
addrec: ldx     #0                      ; the same address there already: out
@find:  cpx     nrec
        bcs     @ins
        phx
        txa
        jsr     recat                   ; Y = entry X
        ldx     #0
:       lda     urlbuf,x
        and     #$00FF
        sta     tmp
        lda     a:0,y
        and     #$00FF
        cmp     tmp
        bne     @diff
        cmp     #0
        beq     @same
        inx
        iny
        bra     :-
@diff:  plx
        inx
        bra     @find
@same:  plx                             ; remove entry X: the ones after it move up
:       inx
        cpx     nrec
        bcs     :+
        jsr     @move                   ; entry X to X - 1
        bra     :-
:       dec     nrec
@ins:   lda     nrec                    ; the others move down (the last one may go)
        cmp     #NREC
        bcc     :+
        dec     nrec
:       ldx     nrec
:       cpx     #0
        beq     :+
        jsr     @movedn                 ; entry X - 1 to X
        dex
        bra     :-
:       ldx     #.loword(urlbuf)
        ldy     #.loword(rec)
        jsr     ui_strcpy
        inc     nrec
        jmp     saverec
@move:  phx                             ; entry X -> X - 1
        txa
        xba
        lsr     a
        clc
        adc     #.loword(rec)
        pha
        sec
        sbc     #URLSZ
        tay
        plx
        jsr     ui_strcpy
        plx
        rts
@movedn:
        phx                             ; entry X - 1 -> X
        txa
        xba
        lsr     a
        clc
        adc     #.loword(rec)
        tay
        sec
        sbc     #URLSZ
        tax
        jsr     ui_strcpy
        plx
        rts

saverec:
        ldy     #0                      ; the lines into rbuf
        ldx     #0
@ent:   cpx     nrec
        bcs     @wr
        phx
        phy
        txa
        jsr     recat
        tyx
        ply
:       lda     a:0,x
        and     #$00FF
        beq     :+
        sep     #$20
        .a8
        sta     rbuf,y
        rep     #$20
        .a16
        inx
        iny
        bra     :-
:       lda     #10
        sep     #$20
        .a8
        sta     rbuf,y
        rep     #$20
        .a16
        iny
        plx
        inx
        bra     @ent
@wr:    sty     tmp
        ptr     p_urls
        lda     #O_CREATE
        sys     SYS_OPEN
        bcs     @out
        sta     rwb
        lda     #.loword(rbuf)
        sta     rwb+1
        sep     #$20
        .a8
        lda     #^rbuf
        sta     rwb+3
        rep     #$20
        .a16
        lda     tmp
        sta     rwb+4
        ptr     rwb
        sys     SYS_WRITE
        lda     rwb
        and     #$00FF
        sys     SYS_CLOSE
@out:   rts

; Recent...: a pop-up menu of the addresses below the button; the one chosen goes into
; the field
recent: ldy     #0                      ; the items: each cut to 56 characters
        ldx     #0
@ent:   cpx     nrec
        bcs     @end
        phx
        phy
        txa
        jsr     recat
        tyx
        ply
        stz     tmp
:       lda     a:0,x
        and     #$00FF
        beq     @eos
        pha
        lda     tmp
        cmp     #56
        pla
        bcc     :+
        lda     #'.'                    ; longer: "..."
        jsr     @put
        jsr     @put
        jsr     @put
        bra     @eos
:       jsr     @put
        inx
        inc     tmp
        bra     :--
@eos:   lda     #0
        jsr     @put
        plx
        inx
        bra     @ent
@end:   cpy     #0
        bne     :+
        ldx     #.loword(m_none)        ; none yet: one dimmed item
        jsr     @str
:       lda     #0
        jsr     @put
        lda     win
        sta     z:ui_win
        lda     b_recent+CT_X
        sta     z:ui_x
        lda     b_recent+CT_Y
        clc
        adc     #UI_BTNH
        sta     z:ui_y
        ldx     #.loword(items)
        lda     win
        jsr     ui_popat
        cmp     nrec
        bcs     @out
        jsr     recat
        tyx
        ldy     #.loword(urlbuf)
        jsr     ui_strcpy
        ldx     #.loword(f_url)
        ldy     #.loword(urlbuf)
        jsr     ui_fdset
        jsr     newname
        ldx     #.loword(f_dest)
        ldy     #.loword(dstbuf)
        jsr     ui_fdset
        stz     asked
@out:   rts
@put:   sep     #$20
        .a8
        sta     items,y
        rep     #$20
        .a16
        iny
        rts
@str:   lda     a:0,x
        and     #$00FF
        jsr     @put
        inx
        cmp     #0
        bne     @str
        rts

; ---------------------------------------------------------------- strings
; X = string appended to albuf
alapp:  phx
        ldx     #.loword(albuf)
        jsr     ui_strlen
        clc
        adc     #.loword(albuf)
        tay
        plx
        jmp     ui_strcpy

; A = number appended to albuf in decimal
decapp: pha
        ldx     #.loword(albuf)
        jsr     ui_strlen
        clc
        adc     #.loword(albuf)
        tay
        pla
        ; fall through
; A = number (0-65535) stored at Y in decimal ("1,500" with thousands) -> Y at its end
decat:  sta     tmp
        stz     any
        ldx     #0
@d:     stz     dig
:       lda     tmp
        cmp     pow,x
        bcc     :+
        sbc     pow,x
        sta     tmp
        inc     dig
        bra     :-
:       lda     dig
        ora     any
        bne     @put
        cpx     #8
        bne     @skip
@put:   lda     #1
        sta     any
        lda     dig
        clc
        adc     #'0'
        jsr     putc
        cpx     #2
        bne     @skip
        lda     #','
        jsr     putc
@skip:  inx
        inx
        cpx     #10
        bcc     @d
        lda     #0
        sep     #$20
        .a8
        sta     a:0,y
        rep     #$20
        .a16
        rts
putc:   sep     #$20
        .a8
        sta     a:0,y
        rep     #$20
        .a16
        iny
        rts

; X = string stored at Y -> Y at its end
strat:  lda     a:0,x
        and     #$00FF
        sep     #$20
        .a8
        sta     a:0,y
        rep     #$20
        .a16
        beq     :+
        inx
        iny
        bra     strat
:       rts

; A = byte appended to albuf in hex, then "."
hexapp: pha
        ldx     #.loword(albuf)
        jsr     ui_strlen
        clc
        adc     #.loword(albuf)
        tay
        pla
        pha
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        jsr     @dig
        pla
        jsr     @dig
        lda     #'.'
        jsr     putc
        lda     #0
        jmp     putc
@dig:   and     #$000F
        tax
        lda     hexd,x
        jmp     putc

        .segment "RODATA"
t_title: .byte  "Downloader", 0
t_choose: .byte "Save the download as", 0
p_urls: .byte   "/SYSTEM/URLS", 0
s_url:  .byte   "Address (http://, https:// or ftp://):", 0
s_dest: .byte   "Save as:", 0
s_choose: .byte "Choose...", 0
s_recent: .byte "Recent...", 0
s_cancel: .byte "Cancel", 0
s_dl:   .byte   "Download", 0
s_slash: .byte  "/", 0
m_nourl: .byte  "Type an address first.", 0
m_noturl: .byte "Not an address: it starts with http://, https:// or ftp://.", 0
m_isdir: .byte  "Save as is a folder: type a file name.", 0
m_repl1: .byte  0
m_repl2: .byte  " is there already.", 10, "Replace it?", 0
m_conn: .byte   "Connecting...", 0
m_dling: .byte  "Downloading...", 0
m_saved: .byte  "Saved ", 0
m_lpar: .byte   " (", 0
m_kbdot: .byte  " KB).", 0
m_cancel: .byte "Cancelled: nothing was saved.", 0
m_http: .byte   "The server answered: HTTP error ", 0
m_errn: .byte   "Error $", 0
m_of:   .byte   " of ", 0
m_kb:   .byte   " KB", 0
m_kbp:  .byte   " KB (", 0
m_pct:  .byte   "%)", 0
m_none: .byte   MS_STATE | MS_DIM, "(none yet)", 0
b_replace: .byte "Replace", 0
errtab: .word   E_NOLINK, m_nolink, E_LOST, m_lost, E_NOSVC, m_nosvc, E_BADADDR, m_badaddr
        .word   E_NONAME, m_noname, E_REFUSED, m_refused, E_TIMEOUT, m_timeout
        .word   E_TLS, m_tls, E_PCBUSY, m_pcbusy, E_NET, m_net, E_NSTREAM, m_nstream
        .word   EIO + $44, m_nofile, EIO + $45, m_nopath, EIO + 7, m_denied
        .word   ENOMEM, m_nomem, EINVAL, m_inval, 0
m_nolink: .byte "No PC link: start the gateway on the PC.", 0
m_lost: .byte   "The PC link was lost.", 0
m_nosvc: .byte  "No internet: the gateway does not offer it (--no-net?).", 0
m_badaddr: .byte "Bad address (the URL, the host or the port).", 0
m_noname: .byte "Name not found: no such server.", 0
m_refused: .byte "Refused or unreachable.", 0
m_timeout: .byte "Timeout: the server did not answer.", 0
m_tls:  .byte   "TLS failed: the server's certificate is not valid.", 0
m_pcbusy: .byte "Too many connections on the PC.", 0
m_net:  .byte   "Network error.", 0
m_nstream: .byte "Too many files or connections open.", 0
m_nofile: .byte "Not found.", 0
m_nopath: .byte "The folder of Save as is not there.", 0
m_denied: .byte "Denied: the file cannot be written.", 0
m_nomem: .byte  "Not enough memory.", 0
m_inval: .byte  "The address or the name is too long.", 0
pow:    .word   10000, 1000, 100, 10, 1
hexd:   .byte   "0123456789ABCDEF"
al_repl: .word  AL_QUESTION, t_title, albuf, b_replace, s_cancel, 0

menus:  .byte   "File", 0, "Download", 0, "Recent addresses...", 0, "-", 0, "Close", 0, 0, 0

        .segment "DATA"
wblk:   .word   120, 80, W, H
        .faraddr t_title
        .byte   0
allc:   .addr   l_url, f_url, l_dest, f_dest, b_choose, l_prog, l_stat, b_recent, b_cancel, b_dl, 0
busyc:  .addr   b_cancel, 0
l_url:  .byte   UT_LABEL, 0
        .word   BX, 10, BW, UI_LINE, 0
        .addr   s_url
f_url:  .byte   UT_FIELD, 0
        .word   BX, 26, BW, UI_FLDH, UF_FOCUS
        .addr   urlbuf
        .word   URLSZ, 0, 0, 0, 0
l_dest: .byte   UT_LABEL, 0
        .word   BX, 54, BW, UI_LINE, 0
        .addr   s_dest
f_dest: .byte   UT_FIELD, 0
        .word   BX, 70, BW - 96, UI_FLDH, 0
        .addr   dstbuf
        .word   URLSZ, 0, 0, 0, 0
b_choose: .byte UT_BUTTON, 0
        .word   W - BX - 88, 69, 88, UI_BTNH, 0
        .addr   s_choose
l_prog: .byte   UT_LABEL, 0
        .word   BX, 104, BW, UI_LINE, 0
        .addr   prbuf
l_stat: .byte   UT_LABEL, 0
        .word   BX, 142, BW, UI_LINE, 0
        .addr   stbuf
b_recent: .byte UT_BUTTON, 0
        .word   BX, H - 12 - UI_BTNH, 88, UI_BTNH, 0
        .addr   s_recent
b_cancel: .byte UT_BUTTON, 0
        .word   W - BX - 184, H - 12 - UI_BTNH, 88, UI_BTNH, UF_CANCEL | UF_DIM
        .addr   s_cancel
b_dl:   .byte   UT_BUTTON, 0
        .word   W - BX - 88, H - 12 - UI_BTNH, 88, UI_BTNH, UF_DEFAULT
        .addr   s_dl

        .segment "BSS"
argl:   .res    2
argx:   .res    2
wsown:  .res    2
win:    .res    2
quit:   .res    2
cancel: .res    2
asked:  .res    2                       ; Save as came from the file dialog (it asked already)
err:    .res    2
evn:    .res    2
lastk:  .res    2
known:  .res    2
tot:    .res    2
kdone:  .res    2
tmp:    .res    2
any:    .res    2
dig:    .res    2
nrec:   .res    2
sblk:   .res    6
rwb:    .res    6
stbuf2: .res    10
urlbuf: .res    URLSZ
dstbuf: .res    URLSZ
dlgbuf: .res    URLSZ
namebuf: .res   UI_NAMEMAX + 1
stbuf:  .res    80
prbuf:  .res    40
albuf:  .res    200
items:  .res    NREC * 64 + 16
rec:    .res    NREC * URLSZ
rbuf:   .res    RBUFSZ
