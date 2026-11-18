; sht_file.s - Sheet: a cell's text forms, files (.SHT, CSV), the clipboard (part of sheet.s).
;
; The .SHT format: text, one item per line (LF or CR LF), read in any order:
;   SHEET 1                 the first line (a file without it is still read)
;   W <column> <width>      a column's width in pixels (16-400), only where not the default
;   F <column> <format>     a column's number format: G (general) or 0-4 (fixed decimals),
;                           then T (thousands separators) and / or P (percent); e.g. 2T
;   <cell> <content>        a cell, e.g. "B3 =SUM(B1:B2)": the content exactly as it would
;                           be typed into the entry line (text that would read as a number
;                           or a formula starts with an apostrophe)
;   # ...                   a comment
; Lines it does not know are skipped. Cells are written row by row.
;
; CSV: fields separated by commas, a field in double quotes may hold commas, quotes ("")
; and line breaks; every field is read as if typed (numbers become numbers). Export
; writes the values (formulas as their results, errors by name), numbers in the general
; format, text quoted when it needs to be.
CHUNK   = 4096
LMAX    = 300                           ; a line of a file
WFLUSH  = 60000

        .segment "CODE"

; ---------------------------------------------------------------- a cell's text forms
; tbuf (zero-terminated, as typed) -> cell c_ci. C set: A = CE_SYNTAX (a formula that does
; not compile: the cell is unchanged, unless ce_force is set: then it is kept with the
; value #VALUE) or CE_MEM (out of memory).
CE_SYNTAX = 1
CE_MEM  = 2
cell_enter:
        lda     #1
        sta     dirty
        ldx     #.loword(tbuf)
        jsr     ui_strlen
        sta     c_tlen
        stz     c_clen
        cmp     #0
        bne     :+
        lda     c_ci                    ; nothing: the cell emptied
        jsr     cell_clear
        clc
        rts
:       lda     tbuf
        and     #$00FF
        cmp     #$27                    ; an apostrophe: text
        bne     @form
        ldx     #.loword(tbuf + 1)
        ldy     #.loword(tbuf)
        jsr     ui_strcpy
        sta     c_tlen
        bra     @text
@form:  cmp     #'='
        bne     @num
        jsr     fx_comp
        bcc     :+
        lda     ce_force
        bne     @bad
        lda     #CE_SYNTAX
        sec
        rts
@bad:   lda     #OP_ERR | (E_VALUE << 8)
        sta     cbuf
        lda     #2
        sta     c_clen
:       lda     #T_FORM
        bra     @put
@num:   jsr     txt_num
        bcs     @text
        lda     #T_NUM
        stz     c_tlen
        bra     @put
@text:  lda     #T_TEXT
@put:   sta     c_type
        jsr     cell_put
        bcc     :+
        lda     #CE_MEM
:       rts

; tbuf as a number (spaces around, a sign, 1,234.5, 12%) -> C clear: na
txt_num:
        lda     #.loword(tbuf)
        sta     z:sp
        lda     #^tbuf
        sta     z:sp+2
        ldy     #0
        jsr     @sp
        stz     tn_neg
        cmp     #'-'
        bne     :+
        inc     tn_neg
        iny
        bra     :++
:       cmp     #'+'
        bne     :+
        iny
:       lda     #3
        sta     n_pflags
        jsr     n_parse
        bcs     @no
        jsr     @sp
        cmp     #0
        bne     @no
        lda     tn_neg
        beq     :+
        jsr     n_nega
:       clc
        rts
@no:    sec
        rts
@sp:    lda     tbuf,y
        and     #$00FF
        cmp     #' '
        bne     :+
        iny
        bra     @sp
:       rts

; cell A as it would be typed -> tbuf (zero-terminated), A = its length
cell_src:
        jsr     cell_get
        bcc     :+
        stz     tbuf
        lda     #0
        rts
:       ldy     #R_TYPE
        lda     [gp],y
        and     #$00FF
        cmp     #T_NUM
        bne     @txt
        jsr     ld_val
        lda     #0
        jsr     n_fmt
        ldx     #.loword(fbuf)
        ldy     #.loword(tbuf)
        jmp     ui_strcpy
@txt:   pha
        ldy     #R_TLEN                 ; the text (T_TEXT and T_FORM)
        lda     [gp],y
        sta     cs_n
        ldx     #0
        ldy     #R_TEXT
        sep     #$20
        .a8
:       cpx     cs_n
        bcs     :+
        lda     [gp],y
        sta     tbuf,x
        iny
        inx
        bra     :-
:       stz     tbuf,x
        rep     #$20
        .a16
        pla
        cmp     #T_TEXT
        bne     @out
        lda     tbuf                    ; text read as something else: an apostrophe first
        and     #$00FF
        cmp     #'='
        beq     @q
        cmp     #$27
        beq     @q
        jsr     txt_num
        bcs     @out
@q:     ldx     cs_n                    ; shift right by one
:       lda     tbuf,x
        sta     tbuf+1,x                ; (a word: the byte above is the next one, set first)
        dex
        bpl     :-
        sep     #$20
        .a8
        lda     #$27
        sta     tbuf
        rep     #$20
        .a16
        inc     cs_n
@out:   lda     cs_n
        rts

; na = the value of the record at gp
ld_val: ldy     #R_VAL
        lda     [gp],y
        sta     z:na
        iny
        iny
        lda     [gp],y
        sta     z:na+2
        iny
        iny
        lda     [gp],y
        sta     z:na+4
        iny
        iny
        lda     [gp],y
        sta     z:na+6
        rts

; cell A as shown with format X -> fbuf (zero-terminated), A = its length, dalign (0 left,
; 1 right, 2 centred), dink (its colour), dkind (0 empty, 1 number, 2 text, 3 error)
cell_disp:
        stx     cd_f
        stz     dalign
        stz     dkind
        ldx     #C_BLACK
        stx     dink
        jsr     cell_get
        bcc     :+
        stz     fbuf
        lda     #0
        rts
:       ldy     #R_TYPE
        lda     [gp],y
        and     #$00FF
        cmp     #T_TEXT
        beq     @txt
        cmp     #T_FORM
        bne     @num
        lda     [gp],y
        xba
        and     #$00FF
        bne     @err
@num:   jsr     ld_val
        lda     #1
        sta     dalign
        sta     dkind
        lda     cd_f
        jmp     n_fmt
@err:   ldy     #R_VAL
        lda     [gp],y
        and     #$00FF
        cmp     #6
        bcc     :+
        lda     #0
:       asl     a
        tax
        lda     errnames,x
        tax
        ldy     #.loword(fbuf)
        lda     #2
        sta     dalign
        lda     #3
        sta     dkind
        lda     #C_RED
        sta     dink
        jmp     ui_strcpy
@txt:   lda     #2
        sta     dkind
        ldy     #R_TLEN
        lda     [gp],y
        sta     cs_n
        ldx     #0
        ldy     #R_TEXT
        sep     #$20
        .a8
:       cpx     cs_n
        bcs     :+
        lda     [gp],y
        sta     fbuf,x
        iny
        inx
        bra     :-
:       stz     fbuf,x
        rep     #$20
        .a16
        txa
        rts

; cell index A -> its name in nmbuf ("B12"), A = the length
ci_name:
        pha
        xba
        lsr     a
        lsr     a
        and     #$003F
        clc
        adc     #'A'
        sta     nmbuf
        ldx     #1
        pla
        and     #CPC - 1
        inc     a
        jsr     put_decx
        stz     nmbuf,x
        txa
        rts
; A (0-65535) in decimal at nmbuf + X, X past it
put_decx:
        stx     pd_x
        ldx     #8
@d:     ldy     #0                      ; digits right to left into pd_buf
:       cmp     p10d,x
        bcc     :+
        sbc     p10d,x
        iny
        bra     :-
:       pha
        tya
        sta     pd_buf,x
        pla
        dex
        dex
        bpl     @d
        ldx     #8                      ; skip leading zeros (the last digit stays)
:       cpx     #0
        beq     :+
        lda     pd_buf,x
        bne     :+
        dex
        dex
        bra     :-
:       ldy     pd_x
:       lda     pd_buf,x
        clc
        adc     #'0'
        sep     #$20
        .a8
        sta     nmbuf,y
        rep     #$20
        .a16
        iny
        dex
        dex
        bpl     :-
        tyx
        stz     nmbuf,x
        rts

; ---------------------------------------------------------------- reading a file
; fh open: start reading
rd_init:
        stz     rd_pos
        stz     rd_n
        stz     rd_eof
        stz     rd_err
        rts
; the next byte -> A; C set at the end (or an error: rd_err)
rd_byte:
        ldy     rd_pos
        cpy     rd_n
        bcc     @have
        lda     rd_eof
        bne     @end
        lda     fh
        sta     rblk
        stz     rblk+1
        lda     sbank
        sta     rblk+3
        lda     #CHUNK
        sta     rblk+4
        ptr     rblk
        sys     SYS_READ
        bcc     :+
        sta     rd_err
        lda     #0
:       sta     rd_n
        cmp     #CHUNK
        beq     :+
        inc     rd_eof
:       stz     rd_pos
        ldy     #0
        cpy     rd_n
        bcs     @end
@have:  lda     [sb],y
        and     #$00FF
        iny
        sty     rd_pos
        clc
        rts
@end:   sec
        rts

; the next line of the file -> lbuf (zero-terminated, CR dropped, cut at LMAX), A = length;
; C set: the end, nothing read
rd_line:
        stz     ln_n
        stz     ln_any
@l:     jsr     rd_byte
        bcs     @eof
        inc     ln_any
        cmp     #10
        beq     @end
        cmp     #13
        beq     @l
        ldx     ln_n
        cpx     #LMAX
        bcs     @l
        sep     #$20
        .a8
        sta     lbuf,x
        rep     #$20
        .a16
        inc     ln_n
        bra     @l
@eof:   lda     ln_any
        bne     @end
        sec
        rts
@end:   ldx     ln_n
        stz     lbuf,x
        txa
        clc
        rts

; ---------------------------------------------------------------- writing a file
wr_init:
        stz     wr_n
        stz     wr_err
        rts
; byte A
wr_byte:
        ldy     wr_n
        sep     #$20
        .a8
        sta     [sb],y
        rep     #$20
        .a16
        iny
        sty     wr_n
        cpy     #WFLUSH
        bcs     wr_flush
        rts
; the string X (code bank)
wr_str: lda     a:0,x
        and     #$00FF
        beq     :+
        phx
        jsr     wr_byte
        plx
        inx
        bra     wr_str
:       rts
wr_flush:
        lda     wr_n
        beq     @out
        lda     fh
        sta     rblk
        stz     rblk+1
        lda     sbank
        sta     rblk+3
        lda     wr_n
        sta     rblk+4
        ptr     rblk
        sys     SYS_WRITE
        bcs     @err
        cmp     wr_n
        beq     @ok
        lda     #$47                    ; (short: the card is full)
@err:   sta     wr_err
@ok:    stz     wr_n
@out:   rts

; ---------------------------------------------------------------- .SHT
; load fpath into an empty sheet -> C set: A = the open / read error
sht_load:
        ptr     fpath
        lda     #O_READ
        sys     SYS_OPEN
        bcc     :+
        rts
:       sta     fh
        jsr     rd_init
        lda     #1
        sta     ce_force
@l:     jsr     rd_line
        bcs     @end
        jsr     sht_line
        bcc     @l
        bra     @end                    ; (out of memory: what fitted stays)
@end:   stz     ce_force
        lda     fh
        sys     SYS_CLOSE
        lda     rd_err
        beq     :+
        sec
        rts
:       clc
        rts

; one line of a .SHT file in lbuf -> C set: out of memory
sht_line:
        lda     lbuf
        and     #$00FF
        jsr     isletter
        bcc     @skip
        and     #$00DF
        sta     sl_c
        lda     lbuf+1
        and     #$00FF
        jsr     isdigit
        bcs     @cell
        cmp     #' '
        bne     @skip
        lda     lbuf+2                  ; "W x ..." / "F x ..."
        and     #$00FF
        jsr     isletter
        bcc     @skip
        and     #$00DF
        sec
        sbc     #'A'
        sta     sl_col
        lda     lbuf+3
        and     #$00FF
        cmp     #' '
        bne     @skip
        lda     sl_c
        cmp     #'W'
        beq     @width
        cmp     #'F'
        bne     @skip
        ldy     #4                      ; a format
        jsr     fmt_parse
        ldx     sl_col
        sep     #$20
        .a8
        sta     colfmt,x
        rep     #$20
        .a16
@skip:  clc
        rts
@width: ldx     #4
        jsr     ln_dec
        cmp     #MINW
        bcc     @skip
        cmp     #MAXW + 1
        bcs     @skip
        pha
        lda     sl_col
        asl     a
        tax
        pla
        sta     colw,x
        clc
        rts
@cell:  lda     sl_c                    ; a cell: its row, then one space, the content
        sec
        sbc     #'A'
        sta     sl_col
        ldx     #1
        jsr     ln_dec
        cmp     #1
        bcc     @skip
        cmp     #NROW + 1
        bcs     @skip
        dec     a
        sta     sl_row
        lda     lbuf,x
        and     #$00FF
        cmp     #' '
        bne     @skip
        inx
        ldy     #0                      ; the content -> tbuf (cut at TXTMAX)
        sep     #$20
        .a8
:       lda     lbuf,x
        beq     :+
        sta     tbuf,y
        inx
        iny
        cpy     #TXTMAX
        bcc     :-
:       lda     #0
        sta     tbuf,y
        rep     #$20
        .a16
        lda     sl_col
        xba
        asl     a
        asl     a
        ora     sl_row
        sta     c_ci
        jsr     cell_enter
        bcc     :+
        cmp     #CE_MEM
        beq     :++
:       clc
        rts
:       sec
        rts

; a decimal number at lbuf + X -> A (capped at 9999), X past it
ln_dec: stz     sl_n
:       lda     lbuf,x
        and     #$00FF
        jsr     isdigit
        bcc     :+
        and     #$000F
        pha
        lda     sl_n
        cmp     #1000
        bcc     @m
        lda     #999
@m:     asl     a
        sta     sl_t
        asl     a
        asl     a
        adc     sl_t
        sta     sl_n
        pla
        clc
        adc     sl_n
        sta     sl_n
        inx
        bra     :-
:       lda     sl_n
        rts

; a format spec at lbuf + Y ("G", "0"-"4", then "T", "P") -> A = the format byte
fmt_parse:
        stz     sl_n
@l:     lda     lbuf,y
        and     #$00FF
        beq     @out
        and     #$00DF                  ; (digits lose $20: '0' $30 -> $10)
        cmp     #$10
        bcc     :+
        cmp     #$15
        bcs     :+
        sec                             ; '0'-'4' -> 1-5
        sbc     #$0F
        sta     sl_t
        lda     sl_n
        and     #$FFF0
        ora     sl_t
        sta     sl_n
        bra     @n
:       cmp     #'T'
        bne     :+
        lda     #FM_THOU
        tsb     sl_n
        bra     @n
:       cmp     #'P'
        bne     @n
        lda     #FM_PCT
        tsb     sl_n
@n:     iny
        bra     @l
@out:   lda     sl_n
        rts

; write the sheet to fpath -> C set: failed, A = the error
sht_save:
        ptr     fpath
        lda     #O_CREATE
        sys     SYS_OPEN
        bcc     :+
        rts
:       sta     fh
        jsr     wr_init
        ldx     #.loword(s_hdr)
        jsr     wr_str
        stz     sv_c                    ; widths and formats
@cl:    lda     sv_c
        asl     a
        tax
        lda     colw,x
        cmp     #DEFW
        beq     @fm
        pha
        lda     #'W'
        jsr     sv_col
        pla
        ldx     #0
        jsr     put_decx
        jsr     sv_nm
@fm:    ldx     sv_c
        lda     colfmt,x
        and     #$00FF
        beq     @nc
        pha
        lda     #'F'
        jsr     sv_col
        pla
        jsr     fmt_spec
        jsr     sv_nm
@nc:    inc     sv_c
        lda     sv_c
        cmp     #NCOL
        bcc     @cl
        stz     sv_r                    ; the cells, row by row
@row:   lda     sv_r
        cmp     maxrow
        bcs     @end
        stz     sv_c
@cell:  lda     sv_c
        xba
        asl     a
        asl     a
        ora     sv_r
        sta     sv_ci
        tay
        lda     [ixb],y
        and     #$00FF
        beq     @nx
        lda     sv_ci
        jsr     ci_name
        ldx     #.loword(nmbuf)
        jsr     wr_str
        lda     #' '
        jsr     wr_byte
        lda     sv_ci
        jsr     cell_src
        ldx     #.loword(tbuf)
        jsr     wr_str
        lda     #10
        jsr     wr_byte
@nx:    inc     sv_c
        lda     sv_c
        cmp     #NCOL
        bcc     @cell
        inc     sv_r
        bra     @row
@end:   jmp     wr_end

; "W x " / "F x " for column sv_c
sv_col: jsr     wr_byte
        lda     #' '
        jsr     wr_byte
        lda     sv_c
        clc
        adc     #'A'
        jsr     wr_byte
        lda     #' '
        jmp     wr_byte
; nmbuf and a line end
sv_nm:  ldx     #.loword(nmbuf)
        jsr     wr_str
        lda     #10
        jmp     wr_byte
; format A -> its spec in nmbuf ("2T")
fmt_spec:
        sta     sl_n
        ldx     #0
        and     #$0F
        bne     :+
        lda     #'G'
        bra     :++
:       clc
        adc     #'0' - 1
:       sta     nmbuf,x
        inx
        lda     sl_n
        and     #FM_THOU
        beq     :+
        lda     #'T'
        sta     nmbuf,x
        inx
:       lda     sl_n
        and     #FM_PCT
        beq     :+
        lda     #'P'
        sta     nmbuf,x
        inx
:       stz     nmbuf,x
        rts

; the end of a write: flush, close -> C set: A = the error
wr_end: jsr     wr_flush
        lda     fh
        sys     SYS_CLOSE
        bcc     :+
        ldx     wr_err
        bne     :+
        sta     wr_err
:       lda     wr_err
        beq     :+
        sec
        rts
:       clc
        rts

; ---------------------------------------------------------------- CSV and TSV
; read fpath as CSV into an empty sheet -> C set: A = the error
csv_load:
        ptr     fpath
        lda     #O_READ
        sys     SYS_OPEN
        bcc     :+
        rts
:       sta     fh
        jsr     rd_init
        lda     #','
        sta     dl_sep
        stz     dl_c0
        stz     dl_r0
        stz     dl_clr
        lda     #.loword(rd_byte)
        sta     dl_get
        jsr     dl_read
        lda     fh
        sys     SYS_CLOSE
        lda     rd_err
        beq     :+
        sec
        rts
:       clc
        rts

; delimited text (separator dl_sep, bytes from the routine dl_get) into the cells from
; dl_c0, dl_r0 (0, 0 for a file). Quotes: a field starting with " runs to the closing
; quote ("" is one quote inside). C set at the end: out of memory.
dl_read:
        stz     dl_c
        stz     dl_r
        stz     dl_n
        stz     dl_q
        stz     dl_any
        lda     #1
        sta     ce_force
@l:     jsr     @get
        bcs     @eof
        ldx     dl_q
        beq     @plain
        cmp     #'"'                    ; in quotes
        bne     @add
        jsr     @get                    ; "" -> a quote, " -> the end of the quotes
        bcs     @eof
        cmp     #'"'
        beq     @add
        stz     dl_q
        bra     @plain
@plain: cmp     #13
        beq     @l
        cmp     #10
        beq     @eol
        cmp     dl_sep
        beq     @sep
        cmp     #'"'
        bne     @add
        ldx     dl_n                    ; a quote opens only at a field's start
        bne     @add
        inc     dl_q
        bra     @l
@add:   ldx     dl_n
        cpx     #TXTMAX
        bcs     :+
        sep     #$20
        .a8
        sta     tbuf,x
        rep     #$20
        .a16
        inc     dl_n
:       inc     dl_any
        bra     @l
@sep:   jsr     @field
        bcs     @mem
        inc     dl_c
        bra     @l
@eol:   jsr     @field
        bcs     @mem
        stz     dl_c
        inc     dl_r
        stz     dl_any
        bra     @l
@eof:   lda     dl_any                  ; a last line without its end
        ora     dl_c
        beq     @done
        jsr     @field
        bcs     @mem
@done:  stz     ce_force
        clc
        rts
@mem:   stz     ce_force
        sec
        rts
@get:   ldx     #0
        jmp     (dl_get,x)
; the field in tbuf (dl_n) -> its cell (not past Z, 999)
@field: ldx     dl_n
        stz     tbuf,x
        stz     dl_n
        lda     dl_c
        clc
        adc     dl_c0
        cmp     #NCOL
        bcs     @fo
        sta     dl_t
        lda     dl_r
        clc
        adc     dl_r0
        cmp     #NROW
        bcs     @fo
        sta     c_ci
        lda     dl_t
        xba
        asl     a
        asl     a
        ora     c_ci
        sta     c_ci
        lda     tbuf
        and     #$00FF
        bne     :+
        lda     dl_clr                  ; an empty field: (paste) clears the cell
        beq     @fo
        lda     c_ci
        jsr     cell_clear
        bra     @fo
:       jsr     cell_enter
        bcc     @fo
        cmp     #CE_MEM
        bne     @fo
        sec
        rts
@fo:    clc
        rts

; write the sheet's values as CSV to fpath -> C set: A = the error
csv_save:
        ptr     fpath
        lda     #O_CREATE
        sys     SYS_OPEN
        bcc     :+
        rts
:       sta     fh
        jsr     wr_init
        jsr     used                    ; the used area: us_c columns, us_r rows
        stz     sv_r
@row:   lda     sv_r
        cmp     us_r
        bcs     @end
        stz     sv_c
@cell:  lda     sv_c
        beq     :+
        lda     #','
        jsr     wr_byte
:       lda     sv_c
        xba
        asl     a
        asl     a
        ora     sv_r
        ldx     #0                      ; general format
        jsr     cell_disp
        lda     dkind
        cmp     #2
        bne     @plain
        jsr     csv_quote
        bra     @nx
@plain: ldx     #.loword(fbuf)
        jsr     wr_str
@nx:    inc     sv_c
        lda     sv_c
        cmp     us_c
        bcc     @cell
        lda     #13
        jsr     wr_byte
        lda     #10
        jsr     wr_byte
        inc     sv_r
        bra     @row
@end:   jmp     wr_end

; (0.23) File > Print: the used area as text columns, a print job "/PRN:Sheet" -> C set:
; A = the error. Each cell as shown (its column's format; formulas as their results,
; errors by name), not cut to the column's width; each column as wide as its widest value
; (a text with nothing right of it in its row does not count: it runs on, as on the
; screen), two spaces between columns, numbers and errors right-aligned, text left-aligned; no
; column letters, no row numbers; a column empty in the used area is left out; rows in
; the used area that are empty are blank lines; no spaces at a line's end; LF line ends.
prt_save:
        ptr     t_prn
        lda     #O_CREATE
        sys     SYS_OPEN
        bcc     :+
        rts
:       sta     fh
        jsr     wr_init
        jsr     used
        stz     sv_c                    ; the columns' widths
@wc:    lda     sv_c
        cmp     us_c
        bcs     @rows
        asl     a
        tax
        stz     pr_w,x
        stz     sv_r
@wr:    lda     sv_r
        cmp     us_r
        bcs     @wn
        jsr     pr_disp
        lda     dkind                   ; (a text with nothing right of it in its row
        cmp     #2                      ; runs on: it does not widen its column)
        bne     :+
        jsr     pr_last
        bcs     :++
:       lda     sv_c
        asl     a
        tax
        lda     pr_n
        cmp     pr_w,x
        bcc     :+
        sta     pr_w,x
:       inc     sv_r
        bra     @wr
@wn:    inc     sv_c
        bra     @wc
@rows:  stz     sv_r
@row:   lda     sv_r
        cmp     us_r
        jcs     @end
        stz     pr_sp
        stz     pr_any
        stz     sv_c
@cell:  lda     sv_c
        cmp     us_c
        bcs     @eol
        asl     a
        tax
        lda     pr_w,x
        beq     @cn
        lda     pr_any                  ; two spaces after the column before
        beq     :+
        inc     pr_sp
        inc     pr_sp
:       sta     pr_any                  ; (A: not 0 from here on)
        inc     pr_any
        jsr     pr_disp
        lda     sv_c
        asl     a
        tax
        lda     pr_w,x                  ; the padding: before a number, after a text
        sec
        sbc     pr_n
        bcs     :+
        lda     #0
:       ldx     dalign
        beq     :+
        clc
        adc     pr_sp
        sta     pr_sp
        lda     #0
:       pha
        ldx     #0
:       cpx     pr_n
        bcs     :++
        lda     fbuf,x
        and     #$00FF
        cmp     #' '                    ; (a line break in a text: a space)
        bcs     :+
        lda     #' '
:       jsr     pr_char
        inx
        bra     :--
:       pla
        clc
        adc     pr_sp
        sta     pr_sp
@cn:    inc     sv_c
        bra     @cell
@eol:   lda     #10
        jsr     wr_byte
        inc     sv_r
        brl     @row
@end:   jmp     wr_end

; is cell sv_c, sv_r the last one in its row (the cells right of it empty)? -> C set
pr_last:
        lda     sv_c
@l:     inc     a
        cmp     us_c
        bcs     @out
        pha
        xba
        asl     a
        asl     a
        ora     sv_r
        jsr     cell_get
        pla
        bcs     @l
@out:   rts

; cell sv_c, sv_r as shown -> fbuf, pr_n = its length, dalign
pr_disp:
        ldx     sv_c
        lda     colfmt,x
        and     #$00FF
        tax
        lda     sv_c
        xba
        asl     a
        asl     a
        ora     sv_r
        jsr     cell_disp
        sta     pr_n
        rts

; byte A after the spaces waiting (pr_sp) (X kept)
pr_char:
        phx
        pha
:       lda     pr_sp
        beq     :+
        dec     pr_sp
        lda     #' '
        jsr     wr_byte
        bra     :-
:       pla
        jsr     wr_byte
        plx
        rts

; the text in fbuf as a CSV field: quoted if it holds a comma, a quote, a line break or
; spaces at its ends
csv_quote:
        ldx     #0
        stz     cq_q
:       lda     fbuf,x
        and     #$00FF
        beq     :++
        cmp     #','
        beq     :+
        cmp     #'"'
        beq     :+
        cmp     #10
        beq     :+
        cmp     #13
        beq     :+
        inx
        bra     :-
:       inc     cq_q
:       lda     fbuf                    ; leading or trailing space
        and     #$00FF
        cmp     #' '
        bne     :+
        inc     cq_q
:       cpx     #0
        beq     :+
        lda     fbuf-1,x
        and     #$00FF
        cmp     #' '
        bne     :+
        inc     cq_q
:       lda     cq_q
        bne     :+
        ldx     #.loword(fbuf)
        jmp     wr_str
:       lda     #'"'
        jsr     wr_byte
        ldx     #0
@l:     lda     fbuf,x
        and     #$00FF
        beq     @e
        phx
        pha
        jsr     wr_byte
        pla
        cmp     #'"'
        bne     :+
        jsr     wr_byte
:       plx
        inx
        bra     @l
@e:     lda     #'"'
        jmp     wr_byte

; the used area: us_c = the last column with a cell + 1, us_r = the last row + 1
used:   stz     us_c
        stz     us_r
        stz     sv_ci
@l:     lda     sv_ci
        and     #CPC - 1
        cmp     maxrow
        bcs     @col
        lda     sv_ci
        tay
        lda     [ixb],y
        and     #$00FF
        beq     @n
        lda     sv_ci
        and     #CPC - 1
        inc     a
        cmp     us_r
        bcc     :+
        sta     us_r
:       lda     sv_ci
        xba
        lsr     a
        lsr     a
        and     #$003F
        inc     a
        cmp     us_c
        bcc     @n
        sta     us_c
@n:     inc     sv_ci
        bra     @l
@col:   lda     sv_ci
        and     #$FFFF ^ (CPC - 1)
        clc
        adc     #CPC
        sta     sv_ci
        cmp     #NCOL * CPC
        bcc     @l
        rts

        .segment "RODATA"
s_hdr:  .byte   "SHEET 1", 10, 0
p10d:   .word   1, 10, 100, 1000, 10000

        .segment "BSS"
dirty:  .res    2                       ; cells changed since the last recalculation
ce_force: .res  2
tn_neg: .res    2
cs_n:   .res    2
cd_f:   .res    2
dalign: .res    2
dink:   .res    2
dkind:  .res    2
nmbuf:  .res    16
pd_x:   .res    2
pd_buf: .res    10
fh:     .res    2
rblk:   .res    6
rd_pos: .res    2
rd_n:   .res    2
rd_eof: .res    2
rd_err: .res    2
ln_n:   .res    2
ln_any: .res    2
lbuf:   .res    LMAX + 4
wr_n:   .res    2
wr_err: .res    2
sl_c:   .res    2
sl_col: .res    2
sl_row: .res    2
sl_n:   .res    2
sl_t:   .res    2
sv_c:   .res    2
sv_r:   .res    2
sv_ci:  .res    2
us_c:   .res    2
us_r:   .res    2
dl_sep: .res    2
dl_get: .res    2
dl_c:   .res    2
dl_r:   .res    2
dl_c0:  .res    2
dl_r0:  .res    2
dl_n:   .res    2
dl_q:   .res    2
dl_any: .res    2
dl_t:   .res    2
dl_clr: .res    2
cq_q:   .res    2
pr_w:   .res    NCOL * 2                ; (0.23) prt_save: the columns' widths, a cell's
pr_n:   .res    2                       ;   length, spaces waiting, a column written
pr_sp:  .res    2
pr_any: .res    2

        .segment "ZEROPAGE"
sb:     .res    4                       ; the scratch bank (file data)

        .segment "CODE"
