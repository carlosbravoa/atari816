; CALC - the Calculator (/BIN/CALC.PRG): a small window with a display and keys.
; "calc -t" runs the self test instead (no window): a table of key sequences, PASS or FAIL
; for each on the console (DBG_OUT).
;
; Two layouts (View menu): Standard - decimal numbers of 16 digits (calc_num.s: decimal
; floating point, so 0.1 + 0.2 = 0.3; results rounded to 16 digits, 15 shown), + - x /, =
; (again: the last operation again), %, square root, 1/x, x squared, +/-, C, CE, Backspace and
; the memory (MC MR M+ M-); Programmer - 32-bit integers (two's complement) shown in hex,
; decimal (signed), octal and binary at once, the base of the input chosen by a click on its
; line (or F5-F8), + - x / Mod And Or Xor Not, shifts (<< logical, >> arithmetic), rotations
; by one bit. Operations are done as they come (2 + 3 x 4 = 20), as on a pocket calculator.
; Errors (divide by zero, overflow beyond 1e99, the root of a negative number) are shown
; until C, CE, Backspace or a digit. Edit > Copy / Paste: the display through the system
; clipboard (a pasted number may have spaces, a sign, commas between digits, an exponent).
;
; Keys: digits, . or , + - * / = Enter % ; Esc = C, Delete = CE, Backspace; r = 1/x, @ = root,
; q = x squared, n = +/-; ctrl-C / ctrl-V copy / paste; Programmer: a-f, & | ^ ~ < >, % = Mod,
; F5 hex, F6 decimal, F7 octal, F8 binary.
;
; Engine: calc_key takes one key code (the internal codes below, which the self test types
; directly) and changes the state; mkdisp makes the display's strings (dstr, xstr). The
; window shows them in a picture drawn by the program (its own digit fonts: one blit, so the
; display never flickers); the keys are drawn with win_draw.
;
; Internal key codes: 0-9 . + - * / = % ; C clear, E clear entry, B backspace, N +/-, Q root,
; I 1/x, S x squared, k MC, r MR, p M+, m M-; V programmer view, W standard view; Programmer:
; a-f digits, & | ^ ~ < > , L rotate left, R rotate right, H D O Y hex / dec / oct / bin.
        .include "horizon.inc"
        .include "ui.inc"

KSZ     = 12                            ; a key: x, y, w, h, u8 code, u8 style, label
K_X     = 0
K_Y     = 2
K_W     = 4
K_H     = 6
K_CODE  = 8
K_STY   = 9
K_LBL   = 10                            ; < 32: an icon, else the label string
ST_DIG  = 0                             ; key styles
ST_OP   = 1
ST_FN   = 2
ST_EQ   = 3
ST_CLR  = 4
C_DBG   = C_WHITE                       ; the display's paper and inks
C_DINK  = C_SHADOW
C_DSUB  = C_DARK
SW      = 212                           ; Standard: content size, the display's inside
SH      = 232
SDW     = 194
SDH     = 42
PW      = 276                           ; Programmer
PH      = 268
PDW     = 258
PDH     = 78
BIGY    = 21                            ; the big digits' top (Standard), and below the
BIGYP   = 15                            ;   expression line (Programmer)
PANY    = 36                            ; Programmer: the first base line
PANH    = 10                            ;   their spacing
BIGH    = 14                            ; glyph heights
MINH    = 7
KEYC    = 231                           ; the transparent colour of the key digits' blits

        .segment "CODE"
        .a16
        .i16
start:  sta     argl
        stx     argx
        jsr     reset
        lda     argl                    ; "-t": the self test
        beq     @win
        ldx     argx
@sp:    lda     f:0,x                   ; (the argument is in bank 0)
        and     #$00FF
        cmp     #' '
        bne     :+
        inx
        bra     @sp
:       cmp     #'-'
        bne     @win
        lda     f:1,x
        and     #$00FF
        ora     #$20
        cmp     #'t'
        bne     @win
        jmp     test_run
@win:   sys     SYS_WSSTART
        bcc     :+
        print   "calc: no window system\n"
        exit    1
:       sta     wsown
        jsr     ui_init
        sys     SYS_BALLOC
        bcc     :+
        jsr     stopws
        print   "calc: not enough memory\n"
        exit    1
:       sta     dbank
        lda     #200
        sta     wopen
        lda     #64
        sta     wopen+2
        jsr     openwin
        jcc     loop
        jsr     stopws
        print   "calc: no window\n"
        exit    1

stopws: lda     wsown
        beq     :+
        sys     SYS_WSSTOP
:       rts

quit:   lda     win
        sys     SYS_WCLOSE
        jsr     stopws
        exit    0

; the window for the current mode at wopen's x, y -> C set: none
openwin:
        lda     mode
        beq     :+
        lda     #PW
        ldx     #PH
        bra     :++
:       lda     #SW
        ldx     #SH
:       sta     wopen+4
        stx     wopen+6
        ptr     wopen
        sys     SYS_WOPEN
        bcs     @out
        sta     win
        ptr     menus                   ; (the view checked)
        lda     mode
        beq     :+
        ptr     pmenus
:       lda     win
        sys     SYS_WMENU
        jsr     setgeom
        jsr     drawall
        clc
@out:   rts

; the layout of the current mode
setgeom:
        lda     mode
        bne     :+
        lda     #.loword(skeys)
        sta     keys
        lda     #SDW
        sta     dw
        lda     #SDH
        sta     dh
        lda     #BIGY
        sta     bigy
        rts
:       lda     #.loword(pkeys)
        sta     keys
        lda     #PDW
        sta     dw
        lda     #PDH
        sta     dh
        lda     #BIGYP
        sta     bigy
        rts

; ---------------------------------------------------------------- events
loop:   lda     #0
        jsr     ui_getev
        bcs     loop
        lda     ui_ev
        and     #$00FF
        cmp     #WE_BUTTON
        beq     onbutton
        cmp     #WE_MOTION
        jeq     onmotion
        cmp     #WE_KEY
        jeq     onkey
        cmp     #WE_MENU
        jeq     onmenu
        cmp     #WE_CLOSE
        jeq     quit
        bra     loop

onbutton:
        lda     ui_ev+6
        and     #1
        bne     @press
        ldx     presk_was               ; a release: the key held is activated if the
        beq     @out                    ; pointer is still on it
        stz     presk_was
        lda     presk
        beq     @out
        stz     presk
        stx     fkey
        lda     #0
        jsr     drawkey
        jsr     hitkey
        cpx     fkey
        bne     @out
        lda     a:K_CODE,x
        and     #$00FF
        jsr     dokey
@out:   jmp     loop
@press: jsr     hitkey
        bcc     @panel
        jsr     keydim
        bcs     @beep
        stx     presk
        stx     presk_was
        lda     #1
        jsr     drawkey
        jmp     loop
@beep:  jsr     ui_beep
        jmp     loop
@panel: lda     mode                    ; Programmer: a base line chosen
        jeq     loop
        lda     ui_ev+2
        sec
        sbc     #9
        cmp     #PDW
        jcs     loop
        lda     ui_ev+4
        sec
        sbc     #9 + PANY - 2
        bpl     :+
        jmp     loop
:
        ldx     #0
:       cmp     #PANH
        bcc     :+
        sbc     #PANH
        inx
        bra     :-
:       cpx     #4
        jcs     loop
        lda     basecode,x
        and     #$00FF
        jsr     dokey
        jmp     loop

onmotion:
        lda     presk_was               ; pressed while the pointer is on it
        jeq     loop
        jsr     hitkey
        cpx     presk_was
        beq     @on
        lda     presk                   ; off the key
        jeq     loop
        stz     presk
        ldx     presk_was
        lda     #0
        jsr     drawkey
        jmp     loop
@on:    lda     presk
        jne     loop
        stx     presk                   ; back on it
        lda     #1
        jsr     drawkey
        jmp     loop

; a key typed
onkey:  lda     ui_ev+4
        cmp     #$0100
        jcc     loop                    ; (releases)
        lda     ui_ev+2
        cmp     #$3E                    ; F5-F8: the base (Programmer)
        bcc     :+
        cmp     #$42
        bcs     :+
        sbc     #$3E - 1
        tax
        lda     mode
        jeq     loop
        lda     basecode,x
        and     #$00FF
        jmp     @do
:       lda     ui_ev+2
        ldx     ui_ev+4
        jsr     key_ascii
        sta     z:t0
        cmp     #0
        jeq     loop
        lda     ui_ev+4
        and     #$0011                  ; ctrl
        beq     @plain
        lda     z:t0
        cmp     #3
        jeq     m_copy
        cmp     #22
        jeq     m_paste
        jmp     loop
@plain: lda     z:t0                    ; letters in lower case
        cmp     #'A'
        bcc     :+
        cmp     #'Z' + 1
        bcs     :+
        ora     #$20
        sta     z:t0
:       cmp     #'0'                    ; digits (Programmer: a-f too) are their codes
        bcc     @tab
        cmp     #'9' + 1
        bcc     @do
        ldx     mode
        beq     @tab
        cmp     #'a'
        bcc     @tab
        cmp     #'f' + 1
        bcc     @do
@tab:   ldx     #.loword(ktab_c)        ; the others by the tables
        jsr     kfind
        bcs     @do
        ldx     #.loword(ktab_s)
        lda     mode
        beq     :+
        ldx     #.loword(ktab_p)
:       jsr     kfind
        jcc     loop
@do:    sta     z:t0                    ; the key on screen pressed for a moment
        jsr     findkey
        bcc     @run
        stx     fkey
        jsr     keydim
        bcc     :+
        jsr     ui_beep
        jmp     loop
:       lda     z:t0
        sta     fcode
        ldx     fkey
        lda     #1
        jsr     drawkey
        sys     SYS_WSSYNC
        lda     #60
        sys     SYS_SLEEP
        ldx     fkey
        lda     #0
        jsr     drawkey
        lda     fcode
        sta     z:t0
@run:   lda     z:t0
        jsr     dokey
        jmp     loop

; X = table of (key, code) byte pairs ending with 0: z:t0 -> C set, A = its code
kfind:  lda     a:0,x
        and     #$00FF
        beq     @no
        cmp     z:t0
        beq     :+
        inx
        inx
        bra     kfind
:       lda     a:1,x
        and     #$00FF
        sec
        rts
@no:    clc
        rts

; A = key code: act, show the result
dokey:  sta     z:t0
        cmp     #'V'
        beq     @view
        cmp     #'W'
        beq     @view
        lda     mode
        sta     z:t2
        lda     base
        sta     z:t3
        lda     z:t0
        jsr     calc_key
        lda     base                    ; a new base: the digit keys' state
        cmp     z:t3
        beq     :+
        jsr     drawkeys
:       jmp     showdisp
@view:  ldx     #1                      ; a new layout: (0.15) the same window, resized to it
        cmp     #'V'                    ; (win_geom: it stays where it is)
        beq     :+
        ldx     #0
:       cpx     mode
        beq     @out
        jsr     calc_key
        lda     #$8000
        sta     wgeo
        lda     #SW
        ldx     #SH
        ldy     mode
        beq     :+
        lda     #PW
        ldx     #PH
:       sta     wgeo+4
        stx     wgeo+6
        lda     win
        ptr     wgeo
        sys     SYS_WGEOM
        ptr     menus                   ; (the view checked)
        lda     mode
        beq     :+
        ptr     pmenus
:       lda     win
        sys     SYS_WMENU
        jsr     setgeom
        lda     #1                      ; (the screen shows the new view whole)
        sys     SYS_WSHOLD
        jsr     uwin                    ; (the old layout cleared away)
        stz     z:ui_x
        stz     z:ui_y
        lda     wgeo+4
        sta     z:ui_w
        lda     wgeo+6
        sta     z:ui_h
        lda     #WD_FILL | (C_BODY << 8)
        jsr     ui_rect
        jsr     drawall
        lda     #0
        sys     SYS_WSHOLD
@out:   rts

onmenu: lda     ui_ev+2                 ; Edit 0, View 1
        bne     @view
        lda     ui_ev+4
        jeq     m_copy
        cmp     #1
        jeq     m_paste
        jmp     loop
@view:  lda     ui_ev+4
        bne     :+
        lda     #'W'
        bra     :++
:       lda     #'V'
:       jsr     dokey
        jmp     loop

m_copy: jsr     mkdisp
        lda     #.loword(dstr)
        sta     clipblk
        lda     #^dstr
        sta     clipblk+2
        ldx     #.loword(dstr)
        jsr     ui_strlen
        sta     clipblk+3
        ptr     clipblk
        sys     SYS_CLPUT
        jmp     loop
m_paste:
        lda     #.loword(pbuf)
        sta     clipblk
        lda     #^pbuf
        sta     clipblk+2
        lda     #63
        sta     clipblk+3
        ptr     clipblk
        sys     SYS_CLGET
        bcs     @bad
        cmp     #64
        bcs     @bad                    ; (too long for a number)
        tax
        sep     #$20
        .a8
        stz     pbuf,x
        rep     #$20
        .a16
        jsr     paste
        bcs     @bad
        jsr     showdisp
        jmp     loop
@bad:   jsr     ui_beep
        jmp     loop

; ---------------------------------------------------------------- the keys on screen
; the key under the event's pointer -> C set, X (else X = 0)
hitkey: ldx     keys
@l:     lda     a:K_W,x
        beq     @no
        lda     ui_ev+2
        sec
        sbc     a:K_X,x
        bmi     @n
        cmp     a:K_W,x
        bcs     @n
        lda     ui_ev+4
        sec
        sbc     a:K_Y,x
        bmi     @n
        cmp     a:K_H,x
        bcs     @n
        sec
        rts
@n:     txa
        clc
        adc     #KSZ
        tax
        bra     @l
@no:    ldx     #0
        clc
        rts

; the key with code z:t0 -> C set, X
findkey:
        ldx     keys
:       lda     a:K_W,x
        beq     :+
        lda     a:K_CODE,x
        and     #$00FF
        cmp     z:t0
        beq     @y
        txa
        clc
        adc     #KSZ
        tax
        bra     :-
:       clc
        rts
@y:     sec
        rts

; X = key: C set if it is a digit the base does not have (Programmer). Keeps X.
keydim: lda     mode
        beq     @no
        lda     a:K_CODE,x
        and     #$00FF
        jsr     digval
        bcc     @no
        cmp     base
        bcs     @y
@no:    clc
        rts
@y:     sec
        rts

; A = code -> C set and A = its value if it is a digit (0-9, a-f)
digval: cmp     #'0'
        bcc     @no
        cmp     #'9' + 1
        bcs     :+
        sbc     #'0' - 1
        sec
        rts
:       cmp     #'a'
        bcc     @no
        cmp     #'f' + 1
        bcs     @no
        sbc     #'a' - 11
        sec
        rts
@no:    clc
        rts

drawall:
        jsr     uwin
        lda     #8                      ; the display's sunken frame
        sta     z:ui_x
        sta     z:ui_y
        lda     dw
        clc
        adc     #2
        sta     z:ui_w
        lda     dh
        clc
        adc     #2
        sta     z:ui_h
        lda     #1
        jsr     ui_bevel
        jsr     showdisp
drawkeys:
        ldx     keys
:       lda     a:K_W,x
        beq     :+
        phx
        lda     #0
        jsr     drawkey
        pla
        clc
        adc     #KSZ
        tax
        bra     :-
:       rts

uwin:   lda     win
        sta     z:ui_win
        rts

; X = key, A = 1 pressed: draw it (keeps nothing)
drawkey:
        sta     z:t5
        stx     z:t4
        jsr     uwin
        lda     a:K_X,x
        sta     z:ui_x
        lda     a:K_Y,x
        sta     z:ui_y
        lda     a:K_W,x
        sta     z:ui_w
        lda     a:K_H,x
        sta     z:ui_h
        lda     a:K_STY,x
        and     #$00FF
        asl     a
        tay
        lda     kfill,y                 ; colours: fill, pressed fill, ink
        sta     z:t6
        lda     kink,y
        sta     z:t7
        lda     z:t5
        beq     :+
        lda     z:t6
        xba
        sta     z:t6
:       jsr     keydim
        bcc     :+
        lda     #C_MID
        sta     z:t7
:       lda     #WD_FRAME | (C_DARK << 8)
        jsr     ui_rect
        inc     z:ui_x
        inc     z:ui_y
        dec     z:ui_w
        dec     z:ui_w
        dec     z:ui_h
        dec     z:ui_h
        lda     z:t6
        xba
        and     #$FF00
        ora     #WD_FILL
        jsr     ui_rect
        lda     z:t5
        jsr     ui_bevel
        lda     z:ui_x                  ; the centre (one pixel down right when pressed)
        clc
        adc     z:t5
        sta     z:ui_x
        lda     z:ui_y
        clc
        adc     z:t5
        sta     z:ui_y
        ldx     z:t4
        lda     a:K_LBL,x
        cmp     #32
        jcs     @text
        asl     a                       ; an icon: rectangles and lines around the centre
        tax
        lda     icons-2,x
        sta     z:t3
        lda     z:ui_w
        lsr     a
        clc
        adc     z:ui_x
        sta     z:t1                    ; centre x
        lda     z:ui_h
        lsr     a
        clc
        adc     z:ui_y
        sta     z:t2                    ; centre y
@op:    ldx     z:t3                    ; {u8 op, i8 x, y, then w, h (fill) or x2, y2 (line)}
        lda     a:0,x
        and     #$00FF
        beq     @out
        sta     z:t0
        lda     z:t7
        xba
        and     #$FF00
        ora     z:t0
        sta     kblk
        stz     kblk+2
        lda     a:1,x
        jsr     sext
        clc
        adc     z:t1
        sta     kblk+4
        lda     a:2,x
        jsr     sext
        clc
        adc     z:t2
        sta     kblk+6
        lda     a:3,x
        jsr     sext
        sta     kblk+8
        lda     a:4,x
        jsr     sext
        sta     kblk+10
        lda     z:t0
        cmp     #WD_LINE
        bne     :+
        lda     kblk+8
        clc
        adc     z:t1
        sta     kblk+8
        lda     kblk+10
        clc
        adc     z:t2
        sta     kblk+10
:       lda     win
        ptr     kblk
        sys     SYS_WDRAW
        lda     z:t3
        clc
        adc     #5
        sta     z:t3
        bra     @op
@out:   rts
@text:  sta     z:t3
        tax
        ldy     z:t4                    ; a digit key: in the big font
        lda     a:K_STY,y
        and     #$00FF
        jne     @utext                  ; (ST_DIG = 0)
        lda     a:1,x
        and     #$00FF
        jne     @utext
        lda     a:0,x
        and     #$00FF
        cmp     #'0'
        jcc     @utext
        jsr     bfind
        jcc     @utext
        txa                             ; its bitmap -> kgbuf (ink or KEYC), one KBLIT
        asl     a
        sta     z:t6
        asl     a
        asl     a
        asl     a
        sec
        sbc     z:t6
        clc
        adc     #.loword(bigfont)
        sta     z:gp
        ldx     #0
        ldy     #0
@gr:    sep     #$20
        .a8
        lda     (gp),y
        sta     z:gb
        phy
        ldy     #8
@gb:    lda     #KEYC
        asl     z:gb
        bcc     :+
        lda     z:t7
:       sta     kgbuf,x
        inx
        dey
        bne     @gb
        ply
        rep     #$20
        .a16
        iny
        cpy     #BIGH
        bcc     @gr
        lda     #WD_KBLIT
        sta     kblk
        lda     #KEYC
        sta     kblk+2
        lda     z:ui_w
        sec
        sbc     #8
        lsr     a
        clc
        adc     z:ui_x
        sta     kblk+4
        lda     z:ui_h
        sec
        sbc     #BIGH
        lsr     a
        clc
        adc     z:ui_y
        sta     kblk+6
        lda     #8
        sta     kblk+8
        lda     #BIGH
        sta     kblk+10
        lda     #.loword(kgbuf)
        sta     kblk+12
        lda     #^kgbuf
        sta     kblk+14
        lda     win
        ptr     kblk
        sys     SYS_WDRAW
        rts
@utext: ldx     z:t3
        lda     #0
        jsr     ui_twidth
        eor     #$FFFF
        sec
        adc     z:ui_w
        lsr     a
        clc
        adc     z:ui_x
        sta     z:ui_x
        lda     z:ui_h
        sec
        sbc     #9
        lsr     a
        clc
        adc     z:ui_y
        sta     z:ui_y
        stz     z:ui_font
        lda     z:t7
        and     #$00FF
        ora     #$FF00
        ldx     z:t3
        jmp     ui_text

; A's low byte, signed -> A
sext:   and     #$00FF
        cmp     #$80
        bcc     :+
        ora     #$FF00
:       rts

; ---------------------------------------------------------------- the display
; the strings (mkdisp), drawn in the picture buffer (bank dbank, dw x dh), one blit
showdisp:
        jsr     mkdisp
        lda     dw                      ; the paper
        sta     z:t0
        lda     dh
        sta     z:t1
        jsr     dclear
        lda     mode
        bne     @prog
        ldx     #.loword(nmem)          ; Standard: "M" while the memory holds a number
        jsr     n_isz
        beq     :+
        lda     #4
        sta     gx
        lda     #4
        sta     gy
        lda     #C_DSUB
        sta     gc
        ldx     #.loword(s_m)
        jsr     mstr
:       lda     #4
        bra     @xs
@prog:  lda     #3
@xs:    sta     gy                      ; the expression line, right-aligned
        ldx     #.loword(xstr)
        jsr     mwidth
        eor     #$FFFF
        sec
        adc     dw
        sec
        sbc     #5
        sta     gx
        lda     #C_DSUB
        sta     gc
        ldx     #.loword(xstr)
        jsr     mstr
        lda     err
        bne     @pan
        ldx     #.loword(dstr)          ; the number: big digits, or (too wide) small ones
        jsr     bwidth
        sta     z:t0
        lda     dw
        sec
        sbc     #10
        cmp     z:t0
        bcc     @small
        lda     dw
        sec
        sbc     #5
        sec
        sbc     z:t0
        sta     gx
        lda     bigy
        sta     gy
        lda     #C_DINK
        sta     gc
        ldx     #.loword(dstr)
        jsr     bstr
        bra     @pan
@small: ldx     #.loword(dstr)
        jsr     mwidth
        eor     #$FFFF
        sec
        adc     dw
        sec
        sbc     #5
        sta     gx
        lda     bigy
        clc
        adc     #4
        sta     gy
        lda     #C_DINK
        sta     gc
        ldx     #.loword(dstr)
        jsr     mstr
@pan:   lda     mode
        beq     @blit
        jsr     panel
@blit:  lda     #WD_BLIT
        sta     kblk
        stz     kblk+2
        lda     #9
        sta     kblk+4
        sta     kblk+6
        lda     dw
        sta     kblk+8
        lda     dh
        sta     kblk+10
        stz     kblk+12
        lda     dbank
        sta     kblk+14
        lda     win
        ptr     kblk
        sys     SYS_WDRAW
        lda     err                     ; an error: its message in the UI font
        beq     @out
        jsr     uwin
        asl     a
        tax
        lda     errmsg-2,x
        sta     z:t3
        tax
        lda     #0
        jsr     ui_twidth
        eor     #$FFFF
        sec
        adc     dw
        clc
        adc     #9 - 5
        sta     z:ui_x
        lda     bigy
        clc
        adc     #9 + 3
        sta     z:ui_y
        stz     z:ui_font
        lda     #C_DINK | (C_DBG << 8)
        ldx     z:t3
        jmp     ui_text
@out:   rts

; Programmer: the value in the four bases, the input's base marked
panel:  stz     z:t6                    ; line 0-3: HEX DEC OCT BIN
@l:     lda     z:t6
        asl     a
        tax
        lda     z:t6                    ; its top
        asl     a
        sta     z:t0
        asl     a
        asl     a
        clc
        adc     z:t0
        adc     #PANY
        sta     gy
        lda     #C_DSUB
        sta     gc
        lda     bases,x
        cmp     base
        bne     :+
        lda     gy                      ; the input's base: a bar
        dec     a
        dec     a
        sta     z:t1
        lda     #2
        sta     z:t0
        lda     #MINH + 3
        sta     z:t2
        lda     dw
        sec
        sbc     #4
        sta     z:t3
        lda     #C_SELECT
        jsr     dfill
        lda     #C_WHITE
        sta     gc
:       lda     #4
        sta     gx
        lda     z:t6
        asl     a
        asl     a
        clc
        adc     #.loword(s_hex)
        tax
        jsr     mstr
        lda     z:t6
        asl     a
        tax
        lda     bases,x
        cmp     #2
        beq     @bin
        jsr     fmtg                    ; grouped by 4 (hex, bin) or 3 (dec, oct)? (see fmtg)
        lda     #30
        sta     gx
        ldx     #.loword(gstr)
        jsr     mstr
        bra     @n
@bin:   lda     #30                     ; binary: 32 digits in eight groups
        sta     gx
        lda     #31
        sta     z:t0
@bit:   lda     z:t0                    ; bit t0 of px
        ldx     px
        cmp     #16
        bcc     :+
        sbc     #16
        ldx     px+2
:       tay
        txa
:       cpy     #0
        beq     :+
        lsr     a
        dey
        bra     :-
:       and     #1
        ora     #'0'
        sta     gstr
        ldx     #.loword(gstr)
        jsr     mstr
        lda     z:t0
        and     #3
        bne     :+
        lda     gx
        clc
        adc     #3
        sta     gx
:       dec     z:t0
        bpl     @bit
@n:     inc     z:t6
        lda     z:t6
        cmp     #4
        jcc     @l
        rts

; the value px in base A -> gstr, digits in groups (hex by 4, decimal and octal by 3)
fmtg:   pha
        lda     px
        sta     pv
        lda     px+2
        sta     pv+2
        pla
        pha
        jsr     i_fmt
        pla
        ldx     #4
        cmp     #16
        beq     :+
        ldx     #3
:       stx     z:t1
        ldx     #.loword(istr)
        jsr     ui_strlen
        tay                             ; Y = the source's end, digits counted from the right
        ldx     #0
        stz     z:t2
        lda     istr                    ; (a sign stays in front)
        and     #$00FF
        cmp     #'-'
        bne     :+
        sta     gstr
        inx
:       stx     z:t3                    ; the first digit's index in istr
        tya
        sec
        sbc     z:t3
        sta     z:t0                    ; digits
        ldy     z:t3
@c:     cpy     #40
        bcs     @e
        lda     istr,y
        and     #$00FF
        beq     @e
        sep     #$20
        .a8
        sta     gstr,x
        rep     #$20
        .a16
        inx
        iny
        dec     z:t0                    ; a space before each group but the first
        beq     @c
        lda     z:t0
        sta     z:t2
:       lda     z:t2
        sec
        sbc     z:t1
        bcc     :+
        sta     z:t2
        bra     :-
:       adc     z:t1                    ; (C clear)
        bne     @c
        lda     #' '
        sep     #$20
        .a8
        sta     gstr,x
        rep     #$20
        .a16
        inx
        bra     @c
@e:     sep     #$20
        .a8
        stz     gstr,x
        rep     #$20
        .a16
        rts

; the buffer: t0 x t1 filled with the paper
dclear: stz     z:t0
        stz     z:t1
        lda     dw
        sta     z:t3
        lda     dh
        sta     z:t2
        lda     #C_DBG
        ; fall through
; the rectangle t0, t1 (x, y), t3 x t2 (w x h) of the buffer in colour A
dfill:  sta     z:gb
        lda     z:t1
        jsr     rowoff
        clc
        adc     z:t0
        sta     z:bp
        lda     dbank
        sta     z:bp+2
        ldx     z:t2
@r:     ldy     z:t3
        dey
        sep     #$20
        .a8
        lda     z:gb
:       sta     [bp],y
        dey
        bpl     :-
        rep     #$20
        .a16
        lda     z:bp
        clc
        adc     dw
        sta     z:bp
        dex
        bne     @r
        rts

; A = row -> A = row * dw
rowoff: tax
        lda     #0
:       cpx     #0
        beq     :+
        clc
        adc     dw
        dex
        bra     :-
:       rts

; the string X in the big font at gx, gy, colour gc (gx advances)
bstr:   stx     z:sptr
@c:     lda     (sptr)
        and     #$00FF
        beq     @out
        jsr     bfind
        bcc     @n
        sta     z:t5
        txa                             ; the bitmap: index * 14
        asl     a
        sta     z:t6
        asl     a
        asl     a
        asl     a
        sec
        sbc     z:t6
        clc
        adc     #.loword(bigfont)
        sta     z:gp
        lda     #BIGH
        sta     z:gh
        jsr     glyph
        lda     gx
        clc
        adc     z:t5
        sta     gx
@n:     inc     z:sptr
        bra     @c
@out:   rts
; A = character -> C set: X = its index in the big font, A = its advance
bfind:  sta     z:gb
        ldx     #0
:       lda     bigch,x
        and     #$00FF
        cmp     z:gb
        beq     :+
        inx
        cpx     #NBIG
        bcc     :-
        clc
        rts
:       lda     #10
        cpx     #DOTIDX
        bne     :+
        lda     #5
:       sec
        rts

; the width of string X in the big font
bwidth: stx     z:sptr
        stz     z:t5
@c:     lda     (sptr)
        and     #$00FF
        beq     @out
        jsr     bfind
        bcc     :+
        clc
        adc     z:t5
        sta     z:t5
:       inc     z:sptr
        bra     @c
@out:   lda     z:t5
        beq     :+
        dec     a                       ; (no gap after the last)
        dec     a
:       rts

; the string X in the small font at gx, gy, colour gc (gx advances)
mstr:   stx     z:sptr
@c:     lda     (sptr)
        and     #$00FF
        beq     @out
        cmp     #' '
        beq     @sp
        sta     z:gb
        ldx     #0
:       lda     minch,x
        and     #$00FF
        cmp     z:gb
        beq     :+
        inx
        cpx     #NMIN
        bcc     :-
        bra     @n
:       txa                             ; x * 7
        asl     a
        asl     a
        asl     a
        stx     z:gb
        sec
        sbc     z:gb
        clc
        adc     #.loword(minfont)
        sta     z:gp
        lda     #MINH
        sta     z:gh
        jsr     glyph
@sp:    lda     gx
        clc
        adc     #6
        sta     gx
@n:     inc     z:sptr
        bra     @c
@out:   rts

; the width of string X in the small font
mwidth: jsr     ui_strlen
        sta     z:t0
        asl     a
        clc
        adc     z:t0
        asl     a                       ; 6 a character
        beq     :+
        dec     a
:       rts

; a glyph: gh rows of 8 pixels (bit 7 the left one) at gp -> the buffer at gx, gy in gc
glyph:  lda     gy
        jsr     rowoff
        clc
        adc     gx
        sta     z:bp
        lda     dbank
        sta     z:bp+2
        ldx     #0
@r:     txy
        lda     (gp),y
        sep     #$20
        .a8
        sta     z:gb
        ldy     #0
@b:     asl     z:gb
        bcc     :+
        lda     gc
        sta     [bp],y
:       iny
        lda     z:gb
        bne     @b
        rep     #$20
        .a16
        lda     z:bp
        clc
        adc     dw
        sta     z:bp
        inx
        cpx     z:gh
        bcc     @r
        rts

        .include "calc_num.s"
        .include "calc_eng.s"
        .include "calc_data.s"
