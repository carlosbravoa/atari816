; PRINTER - the print jobs (/BIN/PRINTER.PRG, 0.23): a resizable window "Printer".
;   Programs print by writing a job to "/PRN:NAME"; the I/O processor keeps each finished
;   job as /Printouts/YYYY-MM-DD HH.MM.SS NAME.txt (the classic Atari's printer too:
;   "... Atari.txt"). This window shows them:
;   - the list of jobs: the files in /Printouts whose names do not start with "." (a job
;     still being written does), newest first (name order descending: names start with
;     the date and time), each row its size ("512 bytes", "3 KB") at the left and the name
;     without ".txt". At most MAXJOB rows (the newest ones; a name longer than 63
;     characters is left out). No /Printouts: no jobs;
;   - a preview of the selected job: its text (the first 63 KB, read into a bank of its
;     own) in the fixed 8x12 font, read-only, with a vertical scroll bar. Lines longer than
;     the width wrap after the last blank that fits (a word longer than a row is cut);
;     tabs go to multiples of 8 columns, CR is not shown, FF (a new page) is a row of
;     dashes of its own, other control characters and bytes above 126 show as '?'. The
;     line starts are a table in a second bank (MAXL rows at most). With no jobs it says
;     how to print instead;
;   - buttons Delete (asks first), Send to PC, Open in Edit, Close (Esc), and the same in
;     the File menu; the Delete key deletes too, Enter or a double click opens in Edit.
;   Send to PC is dimmed unless STAT "/PC:" has PCS_PRINT (the gateway makes PDFs). It
;   runs /SYSTEM/PRINTD.PRG with the job's path, waits for it (the title says "sending")
;   and says in an alert what happened (by PRINTD's exit code: 0 "Sent to the PC as
;   Printouts/NAME.pdf", 2 no PC or no print service, 1 an error).
;   Refresh: a timer every second asks STAT "/PRN:" (the number of jobs finished since the
;   I/O processor started; one STAT a tick) and reads /Printouts again only when it
;   changed; the window getting the focus reads it again too and asks the PC again. The
;   selection stays on the same job (when it is gone: the row where it was); the preview
;   is read again only when the selected job changes. At start the newest job is selected,
;   or the job named by the argument ("printer PATH": its last part is looked up in
;   /Printouts). One instance only (SYS_SINGLE): started again, it raises this one.
        .include "horizon.inc"
        .include "ui.inc"

W0      = 560                           ; the content size at start
H0      = 296
MINW    = 400                           ; and at least (the buttons fit)
MINH    = 190
M       = 8                             ; margins
LISTROWS = 5
LISTH   = 2 + LISTROWS * UI_ROWH
PVY     = M + LISTH + M                 ; the preview box's top
TX      = M + 1 + 4                     ; its text's top-left
TY      = PVY + 1 + 2
LH      = 12                            ; a text row
SZW     = 64                            ; the size column (right-aligned) in the list's indent
INDENT  = SZW + 10
DELW    = 72                            ; buttons
SNDW    = 96
EDW     = 104
CLW     = 72
MAXJOB  = 100                           ; jobs listed at most
NMAX    = 64                            ; a job's name: 63 characters at most
DBUFLEN = 1024
CAP     = $FC00                         ; the preview: the first 63 KB
PIECE   = 16384
MAXL    = 32000                         ; preview rows at most
COLMAX  = 120
PMAX    = 128
TICK    = 100                           ; the timer: 1 s

        .segment "ZEROPAGE"
tp:     .res    4                       ; the text bank (offset 0)
lp:     .res    4                       ; the line table's bank (offset 0)
lw:     .res    4                       ; the table, written
ap:     .res    4                       ; the argument string (bank 0)

        .segment "CODE"
        .a16
        .i16
start:  sta     argl
        stx     argx
        sys     SYS_SINGLE              ; one Printer only: the kernel raised the open one
        bcc     :+
        exit    0
:       sys     SYS_WSSTART
        bcc     :+
        print   "printer: no window system\n"
        exit    1
:       sta     wsown
        jsr     ui_init
        sys     SYS_BALLOC              ; the preview's text
        bcs     nomem
        sta     z:tp+2
        stz     z:tp
        sys     SYS_BALLOC              ; its line table
        bcs     nomem
        sta     z:lp+2
        sta     z:lw+2
        stz     z:lp
        jsr     getarg
        ptr     wblk
        sys     SYS_WOPEN
        bcc     :+
        jsr     stopws
        print   "printer: no window\n"
        exit    1
nomem:  jsr     stopws
        print   "printer: not enough memory\n"
        exit    1
:       sta     win
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
:       lda     #0                      ; the name the menu bar shows
        ptr     t_title
        sys     SYS_TNAME
        lda     win
        ptr     menus
        sys     SYS_WMENU
        lda     #W0
        sta     cw
        lda     #H0
        sta     chh
        jsr     geom
        jsr     prnstat
        bcc     :+
        lda     #$FFFF
:       sta     prncnt
        jsr     pccheck
        jsr     scan
        jsr     updstate
        jsr     drawall
        jsr     showsel
        lda     win
        ldx     #TICK
        sys     SYS_WTIMER

loop:   lda     #0
        jsr     ui_getev
        bcs     loop
        lda     ui_ev
        and     #$00FF
        cmp     #WE_WHEEL
        bne     :+
        jsr     wheel
        bra     loop
:       ldx     #.loword(allc)
        jsr     ui_event
        cmp     #UA_CLICK
        bne     @chg
        cpx     #.loword(b_close)
        jeq     quit
        cpx     #.loword(b_del)
        bne     :+
        jsr     delete
        bra     loop
:       cpx     #.loword(b_send)
        bne     :+
        jsr     send
        bra     loop
:       cpx     #.loword(b_edit)
        bne     loop
        jsr     openedit
        bra     loop
@chg:   cmp     #UA_CHANGE
        bne     @open
        cpx     #.loword(lst)
        bne     :+
        jsr     showsel
        bra     loop
:       cpx     #.loword(pv_sb)
        bne     loop
        jsr     pvrows
        jmp     loop
@open:  cmp     #UA_OPEN
        bne     @none
        jsr     openedit
        jmp     loop
@none:  cmp     #UA_NONE
        jne     loop
        lda     ui_ev
        and     #$00FF
        cmp     #WE_CLOSE
        jeq     quit
        cmp     #WE_TICK                ; the counter of finished jobs changed: read again
        bne     :+
        jsr     prnstat
        jcs     loop
        cmp     prncnt
        jeq     loop
        sta     prncnt
        jsr     refresh
        jmp     loop
:       cmp     #WE_FOCUS
        bne     :+
        jsr     pccheck
        jsr     refresh
        jmp     loop
:       cmp     #WE_RESIZE
        bne     :+
        jsr     resize
        jmp     loop
:       cmp     #WE_MENU                ; File: Send to PC, Open in Edit, Delete, -, Close
        bne     @key
        lda     ui_ev+2
        jne     loop
        lda     ui_ev+4
        bne     :+
        jsr     send
        jmp     loop
:       cmp     #1
        bne     :+
        jsr     openedit
        jmp     loop
:       cmp     #2
        bne     :+
        jsr     delete
        jmp     loop
:       cmp     #4
        jeq     quit
        jmp     loop
@key:   cmp     #WE_KEY                 ; the Delete key (down)
        jne     loop
        lda     ui_ev+4
        and     #$0100
        jeq     loop
        lda     ui_ev+2
        cmp     #$4C
        jne     loop
        jsr     delete
        jmp     loop

quit:   lda     win
        sys     SYS_WCLOSE
        jsr     stopws
        exit    0

stopws: lda     wsown
        beq     :+
        sys     SYS_WSSTOP
:       rts

; the wheel: over the list it scrolls the list, elsewhere the preview
wheel:  lda     win
        ptr     mbuf
        sys     SYS_WMOUSE
        ldx     #.loword(lstc)
        lda     mbuf+6                  ; (the pointer's y in the content)
        sec
        sbc     #PVY
        bmi     :+
        ldx     #.loword(pvc)
:       jsr     ui_event
        cmp     #UA_CHANGE
        bne     :+
        cpx     #.loword(pv_sb)
        bne     :+
        jmp     pvrows
:       rts

; ---------------------------------------------------------------- the jobs
; refresh: /Printouts read again, the list drawn, the preview if the selected job changed
refresh:
        jsr     scan
        ldx     #.loword(lst)
        jsr     ui_draw
        jsr     updstate
        jmp     showsel

; the list read again; the selection kept on the same job (selname; from the argument at
; start), else on the same row (clamped), else the first; the list's fields set
scan:   stz     oldrow
        lda     njob
        beq     @read
        lda     lst+LS_SEL
        cmp     njob
        bcs     @read
        sta     oldrow
        jsr     curname
        ldy     #.loword(selname)
        jsr     ui_strcpy
@read:  jsr     readjobs
        lda     #$FFFF
        sta     newsel
        lda     njob
        beq     @set
        jsr     findsel
        bcc     :+
        lda     oldrow
        cmp     njob
        bcc     :+
        lda     njob
        dec     a
:       sta     newsel
@set:   stz     selname                 ; (used once)
        lda     njob
        sta     lst+LS_COUNT
        lda     newsel
        sta     lst+LS_SEL
        cmp     #$FFFF                  ; the selection shown
        bne     :+
        stz     lst+LS_TOP
        rts
:       cmp     lst+LS_TOP
        bcs     :+
        sta     lst+LS_TOP
        rts
:       sec
        sbc     #LISTROWS - 1
        bcc     :+
        cmp     lst+LS_TOP
        bcc     :+
        sta     lst+LS_TOP
:       rts

; the row of the job named selname -> A (C clear); C set: not there
findsel:
        lda     selname
        and     #$00FF
        beq     @no
        ldx     #0
@r:     stx     tmp
        txa
        cmp     njob
        bcs     @no
        asl     a
        tax
        lda     jord,x
        jsr     nameaddr
        tax
        ldy     #.loword(selname)
        jsr     scmp
        beq     @yes
        ldx     tmp
        inx
        bra     @r
@yes:   lda     tmp
        clc
        rts
@no:    sec
        rts

; /Printouts -> the jobs (jname, jsize, jord: newest first)
readjobs:
        stz     njob
        stz     skip
@call:  lda     #.loword(p_dir)         ; {path, buffer, length, skip}
        sta     rdb
        lda     #.loword(dbuf)
        sta     rdb+3
        sep     #$20
        .a8
        lda     #^p_dir
        sta     rdb+2
        lda     #^dbuf
        sta     rdb+5
        rep     #$20
        .a16
        lda     #DBUFLEN
        sta     rdb+6
        lda     skip
        sta     rdb+8
        ptr     rdb
        sys     SYS_READDIR
        jcs     @out                    ; (no /Printouts: no jobs)
        cmp     #0
        beq     @out
        sta     cnt
        clc
        adc     skip
        sta     skip
        ldx     #0
@ent:   stx     dpos                    ; {u32 size, u8 attr, u8 length, name}
        lda     dbuf+4,x
        and     #$0010                  ; folders: no
        bne     @next
        lda     dbuf+5,x
        and     #$00FF
        sta     nlen
        beq     @next
        cmp     #NMAX
        bcs     @next
        lda     dbuf+6,x
        and     #$00FF
        cmp     #'.'                    ; (a job being written, or hidden)
        beq     @next
        ldy     #0
:       lda     dbuf+6,x
        sep     #$20
        .a8
        sta     nbuf,y
        rep     #$20
        .a16
        inx
        iny
        cpy     nlen
        bcc     :-
        lda     #0
        sep     #$20
        .a8
        sta     nbuf,y
        rep     #$20
        .a16
        ldx     dpos
        lda     dbuf,x
        sta     nsz
        lda     dbuf+2,x
        sta     nsz+2
        jsr     insert
@next:  ldx     dpos
        lda     dbuf+5,x
        and     #$00FF
        clc
        adc     #6
        adc     dpos
        tax
        dec     cnt
        jne     @ent
        jmp     @call
@out:   rts

; nbuf (size nsz) into the list at its place (names descending); when the list is full
; the oldest job is dropped (or this one, if it is older than all)
insert: ldx     #0
@find:  stx     ipos
        txa
        lsr     a
        cmp     njob
        bcs     @found
        lda     jord,x
        jsr     nameaddr
        tay
        ldx     #.loword(nbuf)
        jsr     ocmp
        ldx     ipos
        bcs     @found                  ; (nbuf after it in name order: newer)
        inx
        inx
        bra     @find
@found: lda     njob
        cmp     #MAXJOB
        bcc     @room
        cpx     #MAXJOB * 2
        bcs     @out
        lda     jord + (MAXJOB - 1) * 2
        sta     slot
        ldy     #(MAXJOB - 1) * 2
        bra     @shift
@room:  sta     slot
        asl     a
        tay
        inc     njob
@shift: sty     tmp                     ; the rows from X on move down one
        cpx     tmp
        bcs     @put
        lda     jord - 2,y
        sta     jord,y
        dey
        dey
        bra     @shift
@put:   lda     slot
        sta     jord,x
        jsr     nameaddr
        tay
        ldx     #.loword(nbuf)
        jsr     ui_strcpy
        lda     slot
        asl     a
        asl     a
        tax
        lda     nsz
        sta     jsize,x
        lda     nsz+2
        sta     jsize+2,x
@out:   rts

; A = a slot -> A = the address of its name
nameaddr:
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        clc
        adc     #.loword(jname)
        rts

; the selected job -> X = its name (C clear); C set: none
curname:
        lda     lst+LS_SEL
        cmp     njob
        bcs     :+
        asl     a
        tax
        lda     jord,x
        jsr     nameaddr
        tax
        clc
:       rts

; X, Y = strings -> Z set: the same; else C set: X's comes after Y's (bytes, unsigned)
scmp:   sep     #$20
        .a8
:       lda     a:0,x
        cmp     a:0,y
        bne     :+
        inx
        iny
        cmp     #0
        bne     :-
:       rep     #$20
        .a16
        rts

; X, Y = job names -> C set: X's comes after Y's in the list's order: by bytes, but a '.'
; before all others (so "... NAME 2.txt", the second job of the same second, after
; "... NAME.txt")
ocmp:   sep     #$20
        .a8
:       lda     a:0,y
        cmp     #'.'
        bne     :+
        lda     #1
:       sta     och
        lda     a:0,x
        cmp     #'.'
        bne     :+
        lda     #1
:       cmp     och
        bne     :+
        inx
        iny
        cmp     #0
        bne     :---
        clc
:       rep     #$20
        .a16
        rts

; X = a job's name, Y = a buffer -> the name there without ".txt" (any case)
basecpy:
        sty     tmp2
        jsr     ui_strcpy
        cmp     #5
        bcc     @out
        clc
        adc     tmp2
        sec
        sbc     #4
        tax
        lda     a:0,x
        and     #$DFFF
        cmp     #'.' | ('T' << 8)
        bne     @out
        lda     a:2,x
        and     #$DFDF
        cmp     #'X' | ('T' << 8)
        bne     @out
        sep     #$20
        .a8
        stz     a:0,x
        rep     #$20
        .a16
@out:   rts

; X = a job's name -> pbuf = "/Printouts/NAME", qbuf = the same in double quotes
jobpath:
        phx
        ldx     #.loword(p_dirsl)
        ldy     #.loword(pbuf)
        jsr     ui_strcpy
        clc
        adc     #.loword(pbuf)
        tay
        plx
        jsr     ui_strcpy
        lda     #'"'
        sta     qbuf                    ; ('"', 0)
        ldx     #.loword(pbuf)
        ldy     #.loword(qbuf + 1)
        jsr     ui_strcpy
        clc
        adc     #.loword(qbuf + 1)
        tax
        lda     #'"'
        sta     a:0,x                   ; ('"', 0)
        rts

; the list's row callback: A = row -> X = its text (the name without ".txt"); the size
; drawn right-aligned in the indent
lsrow:  asl     a
        tax
        lda     jord,x
        sta     slot
        jsr     fmtsize
        lda     #C_BLACK | (C_WHITE << 8)
        ldx     z:ui_rsel
        beq     :+
        lda     lst+CT_FLAGS
        and     #UF_FOCUS
        beq     :++
        lda     #C_WHITE | (C_SELECT << 8)
:       sta     ink
        bra     :++
:       lda     #C_BLACK | (C_LIGHT << 8)
        sta     ink
:
        lda     z:ui_w
        pha
        lda     z:ui_h
        pha
        lda     z:ui_x
        pha
        lda     z:ui_y
        pha
        clc
        adc     #3
        sta     z:ui_y
        stz     z:ui_font
        lda     #INDENT                 ; the paper under the text, as the name's text has it
        sta     z:ui_w
        lda     #UI_LINE
        sta     z:ui_h
        lda     ink
        and     #$FF00
        ora     #WD_FILL
        jsr     ui_rect
        ldx     #.loword(szbuf)
        lda     #0
        jsr     ui_twidth
        eor     #$FFFF
        sec
        adc     #SZW
        bpl     :+
        lda     #0
:       clc
        adc     z:ui_x
        sta     z:ui_x
        ldx     #.loword(szbuf)
        lda     ink
        jsr     ui_text
        pla
        sta     z:ui_y
        pla
        sta     z:ui_x
        pla
        sta     z:ui_h
        pla
        sta     z:ui_w
        lda     slot
        jsr     nameaddr
        tax
        ldy     #.loword(rowbuf)
        jsr     basecpy
        ldx     #.loword(rowbuf)
        rts

; the size of slot -> szbuf: "N bytes" below 1 KB, "N KB" (rounded up), from 10 MB "N MB"
fmtsize:
        lda     slot
        asl     a
        asl     a
        tax
        ldy     #.loword(szbuf)
        lda     jsize+2,x
        bne     @kb
        lda     jsize,x
        cmp     #1024
        bcs     @kb
        jsr     decat
        ldx     #.loword(s_bytes)
        jmp     strat
@kb:    lda     jsize,x                 ; + 1023, / 1024
        clc
        adc     #1023
        sta     tmp
        lda     jsize+2,x
        adc     #0
        cmp     #160
        bcs     @mb
        xba                             ; hi << 6 | lo >> 10
        and     #$FF00
        lsr     a
        lsr     a
        sta     tmp2
        lda     tmp
        xba
        and     #$00FF
        lsr     a
        lsr     a
        ora     tmp2
        jsr     decat
        ldx     #.loword(s_kb)
        jmp     strat
@mb:    lda     jsize,x                 ; + $FFFFF, / $100000
        clc
        adc     #$FFFF
        lda     jsize+2,x
        adc     #$000F
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        jsr     decat
        ldx     #.loword(s_mb)
        jmp     strat

; ---------------------------------------------------------------- states, the PC
; STAT "/PRN:" -> A = the jobs finished (C set: an older firmware)
prnstat:
        ldx     #.loword(p_prn)
        jmp     stat

; STAT "/PC:" -> pcok = its print service is there
pccheck:
        ldx     #.loword(p_pc)
        jsr     stat
        bcs     :+
        lda     stb
        and     #PCS_PRINT
        sta     pcok
        rts
:       stz     pcok
        rts

; X = path -> stb (STAT), A = the size's low word. C set: an error
stat:   stx     sblk
        lda     #.loword(stb)
        sta     sblk+3
        sep     #$20
        .a8
        lda     #^stb
        sta     sblk+2
        sta     sblk+5
        rep     #$20
        .a16
        ptr     sblk
        sys     SYS_STAT
        rts

; the buttons and menu items dimmed or not: Delete, Open in Edit need a job, Send to PC
; also the PC's print service
updstate:
        lda     #UF_DIM
        ldx     njob
        beq     :+
        lda     #0
:       sta     want
        ldx     #.loword(b_del)
        ldy     #2
        jsr     setdim
        ldx     #.loword(b_edit)
        ldy     #1
        jsr     setdim
        lda     pcok
        bne     :+
        lda     #UF_DIM
        sta     want
:       ldx     #.loword(b_send)
        ldy     #0
        ; fall through
; X = button, Y = its File menu item, want = UF_DIM or 0: changed -> drawn, the item too
setdim: lda     a:CT_FLAGS,x
        and     #UF_DIM
        cmp     want
        beq     @out
        lda     a:CT_FLAGS,x
        eor     #UF_DIM
        sta     a:CT_FLAGS,x
        phy
        jsr     ui_draw
        pla
        xba
        tax                             ; (menu 0 | item << 8)
        ldy     #0
        lda     want
        beq     :+
        ldy     #MS_DIM
:       lda     win
        sys     SYS_WMSTATE
@out:   rts

; ---------------------------------------------------------------- the actions
; Delete: the selected job, after a question
delete: jsr     curname
        bcs     @out
        phx
        jsr     jobpath
        plx
        ldy     #.loword(dname)
        jsr     basecpy
        ldx     #.loword(m_del)         ; "Delete the print job NAME?"
        ldy     #.loword(albuf)
        jsr     ui_strcpy
        ldx     #.loword(dname)
        jsr     alapp
        ldx     #.loword(m_qm)
        jsr     alapp
        ldx     #.loword(al_del)
        jsr     ui_alert
        cmp     #0
        bne     @out
        ptr     pbuf
        sys     SYS_DELETE
        bcc     :+
        sta     err
        ldx     #.loword(m_nodel)       ; "NAME could not be deleted (error $xx)."
        jsr     errmsg
        lda     #AL_ERROR
        jsr     alert
:       jmp     refresh
@out:   rts

; Send to PC: PRINTD with the job's path, waited for; an alert says how it went
send:   lda     pcok
        beq     @out
        jsr     curname
        bcc     :+
@out:   rts
:       phx
        jsr     jobpath
        plx
        ldy     #.loword(dname)
        jsr     basecpy
        lda     win
        ptr     t_send
        sys     SYS_WTITLE
        lda     #.loword(qbuf)
        sta     z:u_arg
        sep     #$20
        .a8
        lda     #^qbuf
        sta     z:u_arg+2
        rep     #$20
        .a16
        ldx     #.loword(p_printd)
        ldy     #^p_printd
        lda     #1
        jsr     spawn
        bcc     :+
        pha
        jsr     untitle
        pla
        ldx     #.loword(s_printd)
        jmp     ui_spawnerr
:       sys     SYS_WAIT
        bcc     :+
        lda     #$FFFF
:       sta     err
        jsr     untitle
        lda     err
        bne     @e2
        ldx     #.loword(m_sent)        ; "Sent to the PC as Printouts/NAME.pdf"
        ldy     #.loword(albuf)
        jsr     ui_strcpy
        ldx     #.loword(dname)
        jsr     alapp
        ldx     #.loword(m_pdf)
        jsr     alapp
        lda     #AL_INFO
        bra     @show
@e2:    cmp     #2
        bne     @e1
        stz     pcok
        ldx     #.loword(m_nopdf)
        ldy     #.loword(albuf)
        jsr     ui_strcpy
        lda     #AL_WARN
        bra     @show
@e1:    cmp     #1
        bne     @e3
        ldx     #.loword(dname)         ; "NAME was not sent to the PC: ..."
        ldy     #.loword(albuf)
        jsr     ui_strcpy
        ldx     #.loword(m_fail)
        jsr     alapp
        lda     #AL_ERROR
        bra     @show
@e3:    ldx     #.loword(dname)         ; "... (PRINTD ended with code $xxxx)."
        ldy     #.loword(albuf)
        jsr     ui_strcpy
        ldx     #.loword(m_code)
        jsr     alapp
        lda     err
        xba
        jsr     hexapp
        lda     err
        jsr     hexapp
        ldx     #.loword(m_rpar)
        jsr     alapp
        lda     #AL_ERROR
@show:  jsr     alert
        jsr     pccheck
        jmp     updstate

untitle:
        lda     win
        ptr     t_title
        sys     SYS_WTITLE
        rts

; Open in Edit: Edit started with the job's path
openedit:
        jsr     curname
        bcs     :+
        jsr     jobpath
        ldx     #.loword(p_edit)
        ldy     #.loword(qbuf)
        lda     #0
        jmp     ui_launch
:       rts

; A = AL_* kind: the alert with albuf and OK
alert:  sta     al_res
        ldx     #.loword(al_res)
        jmp     ui_alert

; X = text after the job's name, err: albuf = "NAME" text "$xx)."
errmsg: phx
        ldx     #.loword(dname)
        ldy     #.loword(albuf)
        jsr     ui_strcpy
        plx
        jsr     alapp
        lda     err
        jsr     hexapp
        ldx     #.loword(m_rpar)
        jmp     alapp

; ---------------------------------------------------------------- the window's layout
; the geometry from cw x chh
geom:   lda     cw
        sec
        sbc     #2 * M
        sta     lst+CT_W
        sta     pvw
        lda     chh
        sec
        sbc     #PVY + M + UI_BTNH + M
        sta     pvh
        lda     pvw
        sec
        sbc     #1 + UI_SBW - M
        sta     pv_sb+CT_X
        lda     pvh
        dec     a
        dec     a
        sta     pv_sb+CT_H
        lda     pvw                     ; text columns and rows
        sec
        sbc     #2 + UI_SBW + 8
        lsr     a
        lsr     a
        lsr     a
        cmp     #COLMAX
        bcc     :+
        lda     #COLMAX
:       sta     ncols
        lda     pvh
        sec
        sbc     #6
        ldx     #0
:       cmp     #LH
        bcc     :+
        sbc     #LH
        inx
        bra     :-
:       stx     nrows
        lda     chh                     ; the buttons
        sec
        sbc     #M + UI_BTNH
        sta     b_del+CT_Y
        sta     b_send+CT_Y
        sta     b_edit+CT_Y
        sta     b_close+CT_Y
        lda     cw
        sec
        sbc     #M + CLW
        sta     b_close+CT_X
        rts

; WE_RESIZE: the new size (at least MINW x MINH), the text wrapped again when the width
; in columns changed (the first row shown stays where it was in the text), all drawn
resize: lda     ui_ev+2
        sta     cw
        lda     ui_ev+4
        sta     chh
        stz     tmp
        lda     cw
        cmp     #MINW
        bcs     :+
        lda     #MINW
        sta     cw
        inc     tmp
:       lda     chh
        cmp     #MINH
        bcs     :+
        lda     #MINH
        sta     chh
        inc     tmp
:       lda     tmp                     ; too small: back to the least size
        beq     :+
        lda     #$8000
        sta     gblk
        lda     cw
        sta     gblk+4
        lda     chh
        sta     gblk+6
        lda     win
        ptr     gblk
        sys     SYS_WGEOM
:       lda     ncols
        pha
        jsr     geom
        pla
        cmp     ncols
        beq     @same
        lda     pv_sb+SB_POS            ; the top row's place in the text
        jsr     linestart
        sta     tmp2
        jsr     layout
        ldy     #0                      ; the row that holds it now
        ldx     #0
:       inx
        cpx     nl
        bcs     :+
        iny
        iny
        lda     [lp],y
        cmp     tmp2
        beq     :++
        bcc     :-
:       dex
:       stx     pv_sb+SB_POS
@same:  jsr     setsb
        jmp     drawall

; A = row -> A = its offset in the text
linestart:
        cmp     nl
        bcc     :+
        lda     #0
        rts
:       asl     a
        tay
        lda     [lp],y
        rts

; the preview's scroll bar: max, page, the position clamped
setsb:  lda     nl
        sec
        sbc     nrows
        bcs     :+
        lda     #0
:       sta     pv_sb+SB_MAX
        lda     nrows
        sta     pv_sb+SB_PAGE
        lda     #1
        sta     pv_sb+SB_STEP
        lda     pv_sb+SB_POS
        cmp     pv_sb+SB_MAX
        bcc     :+
        lda     pv_sb+SB_MAX
        sta     pv_sb+SB_POS
:       rts

; everything drawn (the screen holds while it is)
drawall:
        lda     #1
        sys     SYS_WSHOLD
        lda     win
        sta     z:ui_win
        stz     z:ui_x
        stz     z:ui_y
        lda     cw
        sta     z:ui_w
        lda     chh
        sta     z:ui_h
        lda     #WD_FILL | (C_BODY << 8)
        jsr     ui_rect
        ldx     #.loword(allc)
        jsr     ui_drawall
        jsr     pvbox
        lda     #0
        sys     SYS_WSHOLD
        rts

; the preview's box: sunken, white, the rows (not its scroll bar)
pvbox:  lda     win
        sta     z:ui_win
        lda     #M
        sta     z:ui_x
        lda     #PVY
        sta     z:ui_y
        lda     pvw
        sta     z:ui_w
        lda     pvh
        sta     z:ui_h
        lda     #1
        jsr     ui_bevel
        lda     #M + 1
        sta     z:ui_x
        lda     #PVY + 1
        sta     z:ui_y
        lda     pvw
        sec
        sbc     #2 + UI_SBW
        sta     z:ui_w
        lda     pvh
        dec     a
        dec     a
        sta     z:ui_h
        lda     #WD_FILL | (C_WHITE << 8)
        jsr     ui_rect
        ; fall through
; the preview's rows from the scroll bar's position
pvrows: lda     win
        sta     z:ui_win
        lda     #1
        sta     z:ui_font
        stz     row
@r:     lda     row
        cmp     nrows
        bcs     @out
        clc
        adc     pv_sb+SB_POS
        jsr     render
        ora     #C_WHITE << 8
        pha
        lda     #TX
        sta     z:ui_x
        lda     row                     ; y = TY + 12 row
        asl     a
        adc     row
        asl     a
        asl     a
        adc     #TY
        sta     z:ui_y
        pla
        ldx     #.loword(rowbuf)
        jsr     ui_text
        inc     row
        bra     @r
@out:   stz     z:ui_font
        rts

; ---------------------------------------------------------------- the preview's text
; the preview for the selected job: read (when it is not the one shown), wrapped, drawn
showsel:
        lda     njob
        bne     @job
        lda     pvkind                  ; no jobs: how to print
        cmp     #1
        beq     @out
        lda     #1
        sta     pvkind
        stz     tlen
        ldx     #.loword(m_empty)
        jsr     bankapp
        bra     @new
@job:   jsr     curname
        bcs     @out
        lda     pvkind
        cmp     #2
        bne     @load
        ldy     #.loword(shown)
        jsr     scmp
        beq     @out
        jsr     curname
@load:  ldy     #.loword(shown)
        jsr     ui_strcpy
        lda     #2
        sta     pvkind
        jsr     load
@new:   jsr     layout
        stz     pv_sb+SB_POS
        jsr     setsb
        lda     #1
        sys     SYS_WSHOLD
        jsr     pvbox
        ldx     #.loword(pv_sb)
        jsr     ui_draw
        lda     #0
        sys     SYS_WSHOLD
@out:   rts

; the job named shown -> the text bank (tlen): its first CAP bytes (then a note if there is
; more), or a message saying why it cannot be read
load:   ldx     #.loword(shown)
        jsr     jobpath
        stz     tlen
        ptr     pbuf
        lda     #O_READ
        sys     SYS_OPEN
        bcs     @err
        sta     fh
@rd:    lda     #CAP
        sec
        sbc     tlen
        beq     @full
        cmp     #PIECE
        bcc     :+
        lda     #PIECE
:       sta     want
        sta     rw+4
        lda     fh
        sta     rw
        lda     tlen
        sta     rw+1
        sep     #$20
        .a8
        lda     z:tp+2
        sta     rw+3
        rep     #$20
        .a16
        ptr     rw
        sys     SYS_READ
        bcs     @rerr
        pha
        clc
        adc     tlen
        sta     tlen
        pla
        cmp     want
        beq     @rd
        lda     fh
        sys     SYS_CLOSE
        rts
@full:  lda     fh                      ; more than CAP: a note at the end
        sys     SYS_CLOSE
        lda     lst+LS_SEL              ; (the list's size)
        asl     a
        tax
        lda     jord,x
        asl     a
        asl     a
        tax
        lda     jsize+2,x
        bne     :+
        lda     jsize,x
        cmp     #CAP + 1
        bcc     @out
:       ldx     #.loword(m_more)
        jmp     bankapp
@rerr:  sta     err
        lda     fh
        sys     SYS_CLOSE
        lda     err
@err:   sta     err                     ; "This job cannot be read (error $xx)."
        stz     tlen
        ldx     #.loword(m_cant)
        ldy     #.loword(albuf)
        jsr     ui_strcpy
        lda     err
        jsr     hexapp
        ldx     #.loword(m_rpar)
        jsr     alapp
        ldx     #.loword(albuf)
        jmp     bankapp
@out:   rts

; X = a string appended to the text bank at tlen
bankapp:
        ldy     tlen
:       lda     a:0,x
        and     #$00FF
        beq     :+
        sep     #$20
        .a8
        sta     [tp],y
        rep     #$20
        .a16
        inx
        iny
        bra     :-
:       sty     tlen
        rts

; the text (tlen bytes) -> the line table: nl rows, entry i = the offset of row i, entry nl
; = the end. A row ends at LF; at FF (a row of its own); when the next character does not
; fit in ncols columns: after the last blank of the row (else there; a blank that does not
; fit is dropped); CR has no width, a tab goes to the next multiple of 8
layout: stz     z:lw
        stz     nl
        ldy     #0
        tya
        jsr     @nl
@loop:  cpy     tlen
        jcs     @end
        lda     nl
        cmp     #MAXL
        jcs     @end
        lda     [tp],y
        and     #$00FF
        cmp     #10
        jeq     @lf
        cmp     #13
        jeq     @cr
        cmp     #12
        jeq     @ff
        sta     ch
        ldx     #1
        cmp     #9
        bne     :+
        lda     col
        and     #7
        eor     #7
        inc     a
        tax
:       stx     cwid
        txa
        clc
        adc     col
        cmp     ncols
        beq     @fits
        bcc     @fits
        lda     ch                      ; it does not fit
        cmp     #' '
        beq     @blank
        cmp     #9
        beq     @blank
        lda     lastsp
        beq     @hard
        tya                             ; after the last blank: the word moves down
        sec
        sbc     lastsp
        pha
        lda     lastsp
        jsr     @nl
        pla
        sta     col
        bra     @fits
@hard:  tya
        jsr     @nl
@fits:  lda     ch
        cmp     #' '
        beq     :+
        cmp     #9
        bne     :++
:       tya
        inc     a
        sta     lastsp
:       lda     col
        clc
        adc     cwid
        sta     col
        iny
        jmp     @loop
@blank: iny                             ; (dropped)
        tya
        jsr     @nl
        jmp     @loop
@cr:    iny
        jmp     @loop
@lf:    iny
        cpy     tlen
        bcs     @end
        tya
        jsr     @nl
        jmp     @loop
@ff:    cpy     lstart                  ; a row of its own
        beq     :+
        tya
        jsr     @nl
:       iny
        cpy     tlen
        bcs     @end
        tya
        jsr     @nl
        jmp     @loop
@end:   tya                             ; the end
        sta     [lw]
        rts
@nl:    sta     [lw]                    ; a row starts at A
        inc     z:lw
        inc     z:lw
        sta     lstart
        stz     col
        stz     lastsp
        inc     nl
        rts

; A = a row -> rowbuf: ncols characters (blanks after its text); A = the ink
render: stz     ink
        cmp     nl
        bcc     :+
        ldx     #0
        jmp     @pad
:       asl     a
        tay
        lda     [lp],y
        sta     tmp
        iny
        iny
        lda     [lp],y
        sta     tmp2                    ; the row's end
        ldy     tmp
        ldx     #0
        cpy     tmp2
        bcs     @pad
        lda     [tp],y
        and     #$00FF
        cmp     #12
        bne     @ch
        lda     #C_MID                  ; FF: a row of dashes
        sta     ink
:       lda     #'-'
        jsr     @put
        cpx     ncols
        bcc     :-
        bra     @end
@ch:    cpy     tmp2
        bcs     @pad
        cpx     ncols
        bcs     @pad
        lda     [tp],y
        and     #$00FF
        iny
        cmp     #9
        beq     @tab
        cmp     #' '
        bcc     @ctl
        cmp     #127
        bcc     :+
@q:     lda     #'?'
:       jsr     @put
        bra     @ch
@ctl:   cmp     #10
        beq     @ch
        cmp     #13
        beq     @ch
        cmp     #12
        beq     @ch
        bra     @q
@tab:   lda     #' '
        jsr     @put
        cpx     ncols
        bcs     @ch
        txa
        and     #7
        bne     @tab
        bra     @ch
@pad:   cpx     ncols
        bcs     @end
        lda     #' '
        jsr     @put
        bra     @pad
@end:   lda     #0
        jsr     @put
        lda     ink
        rts
@put:   sep     #$20
        .a8
        sta     rowbuf,x
        rep     #$20
        .a16
        inx
        rts

; ---------------------------------------------------------------- the argument
; "printer [PATH]": selname = PATH's last part (blanks around it and quotes taken off)
getarg: stz     selname
        lda     argl
        beq     @out
        lda     argx
        sta     z:ap
        stz     z:ap+2
        ldy     #0
:       lda     [ap],y
        and     #$00FF
        cmp     #' '
        bne     :+
        iny
        bra     :-
:       stz     tmp
        cmp     #'"'
        bne     :+
        inc     tmp
        iny
:       ldx     #0
@cp:    lda     [ap],y
        and     #$00FF
        beq     @end
        cmp     #'"'
        bne     :+
        lda     tmp
        bne     @end
        lda     #'"'
:       cmp     #'/'                    ; (a '/' starts the name again)
        bne     :+
        ldx     #0
        bra     @nx
:       cpx     #NMAX - 1
        bcs     @nx
        sep     #$20
        .a8
        sta     selname,x
        rep     #$20
        .a16
        inx
@nx:    iny
        bra     @cp
@end:   sep     #$20                    ; blanks after it off
        .a8
:       stz     selname,x
        cpx     #0
        beq     :+
        dex
        lda     selname,x
        cmp     #' '
        beq     :-
:       rep     #$20
        .a16
@out:   rts

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

; A = a byte appended to albuf in hex (two digits)
hexapp: and     #$00FF
        pha
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
        lda     #0
        jmp     putc
@dig:   and     #$000F
        tax
        lda     hexd,x
        ; fall through
; A = a byte stored at Y, Y + 1
putc:   sep     #$20
        .a8
        sta     a:0,y
        rep     #$20
        .a16
        iny
        rts

; A = number stored at Y in decimal -> Y at its end (zero-terminated)
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

        .segment "RODATA"
t_title: .byte  "Printer", 0
t_send: .byte   "Printer: sending to the PC...", 0
p_dir:  .byte   "/Printouts", 0
p_dirsl: .byte  "/Printouts/", 0
p_prn:  .byte   "/PRN:", 0
p_pc:   .byte   "/PC:", 0
p_printd: .byte "/SYSTEM/PRINTD.PRG", 0
p_edit: .byte   "/BIN/EDIT.PRG", 0
s_printd: .byte "PRINTD", 0
s_delete: .byte "Delete", 0
s_send: .byte   "Send to PC", 0
s_edit: .byte   "Open in Edit", 0
s_close: .byte  "Close", 0
s_cancel: .byte "Cancel", 0
s_ok:   .byte   "OK", 0
s_bytes: .byte  " bytes", 0
s_kb:   .byte   " KB", 0
s_mb:   .byte   " MB", 0
m_empty: .byte  "No print jobs.", 10, 10
        .byte   "Programs print with File > Print; the Atari prints with LPRINT. "
        .byte   "Each job appears here.", 0
m_more: .byte   10, 10, "(The preview shows the first 63 KB only.)", 0
m_cant: .byte   "This job cannot be read (error $", 0
m_rpar: .byte   ").", 0
m_del:  .byte   "Delete the print job", 10, 0
m_qm:   .byte   "?", 0
m_nodel: .byte  " could not be deleted (error $", 0
m_sent: .byte   "Sent to the PC as Printouts/", 0
m_pdf:  .byte   ".pdf", 0
m_nopdf: .byte  "Not sent: there is no PC link, or the PC's gateway", 10
        .byte   "cannot make PDFs.", 0
m_fail: .byte   " was not sent to the PC:", 10
        .byte   "the job could not be read, or writing to the PC failed", 10
        .byte   "(the PC link may have been lost).", 0
m_code: .byte   " was not sent to the PC (PRINTD ended with code $", 0
hexd:   .byte   "0123456789ABCDEF"
pow:    .word   10000, 1000, 100, 10, 1
al_del: .word   AL_QUESTION, t_title, albuf, s_delete, s_cancel, 0

menus:  .byte   "File", 0, MS_STATE | MS_DIM, "Send to PC", 0
        .byte   MS_STATE | MS_DIM, "Open in Edit", 9, "Enter", 0
        .byte   MS_STATE | MS_DIM, "Delete", 9, "Del", 0, "-", 0, "Close", 9, "Esc", 0, 0, 0

        .segment "DATA"
wblk:   .word   40, 22, W0, H0
        .faraddr t_title
        .byte   WF_RESIZE
al_res: .word   AL_INFO, t_title, albuf, s_ok, 0, 0
allc:   .addr   lst, pv_sb, b_del, b_send, b_edit, b_close, 0
lstc:   .addr   lst, 0                  ; (the wheel over the list)
pvc:    .addr   pv_sb, 0                ; (over the preview)
lst:    .byte   UT_LIST, 0
        .word   M, M, W0 - 2 * M, LISTH, UF_FOCUS
        .word   0, $FFFF, 0, lsrow, INDENT, 0
        .res    SB_SIZE
pv_sb:  .byte   UT_VSCROLL, 0
        .word   0, PVY + 1, UI_SBW, 0, 0
        .word   0, 0, 1, 1, 0, 0
b_del:  .byte   UT_BUTTON, 0
        .word   M, 0, DELW, UI_BTNH, UF_DIM
        .addr   s_delete
b_send: .byte   UT_BUTTON, 0
        .word   M + DELW + M, 0, SNDW, UI_BTNH, UF_DIM
        .addr   s_send
b_edit: .byte   UT_BUTTON, 0
        .word   M + DELW + M + SNDW + M, 0, EDW, UI_BTNH, UF_DIM
        .addr   s_edit
b_close: .byte  UT_BUTTON, 0
        .word   0, 0, CLW, UI_BTNH, UF_CANCEL
        .addr   s_close

        .segment "BSS"
argl:   .res    2
argx:   .res    2
wsown:  .res    2
win:    .res    2
cw:     .res    2                       ; the content's size
chh:    .res    2
pvw:    .res    2                       ; the preview box's size
pvh:    .res    2
ncols:  .res    2                       ; its text columns and rows
nrows:  .res    2
prncnt: .res    2                       ; STAT /PRN: last seen
pcok:   .res    2                       ; the PC can make PDFs
want:   .res    2
err:    .res    2
tmp:    .res    2
tmp2:   .res    2
any:    .res    2
dig:    .res    2
row:    .res    2
ink:    .res    2
slot:   .res    2
ipos:   .res    2
oldrow: .res    2
newsel: .res    2
skip:   .res    2
cnt:    .res    2
dpos:   .res    2
nlen:   .res    2
nsz:    .res    4
fh:     .res    2
tlen:   .res    2                       ; the preview's text and rows
nl:     .res    2
pvkind: .res    2                       ; what it shows: 0 nothing, 1 "no jobs", 2 the job shown
lstart: .res    2
col:    .res    2
lastsp: .res    2
ch:     .res    2
och:    .res    2
cwid:   .res    2
njob:   .res    2
sblk:   .res    6
rw:     .res    6
rdb:    .res    10
gblk:   .res    8
mbuf:   .res    10
stb:    .res    10
jord:   .res    MAXJOB * 2              ; the rows: slots, newest first
jsize:  .res    MAXJOB * 4
jname:  .res    MAXJOB * NMAX
nbuf:   .res    NMAX
selname: .res   NMAX
shown:  .res    NMAX
dname:  .res    NMAX
szbuf:  .res    16
rowbuf: .res    COLMAX + 8
pbuf:   .res    PMAX
qbuf:   .res    PMAX + 4
albuf:  .res    320
dbuf:   .res    DBUFLEN
