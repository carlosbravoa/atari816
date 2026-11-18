; term.s - terminal windows (window system, stage 2). A window opened with WF_TERM is a
; text screen of 8x12 cells (as many as its content holds, at most 128 x 40) that
; understands what the screen console does: CR, LF, BS, TAB, BEL (a beep), and ESC Y r c,
; ESC K, ESC E, ESC p / ESC q (inverse), ESC f / ESC e (cursor off / on). A task attached
; to it (ws_term, inherited by the tasks it starts) prints there and reads its keys from
; the terminal's own queue: the console syscalls work unchanged. Ctrl-C kills the
; borrower of the keyboard when it was lent with the break flag.
;
; Per terminal: one kernel bank. Cells at $0000 (physical row * 256 + column * 2:
; character, inverse; a ring of rows: row r is physical row (r + tm_top) mod rows, so a
; scroll moves no cells), the key ring at $C000 (32 x {usage, modifiers}).
;
; Drawing is deferred (jump scroll): output only changes the cells, marks the rows that
; changed (tm_d0 .. tm_d1) and counts the rows scrolled (tm_ps). The WS thread flushes a
; terminal just before it repaints (term_flush): one copy moves the pixels up by all the
; rows scrolled since the last flush, then the marked rows are drawn (a text call per run
; of characters of one attribute) with the cursor. So a burst of output costs one move
; and the new rows per repaint, not a move per line, and the screen never shows a half
; written state.

TM_FG   = C_LIGHT
TM_BG   = 16 + 1 * 6 + 2                ; (0, 51, 102): dark blue
TM_KEYS = $C000
tm_p    = $CC                           ; DP: 24-bit pointer into the terminal's bank

; ---- (win_open) window X gets WF_TERM: its bank, cleared cells, the background ----
term_open:
        stx     tm_w
        lda     #1
        jsr     bank_run
        bcc     :+
        rts
:       ldx     tm_w
        sta     tm_bank,x
        lda     w_w,x                   ; columns, rows of the content
        sec
        sbc     w_cx,x
        sec
        sbc     w_cx,x
        lsr     a
        lsr     a
        lsr     a
        cmp     #128
        bcc     :+
        lda     #128
:       sta     tm_cols,x
        lda     w_h,x
        sec
        sbc     w_cy,x
        sec
        sbc     w_cb,x
        ldy     #0
:       cmp     #12
        bcc     :+
        sbc     #12
        iny
        bra     :-
:       cpy     #40
        bcc     :+
        ldy     #40
:       tya
        sta     tm_rows,x
        stz     tm_inv,x
        stz     tm_coff,x
        stz     tm_esc,x
        stz     tm_kn,x
        stz     tm_kh,x
        lda     #NONE
        sta     tm_fg,x
        jsr     term_clear
        jsr     term_end                ; (the cursor at the first flush)
        ldx     tm_w
        jsr     win_damage
        clc
        rts

; ---- (win_close) window X: free its bank, detach its tasks ----
term_close:
        lda     w_fl,x
        bit     #WF_TERM
        beq     @out
        stz     tm_pw,x
        lda     tm_bank,x
        beq     :+
        phx
        jsr     bank_free
        plx
        stz     tm_bank,x
:       txa
        ora     #$8000
        sta     kt6
        ldy     #0
:       lda     t_term,y
        cmp     kt6
        bne     :+
        lda     #0
        sta     t_term,y
:       iny
        iny
        cpy     #NSLOT * 2
        bne     :--
@out:   rts

; A = t_term of the current task -> C clear and X = its terminal window*2, or C set
term_of_cur:
        ldx     cur
        lda     t_term,x
        bpl     @no
        and     #$7FFF
        tax
        lda     w_used,x
        beq     @no
        lda     w_fl,x
        bit     #WF_TERM
        beq     @no
        lda     tm_bank,x
        beq     @no
        clc
        rts
@no:    sec
        rts

; tm_p = the start of row A of terminal tm_w (X = tm_w; keeps X)
term_rowp:
        clc
        adc     tm_top,x
        cmp     tm_rows,x
        bcc     :+
        sbc     tm_rows,x
:       xba
        sta     tm_p
        lda     tm_bank,x
        sta     tm_p+2
        rts

; tm_p = the cell (tm_cx, tm_cy) of terminal tm_w (X = tm_w after)
term_cellp:
        ldx     tm_w
        lda     tm_cy,x
        jsr     term_rowp
        lda     tm_cx,x
        asl     a
        clc
        adc     tm_p
        sta     tm_p
        rts

; ---- output: term_begin (X = window*2), term_char (A) ..., term_end ----
term_begin:
        stx     tm_w
        rts

; the terminal has changed: drawn now when it was quiet for 2 ticks (a prompt, an echo),
; else by the WS thread before its next repaint (a burst: one scroll for many lines)
term_end:
        ldx     tm_w
        lda     ticks                   ; (tm_lt: the last output)
        sec
        sbc     tm_lt,x
        pha
        lda     ticks
        sta     tm_lt,x
        pla
        cmp     #2
        bcc     :+
        lda     ticks                   ; (and none drawn for 2 ticks: tm_lf)
        sec
        sbc     tm_lf,x
        cmp     #2
        bcc     :+
        lda     tm_pw,x                 ; (nothing else waiting for this one)
        bne     :+
        jmp     term_flush1
:       lda     #1
        sta     tm_pw,x
        sta     tm_pend
        lda     #W_WS
        ldy     #0
        jmp     k_wake_all

; A * 12 (keeps X)
mul12:  asl     a
        asl     a
        sta     tm_t
        asl     a
        clc
        adc     tm_t
        rts

; row A of terminal tm_w changed: drawn at the next flush (keeps A)
term_dirty:
        ldx     tm_w
        ; fall through
term_dirtyx:                            ; (X = the window)
        pha
        lda     tm_d0,x
        cmp     #$FFFF
        bne     :+
        lda     1,s
        sta     tm_d0,x
        sta     tm_d1,x
        pla
        rts
:       pla
        cmp     tm_d0,x
        bcs     :+
        sta     tm_d0,x
:       cmp     tm_d1,x
        bcc     :+
        sta     tm_d1,x
:       rts

; one character (A) to terminal tm_w
term_char:
        and     #$00FF
        sta     tm_c
        ldx     tm_w
        lda     tm_esc,x
        jne     @esc
        lda     tm_c
        cmp     #27
        bne     :+
        lda     #1
        sta     tm_esc,x
        rts
:       cmp     #' '
        bcc     @ctl
        cmp     #$7F
        bcc     :+
        rts
:       lda     tm_cx,x                 ; printable: wrap first if the line is full
        cmp     tm_cols,x
        bcc     :+
        stz     tm_cx,x
        jsr     term_nl
:       jsr     term_cellp
        ldx     tm_w
        lda     tm_inv,x
        xba
        ora     tm_c
        sta     [tm_p]
        lda     tm_cy,x
        jsr     term_dirtyx
        inc     tm_cx,x
        rts
@ctl:   cmp     #10
        bne     :+
        stz     tm_cx,x
        jmp     term_nl
:       cmp     #13
        bne     :+
        stz     tm_cx,x
        rts
:       cmp     #8
        bne     :+
        lda     tm_cx,x
        beq     @r
        dec     tm_cx,x
@r:     rts
:       cmp     #9
        bne     :+
        lda     tm_cx,x
        ora     #7
        inc     a
        cmp     tm_cols,x
        bcc     @tab
        lda     tm_cols,x
@tab:   sta     tm_cx,x
        rts
:       cmp     #7
        bne     @r
        jmp     k_errbeep
@esc:   cmp     #2                      ; ESC Y row / column
        bcc     @cmd
        bne     @col
        lda     tm_c
        sec
        sbc     #32
        bcc     :+
        cmp     tm_rows,x
        bcc     :++
:       lda     tm_rows,x
        dec     a
:       sta     tm_cy,x
        lda     #3
        sta     tm_esc,x
        rts
@col:   stz     tm_esc,x
        lda     tm_c
        sec
        sbc     #32
        bcc     :+
        cmp     tm_cols,x
        bcc     :++
:       lda     tm_cols,x
        dec     a
:       sta     tm_cx,x
        rts
@cmd:   stz     tm_esc,x
        lda     tm_c
        cmp     #'Y'
        bne     :+
        lda     #2
        sta     tm_esc,x
        rts
:       cmp     #'p'
        bne     :+
        lda     #1
        sta     tm_inv,x
        rts
:       cmp     #'q'
        bne     :+
        stz     tm_inv,x
        rts
:       cmp     #'f'
        bne     :+
        lda     #1
        sta     tm_coff,x
        rts
:       cmp     #'e'
        bne     :+
        stz     tm_coff,x
        rts
:       cmp     #'E'
        bne     :+
        jmp     term_clear
:       cmp     #'K'
        bne     @r2
        lda     tm_cx,x                 ; clear to the end of the line (inverse fills)
        pha
:       ldx     tm_w
        lda     tm_cx,x
        cmp     tm_cols,x
        bcs     :+
        jsr     term_cellp
        ldx     tm_w
        lda     tm_inv,x
        xba
        ora     #' '
        sta     [tm_p]
        lda     tm_cy,x
        jsr     term_dirtyx
        inc     tm_cx,x
        bra     :-
:       pla
        ldx     tm_w
        sta     tm_cx,x
@r2:    rts

; new line: down one row, scrolling at the bottom
term_nl:
        ldx     tm_w
        lda     tm_cy,x
        inc     a
        cmp     tm_rows,x
        bcs     :+
        sta     tm_cy,x
        rts
:       jmp     term_scroll

; ESC E: blank cells and screen (at once), home
term_clear:
        ldx     tm_w
        stz     tm_cx,x
        stz     tm_cy,x
        stz     tm_top,x
        stz     tm_ps,x
        lda     #$FFFF
        sta     tm_d0,x
        lda     #NONE
        sta     tm_dcy,x
        lda     tm_bank,x
        sta     tm_p+2
        stz     tm_p
        ldy     #0
        lda     #' '
:       sta     [tm_p],y
        iny
        iny
        cpy     #40 * 256
        bne     :-
        ldx     tm_w
        jsr     win_unstale             ; (drawn into the bitmap)
        jsr     win_surf
        jsr     win_clip
        ldx     tm_w
        lda     w_cx,x
        sta     kg_x
        lda     w_cy,x
        sta     kg_y
        lda     w_w,x
        sta     kg_w
        lda     w_h,x
        sta     kg_h
        lda     #TM_BG
        sta     kg_fg
        jsr     gfx_rect
        ldx     tm_w
        jmp     term_dmgall

; scroll the text up one row (the cursor stays on the last row): the ring turns, the new
; last row is blank; the pixels move at the flush
term_scroll:
        ldx     tm_w
        lda     tm_top,x
        inc     a
        cmp     tm_rows,x
        bcc     :+
        lda     #0
:       sta     tm_top,x
        lda     tm_rows,x               ; the last row blank
        dec     a
        jsr     term_rowp
        ldy     #0
        lda     #' '
:       sta     [tm_p],y
        iny
        iny
        cpy     #256
        bne     :-
        ldx     tm_w
        lda     tm_ps,x
        cmp     tm_rows,x
        bcs     :+
        inc     tm_ps,x
:       lda     tm_d0,x                 ; the rows to draw move up with the text
        cmp     #$FFFF
        beq     :+
        cmp     #0
        beq     :+
        dec     tm_d0,x
:       lda     tm_rows,x
        dec     a
        jmp     term_dirtyx

; damage terminal X's text area on the screen
term_dmgall:
        lda     w_x,x
        clc
        adc     w_cx,x
        sta     kg_x
        lda     w_y,x
        clc
        adc     w_cy,x
        sta     kg_y
        lda     tm_cols,x
        asl     a
        asl     a
        asl     a
        sta     kg_w
        lda     tm_rows,x
        jsr     mul12
        sta     kg_h
        jmp     damage

; ---- (WS thread, before a repaint) every terminal with output: its flush ----
term_flush:
        stz     tm_pend
        ldx     #0
:       lda     tm_pw,x
        beq     :+
        stz     tm_pw,x
        lda     w_used,x
        beq     :+
        lda     w_fl,x
        bit     #WF_TERM
        beq     :+
        lda     tm_bank,x
        beq     :+
        phx
        stx     tm_w
        jsr     term_flush1
        plx
:       inx
        inx
        cpx     #NWIN * 2
        bne     :--
        rts

; terminal tm_w: the pending scroll, the cursor, the marked rows (on the screen itself
; when the window is fully in view: win_target); tm_lf = the tick it ended
term_flush1:
        jsr     term_fl
        ldx     tm_w
        lda     ticks
        sta     tm_lf,x
        rts
term_fl:
        lda     tm_w
        sta     kg_e
        jsr     win_target
        ldx     tm_w
        lda     tm_ps,x
        beq     @cur
        cmp     tm_rows,x
        bcc     @move
        stz     tm_ps,x                 ; a page or more: everything is drawn
        lda     #NONE
        sta     tm_dcy,x
        lda     #0
        jsr     term_dirtyx
        lda     tm_rows,x
        dec     a
        jsr     term_dirtyx
        bra     @cur
@move:  lda     tm_dcy,x                ; the drawn cursor moves with the pixels
        cmp     #NONE
        beq     :++
        sec
        sbc     tm_ps,x
        bcs     :+
        lda     #NONE
:       sta     tm_dcy,x
:       jsr     win_retarget            ; rows ps.. -> 0..: one copy
        ldx     tm_w
        lda     w_cx,x
        clc
        adc     wo_x
        sta     kg_x
        sta     kg_dx
        lda     w_cy,x
        clc
        adc     wo_y
        sta     kg_dy
        lda     tm_ps,x
        jsr     mul12
        clc
        adc     kg_dy
        sta     kg_y
        lda     tm_rows,x
        sec
        sbc     tm_ps,x
        jsr     mul12
        sta     kg_h
        lda     tm_cols,x
        asl     a
        asl     a
        asl     a
        sta     kg_w
        jsr     gfx_move
        ldx     tm_w
        stz     tm_ps,x
        lda     wo_dir
        bne     @cur
        jsr     term_dmgall
@cur:   ldx     tm_w                    ; the cursor: where it should be (NONE: hidden)
        lda     tm_coff,x
        bne     @hid
        lda     tm_cx,x
        cmp     tm_cols,x
        bcs     @hid
        lda     tm_cy,x
        cmp     tm_dcy,x
        bne     :+
        lda     tm_cx,x
        cmp     tm_dcx,x
        beq     @rows
:       lda     tm_dcy,x                ; moved: the old and the new row
        cmp     #NONE
        beq     :+
        jsr     term_dirtyx
:       lda     tm_cy,x
        sta     tm_dcy,x
        jsr     term_dirtyx
        lda     tm_cx,x
        sta     tm_dcx,x
        bra     @rows
@hid:   lda     tm_dcy,x
        cmp     #NONE
        beq     @rows
        jsr     term_dirtyx
        lda     #NONE
        sta     tm_dcy,x
@rows:  lda     tm_d0,x                 ; the marked rows
        cmp     #$FFFF
        bne     :+
        rts
:       sta     tm_r
@row:   jsr     term_drow
        ldx     tm_w
        lda     tm_r
        inc     a
        sta     tm_r
        cmp     tm_d1,x
        beq     @row
        bcc     @row
        lda     wo_dir                  ; (on the screen: nothing to repaint)
        bne     @nod
        lda     w_x,x                   ; damage those rows
        clc
        adc     w_cx,x
        sta     kg_x
        lda     tm_d0,x
        jsr     mul12
        clc
        adc     w_cy,x
        adc     w_y,x
        sta     kg_y
        lda     tm_cols,x
        asl     a
        asl     a
        asl     a
        sta     kg_w
        lda     tm_d1,x
        sec
        sbc     tm_d0,x
        inc     a
        jsr     mul12
        sta     kg_h
        lda     #$FFFF
        sta     tm_d0,x
        jmp     damage
@nod:   lda     #$FFFF
        sta     tm_d0,x
        rts

; draw row tm_r of terminal tm_w from its cells: one text call per run of one attribute
; (inverse, or the cursor's cell inverted)
term_drow:
        ldx     tm_w
        lda     tm_r
        jsr     term_rowp
        stz     tm_col
@run:   ldx     tm_w
        lda     tm_col
        cmp     tm_cols,x
        bcc     :+
        rts
:       sta     tm_rs
        jsr     @attr
        sta     tm_at
        stz     tm_ri
@ch:    ldx     tm_w                    ; characters while the attribute stays
        lda     tm_col
        cmp     tm_cols,x
        bcs     @draw
        jsr     @attr
        cmp     tm_at
        bne     @draw
        lda     tm_col
        asl     a
        tay
        lda     [tm_p],y
        ldy     tm_ri
        a8
        sta     tm_rb,y
        a16
        inc     tm_ri
        inc     tm_col
        bra     @ch
@draw:  ldy     tm_ri
        lda     #0
        a8
        sta     tm_rb,y
        a16
        lda     tm_w
        sta     kg_e
        jsr     win_retarget
        ldx     tm_w
        lda     #TM_FG
        sta     kg_fg
        lda     #TM_BG
        sta     kg_bg
        lda     tm_at
        beq     :+
        lda     #TM_BG
        sta     kg_fg
        lda     #TM_FG
        sta     kg_bg
:       lda     tm_rs
        asl     a
        asl     a
        asl     a
        clc
        adc     w_cx,x
        adc     wo_x
        sta     kg_x
        lda     tm_r
        jsr     mul12
        clc
        adc     w_cy,x
        adc     wo_y
        sta     kg_y
        lda     #.loword(tm_rb)
        sta     kg_ln
        lda     #KBANK
        sta     kg_ln+2
        lda     #1
        sta     kg_i
        lda     tm_p                    ; (gfx_text may use it)
        pha
        lda     tm_p+2
        pha
        jsr     gfx_text
        pla
        sta     tm_p+2
        pla
        sta     tm_p
        jmp     @run
; the attribute of cell tm_col: its inverse flag, inverted at the cursor (X = tm_w)
@attr:  lda     tm_col
        asl     a
        tay
        lda     [tm_p],y
        xba
        and     #$00FF
        sta     tm_t
        lda     tm_r
        cmp     tm_dcy,x
        bne     :+
        lda     tm_col
        cmp     tm_dcx,x
        bne     :+
        lda     tm_t
        eor     #1
        rts
:       lda     tm_t
        rts

; ---- input: (WS thread) a key for terminal X: kg_t = usage, kg_u = mods | down << 8 ----
term_key:
        stx     tm_w
        lda     kg_t                    ; ctrl-C down: break the borrower (lent with the
        cmp     #$06                    ; break flag)
        bne     @q
        lda     kg_u
        cmp     #$0100
        bcc     @q
        and     #$0011
        beq     @q
        lda     tm_fg,x
        bmi     @q
        tay
        lda     t_lender,y
        cmp     #NONE
        beq     @q
        lda     t_lbrk,y
        beq     @q
        tyx
        jmp     kill_slot
@q:     ldx     tm_w
        lda     tm_kn,x
        cmp     #32
        bcs     @out
        clc
        adc     tm_kh,x
        and     #31
        asl     a
        asl     a
        clc
        adc     #TM_KEYS
        sta     tm_p
        lda     tm_bank,x
        sta     tm_p+2
        lda     kg_t
        sta     [tm_p]
        ldy     #2
        lda     kg_u
        sta     [tm_p],y
        inc     tm_kn,x
        lda     tm_fg,x                 ; wake the reader
        bmi     @out
        tax
        lda     t_state,x
        cmp     #TS_BLOCKED
        bne     @out
        lda     t_wreason,x
        cmp     #W_INPUT
        bne     @out
        jmp     k_wake
@out:   rts

; ---- the console and input syscalls for a task attached to a terminal ----
; (each: C set if the current task has no terminal: the normal path)

; putc: A = the character
term_putc:
        pha
        jsr     term_of_cur
        bcc     :+
        pla
        rts
:       jsr     term_begin
        pla
        jsr     term_char
        jsr     term_end
        clc
        rts

; puts: the string at [kp1] (checked)
term_puts:
        jsr     term_of_cur
        bcc     :+
        rts
:       jsr     term_begin
        stz     tm_si
:       ldy     tm_si
        lda     [kp1],y
        and     #$00FF
        beq     :+
        jsr     term_char
        inc     tm_si
        bra     :-
:       jsr     term_end
        clc
        rts

; con_size -> A = columns, X = rows
term_csize:
        jsr     term_of_cur
        bcc     :+
        rts
:       lda     tm_rows,x
        ldy     cur
        sta     t_x,y
        lda     tm_cols,x
        clc
        rts

; input_read: the next key of the terminal (the borrower only); blocks
term_iread:
        jsr     term_of_cur
        bcc     :+
        rts
:       stx     tm_w
        lda     tm_fg,x                 ; (nobody has the keys yet: the first reader)
        bpl     :+
        lda     cur
        sta     tm_fg,x
:       lda     tm_fg,x
        cmp     cur
        beq     :+
        lda     #EINVAL
        jsr     set_err
        clc
        rts
:       ldx     tm_w
        lda     tm_kn,x
        bne     @take
        ldx     cur
        lda     t_killed,x
        beq     :+
        lda     #EINVAL
        jsr     set_err
        clc
        rts
:       lda     #W_INPUT
        ldy     #0
        jsr     k_block
        jsr     term_of_cur
        bcc     :+
        lda     #EINVAL                 ; (the terminal closed)
        jsr     set_err
        clc
        rts
:       stx     tm_w
        bra     :----
@take:  lda     tm_kh,x
        asl     a
        asl     a
        clc
        adc     #TM_KEYS
        sta     tm_p
        lda     tm_bank,x
        sta     tm_p+2
        lda     tm_kh,x
        inc     a
        and     #31
        sta     tm_kh,x
        dec     tm_kn,x
        ldy     #2
        lda     [tm_p],y
        ldx     cur
        sta     t_x,x
        lda     [tm_p]
        jsr     set_ok
        clc
        rts

; input_claim / input_release / input_lend on a terminal
term_iclaim:
        jsr     term_of_cur
        bcc     :+
        rts
:       lda     #0
        jsr     set_ok
        clc
        rts

term_irel:
        jsr     term_of_cur
        bcc     :+
        rts
:       jsr     term_fgdone
        lda     #0
        jsr     set_ok
        clc
        rts

term_ilend:
        jsr     term_of_cur
        bcc     :+
        rts
:       stx     tm_w
        ldx     cur
        lda     t_a,x
        jsr     find_id
        bcs     @bad
        cpx     cur
        beq     @bad
        lda     cur
        sta     t_lender,x
        ldy     cur
        lda     t_x,y
        and     #1
        sta     t_lbrk,x
        txa
        ldx     tm_w
        sta     tm_fg,x
        lda     #0
        jsr     set_ok
        clc
        rts
@bad:   lda     #EINVAL
        jsr     set_err
        clc
        rts

; the current task leaves (release, exit): if it has its terminal's keys, they go back to
; its lender
term_fgdone:
        jsr     term_of_cur
        bcs     @out
        lda     tm_fg,x
        cmp     cur
        bne     @out
        stx     tm_w
        ldx     cur
        lda     t_lender,x
        ldx     tm_w
        sta     tm_fg,x
        cmp     #NONE
        beq     @out
        tax                             ; it may wait for keys already
        lda     t_state,x
        cmp     #TS_BLOCKED
        bne     @out
        lda     t_wreason,x
        cmp     #W_INPUT
        bne     @out
        jmp     k_wake
@out:   rts

; at exit
term_task_exit:
        jsr     term_fgdone
        ldx     cur
        lda     #0
        sta     t_term,x
        rts

; ---- $7F ws_term(A = window: the caller prints to and reads from that terminal window,
; and so do the tasks it starts; A = $FF: detach) ----
sys_wterm:
        ldx     cur
        lda     t_a,x
        cmp     #$FF
        bne     :+
        lda     #0
        sta     t_term,x
        jmp     set_ok
:       jsr     win_arg
        bcc     :+
        jmp     err_inval
:       lda     w_fl,x
        bit     #WF_TERM
        bne     :+
        jmp     err_inval
:       lda     tm_bank,x
        bne     :+
        jmp     err_inval
:       txa
        ora     #$8000
        ldx     cur
        sta     t_term,x
        lda     #0
        jmp     set_ok
