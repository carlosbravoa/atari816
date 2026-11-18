; write_test.s - Write: "write -t SCRIPT" (the self test, no window: the results go to the
; console, so to the debug log) and "write -b FILE" (timings in the window). Part of
; write.s.
;
; The script, line by line ("X args"):
;   # ...               a comment
;   = NAME              a group of checks starts (the last one's result is printed:
;                       "PASS NAME", or "FAIL NAME" after a line for each failed check)
;   ? KIND STYLES|TEXT  line TEXT is read as block KIND (P H1 H2 H3 UL OL Q HR BL; a list's
;                       level as a digit after it: UL1) with the styles STYLES, one letter
;                       a column: . text, p block marker, m inline marker, b bold,
;                       i italic, x bold italic, c code
;   n                   a new, empty document
;   d TEXT              a line added at the document's end (the first one after n
;                       replaces its empty line)
;   s L0 C0 L1 C1       the selection: anchor line, column, cursor line, column (from 0)
;   c CMD [TEXT]        a command: bold ital code h1 h2 h3 norm bul num quote (Format),
;                       enter tab stab bs del undo redo, type TEXT
;   e TEXT              a line the document must have (in order)
;   x                   the document must be the lines given by e (which are then dropped)
;   o PATH, w PATH      open, save (as)
;   t PATH              export plain text
;   k PATH1 PATH2       the two files must be equal, byte for byte
;   r PATH              round trip: PATH opened, saved as /WT.OUT, must equal PATH
;   v N                 the word count must be N
;   a PATH              save as (File > Save as without the dialog: a name without an
;                       extension gets ".md")
;   y NAMES             the toolbar's buttons shown pressed in must be these (undo redo
;                       bold ital code h1 h2 h3 norm bul num quote rule; none: "y")
; At the end: "WRITE TEST END: g groups, f failed".
;
; The commands run as they do from a key or a menu: tst_sp makes the event loop return
; to the script (loop: "S = tst_sp, RTS").

TSMAX   = $C000                         ; the script's room (bank TB)
TEMAX   = 48                            ; expected lines

        .segment "CODE"

test_run:
        lda     #600                    ; a view's geometry, for the layout
        sta     cw
        lda     #300
        sta     chh
        jsr     geom
        lda     tmode
        cmp     #2
        jeq     bench
        lda     #1
        sta     nodraw
        sys     SYS_BALLOC              ; the script into a bank of its own
        bcc     :+
        print   "write: not enough memory\n"
        lda     #1
        jmp     exit_a
:       sta     z:tsk+2
        stz     z:tsk
        ptr     fpath
        lda     #O_READ
        sys     SYS_OPEN
        bcc     :+
        print   "write: cannot open the test script\n"
        lda     #1
        jmp     exit_a
:       sta     fh
        sta     rblk
        stz     rblk+1
        lda     z:tsk+2
        sta     rblk+3
        lda     #TSMAX
        sta     rblk+4
        lda     #0
        ptr     rblk
        sys     SYS_READ
        bcc     :+
        lda     #0
:       sta     ts_len
        sta     te_top
        lda     fh
        sys     SYS_CLOSE
        print   "WRITE TEST START\n"
        stz     ts_pos
        stz     tg_n
        stz     tg_bad
        stz     tg_on
        stz     te_n
@line:  jsr     ts_line                 ; -> lbuf, ts_ln
        bcs     @end
        lda     lbuf
        and     #$00FF
        cmp     #'#'
        beq     @line
        cmp     #'='
        bne     :+
        jsr     tg_end
        jsr     tg_start
        bra     @line
:       sta     z:t5
        ldx     #0
:       lda     tcmds,x
        beq     @bad
        cmp     z:t5
        beq     :+
        inx
        inx
        inx
        inx
        bra     :-
:       jsr     (tcmds+2,x)
        bra     @line
@bad:   ldx     #.loword(tm_bad)
        jsr     t_fail
        bra     @line
@end:   jsr     tg_end
        print   "WRITE TEST END: "
        lda     tg_n
        jsr     put_dec
        print   " groups, "
        lda     tg_bad
        jsr     put_dec
        print   " failed\n"
        jsr     out_flush
        lda     tg_bad
        jmp     exit_a

; the next script line -> lbuf (zero-terminated, at most 250 characters); C set: none left
ts_line:
        lda     ts_pos
        cmp     ts_len
        bcc     :+
        rts
:       tay
        ldx     #0
@c:     cpy     ts_len
        bcs     @e
        lda     [tsk],y
        iny
        and     #$00FF
        cmp     #13
        beq     @c
        cmp     #10
        beq     @e
        cpx     #250
        bcs     @c
        sep     #$20
        .a8
        sta     lbuf,x
        rep     #$20
        .a16
        inx
        bra     @c
@e:     sty     ts_pos
        stz     lbuf,x
        txa
        sta     ts_ll
        clc
        rts

; groups
tg_start:
        ldx     #.loword(lbuf+2)
        ldy     #.loword(tg_name)
        jsr     ui_strcpy
        lda     #1
        sta     tg_on
        stz     tg_f
        inc     tg_n
        rts
tg_end: lda     tg_on
        beq     @out
        stz     tg_on
        lda     tg_f
        beq     :+
        inc     tg_bad
        print   "FAIL "
        bra     :++
:       print   "PASS "
:       ptr     tg_name
        jsr     out_str
        jsr     put_nl
@out:   rts

; a failed check: message X, then the script line
t_fail: phx
        lda     #1
        sta     tg_f
        print   "  "
        plx
        ldy     #^tm_bad
        jsr     out_str
        print   ": "
        ptr     lbuf
        jsr     out_str
        jmp     put_nl

; the argument after the command letter and a space -> X (in lbuf)
t_arg:  ldx     #.loword(lbuf+2)
        rts

; a number at X (in lbuf, spaces first) -> A, X after it
tt_num:  lda     a:0,x
        and     #$00FF
        cmp     #' '
        bne     :+
        inx
        bra     tt_num
:       stz     z:t0
:       lda     a:0,x
        and     #$00FF
        cmp     #'0'
        bcc     :+
        cmp     #'9' + 1
        bcs     :+
        sbc     #'0' - 1
        sta     z:t1
        lda     z:t0
        asl     a
        asl     a
        adc     z:t0
        asl     a
        adc     z:t1
        sta     z:t0
        inx
        bra     :-
:       lda     z:t0
        rts

; ? KIND STYLES|TEXT
t_parse:
        ldx     #.loword(lbuf+2)        ; the kind
        ldy     #0
:       lda     tkinds,y
        and     #$00FF
        beq     @kbad
        sta     z:t0
        lda     a:0,x
        and     #$00FF
        cmp     z:t0
        bne     @kn
        lda     tkinds+1,y
        and     #$00FF
        sta     z:t0
        lda     a:1,x
        and     #$00FF
        cmp     z:t0
        beq     @kok
@kn:    iny
        iny
        iny
        bra     :-
@kbad:  ldx     #.loword(tm_bad)
        jmp     t_fail
@kok:   lda     tkinds+2,y
        and     #$00FF
        sta     tp_kind
        stz     tp_lvl
        lda     a:2,x                   ; a level: a digit after the two letters
        and     #$00FF
        sec
        sbc     #'0'
        cmp     #10
        bcs     :+
        sta     tp_lvl
:       lda     a:0,x                   ; the kind's end
        and     #$00FF
        jeq     @kbad
        cmp     #' '
        beq     :+
        inx
        bra     :-
:       inx
        stx     tp_st
:       lda     a:0,x
        and     #$00FF
        jeq     @kbad
        cmp     #'|'
        beq     :+
        inx
        bra     :-
:       txa
        sec
        sbc     tp_st
        sta     tp_n
        inx
        jsr     t_doc1                  ; the document: that line
        lda     #0
        jsr     lget
        jsr     md_block
        jsr     md_inline
        lda     #NONE
        sta     ml_line
        lda     m_blk
        cmp     tp_kind
        bne     @bad
        lda     m_lvl
        cmp     tp_lvl
        bne     @bad
        lda     tp_n
        cmp     llen
        bne     @bad
        ldx     tp_st                   ; each column's style
        ldy     #4
@c:     tya
        sec
        sbc     #4
        cmp     llen
        bcs     @ok
        lda     [mb],y
        and     #$00FF
        sta     z:t0
        and     #S_P
        beq     :+
        lda     #'p'
        bra     @cmp
:       lda     z:t0
        and     #S_M
        beq     :+
        lda     #'m'
        bra     @cmp
:       lda     z:t0
        and     #S_C
        beq     :+
        lda     #'c'
        bra     @cmp
:       lda     z:t0
        and     #S_B | S_I
        asl     a
        phx
        tax
        lda     tstyl,x
        plx
@cmp:   sta     z:t2
        lda     a:0,x
        and     #$00FF
        cmp     z:t2
        bne     @bad
        inx
        iny
        bra     @c
@ok:    rts
@bad:   ldx     #.loword(tm_parse)
        jsr     t_fail
        print   "  read: "
        lda     m_blk
        jsr     put_dec
        print   " "
        lda     m_lvl
        jsr     put_dec
        print   " "
        ldy     #4
:       tya
        sec
        sbc     #4
        cmp     llen
        bcs     :+
        lda     [mb],y
        and     #$00FF
        phy
        jsr     put_hex8
        print   " "
        ply
        iny
        bra     :-
:       jmp     put_nl

; the document made of the one line at X (in lbuf)
t_doc1: phx
        jsr     t_new
        plx
        bra     t_add
; d TEXT
t_d:    ldx     #.loword(lbuf+2)
        ; fall through
; the line at X (in lbuf) added at the end
t_add:  stx     td_p
        jsr     ui_strlen
        sta     td_n
        lda     td_empty
        bne     :+
        lda     nl                      ; after the last line: a line end, then it
        dec     a
        sta     cl
        jsr     lget
        lda     llen
        sta     cc
        jsr     anchor0
        lda     #10
        sta     onech
        lda     #.loword(onech)
        sta     isrc
        lda     #^onech
        sta     isrc+2
        lda     #1
        jsr     inst
:       stz     td_empty
        lda     nl
        dec     a
        sta     cl
        jsr     lget
        lda     llen
        sta     cc
        jsr     anchor0
        lda     td_n
        beq     :+
        lda     td_p
        sta     isrc
        lda     #^lbuf
        sta     isrc+2
        lda     td_n
        jsr     inst
:       stz     cl
        stz     cc
        jmp     anchor0
; n
t_new:  jsr     tx_reset
        lda     #1
        sta     td_empty
        rts

; s L0 C0 L1 C1
t_sel:  ldx     #.loword(lbuf+2)
        jsr     tt_num
        sta     al
        jsr     tt_num
        sta     ac
        jsr     tt_num
        sta     cl
        jsr     tt_num
        sta     cc
        rts

; c CMD [TEXT]: as a key or a menu would
t_cmd:  stz     shift
        ldy     #0
@f:     lda     tcmdn,y
        and     #$00FF
        beq     @bad
        ldx     #.loword(lbuf+2)
        phy
@m:     lda     tcmdn,y
        and     #$00FF
        beq     @end
        sta     z:t0
        lda     a:0,x
        and     #$00FF
        cmp     z:t0
        bne     @no
        inx
        iny
        bra     @m
@end:   lda     a:0,x                   ; (the word ends there)
        and     #$00FF
        beq     :+
        cmp     #' '
        bne     @no
:       ply
        tya                             ; its handler: after its name's zero
        tax
:       lda     tcmdn,x
        and     #$00FF
        beq     :+
        inx
        bra     :-
:       lda     tcmdn+1,x
        sta     tc_h
        lda     tc_h
        cmp     #.loword(t_type)
        beq     t_type
        cmp     #.loword(k_tab_s)
        bne     :+
        lda     #1
        sta     shift
        lda     #.loword(k_tab)
        sta     tc_h
:       lda     #9                      ; (k_tab's key)
        sta     key
        jmp     t_call
@no:    ply
:       lda     tcmdn,y                 ; the next name
        iny
        and     #$00FF
        bne     :-
        iny
        iny
        bra     @f
@bad:   ldx     #.loword(tm_bad)
        jmp     t_fail
; the handler tc_h run as from the event loop (back here at its "jmp loop")
t_call: jsr     snap
        tsx
        stx     tst_sp
        ldx     #0
        jmp     (tc_h,x)
; type TEXT: each character as a key
t_type: ldx     #.loword(lbuf+7)
@l:     lda     a:0,x
        and     #$00FF
        beq     @out
        sta     key
        phx
        lda     #.loword(k_char)
        sta     tc_h
        jsr     t_call
        plx
        inx
        bra     @l
@out:   rts
k_tab_s:

; e TEXT (kept in the script's bank, after the script)
t_exp:  ldx     te_n
        cpx     #TEMAX * 2
        bcs     @out
        lda     ts_ll
        sec
        sbc     #2
        bpl     :+
        lda     #0
:       sta     te_l,x
        sta     z:t0
        lda     te_top
        sta     te_p,x
        inx
        inx
        stx     te_n
        ldx     #0
        ldy     te_top
        sep     #$20
        .a8
:       cpx     z:t0
        bcs     :+
        lda     lbuf+2,x
        sta     [tsk],y
        inx
        iny
        bra     :-
:       rep     #$20
        .a16
        sty     te_top
@out:   rts

; x: the document is the lines expected?
t_cmpdoc:
        lda     te_n
        lsr     a
        cmp     nl
        bne     @bad
        ldx     #0
@l:     cpx     te_n
        bcs     @ok
        phx
        txa
        lsr     a
        jsr     lget
        plx
        lda     te_l,x
        cmp     llen
        bne     @bad
        lda     te_p,x                  ; the bytes
        sta     z:t0
        ldy     #4
        stx     z:t2
:       tya
        sec
        sbc     #4
        cmp     llen
        bcs     :+
        sty     z:t1
        ldy     z:t0
        lda     [tsk],y
        inc     z:t0
        ldy     z:t1
        eor     [lp],y
        and     #$00FF
        bne     @bad
        iny
        bra     :-
:       ldx     z:t2
        inx
        inx
        bra     @l
@ok:    stz     te_n
        lda     ts_len
        sta     te_top
        rts
@bad:   stz     te_n
        lda     ts_len
        sta     te_top
        ldx     #.loword(tm_doc)
        jsr     t_fail
        jmp     t_show
; the document on the console (after a failed check)
t_show: stz     cpi
@l:     lda     cpi
        cmp     nl
        bcs     @out
        print   "  | "
        lda     cpi
        jsr     lget
        ldy     #4
:       tya
        sec
        sbc     #4
        cmp     llen
        bcs     :+
        lda     [lp],y
        and     #$00FF
        phy
        jsr     out_char
        ply
        iny
        bra     :-
:       jsr     put_nl
        inc     cpi
        bra     @l
@out:   rts

; o PATH
tt_open: jsr     t_path
        jsr     load
        stz     td_empty
        rts
; w PATH
t_save: jsr     t_path
        jsr     save
        bcc     :+
        ldx     #.loword(tm_save)
        jmp     t_fail
:       rts
; t PATH
tt_export:
        ldx     #.loword(lbuf+2)
        jsr     exportf
        bcc     :+
        ldx     #.loword(tm_save)
        jmp     t_fail
:       rts
; the path argument -> fpath
t_path: ldx     #.loword(lbuf+2)
        ldy     #.loword(fpath)
        jmp     ui_strcpy
; r PATH: open, save as /WT.OUT, compare
t_rt:   jsr     t_path
        jsr     load
        stz     td_empty
        ldx     #.loword(fpath)         ; (the name kept for the comparison)
        ldy     #.loword(tk_a)
        jsr     ui_strcpy
        ldx     #.loword(tm_out)
        ldy     #.loword(fpath)
        jsr     ui_strcpy
        jsr     save
        ldx     #.loword(tk_a)
        ldy     #.loword(tm_out)
        jmp     t_fcmp
; k PATH1 PATH2
t_k:    ldx     #.loword(lbuf+2)        ; the two paths
:       lda     a:0,x
        and     #$00FF
        beq     @bad
        cmp     #' '
        beq     :+
        inx
        bra     :-
:       sep     #$20
        .a8
        stz     a:0,x
        rep     #$20
        .a16
        inx
        txy
        ldx     #.loword(lbuf+2)
        jmp     t_fcmp
@bad:   ldx     #.loword(tm_bad)
        jmp     t_fail
; files X and Y (paths in our bank) equal, byte for byte? (sbank, tbank hold them)
t_fcmp: stx     tk_x
        sty     tk_y
        ldx     tk_x
        lda     sbank
        jsr     @read
        sta     tk_n1
        bcs     @bad
        ldx     tk_y
        lda     tbank
        jsr     @read
        sta     tk_n2
        bcs     @bad
        lda     tk_n1
        cmp     tk_n2
        bne     @bad
        stz     z:dp
        lda     tbank
        sta     z:dp+2
        stz     z:sp
        lda     sbank
        sta     z:sp+2
        ldy     #0
:       cpy     tk_n1
        bcs     :+
        lda     [sp],y
        eor     [dp],y
        and     #$00FF
        bne     @bad
        iny
        bra     :-
:       rts
@bad:   ldx     #.loword(tm_file)
        jmp     t_fail
; file X into bank A (64 KB at most) -> A = its length; C set: cannot
@read:  sta     rblk+3
        ldy     #^tk_a
        lda     #O_READ
        sys     SYS_OPEN
        bcs     :+
        sta     fh
        sta     rblk
        stz     rblk+1
        lda     #$FFF0
        sta     rblk+4
        ptr     rblk
        sys     SYS_READ
        pha
        php
        lda     fh
        sys     SYS_CLOSE
        plp
        pla
:       rts

; v N: the word count
tt_words:
        ldx     #.loword(lbuf+2)
        jsr     tt_num
        cmp     wc_tot
        bne     :+
        lda     wc_tot+2
        beq     :++
:       ldx     #.loword(tm_words)
        jmp     t_fail
:       rts

; a PATH: saved as PATH (".md" added to a name without an extension)
tt_saveas:
        ldx     #.loword(lbuf+2)
        ldy     #.loword(dlgbuf)
        jsr     ui_strcpy
        jsr     addmd
        jsr     saveto
        bcc     :+
        ldx     #.loword(tm_save)
        jmp     t_fail
:       rts

; y NAMES: the toolbar's state (the buttons pressed in)
t_tbst: stz     z:t5                    ; the bits named
        ldx     #.loword(lbuf+1)
@w:     lda     a:0,x                   ; the next name
        and     #$00FF
        beq     @cmp
        cmp     #' '
        bne     :+
        inx
        bra     @w
:       stx     tt_p
        ldy     #0                      ; which one?
        stz     tt_b
@n:     ldx     tt_p
        lda     tbnames,y
        and     #$00FF
        jeq     @bad
:       lda     tbnames,y
        and     #$00FF
        beq     @end
        sta     z:t0
        lda     a:0,x
        and     #$00FF
        cmp     z:t0
        bne     @no
        inx
        iny
        bra     :-
@end:   lda     a:0,x
        and     #$00FF
        beq     @yes
        cmp     #' '
        beq     @yes
@no:    lda     tbnames,y               ; the next name
        iny
        and     #$00FF
        bne     @no
        inc     tt_b
        bra     @n
@yes:   lda     tt_b
        asl     a
        tay
        lda     tbbit,y
        tsb     z:t5
        bra     @w
@cmp:   lda     z:t5
        sta     tt_b
        jsr     tb_calc
        lda     tb_st
        cmp     tt_b
        beq     :+
        ldx     #.loword(tm_tbst)
        jsr     t_fail
        print   "  shown (bits): "
        lda     tb_st
        jsr     put_hex16
        print   ", not "
        lda     tt_b
        jsr     put_hex16
        jmp     put_nl
:       rts
@bad:   ldx     #.loword(tm_bad)
        jmp     t_fail

; ---------------------------------------------------------------- write -b FILE
; Timings in the window, printed on the console: a full redraw, a character typed in a
; paragraph, the cursor moved, a scroll by one row, a page down (each until the screen
; shows it: ws_sync)
bench:  sys     SYS_WSSTART
        bcc     :+
        print   "write: no window system\n"
        lda     #1
        jmp     exit_a
:       sta     wsown
        jsr     ui_init
        ptr     wopen
        sys     SYS_WOPEN
        sta     win
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
        print   "WRITE BENCH: "
        ptr     fpath
        jsr     out_str
        jsr     put_nl
        jsr     bt_start                ; loading and the first view
        jsr     load
        jsr     settitle
        jsr     redraw_all
        lda     #1
        ldx     #.loword(bm_load)
        jsr     bt_end
        ; a full redraw, 5 times
        jsr     bt_start
        lda     #5
        sta     bt_n
:       jsr     redraw_all
        sys     SYS_WSSYNC
        dec     bt_n
        bne     :-
        lda     #5
        ldx     #.loword(bm_full)
        jsr     bt_end
        ; 20 characters typed in the middle of a paragraph of 3 rows (line 2, column 100)
        lda     #2
        sta     cl
        lda     #100
        sta     cc
        jsr     anchor0
        lda     #.loword(k_right)       ; (the cursor there, drawn)
        jsr     bt_key
        jsr     bt_start
        lda     #20
        sta     bt_n
:       lda     #'x'
        sta     key
        lda     #.loword(k_char)
        jsr     bt_key
        dec     bt_n
        bne     :-
        lda     #20
        ldx     #.loword(bm_type3)
        jsr     bt_end
        ; 20 characters typed in a paragraph (line 6, column 10)
        lda     #6
        sta     cl
        lda     #10
        sta     cc
        jsr     anchor0
        lda     #.loword(k_right)       ; (the cursor there, drawn)
        jsr     bt_key
        jsr     bt_start
        lda     #20
        sta     bt_n
:       lda     #'x'
        sta     key
        lda     #.loword(k_char)
        jsr     bt_key
        dec     bt_n
        bne     :-
        lda     #20
        ldx     #.loword(bm_type)
        jsr     bt_end
        ; 20 cursor moves to the right
        jsr     bt_start
        lda     #20
        sta     bt_n
:       lda     #KEY_RIGHT
        sta     key
        lda     #.loword(k_right)
        jsr     bt_key
        dec     bt_n
        bne     :-
        lda     #20
        ldx     #.loword(bm_right)
        jsr     bt_end
        ; 20 scrolls by a row (Down on the last row in view)
        lda     vis
        sta     bt_n
:       lda     #.loword(k_down)
        jsr     bt_key
        dec     bt_n
        bne     :-
        jsr     bt_start
        lda     #20
        sta     bt_n
:       lda     #.loword(k_down)
        jsr     bt_key
        dec     bt_n
        bne     :-
        lda     #20
        ldx     #.loword(bm_down)
        jsr     bt_end
        ; 5 pages down
        jsr     bt_start
        lda     #5
        sta     bt_n
:       lda     #.loword(k_pgdn)
        jsr     bt_key
        dec     bt_n
        bne     :-
        lda     #5
        ldx     #.loword(bm_pgdn)
        jsr     bt_end
        ; ctrl-End (to the text's end), then 20 characters typed there
        jsr     bt_start
        lda     #KEY_END
        sta     key
        lda     #$11
        sta     kmods
        lda     #.loword(bt_cend)
        jsr     bt_key
        lda     #1
        ldx     #.loword(bm_end)
        jsr     bt_end
        jsr     bt_start
        lda     #20
        sta     bt_n
:       lda     #'x'
        sta     key
        lda     #.loword(k_char)
        jsr     bt_key
        dec     bt_n
        bne     :-
        lda     #20
        ldx     #.loword(bm_type)
        jsr     bt_end
        jsr     out_flush
        stz     tst_sp
        jmp     quit
; ctrl-End
bt_cend:
        lda     nl
        dec     a
        sta     cl
        jsr     lget
        lda     llen
        sta     cc
        jmp     mv_h
; handler A run as a key, then drawn and shown
bt_key: sta     tc_h
        stz     shift
        jsr     t_call
        jmp     flush
bt_start:
        sys     SYS_WSSYNC
        sys     SYS_UPTIME
        sta     bt_t
        stx     bt_t+2
        rts
; "NAME: T ms" (the time since bt_start / A, one decimal)
bt_end: sta     bt_d
        phx
        sys     SYS_WSSYNC
        sys     SYS_UPTIME
        sec
        sbc     bt_t
        sta     z:t0                    ; ms (a 16-bit difference)
        plx
        ldy     #^bm_full
        jsr     out_str
        lda     z:t0                    ; * 10 / n
        asl     a
        sta     z:t1
        asl     a
        asl     a
        clc
        adc     z:t1
        sta     z:t0
        ldx     #0
:       cmp     bt_d
        bcc     :+
        sbc     bt_d
        inx
        bra     :-
:       txa
        sta     z:t2
        ldy     #.loword(msgbuf)
        lda     z:t2                    ; tenths -> "N.N"
        ldx     #0
:       cmp     #10
        bcc     :+
        sbc     #10
        inx
        bra     :-
:       sta     bt_d
        txa
        jsr     snum
        lda     #'.'
        sta     a:0,y
        iny
        lda     bt_d
        clc
        adc     #'0'
        sta     a:0,y
        iny
        lda     #0
        sta     a:0,y
        ptr     msgbuf
        jsr     out_str
        print   " ms\n"
        rts

        .segment "RODATA"
; script commands: the letter, the handler
tcmds:  .word   '?', t_parse, 'n', t_new, 'd', t_d, 's', t_sel, 'c', t_cmd, 'e', t_exp
        .word   'x', t_cmpdoc, 'o', tt_open, 'w', t_save, 't', tt_export, 'k', t_k
        .word   'r', t_rt, 'v', tt_words, 'a', tt_saveas, 'y', t_tbst, 0
; c: the command names and handlers
tcmdn:  .byte   "bold", 0
        .addr   f_bold
        .byte   "ital", 0
        .addr   f_ital
        .byte   "code", 0
        .addr   f_code
        .byte   "h1", 0
        .addr   f_h1
        .byte   "h2", 0
        .addr   f_h2
        .byte   "h3", 0
        .addr   f_h3
        .byte   "norm", 0
        .addr   f_norm
        .byte   "bul", 0
        .addr   f_bul
        .byte   "num", 0
        .addr   f_num
        .byte   "quote", 0
        .addr   f_quote
        .byte   "enter", 0
        .addr   k_enter
        .byte   "tab", 0
        .addr   k_tab
        .byte   "stab", 0
        .addr   k_tab_s
        .byte   "bs", 0
        .addr   k_bs
        .byte   "del", 0
        .addr   k_del
        .byte   "undo", 0
        .addr   m_undo
        .byte   "redo", 0
        .addr   m_redo
        .byte   "rule", 0
        .addr   f_rule
        .byte   "indent", 0
        .addr   f_indent
        .byte   "outdent", 0
        .addr   f_outdent
        .byte   "left", 0
        .addr   k_left
        .byte   "right", 0
        .addr   k_right
        .byte   "type", 0
        .addr   t_type
        .byte   0
; ? kinds: two letters, the block
tkinds: .byte   "P ", B_PARA, "H1", B_H1, "H2", B_H2, "H3", B_H3, "UL", B_BUL, "OL", B_NUM
        .byte   "Q ", B_QUO, "HR", B_RULE, "BL", B_BLANK, 0
tstyl:  .word   '.', 'b', 'i', 'x'
tm_bad: .byte   "bad script line", 0
tm_parse: .byte "not read so", 0
tm_doc: .byte   "the document differs", 0
tm_file: .byte  "the files differ", 0
tm_save: .byte  "cannot save", 0
tm_words: .byte "another word count", 0
tm_tbst: .byte  "another toolbar state", 0
; the toolbar's buttons by name
tbnames: .byte  "undo", 0, "redo", 0, "bold", 0, "ital", 0, "code", 0, "h1", 0, "h2", 0
        .byte   "h3", 0, "norm", 0, "bul", 0, "num", 0, "quote", 0, "rule", 0, 0
tm_out: .byte   "/WT.OUT", 0
bm_full: .byte  "full redraw: ", 0
bm_type: .byte  "a character typed: ", 0
bm_type3: .byte "a character typed, 3-row paragraph: ", 0
bm_right: .byte "cursor right: ", 0
bm_down: .byte  "scroll by a row (Down): ", 0
bm_pgdn: .byte  "page down: ", 0
bm_load: .byte  "load and first view: ", 0
bm_end: .byte   "ctrl-End: ", 0

        .segment "BSS"
nodraw: .res    2                       ; the self test: nothing drawn
tst_sp: .res    2                       ; (not 0) the event loop returns there
ts_len: .res    2
ts_pos: .res    2
ts_ll:  .res    2
tg_n:   .res    2
tg_bad: .res    2
tg_on:  .res    2
tg_f:   .res    2
tg_name: .res   64
tp_kind: .res   2
tp_lvl: .res    2
tp_st:  .res    2
tp_n:   .res    2
td_empty: .res  2
td_p:   .res    2
td_n:   .res    2
tc_h:   .res    2
te_n:   .res    2
te_p:   .res    TEMAX * 2
te_l:   .res    TEMAX * 2
te_top: .res    2
tk_x:   .res    2
tk_y:   .res    2
tk_n1:  .res    2
tk_n2:  .res    2
tk_a:   .res    130
bt_n:   .res    2
bt_t:   .res    4
bt_d:   .res    2
tt_p:   .res    2
tt_b:   .res    2
lbuf:   .res    256

        .segment "ZEROPAGE"
tsk:    .res    4                       ; the script's bank
