; bas_tok.s - the tokenizer (a typed or loaded line -> tokens), LIST (tokens -> text).
;
; A line is tokenized once, when it is entered (or loaded). Tokens:
;   $00             the end of the line
;   $01-$7F         themselves: operators and punctuation ( ) , ; : = < > + - * / ^
;   $80-$AF         statements, $B0-$BF other keywords, $C0-$DF functions (kwtab)
;   TK_NVAR off16   a number variable: off = its slot's offset in VB (slot * 8)
;   TK_SVAR off16   a string variable;  TK_NARR / TK_SARR off16: arrays (then "(")
;   TK_IVAR off16   an integer variable (A%); TK_IARR: its arrays
;   TK_INT  i32     a number (TK_BYTE u8 for 0-255; TK_HEX i32 when typed in hex)
;   TK_FLT  ft16 lo16 hi16 len16   a number that is not a 32-bit integer (2.5, 1E20)
;   TK_STR  n, ..   a string literal of n bytes
;   TK_LINE n16 idx16 gen16   a line number after GOTO, GOSUB, THEN, ELSE, RESTORE, RUN:
;                   idx is the line's index, valid while gen = pgen (a lookup cache)
;   REM, ' and DATA keep the rest of the line (DATA: of the statement) as typed.
; Variables are resolved to their slot here, so running a program never looks up a name.
; Keywords are whole words: FORI=1TO9 is not FOR I=1 TO 9. Names: a letter, then letters,
; digits and _ (32 at most), $ for strings, % for integers, all significant; case is
; ignored.

        .segment "CODE"
        .a16
        .i16
TK_LET  = $80
TK_PRINT = $81
TK_INPUT = $82
TK_IF   = $83
TK_GOTO = $84
TK_GOSUB = $85
TK_RETURN = $86
TK_ON   = $87
TK_FOR  = $88
TK_NEXT = $89
TK_WHILE = $8A
TK_WEND = $8B
TK_DIM  = $8C
TK_DATA = $8D
TK_READ = $8E
TK_RESTORE = $8F
TK_REM  = $90
TK_APOS = $91
TK_END  = $92
TK_STOP = $93
TK_CONT = $94
TK_RUN  = $95
TK_LIST = $96
TK_NEW  = $97
TK_CLR  = $98
TK_LOAD = $99
TK_SAVE = $9A
TK_POKE = $9B
TK_CLS  = $9C
TK_PAUSE = $9D
TK_RANDOMIZE = $9E
TK_SCREEN = $9F
TK_COLOR = $A0
TK_PLOT = $A1
TK_LINEST = $A2
TK_RECT = $A3
TK_FRECT = $A4
TK_CIRCLE = $A5
TK_TEXT = $A6
TK_PALETTE = $A7
TK_GCLS = $A8
TK_SOUND = $A9
TK_BEEP = $AA
TK_DIR  = $AB
TK_DEG  = $AC
TK_RAD  = $AD
TK_VSYNC = $AE                          ; (1.2)
TK_THEN = $B0
TK_ELSE = $B1
TK_TO   = $B2
TK_STEP = $B3
TK_AND  = $B4
TK_OR   = $B5
TK_XOR  = $B6
TK_NOT  = $B7
TK_MOD  = $B8
TK_LE   = $B9
TK_GE   = $BA
TK_NE   = $BB
TK_OFF  = $BC                           ; (2.0)
TK_ABS  = $C0
TK_SGN  = $C1
TK_RND  = $C2
TK_LEN  = $C3
TK_LEFT = $C4
TK_RIGHT = $C5
TK_MID  = $C6
TK_CHR  = $C7
TK_ASC  = $C8
TK_STR  = $C9
TK_VAL  = $CA
TK_HEXS = $CB
TK_INSTR = $CC
TK_PEEK = $CD
TK_TIME = $CE
TK_INKEY = $CF
TK_MOUSEX = $D0
TK_MOUSEY = $D1
TK_MOUSEB = $D2
TK_POINT = $D3
TK_TAB  = $D4
TK_SPC  = $D5
TK_FRE  = $D6
TK_MIN  = $D7
TK_MAX  = $D8
TK_SQR  = $D9
TK_SIN  = $DA
TK_COS  = $DB
TK_TAN  = $DC
TK_ATN  = $DD
TK_EXP  = $DE
TK_LOG  = $DF
TK_LOG10 = $E0
TK_INTF = $E1
TK_FIX  = $E2
TK_ROUND = $E3
TK_PI   = $E4
TK_STICK = $E5                          ; (1.2)
TK_STRIG = $E6
TK_HIT  = $E7                           ; (2.0)
TK_FRAME = $E8
TK_NOTE = $E9
TK_LASTKW = $E9
TK_NVAR = $F0
TK_SVAR = $F1
TK_NARR = $F2
TK_SARR = $F3
TK_INT  = $F4
TK_BYTE = $F5
TK_STRL = $F6
TK_LINE = $F7
TK_HEX  = $F8
TK_FLT  = $F9
TK_IVAR = $FA
TK_IARR = $FB
TK_X    = $FC                           ; (2.0) an extended statement: TK_X, then its X_*
X_SPRITE = 0
X_SHAPE = 1
X_GET   = 2
X_PUT   = 3
X_COPY  = 4
X_WAVE  = 5
X_PLAY  = 6
X_SCROLL = 7
X_PANEL = 8
X_RASTER = 9
X_LPRINT = 10                           ; (Horizon 0.23)
X_LLIST = 11
X_N     = 12

TMAX    = 500                           ; tokens of one line
LBMAX   = 1000                          ; LIST's text of one line

; ---------------------------------------------------------------- tokenize
; ibuf -> tbuf (tlen bytes including the final 0). tline = 1 and tlnum = the number when
; the line starts with one. Errors: E_LONG, E_NUM, E_NAME, E_VARS.
tokenize:
        stz     tline
        ldx     #0
        jsr     tk_skipsp
        jsr     tk_isdigit
        bcc     @body
        jsr     tk_dec
        jcs     @badln
        lda     z:t1
        jne     @badln
        lda     z:t0
        sta     tlnum
        lda     #1
        sta     tline
@body:  ldy     #0
        stz     wantln
@loop:  jsr     tk_skipsp
        lda     ibuf,x
        and     #$00FF
        jeq     @end
        cmp     #'"'
        jeq     @str
        jsr     tk_isdigit
        jcs     @num
        cmp     #'.'                    ; .5
        bne     :+
        lda     ibuf+1,x
        and     #$00FF
        jsr     tk_isdigit
        lda     #'.'
        jcs     @pnum
:       cmp     #'$'
        bne     :+
        lda     ibuf+1,x
        jsr     tk_ishex
        jcs     @hex1
        lda     #'$'
        brl     @char
:       cmp     #'&'
        bne     :+
        lda     ibuf+1,x
        and     #$00DF
        cmp     #'H'
        bne     @amp
        lda     ibuf+2,x
        jsr     tk_ishex
        bcc     @amp
        inx
        jmp     @hex1
@amp:   lda     #'&'
        brl     @char
:       jsr     tk_isalpha
        jcs     @word
        cmp     #$27
        jeq     @apos
        cmp     #'?'
        bne     :+
        lda     #TK_PRINT
        jsr     tk_emit
        inx
        stz     wantln
        brl     @loop
:       cmp     #'<'
        bne     :++
        lda     ibuf+1,x
        and     #$00FF
        cmp     #'='
        bne     :+
        inx
        lda     #TK_LE
        bra     @op2
:       cmp     #'>'
        bne     @lt
        inx
        lda     #TK_NE
        bra     @op2
@lt:    lda     #'<'
        bra     @char
:       cmp     #'>'
        bne     :++
        lda     ibuf+1,x
        and     #$00FF
        cmp     #'='
        bne     :+
        inx
        lda     #TK_GE
        bra     @op2
:       lda     #'>'
        bra     @char
:       cmp     #'='
        bne     :+++
        lda     ibuf+1,x
        and     #$00FF
        cmp     #'<'
        bne     :+
        inx
        lda     #TK_LE
        bra     @op2
:       cmp     #'>'
        bne     :+
        inx
        lda     #TK_GE
        bra     @op2
:       lda     #'='
        bra     @char
:       cmp     #','
        bne     :+
        jsr     tk_emit                 ; (a list of line numbers: ON .. GOTO a, b)
        inx
        jmp     @loop
:       cmp     #127
        bcs     :+
        cmp     #' '
        bcs     @char
:       inx                             ; control characters are dropped
        jmp     @loop
@op2:
@char:  jsr     tk_emit
        inx
        stz     wantln
        jmp     @loop
@end:   lda     #0
        jsr     tk_emit
        sty     tlen
        rts
@badln: err     E_NUM

; a string literal
@str:   inx
        lda     #TK_STRL
        jsr     tk_emit
        sty     z:t2                    ; where the length goes
        jsr     tk_emit
:       lda     ibuf,x
        and     #$00FF
        beq     :++
        inx
        cmp     #'"'
        beq     :++
        jsr     tk_emit
        bra     :-
:
:       tya
        clc
        sbc     z:t2                    ; length = Y - t2 - 1
        cmp     #256
        bcc     :+
        err     E_LONG
:       phx
        ldx     z:t2
        a8
        sta     tbuf,x
        a16
        plx
        stz     wantln
        jmp     @loop

; a decimal number: a line number after GOTO and the like, or a value
@num:   lda     wantln
        beq     @pnum
        jsr     tk_dec
        jcs     @big
        lda     z:t1
        jne     @big
        lda     #TK_LINE
        jsr     tk_emit
        lda     z:t0
        jsr     tk_emit
        xba
        jsr     tk_emit
        lda     #0
        jsr     tk_emit
        jsr     tk_emit
        jsr     tk_emit
        jsr     tk_emit
        jmp     @loop
@pnum:  phy                             ; a value: parse_num on the line
        stx     z:t2
        txa
        clc
        adc     #.loword(ibuf)
        sta     z:bp
        lda     codebk
        sta     z:bp+2
        lda     #255
        jsr     parse_num
        bcs     @big
        tya
        clc
        adc     z:t2
        tax
        ply
        lda     ft
        bne     @flt
        lda     flo
        sta     z:t0
        lda     fhi
        sta     z:t1
@val:   lda     z:t1
        bne     @i32
        lda     z:t0
        cmp     #256
        bcs     @i32
        lda     #TK_BYTE
        jsr     tk_emit
        lda     z:t0
        jsr     tk_emit
        jmp     @loop
@i32:   lda     #TK_INT
@put32: jsr     tk_emit
        lda     z:t0
        jsr     tk_emit
        xba
        jsr     tk_emit
        lda     z:t1
        jsr     tk_emit
        xba
        jsr     tk_emit
        stz     wantln
        jmp     @loop
@big:   err     E_NUM
@flt:   lda     #TK_FLT                 ; {ft, flo, fhi, flen}
        jsr     tk_emit
        lda     ft
        jsr     @w16
        lda     flo
        jsr     @w16
        lda     fhi
        jsr     @w16
        lda     flen
        jsr     @w16
        stz     wantln
        jmp     @loop
@w16:   jsr     tk_emit
        xba
        jmp     tk_emit
; hexadecimal: $1F or &H1F (X at the '$' / 'H')
@hex1:  inx
        stz     z:t0
        stz     z:t1
        stz     z:t2                    ; digits
:       lda     ibuf,x
        jsr     tk_ishex
        bcc     :+
        sta     z:t3
        lda     z:t2
        cmp     #8
        bcs     @big
        inc     z:t2
        phx
        ldx     #4
@sh:    asl     z:t0
        rol     z:t1
        dex
        bne     @sh
        plx
        lda     z:t3
        ora     z:t0
        sta     z:t0
        inx
        bra     :-
:       lda     #TK_HEX
        bra     @put32

; ' and REM: the rest of the line as typed
@apos:  inx
        lda     #TK_APOS
        bra     :+
@rem:   lda     #TK_REM
:       jsr     tk_emit
:       lda     ibuf,x
        and     #$00FF
        jeq     @end
        jsr     tk_emit
        inx
        bra     :-

; a word: a keyword or a variable
@word:  phy
        ldy     #0
:       lda     ibuf,x
        and     #$00FF
        jsr     tk_isalnum
        bcc     :+
        cpy     #32
        jcs     @long
        jsr     tk_upper
        sta     nbuf,y
        iny
        inx
        bra     :-
:       stz     z:t5                    ; t5 = 1: a string name
        stz     z:t7                    ; t7 = 1: an integer name
        cmp     #'$'
        bne     :+
        sta     nbuf,y
        iny
        inx
        inc     z:t5
        bra     :++
:       cmp     #'%'
        bne     :+
        sta     nbuf,y
        iny
        inx
        inc     z:t7
:       sty     nlen
        lda     #0
        sta     nbuf,y
        ply
        jsr     kw_find
        bcc     @var
        cmp     #$0100                  ; (2.0) an extended statement: TK_X, X_*
        bcc     :+
        pha
        lda     #TK_X
        jsr     tk_emit
        pla
        jsr     tk_emit
        stz     wantln
        jmp     @loop
:       cmp     #TK_REM
        beq     @rem
        cmp     #TK_DATA
        jeq     @data
        pha
        jsr     tk_emit
        pla
        stz     wantln
        cmp     #TK_RUN                 ; RUN, LOAD, SAVE, DIR: a file name without quotes?
        beq     @fn
        cmp     #TK_LOAD
        beq     @fn
        cmp     #TK_SAVE
        beq     @fn
        cmp     #TK_DIR
        bne     @kw
@fn:    pha
        jsr     tk_fname
        pla
        bcc     @kw
        jmp     @loop
@kw:    cmp     #TK_GOTO
        beq     @want
        cmp     #TK_GOSUB
        beq     @want
        cmp     #TK_THEN
        beq     @want
        cmp     #TK_ELSE
        beq     @want
        cmp     #TK_RESTORE
        beq     @want
        cmp     #TK_RUN
        bne     :+
@want:  inc     wantln
:       jmp     @loop
@long:  err     E_NAME
@var:   lda     z:t5                    ; kind: 0 number, 1 string, + 2 array
        sta     z:t6
        phx
:       lda     ibuf,x
        and     #$00FF
        cmp     #' '
        bne     :+
        inx
        bra     :-
:       plx
        cmp     #'('
        bne     :+
        inc     z:t6
        inc     z:t6
:       phx
        phy
        lda     z:t6
        jsr     sym_find                ; -> A = slot offset
        ply
        plx
        sta     z:t0
        lda     z:t7                    ; A%: TK_IVAR, A%(: TK_IARR
        beq     :+
        lda     z:t6
        lsr     a
        clc
        adc     #TK_IVAR
        bra     :++
:       lda     z:t6
        clc
        adc     #TK_NVAR
:       jsr     tk_emit
        lda     z:t0
        jsr     tk_emit
        xba
        jsr     tk_emit
        stz     wantln
        jmp     @loop
; DATA: the rest of the statement as typed (to a ':' outside quotes)
@data:  jsr     tk_emit
        stz     z:t2                    ; inside quotes
@dl:    lda     ibuf,x
        and     #$00FF
        jeq     @end
        cmp     #'"'
        bne     :+
        lda     z:t2
        eor     #1
        sta     z:t2
        lda     #'"'
        bra     @dput
:       cmp     #':'
        bne     @dput
        pha
        lda     z:t2
        bne     :+
        pla
        jmp     @loop
:       pla
@dput:  jsr     tk_emit
        inx
        bra     @dl

; A -> tbuf[Y++] (keeps A, X)
tk_emit:
        cpy     #TMAX
        bcs     :+
        pha
        a8
        sta     tbuf,y
        a16
        pla
        iny
        rts
:       err     E_LONG

; after RUN, LOAD, SAVE or DIR (A): an argument that cannot start a string expression
; (a quote, a parenthesis, a name ending in $) nor, after RUN, a line number, is a file
; name typed without quotes: it becomes a string literal of the text up to ':' or the end
; of the line, without trailing spaces (X past it) -> C set. C clear: X kept, nothing done.
tk_fname:
        sta     z:t4
        phx
        jsr     tk_skipsp
        lda     ibuf,x
        and     #$00FF
        beq     @no
        cmp     #':'
        beq     @no
        cmp     #'"'
        beq     @no
        cmp     #'('
        beq     @no
        cmp     #$27                    ; (a ' comment)
        beq     @no
        jsr     tk_isdigit
        bcc     :+
        lda     z:t4                    ; RUN 100: a line number
        cmp     #TK_RUN
        bne     @yes
@no:    plx
        clc
        rts
:       jsr     tk_isalpha
        bcc     @yes
        phx                             ; a name: followed by $, a string expression
:       inx
        lda     ibuf,x
        and     #$00FF
        jsr     tk_isalnum
        bcs     :-
        plx
        cmp     #'$'
        beq     @no
@yes:   stx     z:t3                    ; the start
:       lda     ibuf,x                  ; the end: ':' or the line's end
        and     #$00FF
        beq     :+
        cmp     #':'
        beq     :+
        inx
        bra     :-
:       stx     z:t2
:       dex                             ; without trailing spaces
        lda     ibuf,x
        and     #$00FF
        cmp     #' '
        beq     :-
        inx
        stx     z:t1
        txa
        sec
        sbc     z:t3
        cmp     #128
        bcc     :+
        err     E_LONG
:       pha
        lda     #TK_STRL
        jsr     tk_emit
        pla
        jsr     tk_emit
        ldx     z:t3
:       lda     ibuf,x
        jsr     tk_emit
        inx
        cpx     z:t1
        bcc     :-
        ldx     z:t2
        pla                             ; (the saved X)
        sec
        rts

tk_skipsp:
:       lda     ibuf,x
        and     #$00FF
        cmp     #' '
        beq     :+
        cmp     #9
        bne     :++
:       inx
        bra     :--
:       rts

; A (a character): C set if a digit (keeps A)
tk_isdigit:
        cmp     #'0'
        bcc     :+
        cmp     #'9' + 1
        bcs     :+
        sec
        rts
:       clc
        rts
tk_isalpha:
        pha
        and     #$00DF
        cmp     #'A'
        bcc     :+
        cmp     #'Z' + 1
        bcs     :+
        pla
        sec
        rts
:       pla
        clc
        rts
tk_isalnum:
        jsr     tk_isalpha
        bcs     :+
        jsr     tk_isdigit
        bcs     :+
        cmp     #'_'
        beq     :+
        clc
:       rts
tk_upper:
        cmp     #'a'
        bcc     :+
        cmp     #'z' + 1
        bcs     :+
        and     #$00DF
:       rts
; A = a character (16-bit read: low byte): C set if a hex digit, A = its value
tk_ishex:
        and     #$00FF
        jsr     tk_isdigit
        bcc     :+
        sbc     #'0'
        sec
        rts
:       and     #$00DF
        cmp     #'A'
        bcc     :+
        cmp     #'F' + 1
        bcs     :+
        sbc     #'A' - 10 - 1
        sec
        rts
:       clc
        rts

; a decimal number at ibuf, X -> t0, t1 (32-bit); C set if above 2147483647
tk_dec: stz     z:t0
        stz     z:t1
@l:     lda     ibuf,x
        and     #$00FF
        jsr     tk_isdigit
        bcc     @end
        sbc     #'0'
        sta     z:t3
        jsr     mul10                   ; t0:t1 * 10
        bcs     @ovf
        lda     z:t0
        clc
        adc     z:t3
        sta     z:t0
        lda     z:t1
        adc     #0
        sta     z:t1
        bmi     @ovf
        inx
        bra     @l
@end:   clc
        rts
@ovf:   inx                             ; (the rest of the digits)
        lda     ibuf,x
        and     #$00FF
        jsr     tk_isdigit
        bcs     @ovf
        sec
        rts

; t0:t1 = t0:t1 * 10 (unsigned) -> C set on overflow past 31 bits (keeps X, Y)
mul10:  lda     z:t0
        sta     z:t2
        lda     z:t1
        sta     z:t4
        asl     z:t0                    ; * 2
        rol     z:t1
        bcs     @ovf
        asl     z:t0                    ; * 4
        rol     z:t1
        bcs     @ovf
        lda     z:t0                    ; * 5
        clc
        adc     z:t2
        sta     z:t0
        lda     z:t1
        adc     z:t4
        sta     z:t1
        bcs     @ovf
        asl     z:t0                    ; * 10
        rol     z:t1
        bcs     @ovf
        bmi     @ovf
        clc
        rts
@ovf:   sec
        rts

; the name in nbuf (nlen) a keyword? -> C set, A = token
kw_find:
        phx
        phy
        lda     #TK_LET
        sta     z:t3
@l:     lda     z:t3
        sec
        sbc     #$80
        asl     a
        tax
        lda     kwtab,x                 ; (kwtab2 follows kwtab at $100: $80 entries on)
        sta     z:t4
        ldy     #0
:       lda     (t4),y
        and     #$00FF
        sta     z:t2
        lda     nbuf,y
        and     #$00FF
        cmp     z:t2
        bne     @next
        cmp     #0
        beq     @hit
        iny
        bra     :-
@next:  inc     z:t3
        lda     z:t3
        cmp     #TK_LASTKW + 1
        bcc     @l
        cmp     #$0100                  ; (2.0) then the extended ones: $100 + X_*
        bcs     :+
        lda     #$0100
        sta     z:t3
:       cmp     #$0100 + X_N
        bcc     @l
        ply
        plx
        clc
        rts
@hit:   ply
        plx
        lda     z:t3
        sec
        rts

; ---------------------------------------------------------------- LIST
; the line at [ap] (its record: number, size, tokens) -> lbuf (zero-terminated), A = length
detok:  stz     lbn
        stz     z:t6                    ; t6: a space owed (after a keyword)
        lda     [ap]
        sta     flo
        stz     fhi
        jsr     fmt_int
        jsr     lb_str
        lda     #' '
        jsr     lb_put
        lda     z:ap
        clc
        adc     #4
        sta     z:ap
@l:     lda     [ap]
        and     #$00FF
        jeq     @end
        inc     z:ap
        cmp     #$80
        jcs     @tok
        cmp     #':'                    ; a character
        beq     :+
        jsr     lb_owed
        bra     :++
:       stz     z:t6
:       jsr     lb_put
        bra     @l
@tok:   cmp     #TK_NVAR
        jcs     @spec
        sta     z:t5                    ; a keyword
        cmp     #TK_LE
        bcc     :+
        cmp     #TK_NE + 1
        bcs     :+
        stz     z:t6                    ; <= >= <>: as operators
        sec
        sbc     #$80
        asl     a
        tay
        lda     kwtab,y
        tay
        jsr     lb_strY
        bra     @l
:       stz     lxnm
@kwsp:  lda     z:t6                    ; a space before it?
        bne     :+
        jsr     lb_last
        ldx     z:t5                    ; (ELSE: always, unless at the line's start)
        cpx     #TK_ELSE
        bne     @nelse
        cmp     #' '
        bne     :+
@nelse:
        jsr     tk_isalnum
        bcs     :+
        cmp     #'$'
        beq     :+
        cmp     #'%'
        beq     :+
        cmp     #'"'
        beq     :+
        cmp     #')'
        bne     :++
:       lda     #' '
        jsr     lb_put
:       stz     z:t6
        ldy     lxnm                    ; (an extended statement's name)
        bne     :+
        lda     z:t5
        sec
        sbc     #$80
        asl     a
        tay
        lda     kwtab,y
        tay
:       jsr     lb_strY
        lda     z:t5
        cmp     #TK_REM
        beq     @raw
        cmp     #TK_APOS
        beq     @raw
        cmp     #TK_DATA
        beq     @rawd
        cmp     #TK_ABS
        bcs     :+
        inc     z:t6                    ; statements, operators: a space after
:       jmp     @l
@raw:   lda     [ap]                    ; the rest of the line
        and     #$00FF
        jeq     @end
        jsr     lb_put
        inc     z:ap
        bra     @raw
@rawd:  stz     z:t2                    ; DATA: to a ':' outside quotes
:       lda     [ap]
        and     #$00FF
        jeq     @end
        cmp     #':'
        bne     :+
        ldy     z:t2
        jeq     @l
:       cmp     #'"'
        bne     :+
        pha
        lda     z:t2
        eor     #1
        sta     z:t2
        pla
:       jsr     lb_put
        inc     z:ap
        bra     :---
@spec:  cmp     #TK_X                   ; (2.0) an extended statement
        bne     :+
        lda     [ap]
        inc     z:ap
        and     #$00FF
        clc
        adc     #$0100 - $80
        asl     a
        tay
        lda     kwtab,y
        sta     lxnm
        lda     #TK_LET
        sta     z:t5
        brl     @kwsp
:       pha
        jsr     lb_owed
        pla
        cmp     #TK_IVAR
        bcs     @var
        cmp     #TK_FLT
        beq     @flt
        cmp     #TK_INT
        bcs     :+
@var:   lda     [ap]                    ; a variable
        jsr     sym_name                ; -> X = its name in nbuf (with '$')
        txy
        ldx     lbn
        jsr     lb_strY
        lda     z:ap
        clc
        adc     #2
        sta     z:ap
        jmp     @l
:       cmp     #TK_STRL
        jeq     @lstr
        cmp     #TK_BYTE
        bne     :+
        lda     [ap]
        and     #$00FF
        sta     flo
        stz     fhi
        inc     z:ap
        bra     @num
:       cmp     #TK_LINE
        bne     :+
        lda     [ap]
        sta     flo
        stz     fhi
        lda     z:ap
        clc
        adc     #6
        sta     z:ap
        bra     @num
:       pha                             ; TK_INT, TK_HEX
        lda     [ap]
        sta     flo
        ldy     #2
        lda     [ap],y
        sta     fhi
        lda     z:ap
        clc
        adc     #4
        sta     z:ap
        pla
        cmp     #TK_HEX
        beq     @hex
@num:   ldx     lbn
        jsr     fmt_int
        jsr     lb_str
        jmp     @l
@flt:   lda     [ap]                    ; a float: 12 digits
        sta     ft
        ldy     #2
        lda     [ap],y
        sta     flo
        ldy     #4
        lda     [ap],y
        sta     fhi
        ldy     #6
        lda     [ap],y
        sta     flen
        lda     z:ap
        clc
        adc     #8
        sta     z:ap
        lda     #12
        jsr     fp_fmt
        jsr     lb_str
        jmp     @l
@hex:   ldx     lbn
        lda     #'$'
        jsr     lb_put
        jsr     fmt_hex
        jsr     lb_str
        jmp     @l
@lstr:  lda     #'"'
        jsr     lb_put
        lda     [ap]
        and     #$00FF
        sta     z:t2
        inc     z:ap
:       lda     z:t2
        beq     :+
        lda     [ap]
        and     #$00FF
        jsr     lb_put
        inc     z:ap
        dec     z:t2
        bra     :-
:       lda     #'"'
        jsr     lb_put
        jmp     @l
@end:   ldx     lbn
        stz     lbuf,x
        txa
        rts

; lbuf helpers: X = lbn kept in step. lb_put A; lb_str X = string (from fmt_*);
; lb_strY Y = string; lb_owed: the owed space; lb_last: the last character -> A
lb_put: ldx     lbn
        cpx     #LBMAX
        bcs     :+
        a8
        sta     lbuf,x
        a16
        inx
        stx     lbn
:       rts
lb_str: txy
lb_strY:
:       lda     a:0,y
        and     #$00FF
        beq     :+
        phy
        jsr     lb_put
        ply
        iny
        bra     :-
:       rts
lb_owed:
        pha
        lda     z:t6
        beq     :+
        stz     z:t6
        lda     #' '
        jsr     lb_put
:       pla
        rts
lb_last:
        ldx     lbn
        lda     lbuf-1,x
        and     #$00FF
        rts

        .segment "RODATA"
kwtab:  .addr   k_let, k_print, k_input, k_if, k_goto, k_gosub, k_return, k_on
        .addr   k_for, k_next, k_while, k_wend, k_dim, k_data, k_read, k_restore
        .addr   k_rem, k_apos, k_end, k_stop, k_cont, k_run, k_list, k_new
        .addr   k_clr, k_load, k_save, k_poke, k_cls, k_pause, k_randomize, k_screen
        .addr   k_color, k_plot, k_line, k_rect, k_frect, k_circle, k_text, k_palette
        .addr   k_gcls, k_sound, k_beep, k_dir, k_deg, k_rad, k_vsync, k_none
        .addr   k_then, k_else, k_to, k_step, k_and, k_or, k_xor, k_not
        .addr   k_mod, k_le, k_ge, k_ne, k_off, k_none, k_none, k_none
        .addr   k_abs, k_sgn, k_rnd, k_len, k_left, k_right, k_mid, k_chr
        .addr   k_asc, k_str, k_val, k_hex, k_instr, k_peek, k_time, k_inkey
        .addr   k_mousex, k_mousey, k_mouseb, k_point, k_tab, k_spc, k_fre, k_min
        .addr   k_max, k_sqr, k_sin, k_cos, k_tan, k_atn, k_exp, k_log
        .addr   k_log10, k_int, k_fix, k_round, k_pi, k_stick, k_strig, k_hit
        .addr   k_frame, k_note, k_none, k_none, k_none, k_none, k_none, k_none   ; $E8
        .repeat 16
        .addr   k_none                                                          ; $F0
        .endrepeat
kwtab2: .addr   k_sprite, k_shape, k_get, k_put, k_copy, k_wave, k_play, k_scroll ; $100
        .addr   k_panel, k_raster, k_lprint, k_llist
k_off:  .byte   "OFF", 0
k_hit:  .byte   "HIT", 0
k_frame: .byte  "FRAME", 0
k_note: .byte   "NOTE", 0
k_sprite: .byte "SPRITE", 0
k_shape: .byte  "SHAPE", 0
k_get:  .byte   "GET", 0
k_put:  .byte   "PUT", 0
k_copy: .byte   "COPY", 0
k_wave: .byte   "WAVE", 0
k_play: .byte   "PLAY", 0
k_scroll: .byte "SCROLL", 0
k_panel: .byte  "PANEL", 0
k_raster: .byte "RASTER", 0
k_lprint: .byte "LPRINT", 0
k_llist: .byte  "LLIST", 0
k_let:  .byte   "LET", 0
k_print: .byte  "PRINT", 0
k_input: .byte  "INPUT", 0
k_if:   .byte   "IF", 0
k_goto: .byte   "GOTO", 0
k_gosub: .byte  "GOSUB", 0
k_return: .byte "RETURN", 0
k_on:   .byte   "ON", 0
k_for:  .byte   "FOR", 0
k_next: .byte   "NEXT", 0
k_while: .byte  "WHILE", 0
k_wend: .byte   "WEND", 0
k_dim:  .byte   "DIM", 0
k_data: .byte   "DATA", 0
k_read: .byte   "READ", 0
k_restore: .byte "RESTORE", 0
k_rem:  .byte   "REM", 0
k_apos: .byte   "'", 0
k_end:  .byte   "END", 0
k_stop: .byte   "STOP", 0
k_cont: .byte   "CONT", 0
k_run:  .byte   "RUN", 0
k_list: .byte   "LIST", 0
k_new:  .byte   "NEW", 0
k_clr:  .byte   "CLR", 0
k_load: .byte   "LOAD", 0
k_save: .byte   "SAVE", 0
k_poke: .byte   "POKE", 0
k_cls:  .byte   "CLS", 0
k_pause: .byte  "PAUSE", 0
k_randomize: .byte "RANDOMIZE", 0
k_screen: .byte "SCREEN", 0
k_color: .byte  "COLOR", 0
k_plot: .byte   "PLOT", 0
k_line: .byte   "LINE", 0
k_rect: .byte   "RECT", 0
k_frect: .byte  "FRECT", 0
k_circle: .byte "CIRCLE", 0
k_text: .byte   "TEXT", 0
k_palette: .byte "PALETTE", 0
k_gcls: .byte   "GCLS", 0
k_sound: .byte  "SOUND", 0
k_beep: .byte   "BEEP", 0
k_dir:  .byte   "DIR", 0
k_none: .byte   0
k_then: .byte   "THEN", 0
k_else: .byte   "ELSE", 0
k_to:   .byte   "TO", 0
k_step: .byte   "STEP", 0
k_and:  .byte   "AND", 0
k_or:   .byte   "OR", 0
k_xor:  .byte   "XOR", 0
k_not:  .byte   "NOT", 0
k_mod:  .byte   "MOD", 0
k_le:   .byte   "<=", 0
k_ge:   .byte   ">=", 0
k_ne:   .byte   "<>", 0
k_abs:  .byte   "ABS", 0
k_sgn:  .byte   "SGN", 0
k_rnd:  .byte   "RND", 0
k_len:  .byte   "LEN", 0
k_left: .byte   "LEFT$", 0
k_right: .byte  "RIGHT$", 0
k_mid:  .byte   "MID$", 0
k_chr:  .byte   "CHR$", 0
k_asc:  .byte   "ASC", 0
k_str:  .byte   "STR$", 0
k_val:  .byte   "VAL", 0
k_hex:  .byte   "HEX$", 0
k_instr: .byte  "INSTR", 0
k_peek: .byte   "PEEK", 0
k_time: .byte   "TIME", 0
k_inkey: .byte  "INKEY$", 0
k_mousex: .byte "MOUSEX", 0
k_mousey: .byte "MOUSEY", 0
k_mouseb: .byte "MOUSEB", 0
k_point: .byte  "POINT", 0
k_tab:  .byte   "TAB", 0
k_spc:  .byte   "SPC", 0
k_fre:  .byte   "FRE", 0
k_min:  .byte   "MIN", 0
k_max:  .byte   "MAX", 0
k_sqr:  .byte   "SQR", 0
k_sin:  .byte   "SIN", 0
k_cos:  .byte   "COS", 0
k_tan:  .byte   "TAN", 0
k_atn:  .byte   "ATN", 0
k_exp:  .byte   "EXP", 0
k_log:  .byte   "LOG", 0
k_log10: .byte  "LOG10", 0
k_int:  .byte   "INT", 0
k_fix:  .byte   "FIX", 0
k_round: .byte  "ROUND", 0
k_pi:   .byte   "PI", 0
k_stick: .byte  "STICK", 0
k_strig: .byte  "STRIG", 0
k_vsync: .byte  "VSYNC", 0
k_deg:  .byte   "DEG", 0
k_rad:  .byte   "RAD", 0

        .segment "BSS"
tline:  .res    2
tlnum:  .res    2
tlen:   .res    2
wantln: .res    2
nlen:   .res    2
nbuf:   .res    40 * 2                  ; (16-bit entries: one character each)
lbn:    .res    2
lxnm:   .res    2                       ; (LIST: an extended statement's name)
tbuf:   .res    TMAX + 8
lbuf:   .res    LBMAX + 8
