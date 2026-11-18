; BASIC - Horizon BASIC (/BIN/BASIC.PRG): a line-numbered BASIC for the 65C816, run as a
; window program (a console window, and a graphics window opened by SCREEN).
;   basic [FILE.BAS]        the console (FILE loaded)
;   basic -r FILE.BAS       load and run
;   basic -t FILE.BAS       test mode: load and run; the console is mirrored to the kernel
;                           console (DBG_OUT); exit at the end (code 0, 1 after an error)
; The language is described in BASIC.md. One assembly unit made of:
;   basic.s      start, the immediate loop, events, menus, files, errors
;   bas_con.s    the console window: scrollback, drawing, the line editor
;   bas_tok.s    tokenizer, LIST (detokenizer), the symbol table
;   bas_prog.s   the program store: line index, lines, LOAD and SAVE as text
;   bas_exec.s   the statement loop and the statements
;   bas_expr.s   expressions, operators, functions, numbers
;   bas_fp.s     floating point: decimal arithmetic, number text
;   bas_fn.s     the functions of floating point (SQR, SIN, EXP, LOG ...)
;   bas_mem.s    variables, arrays, the string heap and its garbage collector
;   bas_gfx.s    the graphics window, sound
;   bas_prn.s    (Horizon 0.23) LPRINT and LLIST: the print job
;
; Memory: the code bank holds the interpreter and small buffers; everything else lives in
; banks of its own (SYS_BALLOC), so a program and its data can use many 64 KB banks:
;   VB      variables: 2048 slots of 8 bytes, the names (bas_mem.s)
;   IB      the line index: line numbers and line pointers, 8000 lines (bas_prog.s)
;   PB[8]   program lines (tokenized), 512 KB
;   SB[16]  the string heap, 1 MB, compacted by a mark / slide garbage collector
;   AB[32]  arrays, 2 MB (one array at most 64 KB)
;   CB      the console's scrollback: 512 rows of 128 characters
;   GB[6]   the graphics window's pixels (a shadow of the window, for POINT)
;   KB      the PEEK / POKE memory, 64 KB (allocated on first use)
;   FB      file transfers
;
; Values: an expression's value is the accumulator {ft type, flo, fhi, flen} in zero page;
; operands wait on the value stack (vstk, 8 bytes each: the same four words).
;   T_INT 0: a 32-bit signed integer in flo (low word), fhi (high word).
;   T_STR 2: a string: flo = offset, fhi = bank, flen = length (0-255). Its bytes live in
;            the string heap, in the program (literals, DATA), or in the code bank (CHR$
;            table, input buffers: copied into the heap when assigned).
;   T_FLT 4: a decimal float of 12 digits: ft = (exponent + 128) << 8 | 4 | sign, the BCD
;            digits in flen (the first four), fhi, flo (bas_fp.s).
; A number is an integer while it can be: integer operators on integers stay integers (the
; fast path: eval_p keeps an integer left operand on the hardware stack and calls iopjt),
; an integer result that does not fit becomes a float, / of integers is an integer when it
; divides exactly. A float on either side makes the operation a float one (opjt).
; A number variable's slot is {lo, hi, type, len}: an integer {lo, hi, 0, -} or a float
; {flo, fhi, ft, flen}; a % variable (TK_IVAR) holds only integers {lo, hi}.
        .include "horizon.inc"
        .include "ui.inc"

; ---------------------------------------------------------------- zero page
        .segment "ZEROPAGE"
tp:     .res    4               ; the token pointer (u24): the next token to execute
vb:     .res    4               ; the variable bank, offset 0
vb4:    .res    4               ; the variable bank, offset 4 (a number slot's type)
ib:     .res    4               ; the line index bank: line numbers at 0
ipt:    .res    4               ; the line index bank + LPTR: line pointers
ap:     .res    4               ; general long pointers
bp:     .res    4
cp:     .res    4
dp:     .res    4
ep:     .res    4
ft:     .res    2               ; the accumulator: type
flo:    .res    2               ;   int low / string offset
fhi:    .res    2               ;   int high / string bank
flen:   .res    2               ;   string length
t0:     .res    2
t1:     .res    2
t2:     .res    2
t3:     .res    2
t4:     .res    2
t5:     .res    2
t6:     .res    2
t7:     .res    2
pollc:  .res    2               ; statements until the next event poll
fbp:    .res    4               ; the file bank FB, offset 0
gp:     .res    4               ; (bas_mem.s: names, arrays, the collector)
gq:     .res    4
gr:     .res    4
gh:     .res    4
il:     .res    2               ; (bas_expr.s: the left number of an operator)
ih:     .res    2
fa:     .res    8               ; float register FA: digits m0..m3 (bas_fp.s)
fa_e:   .res    2               ;   exponent
fa_s:   .res    2               ;   sign
fb:     .res    8               ; float register FB
fb_e:   .res    2
fb_s:   .res    2
fstk:   .res    2               ; the sticky flag of FA's last result
fw:     .res    4               ; a 32-bit work value
dr:     .res    8               ; fp_div, fp_sqrt: remainder, divisor, divisor * 10
dd:     .res    8
dt:     .res    8

; ---------------------------------------------------------------- constants
T_INT   = 0
T_STR   = 2
T_FLT   = 4
K_NUM   = 0                     ; kinds of a place (lvalue, bas_expr.s)
K_STR   = 2
K_INT   = 4
K_NA4   = 6

.macro  a8
        sep     #$20
        .a8
.endmacro
.macro  a16
        rep     #$20
        .a16
.endmacro
.macro  jmi     dst
        bpl     *+5
        jmp     dst
.endmacro
.macro  jpl     dst
        bmi     *+5
        jmp     dst
.endmacro
; raise error n (never returns)
.macro  err     n
        lda     #n
        jmp     error
.endmacro
; print a string literal on the console (A, X, Y clobbered)
.macro  cprint  str
        ldx     #.loword(* + 8)
        jsr     con_puts
        bra     * + 3 + .strlen(str)
        .byte   str, 0
.endmacro

; error codes (errmsg has the texts)
E_SYNTAX = 1
E_TYPE  = 2
E_MEM   = 3
E_LINE  = 4
E_DIV0  = 5
E_OVF   = 6
E_SUBS  = 7
E_REDIM = 8
E_NEXT  = 9
E_RET   = 10
E_WEND  = 11
E_WHILE = 12
E_DATA  = 13
E_ARG   = 14
E_STRLEN = 15
E_VARS  = 16
E_STACK = 17
E_EXPR  = 18
E_CONT  = 19
E_FILE  = 20
E_NOFILE = 21
E_LONG  = 22
E_LINES = 23
E_NUM   = 24
E_NAME  = 25
E_NOLN  = 26
E_NOSCR = 27
E_DIRECT = 28
E_FUNC  = 29
E_NODEV = 30                    ; (2.0)
E_NOFS  = 31
E_INUSE = 32
E_NOPIC = 33
E_NOSMP = 34

; (2.0) the window bank (bank 0, $0000-$7FFF, private: the direct page at $0000 and the
; hardware stack, which stays above STKMIN) also holds tables the code bank has no room for
WIN_HIST = $0100                ; the line editor's history: NHIST x 256 (bas_con.s)
WIN_ROWO = $0900                ; the drawing area's row table: offsets, 1024 rows ...
WIN_ROWB = $1100                ; ... and banks (bas_gfx.s)
WIN_DL  = $1900                 ; the draw list: 128 records of 20 bytes (bas_game.s)
WIN_SPR = $2300                 ; the 16 sprites' spr_set entries, 10 bytes each
WIN_ORPH = $2400                ; banks set aside while looking for consecutive ones
WIN_FSPAL = $2500               ; the full-screen palette as set: 256 x 3 bytes
WIN_CSTK = $2800                ; the control stack: CSMAX frames of CSF bytes (bas_exec.s)
WIN_END = $4000

; actions of the line editor (con_input with C set)
ACT_BREAK = 1
ACT_MENU = 2
ACT_CLOSE = 3

        .segment "CODE"
        .a16
        .i16
start:  sta     argl
        stx     argx
        tsx                             ; the stack level of the immediate loop
        stx     err_sp
        sys     SYS_WSSTART
        bcc     :+
        print   "basic: no window system\n"
        exit    1
:       sta     wsown
        jsr     ui_init
        jsr     mem_init
        bcc     :+
        jsr     stopws
        print   "basic: not enough memory\n"
        exit    1
:       jsr     game_reset              ; (2.0: the window bank's tables)
        jsr     getargs
        jsr     con_open
        bcc     :+
        jsr     stopws
        print   "basic: no window\n"
        exit    1
:       lda     amode
        cmp     #2
        bne     @norm
        lda     #1                      ; -t: a script, the console mirrored
        sta     mirror
        jsr     script_open
        bcc     @ready
        lda     #1
        jmp     quit_code
@norm:  jsr     banner
        jsr     settitle
        lda     fpath
        and     #$00FF
        beq     @ready
        jsr     prog_load               ; (errors: reported, then Ready)
        bcs     @ready
        jsr     settitle
        lda     amode
        beq     @ready
        jmp     run_start               ; -r: RUN
@ready: jmp     main_ready

banner: cprint  "Horizon BASIC 2.0"
        jsr     con_nl
        sys     SYS_MINFO               ; free memory: banks x 64 KB
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        sta     flo
        stz     fhi
        jsr     con_putnum
        cprint  " KB free"
        jmp     con_nl

stopws: lda     wsown
        beq     :+
        sys     SYS_WSSTOP
:       rts

; leave: exit code 0 (A = code: quit_code)
quit:   lda     #0
quit_code:
        pha
        jsr     lp_end                  ; (0.23) the print job finished
        jsr     snd_off
        jsr     pal_restore
        jsr     stopws
        jsr     out_flush
        pla
        sys     SYS_EXIT

; the arguments: [-r | -t] [FILE] -> amode, fpath (absolute)
getargs:
        stz     fpath
        stz     amode
        lda     argl
        beq     @out
        ldx     argx
        jsr     args_init
        jsr     @arg
        lda     abuf
        and     #$FFFF
        cmp     #'-' | ('r' << 8)
        beq     @run
        cmp     #'-' | ('R' << 8)
        beq     @run
        cmp     #'-' | ('t' << 8)
        beq     @test
        cmp     #'-' | ('T' << 8)
        bne     @name
@test:  lda     #1
        sta     amode
@run:   inc     amode
        lda     abuf+2
        and     #$00FF
        bne     @out
        jsr     @arg
@name:  lda     abuf
        and     #$00FF
        beq     @out
        ldx     #.loword(abuf)
        jsr     mkabs
@out:   rts
@arg:   ldx     #.loword(abuf)
        ldy     #^abuf
        lda     #128
        jmp     next_arg

; the name X (in our bank) made absolute -> fpath; ".BAS" added when it has no extension
mkabs:  stx     z:t0
        lda     (t0)
        and     #$00FF
        cmp     #'/'
        bne     :+
        ldy     #.loword(fpath)
        jsr     ui_strcpy
        bra     @ext
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
        a8
        sta     fpath,x
        a16
        beq     @ext
        inx
        iny
        cpx     #120
        bcc     :-
        stz     fpath,x
@ext:   ldx     #0                      ; a '.' after the last '/'?
        ldy     #0
:       lda     fpath,x
        and     #$00FF
        beq     :+++
        cmp     #'/'
        bne     :+
        ldy     #0
:       cmp     #'.'
        bne     :+
        ldy     #1
:       inx
        cpx     #124
        bcc     :---
:       cpy     #0
        bne     @out
        lda     fpath-1,x               ; (a lower case name: ".bas")
        and     #$00FF
        cmp     #'a'
        bcs     :+
        lda     #'.' | ('B' << 8)
        sta     fpath,x
        lda     #'A' | ('S' << 8)
        sta     fpath+2,x
        stz     fpath+4,x
        rts
:       lda     #'.' | ('b' << 8)
        sta     fpath,x
        lda     #'a' | ('s' << 8)
        sta     fpath+2,x
        stz     fpath+4,x
@out:   rts

; ---------------------------------------------------------------- the immediate loop
; after a program or direct command: "Ready"
main_ready:
        rep     #$30
        .a16
        .i16
        phk
        plb
        ldx     err_sp
        txs
        stz     running
        stz     vsp                     ; (values left by an error or a break)
        jsr     lp_end                  ; (0.23) the run's print job finished
        jsr     fs_suspend              ; (2.0: the console is seen while BASIC waits)
        lda     script                  ; (a script: no Ready)
        bne     main_cmd
        jsr     con_bol
        cprint  "Ready"
        jsr     con_nl
main_cmd:
        rep     #$30
        phk
        plb
        ldx     err_sp
        txs
        stz     running
        stz     brkf
        lda     #$FFFF
        sta     curidx
        jsr     gfx_flush
        lda     #0
        jsr     con_input
        bcc     :+
        jmp     action
:       cmp     #0
        beq     main_cmd
        jsr     tokenize
        lda     tline
        beq     :+
        jsr     prog_enter              ; a program line
        jmp     main_cmd
:       jsr     direct_copy             ; a direct command
        lda     #1
        sta     running
        jmp     stmt

; the line editor reported an action A (menu, close)
action: cmp     #ACT_CLOSE
        jeq     m_close
        cmp     #ACT_MENU
        jne     main_cmd
        lda     pend_menu
        ldx     #$FFFF
        stx     pend_menu
        cmp     #$0100                  ; Program menu
        bcs     @prog
        asl     a
        tax
        cpx     #12
        jcs     main_cmd
        jmp     (ftab,x)
@prog:  and     #$00FF
        cmp     #0
        beq     m_run
        cmp     #2
        beq     m_list
        jmp     main_cmd
m_run:  jsr     con_bol
        cprint  "RUN"
        jsr     con_nl
        jmp     run_start
m_list: jsr     con_bol
        cprint  "LIST"
        jsr     con_nl
        lda     #1
        sta     running
        stz     lfrom
        lda     #$FFFF
        sta     lto
        jsr     list_range
        jmp     main_ready
m_new:  jsr     confirm
        jcs     main_cmd
        jsr     con_bol
        cprint  "NEW"
        jsr     con_nl
        jsr     prog_new
        stz     fpath
        jsr     settitle
        jmp     main_ready
m_load: jsr     confirm
        jcs     main_cmd
        stz     dlgbuf
        lda     #0
        ldx     #.loword(dlgbuf)
        ldy     #.loword(t_load)
        jsr     ui_filedlg
        jcs     main_cmd
        ldx     #.loword(dlgbuf)
        ldy     #.loword(fpath)
        jsr     ui_strcpy
        jsr     con_bol
        cprint  "LOAD "
        jsr     basename
        jsr     con_puts
        jsr     con_nl
        jsr     prog_load
        jsr     settitle
        jmp     main_ready
m_save: jsr     do_save
        jmp     main_cmd
m_saveas:
        jsr     do_saveas
        jmp     main_cmd
m_close:
        jsr     confirm
        jcs     main_cmd
        jmp     quit

; File > Save: to its path, or Save as for a new program -> C set: not saved
do_save:
        lda     fpath
        and     #$00FF
        beq     do_saveas
        jmp     save_report
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
:       ldx     #.loword(dlgbuf)        ; (.BAS added when no extension was given)
        jsr     mkabs
        jsr     save_report
        php
        jsr     settitle
        plp
        rts
; save to fpath, say so on the console
save_report:
        jsr     con_bol
        cprint  "SAVE "
        jsr     basename
        jsr     con_puts
        jsr     con_nl
        jsr     prog_save
        bcs     :+
        jsr     settitle
        clc
        rts
:       jsr     con_puterr
        sec
        rts

; unsaved changes: ask (Save / Discard / Cancel) -> C set: stop
confirm:
        lda     pmod
        bne     :+
        clc
        rts
:       ldx     #.loword(m_save1)
        ldy     #.loword(msgbuf)
        jsr     ui_strcpy
        jsr     basename
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

; the window title: "BASIC: name" (and " *" when changed)
settitle:
        ldx     #.loword(t_basic)
        ldy     #.loword(msgbuf)
        jsr     ui_strcpy
        lda     fpath
        and     #$00FF
        beq     @mod
        ldx     #.loword(t_colon)
        jsr     append
        jsr     basename
        ldy     #.loword(msgbuf+7)
        jsr     ui_strcpy
        cmp     #22
        bcc     @mod
        lda     #'.' | ('.' << 8)
        sta     msgbuf+7+19
        stz     msgbuf+7+21
@mod:   lda     pmod
        beq     :+
        ldx     #.loword(t_star)
        jsr     append
:       lda     win
        ptr     msgbuf
        sys     SYS_WTITLE
        rts

; the program changed (title shows " *")
setmod: lda     pmod
        bne     :+
        inc     pmod
        jsr     settitle
:       rts

; ---------------------------------------------------------------- events
; one event (A = 0 wait, 1 poll) -> C set: none (poll only). Keys go to the key ring (Esc
; and ctrl-C while running set brk instead), menus to pend_menu (while running: Stop and
; Close break, the rest beeps). (MOUSEX, MOUSEY, MOUSEB ask the kernel: SYS_WMOUSE.)
pump:   jsr     ui_getev
        bcc     :+
        rts
:       ldx     #.loword(ctls)
        jsr     ui_event
        cmp     #UA_CHANGE
        bne     :+
        jsr     con_sbmoved
        clc
        rts
:       cmp     #UA_NONE
        beq     :+
        clc
        rts
:       lda     ui_ev
        and     #$00FF
        cmp     #WE_KEY
        beq     @key
        cmp     #WE_MENU
        jeq     @menu
        cmp     #WE_CLOSE
        jeq     @close
        cmp     #WE_RESIZE
        jeq     @resize
        cmp     #WE_FOCUS
        beq     @focus
        cmp     #WE_UNFOCUS
        beq     @unfoc
@done:  clc
        rts
@focus: lda     ui_ev+1                 ; (2.0) the graphics window's focus: its sprites,
        and     #$00FF                  ; the full screen
        cmp     gwin
        bne     @done
        lda     #1
        sta     gfocus
        clc
        rts
@unfoc: lda     ui_ev+1
        and     #$00FF
        cmp     gwin
        bne     @done
        stz     gfocus
        lda     gmode                   ; (full screen left: the window shows its picture)
        beq     @done
        jsr     dirty_all
        clc
        rts
@key:   lda     ui_ev+2                 ; (2.0) the arrows and Space held: STICK(0), STRIG(0)
        ldx     #8
:       cmp     kh_use,x
        beq     :+
        dex
        dex
        bpl     :-
        bra     @kd
:       lda     kh_bit,x
        ldx     ui_ev+4
        cpx     #$0100
        bcc     :+
        tsb     kheld
        bra     @kd
:       trb     kheld
@kd:    lda     ui_ev+4
        cmp     #$0100
        bcc     @done
        lda     ui_key
        beq     @done
        ldx     running
        beq     @queue
        cmp     #27
        beq     @brk
        cmp     #3
        beq     @brk
@queue: jsr     kr_put
        clc
        rts
@brk:   lda     #1
        sta     brkf
        clc
        rts
@menu:  lda     ui_ev+2                 ; menu << 8 | item
        xba
        ora     ui_ev+4
        ldx     running
        bne     :+
        sta     pend_menu
        clc
        rts
:       cmp     #$0101                  ; Program > Stop
        beq     @brk
        cmp     #$0005                  ; File > Close
        beq     @cls
        jsr     ui_beep
        clc
        rts
@close: lda     ui_ev+1
        and     #$00FF
        cmp     win
        bne     @gclose
        ldx     running
        bne     @cls
        lda     #1
        sta     pend_close
        clc
        rts
@cls:   lda     #1
        sta     pend_close
        sta     brkf
        clc
        rts
@gclose:
        jsr     gfx_close
        lda     running
        beq     :+
        lda     #1
        sta     brkf
:       clc
        rts
@resize:
        lda     ui_ev+1
        and     #$00FF
        cmp     win
        jne     @done
        lda     ui_ev+2
        sta     cw
        lda     ui_ev+4
        sta     chh
        jsr     con_geom
        lda     #1
        sta     cfull
        jsr     con_follow
        jsr     con_flush
        clc
        rts

; the key ring: kr_put A (dropped when full), kr_get -> C clear and A = key, C set: empty
kr_put: ldx     krh
        a8
        sta     kring,x
        a16
        inx
        txa
        and     #KRN - 1
        cmp     krt
        beq     :+
        sta     krh
:       rts
kr_get: ldx     krt
        cpx     krh
        beq     :+
        lda     kring,x
        and     #$00FF
        pha
        inx
        txa
        and     #KRN - 1
        sta     krt
        pla
        clc
        rts
:       sec
        rts

; every POLLN statements while running: events, Esc, the screen every FLUSHMS
POLLN   = 200
FLUSHMS = 40
periodic:
        lda     #POLLN
        sta     z:pollc
@ev:    lda     #1
        jsr     pump
        bcc     @ev
        lda     brkf
        jne     do_break
        sys     SYS_UPTIME
        sec
        sbc     nextfl
        bmi     :+
        jsr     flush_all
:       rts

; both windows up to date; the next periodic flush FLUSHMS later (or later still when the
; drawing itself took long)
flush_all:
        jsr     con_flush
        jsr     gfx_flush
        jsr     game_flush              ; (2.0: unless VSYNC paces the program)
        sys     SYS_UPTIME
        clc
        adc     #FLUSHMS
        sta     nextfl
        rts

; ---------------------------------------------------------------- errors
; error A: the message (with the line), Ready. In test mode: exit 1.
error:  rep     #$38                    ; (also decimal mode off)
        phk
        plb
        ldx     err_sp
        txs
        sta     errcode
        stz     lpon                    ; (0.23) the message to the console
        jsr     snd_off
        jsr     game_stop
        stz     contok
        jsr     con_bol
        lda     errcode
        jsr     con_errmsg
        lda     loading                 ; LOAD: the file's line, the file closed
        beq     :+
        jsr     load_end
        cprint  " in file line "
        lda     lfline
        jsr     con_putu16
        bra     :++
:       lda     curidx
        cmp     #$FFFF
        beq     :+
        cprint  " in "
        jsr     cur_lnum
        jsr     con_putu16
:       jsr     con_nl
        lda     #1                      ; (a script's exit code)
        sta     serr
        jmp     main_ready

; ---------------------------------------------------------------- test scripts
; -t FILE: the file (64 KB at most) is read into a bank of its own and fed to the
; immediate loop as typed lines: numbered lines are stored, the others run (shown on the
; console, so in the log), INPUT takes the next line. At its end: RUN if it held only
; numbered lines, then exit (code 1 if an error was reported).
script_open:
        sys     SYS_BALLOC
        bcs     @no
        sta     z:dp+2
        sta     sbank
        stz     z:dp
        ptr     fpath
        lda     #O_READ
        sys     SYS_OPEN
        bcs     @err
        sta     lfh
        sta     rblk
        stz     rblk+1
        lda     sbank
        sta     rblk+3
        lda     #$FFF0
        sta     rblk+4
        ptr     rblk
        sys     SYS_READ
        bcs     @err
        sta     slen
        lda     lfh
        sys     SYS_CLOSE
        stz     spos
        lda     #1
        sta     script
        clc
        rts
@err:   jsr     con_puterr
@no:    sec
        rts

; the next line of the script -> ibuf, ilen (C set: none left)
script_line:
        stz     ilen
        lda     sbank
        sta     z:dp+2
        stz     z:dp
        ldy     spos
        cpy     slen
        bcs     @eof
@l:     cpy     slen
        bcs     @end
        lda     [dp],y
        iny
        and     #$00FF
        cmp     #10
        beq     @end
        cmp     #' '
        bcc     @l
        cmp     #127
        bcs     @l
        ldx     ilen
        cpx     #IMAX
        bcs     @l
        a8
        sta     ibuf,x
        a16
        inc     ilen
        bra     @l
@end:   sty     spos
        ldx     ilen
        a8
        stz     ibuf,x
        a16
        clc
        rts
@eof:   sec
        rts

; con_input for a script (A = mode): the next line, shown unless it is numbered
script_input:
        sta     imode
@next:  jsr     script_line
        bcs     @eof
        lda     imode
        bne     @show
        ldx     #0                      ; numbered (a program line): quietly
:       lda     ibuf,x
        and     #$00FF
        cmp     #' '
        bne     :+
        inx
        bra     :-
:       jsr     tk_isdigit
        bcs     @out
        lda     ilen                    ; (blank lines are skipped)
        beq     @next
        lda     #1
        sta     sran
@show:  ldx     #.loword(ibuf)
        jsr     con_puts
        jsr     con_nl
@out:   lda     ilen
        clc
        rts
@eof:   lda     imode                   ; the end: RUN a program nothing ran yet
        bne     @quit
        lda     sran
        bne     @quit
        lda     nlines
        beq     @quit
        inc     sran
        lda     #'R' | ('U' << 8)
        sta     ibuf
        lda     #'N'
        sta     ibuf+2
        lda     #3
        sta     ilen
        bra     @show
@quit:  lda     serr
        jmp     quit_code

; the message of error A
con_errmsg:
        cmp     #E_LINE
        bne     :+
        cprint  "Undefined line "
        lda     errarg
        jmp     con_putu16
:       pha
        asl     a
        tax
        lda     errtab-2,x
        tax
        jsr     con_puts
        pla                             ; (0.23) "File error $XX": the I/O error of the
        cmp     #E_FILE                 ; print job
        bne     :+
        lda     ioerr
        beq     :+
        stz     ioerr
        pha
        cprint  " $"
        pla
        jmp     con_puthex8
:       rts

; an I/O error A (prog_load, prog_save): the message on the console
con_puterr:
        cmp     #$44
        beq     :+
        cmp     #$45
        beq     :+
        pha
        cprint  "File error $"
        pla
        jsr     con_puthex8
        jmp     con_nl
:       cprint  "File not found"
        jmp     con_nl

; Esc, ctrl-C, Program > Stop while running: "Break in N", CONT goes on from here
do_break:
        rep     #$30
        phk
        plb
        ldx     err_sp
        txs
        stz     brkf
        stz     lpon                    ; (0.23) the message to the console
        jsr     snd_off
        jsr     game_stop
        lda     curidx
        sta     contidx
        lda     stmtp
        sta     conttp
        lda     #1
        sta     contok
        lda     pend_close
        beq     :+
        stz     pend_close
        jsr     confirm
        jcc     quit
:       jsr     con_bol
        cprint  "Break"
        lda     curidx
        cmp     #$FFFF
        beq     :+
        cprint  " in "
        jsr     cur_lnum
        jsr     con_putu16
:       jsr     con_nl
        jmp     main_ready

        .include "bas_con.s"
        .include "bas_tok.s"
        .include "bas_prog.s"
        .include "bas_exec.s"
        .include "bas_expr.s"
        .include "bas_fp.s"
        .include "bas_fn.s"
        .include "bas_mem.s"
        .include "bas_gfx.s"
        .include "bas_game.s"
        .include "bas_snd.s"
        .include "bas_prn.s"

        .segment "RODATA"
menus:  .byte   "File", 0, "New", 0, "Load...", 0, "Save", 0, "Save as...", 0, "-", 0, "Close", 0, 0
        .byte   "Program", 0, "Run", 0, "Stop", 0, "List", 0, 0, 0
        .res    128 - (* - menus)
ftab:   .addr   m_new, m_load, m_save, m_saveas, main_cmd, m_close
kh_use: .word   $52, $51, $50, $4F, $2C ; up, down, left, right, Space (HID usages)
kh_bit: .word   1, 2, 4, 8, 16          ; as SYS_JOY's port 1 bits, then its trigger
ctls:   .addr   es_sb, 0
t_basic: .byte  "BASIC", 0
t_colon: .byte  ": ", 0
t_star: .byte   " *", 0
t_newname: .byte "(new)", 0
t_load: .byte   "Load", 0
t_saveas: .byte "Save as", 0
m_save1: .byte  "Save the changes to ", 0
m_save2: .byte  "?", 10, "Changes that are not saved will be lost.", 0
b_save: .byte   "Save", 0
b_discard: .byte "Discard", 0
b_cancel: .byte "Cancel", 0
al_save: .word  2, t_basic, msgbuf, b_save, b_discard, b_cancel
errtab: .addr   s_e1, s_e2, s_e3, s_e4, s_e5, s_e6, s_e7, s_e8, s_e9, s_e10
        .addr   s_e11, s_e12, s_e13, s_e14, s_e15, s_e16, s_e17, s_e18, s_e19, s_e20
        .addr   s_e21, s_e22, s_e23, s_e24, s_e25, s_e26, s_e27, s_e28, s_e29, s_e30
        .addr   s_e31, s_e32, s_e33, s_e34
s_e1:   .byte   "Syntax error", 0
s_e2:   .byte   "Type mismatch", 0
s_e3:   .byte   "Out of memory", 0
s_e4:   .byte   "Undefined line", 0
s_e5:   .byte   "Division by zero", 0
s_e6:   .byte   "Overflow", 0
s_e7:   .byte   "Subscript out of range", 0
s_e8:   .byte   "Array already dimensioned", 0
s_e9:   .byte   "NEXT without FOR", 0
s_e10:  .byte   "RETURN without GOSUB", 0
s_e11:  .byte   "WEND without WHILE", 0
s_e12:  .byte   "WHILE without WEND", 0
s_e13:  .byte   "Out of DATA", 0
s_e14:  .byte   "Bad argument", 0
s_e15:  .byte   "String too long", 0
s_e16:  .byte   "Too many variables", 0
s_e17:  .byte   "Nesting too deep", 0
s_e18:  .byte   "Expression too complex", 0
s_e19:  .byte   "Cannot continue", 0
s_e20:  .byte   "File error", 0
s_e21:  .byte   "File not found", 0
s_e22:  .byte   "Line too long", 0
s_e23:  .byte   "Too many lines", 0
s_e24:  .byte   "Number too large", 0
s_e25:  .byte   "Name too long", 0
s_e26:  .byte   "Line number missing", 0
s_e27:  .byte   "No graphics window", 0
s_e28:  .byte   "Not in direct mode", 0
s_e29:  .byte   "Illegal function call", 0
s_e30:  .byte   "Not available on this machine", 0
s_e31:  .byte   "Full screen only", 0
s_e32:  .byte   "In use by another program", 0
s_e33:  .byte   "Undefined picture", 0
s_e34:  .byte   "Undefined sample", 0

        .segment "DATA"
es_sb:  .byte   UT_VSCROLL, 0
        .word   0, 0, UI_SBW, 0, 0
        .word   0, 0, 1, 1, 0, 0
pend_menu: .word $FFFF

        .segment "BSS"
argl:   .res    2
argx:   .res    2
amode:  .res    2               ; 0 normal, 1 -r, 2 -t
script: .res    2               ; -t: lines come from the script bank
sbank:  .res    2
slen:   .res    2
spos:   .res    2
sran:   .res    2               ; a direct line ran
serr:   .res    2               ; an error was reported
mirror: .res    2               ; 1: the console also goes to DBG_OUT
wsown:  .res    2
err_sp: .res    2               ; S of the immediate loop
errcode: .res   2
errarg: .res    2
running: .res   2               ; 1 while statements execute
brkf:    .res    2               ; Esc / ctrl-C / Stop seen while running
pend_close: .res 2
pmod:   .res    2               ; the program changed since LOAD / SAVE
nextfl: .res    2               ; uptime (low word) of the next periodic flush
mbuf:   .res    10              ; SYS_WMOUSE: screen x, y, content x, y, buttons
kheld:  .res    2               ; (2.0) kh_bit of the keys held now
KRN     = 32
kring:  .res    KRN
krh:    .res    2
krt:    .res    2
fpath:  .res    130
abuf:   .res    130
dlgbuf: .res    130
msgbuf: .res    200
