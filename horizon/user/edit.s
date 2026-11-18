; EDIT - the text editor (/BIN/EDIT.PRG): a resizable window, "edit [path]".
;
; The text: a table of lines plus a heap of line blocks, all in banks of their own.
;   - Line table: two banks, entry i at offset 2 i: the block's offset in bank LO, its bank
;     in bank HI. At most MAXLINES lines (16-bit line numbers everywhere).
;   - Line block: {u16 capacity, u16 length, the bytes}, never crossing a bank. A line that
;     outgrows its block moves to a new one (capacity + 1/4 + 16); the old one is garbage.
;   - Heap: up to MAXHB banks (768 KB) filled from the bottom; when they are full, the live
;     lines are copied into fresh banks in line order (compaction) and the old ones freed.
;     So the text can be about 700 KB; a line at most MAXLEN bytes (longer lines are
;     broken when loaded or pasted).
;   - Two scratch banks: file and clipboard data (SB), the tail of a line being split (TB).
;   - The undo bank (UB): the undo stack (below).
; Lines hold no line ends. A file is read in 4 KB pieces: LF ends a line, a CR before an LF
; is dropped (and remembered: the file is written back with CR LF); other bytes are kept
; (shown as '?', tabs as spaces to the next multiple of 8 columns). Saving joins the lines
; with LF (CR LF), so a file ending in a line end ends with an empty last line here.
; Cursor and selection: (line, column) pairs, cl:cc the cursor, al:ac the other end.
;
; The view. Rows of LH pixels show the text in the fixed 8x12 font (default) or the UI
; font. Without word wrap a row is a line, and hcol is the first display column shown (a
; multiple of 8, so a tab never straddles it). With word wrap (View > Word wrap: the file
; is not changed) a line is shown in as many rows as it needs: a row ends after the last
; space that fits the width (a word longer than the row is cut), tabs go to multiples of
; 8 columns from the row's start. A row is (line, start column, end column); the view
; starts at row (top, toff). Up / Down, PgUp / PgDn, Home / End move by rows; a cursor at
; a row's end column that is not the line's end is shown at the start of the next row.
;
; Drawing. Every change only marks what it touched (dirty lines, or a line from a column
; on: typing redraws the end of one line), and the view is redrawn when no event waits
; (so keys that come faster than drawing are taken together: one scroll for all of them).
; Redrawing compares the rows wanted (layout) with the rows drawn: when the view moved by
; less than a page, the rows that stay move with one copy (WD_COPY), and only rows that
; came in or changed are drawn. The scroll bar moves only its thumb, the status line
; (line, column, lines, modified, wrap) is drawn when its text changes.
;
; Undo. Every change of the text is a record on the undo stack in UB: {u8 kind (1 insert,
; 2 delete), u8 flags, u16 line, column (where), u16 line, column (the end: after the
; insert / of the range deleted), u16 n, n bytes of text (LF between lines), u16 the
; record's size}. The changes of one action form a group (flags bit 0: joined to the
; record below). Characters typed in a row are one record per word (a space ends it), so
; are Backspaces and Deletes in a row. Undo takes records back, Redo applies them again;
; a new change drops what Redo had. When the bank is full the oldest records go; a change
; larger than the bank empties the stack (it cannot be undone).
        .include "horizon.inc"
        .include "ui.inc"
        .import ui_cw                   ; (the UI font's advances: the walk reads them)

MAXLINES = 32000
MAXLEN  = 16000
.ifndef MAXHB
MAXHB   = 12
.endif
LH      = 12                            ; line height
TOPM    = 2                             ; margins of the text area
LEFTM   = 4
STH     = 14                            ; the status line's height
MAXVIS  = 32                            ; rows at most
CHUNK   = 4096
RBUFMAX = 320
NONE    = $FFFF
UBSIZE  = $FF00                         ; the undo stack's room
U_INS   = 1                             ; undo record kinds and flags
U_DEL   = 2
UF_JOIN = 1
UF_TYPE = 2
UF_BS   = 4
UF_DELK = 8
FINDMAX = 64

        .segment "CODE"
        .a16
        .i16
start:  sta     argl
        stx     argx
        sys     SYS_WSSTART
        bcc     :+
        print   "edit: no window system\n"
        exit    1
:       sta     wsown
        jsr     ui_init
        sys     SYS_BALLOC              ; the line table, the scratch banks, the undo bank
        jcs     nomem
        sta     z:zlo+2
        stz     z:zlo
        sys     SYS_BALLOC
        jcs     nomem
        sta     z:zhi+2
        stz     z:zhi
        sys     SYS_BALLOC
        jcs     nomem
        sta     sbank
        sys     SYS_BALLOC
        jcs     nomem
        sta     tbank
        sys     SYS_BALLOC
        jcs     nomem
        sta     z:ub+2
        stz     z:ub
        jsr     tx_reset
        bcs     nomem
        jsr     getarg
        ptr     wopen
        sys     SYS_WOPEN
        bcc     :+
        jsr     stopws
        print   "edit: no window\n"
        exit    1
:       sta     win
        sep     #$20
        .a8
        sta     es_sb+CT_WIN
        rep     #$20
        .a16
        lda     win
        ptr     menus
        sys     SYS_WMENU
        lda     wopen+4
        sta     cw
        lda     wopen+6
        sta     chh
        jsr     geom
        lda     fpath
        and     #$00FF
        beq     :+
        jsr     loading
        jsr     load
:       jsr     settitle
        jsr     redraw_all
        jmp     loop

nomem:  jsr     stopws
        print   "edit: not enough memory\n"
        exit    1

stopws: lda     wsown
        beq     :+
        sys     SYS_WSSTOP
:       rts

quit:   lda     win
        sys     SYS_WCLOSE
        jsr     stopws
        exit    0

; the argument: a path (quotes, or "\ " for a space) -> fpath, absolute
getarg: stz     fpath
        lda     argl
        beq     @out
        ldx     argx
        jsr     args_init
        jsr     str_skip
        ldx     #0
        cmp     #'"'
        bne     @pl
        inc     z:u_p
@q:     lda     [u_p]
        and     #$00FF
        beq     @end
        cmp     #'"'
        beq     @end
        jsr     @put
        inc     z:u_p
        bra     @q
@pl:    lda     [u_p]
        and     #$00FF
        beq     @trim
        cmp     #$5C                    ; backslash
        bne     :+
        inc     z:u_p
        lda     [u_p]
        and     #$00FF
        beq     @trim
:       jsr     @put
        inc     z:u_p
        bra     @pl
@trim:  cpx     #0
        beq     @end
        lda     abuf-1,x
        and     #$00FF
        cmp     #' '
        bne     @end
        dex
        bra     @trim
@end:   stz     abuf,x
        cpx     #0
        beq     @out
        ldx     #.loword(abuf)
        jsr     mkabs
@out:   rts
@put:   cpx     #120
        bcs     :+
        sep     #$20
        .a8
        sta     abuf,x
        rep     #$20
        .a16
        inx
:       rts

; the name X (in our bank) made absolute -> fpath
mkabs:  stx     z:t0
        lda     (t0)
        and     #$00FF
        cmp     #'/'
        bne     :+
        ldy     #.loword(fpath)
        jmp     ui_strcpy
:       ptr     fpath
        lda     #128
        sys     SYS_GETCWD
        bcc     :+
        lda     #0
:       tax
        beq     :+
        lda     fpath-1,x
        and     #$00FF
        cmp     #'/'
        beq     :++
:       lda     #'/'
        sta     fpath,x
        inx
:       ldy     #0
:       lda     (t0),y
        and     #$00FF
        sep     #$20
        .a8
        sta     fpath,x
        rep     #$20
        .a16
        beq     :+
        inx
        iny
        cpx     #127
        bcc     :-
        stz     fpath,x
:       rts


; the content size cw x chh -> the text area, the rows shown, the scroll bar, the status
; line; everything is drawn again
geom:   lda     cw
        sec
        sbc     #UI_SBW
        sta     tw
        sec
        sbc     #LEFTM + 2
        sta     wlim
        lda     chh
        sec
        sbc     #STH
        bpl     :+
        lda     #0
:       sta     th
        sec
        sbc     #TOPM
        ldx     #0
        bmi     :++
:       cmp     #LH
        bcc     :+
        sbc     #LH
        inx
        bra     :-
:       txa
        bne     :+
        inc     a
:       cmp     #MAXVIS
        bcc     :+
        lda     #MAXVIS
:       sta     vis
        lda     tw
        sta     es_sb+CT_X
        stz     es_sb+CT_Y
        lda     #UI_SBW
        sta     es_sb+CT_W
        lda     th
        sta     es_sb+CT_H
        stz     dr_ok
        stz     mt_ok
        rts

; ---------------------------------------------------------------- events
; Events are taken while they come; the view is redrawn when none waits (at most 16
; events apart), so a burst of keys costs one redraw.
loop:   lda     pend
        beq     @wait
        lda     pendn
        cmp     #16
        bcs     @draw
        lda     #1
        jsr     ui_getev
        bcc     @got
@draw:  jsr     flush
@wait:  lda     #0
        jsr     ui_getev
        bcs     loop
@got:   inc     pendn
        ldx     #.loword(ctls)
        jsr     ui_event
        cmp     #UA_CHANGE
        bne     :+
        lda     es_sb+SB_POS            ; the scroll bar moved the view (it shows it)
        sta     sbl_pos
        cmp     top
        beq     loop
        sta     top
        stz     toff
        jsr     endclamp
        jsr     sbupdate
        lda     #1
        sta     pend
        jmp     loop
:       cmp     #UA_NONE
        bne     loop
        lda     ui_ev
        and     #$00FF
        cmp     #WE_KEY
        jeq     onkey
        cmp     #WE_BUTTON
        jeq     onbutton
        cmp     #WE_MOTION
        jeq     onmotion
        cmp     #WE_CLOSE
        jeq     m_close
        cmp     #WE_RESIZE
        beq     onresize
        cmp     #WE_MENU
        beq     onmenu
        jmp     loop

; the view drawn now (if anything is due)
flush:  stz     pendn
        lda     pend
        beq     :+
        stz     pend
        jmp     refresh
:       rts

onresize:
        lda     ui_ev+2
        sta     cw
        lda     ui_ev+4
        sta     chh
        jsr     geom
        jsr     normtop
        jsr     ensure
        jsr     redraw_all
        jmp     loop

onmenu: jsr     flush
        lda     ui_ev+2                 ; menu: File 0, Edit 1, View 2
        asl     a
        tax
        lda     ui_ev+4                 ; item (counting separators)
        asl     a
        tay
        jmp     (mtab,x)
m_file: tyx
        cpx     #12
        jcs     loop
        jmp     (ftab,x)
m_edit: tyx
        cpx     #24
        jcs     loop
        jmp     (etab,x)
m_view: tyx
        cpx     #12
        jcs     loop
        jmp     (vtab,x)
m_fixed:
        lda     #1
        bra     :+
m_prop: lda     #0
:       cmp     efont
        jeq     loop
        sta     efont
viewchg:
        stz     dr_ok
        stz     mt_ok
        jsr     normtop
        jsr     ensure
        jsr     refresh
        jmp     loop
m_wrap: lda     wrap
        eor     #1
        sta     wrap
        stz     hcol
        stz     toff
        bra     viewchg

m_new:  jsr     confirm
        jcs     loop
        jsr     tx_reset
        stz     fpath
        jsr     settitle
        jsr     refresh
        jmp     loop
m_open: jsr     confirm
        jcs     loop
        stz     dlgbuf
        lda     #0
        ldx     #.loword(dlgbuf)
        ldy     #.loword(t_open)
        jsr     ui_filedlg
        jcs     loop
        ldx     #.loword(dlgbuf)
        ldy     #.loword(fpath)
        jsr     ui_strcpy
        jsr     load
        jsr     settitle
        jsr     refresh
        jmp     loop
m_save: jsr     flush
        jsr     do_save
        jsr     refresh
        jmp     loop
m_saveas:
        jsr     flush
        jsr     do_saveas
        jsr     refresh
        jmp     loop
m_close:
        jsr     confirm
        jcs     loop
        jmp     quit
m_cut:  jsr     snap
        jsr     copysel
        jsr     delsel
        jmp     edited
m_copy: jsr     copysel
        jmp     loop
m_paste:
        jsr     snap
        jsr     paste
        jmp     edited
m_all:  jsr     snap
        stz     al
        stz     ac
        lda     nl
        dec     a
        sta     cl
        jsr     lget
        lda     llen
        sta     cc
        jmp     post
m_undo: jsr     snap                    ; (what comes back stays selected)
        jsr     undo
        jsr     setgoal
        jmp     post
m_redo: jsr     snap
        jsr     redo
        jsr     setgoal
        jmp     post

; a key
onkey:  jsr     ui_menukey              ; (0.15) the menu key: the pop-up menu
        bcc     :+
        lda     #1
        jmp     popmenu
:       lda     ui_ev+4
        and     #$00FF
        sta     kmods
        lda     ui_ev+4
        cmp     #$0100
        jcc     loop
        lda     ui_ev+2                 ; F3: find next
        cmp     #$3C
        jeq     m_fnext
        lda     ui_key                  ; (ui_event made it: key_ascii twice would
        jeq     loop                    ; toggle caps lock twice)
        sta     key
        jsr     snap
        lda     kmods
        and     #$22
        sta     shift
        lda     kmods
        and     #$11
        jeq     @plain
        lda     key                     ; ctrl
        cmp     #1
        jeq     m_all
        cmp     #3
        jeq     m_copy
        cmp     #24
        jeq     m_cut
        cmp     #22
        jeq     m_paste
        cmp     #19
        jeq     m_save
        cmp     #15
        jeq     m_open
        cmp     #14
        jeq     m_new
        cmp     #26
        jeq     m_undo
        cmp     #25
        jeq     m_redo
        cmp     #6
        jeq     m_find
        cmp     #7
        jeq     m_fnext
        cmp     #8
        jeq     m_repl
        cmp     #12
        jeq     m_goto
        cmp     #KEY_LEFT
        jeq     k_wleft
        cmp     #KEY_RIGHT
        jeq     k_wright
        cmp     #KEY_HOME
        bne     :+
        stz     cl
        stz     cc
        jmp     mv_h
:       cmp     #KEY_END
        jne     loop
        lda     nl
        dec     a
        sta     cl
        jsr     lget
        lda     llen
        sta     cc
        jmp     mv_h
@plain: lda     key
        cmp     #KEY_LEFT
        jeq     k_left
        cmp     #KEY_RIGHT
        jeq     k_right
        cmp     #KEY_UP
        jeq     k_up
        cmp     #KEY_DOWN
        jeq     k_down
        cmp     #KEY_HOME
        jeq     k_home
        cmp     #KEY_END
        jeq     k_end
        cmp     #KEY_PGUP
        jeq     k_pgup
        cmp     #KEY_PGDN
        jeq     k_pgdn
        cmp     #8
        jeq     k_bs
        cmp     #KEY_DEL
        jeq     k_del
        cmp     #13
        jeq     k_enter
        cmp     #9
        beq     :+
        cmp     #' '
        jcc     loop
        cmp     #$7F
        jcs     loop
:       jsr     selord                  ; a character (over a selection: one group)
        bcs     :+
        lda     #UF_TYPE                ; (typed in a row: one undo record per word)
        sta     ub_mrg
:       jsr     delsel
        lda     key
        sta     onech
        lda     #.loword(onech)
        sta     isrc
        lda     #^onech
        sta     isrc+2
        lda     #1
        jsr     inst
        stz     ub_mrg
        jmp     edited

k_left: jsr     collapse
        bcs     mv_h
        lda     cc
        beq     :+
        dec     cc
        bra     mv_h
:       lda     cl
        beq     mv_h
        dec     cl
        jsr     lget
        lda     llen
        sta     cc
        bra     mv_h
k_right:
        jsr     collapse
        bcs     mv_h
        lda     cl
        jsr     lget
        lda     cc
        cmp     llen
        bcs     :+
        inc     cc
        bra     mv_h
:       lda     cl
        inc     a
        cmp     nl
        bcs     mv_h
        sta     cl
        stz     cc
; a horizontal move: the goal x follows
mv_h:   jsr     anchor
        jsr     setgoal
        jmp     post
; Home / End: the start / end of the cursor's row (End: before the space a wrapped row
; ends with, so the cursor stays on that row)
k_home: jsr     currow
        lda     rw_s
        sta     cc
        bra     mv_h
k_end:  jsr     currow
        lda     rw_e
        cmp     llen
        bcs     :+
        dec     a
        cmp     rw_s
        bcs     :+
        lda     rw_s
:       sta     cc
        bra     mv_h
; ctrl-Left / Right: the start of the previous / next word
k_wleft:
        jsr     wordleft
        bra     mv_h
k_wright:
        jsr     wordright
        bra     mv_h

k_up:   jsr     currow                  ; the row above, the column nearest the goal x
        lda     cl
        sta     pr_l
        lda     rw_s
        sta     pr_s
        jsr     prevrow
        bcs     mv_v0
        bra     mv_v
k_down: jsr     currow
        lda     cl
        sta     pr_l
        lda     rw_s
        sta     pr_s
        jsr     nextrow
        bcs     mv_v0
; a vertical move to row pr_l:pr_s: the column nearest the goal x
mv_v:   lda     pr_l
        sta     cl
        lda     pr_s
        jsr     rowhit
mv_v0:  jsr     anchor
        jmp     post
; PgUp / PgDn: the view and the cursor by a page of rows
k_pgup: lda     #0
        bra     :+
k_pgdn: lda     #1
:       sta     pgdir
        lda     top                     ; the view
        sta     pr_l
        lda     toff
        sta     pr_s
        jsr     pgstep
        lda     pr_l
        sta     top
        lda     pr_s
        sta     toff
        jsr     currow                  ; the cursor
        lda     cl
        sta     pr_l
        lda     rw_s
        sta     pr_s
        jsr     pgstep
        lda     pr_l
        pha
        lda     pr_s
        pha
        jsr     endclamp
        pla
        sta     pr_s
        pla
        sta     pr_l
        jmp     mv_v
; pr_l:pr_s moved by vis rows (pgdir 1 down, 0 up), stopping at the ends
pgstep: lda     vis
        sta     pgn
:       lda     pgdir
        beq     @up
        jsr     nextrow
        bcs     @out
        bra     @n
@up:    jsr     prevrow
        bcs     @out
@n:     dec     pgn
        bne     :-
@out:   rts

k_enter:
        jsr     delsel
        lda     #10
        sta     onech
        lda     #.loword(onech)
        sta     isrc
        lda     #^onech
        sta     isrc+2
        lda     #1
        jsr     inst
        bra     edited
k_bs:   jsr     selord
        bcs     @del
        lda     #UF_BS
        sta     ub_mrg
        lda     cc
        beq     :+
        dec     a
        sta     ac
        bra     @del
:       lda     cl
        beq     edited0
        dec     a
        sta     al
        jsr     lget
        lda     llen
        sta     ac
@del:   jsr     delsel
        stz     ub_mrg
        bra     edited
k_del:  jsr     selord
        bcs     @del
        lda     #UF_DELK
        sta     ub_mrg
        lda     cl
        jsr     lget
        lda     cc
        cmp     llen
        bcs     :+
        inc     a
        sta     ac
        bra     @del
:       lda     cl
        inc     a
        cmp     nl
        bcs     edited0
        sta     al
        stz     ac
@del:   jsr     delsel
        stz     ub_mrg
; after an edit: goal x, redraw
edited: stz     ub_mrg
edited0:
        jsr     anchor0
        jsr     setgoal
        jmp     post

; no Shift: the anchor follows the cursor
anchor: lda     shift
        bne     :+
        lda     cl
        sta     al
        lda     cc
        sta     ac
:       rts

; Left / Right without Shift on a selection: the cursor to its start (left) or end -> C set
collapse:
        lda     shift
        bne     @no
        jsr     selord
        bcc     @no
        lda     key
        cmp     #KEY_LEFT
        bne     :+
        lda     s0l
        sta     cl
        lda     s0c
        sta     cc
        sec
        rts
:       lda     s1l
        sta     cl
        lda     s1c
        sta     cc
        sec
        rts
@no:    clc
        rts

; the goal x = the cursor's x in its row now
setgoal:
        jsr     currow
        lda     cc
        jsr     wstopat
        lda     wx
        ldx     wleft
        beq     :+
        lda     #0
:       sta     goalx
        rts

; the cursor's row: rw_s, rw_e (line cl loaded)
currow: lda     cl
        jsr     lget
        lda     cc
        jmp     rowof

; cc = the column of row (cl, A = its start) nearest the goal x
rowhit: sta     rw_s
        lda     cl
        jsr     lget
        lda     rw_s
        jsr     rowend
        sta     rw_e
        lda     goalx
        ; fall through
; cc = the column of row rw_s .. rw_e of line cl (loaded) nearest pixel A (a column at a
; wrapped row's end goes back one: it would show on the next row)
rowhitx:
        jsr     whitat
        cmp     rw_e
        bcc     :+
        lda     rw_e
        cmp     llen
        bcs     :+
        dec     a
        cmp     rw_s
        bcs     :+
        lda     rw_s
:       sta     cc
        rts

; ctrl-Left: back over spaces and punctuation, then over a word (to the line before at
; its start)
wordleft:
        lda     cc
        bne     :+
        lda     cl
        beq     @out
        dec     cl
        jsr     lget
        lda     llen
        sta     cc
        rts
:       lda     cl
        jsr     lget
@sp:    lda     cc
        beq     @out
        dec     a
        jsr     chclass
        cmp     #1
        beq     @w
        dec     cc
        bra     @sp
@w:     lda     cc
        beq     @out
        dec     a
        jsr     chclass
        cmp     #1
        bne     @out
        dec     cc
        bra     @w
@out:   rts

; ctrl-Right: over the word, then over spaces (from a line's end: the next line's start)
wordright:
        lda     cl
        jsr     lget
        lda     cc
        cmp     llen
        bcc     @w
        lda     cl
        inc     a
        cmp     nl
        bcs     @out
        sta     cl
        stz     cc
        rts
@w:     lda     cc
        cmp     llen
        bcs     @out
        jsr     chclass
        cmp     #1
        bne     @sp
        inc     cc
        bra     @w
@sp:    lda     cc
        cmp     llen
        bcs     @out
        jsr     chclass
        cmp     #1
        beq     @out
        inc     cc
        bra     @sp
@out:   rts

; the class of character A of line lp: 0 space or tab, 1 a word character (letter,
; digit, _, 128-255), 2 other
chclass:
        clc
        adc     #4
        tay
        lda     [lp],y
        and     #$00FF
        cmp     #' ' + 1
        bcs     :+
        lda     #0
        rts
:       cmp     #128
        bcs     @w
        cmp     #'_'
        beq     @w
        cmp     #'0'
        bcc     @o
        cmp     #'9' + 1
        bcc     @w
        and     #$DF
        cmp     #'A'
        bcc     @o
        cmp     #'Z' + 1
        bcc     @w
@o:     lda     #2
        rts
@w:     lda     #1
        rts

; the mouse: a left press in the text area places the cursor (Shift: extends); a second
; press there within 0.5 s selects the word, a third the line
; (0.15) the text's pop-up menu (A = 0 at the pointer, 1 from the keyboard: near the top
; left of the text): Undo, Redo, -, Cut, Copy, Paste, Select all, done as the Edit menu's
popmenu:
        pha
        jsr     flush
        stz     drag
        pla
        bne     :+
        lda     win
        ldx     #.loword(popitems)
        jsr     ui_popup
        bra     :++
:       lda     #24
        sta     z:ui_x
        sta     z:ui_y
        lda     win
        ldx     #.loword(popitems)
        jsr     ui_popat
:       cmp     #7
        jcs     loop
        asl     a
        tax
        jmp     (etab,x)

onbutton:
        lda     ui_ev+6                 ; (0.15) the right button alone: the pop-up menu
        and     #3
        cmp     #2
        bne     :+
        lda     ui_ev+2
        cmp     tw
        jcs     loop
        lda     ui_ev+4
        cmp     th
        jcs     loop
        lda     #0
        jmp     popmenu
:       lda     ui_ev+6
        and     #1
        bne     :+
        stz     drag                    ; a release
        jmp     loop
:       lda     ui_ev+2
        cmp     tw
        jcs     loop
        lda     ui_ev+4
        cmp     th
        jcs     loop
        lda     #1
        sta     drag
        jsr     snap
        sys     SYS_UPTIME              ; a double or triple click?
        sta     z:t0
        sec
        sbc     clk_t
        cmp     #500
        bcs     @one
        lda     ui_ev+2
        sec
        sbc     clk_x
        bpl     :+
        eor     #$FFFF
        inc     a
:       cmp     #5
        bcs     @one
        lda     ui_ev+4
        sec
        sbc     clk_y
        bpl     :+
        eor     #$FFFF
        inc     a
:       cmp     #5
        bcs     @one
        lda     clk_n
        cmp     #3
        bcs     @one
        inc     clk_n
        bra     @cnt
@one:   lda     #1
        sta     clk_n
@cnt:   lda     z:t0
        sta     clk_t
        lda     ui_ev+2
        sta     clk_x
        lda     ui_ev+4
        sta     clk_y
        jsr     posat
        lda     clk_n
        cmp     #2
        beq     @word
        bcs     @line
        lda     kmods
        and     #$22
        sta     shift
        jmp     mv_m
@word:  lda     cl                      ; the word (or the run of one class) there
        jsr     lget
        lda     cc
        cmp     llen
        bcc     :+
        lda     cc
        jeq     mv_m0
        dec     cc
:       lda     cc
        jsr     chclass
        sta     z:t0
        lda     cc
        sta     ac
:       lda     ac
        beq     :+
        dec     a
        jsr     chclass
        cmp     z:t0
        bne     :+
        dec     ac
        bra     :-
:       lda     cc
        cmp     llen
        bcs     :+
        jsr     chclass
        cmp     z:t0
        bne     :+
        inc     cc
        bra     :-
:       lda     cl
        sta     al
        stz     drag
        bra     mv_m1
@line:  lda     cl                      ; the line, with its end
        sta     al
        stz     ac
        stz     drag
        inc     a
        cmp     nl
        bcs     :+
        sta     cl
        stz     cc
        bra     mv_m1
:       lda     cl
        jsr     lget
        lda     llen
        sta     cc
        bra     mv_m1
onmotion:
        lda     drag
        jeq     loop
        jsr     snap
        jsr     posat
        lda     #1
        sta     shift
mv_m:   jsr     anchor
mv_m1:  jsr     setgoal
        jmp     post
mv_m0:  stz     drag
        jsr     anchor0
        bra     mv_m1

; the pointer (ui_ev a, b) -> cl, cc (above or below the text: the row beyond the view)
posat:  jsr     layout
        lda     ui_ev+4
        sec
        sbc     #TOPM
        bpl     @in
        lda     top                     ; above: the row before the first
        sta     pr_l
        lda     toff
        sta     pr_s
        jsr     prevrow
        bra     @row
@in:    ldx     #0
:       cmp     #LH
        bcc     :+
        sbc     #LH
        inx
        bra     :-
:       cpx     vis
        bcc     :+
        ldx     vis                     ; below: the row after the last
        dex
        txa
        asl     a
        tax
        lda     ly_l,x
        cmp     #NONE
        beq     @last
        sta     pr_l
        lda     ly_s,x
        sta     pr_s
        jsr     nextrow
        bra     @row
:       txa
        asl     a
        tax
        lda     ly_l,x
        cmp     #NONE
        beq     @last
        sta     pr_l
        lda     ly_s,x
        sta     pr_s
        bra     @row
@last:  lda     nl                      ; past the text: its last row
        dec     a
        sta     pr_l
        jsr     lget
        lda     llen
        jsr     rowof
        lda     rw_s
        sta     pr_s
@row:   lda     pr_l
        sta     cl
        jsr     lget
        lda     pr_s
        sta     rw_s
        jsr     rowend
        sta     rw_e
        lda     ui_ev+2
        sec
        sbc     #LEFTM
        jmp     rowhitx

; ---------------------------------------------------------------- rows
; line lp (llen) from column A: the end of its row -> A. Without word wrap the line's end;
; with it, after the last space that fits wlim pixels (a space past the edge hangs there),
; else before the character that does not fit (at least one character a row).
rowend: ldx     wrap
        bne     :+
        lda     llen
        rts
:       sta     re_i
        sta     re_s
        stz     re_x
        stz     re_d
        lda     #NONE
        sta     re_sp
@l:     lda     re_i
        cmp     llen
        bcc     :+
        lda     llen
        rts
:       clc
        adc     #4
        tay
        lda     [lp],y
        and     #$00FF
        sta     re_ch
        cmp     #9
        bne     @nt
        lda     re_d                    ; a tab: spaces to the next multiple of 8
        and     #7
        eor     #$FFFF
        clc
        adc     #9
        sta     re_n
        lda     #' '
        ldx     efont
        jsr     ui_cwidth
        sta     re_w0
        stz     re_w
        ldx     re_n
:       lda     re_w
        clc
        adc     re_w0
        sta     re_w
        dex
        bne     :-
        lda     re_w
        bra     @w
@nt:    ldx     #1
        stx     re_n
        ldx     efont                   ; (fixed: 8; the UI font: its table)
        beq     :+
        lda     #8
        bra     @w
:       cmp     #' '
        bcc     :+
        cmp     #$7F
        bcc     :++
:       lda     #'?'
:       sec
        sbc     #' '
        tax
        lda     ui_cw,x
        and     #$00FF
@w:     clc
        adc     re_x
        cmp     wlim
        beq     @fit
        bcc     @fit
        lda     re_ch                   ; it does not fit
        cmp     #' '
        beq     @hang
        cmp     #9
        beq     @hang
        lda     re_sp
        cmp     #NONE
        beq     :+
        inc     a
        rts
:       lda     re_i
        cmp     re_s
        bne     :+
        inc     a
:       rts
@hang:  lda     re_i
        inc     a
        rts
@fit:   sta     re_x
        lda     re_d
        clc
        adc     re_n
        sta     re_d
        lda     re_ch
        cmp     #' '
        beq     :+
        cmp     #9
        bne     :++
:       lda     re_i
        sta     re_sp
:       inc     re_i
        jmp     @l

; line lp, column A -> its row rw_s .. rw_e (a column at a wrapped row's end belongs to
; the next row)
rowof:  sta     ro_c
        stz     rw_s
@l:     lda     rw_s
        jsr     rowend
        sta     rw_e
        cmp     llen
        bcs     @out
        cmp     ro_c
        beq     :+
        bcs     @out
:       lda     rw_e
        sta     rw_s
        bra     @l
@out:   rts

; the row before / after row pr_l:pr_s -> pr_l:pr_s; C set: none (it stays)
prevrow:
        lda     pr_s
        beq     @pl
        lda     pr_l
        jsr     lget
        lda     pr_s
        dec     a
        jsr     rowof
        lda     rw_s
        sta     pr_s
        clc
        rts
@pl:    lda     pr_l
        beq     @none
        dec     a
        sta     pr_l
        jsr     lget
        lda     llen
        jsr     rowof
        lda     rw_s
        sta     pr_s
        clc
        rts
@none:  sec
        rts
nextrow:
        lda     pr_l
        jsr     lget
        lda     pr_s
        jsr     rowend
        cmp     llen
        bcs     @nl
        sta     pr_s
        clc
        rts
@nl:    lda     pr_l
        inc     a
        cmp     nl
        bcs     @none
        sta     pr_l
        stz     pr_s
        clc
        rts
@none:  sec
        rts

; the rows wanted from top:toff -> ly_l, ly_s, ly_e (ly_l = NONE past the text), ly_empty
; of them past the text
layout: lda     top
        sta     pr_l
        lda     toff
        sta     pr_s
        stz     lyi
        stz     ly_empty
@r:     lda     pr_l
        cmp     nl
        bcs     @past
        ldx     lyi
        sta     ly_l,x
        jsr     lget
        lda     pr_s
        ldx     lyi
        sta     ly_s,x
        jsr     rowend
        ldx     lyi
        sta     ly_e,x
        cmp     llen
        bcc     :+
        inc     pr_l
        stz     pr_s
        bra     @n
:       sta     pr_s
        bra     @n
@past:  ldx     lyi
        lda     #NONE
        sta     ly_l,x
        stz     ly_s,x
        stz     ly_e,x
        inc     ly_empty
@n:     lda     lyi
        inc     a
        inc     a
        sta     lyi
        lsr     a
        cmp     vis
        bcc     @r
        rts

; top:toff made a row start again (after the width, the font or word wrap changed)
normtop:
        lda     top
        cmp     nl
        bcc     :+
        lda     nl
        dec     a
        sta     top
:       stz     hcol
        lda     wrap
        bne     :+
        stz     toff
        rts
:       lda     top
        jsr     lget
        lda     toff
        jsr     rowof
        lda     rw_s
        sta     toff
        rts

; keep the cursor in view (top, toff, hcol)
ensure: lda     wrap
        jne     @wrap
        stz     toff
        lda     cl
        cmp     top
        bcs     :+
        sta     top
:       lda     cl
        sec
        sbc     vis
        bcc     :+
        inc     a
        cmp     top
        bcc     :+
        sta     top
:       jsr     endclamp
        jsr     currow                  ; sideways
        lda     cc
        jsr     wstopat
        lda     wleft
        beq     @right
        lda     wd                      ; left of the view: the cursor's column - 8
        and     #$FFF8
        sec
        sbc     #8
        bcs     :+
        lda     #0
:       sta     hcol
        rts
@right: lda     wlim
        sec
        sbc     #2
        cmp     wx
        bcs     @out
        lda     wx                      ; past the right edge: on by the excess / 8 + 8
        clc
        adc     #2
        sec
        sbc     wlim
        lsr     a
        lsr     a
        lsr     a
        clc
        adc     #8
        and     #$FFF8
        clc
        adc     hcol
        sta     hcol
        lda     cc
        jsr     wstopat
        bra     @right
@out:   rts
@wrap:  stz     hcol
        jsr     currow                  ; the cursor's row: before the view?
        lda     cl
        cmp     top
        bcc     @settop
        bne     @fwd
        lda     rw_s
        cmp     toff
        bcc     @settop
@fwd:   lda     top                     ; among the vis rows from the top?
        sta     pr_l
        lda     toff
        sta     pr_s
        lda     vis
        sta     en_n
@f:     lda     pr_l
        cmp     cl
        bne     :+
        lda     pr_s
        cmp     rw_s
        beq     @vis
:       dec     en_n
        beq     @below
        jsr     nextrow
        bcs     @vis
        bra     @f
@below: lda     cl                      ; below: it becomes the last row
        sta     pr_l
        lda     rw_s
        sta     pr_s
        lda     vis
        dec     a
        sta     en_n
        beq     @set
:       jsr     prevrow
        bcs     @set
        dec     en_n
        bne     :-
@set:   lda     pr_l
        sta     top
        lda     pr_s
        sta     toff
        bra     @vis
@settop:
        lda     cl
        sta     top
        lda     rw_s
        sta     toff
@vis:   ; fall through
; no empty rows at the end while the text could fill them
endclamp:
        jsr     layout
        lda     ly_empty
        beq     @out
        sta     en_n
        lda     top
        sta     pr_l
        lda     toff
        sta     pr_s
:       jsr     prevrow
        bcs     :+
        dec     en_n
        bne     :-
:       lda     pr_l
        sta     top
        lda     pr_s
        sta     toff
@out:   rts

; with word wrap: the line of the top row when the text's last row is the last one shown
; (the scroll bar's maximum; kept until the text or the view's width changes)
maxtop: lda     mt_ok
        bne     @c
        lda     nl
        dec     a
        sta     pr_l
        jsr     lget
        lda     llen
        jsr     rowof
        lda     rw_s
        sta     pr_s
        lda     vis
        dec     a
        sta     en_n
        beq     @d
:       jsr     prevrow
        bcs     @d
        dec     en_n
        bne     :-
@d:     lda     pr_l
        sta     mt_line
        lda     #1
        sta     mt_ok
@c:     lda     mt_line
        rts

; ---------------------------------------------------------------- what to redraw
; Marks: whole lines dl_lo .. dl_hi (dl_hi = $FFFF: to the end), and up to 4 lines with
; columns dp_c .. dp_t (dp_t = NONE: to the end: typing; else the cursor's moves: the
; character before the cursor, where its bar is drawn, or the margin at a row's start).
; before an action: the cursor and the selection as they are; a new undo group
snap:   lda     cl
        sta     oc_l
        lda     cc
        sta     oc_c
        lda     al
        sta     oa_l
        lda     ac
        sta     oa_c
        stz     ub_grp
        rts

; after it: the change of the cursor and the selection marked, the cursor kept in view, a
; redraw due (when no event waits)
post:   jsr     marksel
        jsr     ensure
        lda     #1
        sta     pend
        jmp     loop

marksel:
        lda     oa_l                    ; a selection before or after?
        cmp     oc_l
        bne     @sel
        lda     oa_c
        cmp     oc_c
        bne     @sel
        lda     al
        cmp     cl
        bne     @sel
        lda     ac
        cmp     cc
        bne     @sel
        lda     oc_l                    ; no: the cursor's old and new places
        cmp     cl
        bne     @two
        lda     oc_c
        cmp     cc
        beq     @out
@two:   lda     oc_l
        ldx     oc_c
        jsr     markbar
        lda     cl
        ldx     cc
        jmp     markbar
@out:   rts
@sel:   lda     oa_l                    ; the anchor stayed: the lines the cursor crossed
        cmp     al
        bne     @both
        lda     oa_c
        cmp     ac
        bne     @both
        lda     oc_l
        ldx     cl
        bra     markr2
@both:  lda     oa_l
        ldx     oc_l
        jsr     markr2
        lda     al
        ldx     cl
        ; fall through
; lines A .. X or X .. A
markr2: stx     mk_c
        cmp     mk_c
        bcc     markr
        tay
        lda     mk_c
        tyx
        ; fall through
; whole lines A .. X (A <= X)
markr:  cmp     dl_lo
        bcs     :+
        sta     dl_lo
:       cpx     dl_hi
        bcc     :+
        stx     dl_hi
:       rts
; lines A to the end (lines moved: they all change)
markrest:
        ldx     #$FFFF
        bra     markr
; line A, the cursor's column X: from the column before it (the cursor is drawn there)
markcur:
        cpx     #0
        beq     markp
        dex
        ; fall through
; line A from column X on (0: all of it)
markp:  ldy     #NONE
        bra     markw
; line A: the cursor's bar at column X (its old or new place): the column before it
markbar:
        txy
        cpx     #0
        beq     markw
        dex
        ; fall through
; line A, columns X .. Y (Y = NONE: to the end)
markw:  sta     mk_l
        stx     mk_c
        sty     mk_t
        cmp     dl_lo                   ; (whole already?)
        bcc     :+
        cmp     dl_hi
        beq     @out
        bcc     @out
:       ldx     #0
@f:     cpx     dp_n
        bcs     @add
        lda     dp_l,x
        cmp     mk_l
        beq     @mm
        inx
        inx
        bra     @f
@mm:    lda     mk_c                    ; (the line has one: both)
        cmp     dp_c,x
        bcs     :+
        sta     dp_c,x
:       lda     mk_t
        cmp     dp_t,x
        bcc     @out
        sta     dp_t,x
@out:   rts
@add:   cpx     #8
        bcs     @full
        lda     mk_l
        sta     dp_l,x
        lda     mk_c
        sta     dp_c,x
        lda     mk_t
        sta     dp_t,x
        inx
        inx
        stx     dp_n
        rts
@full:  lda     mk_l
        tax
        jmp     markr
; no marks
markclr:
        lda     #NONE
        sta     dl_lo
        stz     dl_hi
        stz     dp_n
        rts

; ---------------------------------------------------------------- drawing
redraw_all:
        lda     #$FFFF                  ; (the scroll bar and the status line for sure)
        sta     sbl_page
        stz     st_ok
        stz     dr_ok
        ; fall through
; draw what changed: the rows wanted against the rows drawn (a view moved by less than a
; page: one copy), the scroll bar, the status line. The compositor waits for all of it.
refresh:
        stz     pend
        lda     #1
        sys     SYS_WSHOLD
        jsr     layout
        jsr     selord
        lda     #0
        rol     a
        sta     selon
        lda     win
        sta     z:ui_win
        lda     dr_ok
        beq     @full
        lda     hcol
        cmp     dr_hcol
        bne     @full
        jsr     vshift
        stz     z:t2
@r:     jsr     rowwhat
        cmp     #NONE
        beq     :+
        jsr     drawrow
:       inc     z:t2
        lda     z:t2
        cmp     vis
        bcc     @r
        bra     @done
@full:  stz     z:ui_x                  ; the top margin
        stz     z:ui_y
        lda     tw
        sta     z:ui_w
        lda     #TOPM
        sta     z:ui_h
        lda     #WD_FILL | (C_WHITE << 8)
        jsr     ui_rect
        stz     z:t2
:       jsr     rowall
        jsr     drawrow
        inc     z:t2
        lda     z:t2
        cmp     vis
        bcc     :-
        lda     vis                     ; below the last row
        jsr     mul12
        adc     #TOPM
        sta     z:ui_y
        lda     th
        sec
        sbc     z:ui_y
        beq     @done
        bmi     @done
        sta     z:ui_h
        stz     z:ui_x
        lda     tw
        sta     z:ui_w
        lda     #WD_FILL | (C_WHITE << 8)
        jsr     ui_rect
@done:  ldx     #0                      ; what is drawn now
:       lda     ly_l,x
        sta     dr_l,x
        lda     ly_s,x
        sta     dr_s,x
        lda     ly_e,x
        sta     dr_e,x
        inx
        inx
        txa
        lsr     a
        cmp     vis
        bcc     :-
        lda     hcol
        sta     dr_hcol
        lda     #1
        sta     dr_ok
        jsr     markclr
        jsr     sbupdate
        jsr     stupdate
        lda     #0
        sys     SYS_WSHOLD
        rts

; row t2 -> A = NONE: nothing to draw; else rfrom .. rto (columns; rto = NONE: to the
; row's end; rmar = 1: the left margin too); all of it: rfrom = the row's start, rto = NONE,
; rmar = 1
rowwhat:
        lda     #NONE
        sta     rto
        lda     #1
        sta     rmar
        lda     z:t2
        asl     a
        tax
        lda     ly_l,x
        cmp     dr_l,x
        bne     @full
        lda     ly_s,x                  ; (the same row: its end may have changed, then
        cmp     dr_s,x                  ; a mark says from where)
        bne     @full
        lda     ly_l,x
        cmp     #NONE
        beq     @none
        cmp     dl_lo
        bcc     :+
        cmp     dl_hi
        beq     @full
        bcc     @full
:       ldy     #0
@p:     cpy     dp_n
        bcs     @none
        lda     dp_l,y
        cmp     ly_l,x
        beq     @pm
        iny
        iny
        bra     @p
@pm:    lda     dp_t,y                  ; columns c .. t
        cmp     #NONE
        bne     @win
        lda     dp_c,y                  ; to the end: from c
        cmp     ly_s,x
        beq     @full
        bcc     @full
        cmp     ly_e,x
        bcs     @none
        stz     rmar
        sta     rfrom
        rts
@win:   cmp     ly_s,x                  ; a window: before the row's start, nothing
        bcc     @none
        sta     rto
        lda     dp_c,y
        cmp     ly_e,x                  ; after its end, nothing
        bcc     :+
        beq     :+
        bra     @none
:       cmp     ly_s,x                  ; from the row's start: the margin too (the bar)
        beq     :+
        bcc     :+
        stz     rmar
        sta     rfrom
        rts
:       lda     ly_s,x
        sta     rfrom
        rts
@full:  lda     ly_s,x
        sta     rfrom
        lda     #NONE
        sta     rto
        lda     #1
        sta     rmar
        lda     #0
        rts
@none:  lda     #NONE
        rts

; the view moved by less than a page since it was drawn: the rows that stay move with
; one copy (WD_COPY), and dr_* with them (the rows that come in: $FFFE, never drawn)
vshift: lda     ly_l                    ; up: the first row wanted was drawn j rows lower
        cmp     #NONE
        beq     @dn
        ldx     #2
@u:     txa
        lsr     a
        cmp     vis
        bcs     @dn
        lda     dr_l,x
        cmp     ly_l
        bne     :+
        lda     dr_s,x
        cmp     ly_s
        beq     @up
:       inx
        inx
        bra     @u
@dn:    lda     dr_l                    ; down: the first row drawn is wanted j rows lower
        cmp     #NONE
        bcs     @out
        ldx     #2
@d:     txa
        lsr     a
        cmp     vis
        bcs     @out
        lda     ly_l,x
        cmp     dr_l
        bne     :+
        lda     ly_s,x
        cmp     dr_s
        jeq     @down
:       inx
        inx
        bra     @d
@out:   rts
@up:    stx     sh_j2
        txa
        lsr     a
        sta     sh_j
        jsr     mul12                   ; rows j.. -> 0..
        adc     #TOPM
        sta     z:ui_y
        stz     z:ui_x
        lda     tw
        sta     z:ui_w
        lda     vis
        sec
        sbc     sh_j
        jsr     mul12
        sta     z:ui_h
        ldx     #0
        ldy     #TOPM
        jsr     ui_copy
        ldx     #0
        ldy     sh_j2
:       tya
        lsr     a
        cmp     vis
        bcs     :+
        lda     dr_l,y
        sta     dr_l,x
        lda     dr_s,y
        sta     dr_s,x
        lda     dr_e,y
        sta     dr_e,x
        inx
        inx
        iny
        iny
        bra     :-
:       txa
        lsr     a
        cmp     vis
        bcs     :+
        lda     #$FFFE
        sta     dr_l,x
        inx
        inx
        bra     :-
:       rts
@down:  stx     sh_j2
        txa
        lsr     a
        sta     sh_j
        lda     #TOPM                   ; rows 0.. -> j..
        sta     z:ui_y
        stz     z:ui_x
        lda     tw
        sta     z:ui_w
        lda     vis
        sec
        sbc     sh_j
        jsr     mul12
        sta     z:ui_h
        lda     sh_j
        jsr     mul12
        adc     #TOPM
        tay
        ldx     #0
        jsr     ui_copy
        lda     vis
        dec     a
        asl     a
        tax
:       txa
        sec
        sbc     sh_j2
        bcc     :+
        tay
        lda     dr_l,y
        sta     dr_l,x
        lda     dr_s,y
        sta     dr_s,x
        lda     dr_e,y
        sta     dr_e,x
        dex
        dex
        bra     :-
:       txa
        bmi     :+
        lda     #$FFFE
        sta     dr_l,x
        dex
        dex
        bra     :-
:       rts

; row t2 all of it (rfrom = its start, rto = NONE, rmar = 1)
rowall: lda     z:t2
        asl     a
        tax
        lda     ly_s,x
        sta     rfrom
        lda     #NONE
        sta     rto
        lda     #1
        sta     rmar
        rts

; A * 12 (rows -> pixels; C clear after)
mul12:  sta     z:t0
        asl     a
        adc     z:t0
        asl     a
        asl     a
        rts

; the scroll bar: only its thumb when only the position changed
sbupdate:
        lda     top
        sta     es_sb+SB_POS
        lda     wrap
        beq     :+
        jsr     maxtop
        bra     :++
:       lda     nl
        sec
        sbc     vis
        bcs     :+
        lda     #0
:       sta     es_sb+SB_MAX
        lda     vis
        sta     es_sb+SB_PAGE
        lda     #1
        sta     es_sb+SB_STEP
        lda     es_sb+SB_MAX
        cmp     sbl_max
        bne     @all
        lda     es_sb+SB_PAGE
        cmp     sbl_page
        bne     @all
        lda     es_sb+SB_POS
        cmp     sbl_pos
        beq     @out
        ldx     sbl_pos
        stx     es_sb+SB_POS
        sta     sbl_pos
        ldx     #.loword(es_sb)
        jmp     ui_sbpos
@all:   lda     es_sb+SB_POS
        sta     sbl_pos
        lda     es_sb+SB_MAX
        sta     sbl_max
        lda     es_sb+SB_PAGE
        sta     sbl_page
        ldx     #.loword(es_sb)
        jmp     ui_draw
@out:   rts

; ---------------------------------------------------------------- the status line
; "Line 12 of 150, column 5" at the left; "Modified", "Wrap" at the right. Drawn when its
; text changes, with its paper (no blank moment).
stupdate:
        ldy     #.loword(stbuf)
        ldx     #.loword(t_line)
        jsr     scat
        lda     cl
        inc     a
        jsr     snum
        ldx     #.loword(t_of)
        jsr     scat
        lda     nl
        jsr     snum
        ldx     #.loword(t_col)
        jsr     scat
        lda     cc
        inc     a
        jsr     snum
        ldy     #.loword(stbuf2)
        lda     #0
        sta     a:0,y
        lda     emod
        beq     :+
        ldx     #.loword(t_modif)
        jsr     scat
:       lda     wrap
        beq     :+
        ldx     #.loword(t_wrap)
        jsr     scat
:       lda     st_ok
        beq     @draw
        ldx     #.loword(stbuf2)
        ldy     #.loword(stlast2)
        jsr     strcmp
        bne     @draw
        ldy     #0                      ; the left text from where it changed
        sep     #$20
        .a8
:       lda     stbuf,y
        cmp     stlast,y
        bne     :+
        cmp     #0
        beq     :++
        iny
        bra     :-
:       rep     #$20
        .a16
        jmp     stpart
:       rep     #$20
        .a16
        rts
@draw:  ldx     #.loword(stbuf)
        ldy     #.loword(stlast)
        jsr     ui_strcpy
        ldx     #.loword(stbuf2)
        ldy     #.loword(stlast2)
        jsr     ui_strcpy
        lda     win
        sta     z:ui_win
        stz     z:ui_font
        stz     z:ui_x
        lda     cw
        sta     z:ui_w
        lda     #1
        sta     z:ui_h
        lda     st_ok
        bne     :+
        lda     th                      ; the line above it
        sta     z:ui_y
        lda     #WD_FILL | (C_DARK << 8)
        jsr     ui_rect
:       lda     #1
        sta     st_ok
        lda     th                      ; a row of body above and below the text
        inc     a
        sta     z:ui_y
        lda     #WD_FILL | (C_BODY << 8)
        jsr     ui_rect
        lda     th
        clc
        adc     #STH - 1
        sta     z:ui_y
        lda     #WD_FILL | (C_BODY << 8)
        jsr     ui_rect
        lda     th                      ; the texts, and the body between them
        clc
        adc     #2
        sta     z:ui_y
        lda     #11
        sta     z:ui_h
        lda     #6
        sta     z:ui_w
        lda     #WD_FILL | (C_BODY << 8)
        jsr     ui_rect
        lda     #6
        sta     z:ui_x
        ldx     #.loword(stbuf)
        lda     #C_BLACK | (C_BODY << 8)
        jsr     ui_text
        ldx     #.loword(stbuf)
        lda     #0
        jsr     ui_twidth
        clc
        adc     #6
        sta     z:ui_x
        ldx     #.loword(stbuf2)
        lda     #0
        jsr     ui_twidth
        eor     #$FFFF
        sec
        adc     cw
        sec
        sbc     #6
        sta     z:t0                    ; the right text's x
        sec
        sbc     z:ui_x
        bmi     :+
        beq     :+
        sta     z:ui_w
        lda     #WD_FILL | (C_BODY << 8)
        jsr     ui_rect
:       lda     z:t0
        sta     z:ui_x
        ldx     #.loword(stbuf2)
        lda     #C_BLACK | (C_BODY << 8)
        jsr     ui_text
        lda     cw
        sec
        sbc     #6
        sta     z:ui_x
        lda     #6
        sta     z:ui_w
        lda     #WD_FILL | (C_BODY << 8)
        jmp     ui_rect

; the status line's left text from character Y on (the right one is as it was)
stpart: sty     z:t2
        lda     #6                      ; x = 6 + the width of what stays
        sta     z:t3
        ldy     #0
:       cpy     z:t2
        bcs     :+
        lda     stbuf,y
        and     #$00FF
        ldx     #0
        jsr     ui_cwidth
        clc
        adc     z:t3
        sta     z:t3
        iny
        bra     :-
:       ldx     #.loword(stbuf)
        ldy     #.loword(stlast)
        jsr     ui_strcpy
        lda     win
        sta     z:ui_win
        stz     z:ui_font
        lda     th
        clc
        adc     #2
        sta     z:ui_y
        lda     #11
        sta     z:ui_h
        lda     z:t3
        sta     z:ui_x
        lda     #.loword(stbuf)
        clc
        adc     z:t2
        sta     z:t4
        tax
        lda     #C_BLACK | (C_BODY << 8)
        jsr     ui_text
        ldx     z:t4                    ; the body from its end to the right text
        lda     #0
        jsr     ui_twidth
        clc
        adc     z:t3
        sta     z:ui_x
        ldx     #.loword(stbuf2)
        lda     #0
        jsr     ui_twidth
        eor     #$FFFF
        sec
        adc     cw
        sec
        sbc     #6
        sec
        sbc     z:ui_x
        bmi     :+
        beq     :+
        sta     z:ui_w
        lda     #WD_FILL | (C_BODY << 8)
        jmp     ui_rect
:       rts

; string X appended at Y (both in our bank) -> Y at its end
scat:   stx     z:t0
        sty     z:t1
        ldy     #0
        sep     #$20
        .a8
:       lda     (t0),y
        sta     (t1),y
        beq     :+
        iny
        bra     :-
:       rep     #$20
        .a16
        tya
        clc
        adc     z:t1
        tay
        rts

; A in decimal at Y (zero-terminated) -> Y at its end
snum:   stz     z:t1
        stx     z:t2
        jsr     snum32
        ldx     z:t2
        rts
; t1:A (32-bit) in decimal at Y -> Y at its end
snum32: sta     z:t0
        sty     z:t3
        ldx     #0                      ; digits, last first, on the stack
@d:     phx
        lda     #0                      ; t1:t0 / 10, remainder in A
        ldx     #32
@b:     asl     z:t0
        rol     z:t1
        rol     a
        cmp     #10
        bcc     :+
        sbc     #10
        inc     z:t0
:       dex
        bne     @b
        plx
        pha
        inx
        lda     z:t0
        ora     z:t1
        bne     @d
        ldy     z:t3
@o:     pla
        clc
        adc     #'0'
        sep     #$20
        .a8
        sta     a:0,y
        rep     #$20
        .a16
        iny
        dex
        bne     @o
        lda     #0
        sep     #$20
        .a8
        sta     a:0,y
        rep     #$20
        .a16
        rts

; strings X and Y (our bank) equal -> Z set
strcmp: stx     z:t0
        sty     z:t1
        ldy     #0
        sep     #$20
        .a8
:       lda     (t0),y
        cmp     (t1),y
        bne     :+
        cmp     #0
        beq     :+
        iny
        bra     :-
:       rep     #$20
        .a16
        rts

; row t2 (ly_*) on the screen: the text, the selection, the cursor; columns rfrom .. rto
; (rto = NONE: to the row's end, with the rest of the row; rmar: the left margin too).
; Drawn without a blank moment: the text in up to three pieces with their paper (before,
; in, after the selection), then the rest of the row.
drawrow:
        lda     win
        sta     z:ui_win
        lda     z:t2                    ; y = TOPM + row * 12
        jsr     mul12
        adc     #TOPM
        sta     ry
        lda     z:t2
        asl     a
        tax
        lda     ly_l,x
        cmp     #NONE
        bne     :+
        lda     #$10000 - LEFTM         ; no line: a white row (margin too)
        sta     z:t4
        lda     #C_WHITE
        jmp     @fillto
:       sta     z:t3                    ; the line
        lda     ly_s,x
        sta     rw_s
        lda     ly_e,x
        sta     rw_e
        lda     z:t3
        jsr     lget
        lda     #2                      ; the text that fits -> rbuf
        sta     wmode
        jsr     walk
        ldx     wdi
        stz     rbuf,x
        lda     wdi
        sta     rlen
        sta     seld0                   ; (no selection: all before it)
        sta     seld1
        lda     wx
        sta     rw
        sta     selx0
        sta     selx1
        stz     seleol
        stz     fdi                     ; from where: a column after the row's start?
        stz     fx
        lda     rfrom
        cmp     rw_s
        beq     :+
        bcc     :+
        jsr     wstopat
        jsr     @clip
        stx     fdi
        sta     fx
:       lda     rlen                    ; to where
        sta     tdi
        lda     rw
        sta     tx
        lda     rto
        cmp     rw_e
        bcs     :+
        jsr     wstopat
        jsr     @clip
        stx     tdi
        sta     tx
:       lda     selon                   ; the selection on this row?
        jeq     @txt
        lda     z:t3
        cmp     s0l
        jcc     @txt
        cmp     s1l
        beq     :+
        jcs     @txt
:       stz     z:t4                    ; from
        cmp     s0l
        bne     :+
        lda     s0c
        sta     z:t4
:       lda     z:t4
        cmp     rw_s
        bcs     :+
        lda     rw_s
        sta     z:t4
:       lda     llen                    ; to
        sta     z:t5
        lda     z:t3
        cmp     s1l
        bne     :+
        lda     s1c
        sta     z:t5
        bra     :++
:       lda     rw_e                    ; (the line end is selected: 4 pixels more on its
        cmp     llen                    ; last row)
        bcc     :+
        lda     #4
        sta     seleol
:       lda     z:t5
        cmp     rw_e
        bcc     :+
        lda     rw_e
        sta     z:t5
:       lda     z:t4
        cmp     z:t5
        bcc     :+
        lda     z:t5
        sta     z:t4
:       lda     z:t4
        jsr     wstopat
        jsr     @clip
        stx     seld0
        sta     selx0
        lda     z:t5
        jsr     wstopat
        jsr     @clip
        stx     seld1
        sta     selx1
@txt:   lda     rmar                    ; the left margin
        beq     :+
        stz     z:ui_x
        lda     ry
        sta     z:ui_y
        lda     #LEFTM
        sta     z:ui_w
        lda     #LH
        sta     z:ui_h
        lda     #WD_FILL | (C_WHITE << 8)
        jsr     ui_rect
:       lda     efont                   ; the UI font's paper is 11 lines: the top one
        bne     @seg
        lda     ry
        sta     z:ui_y
        lda     #1
        sta     z:ui_h
        lda     fx
        clc
        adc     #LEFTM
        sta     z:ui_x
        lda     tx
        sec
        sbc     fx
        beq     :+
        bmi     :+
        sta     z:ui_w
        lda     #WD_FILL | (C_WHITE << 8)
        jsr     ui_rect
:       lda     selx0                   ; (the selection's part of it)
        cmp     fx
        bcs     :+
        lda     fx
:       sta     z:t4
        lda     selx1
        cmp     tx
        bcc     :+
        lda     tx
:       sec
        sbc     z:t4
        beq     @seg
        bmi     @seg
        sta     z:ui_w
        lda     z:t4
        clc
        adc     #LEFTM
        sta     z:ui_x
        lda     #WD_FILL | (C_SELECT << 8)
        jsr     ui_rect
@seg:   lda     efont
        sta     z:ui_font
        eor     #1                      ; (the UI font one line down)
        clc
        adc     ry
        sta     z:ui_y
        stz     pc_a                    ; before the selection
        lda     seld0
        sta     pc_b
        stz     pc_x
        lda     #C_BLACK | (C_WHITE << 8)
        jsr     @piece
        lda     seld0                   ; the selection
        sta     pc_a
        lda     seld1
        sta     pc_b
        lda     selx0
        sta     pc_x
        lda     #C_WHITE | (C_SELECT << 8)
        jsr     @piece
        lda     seld1                   ; after it
        sta     pc_a
        lda     rlen
        sta     pc_b
        lda     selx1
        sta     pc_x
        lda     #C_BLACK | (C_WHITE << 8)
        jsr     @piece
        lda     rto                     ; (a window: the rest stays)
        cmp     #NONE
        jne     @cur
        lda     rw                      ; the selected line end
        sta     z:t4
        lda     seleol
        beq     @rest
        lda     seld1
        cmp     rlen
        bcc     @rest
        lda     rw
        sta     z:ui_x
        lda     #4
        sta     z:ui_w
        jsr     @row
        lda     #WD_FILL | (C_SELECT << 8)
        jsr     ui_rect
        lda     rw
        clc
        adc     #4
        sta     z:t4
@rest:  lda     #C_WHITE                ; the rest of the row
        jsr     @fillto
@cur:   lda     z:t3                    ; the cursor
        cmp     cl
        bne     @out
        lda     cc
        cmp     rw_s
        bcc     @out
        cmp     rw_e
        bcc     :+
        bne     @out
        lda     rw_e
        cmp     llen
        bcc     @out
:       lda     cc
        jsr     wstopat
        lda     wleft
        bne     @out
        lda     wx
        cmp     wlim
        beq     :+
        bcs     @out
:       sta     z:ui_x
        lda     #1
        sta     z:ui_w
        jsr     @row
        dec     z:ui_x
        lda     #WD_FILL | (C_BLACK << 8)
        jmp     ui_rect
@out:   rts
; the box x = LEFTM + ui_x (in), y = ry, h = LH
@row:   lda     z:ui_x
        clc
        adc     #LEFTM
        sta     z:ui_x
        lda     ry
        sta     z:ui_y
        lda     #LH
        sta     z:ui_h
        rts
; colour A from x = LEFTM + t4 to the text area's right edge
@fillto:
        xba
        ora     #WD_FILL
        pha
        lda     z:t4
        sta     z:ui_x
        lda     tw
        sec
        sbc     #LEFTM
        sec
        sbc     z:t4
        sta     z:ui_w
        jsr     @row
        pla
        ldx     z:ui_w
        beq     :+
        bmi     :+
        jmp     ui_rect
:       rts
; rbuf[pc_a .. pc_b) at x LEFTM + pc_x, colours A (ink | paper << 8); inside fdi .. tdi
@piece: ldx     pc_b
        cpx     tdi
        bcc     :+
        ldx     tdi
        stx     pc_b
:       ldx     pc_a
        cpx     fdi
        bcs     :+
        ldx     fdi
        stx     pc_a
        ldy     fx
        sty     pc_x
:       cpx     pc_b
        bcs     @pout
        pha
        ldy     #0
:       lda     rbuf,x
        sta     rbuf2,y
        inx
        iny
        cpx     pc_b
        bcc     :-
        lda     #0
        sta     rbuf2,y
        lda     pc_x
        clc
        adc     #LEFTM
        sta     z:ui_x
        pla
        ldx     #.loword(rbuf2)
        jmp     ui_text
@pout:  rts
; the walk's stop -> A = x, X = display index, both inside what was drawn
@clip:  lda     wleft
        beq     :+
        lda     #0
        ldx     #0
        rts
:       ldx     wdi
        cpx     rlen
        bcc     :+
        ldx     rlen
:       lda     wx
        cmp     rw
        bcc     :+
        lda     rw
:       rts

; ---------------------------------------------------------------- the walk along a row
; row rw_s .. rw_e of line lp; wstopat: A = column -> wx (pixels from the view's left),
; wd (display column from the row's start), wdi (display characters shown before it),
; wleft (1: left of the view). whitat: A = pixel x (signed, from the view's left) -> A =
; the nearest column. wmode 2 (walk): the shown characters -> rbuf (wdi of them), at most
; wlim pixels.
wstopat:
        sta     wstop
        stz     wmode
        jmp     walk
whitat: sta     wpx
        lda     #$FFFF
        sta     wstop
        lda     #1
        sta     wmode
        jsr     walk
        lda     whit
        rts

walk:   lda     rw_s
        sta     wi
        stz     wd
        stz     wx
        stz     wdi
        lda     hcol                    ; (nothing left of the view: the tight loops)
        bne     :+
        lda     wmode
        jeq     wfast
        cmp     #2
        jeq     wbuild
:       lda     wmode
        cmp     #2
        bne     @l
        lda     #$FFFF
        sta     wstop
@l:     lda     wi
        cmp     wstop
        jeq     @stop
        cmp     rw_e
        jcs     @end
        clc
        adc     #4
        tay
        lda     [lp],y
        and     #$00FF
        cmp     #9
        bne     @nt
        lda     wd                      ; tab: to the next multiple of 8
        and     #7
        eor     #$FFFF
        clc
        adc     #9
        sta     wn
        lda     #' '
        bra     @w
@nt:    ldx     #1
        stx     wn
        cmp     #' '
        bcc     :+
        cmp     #$7F
        bcc     @w
:       lda     #'?'
@w:     sta     wch
        lda     wd
        cmp     hcol
        jcc     @skip                   ; left of the view
        lda     efont                   ; the width: n characters
        beq     :+
        lda     wn                      ; (fixed: 8 each)
        asl     a
        asl     a
        asl     a
        sta     wtot
        bra     @wd
:       lda     wch
        sec
        sbc     #' '
        tax
        lda     ui_cw,x
        and     #$00FF
        ldx     wn
        cpx     #1
        beq     :++
        sta     wtot
:       clc
        adc     wtot
        dex
        cpx     #1
        bne     :-
:       sta     wtot
@wd:    lda     wmode
        beq     @adv
        cmp     #1
        bne     @build
        lda     wtot                    ; hit: before the middle of this one?
        lsr     a
        clc
        adc     wx
        sta     z:t0
        lda     wpx
        bmi     @hit
        cmp     z:t0
        bcc     @hit
        bra     @adv
@hit:   lda     wi
        sta     whit
        rts
@build: lda     wx
        clc
        adc     wtot
        cmp     wlim
        beq     :+
        bcs     @full
:       lda     wdi
        clc
        adc     wn
        cmp     #RBUFMAX
        bcs     @full
        ldx     wdi
        ldy     wn
        lda     wch
        sep     #$20
        .a8
:       sta     rbuf,x
        inx
        dey
        bne     :-
        rep     #$20
        .a16
@adv:   lda     wdi
        clc
        adc     wn
        sta     wdi
        lda     wx
        clc
        adc     wtot
        sta     wx
@skip:  lda     wd
        clc
        adc     wn
        sta     wd
        inc     wi
        jmp     @l
@full:  rts
@stop:  stz     wleft
        lda     wd
        cmp     hcol
        bcs     :+
        inc     wleft
:       rts
@end:   lda     rw_e
        sta     whit
        stz     wleft
        rts

; (walk) wstopat with nothing left of the view: a tight loop for the x of column wstop
wfast:  stz     wleft
        lda     wstop
        cmp     rw_e
        bcc     :+
        lda     rw_e
:       clc
        adc     #4
        sta     z:wend
        lda     rw_s
        clc
        adc     #4
        tay
        lda     efont
        bne     @fix
@ui:    cpy     z:wend                  ; the UI font: the advances from its table
        bcs     @out
        lda     [lp],y
        and     #$00FF
        cmp     #9
        beq     @tab
        cmp     #' '
        bcc     @q
        cmp     #$7F
        bcc     :+
@q:     lda     #'?'
:       sec
        sbc     #' '
        tax
        lda     ui_cw,x
        and     #$00FF
        clc
        adc     wx
        sta     wx
        inc     wd
        iny
        bra     @ui
@tab:   lda     ui_cw                   ; a tab: spaces to the next multiple of 8
        and     #$00FF
        clc
        adc     wx
        sta     wx
        inc     wd
        lda     wd
        and     #7
        bne     @tab
        iny
        bra     @ui
@fix:   cpy     z:wend                  ; the fixed font: 8 pixels a column
        bcs     @fx
        lda     [lp],y
        and     #$00FF
        cmp     #9
        bne     :+
        lda     wd
        ora     #7
        sta     wd
:       inc     wd
        iny
        bra     @fix
@fx:    lda     wd
        asl     a
        asl     a
        asl     a
        sta     wx
@out:   lda     wd
        sta     wdi
        tya
        sec
        sbc     #4
        sta     wi
        rts

; (walk) the characters of the row that fit wlim pixels -> rbuf (wdi of them, wx pixels),
; with nothing left of the view
wbuild: lda     rw_e
        clc
        adc     #4
        sta     z:wend
        lda     rw_s
        clc
        adc     #4
        tay
        ldx     #0
@l:     cpy     z:wend
        bcs     @out
        lda     [lp],y
        and     #$00FF
        cmp     #9
        beq     @tab
        cmp     #' '
        bcc     @q
        cmp     #$7F
        bcc     :+
@q:     lda     #'?'
:       jsr     @put
        bcs     @out
        iny
        bra     @l
@tab:   lda     #' '                    ; a tab: spaces to the next multiple of 8
        jsr     @put
        bcs     @out
        lda     wd
        and     #7
        bne     @tab
        iny
        bra     @l
@out:   stx     wdi
        tya
        sec
        sbc     #4
        sta     wi
        rts
; character A into rbuf if it fits -> C set: full
@put:   sta     wch
        lda     efont
        beq     :+
        lda     #8
        bra     :++
:       phx
        lda     wch
        sec
        sbc     #' '
        tax
        lda     ui_cw,x
        and     #$00FF
        plx
:       clc
        adc     wx
        cmp     wlim
        beq     :+
        bcs     @full
:       cpx     #RBUFMAX - 1
        bcs     @full
        sta     wx
        lda     wch
        sep     #$20
        .a8
        sta     rbuf,x
        rep     #$20
        .a16
        inx
        inc     wd
        clc
        rts
@full:  sec
        rts

; ---------------------------------------------------------------- the text store
; an empty text: one empty line
tx_reset:
        ldx     #0                      ; the heap banks back
:       cpx     hbn
        bcs     :+
        phx
        txa
        asl     a
        tax
        lda     hb,x
        sys     SYS_BFREE
        plx
        inx
        bra     :-
:       stz     hbn
        stz     hcur
        stz     hoff
        stz     nl
        lda     #16
        jsr     halloc
        bcs     :+
        lda     #0
        jsr     tins
        lda     #0
        jsr     lset
        stz     cl
        stz     cc
        stz     al
        stz     ac
        stz     top
        stz     hcol
        stz     goalx
        stz     toff
        stz     emod
        stz     crlf
        stz     dr_ok
        stz     mt_ok
        jsr     ub_clear
        clc
:       rts

; A = line -> lp = its block, llen, lcap; lnum = A
lget:   sta     lnum
        asl     a
        tay
        lda     [zlo],y
        sta     z:lp
        lda     [zhi],y
        sta     z:lp+2
        ldy     #2
        lda     [lp],y
        sta     llen
        lda     [lp]
        sta     lcap
        rts

; A = line: its entry = lp
lset:   asl     a
        tay
        lda     z:lp
        sta     [zlo],y
        lda     z:lp+2
        sta     [zhi],y
        rts

; A = capacity -> lp = a new block (length 0); C set: no memory
halloc: stz     hretry
halloc2:
        sta     hcap
        clc
        adc     #4
        sta     hsize
        lda     hcur
        beq     @new
        lda     hoff
        clc
        adc     hsize
        bcs     @new
        cmp     #$FFF0
        bcs     @new
@take:  lda     hoff
        sta     z:lp
        lda     hcur
        sta     z:lp+2
        lda     hcap
        sta     [lp]
        ldy     #2
        lda     #0
        sta     [lp],y
        lda     hoff
        clc
        adc     hsize
        sta     hoff
        clc
        rts
@new:   lda     hbn
        cmp     #MAXHB
        bcc     @alloc
        lda     incomp                  ; compacting: may go further
        beq     :+
        lda     hbn
        cmp     #MAXHB * 2
        bcs     @fail
        bra     @alloc
:       lda     hretry                  ; full: compact once, then try again
        bne     @fail
        inc     hretry
        jsr     compact
        bcs     @fail
        lda     hcap
        jmp     halloc2
@alloc: sys     SYS_BALLOC
        bcs     @fail
        sta     hcur
        stz     hoff
        lda     hbn
        asl     a
        tax
        lda     hcur
        sta     hb,x
        inc     hbn
        bra     @take
@fail:  sec
        rts

; copy the live lines into fresh banks (in line order), free the old ones -> C set: failed
; (then the old banks are kept as well)
compact:
        inc     incomp
        ldx     #0                      ; the old banks aside
:       cpx     hbn
        bcs     :+
        txa
        asl     a
        tay
        lda     hb,y
        sta     ohb,y
        inx
        bra     :-
:       stx     ohbn
        stz     hbn
        stz     hcur
        stz     cpi
@l:     lda     cpi
        cmp     nl
        bcs     @done
        jsr     lget
        lda     z:lp                    ; sp = the old block
        sta     z:sp
        lda     z:lp+2
        sta     z:sp+2
        lda     llen
        sta     cplen
        clc
        adc     #8
        jsr     halloc2
        bcs     @fail
        lda     cplen
        ldy     #2
        sta     [lp],y
        jsr     cpblock
        lda     cpi
        jsr     lset
        inc     cpi
        bra     @l
@done:  ldx     #0
:       cpx     ohbn
        bcs     :+
        phx
        txa
        asl     a
        tax
        lda     ohb,x
        sys     SYS_BFREE
        plx
        inx
        bra     :-
:       dec     incomp
        clc
        rts
@fail:  ldx     #0                      ; keep both
:       cpx     ohbn
        bcs     :+
        txa
        asl     a
        tay
        lda     ohb,y
        phy
        lda     hbn
        asl     a
        tay
        pla
        tax
        lda     ohb,x
        sta     hb,y
        inc     hbn
        txa
        lsr     a
        tax
        inx
        bra     :-
:       dec     incomp
        sec
        rts

; copy cplen bytes of line data: [sp] + 4 -> [lp] + 4
cpblock:
        ldy     #4
        ldx     cplen
        beq     :++
        sep     #$20
        .a8
:       lda     [sp],y
        sta     [lp],y
        iny
        dex
        bne     :-
        rep     #$20
        .a16
:       rts

; line lnum (loaded) must hold A bytes: moved to a larger block if needed -> C set: no memory
lgrow:  cmp     lcap
        bcc     @ok
        beq     @ok
        sta     z:t0
        lsr     a
        lsr     a
        clc
        adc     z:t0
        adc     #16
        cmp     #MAXLEN + 64
        bcc     :+
        lda     #MAXLEN + 64
:       sta     gcap
        lda     lnum
        pha
        lda     gcap
        jsr     halloc
        pla
        bcs     @fail
        sta     lnum
        lda     z:lp                    ; the new block -> dp
        sta     z:dp
        lda     z:lp+2
        sta     z:dp+2
        lda     lnum                    ; the old one (it may have moved) -> sp
        jsr     lget
        lda     z:lp
        sta     z:sp
        lda     z:lp+2
        sta     z:sp+2
        lda     z:dp
        sta     z:lp
        lda     z:dp+2
        sta     z:lp+2
        lda     llen
        sta     cplen
        ldy     #2
        sta     [lp],y
        jsr     cpblock
        lda     gcap
        sta     lcap
        lda     lnum
        jsr     lset
@ok:    clc
        rts
@fail:  sec
        rts

; insert A bytes from [sp] into line lnum (loaded) at column X -> C set: no room
ins_bytes:
        sta     in_n
        stx     in_c
        lda     z:sp                    ; (lgrow uses sp)
        sta     insrc
        lda     z:sp+2
        sta     insrc+2
        lda     in_n
        clc
        adc     llen
        cmp     #MAXLEN + 1
        bcs     @fail
        jsr     lgrow
        bcs     @fail
        lda     insrc
        sta     z:sp
        lda     insrc+2
        sta     z:sp+2
        lda     z:lp                    ; dp = lp + n: the tail moves up
        clc
        adc     in_n
        sta     z:dp
        lda     z:lp+2
        sta     z:dp+2
        lda     in_c
        clc
        adc     #4
        sta     z:t0
        lda     llen
        clc
        adc     #4
        tay
        sep     #$20
        .a8
:       cpy     z:t0
        beq     :+
        dey
        lda     [lp],y
        sta     [dp],y
        bra     :-
:       rep     #$20
        .a16
        lda     z:lp                    ; dp = the gap: the new bytes
        clc
        adc     z:t0
        sta     z:dp
        ldy     #0
        ldx     in_n
        beq     :++
        sep     #$20
        .a8
:       lda     [sp],y
        sta     [dp],y
        iny
        dex
        bne     :-
        rep     #$20
        .a16
:       lda     llen
        clc
        adc     in_n
        sta     llen
        ldy     #2
        sta     [lp],y
        clc
        rts
@fail:  sec
        rts

; delete A bytes of line lnum (loaded) at column X
del_bytes:
        sta     in_n
        txa
        clc
        adc     #4
        tay
        lda     z:lp                    ; dp = lp + n: the tail comes down from there
        clc
        adc     in_n
        sta     z:dp
        lda     z:lp+2
        sta     z:dp+2
        lda     llen
        sec
        sbc     in_n
        sta     llen
        clc
        adc     #4
        sta     z:t0
        sep     #$20
        .a8
:       cpy     z:t0
        bcs     :+
        lda     [dp],y
        sta     [lp],y
        iny
        bra     :-
:       rep     #$20
        .a16
        lda     llen
        ldy     #2
        sta     [lp],y
        rts

; a new entry at line A (the entries from there move up); the caller sets it
tins:   asl     a
        sta     z:t0
        lda     nl
        asl     a
        tay
:       cpy     z:t0
        beq     :+
        dey
        dey
        lda     [zlo],y
        iny
        iny
        sta     [zlo],y
        dey
        dey
        lda     [zhi],y
        iny
        iny
        sta     [zhi],y
        dey
        dey
        bra     :-
:       inc     nl
        rts

; delete X entries from line A
tdel:   stx     z:t1
        asl     a
        tay
        txa
        asl     a
        clc
        adc     z:zlo
        sta     z:sp
        lda     z:zlo+2
        sta     z:sp+2
        txa
        asl     a
        clc
        adc     z:zhi
        sta     z:dp
        lda     z:zhi+2
        sta     z:dp+2
        lda     nl
        sec
        sbc     z:t1
        sta     nl
        asl     a
        sta     z:t0
:       cpy     z:t0
        bcs     :+
        lda     [sp],y
        sta     [zlo],y
        lda     [dp],y
        sta     [zhi],y
        iny
        iny
        bra     :-
:       rts


; ---------------------------------------------------------------- changes of the text
; Every change goes through inst and delsel: they mark what to redraw and keep the undo
; record (unless ub_rec = 0: loading, undo, redo).

; insert A bytes from isrc (a long pointer; LF = a line break) at the cursor; the cursor
; ends after them. C set if something did not fit (lines, memory).
inst:   sta     in_len
        lda     cl
        sta     u_l0
        lda     cc
        sta     u_c0
        stz     mt_ok
        lda     isrc                    ; one line, or lines that move?
        sta     z:sp
        lda     isrc+2
        sta     z:sp+2
        ldy     #0
:       cpy     in_len
        bcs     @one
        lda     [sp],y
        and     #$00FF
        cmp     #10
        beq     @multi
        iny
        bra     :-
@one:   lda     cl
        ldx     cc
        jsr     markcur
        bra     @go
@multi: lda     cl
        jsr     markrest
@go:    lda     loadng
        bne     :+
        jsr     setmod
:       lda     in_len
        jsr     inst0
        bcs     @err
        jmp     ub_ins
@err:   jsr     ub_clear                ; (not all of it: the history would not match)
        sec
        rts

; delete the selection (if any); the cursor at its start
delsel: jsr     selord
        bcs     :+
        rts
:       stz     mt_ok
        lda     s0l
        cmp     s1l
        bne     :+
        ldx     s0c
        jsr     markcur
        bra     :++
:       jsr     markrest
:       jsr     ub_del
        jmp     delsel0

; ---------------------------------------------------------------- undo
; the stack empty (the text as it is counts as saved unless it is modified)
ub_clear:
        stz     ub_top
        stz     ub_end
        lda     emod
        beq     :+
        lda     #NONE
:       sta     ub_save
        rts

; the insert just made (u_l0:u_c0 .. cl:cc, in_len bytes at isrc): recorded, or added to
; the record on top (characters typed in a row, up to a word's end)
ub_ins: lda     ub_rec
        jeq     @out
        lda     isrc                    ; (the text: up)
        sta     z:up
        lda     isrc+2
        sta     z:up+2
        lda     ub_mrg
        cmp     #UF_TYPE
        jne     @new
        lda     ub_grp                  ; (not the first change of this action)
        jne     @new
        jsr     ub_topr
        jcs     @new
        lda     ub_k                    ; an insert typed, ending here?
        and     #$00FF
        cmp     #U_INS
        jne     @new
        lda     ub_k+1
        and     #UF_TYPE
        jeq     @new
        lda     ub_l1
        cmp     u_l0
        jne     @new
        lda     ub_c1
        cmp     u_c0
        jne     @new
        lda     ub_n
        cmp     #250
        jcs     @new
        lda     [up]                  ; a word starts after a space: a new record
        and     #$00FF
        cmp     #' '
        beq     :+
        lda     ub_r
        clc
        adc     #12 - 1
        adc     ub_n
        tay
        lda     [ub],y
        and     #$00FF
        cmp     #' '
        jeq     @new
:       lda     ub_top                  ; room for one more byte?
        cmp     #UBSIZE - 1
        jcs     @new
        lda     ub_r                    ; the byte after its text, the size after that
        clc
        adc     #12
        adc     ub_n
        tay
        lda     [up]
        sep     #$20
        .a8
        sta     [ub],y
        rep     #$20
        .a16
        iny
        lda     ub_n
        clc
        adc     #15
        sta     [ub],y
        inc     ub_top
        lda     ub_top
        sta     ub_end
        ldy     ub_r                    ; n + 1, its end = the cursor
        tya
        clc
        adc     #10
        tay
        lda     ub_n
        inc     a
        sta     [ub],y
        ldy     ub_r
        iny
        iny
        iny
        iny
        iny
        iny
        lda     cl
        sta     [ub],y
        iny
        iny
        lda     cc
        sta     [ub],y
@out:   clc
        rts
@new:   lda     in_len
        sta     u_n
        lda     cl
        sta     u_l1
        lda     cc
        sta     u_c1
        lda     #U_INS
        ldx     ub_mrg
        cpx     #UF_TYPE
        bne     :+
        ora     #UF_TYPE << 8
:       jsr     ub_new
        bcs     @out
        ldy     #0                      ; the text
        ldx     ub_w
:       cpy     u_n
        bcs     :+
        lda     [up],y
        phy
        txy
        sep     #$20
        .a8
        sta     [ub],y
        rep     #$20
        .a16
        ply
        iny
        inx
        bra     :-
:       clc
        rts

; the delete about to be made (the selection s0l:s0c .. s1l:s1c): recorded with its text,
; or added to the record on top (Backspace, Delete in a row)
ub_del: lda     ub_rec
        jeq     @out
        lda     s0l                     ; its size
        cmp     s1l
        bne     :+
        lda     s1c
        sec
        sbc     s0c
        bra     @sz
:       lda     s0l
        sta     cpi
        jsr     lget
        lda     llen
        sec
        sbc     s0c
        sta     u_n
:       inc     cpi                     ; + LF + the next line (the last one: to s1c)
        inc     u_n
        jeq     @big
        lda     cpi
        cmp     s1l
        bcs     :+
        jsr     lget
        lda     u_n
        clc
        adc     llen
        jcs     @big
        sta     u_n
        bra     :-
:       lda     u_n
        clc
        adc     s1c
        jcs     @big
@sz:    sta     u_n
        cmp     #UBSIZE - 14
        jcs     @big
        cmp     #1                      ; one character (or line end) by Backspace / Delete
        jne     @new
        lda     ub_mrg
        cmp     #UF_BS
        beq     :+
        cmp     #UF_DELK
        jne     @new
:       lda     ub_grp
        jne     @new
        jsr     ub_topr
        jcs     @new
        lda     ub_k
        and     #$00FF
        cmp     #U_DEL
        jne     @new
        lda     ub_k+1
        and     ub_mrg
        jeq     @new
        lda     ub_n
        cmp     #250
        jcs     @new
        lda     ub_top
        cmp     #UBSIZE - 1
        jcs     @new
        jsr     @char                   ; z:t0 = the character
        lda     ub_mrg
        cmp     #UF_BS
        bne     @dk
        lda     ub_l0                   ; Backspace: this one ends where the last began
        cmp     s1l
        jne     @new
        lda     ub_c0
        cmp     s1c
        jne     @new
        lda     ub_r                    ; the text moves up one byte (with the size)
        clc
        adc     #12
        sta     z:t1
        adc     ub_n
        inc     a
        tay
:       dey
        cpy     z:t1
        bcc     :+
        lda     [ub],y
        iny
        sep     #$20
        .a8
        sta     [ub],y
        rep     #$20
        .a16
        dey
        bra     :-
:       ldy     z:t1
        lda     z:t0
        sep     #$20
        .a8
        sta     [ub],y
        rep     #$20
        .a16
        ldy     ub_r                    ; starts at s0
        iny
        iny
        lda     s0l
        sta     [ub],y
        iny
        iny
        lda     s0c
        sta     [ub],y
        bra     @grow
@dk:    lda     ub_l0                   ; Delete: at the same place
        cmp     s0l
        jne     @new
        lda     ub_c0
        cmp     s0c
        jne     @new
        lda     ub_r                    ; the character after its text
        clc
        adc     #12
        adc     ub_n
        tay
        lda     z:t0
        sep     #$20
        .a8
        sta     [ub],y
        rep     #$20
        .a16
        ldy     ub_r                    ; its end one character on (in the old text)
        tya
        clc
        adc     #6
        tay
        lda     z:t0
        cmp     #10
        bne     :+
        lda     ub_l1
        inc     a
        sta     [ub],y
        iny
        iny
        lda     #0
        sta     [ub],y
        bra     @grow
:       iny
        iny
        lda     ub_c1
        inc     a
        sta     [ub],y
@grow:  ldy     ub_r                    ; n + 1, the size after the text
        tya
        clc
        adc     #10
        tay
        lda     ub_n
        inc     a
        sta     [ub],y
        lda     ub_r
        clc
        adc     #13
        adc     ub_n
        tay
        lda     ub_n
        clc
        adc     #15
        sta     [ub],y
        inc     ub_top
        lda     ub_top
        sta     ub_end
@out:   rts
@big:   jmp     ub_clear                ; (too large to keep: the history goes)
@new:   lda     s0l
        sta     u_l0
        lda     s0c
        sta     u_c0
        lda     s1l
        sta     u_l1
        lda     s1c
        sta     u_c1
        lda     #U_DEL
        ldx     ub_mrg
        cpx     #UF_BS
        beq     :+
        cpx     #UF_DELK
        bne     :++
:       pha
        txa
        xba
        ora     1,s
        sta     1,s
        pla
:       jsr     ub_new
        bcs     @out
        jmp     ub_cpdoc
; the one character deleted -> z:t0 (an LF for a line end)
@char:  lda     #10
        sta     z:t0
        lda     s0l
        cmp     s1l
        bne     :+
        jsr     lget
        lda     s0c
        clc
        adc     #4
        tay
        lda     [lp],y
        and     #$00FF
        sta     z:t0
:       rts

; the text s0l:s0c .. s1l:s1c -> UB at ub_w (lines joined with LF)
ub_cpdoc:
        lda     ub_w
        sta     cpn
        lda     s0l
        sta     cpi
@l:     lda     cpi
        jsr     lget
        stz     z:t0                    ; from
        lda     cpi
        cmp     s0l
        bne     :+
        lda     s0c
        sta     z:t0
:       lda     llen                    ; to
        sta     z:t1
        lda     cpi
        cmp     s1l
        bne     :+
        lda     s1c
        sta     z:t1
:       lda     z:t0
        clc
        adc     #4
        tay
        ldx     cpn
@c:     tya
        sec
        sbc     #4
        cmp     z:t1
        bcs     @le
        lda     [lp],y
        phy
        txy
        sep     #$20
        .a8
        sta     [ub],y
        rep     #$20
        .a16
        ply
        iny
        inx
        bra     @c
@le:    lda     cpi
        cmp     s1l
        bcs     @out
        lda     #10
        txy
        sep     #$20
        .a8
        sta     [ub],y
        rep     #$20
        .a16
        inx
        stx     cpn
        inc     cpi
        bra     @l
@out:   rts

; the record on top -> ub_r (its offset), ub_k (kind | flags << 8), ub_l0 .. ub_c1, ub_n;
; C set: none, or the text was saved just after it (it stays as it is)
ub_topr:
        lda     ub_top
        beq     ub_no
        cmp     ub_save
        beq     ub_no
        sec
        sbc     #2
        tay
        lda     [ub],y
        eor     #$FFFF
        sec
        adc     ub_top
        sta     ub_r
        ; fall through
; the record at ub_r -> ub_k .. ub_n (C clear)
ub_rd:  ldy     ub_r
        lda     [ub],y
        sta     ub_k
        iny
        iny
        lda     [ub],y
        sta     ub_l0
        iny
        iny
        lda     [ub],y
        sta     ub_c0
        iny
        iny
        lda     [ub],y
        sta     ub_l1
        iny
        iny
        lda     [ub],y
        sta     ub_c1
        iny
        iny
        lda     [ub],y
        sta     ub_n
        clc
        rts
ub_no:  sec
        rts

; a new record: A = kind | flags << 8 (UF_JOIN is added after the action's first change),
; u_l0 .. u_c1, u_n bytes of text to come. Room is made (the redo part goes; the oldest
; records if needed) -> C clear, ub_w = where its text goes; C set: too large (the stack
; is emptied)
ub_new: ldx     ub_grp
        beq     :+
        ora     #UF_JOIN << 8
:       sta     ub_k
        lda     #1
        sta     ub_grp
        lda     u_n
        clc
        adc     #14
        jcs     @big
        cmp     #UBSIZE
        jcs     @big
        sta     u_sz
        lda     ub_top                  ; the redo part goes (and a save point in it)
        sta     ub_end
        lda     ub_save
        cmp     #NONE
        beq     :+
        cmp     ub_top
        bcc     :+
        beq     :+
        lda     #NONE
        sta     ub_save
:       lda     ub_top
        clc
        adc     u_sz
        bcs     @drop
        cmp     #UBSIZE
        bcc     @fits
@drop:  jsr     ub_dropold
        jcs     @big
@fits:  ldy     ub_top
        lda     ub_k
        sta     [ub],y
        iny
        iny
        lda     u_l0
        sta     [ub],y
        iny
        iny
        lda     u_c0
        sta     [ub],y
        iny
        iny
        lda     u_l1
        sta     [ub],y
        iny
        iny
        lda     u_c1
        sta     [ub],y
        iny
        iny
        lda     u_n
        sta     [ub],y
        iny
        iny
        sty     ub_w
        tya
        clc
        adc     u_n
        tay
        lda     u_sz
        sta     [ub],y
        lda     ub_top
        clc
        adc     u_sz
        sta     ub_top
        sta     ub_end
        clc
        rts
@big:   jsr     ub_clear
        sec
        rts

; the oldest records go until u_sz bytes fit -> C set: they cannot
ub_dropold:
        lda     ub_top
        clc
        adc     u_sz
        sec
        sbc     #UBSIZE
        sta     z:t0                    ; at least this much
        stz     z:t1                    ; record boundaries from the bottom
@w:     lda     z:t1
        cmp     z:t0
        bcs     @cut
        cmp     ub_top
        bcs     @no
        clc
        adc     #10
        tay
        lda     [ub],y
        clc
        adc     #14
        adc     z:t1
        sta     z:t1
        bra     @w
@cut:   cmp     ub_top
        beq     :+
        bcs     @no
:       sta     z:t0                    ; [t0, top) -> [0, top - t0)
        lda     z:ub
        clc
        adc     z:t0
        sta     z:ubs
        lda     z:ub+2
        sta     z:ubs+2
        lda     ub_top
        sec
        sbc     z:t0
        sta     ub_top
        sta     ub_end
        ldy     #0
:       cpy     ub_top
        bcs     :+
        lda     [ubs],y
        sta     [ub],y
        iny
        iny
        bra     :-
:       lda     ub_save
        cmp     #NONE
        beq     :++
        sec
        sbc     z:t0
        bcs     :+
        lda     #NONE
:       sta     ub_save
:       lda     ub_top                  ; the first record left starts a group
        beq     :+
        lda     [ub]
        and     #$FFFF ^ (UF_JOIN << 8)
        sta     [ub]
:       clc
        rts
@no:    sec
        rts

; Edit > Undo: the last group of changes taken back (the text they removed comes back
; selected)
undo:   lda     ub_top
        bne     :+
        jmp     ui_beep
:       stz     ub_rec
@l:     lda     ub_top
        sec
        sbc     #2
        tay
        lda     [ub],y
        eor     #$FFFF
        sec
        adc     ub_top
        sta     ub_r
        jsr     ub_rd
        lda     ub_k
        and     #$00FF
        cmp     #U_INS
        bne     @del
        lda     ub_l0                   ; an insert: its text goes
        sta     al
        lda     ub_c0
        sta     ac
        lda     ub_l1
        sta     cl
        lda     ub_c1
        sta     cc
        jsr     delsel
        bra     @n
@del:   lda     ub_l0                   ; a delete: its text comes back, selected
        sta     cl
        lda     ub_c0
        sta     cc
        jsr     ub_text
        lda     ub_n
        jsr     inst
        lda     ub_l0
        sta     al
        lda     ub_c0
        sta     ac
@n:     lda     ub_r
        sta     ub_top
        beq     :+
        lda     ub_k+1
        and     #UF_JOIN
        bne     @l
:       bra     ub_done

; Edit > Redo: the next group of changes made again
redo:   lda     ub_top
        cmp     ub_end
        bcc     :+
        jmp     ui_beep
:       stz     ub_rec
@l:     lda     ub_top
        sta     ub_r
        jsr     ub_rd
        lda     ub_k
        and     #$00FF
        cmp     #U_INS
        bne     @del
        lda     ub_l0                   ; an insert: again
        sta     cl
        sta     al
        lda     ub_c0
        sta     cc
        sta     ac
        jsr     ub_text
        lda     ub_n
        jsr     inst
        jsr     anchor0                 ; (the cursor after it)
        bra     @n
@del:   lda     ub_l0                   ; a delete: again
        sta     al
        lda     ub_c0
        sta     ac
        lda     ub_l1
        sta     cl
        lda     ub_c1
        sta     cc
        jsr     delsel
@n:     lda     ub_n
        clc
        adc     #14
        adc     ub_top
        sta     ub_top
        cmp     ub_end
        bcs     ub_done
        tay
        lda     [ub],y
        xba
        and     #UF_JOIN
        bne     @l
        ; fall through
; after undo / redo: recording again; modified unless back at the saved state
ub_done:
        lda     #1
        sta     ub_rec
        lda     ub_top
        cmp     ub_save
        bne     :+
        lda     emod
        beq     :+
        stz     emod
        jmp     settitle
:       rts

; isrc = the text of record ub_r
ub_text:
        lda     ub_r
        clc
        adc     #12
        sta     isrc
        lda     z:ub+2
        sta     isrc+2
        rts

; (inst) insert A bytes from isrc (a long pointer; LF = a line break) at the cursor; the
; cursor ends after them. Returns C set if something did not fit (lines, memory).
inst0:   sta     itn
        stz     ierr
        lda     isrc                    ; one line? straight in
        sta     z:sp
        lda     isrc+2
        sta     z:sp+2
        ldy     #0
:       cpy     itn
        bcs     @one
        lda     [sp],y
        and     #$00FF
        cmp     #10
        beq     @multi
        iny
        bra     :-
@one:   lda     cl
        jsr     lget
        lda     itn
        ldx     cc
        jsr     ins_bytes
        bcs     @err
        lda     cc
        clc
        adc     itn
        sta     cc
        clc
        rts
@err:   jsr     ui_beep
        sec
        rts
@multi: lda     cl                      ; the tail of the line -> TB
        jsr     lget
        lda     llen
        sec
        sbc     cc
        sta     itail
        lda     z:lp
        clc
        adc     cc
        sta     z:sp
        lda     z:lp+2
        sta     z:sp+2
        stz     z:dp
        lda     tbank
        sta     z:dp+2
        ldy     #4
        ldx     itail
        beq     :++
        sep     #$20
        .a8
:       lda     [sp],y
        phy
        dey
        dey
        dey
        dey
        sta     [dp],y
        ply
        iny
        dex
        bne     :-
        rep     #$20
        .a16
:       lda     cc
        sta     llen
        ldy     #2
        sta     [lp],y
        stz     ipos
@run:   jsr     runlen                  ; the run up to the next LF
        sta     irun
        stz     iforce
        lda     cl
        jsr     lget
        lda     #MAXLEN                 ; room in this line?
        sec
        sbc     llen
        cmp     irun
        bcs     :+
        sta     irun
        inc     iforce
:       lda     irun
        beq     :+
        ldx     llen
        jsr     ins_bytes
        bcs     @nomem
        lda     ipos
        clc
        adc     irun
        sta     ipos
:       lda     iforce                  ; a line break: LF, or a full line
        bne     @brk
        lda     ipos
        cmp     itn
        bcs     @tail
        inc     ipos                    ; (the LF)
@brk:   lda     nl
        cmp     #MAXLINES
        bcs     @nomem
        jsr     runlen                  ; a block for the next run
        cmp     #MAXLEN
        bcc     :+
        lda     #MAXLEN
:       clc
        adc     #8
        jsr     halloc
        bcs     @nomem
        lda     cl
        inc     a
        sta     cl
        jsr     tins
        lda     cl
        jsr     lset
        lda     ipos
        cmp     itn
        jcc     @run
        lda     iforce                  ; (a forced break at the very end: done)
        jeq     @run
        bra     @tail
@nomem: inc     ierr
@tail:  lda     cl                      ; the old tail back, after the cursor
        jsr     lget
        lda     llen
        sta     cc
        stz     z:sp
        lda     tbank
        sta     z:sp+2
        lda     itail
        beq     :+
        ldx     llen
        jsr     ins_bytes
        bcc     :+
        inc     ierr
:       lda     ierr
        beq     :+
        jsr     ui_beep
        sec
        rts
:       clc
        rts

; the length of the run at isrc + ipos up to the next LF (or itn) -> A; sp = its start
runlen: lda     isrc
        clc
        adc     ipos
        sta     z:sp
        lda     isrc+2
        sta     z:sp+2
        ldy     #0
:       tya
        clc
        adc     ipos
        cmp     itn
        bcs     :+
        lda     [sp],y
        and     #$00FF
        cmp     #10
        beq     :+
        iny
        bra     :-
:       tya
        rts

; the selection, ordered -> s0l:s0c .. s1l:s1c; C set if there is one
selord: lda     cl
        cmp     al
        bcc     @cfirst
        bne     @afirst
        lda     cc
        cmp     ac
        beq     @none
        bcc     @cfirst
@afirst:
        lda     al
        sta     s0l
        lda     ac
        sta     s0c
        lda     cl
        sta     s1l
        lda     cc
        sta     s1c
        sec
        rts
@cfirst:
        lda     cl
        sta     s0l
        lda     cc
        sta     s0c
        lda     al
        sta     s1l
        lda     ac
        sta     s1c
        sec
        rts
@none:  clc
        rts

; (delsel) delete the selection (if any); the cursor at its start
delsel0:
        jsr     selord
        bcs     :+
        rts
:       jsr     setmod
        lda     s0l
        cmp     s1l
        bne     @multi
        jsr     lget
        lda     s1c
        sec
        sbc     s0c
        ldx     s0c
        jsr     del_bytes
        bra     @cur
@multi: lda     s1l                     ; the tail of the last line -> TB
        jsr     lget
        lda     llen
        sec
        sbc     s1c
        sta     itail
        lda     z:lp
        clc
        adc     s1c
        sta     z:sp
        lda     z:lp+2
        sta     z:sp+2
        stz     z:dp
        lda     tbank
        sta     z:dp+2
        ldy     #4
        ldx     itail
        beq     :++
        sep     #$20
        .a8
:       lda     [sp],y
        phy
        dey
        dey
        dey
        dey
        sta     [dp],y
        ply
        iny
        dex
        bne     :-
        rep     #$20
        .a16
:       lda     s0l                     ; the first line cut, the tail appended
        jsr     lget
        lda     s0c
        sta     llen
        ldy     #2
        sta     [lp],y
        stz     z:sp
        lda     tbank
        sta     z:sp+2
        lda     itail
        ldx     llen
        jsr     ins_bytes
        lda     s1l                     ; the lines between and the last one go
        sec
        sbc     s0l
        tax
        lda     s0l
        inc     a
        jsr     tdel
@cur:   lda     s0l
        sta     cl
        sta     al
        lda     s0c
        sta     cc
        sta     ac
        rts


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
        stz     cc
        stz     shift
        jmp     mv_h

; View > Word count: words (runs of characters that are not spaces), characters (not
; counting line ends), lines
m_count:
        jsr     flush
        stz     wc_w
        stz     wc_w+2
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
:       stz     z:t1                    ; 1: inside a word
        ldy     #4
        ldx     llen
        beq     @nl
@c:     lda     [lp],y
        and     #$00FF
        cmp     #' ' + 1
        bcs     @wch
        stz     z:t1
        bra     @nx
@wch:   lda     z:t1
        bne     @nx
        lda     #1
        sta     z:t1
        inc     wc_w
        bne     @nx
        inc     wc_w+2
@nx:    iny
        dex
        bne     @c
@nl:    inc     cpi
        bra     @l
@show:  ldy     #.loword(msgbuf)
        ldx     #.loword(m_words)
        jsr     scat
        lda     wc_w+2
        sta     z:t1
        lda     wc_w
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

; ---------------------------------------------------------------- clipboard
; the selection -> the system clipboard (lines joined with LF; at most 65535 bytes)
copysel:
        jsr     selord
        bcs     :+
        rts
:       stz     z:dp
        lda     sbank
        sta     z:dp+2
        stz     cpn
        lda     s0l
        sta     cpi
@l:     lda     cpi
        jsr     lget
        stz     z:t0                    ; from
        lda     cpi
        cmp     s0l
        bne     :+
        lda     s0c
        sta     z:t0
:       lda     llen                    ; to
        sta     z:t1
        lda     cpi
        cmp     s1l
        bne     :+
        lda     s1c
        sta     z:t1
:       lda     z:t0
        clc
        adc     #4
        tay
        ldx     cpn
@c:     tya
        sec
        sbc     #4
        cmp     z:t1
        bcs     @le
        cpx     #$FFFF
        bcs     @full
        lda     [lp],y
        phy
        txy
        sep     #$20
        .a8
        sta     [dp],y
        rep     #$20
        .a16
        ply
        iny
        inx
        bra     @c
@le:    lda     cpi
        cmp     s1l
        bcs     @put
        cpx     #$FFFF
        bcs     @full
        lda     #10
        txy
        sep     #$20
        .a8
        sta     [dp],y
        rep     #$20
        .a16
        inx
        stx     cpn
        inc     cpi
        bra     @l
@full:  phx
        jsr     ui_beep                 ; (too much: the first 65535 bytes)
        plx
@put:   stx     cpn
        stz     cblk
        lda     sbank
        sta     cblk+2
        lda     cpn
        sta     cblk+3
        ptr     cblk
        sys     SYS_CLPUT
        rts

; the clipboard -> inserted at the cursor (replacing the selection)
paste:  stz     cblk
        lda     sbank
        sta     cblk+2
        lda     #$FFFF
        sta     cblk+3
        ptr     cblk
        sys     SYS_CLGET
        bcs     @out
        cmp     #0
        beq     @out
        stz     crhold
        jsr     crfilter
        sta     z:t5
        jsr     delsel
        jsr     setmod
        stz     isrc
        lda     sbank
        sta     isrc+2
        lda     z:t5
        jsr     inst
        jsr     anchor0
        jsr     setgoal
@out:   rts
anchor0:
        lda     cl
        sta     al
        lda     cc
        sta     ac
        rts

; A bytes at SB:0 with each CR before an LF removed -> A = the new count (crfin: a CR
; held at the end when more follows)
crfilter:
        sta     crn
        stz     z:sp
        lda     sbank
        sta     z:sp+2
        ldy     #0                      ; Y reads, X writes
        ldx     #0
@l:     cpy     crn
        bcs     @out
        lda     [sp],y
        and     #$00FF
        cmp     #13
        bne     @keep
        iny                             ; CR: an LF next?
        cpy     crn
        bcs     @last
        lda     [sp],y
        and     #$00FF
        cmp     #10
        bne     @cr
        lda     #1
        sta     crlf
        bra     @l
@last:  lda     crhold                  ; the last byte: hold it if more follows
        beq     @cr
        lda     #2
        sta     crhold
        bra     @out
@cr:    dey
        lda     #13
@keep:  phy
        txy
        sep     #$20
        .a8
        sta     [sp],y
        rep     #$20
        .a16
        ply
        inx
        iny
        bra     @l
@out:   txa
        rts

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
        lda     #LEFTM + 4
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
        stz     dr_ok
        stz     mt_ok
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
        stz     hcol
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

; File > Save: to its path, or Save as for a new text -> C set: not saved
do_save:
        lda     fpath
        and     #$00FF
        beq     do_saveas
        jmp     save
do_saveas:
        ldx     #.loword(fpath)
        ldy     #.loword(dlgbuf)
        jsr     ui_strcpy
        lda     #1
        ldx     #.loword(dlgbuf)
        ldy     #.loword(t_saveas)
        jsr     ui_filedlg
        bcc     :+
        rts
:       ldx     #.loword(dlgbuf)
        ldy     #.loword(fpath)
        jsr     ui_strcpy
        jsr     save
        php
        jsr     settitle
        plp
        rts

; unsaved changes: ask (Save / Discard / Cancel) -> C set: stop (cancelled, or not saved)
confirm:
        jsr     flush                   ; (the view as it is behind the alert)
        lda     emod
        bne     :+
        clc
        rts
:       ldx     #.loword(m_save1)
        ldy     #.loword(msgbuf)
        jsr     ui_strcpy
        jsr     basename
        ldy     #.loword(msgbuf)
        jsr     append
        ldx     #.loword(m_save2)
        jsr     append
        ldx     #.loword(al_save)
        jsr     ui_alert
        cmp     #1
        beq     @go
        cmp     #0
        bne     @stop
        jmp     do_save
@go:    clc
        rts
@stop:  sec
        rts

; an alert: message X (then the file's name), error code A (0: none)
errbox: sta     z:t5
        ldy     #.loword(msgbuf)
        jsr     ui_strcpy
        ldy     #.loword(msgbuf)
        jsr     basename
        jsr     append
        lda     z:t5
        beq     @show
        ldx     #.loword(m_code)
        jsr     append
        lda     z:t5                    ; the code in hex
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        jsr     @hex
        lda     z:t5
        jsr     @hex
        ldx     #.loword(m_rpar)
        jsr     append
@show:  ldx     #.loword(al_err)
        jsr     ui_alert
        rts
@hex:   and     #$000F
        cmp     #10
        bcc     :+
        adc     #6
:       adc     #'0'
        sta     onech
        ldx     #.loword(onech)
        ; fall through
; append string X to the string at msgbuf
append: phx
        ldx     #.loword(msgbuf)
        jsr     ui_strlen
        clc
        adc     #.loword(msgbuf)
        tay
        plx
        jmp     ui_strcpy

; X = the file's name (after the last '/'), or "(new)"
basename:
        lda     fpath
        and     #$00FF
        bne     :+
        ldx     #.loword(t_newname)
        rts
:       ldx     #.loword(fpath)
        ldy     #.loword(fpath)
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
        rts

; the window title: "Edit: name" (and " *" when changed)
settitle:
        ldx     #.loword(t_edit)
        ldy     #.loword(msgbuf)
        jsr     ui_strcpy
        jsr     basename
        ldy     #.loword(msgbuf+6)
        jsr     ui_strcpy
        cmp     #23                     ; cut long names
        bcc     :+
        lda     #'.' | ('.' << 8)
        sta     msgbuf+6+20
        stz     msgbuf+6+22
:       lda     emod
        beq     :+
        ldx     #.loword(t_star)
        jsr     append
:       lda     win
        ptr     msgbuf
        sys     SYS_WTITLE
        rts

setmod: lda     emod
        bne     :+
        inc     emod
        jsr     settitle
:       rts


        .segment "RODATA"
; (0.15) with the shortcuts, as Write's (win_menu reads the list to its end)
menus:  .byte   "File", 0, "New", 9, "Ctrl+N", 0, "Open...", 9, "Ctrl+O", 0, "Save", 9, "Ctrl+S", 0
        .byte   "Save as...", 0, "-", 0, "Close", 9, "Ctrl+W", 0, 0
        .byte   "Edit", 0, "Undo", 9, "Ctrl+Z", 0, "Redo", 9, "Ctrl+Y", 0, "-", 0, "Cut", 9, "Ctrl+X", 0
        .byte   "Copy", 9, "Ctrl+C", 0, "Paste", 9, "Ctrl+V", 0, "Select all", 9, "Ctrl+A", 0, "-", 0
        .byte   "Find...", 9, "Ctrl+F", 0, "Find next", 9, "F3", 0, "Replace...", 9, "Ctrl+H", 0
        .byte   "Go to line...", 9, "Ctrl+L", 0, 0
        .byte   "View", 0, "Fixed font", 0, "Proportional font", 0, "-", 0, "Word wrap", 0, "-", 0
        .byte   "Word count", 0, 0, 0
mtab:   .addr   m_file, m_edit, m_view
ftab:   .addr   m_new, m_open, m_save, m_saveas, loop, m_close
popitems: .byte "Undo", 9, "Ctrl+Z", 0, "Redo", 9, "Ctrl+Y", 0, "-", 0, "Cut", 9, "Ctrl+X", 0
        .byte   "Copy", 9, "Ctrl+C", 0, "Paste", 9, "Ctrl+V", 0, "Select all", 9, "Ctrl+A", 0, 0
etab:   .addr   m_undo, m_redo, loop, m_cut, m_copy, m_paste, m_all, loop, m_find, m_fnext
        .addr   m_repl, m_goto
vtab:   .addr   m_fixed, m_prop, loop, m_wrap, loop, m_count
ctls:   .addr   es_sb, 0
t_edit: .byte   "Edit: ", 0
t_star: .byte   " *", 0
t_newname: .byte "(new)", 0
t_open: .byte   "Open", 0
t_saveas: .byte "Save as", 0
t_title: .byte  "Edit", 0
t_line: .byte   "Line ", 0
t_of:   .byte   " of ", 0
t_col:  .byte   ", column ", 0
t_modif: .byte  "Modified", 0
t_wrap: .byte   "   Wrap", 0
t_find: .byte   "Find", 0
t_findc: .byte  "Find:", 0
t_repl: .byte   "Replace", 0
t_with: .byte   "Replace with:", 0
t_rall: .byte   "Replace all", 0
t_fnext: .byte  "Find next", 0
t_close: .byte  "Close", 0
t_goto: .byte   "Go to line", 0
t_lnum: .byte   "Line number:", 0
t_wctitle: .byte "Word count", 0
m_save1: .byte  "Save the changes to ", 0
m_save2: .byte  "?", 10, "Changes that are not saved will be lost.", 0
m_cantopen: .byte "Cannot open ", 0
m_cantread: .byte "Cannot read ", 0
m_cantsave: .byte "Cannot save ", 0
m_toobig: .byte "Too large to load completely: ", 0
m_loading: .byte "Loading ", 0
m_dots: .byte   "...", 0
m_code: .byte   10, "(error $", 0
m_rpar: .byte   ")", 0
m_nofind: .byte "Cannot find ", $22, 0
m_quote: .byte  $22, ".", 0
m_repld: .byte  " replaced.", 0
m_words: .byte  "Words: ", 0
m_chars: .byte  10, "Characters: ", 0
m_lines: .byte  10, "Lines: ", 0
b_save: .byte   "Save", 0
b_discard: .byte "Discard", 0
b_cancel: .byte "Cancel", 0
b_ok:   .byte   "OK", 0
al_save: .word  2, t_title, msgbuf, b_save, b_discard, b_cancel
al_err: .word   3, t_title, msgbuf, b_ok, 0, 0
al_note: .word  0, t_title, msgbuf, b_ok, 0, 0
al_count: .word 0, t_wctitle, msgbuf, b_ok, 0, 0

        .segment "DATA"
wopen:  .word   40, 40, 480, 260
        .faraddr t_title
        .byte   WF_RESIZE
es_sb:  .byte   UT_VSCROLL, 0
        .word   0, 0, UI_SBW, 0, 0
        .word   0, 0, 1, 1, 0, 0
efont:  .word   1                       ; 1 fixed, 0 UI font
ub_rec: .word   1                       ; 1: changes are recorded for undo

; the Find dialog
dg_find: .addr  t_find
        .word   300, 84
        .addr   ls_find
        .word   0
ls_find: .addr  lb_find, fd_find, bt_fcancel, bt_ffind, 0
lb_find: .byte  UT_LABEL, 0
        .word   12, 12, 56, UI_LINE, 0
        .addr   t_findc
fd_find: .byte  UT_FIELD, 0
        .word   72, 8, 216, UI_FLDH, UF_FOCUS
        .addr   fbuf
        .word   FINDMAX, 0, 0, 0, 0
bt_ffind: .byte UT_BUTTON, 0
        .word   224, 52, 64, UI_BTNH, UF_DEFAULT
        .addr   t_find
bt_fcancel: .byte UT_BUTTON, 0
        .word   152, 52, 64, UI_BTNH, UF_CANCEL
        .addr   b_cancel
; the Replace dialog
dg_repl: .addr  t_repl
        .word   360, 112
        .addr   ls_repl
        .word   0
ls_repl: .addr  lb_rfind, fd_rfind, lb_rwith, fd_rwith, bt_rclose, bt_rall, bt_rone, bt_rnext, 0
lb_rfind: .byte UT_LABEL, 0
        .word   12, 12, 80, UI_LINE, 0
        .addr   t_findc
fd_rfind: .byte UT_FIELD, 0
        .word   96, 8, 252, UI_FLDH, UF_FOCUS
        .addr   rfbuf
        .word   FINDMAX, 0, 0, 0, 0
lb_rwith: .byte UT_LABEL, 0
        .word   12, 36, 80, UI_LINE, 0
        .addr   t_with
fd_rwith: .byte UT_FIELD, 0
        .word   96, 32, 252, UI_FLDH, 0
        .addr   rwbuf
        .word   FINDMAX, 0, 0, 0, 0
bt_rnext: .byte UT_BUTTON, 0
        .word   268, 80, 80, UI_BTNH, UF_DEFAULT
        .addr   t_fnext
bt_rone: .byte  UT_BUTTON, 0
        .word   188, 80, 72, UI_BTNH, 0
        .addr   t_repl
bt_rall: .byte  UT_BUTTON, 0
        .word   96, 80, 84, UI_BTNH, 0
        .addr   t_rall
bt_rclose: .byte UT_BUTTON, 0
        .word   12, 80, 64, UI_BTNH, UF_CANCEL
        .addr   t_close
; the Go to line dialog
dg_goto: .addr  t_goto
        .word   260, 84
        .addr   ls_goto
        .word   0
ls_goto: .addr  lb_goto, fd_goto, bt_gcancel, bt_gok, 0
lb_goto: .byte  UT_LABEL, 0
        .word   12, 12, 84, UI_LINE, 0
        .addr   t_lnum
fd_goto: .byte  UT_FIELD, 0
        .word   100, 8, 148, UI_FLDH, UF_FOCUS
        .addr   gbuf
        .word   8, 0, 0, 0, 0
bt_gok: .byte   UT_BUTTON, 0
        .word   184, 52, 64, UI_BTNH, UF_DEFAULT
        .addr   b_ok
bt_gcancel: .byte UT_BUTTON, 0
        .word   112, 52, 64, UI_BTNH, UF_CANCEL
        .addr   b_cancel

        .segment "BSS"
argl:   .res    2
argx:   .res    2
wsown:  .res    2
win:    .res    2
sbank:  .res    2
tbank:  .res    2
cw:     .res    2
chh:    .res    2
tw:     .res    2
th:     .res    2
wlim:   .res    2
vis:    .res    2
top:    .res    2
toff:   .res    2
hcol:   .res    2
wrap:   .res    2
nl:     .res    2
cl:     .res    2
cc:     .res    2
al:     .res    2
ac:     .res    2
goalx:  .res    2
emod:   .res    2
crlf:   .res    2
crhold: .res    2
crn:    .res    2
kmods:  .res    2
key:    .res    2
shift:  .res    2
drag:   .res    2
onech:  .res    2
fh:     .res    2
pend:   .res    2                       ; a redraw is due
pendn:  .res    2                       ; events since the last one
loadng: .res    2                       ; loading a file
oc_l:   .res    2                       ; snap: cursor and anchor before an action
oc_c:   .res    2
oa_l:   .res    2
oa_c:   .res    2
dl_lo:  .res    2                       ; marks: whole lines, lines from a column
dl_hi:  .res    2
dp_n:   .res    2
dp_l:   .res    8
dp_c:   .res    8
dp_t:   .res    8
mk_t:   .res    2
rto:    .res    2
rmar:   .res    2
tdi:    .res    2
tx:     .res    2
mk_l:   .res    2
mk_c:   .res    2
ly_l:   .res    MAXVIS * 2              ; the rows wanted, the rows drawn
ly_s:   .res    MAXVIS * 2
ly_e:   .res    MAXVIS * 2
dr_l:   .res    MAXVIS * 2
dr_s:   .res    MAXVIS * 2
dr_e:   .res    MAXVIS * 2
ly_empty: .res  2
lyi:    .res    2
dr_ok:  .res    2
dr_hcol: .res   2
sh_j:   .res    2
sh_j2:  .res    2
pr_l:   .res    2                       ; prevrow / nextrow
pr_s:   .res    2
rw_s:   .res    2                       ; a row of the line lp
rw_e:   .res    2
ro_c:   .res    2
re_i:   .res    2                       ; rowend
re_s:   .res    2
re_x:   .res    2
re_d:   .res    2
re_sp:  .res    2
re_ch:  .res    2
re_n:   .res    2
re_w:   .res    2
re_w0:  .res    2
en_n:   .res    2
mt_ok:  .res    2                       ; maxtop known
mt_line: .res   2
pgdir:  .res    2
pgn:    .res    2
clk_t:  .res    2                       ; the last press: time, place, count
clk_x:  .res    2
clk_y:  .res    2
clk_n:  .res    2
selon:  .res    2
s0l:    .res    2
s0c:    .res    2
s1l:    .res    2
s1c:    .res    2
ry:     .res    2
rfrom:  .res    2
fdi:    .res    2
fx:     .res    2
pc_a:   .res    2
pc_b:   .res    2
pc_x:   .res    2
rlen:   .res    2
rw:     .res    2
selx0:  .res    2
selx1:  .res    2
seld0:  .res    2
seld1:  .res    2
seleol: .res    2
sbl_pos: .res   2
sbl_max: .res   2
sbl_page: .res  2
st_ok:  .res    2                       ; the status line is drawn
stbuf:  .res    48
stbuf2: .res    24
stlast: .res    48
stlast2: .res   24
wmode:  .res    2
wstop:  .res    2
wpx:    .res    2
wi:     .res    2
wd:     .res    2
wx:     .res    2
wdi:    .res    2
wn:     .res    2
wch:    .res    2
wtot:   .res    2
whit:   .res    2
wleft:  .res    2
lnum:   .res    2
llen:   .res    2
lcap:   .res    2
hbn:    .res    2
hcur:   .res    2
hoff:   .res    2
hcap:   .res    2
hsize:  .res    2
hretry: .res    2
incomp: .res    2
hb:     .res    MAXHB * 4 + 4
ohb:    .res    MAXHB * 4 + 4
ohbn:   .res    2
cpi:    .res    2
cpn:    .res    2
cplen:  .res    2
gcap:   .res    2
in_n:   .res    2
in_c:   .res    2
in_len: .res    2
itn:    .res    2
itail:  .res    2
ipos:   .res    2
irun:   .res    2
iforce: .res    2
ierr:   .res    2
isrc:   .res    4
insrc:  .res    4
rblk:   .res    6
cblk:   .res    6
ub_top: .res    2                       ; undo: the stack's end, the redo part's end
ub_end: .res    2
ub_save: .res   2                       ; ub_top when the text was saved (NONE: lost)
ub_grp: .res    2                       ; 1: this action made a change already
ub_mrg: .res    2                       ; typing / Backspace / Delete (UF_*): may add to the top
ub_w:   .res    2
ub_r:   .res    2
ub_k:   .res    2
ub_l0:  .res    2
ub_c0:  .res    2
ub_l1:  .res    2
ub_c1:  .res    2
ub_n:   .res    2
u_l0:   .res    2
u_c0:   .res    2
u_l1:   .res    2
u_c1:   .res    2
u_n:    .res    2
u_sz:   .res    2
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
wc_w:   .res    4
wc_c:   .res    4
fpath:  .res    130
abuf:   .res    130
dlgbuf: .res    130
msgbuf: .res    200
rbuf:   .res    RBUFMAX + 2
rbuf2:  .res    RBUFMAX + 2

        .segment "ZEROPAGE"
lp:     .res    4
sp:     .res    4
dp:     .res    4
zlo:    .res    4
zhi:    .res    4
ub:     .res    4
ubs:    .res    4
up:     .res    4
wend:   .res    2
t0:     .res    2
t1:     .res    2
t2:     .res    2
t3:     .res    2
t4:     .res    2
t5:     .res    2
