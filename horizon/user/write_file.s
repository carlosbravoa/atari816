; write_file.s - Write: find, replace, go to line, word count (as Edit's), and the files:
; load, save (the lines written back as they are: a file read and saved unedited is the
; same, byte for byte), export as plain text (the markup stripped). Part of write.s.

        .segment "CODE"

; ---------------------------------------------------------------- find, replace, go to
; Edit > Find...: the text to find (ignoring case), then the next place it is
m_find: jsr     flush
        ldx     #.loword(fd_find)       ; the last text, selected
        ldy     #.loword(fpat)
        jsr     fdpre
        lda     #UF_FOCUS
        sta     fd_find+CT_FLAGS
        ldx     #.loword(dg_find)
        jsr     ui_dlgopen
        jcs     loop
        ldx     #.loword(dg_find)
        jsr     ui_dlgrun
        phx
        ldx     #.loword(dg_find)
        jsr     ui_dlgclose
        plx
        cpx     #.loword(bt_ffind)
        jne     loop
        ldx     #.loword(fbuf)
        jsr     setpat
        jmp     m_fnext

; Edit > Find next (F3, ctrl-G): from the selection's end (or the cursor) on, then from
; the start; the text found selected
m_fnext:
        lda     fplen
        jeq     m_find
        jsr     snap
        jsr     findnext
        jsr     setgoal
        jmp     post

; Edit > Replace...: the dialog stays open while it finds and replaces
m_repl: jsr     flush
        ldx     #.loword(fd_rfind)
        ldy     #.loword(fpat)
        jsr     fdpre
        ldx     #.loword(fd_rwith)
        ldy     #.loword(rpat)
        jsr     fdpre
        lda     #UF_FOCUS
        sta     fd_rfind+CT_FLAGS
        stz     fd_rwith+CT_FLAGS
        ldx     #.loword(dg_repl)
        jsr     ui_dlgopen
        jcs     loop
@run:   ldx     #.loword(dg_repl)
        jsr     ui_dlgrun
        stx     z:t5
        cpx     #.loword(bt_rclose)
        beq     @close
        ldx     #.loword(rfbuf)         ; the texts as they are now
        jsr     setpat
        ldx     #.loword(rwbuf)
        ldy     #.loword(rpat)
        jsr     ui_strcpy
        lda     fplen
        beq     @run
        jsr     snap
        lda     z:t5
        cmp     #.loword(bt_rall)
        beq     @all
        cmp     #.loword(bt_rnext)
        beq     @find
        jsr     selmatch                ; Replace: the selection, if it is the text
        bcc     @find
        jsr     replone
@find:  jsr     findnext
        jsr     marksel
        jsr     setgoal
        jsr     ensure
        jsr     refresh
        bra     @run
@all:   jsr     replall
        jsr     marksel
        jsr     setgoal
        jsr     ensure
        jsr     refresh
        ldx     #.loword(dg_repl)
        jsr     ui_dlgclose
        ldy     #.loword(msgbuf)        ; "N replaced."
        lda     rcount
        jsr     snum
        ldx     #.loword(m_repld)
        jsr     scat
        ldx     #.loword(al_note)
        jsr     ui_alert
        jmp     loop
@close: ldx     #.loword(dg_repl)
        jsr     ui_dlgclose
        jmp     loop

; field X gets string Y (selected all, scrolled to its start), not drawn
fdpre:  phx
        lda     a:FD_BUF,x
        tax
        tya
        txy
        tax
        jsr     ui_strcpy
        plx
        sta     a:FD_LEN,x
        sta     a:FD_CUR,x
        stz     a:FD_ANC,x
        stz     a:FD_SCR,x
        rts

; the pattern: string X (at most FINDMAX - 1) -> fpat, fplen, fplow (in lower case)
setpat: ldy     #.loword(fpat)
        jsr     ui_strcpy
        sta     fplen
        ldx     #0
:       cpx     fplen
        bcs     :+
        lda     fpat,x
        jsr     lower
        sep     #$20
        .a8
        sta     fplow,x
        rep     #$20
        .a16
        inx
        bra     :-
:       rts

; A (a byte) in lower case (A-Z only)
lower:  and     #$00FF
        cmp     #'A'
        bcc     :+
        cmp     #'Z' + 1
        bcs     :+
        ora     #$20
:       rts

; the next place of the pattern after the selection or cursor, wrapping to the start ->
; selected (C set); not there: an alert (C clear)
findnext:
        jsr     selord
        bcs     :+
        lda     cl
        sta     sl
        lda     cc
        sta     sc
        bra     :++
:       lda     s1l
        sta     sl
        lda     s1c
        sta     sc
:       jsr     search
        bcs     @got
        stz     sl                      ; from the start
        stz     sc
        jsr     search
        bcs     @got
        ldx     #.loword(m_nofind)      ; "Cannot find "...""
        ldy     #.loword(msgbuf)
        jsr     ui_strcpy
        ldx     #.loword(fpat)
        jsr     append
        ldx     #.loword(m_quote)
        jsr     append
        ldx     #.loword(al_note)
        jsr     ui_alert
        clc
        rts
@got:   lda     sl                      ; selected: the cursor at its end
        sta     al
        sta     cl
        lda     sc
        sta     ac
        clc
        adc     fplen
        sta     cc
        sec
        rts

; the pattern from line sl, column sc on -> C set: found there (sl, sc)
search: lda     sl
        cmp     nl
        bcs     @no
        jsr     lget
        lda     llen
        sec
        sbc     fplen
        bcc     @next
        sta     s_last                  ; the last column it can start
@col:   lda     sc
        cmp     s_last
        beq     :+
        bcs     @next
:       jsr     match
        bcs     @yes
        inc     sc
        bra     @col
@next:  inc     sl
        stz     sc
        bra     search
@yes:   sec
        rts
@no:    clc
        rts

; is the pattern at column sc of line lp? -> C set
match:  lda     sc
        clc
        adc     #4
        tay
        ldx     #0
:       cpx     fplen
        bcs     @y
        lda     [lp],y
        jsr     lower
        sep     #$20
        .a8
        cmp     fplow,x
        rep     #$20
        .a16
        bne     @n
        iny
        inx
        bra     :-
@y:     sec
        rts
@n:     clc
        rts

; is the selection the pattern (on one line, ignoring case)? -> C set
selmatch:
        jsr     selord
        bcc     @no
        lda     s0l
        cmp     s1l
        bne     @no
        lda     s1c
        sec
        sbc     s0c
        cmp     fplen
        bne     @no
        lda     s0c
        sta     sc
        lda     s0l
        jsr     lget
        jmp     match
@no:    clc
        rts

; the selection replaced by rpat (one undo group with what follows in this action)
replone:
        jsr     delsel
        ldx     #.loword(rpat)
        jsr     ui_strlen
        beq     :+
        pha
        lda     #.loword(rpat)
        sta     isrc
        lda     #^rpat
        sta     isrc+2
        pla
        jsr     inst
:       jmp     anchor0

; Replace all: every place from the start, each replaced (one undo group) -> rcount
replall:
        stz     rcount
        stz     sl
        stz     sc
@l:     jsr     search
        bcc     @out
        lda     sl                      ; select it, replace it, on after it
        sta     al
        sta     cl
        lda     sc
        sta     ac
        clc
        adc     fplen
        sta     cc
        jsr     replone
        inc     rcount
        lda     cl
        sta     sl
        lda     cc
        sta     sc
        lda     rcount
        cmp     #$FFFF
        bne     @l
@out:   rts

; Edit > Go to line...
m_goto: jsr     flush
        stz     gbuf
        ldx     #.loword(fd_goto)
        ldy     #.loword(gbuf)
        jsr     fdpre
        lda     #UF_FOCUS
        sta     fd_goto+CT_FLAGS
        ldx     #.loword(dg_goto)
        jsr     ui_dlgopen
        jcs     loop
        ldx     #.loword(dg_goto)
        jsr     ui_dlgrun
        phx
        ldx     #.loword(dg_goto)
        jsr     ui_dlgclose
        plx
        cpx     #.loword(bt_gok)
        jne     loop
        ldx     #0                      ; the number
        stz     z:t0
@d:     lda     gbuf,x
        and     #$00FF
        cmp     #'0'
        bcc     @e
        cmp     #'9' + 1
        bcs     @e
        sec
        sbc     #'0'
        sta     z:t1
        lda     z:t0                    ; t0 * 10 + digit (at most 65535)
        cmp     #6553
        bcs     @e
        asl     a
        asl     a
        adc     z:t0
        asl     a
        adc     z:t1
        sta     z:t0
        inx
        bra     @d
@e:
        lda     z:t0
        jeq     loop
        jsr     snap
        lda     z:t0
        dec     a
        cmp     nl
        bcc     :+
        lda     nl
        dec     a
:       sta     cl
        sta     top                     ; (at the top of the view if it can be)
        stz     toff
        jsr     hidpfx
        sta     cc
        stz     shift
        jmp     mv_h

; View > Word count (ctrl-W): words (as the status line counts them), characters (not
; counting line ends, markup included), lines
m_count:
        jsr     flush
        stz     wc_c
        stz     wc_c+2
        stz     cpi
@l:     lda     cpi
        cmp     nl
        bcs     @show
        jsr     lget
        lda     llen
        clc
        adc     wc_c
        sta     wc_c
        bcc     :+
        inc     wc_c+2
:       inc     cpi
        bra     @l
@show:  ldy     #.loword(msgbuf)
        ldx     #.loword(m_words)
        jsr     scat
        lda     wc_tot+2
        sta     z:t1
        lda     wc_tot
        jsr     snum32
        ldx     #.loword(m_chars)
        jsr     scat
        lda     wc_c+2
        sta     z:t1
        lda     wc_c
        jsr     snum32
        ldx     #.loword(m_lines)
        jsr     scat
        lda     nl
        jsr     snum
        ldx     #.loword(al_count)
        jsr     ui_alert
        jmp     loop


; ---------------------------------------------------------------- files
; "Loading NAME..." in the window (a large file takes seconds)
loading:
        ldx     #.loword(m_loading)
        ldy     #.loword(msgbuf)
        jsr     ui_strcpy
        jsr     basename
        jsr     append
        ldx     #.loword(m_dots)
        jsr     append
        lda     win
        sta     z:ui_win
        lda     #LEFTM
        sta     z:ui_x
        lda     #8
        sta     z:ui_y
        stz     z:ui_font
        ldx     #.loword(msgbuf)
        lda     #C_DARK | ($FF << 8)
        jmp     ui_text

; read fpath into a new text (not recorded for undo; the view from the start)
load:   lda     #1
        sta     loadng
        stz     ub_rec
        jsr     load0
        lda     #1
        sta     ub_rec
        stz     loadng
        stz     emod
        stz     toff
        jsr     viewflush
        jmp     ub_clear
load0:  jsr     tx_reset
        ptr     fpath
        lda     #O_READ
        sys     SYS_OPEN
        bcc     :+
        cmp     #$44                    ; not there: a new file of that name
        beq     @new
        ldx     #.loword(m_cantopen)
        jsr     errbox
@new:   rts
:       sta     fh
        stz     crhold
@chunk: stz     z:t4                    ; a CR held from the last piece first
        lda     crhold
        cmp     #2
        bne     :+
        lda     #13
        stz     z:sp
        ldx     sbank
        stx     z:sp+2
        sep     #$20
        .a8
        sta     [sp]
        rep     #$20
        .a16
        lda     #1
        sta     z:t4
:       lda     fh                      ; read
        sta     rblk
        lda     z:t4
        sta     rblk+1
        lda     sbank
        sta     rblk+3
        lda     #CHUNK
        sta     rblk+4
        ptr     rblk
        sys     SYS_READ
        bcs     @err
        sta     z:t5
        lda     #1                      ; (a CR at the end: held unless this was the last piece)
        sta     crhold
        lda     z:t5
        cmp     #CHUNK
        bcs     :+
        stz     crhold
:       lda     z:t5
        clc
        adc     z:t4
        jsr     crfilter
        stz     isrc
        ldx     sbank
        stx     isrc+2
        cmp     #0
        beq     :+
        jsr     inst
        bcs     @full
:       lda     z:t5
        cmp     #CHUNK
        bcs     @chunk
        bra     @close
@err:   pha
        lda     fh
        sys     SYS_CLOSE
        pla
        ldx     #.loword(m_cantread)
        jmp     errbox
@full:  ldx     #.loword(m_toobig)      ; (what fitted stays)
        lda     #0
        jsr     errbox
@close: lda     fh
        sys     SYS_CLOSE
        stz     cl
        stz     cc
        stz     al
        stz     ac
        stz     top
        stz     goalx
        stz     emod
        rts

; write the text to fpath -> C set: failed (said so)
save:   ptr     fpath
        lda     #O_CREATE
        sys     SYS_OPEN
        bcc     :+
        ldx     #.loword(m_cantsave)
        jsr     errbox
        sec
        rts
:       sta     fh
        stz     z:dp
        lda     sbank
        sta     z:dp+2
        stz     cpn                     ; bytes in SB
        stz     cpi
@l:     lda     cpi
        cmp     nl
        bcs     @end
        jsr     lget
        lda     cpn                     ; room for the line and its end?
        clc
        adc     llen
        bcs     :+
        cmp     #$F000
        bcc     :++
:       ldx     cpn
        jsr     @flush
        bcs     @err
:       ldy     #4                      ; the bytes
        ldx     cpn
        lda     llen
        sta     z:t0
        sep     #$20
        .a8
:       lda     z:t0
        ora     z:t0+1
        beq     :+
        lda     [lp],y
        phy
        txy
        sta     [dp],y
        ply
        iny
        inx
        rep     #$20
        .a16
        dec     z:t0
        sep     #$20
        .a8
        bra     :-
:       rep     #$20
        .a16
        lda     cpi                     ; the line end (not after the last line)
        inc     a
        cmp     nl
        bcs     :++
        lda     crlf
        beq     :+
        lda     #13
        jsr     @put
:       lda     #10
        jsr     @put
:       stx     cpn
        inc     cpi
        bra     @l
@end:   ldx     cpn
        jsr     @flush
        bcs     @err
        lda     fh
        sys     SYS_CLOSE
        bcs     @err2
        stz     emod
        lda     ub_top                  ; (undo back to here: not modified)
        sta     ub_save
        jsr     settitle
        clc
        rts
@err:   pha
        lda     fh
        sys     SYS_CLOSE
        pla
@err2:  ldx     #.loword(m_cantsave)
        jsr     errbox
        sec
        rts
@put:   txy
        sep     #$20
        .a8
        sta     [dp],y
        rep     #$20
        .a16
        inx
        rts
@flush: stx     cpn
        lda     cpn
        beq     :+
        lda     fh
        sta     rblk
        stz     rblk+1
        lda     sbank
        sta     rblk+3
        lda     cpn
        sta     rblk+4
        ptr     rblk
        sys     SYS_WRITE
        bcs     :++
        cmp     cpn
        bne     @short
        stz     cpn
:       ldx     #0
        clc
:       rts
@short: lda     #$47                    ; (a short write: the card is full)
        sec
        rts

; File > Save: to its path, or Save as for a new text -> C set: not saved (a style armed
; and left empty goes first). A file opened under another extension (.TXT) is saved under
; its own name.
do_save:
        jsr     arm_drop
        lda     fpath
        and     #$00FF
        beq     do_saveas
        jmp     save
; File > Save as: the name suggested is the document's as .md ("Untitled.md" for a new
; one); a name typed without an extension gets ".md" (asking before it replaces a file)
do_saveas:
        jsr     arm_drop
        jsr     basename
        ldy     #.loword(dlgbuf)
        jsr     ui_strcpy
        jsr     mdext
        lda     #1
        ldx     #.loword(dlgbuf)
        ldy     #.loword(t_saveas)
        jsr     ui_filedlg
        bcc     :+
        rts
:       jsr     addmd
        bcc     saveto
        rts
; saved to the path in dlgbuf (the document's path from now on) -> C set: not saved
saveto: ldx     #.loword(dlgbuf)
        ldy     #.loword(fpath)
        jsr     ui_strcpy
        jsr     save
        php
        jsr     settitle
        plp
        rts

; the name in dlgbuf with the extension .md (another one replaced, none added)
mdext:  ldx     #.loword(dlgbuf)
        jsr     ui_strlen
        sta     z:t0
        tax
:       dex
        bmi     @add
        lda     dlgbuf,x
        and     #$00FF
        cmp     #'.'
        bne     :-
        lda     dlgbuf+1,x              ; .md already (any case)?
        and     #$DFDF
        cmp     #'M' | ('D' << 8)
        bne     :+
        lda     dlgbuf+3,x
        and     #$00FF
        beq     @out
:       txa
        bra     @put
@add:   lda     z:t0
@put:   cmp     #120
        bcs     @out
        clc
        adc     #.loword(dlgbuf)
        tay
        ldx     #.loword(t_md)
        jmp     ui_strcpy
@out:   rts

; the path in dlgbuf: its name without an extension gets ".md"; a file of that name there
; already: replace it? -> C set: no
addmd:  ldx     #.loword(dlgbuf)
        jsr     ui_strlen
        sta     z:t0
        tax
:       dex
        bmi     @add
        lda     dlgbuf,x
        and     #$00FF
        cmp     #'.'
        beq     @ok
        cmp     #'/'
        bne     :-
@add:   lda     z:t0
        cmp     #124
        bcs     @ok
        clc
        adc     #.loword(dlgbuf)
        tay
        ldx     #.loword(t_md)
        jsr     ui_strcpy
        lda     nodraw                  ; (the self test: no question)
        bne     @ok
        lda     #.loword(dlgbuf)        ; there already?
        sta     stblk
        lda     #.loword(stout)
        sta     stblk+3
        sep     #$20
        .a8
        lda     #^dlgbuf
        sta     stblk+2
        sta     stblk+5
        rep     #$20
        .a16
        ptr     stblk
        sys     SYS_STAT
        bcs     @ok
        ldx     #.loword(dlgbuf)        ; "NAME.md is there already. Replace it?"
        ldy     #.loword(dlgbuf)
:       lda     a:0,x
        and     #$00FF
        beq     :++
        cmp     #'/'
        bne     :+
        txy
        iny
:       inx
        bra     :--
:       tyx
        ldy     #.loword(msgbuf)
        jsr     ui_strcpy
        ldx     #.loword(m_there)
        jsr     append
        ldx     #.loword(al_repl)
        jsr     ui_alert
        cmp     #0
        beq     @ok
        sec
        rts
@ok:    clc
        rts


; File > Export text...: the text without its markup, to a file chosen (suggested: the
; document's name with .TXT) -> C set: not written
do_export:
        jsr     arm_drop
        ldx     #.loword(fpath)         ; the name suggested
        jsr     basename
        ldy     #.loword(dlgbuf)
        jsr     ui_strcpy
        tax                             ; its extension -> .TXT
:       dex
        bmi     :+
        lda     dlgbuf,x
        and     #$00FF
        cmp     #'.'
        bne     :-
        txa
        bra     :++
:       ldx     #.loword(dlgbuf)
        jsr     ui_strlen
:       clc
        adc     #.loword(dlgbuf)
        tay
        ldx     #.loword(t_txt)
        jsr     ui_strcpy
        lda     #1
        ldx     #.loword(dlgbuf)
        ldy     #.loword(t_export)
        jsr     ui_filedlg
        bcc     :+
        rts
:       ldx     #.loword(dlgbuf)
        ; fall through
; the text without its markup written to path X: inline markers and escapes out, a
; heading's #s out, a quote's > made an indent of 4 spaces, trailing spaces out; list
; markers and rules stay (they are plain text conventions)
exportf:
        phx
        ptr     dlgbuf                  ; (Y: our bank)
        plx
        lda     #O_CREATE
        sys     SYS_OPEN
        bcc     :+
        ldx     #.loword(m_cantsave)
        jsr     errbox
        sec
        rts
:       sta     fh
        stz     z:dp
        lda     sbank
        sta     z:dp+2
        stz     cpn
        stz     cpi
@l:     lda     cpi
        cmp     nl
        jcs     @end
        jsr     lget
        lda     cpn                     ; room for the line and its end?
        clc
        adc     llen
        bcs     :+
        cmp     #$F000
        bcc     :++
:       ldx     cpn
        jsr     @flush
        jcs     @err
:       jsr     md_block                ; the line's styles
        jsr     md_inline
        lda     #NONE
        sta     ml_line
        lda     llen                    ; its end without trailing spaces
        clc
        adc     #4
        tay
:       cpy     #4
        beq     :+
        dey
        lda     [lp],y
        and     #$00FF
        cmp     #' '
        beq     :-
        iny
:       sty     z:t3
        ldx     cpn
        lda     m_blk                   ; a quote: 4 spaces
        cmp     #B_QUO
        bne     :+
        lda     #' '
        jsr     @put
        jsr     @put
        jsr     @put
        jsr     @put
:       ldy     #4                      ; the characters shown
@c:     cpy     z:t3
        bcs     @le
        lda     [mb],y
        and     #S_M
        bne     @cn
        lda     [mb],y
        and     #S_P
        beq     @ch
        lda     m_blk                   ; (the markers of lists and rules stay)
        cmp     #B_BUL
        beq     @ch
        cmp     #B_NUM
        beq     @ch
        cmp     #B_RULE
        bne     @cn
@ch:    lda     [lp],y
        jsr     @put
@cn:    iny
        bra     @c
@le:    lda     cpi                     ; the line end (not after the last line)
        inc     a
        cmp     nl
        bcs     :++
        lda     crlf
        beq     :+
        lda     #13
        jsr     @put
:       lda     #10
        jsr     @put
:       stx     cpn
        inc     cpi
        jmp     @l
@end:   ldx     cpn
        jsr     @flush
        bcs     @err
        lda     fh
        sys     SYS_CLOSE
        bcs     @err2
        clc
        rts
@err:   pha
        lda     fh
        sys     SYS_CLOSE
        pla
@err2:  ldx     #.loword(m_cantsave)
        jsr     errbox
        sec
        rts
@put:   phy
        txy
        sep     #$20
        .a8
        sta     [dp],y
        rep     #$20
        .a16
        ply
        inx
        rts
@flush: stx     cpn
        lda     cpn
        beq     :+
        lda     fh
        sta     rblk
        stz     rblk+1
        lda     sbank
        sta     rblk+3
        lda     cpn
        sta     rblk+4
        ptr     rblk
        sys     SYS_WRITE
        bcs     :++
        cmp     cpn
        bne     @short
        stz     cpn
:       ldx     #0
        clc
:       rts
@short: lda     #$47
        sec
        rts

        .segment "RODATA"
t_txt:  .byte   ".TXT", 0
t_md:   .byte   ".md", 0
m_there: .byte  " already exists.", 10, "Replace it?", 0
b_repl: .byte   "Replace", 0
al_repl: .word  2, t_saveas, msgbuf, b_repl, b_cancel, 0

        .segment "BSS"
fpat:   .res    FINDMAX + 2             ; find: the pattern, its length, in lower case
fplen:  .res    2
fplow:  .res    FINDMAX + 2
rpat:   .res    FINDMAX + 2
fbuf:   .res    FINDMAX + 2
rfbuf:  .res    FINDMAX + 2
rwbuf:  .res    FINDMAX + 2
gbuf:   .res    10
sl:     .res    2
sc:     .res    2
s_last: .res    2
rcount: .res    2
wc_c:   .res    4
stblk:  .res    6                       ; stat: the path, the result
stout:  .res    10
