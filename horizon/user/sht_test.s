; sht_test.s - Sheet: the self test, "sheet -t FILE" (part of sheet.s). No window: the
; results go to the console (and so to the debug log).
;
; FILE is a script, read line by line; besides the lines of a .SHT file (cells, W, F) it
; may hold:
;   = NAME            a group of checks starts (the last one's result is printed:
;                     "PASS NAME", or "FAIL NAME" and a line for each failed check)
;   ? A1 TEXT         the cell's value as the general format shows it (errors by name,
;                     text as it is, nothing for an empty cell) must be TEXT
;   ?f A1 TEXT        the value as its column's format shows it
;   ?s A1 TEXT        the cell as it would be typed (a formula's text)
;   ! COMMAND ARGS    copy R T, cut R T (R a cell or range A1:B2, T a cell), filld R,
;                     fillr R, clear R, insr N, delr N, insc L, delc L, new,
;                     save PATH, load PATH, csvout PATH, csvin PATH, bench, memfill
;   # ...             a comment
; The sheet is recalculated before a check when anything changed. At the end:
; "SHEET TEST END: g groups, f failed"; the exit code is the number failed.

        .segment "ZEROPAGE"
tb:     .res    4                       ; the test script's bank
tk_p:   .res    2
tk_q:   .res    2

        .segment "CODE"

test_run:
        sys     SYS_BALLOC              ; the script into a bank of its own
        bcc     :+
        print   "sheet: not enough memory\n"
        lda     #1
        jmp     exit_a
:       sta     z:tb+2
        stz     z:tb
        ptr     fpath
        lda     #O_READ
        sys     SYS_OPEN
        bcc     :+
        print   "sheet: cannot open the test script\n"
        lda     #1
        jmp     exit_a
:       sta     fh
        lda     fh
        sta     rblk
        stz     rblk+1
        lda     z:tb+2
        sta     rblk+3
        lda     #$FF00
        sta     rblk+4
        ptr     rblk
        sys     SYS_READ
        bcc     :+
        lda     #0
:       sta     tl_len
        lda     fh
        sys     SYS_CLOSE
        print   "SHEET TEST START\n"
        stz     tl_pos
        stz     tl_no
        stz     tg_n
        stz     tg_bad
        stz     tg_on
@line:  jsr     tl_line
        bcs     @end
        inc     tl_no
        lda     lbuf
        and     #$00FF
        cmp     #'='
        bne     :+
        jsr     tg_end
        jsr     tg_start
        bra     @line
:       cmp     #'?'
        bne     :+
        jsr     t_check
        bra     @line
:       cmp     #'!'
        bne     :+
        jsr     t_cmd
        bra     @line
:       lda     #1
        sta     ce_force
        jsr     sht_line
        stz     ce_force
        bra     @line
@end:   jsr     tg_end
        print   "SHEET TEST END: "
        lda     tg_n
        jsr     put_dec
        print   " groups, "
        lda     tg_bad
        jsr     put_dec
        print   " failed\n"
        lda     tg_bad
        jmp     exit_a

; the next line of the script -> lbuf; C set at the end
tl_line:
        ldx     #0
        ldy     tl_pos
        cpy     tl_len
        bcc     @l
        sec
        rts
@l:     cpy     tl_len
        bcs     @e
        lda     [tb],y
        iny
        and     #$00FF
        cmp     #10
        beq     @e
        cmp     #13
        beq     @l
        cpx     #LMAX
        bcs     @l
        sep     #$20
        .a8
        sta     lbuf,x
        rep     #$20
        .a16
        inx
        bra     @l
@e:     sty     tl_pos
        stz     lbuf,x
        clc
        rts

; "= NAME": a group starts
tg_start:
        inc     tg_n
        lda     #1
        sta     tg_on
        stz     tg_fail
        ldx     #.loword(lbuf + 2)
        ldy     #.loword(tg_name)
        jmp     ui_strcpy
; the group's result
tg_end: lda     tg_on
        beq     @out
        stz     tg_on
        lda     tg_fail
        bne     @f
        print   "PASS "
        ldx     #.loword(tg_name)
        ldy     #^tg_name
        jsr     out_str
        jmp     put_nl
@f:     inc     tg_bad
        print   "FAIL "
        ldx     #.loword(tg_name)
        ldy     #^tg_name
        jsr     out_str
        jsr     put_nl
        ldx     #.loword(tg_msgs)       ; the failed checks
        ldy     #^tg_msgs
        jsr     out_str
        stz     tg_msgs
        stz     tg_ml
@out:   rts

; "? A1 TEXT", "?f A1 TEXT", "?s A1 TEXT"
t_check:
        lda     dirty
        beq     :+
        stz     dirty
        jsr     recalc
:       lda     lbuf+1
        and     #$00FF
        sta     tk_kind
        ldx     #2
        cmp     #' '
        beq     :+
        inx
:       jsr     t_ref
        bcs     @bad
        sta     tk_ci
        lda     lbuf,x                  ; the expected text after one space
        and     #$00FF
        beq     :+
        inx
:       stx     tk_exp
        lda     tk_kind
        cmp     #'s'
        beq     @src
        cmp     #'f'
        beq     @fmt
        ldx     #0
        bra     @disp
@fmt:   lda     tk_ci
        xba
        lsr     a
        lsr     a
        and     #$003F
        tax
        lda     colfmt,x
        and     #$00FF
        tax
@disp:  lda     tk_ci
        jsr     cell_disp
        bra     @cmp
@src:   lda     tk_ci
        jsr     cell_src
        ldx     #.loword(tbuf)
        ldy     #.loword(fbuf)
        jsr     ui_strcpy
@cmp:   ldx     tk_exp                  ; fbuf = lbuf + tk_exp?
        ldy     #0
:       lda     lbuf,x
        eor     fbuf,y
        and     #$00FF
        bne     @fail
        lda     lbuf,x
        and     #$00FF
        beq     @ok
        inx
        iny
        bra     :-
@ok:    rts
@bad:   ldx     #.loword(m_badline)
        bra     :+
@fail:  ldx     #.loword(m_got)
:       jsr     tm_line
        inc     tg_fail
        lda     tg_on                   ; (outside a group: a group of its own)
        bne     :+
        lda     #1
        sta     tg_on
        inc     tg_n
        ldx     #.loword(m_nogroup)
        ldy     #.loword(tg_name)
        jsr     ui_strcpy
:       rts

; a failure line into tg_msgs: "  line N: <the check> (got 'fbuf')" or X's text
tm_line:
        phx
        ldx     #.loword(m_line)
        jsr     tm_put
        ldx     #0
        lda     tl_no
        jsr     put_decx
        ldx     #.loword(nmbuf)
        jsr     tm_put
        ldx     #.loword(m_colon)
        jsr     tm_put
        ldx     #.loword(lbuf)
        jsr     tm_put
        plx
        cpx     #.loword(m_got)
        bne     :+
        jsr     tm_put
        ldx     #.loword(fbuf)
        jsr     tm_put
        ldx     #.loword(m_q)
:       jsr     tm_put
        ldx     #.loword(m_nl)
; string X appended to tg_msgs (as much as fits)
tm_put: ldy     tg_ml
@l:     lda     a:0,x
        and     #$00FF
        beq     @e
        cpy     #TMSG - 2
        bcs     @e
        sep     #$20
        .a8
        sta     tg_msgs,y
        rep     #$20
        .a16
        inx
        iny
        bra     @l
@e:     sty     tg_ml
        lda     #0
        sta     tg_msgs,y
        rts

; a cell name at lbuf + X ("B12") -> A = its index, X past it; C set: none
t_ref:  lda     lbuf,x
        and     #$00FF
        jsr     isletter
        bcc     @no
        and     #$00DF
        sec
        sbc     #'A'
        sta     tk_c
        inx
        jsr     ln_dec
        cmp     #1
        bcc     @no
        cmp     #NROW + 1
        bcs     @no
        dec     a
        sta     tk_r
        lda     tk_c
        xba
        asl     a
        asl     a
        ora     tk_r
        clc
        rts
@no:    sec
        rts
; a cell or range at lbuf + X -> s_c0 .. s_r1; C set: none
t_rng:  jsr     t_ref
        bcs     @no
        lda     tk_c
        sta     s_c0
        sta     s_c1
        lda     tk_r
        sta     s_r0
        sta     s_r1
        lda     lbuf,x
        and     #$00FF
        cmp     #':'
        bne     @ok
        inx
        jsr     t_ref
        bcs     @no
        lda     tk_c
        sta     s_c1
        lda     tk_r
        sta     s_r1
@ok:    clc
@no:    rts
; skip one space at lbuf + X
t_sp:   lda     lbuf,x
        and     #$00FF
        cmp     #' '
        bne     :+
        inx
:       rts

; "! COMMAND ARGS"
t_cmd:  lda     dirty                   ; (recalculated first: files hold the values)
        beq     :+
        stz     dirty
        jsr     recalc
:       ldx     #0                      ; the command word: tk_w (up to 8 letters)
        ldy     #2
:       lda     lbuf,y
        and     #$00FF
        beq     :+
        cmp     #' '
        beq     :+
        cpx     #8
        bcs     :+
        sep     #$20
        .a8
        sta     tk_w,x
        rep     #$20
        .a16
        inx
        iny
        bra     :-
:       stz     tk_w,x
        cmp     #' '
        bne     :+
        iny
:       tyx                             ; X = the arguments
        stx     tk_arg
        ldy     #0                      ; look it up
@look:  lda     cmdtab,y
        beq     @unk
        sta     tk_s
        phy
        ldx     tk_s
        ldy     #.loword(tk_w)
        jsr     t_streq
        ply
        bcs     @go
        iny
        iny
        iny
        iny
        bra     @look
@go:    lda     cmdtab+2,y              ; (to the routine with X = the arguments)
        tax
        lda     tk_jmp,x
        dec     a
        pha
        ldx     tk_arg
        rts
@unk:   ldx     #.loword(m_badline)
        jsr     tm_line
        inc     tg_fail
        rts
; X, Y = two strings -> C set if equal
t_streq:
        stx     tk_p
        sty     tk_q
        ldy     #0
:       lda     (tk_p),y
        eor     (tk_q),y
        and     #$00FF
        bne     @no
        lda     (tk_p),y
        and     #$00FF
        beq     @yes
        iny
        bra     :-
@yes:   sec
        rts
@no:    clc
        rts

tc_copy:
        jsr     t_rng
        bcs     tc_bad
        jsr     t_sp
        phx
        jsr     cp_copy
        plx
        jsr     t_rng
        bcs     tc_bad
        jmp     cp_paste
tc_cut: jsr     t_rng
        bcs     tc_bad
        jsr     t_sp
        phx
        jsr     cp_copy
        jsr     rng_clear
        plx
        jsr     t_rng
        bcs     tc_bad
        jmp     cp_paste
tc_bad: ldx     #.loword(m_badline)
        jsr     tm_line
        inc     tg_fail
        rts
tc_filld:
        jsr     t_rng
        bcs     tc_bad
        jmp     fill_down
tc_fillr:
        jsr     t_rng
        bcs     tc_bad
        jmp     fill_right
tc_clear:
        jsr     t_rng
        bcs     tc_bad
        jmp     rng_clear
tc_insr:
        jsr     ln_dec
        dec     a
        cmp     #NROW
        bcs     tc_bad
        jmp     ed_insr
tc_delr:
        jsr     ln_dec
        dec     a
        cmp     #NROW
        bcs     tc_bad
        jmp     ed_delr
tc_insc:
        jsr     t_col
        bcs     tc_bad
        jmp     ed_insc
tc_delc:
        jsr     t_col
        bcs     tc_bad
        jmp     ed_delc
t_col:  lda     lbuf,x
        and     #$00FF
        jsr     isletter
        bcc     :+
        and     #$00DF
        sec
        sbc     #'A'
        clc
        rts
:       sec
        rts
tc_new: jsr     sheet_new
        lda     #1
        sta     dirty
        rts
tc_save:
        jsr     t_path
        jsr     sht_save
        bcs     tc_ioerr
        rts
tc_load:
        jsr     t_path
        jsr     sheet_new
        lda     #1
        sta     dirty
        jsr     sht_load
        bcs     tc_ioerr
        rts
tc_csvout:
        jsr     t_path
        jsr     csv_save
        bcs     tc_ioerr
        rts
tc_csvin:
        jsr     t_path
        jsr     sheet_new
        lda     #1
        sta     dirty
        jsr     csv_load
        bcs     tc_ioerr
        rts
tc_ioerr:
        ldx     #.loword(m_ioerr)
        jsr     tm_line
        inc     tg_fail
        rts
; the rest of the line -> fpath
t_path: txa
        clc
        adc     #.loword(lbuf)
        tax
        ldy     #.loword(fpath)
        jmp     ui_strcpy

; 2000 formulas: A = 1..999, B = A * 1.05, C = a running sum of B, D1 = SUM(C1:C999),
; D2 = AVERAGE(B1:B999); the time of a recalculation, and of one after an edit
tc_bench:
        jsr     sheet_new
        stz     tk_r
@row:   lda     tk_r                    ; A: the number
        inc     a
        ldx     #0
        jsr     put_decx
        ldx     #.loword(nmbuf)
        ldy     #.loword(tbuf)
        jsr     ui_strcpy
        lda     tk_r
        sta     c_ci
        jsr     cell_enter
        jcs     tc_mem
        ldx     #.loword(b_bf)          ; B: =A<r>*1.05
        jsr     tb_set
        jsr     tb_row
        ldx     #.loword(b_bt)
        jsr     tb_add
        lda     tk_r
        ora     #CPC
        sta     c_ci
        jsr     cell_enter
        jcs     tc_mem
        lda     tk_r                    ; C: =B<r>+C<r-1> (C1: =B1)
        bne     :+
        ldx     #.loword(b_c1)
        jsr     tb_set
        bra     :++
:       ldx     #.loword(b_cf)
        jsr     tb_set
        jsr     tb_row
        ldx     #.loword(b_ct)
        jsr     tb_add
        lda     tk_r
        ldx     #0
        jsr     put_decx
        ldx     #.loword(nmbuf)
        jsr     tb_add
:       lda     tk_r
        ora     #2 * CPC
        sta     c_ci
        jsr     cell_enter
        jcs     tc_mem
        inc     tk_r
        lda     tk_r
        cmp     #NROW
        jcc     @row
        ldx     #.loword(b_d1)
        jsr     tb_set
        lda     #3 * CPC
        sta     c_ci
        jsr     cell_enter
        ldx     #.loword(b_d2)
        jsr     tb_set
        lda     #3 * CPC + 1
        sta     c_ci
        jsr     cell_enter
        jsr     t_time
        jsr     recalc
        stz     dirty
        jsr     t_time2
        print   "bench: 2000 formulas, a full recalculation "
        lda     tk_ms
        jsr     put_dec
        print   " ms (emulated)\n"
        ldx     #.loword(b_two)         ; A500 = 2, and again
        jsr     tb_set
        lda     #499
        sta     c_ci
        jsr     cell_enter
        jsr     t_time
        jsr     recalc
        stz     dirty
        jsr     t_time2
        print   "bench: after an edit of A500 (504 formulas change) "
        lda     tk_ms
        jsr     put_dec
        print   " ms (emulated)\n"
        ldx     #.loword(b_two)         ; A999 = 2: four formulas change
        jsr     tb_set
        lda     #998
        sta     c_ci
        jsr     cell_enter
        jsr     t_time
        jsr     recalc
        stz     dirty
        jsr     t_time2
        print   "bench: after an edit of A999 (4 formulas change) "
        lda     tk_ms
        jsr     put_dec
        print   " ms (emulated)\n"
        rts
tc_mem: print   "bench: out of memory\n"
        rts
tb_set: ldy     #.loword(tbuf)
        jmp     ui_strcpy
tb_add: phx
        ldx     #.loword(tbuf)
        jsr     ui_strlen
        clc
        adc     #.loword(tbuf)
        tay
        plx
        jmp     ui_strcpy
tb_row: lda     tk_r                    ; the row number (1-based)
        inc     a
        ldx     #0
        jsr     put_decx
        ldx     #.loword(nmbuf)
        jmp     tb_add
t_time: sys     SYS_UPTIME
        sta     tk_t0
        rts
t_time2:
        sys     SYS_UPTIME
        sec
        sbc     tk_t0
        sta     tk_ms
        rts

tc_recalc:
        stz     dirty
        jmp     recalc

; cells of 250 characters (A1, A2, ...) until the heap is full: "out of memory" must come
; back as CE_MEM, with the cells before it intact
tc_memfill:
        jsr     sheet_new
        ldx     #0
        lda     #'x' | ('x' << 8)
:       sta     tbuf,x
        inx
        inx
        cpx     #TXTMAX
        bcc     :-
        stz     tbuf + TXTMAX
        stz     tk_r
        stz     c_ci
@l:     jsr     cell_enter
        bcs     @full
        inc     tk_r
        inc     c_ci
        lda     c_ci
        and     #CPC - 1
        cmp     #NROW
        bcc     @l
        lda     c_ci
        clc
        adc     #CPC - NROW
        sta     c_ci
        cmp     #NCOL * CPC
        bcc     @l
        print   "memfill: no limit reached\n"
        rts
@full:  cmp     #CE_MEM
        beq     :+
        print   "memfill: an error other than out of memory\n"
        rts
:       print   "memfill: "
        lda     tk_r
        jsr     put_dec
        print   " cells of 250 characters, then out of memory (reported)\n"
        rts

        .segment "RODATA"
cmdtab: .addr   c_copy, 0, c_cut, 2, c_filld, 4, c_fillr, 6, c_clear, 8, c_insr, 10
        .addr   c_delr, 12, c_insc, 14, c_delc, 16, c_new, 18, c_save, 20, c_load, 22
        .addr   c_csvout, 24, c_csvin, 26, c_bench, 28, c_recalc, 30, c_memfill, 32, 0
tk_jmp: .addr   tc_copy, tc_cut, tc_filld, tc_fillr, tc_clear, tc_insr, tc_delr, tc_insc
        .addr   tc_delc, tc_new, tc_save, tc_load, tc_csvout, tc_csvin, tc_bench, tc_recalc
        .addr   tc_memfill
c_copy: .byte   "copy", 0
c_cut:  .byte   "cut", 0
c_filld: .byte  "filld", 0
c_fillr: .byte  "fillr", 0
c_clear: .byte  "clear", 0
c_insr: .byte   "insr", 0
c_delr: .byte   "delr", 0
c_insc: .byte   "insc", 0
c_delc: .byte   "delc", 0
c_new:  .byte   "new", 0
c_save: .byte   "save", 0
c_load: .byte   "load", 0
c_csvout: .byte "csvout", 0
c_csvin: .byte  "csvin", 0
c_bench: .byte  "bench", 0
c_recalc: .byte "recalc", 0
c_memfill: .byte "memfill", 0
m_badline: .byte " (a bad line)", 0
m_ioerr: .byte  " (a file error)", 0
m_got:  .byte   " (got '", 0
m_q:    .byte   "')", 0
m_nl:   .byte   10, 0
m_line: .byte   "  line ", 0
m_colon: .byte  ": ", 0
m_nogroup: .byte "(no group)", 0
b_bf:   .byte   "=A", 0
b_bt:   .byte   "*1.05", 0
b_c1:   .byte   "=B1", 0
b_cf:   .byte   "=B", 0
b_ct:   .byte   "+C", 0
b_d1:   .byte   "=SUM(C1:C999)", 0
b_d2:   .byte   "=AVERAGE(B1:B999)", 0
b_two:  .byte   "2", 0

        .segment "BSS"
TMSG    = 1200
tl_len: .res    2
tl_pos: .res    2
tl_no:  .res    2
tg_n:   .res    2
tg_bad: .res    2
tg_on:  .res    2
tg_fail: .res   2
tg_name: .res   80
tg_ml:  .res    2
tg_msgs: .res   TMSG
tk_kind: .res   2
tk_ci:  .res    2
tk_exp: .res    2
tk_c:   .res    2
tk_r:   .res    2
tk_w:   .res    10
tk_arg: .res    2
tk_s:   .res    2
tk_t0:  .res    2
tk_ms:  .res    2

