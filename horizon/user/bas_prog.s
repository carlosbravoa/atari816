; bas_prog.s - the program store: the line index, the lines, LIST, LOAD and SAVE.
;
; The line index (bank IB): the line numbers in order at IB:0 + 2 i, the lines' addresses
; (u24, 4 bytes each) at IB:LPTR + 4 i; nlines entries (at most MAXLINES). A lookup is a
; binary search (13 steps for 8000 lines); GOTO and GOSUB also cache the index they found
; in their TK_LINE token (valid while its generation = pgen, bumped by every edit).
; A line: {u16 number, u16 size of the record, tokens, 0}, in a program bank (PB, filled
; from the bottom; a replaced or deleted line becomes garbage). When the banks are full,
; the live lines are copied into fresh banks in line order (compaction).
; Editing the program clears the variables (as in Microsoft BASIC): so a string variable
; may point at a literal in the program, and CONT is not possible after an edit.

        .segment "CODE"
        .a16
        .i16
MAXLINES = 8000
LPTR    = $4000
MAXPB   = 8
PBLIM   = $FFF0
LCHUNK  = 4096

; NEW: no program, no variables, no names
prog_new:
        jsr     game_reset              ; (2.0)
        jsr     prog_clear
        jsr     sym_reset
        jsr     clr_all
        stz     pmod
        rts

; no lines
prog_clear:
        ldx     #0
:       cpx     npb
        bcs     :+
        phx
        txa
        asl     a
        tax
        lda     pb,x
        sys     SYS_BFREE
        plx
        inx
        bra     :-
:       stz     npb
        stz     nlines
        stz     pboff
        lda     #1
        sta     pgen
        stz     contok
        rts

; A = line number -> X = its index (or where it would go), C set if it exists
line_find:
        sta     lf_key
        stz     lf_lo
        lda     nlines
        sta     lf_hi
@l:     lda     lf_lo
        cmp     lf_hi
        bcs     @no
        clc
        adc     lf_hi
        lsr     a
        sta     lf_mid
        asl     a
        tay
        lda     [ib],y
        cmp     lf_key
        beq     @yes
        bcs     :+
        lda     lf_mid                  ; below: lo = mid + 1
        inc     a
        sta     lf_lo
        bra     @l
:       lda     lf_mid                  ; above: hi = mid
        sta     lf_hi
        bra     @l
@yes:   ldx     lf_mid
        sec
        rts
@no:    ldx     lf_lo
        clc
        rts

; A = line index -> ap = its record
idx_ptr:
        asl     a
        asl     a
        tay
        lda     [ipt],y
        sta     z:ap
        iny
        iny
        lda     [ipt],y
        sta     z:ap+2
        rts

; run line A from its start: curidx, tp
line_start:
        sta     curidx
        asl     a
        asl     a
        tay
        lda     [ipt],y
        clc
        adc     #4
        sta     z:tp
        iny
        iny
        lda     [ipt],y
        sta     z:tp+2
        rts

; the number of the current line -> A
cur_lnum:
        lda     curidx
        asl     a
        tay
        lda     [ib],y
        rts

; the line in tbuf (tlen bytes) as line tlnum: stored, replaced, or (no tokens) deleted
prog_enter:
        lda     loading
        bne     :+
        jsr     clr_all                 ; an edit: no variables, no CONT
        stz     contok
        jsr     setmod
:       inc     pgen                    ; the GOTO caches are stale
        bne     :+
        inc     pgen
        jsr     cache_clear
:       lda     tlnum
        jsr     line_find
        stx     pe_idx
        lda     #0
        rol     a
        sta     pe_found
        lda     tlen
        cmp     #2
        bcs     @store
        lda     pe_found                ; delete
        beq     @out
        dec     nlines
        lda     pe_idx                  ; entries above move down
        sta     z:t0
@dl:    lda     z:t0
        cmp     nlines
        bcs     @out
        asl     a
        tay
        iny
        iny
        lda     [ib],y
        dey
        dey
        sta     [ib],y
        tya
        asl     a
        tay
        iny
        iny
        iny
        iny
        lda     [ipt],y
        pha
        iny
        iny
        lda     [ipt],y
        dey
        dey
        dey
        dey
        sta     [ipt],y
        dey
        dey
        pla
        sta     [ipt],y
        inc     z:t0
        bra     @dl
@out:   rts
@store: lda     pe_found
        bne     :+
        lda     nlines
        cmp     #MAXLINES
        bcc     :+
        err     E_LINES
:       lda     tlen
        clc
        adc     #4
        jsr     ln_alloc                ; -> ap
        lda     tlnum
        sta     [ap]
        lda     tlen
        clc
        adc     #4
        ldy     #2
        sta     [ap],y
        ldx     #0
        ldy     #4
        a8
:       lda     tbuf,x
        sta     [ap],y
        inx
        iny
        cpx     tlen
        bcc     :-
        a16
        lda     pe_found
        bne     @set
        lda     nlines                  ; entries from idx move up
        sta     z:t0
@ul:    lda     z:t0
        cmp     pe_idx
        beq     @ins
        dec     a
        asl     a
        tay
        lda     [ib],y
        iny
        iny
        sta     [ib],y
        dey
        dey
        tya
        asl     a
        tay
        lda     [ipt],y
        pha
        iny
        iny
        lda     [ipt],y
        iny
        iny
        iny
        iny
        sta     [ipt],y
        dey
        dey
        pla
        sta     [ipt],y
        dec     z:t0
        bra     @ul
@ins:   inc     nlines
        lda     pe_idx
        asl     a
        tay
        lda     tlnum
        sta     [ib],y
@set:   lda     pe_idx
        asl     a
        asl     a
        tay
        lda     z:ap
        sta     [ipt],y
        iny
        iny
        lda     z:ap+2
        sta     [ipt],y
        rts

; A bytes in a program bank -> ap (compacts, or E_MEM)
ln_alloc:
        sta     la_size
        stz     la_try
@again: lda     npb
        beq     @new
        lda     pboff
        clc
        adc     la_size
        bcs     @new
        cmp     #PBLIM
        bcs     @new
        lda     pboff
        sta     z:ap
        lda     pbcur
        sta     z:ap+2
        lda     pboff
        clc
        adc     la_size
        sta     pboff
        rts
@new:   lda     npb
        cmp     #MAXPB
        bcs     @comp
        sys     SYS_BALLOC
        bcs     @comp
        sta     pbcur
        pha
        lda     npb
        asl     a
        tax
        pla
        sta     pb,x
        inc     npb
        stz     pboff
        bra     @again
@comp:  lda     la_try
        bne     @fail
        inc     la_try
        jsr     prog_compact
        bcc     @again
@fail:  err     E_MEM

; the live lines into fresh banks, in order; the old banks freed -> C set: not enough
; banks (then nothing changed). The banks needed are counted first and taken at once.
prog_compact:
        stz     pc_n                    ; a dry run: how many banks
        lda     #PBLIM
        sta     pc_off
        stz     pc_i
@cnt:   lda     pc_i
        cmp     nlines
        bcs     @alloc
        jsr     idx_ptr
        ldy     #2
        lda     [ap],y
        sta     z:t5
        lda     pc_off
        clc
        adc     z:t5
        bcs     :+
        cmp     #PBLIM
        bcc     :++
:       inc     pc_n
        lda     z:t5
:       sta     pc_off
        inc     pc_i
        bra     @cnt
@alloc: lda     pc_n
        cmp     #MAXPB + 1
        bcs     @fail0
        stz     pc_i
:       lda     pc_i
        cmp     pc_n
        bcs     @copy
        sys     SYS_BALLOC
        bcs     @fail
        pha
        lda     pc_i
        asl     a
        tax
        pla
        sta     npbk,x
        inc     pc_i
        bra     :-
@fail:  dec     pc_i                    ; give them back
        bmi     @fail0
        lda     pc_i
        asl     a
        tax
        lda     npbk,x
        sys     SYS_BFREE
        bra     @fail
@fail0: sec
        rts
@copy:  ldx     #0                      ; the old banks aside, the new ones in
:       cpx     npb
        bcs     :+
        txa
        asl     a
        tay
        lda     pb,y
        sta     opb,y
        inx
        bra     :-
:       stx     onpb
        ldx     #0
:       cpx     pc_n
        bcs     :+
        txa
        asl     a
        tay
        lda     npbk,y
        sta     pb,y
        inx
        bra     :-
:       stx     npb
        stz     pc_b                    ; (index of the bank being filled, * 2)
        lda     #PBLIM
        sta     pboff
        stz     pc_i
@l:     lda     pc_i
        cmp     nlines
        jcs     @done
        jsr     idx_ptr
        lda     z:ap
        sta     z:bp
        lda     z:ap+2
        sta     z:bp+2
        ldy     #2
        lda     [bp],y                  ; its size
        sta     z:t5
        lda     pboff
        clc
        adc     z:t5
        bcs     :+
        cmp     #PBLIM
        bcc     @cp
:       ldx     pc_b                    ; the next new bank
        lda     pb,x
        sta     pbcur
        inx
        inx
        stx     pc_b
        stz     pboff
@cp:    lda     pboff
        sta     z:ap
        lda     pbcur
        sta     z:ap+2
        ldy     #0
        a8
:       lda     [bp],y
        sta     [ap],y
        iny
        cpy     z:t5
        bcc     :-
        a16
        lda     pboff
        clc
        adc     z:t5
        sta     pboff
        lda     pc_i
        asl     a
        asl     a
        tay
        lda     z:ap
        sta     [ipt],y
        iny
        iny
        lda     z:ap+2
        sta     [ipt],y
        inc     pc_i
        bra     @l
@done:  ldx     #0                      ; the old banks go
:       cpx     onpb
        bcs     :+
        phx
        txa
        asl     a
        tax
        lda     opb,x
        sys     SYS_BFREE
        plx
        inx
        bra     :-
:       lda     npb                     ; (no lines: no bank)
        bne     :+
        lda     #0
        sta     pbcur
:       clc
        rts

; every TK_LINE cache marked stale (pgen wrapped)
cache_clear:
        stz     pc_i
@l:     lda     pc_i
        cmp     nlines
        bcs     @out
        jsr     idx_ptr
        lda     z:ap
        clc
        adc     #4
        sta     z:ep
        lda     z:ap+2
        sta     z:ep+2
@t:     lda     [ep]
        and     #$00FF
        beq     @n
        cmp     #TK_LINE
        bne     :+
        lda     #0
        ldy     #5
        sta     [ep],y
:       jsr     tk_size
        clc
        adc     z:ep
        sta     z:ep
        bra     @t
@n:     inc     pc_i
        bra     @l
@out:   rts

; the size of the token at [ep] -> A (the bytes to the next token)
tk_size:
        lda     [ep]
        and     #$00FF
        cmp     #TK_NVAR
        bcc     @kw
        cmp     #TK_INT
        bcc     @3
        beq     @5
        cmp     #TK_HEX
        beq     @5
        cmp     #TK_BYTE
        beq     @2
        cmp     #TK_LINE
        beq     @7
        cmp     #TK_FLT
        beq     @9
        cmp     #TK_X                   ; (2.0) an extended statement: two bytes
        beq     @2
        cmp     #TK_IVAR
        bcs     @3
        cmp     #TK_STRL
        bne     @1
        ldy     #1
        lda     [ep],y
        and     #$00FF
        clc
        adc     #2
        rts
@kw:    cmp     #TK_REM
        beq     @eol
        cmp     #TK_APOS
        beq     @eol
        cmp     #TK_DATA
        beq     @data
@1:     lda     #1
        rts
@2:     lda     #2
        rts
@3:     lda     #3
        rts
@9:     lda     #9
        rts
@5:     lda     #5
        rts
@7:     lda     #7
        rts
@eol:   ldy     #1
:       lda     [ep],y
        and     #$00FF
        beq     :+
        iny
        bra     :-
:       tya
        rts
@data:  ldy     #1
        stz     z:t7
@dl:    lda     [ep],y
        and     #$00FF
        beq     @dend
        cmp     #'"'
        bne     :+
        lda     z:t7
        eor     #1
        sta     z:t7
        bra     @dn
:       cmp     #':'
        bne     @dn
        lda     z:t7
        beq     @dend
@dn:    iny
        bra     @dl
@dend:  tya
        rts

; ---------------------------------------------------------------- LIST
; the lines lfrom .. lto
list_range:
        lda     lfrom
        jsr     line_find
        stx     lidx
@l:     lda     lidx
        cmp     nlines
        bcs     @out
        asl     a
        tay
        lda     [ib],y
        cmp     lto
        beq     :+
        bcs     @out
:       lda     lidx
        jsr     idx_ptr
        jsr     detok
        ldx     #.loword(lbuf)
        jsr     con_puts
        jsr     con_nl
        dec     z:pollc
        bne     :+
        jsr     periodic
:       inc     lidx
        bra     @l
@out:   rts

; ---------------------------------------------------------------- SAVE
; the program as text to fpath -> C set, A = the error
prog_save:
        ptr     fpath
        lda     #O_CREATE
        sys     SYS_OPEN
        bcc     :+
        rts
:       sta     lfh
        stz     ps_n                    ; bytes in FB
        stz     lidx
@l:     lda     lidx
        cmp     nlines
        bcs     @end
        jsr     idx_ptr
        jsr     detok
        lda     ps_n                    ; room?
        cmp     #$F000
        bcc     :+
        jsr     @flush
        bcs     @err
:       ldx     #0
        ldy     ps_n
:       lda     lbuf,x
        and     #$00FF
        beq     :+
        a8
        sta     [fbp],y
        a16
        inx
        iny
        bra     :-
:       lda     #10
        a8
        sta     [fbp],y
        a16
        iny
        sty     ps_n
        inc     lidx
        bra     @l
@end:   jsr     @flush
        bcs     @err
        lda     lfh
        sys     SYS_CLOSE
        bcs     @err2
        stz     pmod
        clc
        rts
@err:   pha
        lda     lfh
        sys     SYS_CLOSE
        pla
@err2:  sec
        rts
@flush: lda     ps_n
        beq     :+
        lda     lfh
        sta     rblk
        stz     rblk+1
        lda     fbank
        sta     rblk+3
        lda     ps_n
        sta     rblk+4
        ptr     rblk
        sys     SYS_WRITE
        bcs     :++
        cmp     ps_n
        bne     @short
        stz     ps_n
:       clc
:       rts
@short: lda     #$47
        sec
        rts

; ---------------------------------------------------------------- LOAD
; the text file fpath as the program (NEW first) -> C set: the file could not be read
; (said on the console). Lines without a number, or bad lines, are errors ("... in file
; line N"): what came before stays.
prog_load:
        ptr     fpath
        lda     #O_READ
        sys     SYS_OPEN
        bcc     :+
        jsr     con_puterr
        sec
        rts
:       sta     lfh
        jsr     prog_new
        lda     #1
        sta     loading
        stz     lfline
        stz     ilen
@chunk: lda     lfh
        sta     rblk
        stz     rblk+1
        lda     fbank
        sta     rblk+3
        lda     #LCHUNK
        sta     rblk+4
        ptr     rblk
        sys     SYS_READ
        bcc     :+
        pha
        jsr     load_end
        pla
        jsr     con_puterr
        sec
        rts
:       sta     ld_n
        ldy     #0
@b:     cpy     ld_n
        bcs     @more
        lda     [fbp],y
        iny
        and     #$00FF
        cmp     #10
        beq     @line
        cmp     #9
        bne     :+
        lda     #' '
:       cmp     #' '
        bcc     @b
        cmp     #127
        bcs     @b
        ldx     ilen
        cpx     #IMAX
        bcc     :+
        inc     lfline
        err     E_LONG
:       a8
        sta     ibuf,x
        a16
        inc     ilen
        bra     @b
@line:  phy
        jsr     load_line
        ply
        bra     @b
@more:  lda     ld_n
        cmp     #LCHUNK
        bcs     @chunk
        jsr     load_line               ; the last line (no line end)
        jsr     load_end
        stz     pmod
        clc
        rts

; the line in ibuf (ilen) into the program
load_line:
        inc     lfline
        ldx     ilen
        stz     ilen
        a8
        stz     ibuf,x
        a16
        ldx     #0                      ; blank?
:       lda     ibuf,x
        and     #$00FF
        beq     @out
        cmp     #' '
        bne     :+
        inx
        bra     :-
:       jsr     tokenize
        lda     tline
        bne     :+
        err     E_NOLN
:       jmp     prog_enter
@out:   rts

load_end:
        stz     loading
        lda     lfh
        sys     SYS_CLOSE
        rts

        .segment "BSS"
nlines: .res    2
pgen:   .res    2
npb:    .res    2
pbcur:  .res    2
pboff:  .res    2
pb:     .res    MAXPB * 2
opb:    .res    MAXPB * 2
npbk:   .res    MAXPB * 2 + 2
pc_n:   .res    2
pc_off: .res    2
pc_b:   .res    2
onpb:   .res    2
pc_i:   .res    2
la_size: .res   2
la_try: .res    2
lf_key: .res    2
lf_lo:  .res    2
lf_hi:  .res    2
lf_mid: .res    2
pe_idx: .res    2
pe_found: .res  2
curidx: .res    2               ; the line running ($FFFF: a direct command)
lidx:   .res    2
lfrom:  .res    2
lto:    .res    2
lfh:    .res    2               ; the file being loaded or saved
loading: .res   2               ; 1 while LOAD reads
lfline: .res    2               ; its line count
ld_n:   .res    2
ps_n:   .res    2
rblk:   .res    6
