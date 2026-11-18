; bas_exec.s - the statement loop and the statements.
;
; tp points at the next token. `stmt` dispatches one statement (statement tokens through
; stab; a variable token is an implicit LET); every handler ends with `jmp stmt_end`
; (expects ':' or the end of the line) or jumps to a new position itself. A line's end goes
; to the next line by index (curidx), or back to the immediate loop for a direct command.
; The control stack cstk (24-byte frames) holds FOR, GOSUB and WHILE:
;   FOR:   +0 CF_FOR, +2 variable offset (bit 0: a number loop), +4 limit, +12 step (each
;          {lo, hi, type, len}), +20 line index, +22 tp (low word; the bank comes from the line)
;   GOSUB: +0 CF_GOSUB, +20 line index, +22 tp (the return position)
;   WHILE: +0 CF_WHILE, +20 line index, +22 tp (its condition)

        .segment "CODE"
        .a16
        .i16
CF_FOR  = 1
CF_GOSUB = 2
CF_WHILE = 3
CSMAX   = 256                           ; frames
CSF     = 24                            ; bytes a frame

; ---------------------------------------------------------------- the loop
stmt:   lda     z:tp                    ; (a break resumes here: CONT)
        sta     stmtp
        dec     z:pollc
        bne     :+
        jsr     periodic
:       lda     [tp]
        and     #$00FF
        cmp     #$80
        bcc     @low
        inc     z:tp
        asl     a
        tax
        jmp     (stab - $100,x)
@low:   cmp     #':'
        bne     :+
        inc     z:tp
        bra     stmt
:       cmp     #0
        beq     next_line
        err     E_SYNTAX
stmt_end:
        lda     [tp]
        and     #$00FF
        beq     next_line
        cmp     #':'
        bne     :+
        inc     z:tp
        bra     stmt
:       cmp     #TK_ELSE                ; the end of a THEN part
        beq     next_line
        err     E_SYNTAX
next_line:
        lda     curidx
        cmp     #$FFFF
        beq     @direct
        inc     a
        cmp     nlines
        bcs     prog_end
        jsr     line_start
        bra     stmt
@direct:
        jmp     main_ready

; the end of the program (END, or past the last line)
prog_end:
        jsr     snd_off
        stz     contok
        jsr     flush_all
        jsr     dl_sync                 ; (2.0) the last frame's drawing, then sprites
        jsr     game_stop               ; hidden, full screen left
        jmp     main_ready

; tp = the position A (low word) in line X ($FFFF: the direct command)
set_pos:
        sta     z:tp
        stx     curidx
        cpx     #$FFFF
        beq     :+
        txa
        asl     a
        asl     a
        tay
        iny
        iny
        lda     [ipt],y
        sta     z:tp+2
        rts
:       lda     codebk                  ; (the direct buffer: our bank)
        sta     z:tp+2
        rts

; the direct command in tbuf -> dbuf; tp at its start
direct_copy:
        ldx     #0
:       lda     tbuf,x
        sta     dbuf,x
        inx
        inx
        cpx     tlen
        bcc     :-
        lda     #.loword(dbuf)
        ldx     #$FFFF
        jsr     set_pos
        lda     #POLLN
        sta     z:pollc
        rts

; ---------------------------------------------------------------- helpers
; the token at tp must be A (a character or keyword): skip it, else Syntax error
expect: sta     z:t7
        lda     [tp]
        and     #$00FF
        cmp     z:t7
        bne     :+
        inc     z:tp
        rts
:       err     E_SYNTAX

; the token at tp -> A (not skipped)
peek:   lda     [tp]
        and     #$00FF
        rts

; at the end of a statement? (0, ':', ELSE) -> Z set
at_end: lda     [tp]
        and     #$00FF
        beq     :+
        cmp     #':'
        beq     :+
        cmp     #TK_ELSE
:       rts

; an integer expression (a float is rounded) -> flo, fhi (and A = flo)
eval_int:
        jsr     eval
        lda     ft
        bne     :+
        lda     flo
        rts
:       cmp     #T_STR
        beq     ev_type
        jsr     acc_round
        lda     flo
        rts
ev_type:
        err     E_TYPE
; a number rounded to an integer, beyond 32 bits clamped to +-2147483647 -> flo, fhi
eval_clamp:
        jsr     eval_num
        lda     ft
        beq     @x
        ldx     #FAX
        jsr     fp_unp
        lda     #1
        jsr     fp_toint
        bcc     :+
        lda     #$FFFF                  ; (too large)
        sta     z:fw
        lda     #$7FFF
        sta     z:fw+2
        lda     fa_s
        beq     :+
        lda     #1
        sta     z:fw
        lda     #$8000
        sta     z:fw+2
:       lda     z:fw
        sta     flo
        lda     z:fw+2
        sta     fhi
        stz     ft
@x:     rts
; a number (an integer or a float) -> acc
eval_num:
        jsr     eval
        lda     ft
        cmp     #T_STR
        beq     ev_type
        rts
; a condition: a number, true if not 0 -> X (and Z) = 0 if false
eval_cond:
        jsr     eval
        ldx     ft
        beq     :+
        cpx     #T_STR
        beq     ev_type
        rts                             ; (a float is never 0)
:       lda     flo
        ora     fhi
        tax
        rts
; ... that must be 0-65535 -> A
eval_u16:
        jsr     eval_int
        lda     fhi
        bne     :+
        lda     flo
        rts
:       err     E_ARG
; a string expression
eval_str:
        jsr     eval
        lda     ft
        cmp     #T_STR
        bne     :+
        rts
:       err     E_TYPE

; ---------------------------------------------------------------- LET
st_implet:
        dec     z:tp
        lda     [tp]                    ; a number variable: straight in
        and     #$00FF
        cmp     #TK_NVAR
        bne     st_let
        ldy     #1
        lda     [tp],y
        pha
        ldy     #3
        lda     [tp],y
        and     #$00FF
        cmp     #'='
        bne     @syn
        lda     z:tp
        clc
        adc     #4
        sta     z:tp
        jsr     eval
        ply
        lda     ft
        bne     @nint
        sta     [vb4],y                 ; {lo, hi, 0}
        lda     flo
        sta     [vb],y
        iny
        iny
        lda     fhi
        sta     [vb],y
        jmp     stmt_end
@nint:  cmp     #T_STR
        beq     @mism
        sta     [vb4],y                 ; a float {lo, hi, type, len}
        lda     flo
        sta     [vb],y
        iny
        iny
        lda     fhi
        sta     [vb],y
        lda     flen
        sta     [vb4],y
        jmp     stmt_end
@syn:   err     E_SYNTAX
@mism:  err     E_TYPE
st_let: jsr     lvalue
        pha
        lda     #'='
        jsr     expect
        pei     (ap+2)
        pei     (ap)
        jsr     eval
        pla
        sta     z:ap
        pla
        sta     z:ap+2
        pla
        jsr     assign
        jmp     stmt_end

; ---------------------------------------------------------------- PRINT
st_print:
        lda     #1
        sta     pnl                     ; a new line at the end
@l:     jsr     at_end
        beq     @end
        cmp     #';'
        bne     :+
        inc     z:tp
        stz     pnl
        bra     @l
:       cmp     #','
        bne     :+
        inc     z:tp
        stz     pnl
        jsr     pr_pos                  ; the next column of 10
        lda     pcol
        jsr     tabstop
        bra     @l
:       cmp     #TK_TAB
        bne     :+
        inc     z:tp
        jsr     paren_int
        jsr     tabto
        stz     pnl
        bra     @l
:       cmp     #TK_SPC
        bne     :+
        inc     z:tp
        jsr     paren_int
        jsr     spaces
        stz     pnl
        bra     @l
:       jsr     eval
        jsr     print_acc
        lda     #1
        sta     pnl
        bra     @l
@end:   lda     pnl
        beq     :+
        jsr     con_nl
:       stz     lpon                    ; (0.23: the end of an LPRINT)
        jmp     stmt_end

; the accumulator on the console (a number: no spaces around it)
print_acc:
        lda     ft
        bne     :+
        jmp     con_putnum
:       cmp     #T_STR
        beq     :+
        lda     #10                     ; a float
        jsr     fp_fmt
        jmp     con_puts
:       lda     flo
        sta     z:bp
        lda     fhi
        sta     z:bp+2
        ldy     #0
:       cpy     flen
        bcs     :+
        lda     [bp],y
        phy
        jsr     con_putc
        ply
        iny
        bra     :-
:       rts

; "(" n ")" -> A (0-65535)
paren_int:
        lda     #'('
        jsr     expect
        jsr     eval_u16
        pha
        lda     #')'
        jsr     expect
        pla
        rts

; spaces up to the next multiple of 10 after column A (the width pwid: pr_pos first)
tabstop:
        ldx     #0
:       cmp     #10
        bcc     :+
        sbc     #10
        inx
        bra     :-
:       inx
        txa
        asl     a
        sta     z:t0
        asl     a
        asl     a
        adc     z:t0
        cmp     pwid
        bcc     tabto
        jmp     con_nl
; spaces up to column A (a new line first when past it); the console's, or (LPRINT) the
; print job's
tabto:  jsr     pr_pos
        cmp     pwid
        bcc     :+
        lda     pwid
        dec     a
:       sta     z:t0
        cmp     pcol
        bcs     :+
        jsr     con_nl
        stz     pcol
:       lda     z:t0
        sec
        sbc     pcol
; A spaces
spaces: tax
        beq     :++
:       phx
        lda     #' '
        jsr     con_putc
        plx
        dex
        bne     :-
:       rts

; ---------------------------------------------------------------- INPUT
st_input:
        lda     #1
        sta     inq                     ; "? " after the prompt
        jsr     peek
        cmp     #TK_STRL
        bne     @vars
        jsr     eval                    ; the prompt
        jsr     print_acc
        jsr     peek
        cmp     #';'
        beq     :+
        cmp     #','
        jne     @syn
        stz     inq
:       inc     z:tp
@vars:  lda     z:tp
        sta     invars
@ask:   lda     inq
        beq     :+
        cprint  "? "
:       jsr     input_line
        lda     invars
        sta     z:tp
        stz     in_x                     ; the position in ibuf
@var:   jsr     lvalue
        sta     inkind
        jsr     in_item                 ; -> acc, C set: not a number
        bcs     @redo
        lda     inkind
        jsr     assign
        jsr     peek
        cmp     #','
        bne     @done
        inc     z:tp
        jsr     in_skipsp               ; the next item
        cmp     #','
        bne     :+
        inc     in_x
        bra     @var
:       cmp     #0
        bne     @redo
        cprint  "?? "                   ; more wanted
        jsr     input_line
        stz     in_x
        bra     @var
@done:  jsr     in_skipsp
        cmp     #0
        beq     :+
        cprint  "?Extra ignored"
        jsr     con_nl
:       jmp     stmt_end
@redo:  cprint  "?Redo from start"
        jsr     con_nl
        brl     @ask
@syn:   err     E_SYNTAX

; a line from the editor (breaks go to do_break)
input_line:
        jsr     flush_all
        jsr     fs_suspend              ; (2.0) the answer typed on the desktop
        lda     #1
        jsr     con_input
        bcc     :+
        jmp     do_break
:       jmp     fs_resume

; ibuf at inx past spaces -> A = the character there
in_skipsp:
        ldx     in_x
:       lda     ibuf,x
        and     #$00FF
        cmp     #' '
        bne     :+
        inx
        bra     :-
:       stx     in_x
        rts

; the next item of the input line for a target of kind inkind -> acc; C set: no number
in_item:
        lda     inkind
        cmp     #K_STR
        beq     @str
        jsr     in_skipsp
        lda     #.loword(ibuf)          ; a number: parse_num on the line
        clc
        adc     in_x
        sta     z:bp
        lda     codebk
        sta     z:bp+2
        lda     #255
        jsr     parse_num               ; -> acc, Y = characters, C set: none
        bcs     @no
        tya
        clc
        adc     in_x
        sta     in_x
        jsr     in_skipsp
        cmp     #','
        beq     :+
        cmp     #0
        bne     @no
:       clc
        rts
@no:    sec
        rts
@str:   jsr     in_skipsp
        cmp     #'"'
        bne     @plain
        inx
        stx     z:t0                    ; quoted: to the next quote
:       lda     ibuf,x
        and     #$00FF
        beq     :+
        cmp     #'"'
        beq     :+
        inx
        bra     :-
:       txa
        sec
        sbc     z:t0
        sta     flen
        lda     ibuf,x
        and     #$00FF
        beq     :+
        inx
:       stx     in_x
        jsr     in_skipsp
        bra     @set
@plain: stx     z:t0                    ; plain: to a comma, trailing spaces cut
:       lda     ibuf,x
        and     #$00FF
        beq     :+
        cmp     #','
        beq     :+
        inx
        bra     :-
:       stx     in_x
:       cpx     z:t0
        beq     :+
        lda     ibuf-1,x
        and     #$00FF
        cmp     #' '
        bne     :+
        dex
        bra     :-
:       txa
        sec
        sbc     z:t0
        sta     flen
@set:   lda     z:t0
        clc
        adc     #.loword(ibuf)
        sta     flo
        lda     codebk
        sta     fhi
        lda     #T_STR
        sta     ft
        clc
        rts

; ---------------------------------------------------------------- IF, GOTO, GOSUB, ON
st_if:  jsr     eval_cond
        stx     z:t0
        jsr     peek
        cmp     #TK_GOTO
        beq     :+
        lda     #TK_THEN
        jsr     expect
        lda     z:t0
        beq     @false
        jsr     peek                    ; THEN line
        cmp     #TK_LINE
        jeq     goto_line
        jmp     stmt
:       lda     z:t0                    ; IF .. GOTO line
        beq     @false
        inc     z:tp
        jmp     goto_line
@false: stz     z:t1                    ; the ELSE of this IF (nested IFs counted)
@scan:  lda     [tp]
        and     #$00FF
        jeq     next_line
        cmp     #TK_IF
        bne     :+
        inc     z:t1
        bra     @skip
:       cmp     #TK_ELSE
        bne     @skip
        lda     z:t1
        beq     @else
        dec     z:t1
@skip:  jsr     skip_tok
        bra     @scan
@else:  inc     z:tp
        jsr     peek
        cmp     #TK_LINE
        jeq     goto_line
        jmp     stmt

; tp past one token
skip_tok:
        lda     z:tp
        sta     z:ep
        lda     z:tp+2
        sta     z:ep+2
        jsr     tk_size
        clc
        adc     z:tp
        sta     z:tp
        rts

st_goto:
        jsr     peek
        cmp     #TK_LINE
        beq     goto_line
        err     E_SYNTAX
; tp at a TK_LINE: go there
goto_line:
        jsr     lineref
        jsr     line_start
        jmp     stmt

; the TK_LINE at tp -> A = the line's index (cached), tp past it; Undefined line
lineref:
        ldy     #5
        lda     [tp],y
        cmp     pgen
        bne     @look
        ldy     #3
        lda     [tp],y
        bra     @done
@look:  ldy     #1
        lda     [tp],y
        sta     errarg
        jsr     line_find
        bcc     @undef
        txa
        ldy     #3
        sta     [tp],y
        lda     pgen
        ldy     #5
        sta     [tp],y
        txa
@done:  pha
        lda     z:tp
        clc
        adc     #7
        sta     z:tp
        pla
        rts
@undef: err     E_LINE

st_gosub:
        jsr     peek
        cmp     #TK_LINE
        bne     @syn
        jsr     lineref
        pha
        jsr     push_gosub
        pla
        jsr     line_start
        jmp     stmt
@syn:   err     E_SYNTAX

; a GOSUB frame returning to tp
push_gosub:
        jsr     cs_push
        lda     #CF_GOSUB
        sta     f:WIN_CSTK,x
        lda     curidx
        sta     f:WIN_CSTK+20,x
        lda     z:tp
        sta     f:WIN_CSTK+22,x
        rts

; a new frame -> X = its offset
cs_push:
        ldx     csp
        cpx     #CSMAX * CSF
        bcc     :+
        err     E_STACK
:       txa
        clc
        adc     #CSF
        sta     csp
        rts

st_return:
        ldx     csp
@l:     cpx     #0
        beq     @none
        txa
        sec
        sbc     #CSF
        tax
        lda     f:WIN_CSTK,x
        cmp     #CF_GOSUB
        bne     @l
        stx     csp
        lda     f:WIN_CSTK+22,x
        pha
        lda     f:WIN_CSTK+20,x
        tax
        pla
        jsr     set_pos
        jmp     stmt_end
@none:  err     E_RET

st_on:  jsr     eval_int
        lda     fhi                     ; out of 1..: nothing (the next statement)
        bne     @big
        lda     flo
        sta     z:t2
        jsr     peek
        sta     z:t3
        cmp     #TK_GOTO
        beq     :+
        cmp     #TK_GOSUB
        bne     @syn
:       inc     z:tp
@l:     jsr     peek
        cmp     #TK_LINE
        bne     @syn
        dec     z:t2
        beq     @go
        lda     z:tp
        clc
        adc     #7
        sta     z:tp
        jsr     peek
        cmp     #','
        bne     @none
        inc     z:tp
        bra     @l
@none:  jmp     stmt_end
@big:   jsr     on_skip
        jmp     stmt_end
@go:    jsr     lineref
        sta     z:t2
        lda     z:t3
        cmp     #TK_GOSUB
        bne     :+
        jsr     on_skip                 ; returns after the list
        jsr     push_gosub
:       lda     z:t2
        jsr     line_start
        jmp     stmt
@syn:   err     E_SYNTAX
; tp to the end of the statement
on_skip:
:       jsr     at_end
        beq     :+
        jsr     skip_tok
        bra     :-
:       rts

; ---------------------------------------------------------------- FOR, NEXT
; An integer loop (start, limit and step integers, or a % variable): the variable is
; stepped in place. A number loop (+2 has bit 0 set) steps it with floats; an integer loop
; whose variable became a float goes on as a number loop.
st_for: jsr     peek
        cmp     #TK_NVAR
        beq     :+
        cmp     #TK_IVAR
        jne     syn_err
:       sta     fkind
        ldy     #1
        lda     [tp],y
        sta     fvar
        lda     z:tp
        clc
        adc     #3
        sta     z:tp
        lda     #'='
        jsr     expect
        jsr     for_num
        lda     ft
        sta     fflt
        lda     fvar                    ; the start -> the variable
        sta     z:ap
        lda     z:vb+2
        sta     z:ap+2
        lda     #K_NUM
        jsr     assign
        lda     #TK_TO
        jsr     expect
        jsr     for_num
        ldx     #.loword(flim)
        jsr     acc_put
        lda     #1                      ; STEP 1
        sta     flo
        stz     fhi
        stz     ft
        jsr     peek
        cmp     #TK_STEP
        bne     :+
        inc     z:tp
        jsr     for_num
:       ldx     #.loword(fstep)
        jsr     acc_put
        lda     fstep+4                 ; integer start and step, a float limit: the
        tsb     fflt                    ; limit made an integer (floor, ceiling for a
        lda     flim+4                  ; negative step): an integer loop, the same steps
        beq     @lim
        ldx     fflt
        bne     @lim
        jsr     for_ilim
@lim:   lda     flim+4
        tsb     fflt
        ldx     csp                     ; a loop of the same variable ends (with the
@f:     cpx     #0                      ; loops above it; the search stops at a GOSUB or
        beq     @new                    ; WHILE: a subroutine's loop is its own)
        txa
        sec
        sbc     #CSF
        tax
        lda     f:WIN_CSTK,x
        cmp     #CF_FOR
        bne     @new
        lda     f:WIN_CSTK+2,x
        and     #$FFFE
        cmp     fvar
        bne     @f
        stx     csp
@new:   jsr     cs_push
        lda     #CF_FOR
        sta     f:WIN_CSTK,x
        lda     fflt
        beq     :+
        lda     #1
:       ora     fvar
        sta     f:WIN_CSTK+2,x
        ldy     #0
:       lda     flim,y                  ; limit, step {lo, hi, type, len}
        sta     f:WIN_CSTK+4,x
        inx
        inx
        iny
        iny
        cpy     #16
        bcc     :-
        txa
        sec
        sbc     #16
        tax
        lda     curidx
        sta     f:WIN_CSTK+20,x
        lda     z:tp
        sta     f:WIN_CSTK+22,x
        jmp     stmt_end
; a number for FOR (rounded for a % variable)
for_num:
        jsr     eval_num
        lda     fkind
        cmp     #TK_IVAR
        bne     :+
        jmp     acc_round
:       rts
; the float limit flim -> an integer: floor (ceiling for a negative step), beyond 32 bits
; +-2147483647
for_ilim:
        lda     flim+4
        sta     ft
        lda     flim
        sta     flo
        lda     flim+2
        sta     fhi
        lda     flim+6
        sta     flen
        ldx     #FAX
        jsr     fp_unp
        lda     fstep+2
        and     #$8000
        sta     z:t0
        beq     :+
        lda     fa_s                    ; ceiling(x) = -floor(-x)
        eor     #1
        sta     fa_s
:       lda     #2
        jsr     fp_toint
        bcc     :+
        lda     #$FFFF
        sta     z:fw
        lda     #$7FFF
        sta     z:fw+2
        lda     fa_s
        beq     :+
        lda     #1
        sta     z:fw
        lda     #$8000
        sta     z:fw+2
:       lda     z:t0
        beq     :+
        lda     #0
        sec
        sbc     z:fw
        sta     z:fw
        lda     #0
        sbc     z:fw+2
        sta     z:fw+2
:       lda     z:fw
        sta     flim
        lda     z:fw+2
        sta     flim+2
        stz     flim+4
        rts
; acc -> X {lo, hi, type, len}
acc_put:
        lda     flo
        sta     a:0,x
        lda     fhi
        sta     a:2,x
        lda     ft
        sta     a:4,x
        lda     flen
        sta     a:6,x
        rts
; the frame's {lo, hi, type, len} at X -> acc
acc_get:
        lda     f:WIN_CSTK,x
        sta     flo
        lda     f:WIN_CSTK+2,x
        sta     fhi
        lda     f:WIN_CSTK+4,x
        sta     ft
        lda     f:WIN_CSTK+6,x
        sta     flen
        rts

st_next:
        lda     #$FFFF                  ; the variable ($FFFF: the innermost loop)
        sta     fvar
        lda     [tp]
        and     #$00FF
        cmp     #TK_NVAR
        beq     :+
        cmp     #TK_IVAR
        bne     @find
:       ldy     #1
        lda     [tp],y
        sta     fvar
        lda     z:tp
        clc
        adc     #3
        sta     z:tp
@find:  ldx     csp
@f:     cpx     #0
        jeq     @none
        txa
        sec
        sbc     #CSF
        tax
        lda     f:WIN_CSTK,x
        cmp     #CF_FOR
        jne     @none
        lda     fvar
        cmp     f:WIN_CSTK+2,x
        beq     @hit                    ; this variable's integer loop
        ora     #1
        cmp     f:WIN_CSTK+2,x
        jeq     @num
        lda     fvar
        cmp     #$FFFF
        bne     @f                      ; (inner loops of other variables end)
        lda     f:WIN_CSTK+2,x
        lsr     a
        jcs     @num
@hit:   lda     f:WIN_CSTK+2,x          ; var += step
        tay
        lda     [vb4],y                 ; (the variable is a float now: a number loop)
        jne     @tonum
        clc
        lda     [vb],y
        adc     f:WIN_CSTK+4+8,x
        sta     [vb],y
        iny
        iny
        lda     [vb],y
        adc     f:WIN_CSTK+6+8,x
        sta     [vb],y
        bvs     @done                   ; (past the largest number: done)
        lda     f:WIN_CSTK+6+8,x
        bmi     @neg
        dey                             ; step >= 0: on while var <= limit
        dey
        sec
        lda     f:WIN_CSTK+4,x
        sbc     [vb],y
        iny
        iny
        lda     f:WIN_CSTK+6,x
        sbc     [vb],y
        bvc     :+
        eor     #$8000
:       bmi     @done
@loop:  txa                             ; on: back after the FOR
        clc
        adc     #CSF
        sta     csp
        lda     f:WIN_CSTK+20,x
        cmp     curidx
        bne     :+
        lda     f:WIN_CSTK+22,x               ; (same line: same bank)
        sta     z:tp
        jmp     stmt_end
:       pha
        lda     f:WIN_CSTK+22,x
        plx
        jsr     set_pos
        jmp     stmt_end
@neg:   dey                             ; step < 0: on while var >= limit
        dey
        sec
        lda     [vb],y
        sbc     f:WIN_CSTK+4,x
        iny
        iny
        lda     [vb],y
        sbc     f:WIN_CSTK+6,x
        bvc     :+
        eor     #$8000
:       bpl     @loop
@done:  stx     csp                     ; the loop is over
        jsr     peek
        cmp     #','
        beq     :+
        jmp     stmt_end
:       inc     z:tp
        jsr     peek
        cmp     #TK_NVAR
        beq     :+
        cmp     #TK_IVAR
        jne     syn_err
:       ldy     #1
        lda     [tp],y
        sta     fvar
        lda     z:tp
        clc
        adc     #3
        sta     z:tp
        jmp     @find
@tonum: lda     f:WIN_CSTK+2,x                ; a number loop from now on
        ora     #1
        sta     f:WIN_CSTK+2,x
@num:   stx     nx_f                    ; a number loop: var += step in floats
        lda     f:WIN_CSTK+2,x
        and     #$FFFE
        sta     z:ap
        lda     z:vb+2
        sta     z:ap+2
        lda     #K_NUM
        jsr     load_ap
        ldx     #FAX
        jsr     fp_unp
        lda     nx_f
        clc
        adc     #12
        tax
        jsr     acc_get
        ldx     #FBX
        jsr     fp_unp
        jsr     fp_add
        jsr     fp_pack
        lda     #K_NUM
        jsr     assign
        lda     nx_f                    ; var vs limit
        clc
        adc     #4
        tax
        jsr     acc_get
        ldx     #FBX
        jsr     fp_unp
        jsr     fp_cmp
        ldx     nx_f
        sta     z:t0
        lda     f:WIN_CSTK+16,x               ; the step's sign
        beq     :+
        lsr     a
        bra     :++
:       lda     f:WIN_CSTK+14,x
        asl     a
:       lda     z:t0                    ; (C: a negative step)
        bcs     :+
        cmp     #4                      ; on while var <= limit
        jne     @loop
        jmp     @done
:       cmp     #1                      ; on while var >= limit
        jne     @loop
        jmp     @done
@none:  err     E_NEXT

syn_err:
        err     E_SYNTAX

; ---------------------------------------------------------------- WHILE, WEND
st_while:
        lda     z:tp                    ; the condition
        pha
        jsr     eval_cond
        pla
        sta     z:t6
        cpx     #0
        beq     @skip
        jsr     cs_push
        lda     #CF_WHILE
        sta     f:WIN_CSTK,x
        lda     curidx
        sta     f:WIN_CSTK+20,x
        lda     z:t6
        sta     f:WIN_CSTK+22,x
        jmp     stmt_end
@skip:  stz     z:t1                    ; to the matching WEND
@l:     jsr     peek
        bne     :+
        lda     curidx                  ; the line's end: the next line
        cmp     #$FFFF
        beq     @none
        inc     a
        cmp     nlines
        bcs     @none
        jsr     line_start
        bra     @l
:       cmp     #TK_WHILE
        bne     :+
        inc     z:t1
        bra     @n
:       cmp     #TK_WEND
        bne     @n
        lda     z:t1
        beq     @hit
        dec     z:t1
@n:     jsr     skip_tok
        bra     @l
@hit:   inc     z:tp
        jmp     stmt_end
@none:  err     E_WHILE

st_wend:
        ldx     csp
        beq     @none
        lda     f:WIN_CSTK-CSF,x
        cmp     #CF_WHILE
        bne     @none
        lda     curidx                  ; here, in case the loop ends
        sta     wend_idx
        lda     z:tp
        sta     wend_tp
        lda     f:WIN_CSTK-CSF+20,x
        cmp     curidx
        bne     :+
        lda     f:WIN_CSTK-CSF+22,x           ; (the same line: the same bank)
        sta     z:tp
        bra     :++
:       lda     f:WIN_CSTK-CSF+22,x
        pha
        lda     f:WIN_CSTK-CSF+20,x
        tax
        pla
        jsr     set_pos
:
        jsr     eval_cond
        beq     :+
        jmp     stmt_end                ; on: after the WHILE's condition
:       lda     csp
        sec
        sbc     #CSF
        sta     csp
        lda     wend_tp
        ldx     wend_idx
        jsr     set_pos
        jmp     stmt_end
@none:  err     E_WEND

; ---------------------------------------------------------------- DIM
st_dim: jsr     peek
        ldx     #0
        cmp     #TK_NARR
        beq     :+
        cmp     #TK_IARR
        beq     :+
        inx
        cmp     #TK_SARR
        jne     syn_err
:       stx     dimkind
        ldy     #1
        lda     [tp],y
        sta     dimvar
        lda     z:tp
        clc
        adc     #3
        sta     z:tp
        lda     #'('
        jsr     expect
        stz     dimn
@d:     jsr     eval_int
        lda     fhi
        bne     @bad
        lda     flo
        cmp     #$7FFF
        bcs     @bad
        inc     a
        ldx     dimn
        cpx     #4 * 2
        bcs     @bad
        sta     dimsz,x
        inx
        inx
        stx     dimn
        jsr     peek
        cmp     #','
        bne     :+
        inc     z:tp
        bra     @d
:       lda     #')'
        jsr     expect
        jsr     arr_dim
        jsr     peek
        cmp     #','
        beq     :+
        jmp     stmt_end
:       inc     z:tp
        bra     st_dim
@bad:   err     E_SUBS

; ---------------------------------------------------------------- DATA, READ, RESTORE, REM
st_data:
        dec     z:tp                    ; skip its text
        jsr     skip_tok
        jmp     stmt_end
st_rem: dec     z:tp
        jsr     skip_tok
        jmp     stmt_end

st_read:
@l:     jsr     lvalue
        sta     inkind
        pei     (ap+2)
        pei     (ap)
        jsr     data_item               ; -> bp = its text, t0 = length, t1 = quoted
        pla
        sta     z:ap
        pla
        sta     z:ap+2
        lda     inkind
        cmp     #K_STR
        beq     @str
        lda     z:t0
        jsr     parse_num
        bcs     @bad
        cpy     z:t0                    ; the whole item
        bcc     @bad
        bra     @set
@str:   lda     z:bp
        sta     flo
        lda     z:bp+2
        sta     fhi
        lda     z:t0
        sta     flen
        lda     #T_STR
        sta     ft
@set:   lda     inkind
        jsr     assign
        jsr     peek
        cmp     #','
        beq     :+
        jmp     stmt_end
:       inc     z:tp
        bra     @l
@bad:   lda     dline                   ; (the error is in the DATA line)
        sta     curidx
        err     E_TYPE

; the next DATA item -> bp (its text), t0 (length), t1 = 1 if it was quoted. The data
; pointer: dline (line index), dptr (the position in it; 0 = search the line from its
; start for DATA).
data_item:
        lda     dptr
        bne     @at
@line:  lda     dline                   ; the next DATA statement from line dline
        cmp     nlines
        jcs     @none
        jsr     idx_ptr
        lda     z:ap
        clc
        adc     #4
        sta     z:ep
        lda     z:ap+2
        sta     z:ep+2
@t:     lda     [ep]
        and     #$00FF
        bne     :+
        inc     dline
        bra     @line
:       cmp     #TK_DATA
        beq     :+
        jsr     tk_size
        clc
        adc     z:ep
        sta     z:ep
        bra     @t
:       lda     z:ep
        inc     a
        sta     dptr
@at:    lda     dline                   ; ep = dline's bank : dptr
        jsr     idx_ptr
        lda     dptr
        sta     z:ep
        lda     z:ap+2
        sta     z:ep+2
        ldy     #0
:       lda     [ep],y                  ; spaces
        and     #$00FF
        cmp     #' '
        bne     :+
        iny
        bra     :-
:       cmp     #0                      ; the statement's end: on to the next DATA
        jeq     @next
        cmp     #':'
        jeq     @next
        stz     z:t1
        cmp     #'"'
        beq     @q
        tya                             ; plain: to ',' ':' or the end
        clc
        adc     z:ep
        sta     z:bp
        lda     z:ep+2
        sta     z:bp+2
        sty     z:t2
:       lda     [ep],y
        and     #$00FF
        beq     :+
        cmp     #','
        beq     :+
        cmp     #':'
        beq     :+
        iny
        bra     :-
:       sty     z:t3                    ; (the end)
:       cpy     z:t2                    ; trailing spaces
        beq     :+
        dey
        lda     [ep],y
        iny
        and     #$00FF
        cmp     #' '
        bne     :+
        dey
        bra     :-
:       tya
        sec
        sbc     z:t2
        sta     z:t0
        ldy     z:t3
        bra     @after
@q:     iny                             ; quoted
        inc     z:t1
        tya
        clc
        adc     z:ep
        sta     z:bp
        lda     z:ep+2
        sta     z:bp+2
        sty     z:t2
:       lda     [ep],y
        and     #$00FF
        beq     :+
        cmp     #'"'
        beq     :+
        iny
        bra     :-
:       tya
        sec
        sbc     z:t2
        sta     z:t0
        lda     [ep],y
        and     #$00FF
        beq     :+
        iny
:       lda     [ep],y                  ; to the comma
        and     #$00FF
        cmp     #' '
        bne     @after
        iny
        bra     :-
@after: lda     [ep],y                  ; past a comma (a ':' or the end stays)
        and     #$00FF
        cmp     #','
        bne     :+
        iny
:       tya
        clc
        adc     z:ep
        sta     dptr
        rts
@next:  tya                             ; past this DATA: search on from here
        clc
        adc     z:ep
        sta     z:ep
@t2:    lda     [ep]
        and     #$00FF
        bne     :+
        inc     dline
        stz     dptr
        jmp     @line
:       cmp     #TK_DATA
        beq     :+
        jsr     tk_size
        clc
        adc     z:ep
        sta     z:ep
        bra     @t2
:       lda     z:ep
        inc     a
        sta     dptr
        jmp     @at
@none:  err     E_DATA

st_restore:
        stz     dline
        stz     dptr
        jsr     peek
        cmp     #TK_LINE
        bne     :+
        ldy     #1
        lda     [tp],y
        sta     errarg
        jsr     line_find               ; (the line or the next one)
        stx     dline
        lda     z:tp
        clc
        adc     #7
        sta     z:tp
:       jmp     stmt_end

; ---------------------------------------------------------------- END, STOP, CONT, RUN ...
st_end: jmp     prog_end

st_stop:
        jsr     snd_off
        jsr     game_stop
        lda     curidx
        sta     contidx
        lda     z:tp
        sta     conttp
        cmp     #$FFFF
        lda     #1
        sta     contok
        lda     curidx                  ; (a direct STOP: nothing to continue)
        cmp     #$FFFF
        bne     :+
        stz     contok
:       jsr     con_bol
        cprint  "Stopped"
        lda     curidx
        cmp     #$FFFF
        beq     :+
        cprint  " in "
        jsr     cur_lnum
        jsr     con_putu16
:       jsr     con_nl
        jmp     main_ready

st_cont:
        lda     contok
        beq     @no
        lda     contidx
        cmp     #$FFFF
        beq     @no
        stz     contok
        lda     conttp
        ldx     contidx
        jsr     set_pos
        lda     #POLLN
        sta     z:pollc
        jsr     game_resume             ; (2.0) full screen and sprites back
        jmp     stmt
@no:    err     E_CONT

st_run: jsr     at_end                  ; RUN: from the first line
        beq     run_start
        cmp     #TK_LINE                ; RUN 100
        beq     :+
        jsr     load_named              ; RUN "file" (any string expression, or a name
        bra     run_start               ; typed without quotes): LOAD, then RUN
:       jsr     lineref
        pha
        jsr     run_clear
        pla
        bra     run_at
; RUN: everything cleared, from the first line
run_start:
        rep     #$30
        phk
        plb
        ldx     err_sp
        txs
        jsr     run_clear
        lda     nlines
        bne     :+
        jmp     main_ready
:       lda     #0
run_at: jsr     line_start
        lda     #1
        sta     running
        lda     #POLLN
        sta     z:pollc
        jmp     stmt

; RUN and CLR: no values, no loops, DATA from the start, the default palette and sound
run_clear:
        jsr     lp_end                  ; (0.23) a new run, a new print job
        jsr     clr_all
        jsr     snd_off
        jsr     game_reset              ; (2.0) sprites, pictures, samples, full screen
        jsr     pal_restore
        lda     #1
        sta     gcolor
        stz     degm
        rts

st_clr: jsr     clr_all
        jmp     stmt_end

st_new: jsr     prog_new
        stz     fpath
        jsr     settitle
        jmp     main_ready

st_list:
        jsr     list_args
        jsr     list_range
        jmp     stmt_end
; LIST's and LLIST's lines: [n], [n]-[m] -> lfrom, lto
list_args:
        stz     lfrom
        lda     #$FFFF
        sta     lto
        jsr     at_end
        beq     @go
        cmp     #'-'
        beq     @to
        jsr     list_num
        sta     lfrom
        sta     lto
        jsr     peek
        cmp     #'-'
        bne     @go
        lda     #$FFFF
        sta     lto
@to:    inc     z:tp
        jsr     at_end
        beq     @go
        jsr     list_num
        sta     lto
@go:    rts
; a line number in LIST (a plain number token)
list_num:
        jsr     peek
        cmp     #TK_LINE
        bne     :+
        ldy     #1
        lda     [tp],y
        pha
        lda     z:tp
        clc
        adc     #7
        sta     z:tp
        pla
        rts
:       cmp     #TK_BYTE
        bne     :+
        ldy     #1
        lda     [tp],y
        and     #$00FF
        inc     z:tp
        inc     z:tp
        rts
:       cmp     #TK_INT
        bne     :+
        ldy     #3
        lda     [tp],y
        bne     :+
        dey
        dey
        lda     [tp],y
        pha
        lda     z:tp
        clc
        adc     #5
        sta     z:tp
        pla
        rts
:       err     E_SYNTAX

st_load:
        jsr     load_named
        jmp     main_ready
; LOAD "name" (a string expression) -> fpath, loaded (errors: Ready)
load_named:
        jsr     eval_str
        jsr     acc_path
        jsr     prog_load
        php
        jsr     settitle
        plp
        bcc     :+
        jmp     main_ready
:       rts

st_save:
        jsr     at_end
        beq     :+
        jsr     eval_str
        jsr     acc_path
:       lda     fpath
        and     #$00FF
        bne     :+
        err     E_ARG
:       jsr     prog_save
        bcc     :+
        jsr     con_puterr
        jmp     main_ready
:       jsr     settitle
        jmp     stmt_end

; the string in acc as a file name -> fpath (absolute, .BAS added without an extension)
acc_path:
        lda     flen
        beq     @bad
        cmp     #120
        bcs     @bad
        lda     flo
        sta     z:bp
        lda     fhi
        sta     z:bp+2
        ldy     #0
        a8
:       lda     [bp],y
        sta     abuf,y
        iny
        cpy     flen
        bcc     :-
        lda     #0
        sta     abuf,y
        a16
        ldx     #.loword(abuf)
        jmp     mkabs
@bad:   err     E_ARG

; DIR ["folder"]: the names, folders with a '/'
st_dir: stz     abuf
        jsr     at_end
        beq     :+
        jsr     eval_str
        jsr     acc_path0
:       jsr     dir_list
        jmp     stmt_end
; (the string as typed, no extension added)
acc_path0:
        lda     flen
        beq     @bad
        cmp     #120
        bcs     @bad
        lda     flo
        sta     z:bp
        lda     fhi
        sta     z:bp+2
        ldy     #0
        a8
:       lda     [bp],y
        sta     abuf,y
        iny
        cpy     flen
        bcc     :-
        lda     #0
        sta     abuf,y
        a16
        rts
@bad:   err     E_ARG

; the folder abuf ("" = the current one), several names a line
dir_list:
        lda     abuf
        and     #$00FF
        bne     :+
        lda     #'.'
        sta     abuf
:       stz     dr_skip
@batch: lda     #.loword(abuf)
        sta     drblk
        lda     codebk
        sta     drblk+2
        stz     drblk+3
        lda     fbank
        sta     drblk+5
        lda     #$F000
        sta     drblk+6
        lda     dr_skip
        sta     drblk+8
        ptr     drblk
        sys     SYS_READDIR
        bcc     :+
        jsr     con_puterr
        rts
:       sta     dr_n
        cmp     #0
        jeq     @out
        clc
        adc     dr_skip
        sta     dr_skip
        stz     z:ap
        lda     fbank
        sta     z:ap+2
@e:     lda     dr_n
        beq     @batch
        dec     dr_n
        ldy     #5                      ; name length
        lda     [ap],y
        and     #$00FF
        sta     z:t4
        ldy     #4
        lda     [ap],y
        and     #$0010
        sta     z:t5
        lda     z:t4                    ; the column: names are padded to 16
        clc
        adc     #2
        clc
        adc     ccol
        cmp     ccols
        bcc     :+
        lda     ccol
        beq     :+
        jsr     con_nl
:       ldy     #6
@nm:    tya
        sec
        sbc     #6
        cmp     z:t4
        bcs     @nmd
        lda     [ap],y
        phy
        jsr     con_putc
        ply
        iny
        bra     @nm
@nmd:
:       lda     z:t5
        beq     :+
        lda     #'/'
        jsr     con_putc
:       lda     ccol                    ; to the next multiple of 16
        and     #$FFF0
        clc
        adc     #16
        cmp     ccols
        bcc     :+
        jsr     con_nl
        bra     :++
:       jsr     tabto
:       lda     z:t4
        clc
        adc     #6
        clc
        adc     z:ap
        sta     z:ap
        dec     z:pollc
        bne     @e
        jsr     periodic
        bra     @e
@out:   jmp     con_bol

st_poke:
        jsr     eval_u16
        pha
        lda     #','
        jsr     expect
        jsr     eval_int
        lda     fhi
        bne     @bad
        lda     flo
        cmp     #256
        bcs     @bad
        jsr     kb_get
        ply
        lda     flo
        a8
        sta     [ep],y
        a16
        jmp     stmt_end
@bad:   err     E_ARG

st_cls: lda     #12
        jsr     con_putc
        jmp     stmt_end

; PAUSE ms: the windows drawn, then a wait (events and Esc are seen)
st_pause:
        jsr     eval_int
        pei     (fhi)
        pei     (flo)
        jsr     flush_all
        pla
        sta     flo
        pla
        sta     fhi
        lda     fhi
        bmi     @out
        sys     SYS_UPTIME
        clc
        adc     flo
        sta     pz_end
        txa
        adc     fhi
        sta     pz_end+2
@l:     lda     #1
        jsr     pump
        bcc     @l
        lda     brkf
        jne     do_break
        sys     SYS_UPTIME
        stx     z:t1
        sta     z:t0
        lda     pz_end                  ; left = end - now
        sec
        sbc     z:t0
        sta     z:t0
        lda     pz_end+2
        sbc     z:t1
        bmi     @out
        bne     :+
        lda     z:t0
        beq     @out
        cmp     #20
        bcc     :++
:       lda     #20
:       sys     SYS_SLEEP
        bra     @l
@out:   lda     #POLLN
        sta     z:pollc
        jmp     stmt_end

st_randomize:
        jsr     at_end
        bne     :+
        sys     SYS_UPTIME
        sta     flo
        stx     fhi
        bra     :++
:       jsr     eval_int
:       lda     flo
        ora     fhi
        bne     :+
        inc     flo
:       lda     flo
        sta     rseed
        lda     fhi
        sta     rseed+2
        jmp     stmt_end

; ---------------------------------------------------------------- the statement table
        .segment "RODATA"
stab:   .addr   st_let, st_print, st_input, st_if, st_goto, st_gosub, st_return, st_on   ; $80
        .addr   st_for, st_next, st_while, st_wend, st_dim, st_data, st_read, st_restore ; $88
        .addr   st_rem, st_rem, st_end, st_stop, st_cont, st_run, st_list, st_new       ; $90
        .addr   st_clr, st_load, st_save, st_poke, st_cls, st_pause, st_randomize, st_screen ; $98
        .addr   st_color, st_plot, st_line, st_rect, st_frect, st_circle, st_text, st_palette ; $A0
        .addr   st_gcls, st_sound, st_beep, st_dir, st_deg, st_rad, st_vsync, syn_err   ; $A8
        .repeat 16
        .addr   syn_err                                                                  ; $B0
        .endrepeat
        .repeat 48
        .addr   syn_err                                                                  ; $C0
        .endrepeat
        .addr   st_implet, st_implet, st_implet, st_implet                               ; $F0
        .repeat 6
        .addr   syn_err
        .endrepeat
        .addr   st_implet, st_implet, st_x, syn_err, syn_err, syn_err                   ; $FA


        .segment "BSS"
stmtp:    .res    2               ; tp at the statement's start
csp:    .res    2
pnl:    .res    2
inq:    .res    2
invars: .res    2
in_x:    .res    2
inkind: .res    2
fvar:   .res    2
fkind:  .res    2
fflt:   .res    2
flim:   .res    8               ; (FOR: then fstep)
fstep:  .res    8
nx_f:   .res    2
wend_idx: .res  2
wend_tp: .res   2
dimkind: .res   2
dimvar: .res    2
dimn:   .res    2
dimsz:  .res    10
dline:  .res    2
dptr:   .res    2
contok: .res    2
contidx: .res   2
conttp: .res    2
pz_end: .res    4
dr_skip: .res   2
dr_n:   .res    2
drblk:  .res    10
dbuf:   .res    TMAX + 8
