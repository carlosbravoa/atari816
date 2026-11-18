; WRITE - the word processor (/BIN/WRITE.PRG): "write [-t | -b] [path]". Edit's text editor
; with basic formatting; the document is Markdown text (.MD), so it stays readable in Edit
; and on a PC. One assembly unit of several files:
;   write.s        start, events, keys, the mouse, menus, the status line
;   write_store.s  the text store, its changes, undo / redo, the clipboard, the word count
;   write_md.s     Markdown: the blocks and inline spans of a line, the type faces, the
;                  line cache (where each line wraps), rows
;   write_view.s   the view: layout, scrolling, drawing rows (own text rendering)
;   write_fmt.s    the Format menu: inline spans, headings, lists, quotes; Enter / Tab /
;                  Backspace in lists
;   write_file.s   find, replace, go to, word count, files (load, save, save as .md, export
;                  plain text), (0.23) print (prdoc)
;   write_tb.s     the toolbar, its state (the style at the cursor), the menus' check marks
;   write_test.s   "write -t FILE" (the self test) and "write -b FILE" (timings)
;   wfont.inc      the type faces (compressed: unpacked at the start) and the toolbar's
;                  icons, made by tools/mkwfont.py from kernel/font8x12.txt
;
; Memory: the program and its window, 7 banks of its own (the line table (2), the file and
; clipboard data, a line's tail, undo, the line model with the row buffer, VB: the records
; of the rows drawn and the type faces' bitmaps) and the text's heap (one bank per ~60 KB
; of text). The program file must stay under the loader's 64 KB (it is about 60 KB): the
; type faces' bitmaps are in it LZSS-compressed.
;
; The window: the toolbar (write_tb.s: Undo, Redo, Bold, Italic, Code, Heading 1-3, Normal
; text, Bullet list, Numbered list, Quote, Rule; the buttons of what holds at the cursor
; pressed in), the text, the status line (the cursor's place, the block, the words; the
; name of the toolbar button under the pointer). A new document is "Untitled.md"; Save as
; suggests the document's name as .md and adds ".md" to a name typed without an extension;
; a file of another extension (.TXT) opened is saved under its own name.
;
; The text is stored as Edit stores it (write_store.s): a line table and a heap of line
; blocks over several banks, LF / CR LF kept, undo records. Saving writes the lines back
; unchanged, so the file round-trips byte for byte; only what is edited changes.
;
; Markdown (write_md.s). Each line is read on its own: its block (# ## ### heading, - * +
; bullet, 1. numbered item, > quote, --- rule, blank, paragraph; list levels by the indent:
; 4 spaces a level), then its inline spans: `code`, **bold**, *italic* (CommonMark's
; delimiter rules, simplified), \ escapes. Everything else is shown as it is written.
; Markup characters are hidden, except: the inline markers on the cursor's line (shown in
; grey, in place); everything with View > Show markup. Block markers stay drawn as what
; they mean (bullets, numbers, a quote bar, a rule, the heading's type) except with Show
; markup; the status line names the block the cursor is in. Consecutive lines are shown
; on rows of their own (on a PC they would join into one paragraph unless separated by a
; blank line or a line end of two spaces).
;
; The view (write_view.s): always wrapped to the window's width (or, View > Page width, to
; a centred column of PAGEW pixels). A row has the height of its line's type face. Each
; row is drawn into a buffer of our own (stride 1024) and blitted (WD_SBLIT): the type
; faces are ours (wfont.inc): bold (widened where a stroke would close a gap), italic (a
; row-wise shear), heading 1 at 2x (EPX-smoothed, bold), heading 2 at 1.5x (bold), heading
; 3 bold, code in the 8x12 console font on a grey tint. The window shows each row whole,
; never half drawn. Rows that stay but move (lines inserted or deleted, the view scrolled)
; move with one WD_COPY; a row drawn as it is wanted is not drawn again.
;
; Keys: as Edit's (arrows, Shift selects, ctrl-Left / Right words, Home / End rows,
; ctrl-Home / End the text, PgUp / PgDn, ctrl-A, X, C, V, Z (undo), Y (redo), F (find), G or
; F3 (find next), H (replace), L (go to line), S, O, N); ctrl-B bold, ctrl-I italic, ctrl-E
; code, ctrl-1 .. 3 headings, ctrl-0 normal text, ctrl-8 bullets, ctrl-7 numbers, ctrl-9
; quote, ctrl-minus rule (write_fmt.s); Enter, Tab, Shift-Tab and Backspace know lists. The
; mouse: a click places the cursor, Shift-click extends, a drag selects, a double click a
; word, a triple click a line; the wheel scrolls (the scroll bar); the toolbar.
;
; (0.23) File > Print (ctrl-P): the document as plain text (write_file.s, prdoc: each line
; a paragraph wrapped at 80 columns, the markup out, headings underlined or in capitals,
; list markers "- " / "1. " with the other rows under the text, a quote 4 spaces in, a
; blank line between paragraphs and blocks), LF line ends, a print job "/PRN:Write"; then
; "Printed" on the status line (until the next key press, click or menu), or an alert.
;
; Menus: each command with its shortcut (after a TAB) and the Format items' check marks:
; more than 254 bytes, which win_menu keeps on a kernel that takes long menus. On one that
; keeps 254 bytes (it cuts the rest), the long menus' last item is not there (win_mstate
; refuses it), and the short menus of before (no shortcuts, no marks) are set instead.
;
; Limits: Edit's (32,000 lines, about 700 KB, 16,000 bytes a line); inline spans do not
; cross line ends (they do cross the ends of rows); the line cache holds LCN lines of up to
; LCK rows (longer lines are laid out again when needed); a row of more than RCMAX columns
; is drawn whole when it changes (no record).
        .include "horizon.inc"
        .include "ui.inc"

MAXLINES = 32000
MAXLEN  = 16000
.ifndef MAXHB
MAXHB   = 12
.endif
TOPM    = 4                             ; the text area's top margin
LEFTM   = 10                            ; its left and right margins (full width)
STH     = 14                            ; the status line's height
MAXROWS = 28                            ; rows shown at most
CHUNK   = 4096
NONE    = $FFFF
UBSIZE  = $FF00                         ; the undo stack's room
U_INS   = 1                             ; undo record kinds and flags
U_DEL   = 2
UF_JOIN = 1
UF_TYPE = 2
UF_BS   = 4
UF_DELK = 8
FINDMAX = 64
RBS     = 1024                          ; the row buffer's stride
RBOFF   = $8000                         ;   its place in its bank (the model's bank)
PAGEW   = 384                           ; View > Page width: the text column
PAGEP   = 24                            ;   its paper around the text
NMARK   = 8                             ; marks (what to redraw)
C_CODEBG = 254                          ; code's tint (grey 228)
C_MARK  = C_MID                         ; markup shown
C_QUOTE = C_DARK                        ; a quote's text
C_PAGEBG = C_LIGHT                      ; around the page
TBH     = 24                            ; the toolbar's height (write_tb.s)
SLN     = 60                            ; row records (write_view.s): slots of 512 bytes in VB
RCMAX   = 240                           ;   a row's columns at most in one
WFO     = $8000                         ; the type faces' bitmaps in VB (wf_init)

        .segment "CODE"
        .a16
        .i16
start:  sta     argl
        stx     argx
        jsr     getarg
        sys     SYS_BALLOC              ; the line table, the scratch banks, the undo bank,
        jcs     nomem                   ; the line model, the row buffer
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
        sys     SYS_BALLOC              ; the records of the rows drawn
        jcs     nomem
        sta     vbank
        lda     #$7FFF                  ; (no clip)
        sta     clx1
        jsr     wf_init                 ; the type faces
        sys     SYS_BALLOC              ; (one bank: the line model's styles at 4 + column,
        jcs     nomem                   ; its advances at $4004 + column, the row buffer at
        sta     z:mb+2                  ; $8000: 32 rows of RBS)
        sta     z:ma+2
        stz     z:mb
        lda     #$4000
        sta     z:ma
        lda     z:mb+2
        sta     z:gp+2
        lda     #RBOFF
        sta     z:gp
        lda     z:mb+2
        sta     rbank
        jsr     pb_bank
        jsr     tx_reset
        jcs     nomem
        lda     tmode
        jne     test_run                ; write -t / -b (write_test.s)
        sys     SYS_WSSTART
        bcc     :+
        print   "write: no window system\n"
        exit    1
:       sta     wsown
        jsr     ui_init
        ptr     wopen
        sys     SYS_WOPEN
        bcc     :+
        jsr     stopws
        print   "write: no window\n"
        exit    1
:       sta     win
        sep     #$20
        .a8
        sta     es_sb+CT_WIN
        rep     #$20
        .a16
        jsr     setmenus
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
        print   "write: not enough memory\n"
        exit    1

stopws: lda     wsown
        beq     :+
        sys     SYS_WSSTOP
:       rts

quit:   lda     win
        sys     SYS_WCLOSE
        jsr     stopws
        exit    0

; the arguments: [-t | -b] [path] (quotes, or "\ " for a space) -> tmode, fpath (absolute)
getarg: stz     fpath
        stz     tmode
        lda     argl
        jeq     @out
        ldx     argx
        jsr     args_init
        jsr     str_skip
        cmp     #'-'
        bne     @path
        ldy     #1
        lda     [u_p],y
        and     #$00FF
        cmp     #'t'
        beq     :+
        cmp     #'b'
        bne     @path
        lda     #2
        bra     :++
:       lda     #1
:       sta     tmode
        inc     z:u_p
        inc     z:u_p
        jsr     str_skip
@path:  ldx     #0
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

; the content size cw x chh -> the text area (tw x th), the text column (tl, colw), the
; scroll bar; the line cache emptied (the rows change); everything is drawn again
geom:   lda     cw
        sec
        sbc     #UI_SBW
        bpl     :+
        lda     #0
:       cmp     #RBS
        bcc     :+
        lda     #RBS - 2
:       sta     tw
        lda     chh
        sec
        sbc     #STH + TBH
        bpl     :+
        lda     #0
:       sta     th
        clc
        adc     #TBH
        sta     sttop
        jsr     colgeom
        lda     tw
        sta     es_sb+CT_X
        lda     #TBH
        sta     es_sb+CT_Y
        stz     tb_ok                   ; (the toolbar drawn again: its width)
        lda     #UI_SBW
        sta     es_sb+CT_W
        lda     th
        sta     es_sb+CT_H
viewflush:
        stz     dr_ok
        stz     mt_ok
        jmp     lc_flush

; the text column: tl (its left), colw (its width)
colgeom:
        lda     pagew
        beq     @full
        lda     tw
        sec
        sbc     #2 * PAGEP
        bcc     @full
        cmp     #PAGEW
        bcc     :+
        lda     #PAGEW
:       sta     colw
        eor     #$FFFF
        sec
        adc     tw
        lsr     a
        sta     tl
        bra     @min
@full:  lda     #LEFTM
        sta     tl
        lda     tw
        sec
        sbc     #2 * LEFTM
        sta     colw
@min:   lda     colw
        bmi     :+
        cmp     #48
        bcs     @out
:       lda     #48
        sta     colw
@out:   rts

; ---------------------------------------------------------------- events
; Events are taken while they come; the view is redrawn when none waits (at most 16
; events apart), so a burst of keys costs one redraw.
loop:   lda     tst_sp                  ; (write -t, -b: back to the script)
        beq     :+
        tax
        txs
        rts
:       lda     pend
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
        lda     stnote                  ; (0.23) a note on the status line: gone at the
        beq     :+                      ; next key press, click or menu
        jsr     noteoff
:       ldx     #.loword(ctls)
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
        cmp     #WE_LEAVE
        jeq     onleave
        jmp     loop

; (0.23) the status line's note (stnote, "Printed") gone at a key press, a button, a menu
noteoff:
        lda     ui_ev
        and     #$00FF
        cmp     #WE_KEY
        bne     :+
        lda     ui_ev+5
        and     #$00FF
        bne     @off
        rts
:       cmp     #WE_BUTTON
        beq     @off
        cmp     #WE_MENU
        bne     :+
@off:   stz     stnote
        lda     #1
        sta     pend
:       rts

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
        lda     ui_ev+2                 ; menu: File 0, Edit 1, View 2, Format 3
        cmp     #4
        jcs     loop
        asl     a
        tax
        lda     mn_short                ; (the short menus' tables follow the long ones')
        beq     :+
        txa
        clc
        adc     #8
        tax
:       lda     ui_ev+4                 ; item (counting separators)
        cmp     mnn,x
        jcs     loop
        asl     a
        clc
        adc     mnt,x
        tax
        lda     a:0,x
        sta     mn_h
        jsr     snap
        ldx     #0
        jmp     (mn_h,x)

; View > Show markup / Hide markup, Page width / Full width
m_markup:
        lda     showmk
        eor     #1
        sta     showmk
        bra     viewchg
m_page: lda     pagew
        eor     #1
        sta     pagew
viewchg:
        jsr     setchecks
        jsr     colgeom
        jsr     viewflush
        jsr     clampcur
        jsr     normtop
        jsr     ensure
        jsr     redraw_all
        jmp     loop

m_new:  jsr     confirm
        jcs     loop
        jsr     tx_reset
        stz     fpath
        jsr     settitle
        jsr     redraw_all
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
        jsr     redraw_all
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
m_export:
        jsr     flush
        jsr     do_export
        jsr     refresh
        jmp     loop
; (0.23) File > Print (ctrl-P): the document as plain text (prdoc), a print job
; "/PRN:Write"; "Printed" on the status line, or an alert
m_print:
        jsr     flush
        jsr     arm_drop
        ldx     #.loword(t_prn)
        jsr     prdoc
        bcc     :+
        ldx     #.loword(m_cantprint)
        jsr     errbox
        bra     :++
:       lda     #.loword(t_printed)
        sta     stnote
:       jsr     refresh
        jmp     loop
m_close:
        jsr     confirm
        jcs     loop
        jmp     quit
m_cut:  jsr     snap
        jsr     arm_drop
        jsr     copysel
        jsr     delsel
        jmp     edited
m_copy: jsr     copysel
        jmp     loop
m_paste:
        jsr     snap
        jsr     arm_drop
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
        jsr     arm_drop                ; (a style armed: that goes first)
        jcs     post
        jsr     undo
        jsr     setgoal
        jmp     post
m_redo: jsr     snap
        jsr     arm_drop
        jsr     redo
        jsr     setgoal
        jmp     post

; the menus: the long ones (shortcuts, check marks: more than 254 bytes) when the kernel
; keeps them all (their last item is there), else the short ones; View's two items checked
; when on, the others as the toolbar's state (mn_checks)
setmenus:
        stz     mn_short
        stz     mn_st
        stz     mn_dis
        lda     win
        ptr     menus
        sys     SYS_WMENU
        bcs     @short
        lda     win
        ldx     #3 | (MN_LAST << 8)
        ldy     #0
        sys     SYS_WMSTATE
        bcc     setchecks
@short: lda     #1
        sta     mn_short
        lda     win
        ptr     menus_s
        sys     SYS_WMENU
        ; fall through
; View's check marks as the view is
setchecks:
        ldy     #0
        lda     showmk
        beq     :+
        ldy     #MS_CHECK
:       lda     win
        ldx     #2                      ; View, item 0
        sys     SYS_WMSTATE
        ldy     #0
        lda     pagew
        beq     :+
        ldy     #MS_CHECK
:       lda     win
        ldx     #2 | (1 << 8)           ; View, item 1
        sys     SYS_WMSTATE
        rts
; ---------------------------------------------------------------- keys
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
        lda     kmods                   ; (Alt + a key: the menus', not text)
        and     #$44
        jne     loop
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
        cmp     #'0'
        bcc     :+
        cmp     #'4'
        bcs     :+
        sbc     #'0' - 1                ; (C clear: - '0')
        asl     a
        tax
        jmp     (khtab,x)               ; ctrl-0 .. 3: normal text, heading 1 .. 3
:       ldx     #0
:       lda     kctab,x
        beq     @cext
        cmp     key
        beq     :+
        inx
        inx
        inx
        inx
        bra     :-
:       jmp     (kctab+2,x)
@cext:  lda     key
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
        jeq     k_tab
        cmp     #' '
        jcc     loop
        cmp     #$7F
        jcs     loop
; a character (over a selection: one group)
k_char: jsr     selord
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
        lda     cl                      ; (a hidden block marker is no place)
        jsr     hidpfx
        cmp     cc
        bcs     @prev
        dec     cc
        bra     mv_h
@prev:  lda     cl
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
        jsr     hidpfx
        sta     cc
; a horizontal move: the goal x follows
mv_h:   jsr     anchor
        jsr     setgoal
        jmp     post
; Home / End: the start / end of the cursor's row (End: before the space a wrapped row
; ends with, so the cursor stays on that row)
k_home: jsr     currow
        lda     rw_s
        sta     cc
        bne     mv_h
        lda     cl
        jsr     hidpfx
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

; Up / Down: the row above / below, the column nearest the goal x. A line the cursor
; comes into is laid out as the cursor's line (its markers shown) before the column is
; chosen.
k_up:   jsr     currow
        lda     rw_s
        beq     @pl
        lda     cl
        sta     pr_l
        lda     rw_s
        sta     pr_s
        jsr     prevrow
        bra     mv_v
@pl:    lda     cl
        jeq     mv_v0
        dec     a
        sta     rv_l
        sta     pr_l
        jsr     lrows
        lda     llen
        jsr     rowof
        lda     rw_s
        sta     pr_s
        bra     mv_v
k_down: jsr     currow
        lda     rw_e
        cmp     llen
        bcs     @nl
        sta     pr_s
        lda     cl
        sta     pr_l
        bra     mv_v
@nl:    lda     cl
        inc     a
        cmp     nl
        bcs     mv_v0
        sta     rv_l
        sta     pr_l
        stz     pr_s
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
        sta     rv_l
        jsr     lrows                   ; (the cursor's line as it will be laid out)
        lda     pr_s
        cmp     llen
        bcc     :+
        lda     llen
:       jsr     rowof
        lda     rw_s
        sta     pr_s
        jmp     mv_v
; pr_l:pr_s moved by vis rows (pgdir 1 down, 0 up), stopping at the ends
pgstep: lda     vis
        dec     a
        bne     :+
        inc     a
:       sta     pgn
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

k_bs:   jsr     arm_drop                ; (a style armed and left empty: it goes, no more)
        jcs     edited
        jsr     selord
        bcs     @del
        jsr     bs_block                ; (at a list item's start: the marker goes)
        jcc     edited
        lda     #UF_BS
        sta     ub_mrg
        lda     cc
        beq     :+
        dec     a
        sta     ac
        bra     @del
:       lda     cl
        jeq     edited0
        dec     a
        sta     al
        jsr     lget
        lda     llen
        sta     ac
@del:   jsr     delsel
        stz     ub_mrg
        bra     edited
k_del:  jsr     arm_drop
        jcs     edited
        jsr     selord
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
        sta     goalx
        rts

; the cursor's row: rw_s, rw_e (line cl laid out)
currow: lda     cl
        sta     rv_l
        jsr     lrows
        lda     cc
        jmp     rowof

; cc = the column of row (cl, A = its start) nearest the goal x
rowhit: sta     rw_s
        lda     cl
        jsr     lrows
        lda     rw_s
        jsr     rowend
        sta     rw_e
        lda     goalx
        ; fall through
; cc = the column of row rw_s .. rw_e of line cl (laid out) nearest pixel A (a column at a
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

; the cursor out of a hidden block marker (after the view changed)
clampcur:
        lda     cl
        jsr     hidpfx
        cmp     cc
        bcc     :+
        sta     cc
:       rts

; ctrl-Left: back over spaces and punctuation, then over a word (to the line before at
; its end)
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
        jsr     hidpfx
        sta     cc
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

; ---------------------------------------------------------------- the mouse
; a left press in the text area places the cursor (Shift: extends); a second press there
; within 0.5 s selects the word, a third the line
; (0.15) the text's pop-up menu (A = 0 at the pointer, 1 from the keyboard: near the top
; left of the text): Undo, Redo, -, Cut, Copy, Paste, Select all, done as the Edit menu's
popmenu:
        pha
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
        lda     ui_ev+6                 ; (0.15) the right button alone in the text: the
        and     #3                      ; pop-up menu
        cmp     #2
        bne     :+
        lda     ui_ev+4
        cmp     #TBH
        jcc     loop
        lda     #0
        jmp     popmenu
:       lda     ui_ev+6
        and     #1
        bne     :+
        stz     drag                    ; a release (on a toolbar button: its command)
        jmp     tb_release
:       lda     ui_ev+4                 ; on the toolbar
        cmp     #TBH
        jcc     tb_press
        sec                             ; (the text area's y from here on)
        sbc     #TBH
        sta     ui_ev+4
        lda     ui_ev+2
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
        lda     clk_n                   ; (a second or third click: the place of the first;
        cmp     #2                      ; the line's markers shown since then moved its text)
        bcc     :+
        lda     clk_l
        cmp     nl
        bcs     :+
        sta     cl
        jsr     lget
        lda     clk_c
        cmp     llen
        bcc     @cc
        lda     llen
@cc:    sta     cc
        bra     :++
:       jsr     posat
        lda     cl
        sta     clk_l
        lda     cc
        sta     clk_c
:       lda     clk_n
        cmp     #2
        beq     @word
        bcs     @line
        lda     ui_ev+7                 ; (the modifiers at the press)
        and     #$0022
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
        lda     drag                    ; not selecting: the toolbar's (the pointer over
        bne     :+                      ; it: WF_HOVER, or a button of it held)
        jsr     tb_hover
        jmp     loop
:       lda     ui_ev+4
        sec
        sbc     #TBH
        sta     ui_ev+4
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

; the pointer (ui_ev a, b) -> cl, cc (above or below the text: the row beyond the view).
; The rows are those on the screen (the line clicked is laid out as it is shown).
posat:  jsr     layout
        lda     ui_ev+4
        cmp     #TOPM
        bpl     @in
        lda     top                     ; above: the row before the first
        sta     pr_l
        lda     toff
        sta     pr_s
        jsr     prevrow
        bra     @row
@in:    ldx     #0
:       cpx     nly2
        bcs     @below
        lda     ly_y,x
        clc
        adc     ly_h,x
        cmp     ui_ev+4
        beq     :+
        bcs     @hit
:       inx
        inx
        bra     :--
@below: lda     nly2                    ; below the last row shown
        beq     @last
        dec     a
        dec     a
        tax
        lda     ly_l,x
        cmp     #NONE
        beq     @last
        sta     pr_l
        lda     ly_s,x
        sta     pr_s
        jsr     nextrow
        bra     @row
@hit:   lda     ly_l,x
        cmp     #NONE
        beq     @last
        sta     pr_l
        lda     ly_s,x
        sta     pr_s
        bra     @row
@last:  lda     nl                      ; past the text: its last row
        dec     a
        sta     pr_l
        jsr     lrows
        lda     llen
        jsr     rowof
        lda     rw_s
        sta     pr_s
@row:   lda     pr_l
        sta     cl
        jsr     lrows
        lda     pr_s
        sta     rw_s
        jsr     rowend
        sta     rw_e
        lda     ui_ev+2
        sec
        sbc     tl
        jsr     rowhitx
        lda     cl                      ; (not inside a hidden block marker)
        jsr     hidpfx
        cmp     cc
        bcc     :+
        sta     cc
:       rts

; ---------------------------------------------------------------- what to redraw
; Marks (NMARK at most): lines mk_l0 .. mk_l1, and on a single line the columns mk_c0 ..
; mk_c1 (NONE: to the end). A row is drawn again when a mark touches it, or when it is not
; on the screen as it is wanted (line, start, end, height; see refresh). Line numbers in
; the marks and in the rows drawn follow lines inserted and deleted (lc_ins, lc_del).
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

; after it: the change of the cursor and the selection marked, the cursor's line laid out
; with its markers, the cursor kept in view, a redraw due (when no event waits)
post:   jsr     arm_chk                 ; (a style armed: still at the cursor?)
        jsr     marksel
        lda     cl
        sta     rv_l
        cmp     dr_rv
        beq     :+
        tax
        jsr     markr
        lda     dr_rv
        tax
        jsr     markr
        lda     cl
        sta     dr_rv
:       jsr     ensure
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
        txy
        jsr     markw
        lda     cl
        ldx     cc
        txy
        jmp     markw
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
markr2: stx     z:t0
        cmp     z:t0
        bcc     markr
        tay
        lda     z:t0
        tyx
        ; fall through
; whole lines A .. X (A <= X)
markr:  sta     mk_a
        stx     mk_b
        stz     mk_cc0
        lda     #NONE
        sta     mk_cc1
        bra     markadd
; line A from column X to the end (an edit there)
markp:  ldy     #NONE
        ; fall through
; line A, columns X .. Y
markw:  sta     mk_a
        sta     mk_b
        stx     mk_cc0
        sty     mk_cc1
        ; fall through
markadd:
        ldx     #0                      ; (a mark of the same lines: both)
@f:     cpx     mk_n
        bcs     @add
        lda     mk_l0,x
        cmp     mk_a
        bne     @nx
        lda     mk_l1,x
        cmp     mk_b
        bne     @nx
        lda     mk_cc0
        cmp     mk_c0,x
        bcs     :+
        sta     mk_c0,x
:       lda     mk_cc1
        cmp     mk_c1,x
        bcc     :+
        sta     mk_c1,x
:       rts
@nx:    inx
        inx
        bra     @f
@add:   cpx     #NMARK * 2
        bcs     @full
        lda     mk_a
        sta     mk_l0,x
        lda     mk_b
        sta     mk_l1,x
        lda     mk_cc0
        sta     mk_c0,x
        lda     mk_cc1
        sta     mk_c1,x
        inx
        inx
        stx     mk_n
        rts
@full:  lda     mk_a                    ; full: the first one grows to hold it (whole lines)
        cmp     mk_l0
        bcs     :+
        sta     mk_l0
:       lda     mk_b
        cmp     mk_l1
        bcc     :+
        sta     mk_l1
:       stz     mk_c0
        lda     #NONE
        sta     mk_c1
        rts
; no marks
markclr:
        stz     mk_n
        rts

; ---------------------------------------------------------------- the status line
; "Line 12 of 150, column 5" at the left; the block ("Heading 2"), the words, "Modified"
; at the right. Drawn when its text changes, with its paper (no blank moment).
stupdate:
        ldy     #.loword(stbuf)
        ldx     stnote                  ; (0.23) a note ("Printed")
        bne     :+
        lda     tb_hov                  ; a toolbar button under the pointer: its name
        cmp     #NONE
        beq     :++
        asl     a
        tax
        lda     tbhint,x
        tax
:       jsr     scat
        bra     @blk
:       ldx     #.loword(t_line)
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
@blk:   lda     cl                      ; the block
        jsr     lget
        jsr     md_block
        ldy     #.loword(stbuf2)
        lda     m_blk
        asl     a
        tax
        lda     blknames,x
        beq     :+
        tax
        jsr     scat
        ldx     #.loword(t_gap)
        jsr     scat
:       lda     wc_tot+2                ; the words
        sta     z:t1
        lda     wc_tot
        jsr     snum32
        ldx     #.loword(t_words)
        lda     wc_tot+2
        bne     :+
        lda     wc_tot
        cmp     #1
        bne     :+
        ldx     #.loword(t_word)
:       jsr     scat
        lda     emod
        beq     :+
        ldx     #.loword(t_modif)
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
        lda     sttop                   ; the line above it
        sta     z:ui_y
        lda     #WD_FILL | (C_DARK << 8)
        jsr     ui_rect
:       lda     #1
        sta     st_ok
        lda     sttop                   ; a row of body above and below the text
        inc     a
        sta     z:ui_y
        lda     #WD_FILL | (C_BODY << 8)
        jsr     ui_rect
        lda     sttop
        clc
        adc     #STH - 1
        sta     z:ui_y
        lda     #WD_FILL | (C_BODY << 8)
        jsr     ui_rect
        lda     sttop                   ; the texts, and the body between them
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
        lda     sttop
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
        lda     z:t1
        bne     @long
        stz     sn_f                    ; 16 bits: by subtracting powers of ten
        ldx     #0
@p:     stz     sn_d
        lda     z:t0
:       cmp     pow10,x
        bcc     :+
        sbc     pow10,x
        inc     sn_d
        bra     :-
:       sta     z:t0
        lda     sn_d
        ora     sn_f
        beq     :+
        sta     sn_f
        lda     sn_d
        clc
        adc     #'0'
        sep     #$20
        .a8
        sta     a:0,y
        rep     #$20
        .a16
        iny
:       inx
        inx
        cpx     #8
        bcc     @p
        lda     z:t0
        clc
        adc     #'0'
        sta     a:0,y                   ; (and the zero after it)
        iny
        rts
@long:  ldx     #0                      ; digits, last first, on the stack
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

; ---------------------------------------------------------------- names and alerts
; an alert: message X (then the file's name), error code A (0: none). In the self test
; the message goes to the console.
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
@show:  lda     nodraw
        beq     :+
        ptr     msgbuf
        jsr     out_str
        jmp     put_nl
:       ldx     #.loword(al_err)
        jmp     ui_alert
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

; the window title: "Write: name" (and " *" when changed)
settitle:
        lda     nodraw
        bne     @out
        ldx     #.loword(t_wtitle)
        ldy     #.loword(msgbuf)
        jsr     ui_strcpy
        jsr     basename
        ldy     #.loword(msgbuf+7)
        jsr     ui_strcpy
        cmp     #22                     ; cut long names
        bcc     :+
        lda     #'.' | ('.' << 8)
        sta     msgbuf+7+19
        stz     msgbuf+7+21
:       lda     emod
        beq     :+
        ldx     #.loword(t_star)
        jsr     append
:       lda     win
        ptr     msgbuf
        sys     SYS_WTITLE
@out:   rts

setmod: lda     emod
        bne     :+
        inc     emod
        jsr     settitle
:       rts

; unsaved changes: ask (Save / Discard / Cancel) -> C set: stop (cancelled, or not saved)
confirm:
        jsr     arm_drop
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

        .include "write_store.s"
        .include "write_md.s"
        .include "write_view.s"
        .include "write_fmt.s"
        .include "write_file.s"
        .include "write_tb.s"
        .include "write_test.s"

        .segment "RODATA"
; the menus (items with a state byte: their check marks; after a TAB: the shortcut)
menus:  .byte   "File", 0, "New", 9, "Ctrl+N", 0, "Open...", 9, "Ctrl+O", 0
        .byte   "Save", 9, "Ctrl+S", 0, "Save as...", 0, "Export text...", 0, "-", 0
        .byte   "Print", 9, "Ctrl+P", 0, "-", 0, "Close", 9, "Ctrl+W", 0, 0
        .byte   "Edit", 0, MS_STATE, "Undo", 9, "Ctrl+Z", 0, MS_STATE, "Redo", 9, "Ctrl+Y", 0
        .byte   "-", 0, "Cut", 9, "Ctrl+X", 0, "Copy", 9, "Ctrl+C", 0, "Paste", 9, "Ctrl+V", 0
        .byte   "Select all", 9, "Ctrl+A", 0, "-", 0, "Find...", 9, "Ctrl+F", 0
        .byte   "Find next", 9, "F3", 0, "Replace...", 9, "Ctrl+H", 0
        .byte   "Go to line...", 9, "Ctrl+L", 0, 0
        .byte   "View", 0, MS_STATE, "Show markup", 0, MS_STATE, "Page width", 0, "-", 0
        .byte   "Word count", 0, 0
        .byte   "Format", 0, MS_STATE, "Bold", 9, "Ctrl+B", 0, MS_STATE, "Italic", 9, "Ctrl+I", 0
        .byte   MS_STATE, "Code", 9, "Ctrl+E", 0, "-", 0
        .byte   MS_STATE, "Heading 1", 9, "Ctrl+1", 0, MS_STATE, "Heading 2", 9, "Ctrl+2", 0
        .byte   MS_STATE, "Heading 3", 9, "Ctrl+3", 0, MS_STATE, "Normal text", 9, "Ctrl+0", 0
        .byte   "-", 0, MS_STATE, "Bullet list", 9, "Ctrl+8", 0
        .byte   MS_STATE, "Numbered list", 9, "Ctrl+7", 0, MS_STATE, "Quote", 9, "Ctrl+9", 0
        .byte   MS_STATE, "Rule", 9, "Ctrl+-", 0, "-", 0, "Indent list", 9, "Tab", 0
        .byte   MS_STATE, "Outdent list", 9, "Shift+Tab", 0, 0, 0
MN_LAST = 15                            ; (Format's last item)
        .res    32
; the short menus, for a kernel that keeps 254 bytes of them (win_menu reads 256; full:
; (0.23) Print is not in them, ctrl-P prints)
menus_s: .byte  "File", 0, "New", 0, "Open...", 0, "Save", 0, "Save as...", 0, "Export...", 0
        .byte   "-", 0, "Close", 0, 0
        .byte   "Edit", 0, "Undo", 0, "Redo", 0, "-", 0, "Cut", 0, "Copy", 0, "Paste", 0
        .byte   "Select all", 0, "Find...", 0, "Replace...", 0, "Go to...", 0, 0
        .byte   "View", 0, MS_STATE, "Show markup", 0, MS_STATE, "Page width", 0
        .byte   "Word count", 0, 0
        .byte   "Format", 0, "Bold", 0, "Italic", 0, "Code", 0, "-", 0, "Heading 1", 0
        .byte   "Heading 2", 0, "Heading 3", 0, "Normal", 0, "Bullets", 0, "Numbers", 0
        .byte   "Quote", 0, 0, 0
        .res    256 - (* - menus_s)
; each menu's items: their number, their handlers (the long menus, then the short ones)
mnn:    .word   9, 12, 4, 16, 7, 10, 3, 11
mnt:    .addr   ftab, etab, vtab, fmtab, ftab_s, etab_s, vtab_s, fmtab_s
ftab:   .addr   m_new, m_open, m_save, m_saveas, m_export, loop, m_print, loop, m_close
ftab_s: .addr   m_new, m_open, m_save, m_saveas, m_export, loop, m_close
popitems: .byte "Undo", 9, "Ctrl+Z", 0, "Redo", 9, "Ctrl+Y", 0, "-", 0, "Cut", 9, "Ctrl+X", 0
        .byte   "Copy", 9, "Ctrl+C", 0, "Paste", 9, "Ctrl+V", 0, "Select all", 9, "Ctrl+A", 0, 0
etab:   .addr   m_undo, m_redo, loop, m_cut, m_copy, m_paste, m_all, loop, m_find, m_fnext
        .addr   m_repl, m_goto
vtab:   .addr   m_markup, m_page, loop, m_count
fmtab:  .addr   f_bold, f_ital, f_code, loop, f_h1, f_h2, f_h3, f_norm, loop, f_bul, f_num
        .addr   f_quote, f_rule, loop, f_indent, f_outdent
etab_s: .addr   m_undo, m_redo, loop, m_cut, m_copy, m_paste, m_all, m_find, m_repl, m_goto
vtab_s: .addr   m_markup, m_page, m_count
fmtab_s: .addr  f_bold, f_ital, f_code, loop, f_h1, f_h2, f_h3, f_norm, f_bul, f_num, f_quote
pow10:  .word   10000, 1000, 100, 10
khtab:  .addr   f_norm, f_h1, f_h2, f_h3
; ctrl + letter (key_ascii: 1-26) -> handler
kctab:  .word   1, m_all, 3, m_copy, 24, m_cut, 22, m_paste, 19, m_save, 15, m_open
        .word   14, m_new, 26, m_undo, 25, m_redo, 6, m_find, 7, m_fnext, 8, m_repl
        .word   12, m_goto, 2, f_bold, 9, f_ital, 5, f_code, 16, m_print
        .word   '8', f_bul, '7', f_num, '9', f_quote, '-', f_rule, 0
ctls:   .addr   es_sb, 0
blknames: .addr 0, t_h1, t_h2, t_h3, t_bul, t_num, t_quo, t_rule, 0
t_h1:   .byte   "Heading 1", 0
t_h2:   .byte   "Heading 2", 0
t_h3:   .byte   "Heading 3", 0
t_bul:  .byte   "Bullet list", 0
t_num:  .byte   "Numbered list", 0
t_quo:  .byte   "Quote", 0
t_rule: .byte   "Rule", 0
t_gap:  .byte   "     ", 0
t_prn:  .byte   "/PRN:Write", 0
t_printed: .byte "Printed", 0
m_cantprint: .byte "Cannot print ", 0
t_wtitle: .byte "Write: ", 0
t_star: .byte   " *", 0
t_newname: .byte "Untitled.md", 0
t_open: .byte   "Open", 0
t_saveas: .byte "Save as", 0
t_export: .byte "Export plain text", 0
t_title: .byte  "Write", 0
t_line: .byte   "Line ", 0
t_of:   .byte   " of ", 0
t_col:  .byte   ", column ", 0
t_words: .byte  " words", 0
t_word: .byte   " word", 0
t_modif: .byte  "     Modified", 0
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
wopen:  .word   16, 20, 604, 310
        .faraddr t_title
        .byte   WF_RESIZE | WF_HOVER
es_sb:  .byte   UT_VSCROLL, 0
        .word   0, 0, UI_SBW, 0, 0
        .word   0, 0, 1, 1, 0, 0
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
tmode:  .res    2                       ; 1: write -t, 2: write -b
wsown:  .res    2
win:    .res    2
sbank:  .res    2
tbank:  .res    2
rbank:  .res    2
cw:     .res    2
chh:    .res    2
tw:     .res    2                       ; the text area
th:     .res    2
sttop:  .res    2                       ; the status line's top
vbank:  .res    2                       ; VB: the records of the rows drawn
tl:     .res    2                       ; the text column
colw:   .res    2
vis:    .res    2                       ; rows wholly in view
top:    .res    2
toff:   .res    2
showmk: .res    2                       ; View > Show markup
pagew:  .res    2                       ; View > Page width
rv_l:   .res    2                       ; the line laid out with its markers (the cursor's)
dr_rv:  .res    2                       ; the one drawn so
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
mk_n:   .res    2                       ; marks
mk_l0:  .res    NMARK * 2
mk_l1:  .res    NMARK * 2
mk_c0:  .res    NMARK * 2
mk_c1:  .res    NMARK * 2
mk_a:   .res    2
mk_b:   .res    2
mk_cc0: .res    2
mk_cc1: .res    2
pgdir:  .res    2
pgn:    .res    2
clk_t:  .res    2                       ; the last press: time, place, count
clk_x:  .res    2
clk_y:  .res    2
clk_n:  .res    2
clk_l:  .res    2
clk_c:  .res    2
st_ok:  .res    2                       ; the status line is drawn
stbuf:  .res    48
stbuf2: .res    64
stlast: .res    48
stlast2: .res   64
stnote: .res    2                       ; (0.23) the status line's note (0: none)
fpath:  .res    130
abuf:   .res    130
dlgbuf: .res    130
msgbuf: .res    200
mn_h:   .res    2                       ; the menu item's handler
sn_d:   .res    2                       ; snum32
sn_f:   .res    2

        .segment "ZEROPAGE"
lp:     .res    4
sp:     .res    4
dp:     .res    4
zlo:    .res    4
zhi:    .res    4
ub:     .res    4
ubs:    .res    4
up:     .res    4
mb:     .res    4                       ; the line model (styles, advances)
gp:     .res    4                       ; the row buffer
t0:     .res    2
t1:     .res    2
t2:     .res    2
t3:     .res    2
t4:     .res    2
t5:     .res    2
