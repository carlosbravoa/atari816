; SETTINGS - the system settings panel (/BIN/SETTINGS.PRG).
;
;   settings          the "Settings" window, two pages chosen by the two buttons at its top:
;                     Desktop: desktop colour, mouse speed, key repeat, alert volume, sound
;                       volume, (0.24) the screen saver (Off, 1, 5, 10 minutes; Test starts
;                       /SYSTEM/SAVER.PRG at once). Every change applies at once (the desktop
;                       recolours live).
;                     Classic Atari: the I/O processor's /atari.ini (memory, keyboard layout,
;                       arrow keys as joystick, scanlines, horizontal position, boot
;                       cartridge, (0.27) BASIC when a disk boots, fast disk loading). These
;                       apply at the next full restart. (0.27: no stereo
;                       row: REV $0C has one POKEY for the classic machine, so the core's
;                       stereo key does nothing; a stereo line in the file is kept as it is.)
;                     Save writes /SYSTEM/CONFIG (and /atari.ini when a Classic Atari value
;                     changed: then it offers to restart now) and closes; Cancel (Esc, the
;                     close box) puts back the values the panel started with and writes
;                     nothing; Defaults sets the factory values of the page shown (still to
;                     be saved or cancelled). One instance only (SYS_SINGLE).
;   settings atari    (0.15) the same, opened on its Classic Atari page (the Desktop's
;                     "Atari settings...")
;   settings apply    reads /SYSTEM/CONFIG and applies it, no window, no output, exit 0
;                     (DESK runs this at start). No file: nothing happens.
;
; /SYSTEM/CONFIG: plain text, one "key=value" per line (LF or CR LF), decimal numbers.
; Unknown lines (and "#" comments) are ignored; a key missing keeps its default; values
; out of range are clamped. The keys, with the defaults:
;   desk=36,92,112          desktop colour (palette 2, C_DESK): red, green, blue 0-255
;   desk2=46,104,124        its checker partner (palette 3, C_DESK2); both are stored, the
;                           presets keep it about (10, 12, 12) lighter than desk
;   mouse=1                 mouse speed 1-4
;   beep=8                  alert (beep) volume 0-15, kernel setting 1 (0: the alert chimes
;                           and the error beep are silent)
;   repeat_delay=40         key repeat delay in 10 ms ticks, 0-250 (0: no repeat)
;   repeat_rate=5           key repeat interval in 10 ms ticks, 1-100
;   sound=8                 (0.18) sound volume 0-15, kernel setting 4: Lau's master volume
;                           (value x 17), which every program's samples follow
;   saver=300               (0.24) the screen saver's delay in seconds, 0-3600 (0 = off),
;                           kernel setting 5; the panel offers 0, 60, 300 and 600 (another
;                           value, e.g. a test's few seconds, shows no button chosen)
; Save writes all of them (the file is rebuilt; other lines are not kept). The panel reads
; the live kernel values for the last six and the file (or the defaults) for the desktop
; colours (the kernel has no call to read the palette back).
;
; /atari.ini (read by the I/O processor at power-on and at a full restart; its parser is
; load_option() in core/firmware/firmware.c, mirrored here): one "key=value" per line, LF or
; CR LF; blanks around key and value ignored; empty lines and lines starting with "[", ";"
; or "#" skipped; keys case-sensitive; a line without "=" ends the reading (the keys after
; it keep their defaults); values read with C atoi. The keys, with the defaults:
;   ram=128                 128 or 320 (KB; no key: 128, anything else: 320; 0.16: the
;                           core has only these two since REV $0A)
;   kbdlayout=0             0 Atari key positions, non-zero US PC symbols
;   joystick=0              non-zero: the arrow keys drive joystick 1 (Left Alt = fire)
;   scanlines=0             value & 3: 0 off, 1 25 %, 2 50 %, 3 75 %
;   boot=basic              "ash": /ASH.CAR is the default cartridge; anything else: BASIC
;   hpos=0                  horizontal position, clamped to 0-48
;   basic=1                 (0.27) non-zero: BASIC present when a disk boots (as the real
;                           machine); 0: a disk in D1: boots without BASIC (most games)
;   fastdisk=1              (0.27) non-zero: sector reads through the fast disk (a PBI
;                           device); 0: every disk access over the serial port
; Save rewrites only the lines of these keys (every line of a key: the last one counts),
; keeps every other line as it is, and appends the keys missing (CR LF if the file uses it).
        .include "horizon.inc"
        .include "ui.inc"

T       = 32                            ; the page selector's height (above the pages)
W       = 360                           ; content size
H       = T + 288
CX      = 112                           ; the controls' column (labels at LX)
LX      = 12
CW      = 236                           ; the controls' column width
TABY    = 8                             ; the page buttons
TABW    = 104
NSW     = 10                            ; desktop colour presets
SWX     = CX                            ; swatches: 20 x 20, every 24 pixels
SWY     = T + 12
SWS     = 20
SWP     = 24
R_MOUSE = T + 44                        ; row tops
R_DELAY = T + 72
R_RATE  = T + 100
R_TRY   = T + 128
R_BEEP  = T + 156
R_SND   = T + 184
R_SAVER = T + 212                       ; (0.24)
SEPY    = T + 244
R_BTN   = T + 256
RA      = T + 8                         ; the Classic Atari rows: every 24 pixels
RA_RAM  = RA
RA_KBD  = RA + 24                       ; (0.27: the stereo row is gone)
RA_JOY  = RA + 48
RA_SCAN = RA + 72
RA_HPOS = RA + 96
RA_BOOT = RA + 120
RA_BAS  = RA + 144                      ; (0.27) BASIC when a disk boots
RA_FAST = RA + 168                      ; (0.27) fast disk loading
VOLX    = 264                           ; the volume's number, right-aligned in 20 pixels
FBMAX   = 1024
AMAX    = 4096                          ; /atari.ini at most AMAX - 1 bytes
NAK     = 8                             ; its keys
AV_HPOS = 10                            ; aval offsets
AV_BOOT = 8
AV_BAS  = 12                            ; (0.27)
AV_FAST = 14
NSET    = 6                             ; kernel settings 0-5 in val (words)
SNDN    = 3200                          ; the sound Test sample: 0.2 s at 16 kHz, 8-bit

        .segment "CODE"
        .a16
        .i16
start:  sta     argl
        stx     argx
        jsr     load_cfg
        lda     argl                    ; "apply"?
        beq     panel
        ldx     argx
        jsr     args_init
        jsr     str_skip
        ldy     #0
:       lda     s_apply,y
        and     #$00FF
        beq     :+
        sta     z:t0
        lda     [u_p],y
        and     #$00FF
        cmp     z:t0
        bne     panel
        iny
        bra     :-
:       lda     [u_p],y
        and     #$00FF
        beq     :+
        cmp     #' '
        bne     panel
:       lda     cfgok
        beq     :+
        jsr     apply_all
:       lda     #0
        sys     SYS_EXIT

; C set if the argument is the word X
isarg:  stx     z:t0
        lda     argl
        beq     @no
        ldx     argx
        jsr     args_init
        jsr     str_skip
        ldy     #0
:       lda     (t0),y
        and     #$00FF
        beq     :+
        sta     z:t1
        lda     [u_p],y
        and     #$00FF
        cmp     z:t1
        bne     @no
        iny
        bra     :-
:       lda     [u_p],y
        and     #$00FF
        beq     :+
        cmp     #' '
        bne     @no
:       sec
        rts
@no:    clc
        rts

; ---------------------------------------------------------------- the panel
panel:  sys     SYS_SINGLE              ; one Settings: another one runs (raised): done
        bcc     :+
        cmp     #ERUNNING
        bne     :+
        lda     #0
        sys     SYS_EXIT
:       sys     SYS_WSSTART
        bcc     :+
        print   "settings: no window system\n"
        exit    1
:       sta     wsown
        jsr     ui_init
        jsr     load_ini
        ldx     #0                      ; the live kernel values
:       phx
        txa
        lsr     a
        ldx     #$FFFF
        sys     SYS_SETTING
        plx
        sta     val,x
        inx
        inx
        cpx     #NSET * 2
        bne     :-
        ldx     #.loword(cur)           ; what Cancel puts back
        ldy     #.loword(orig)
        jsr     copy16
        ptr     wblk
        sys     SYS_WOPEN
        bcc     :+
        jsr     stopws
        print   "settings: no window\n"
        exit    1
:       sta     win
        ldy     #0                      ; the controls are in it
:       ldx     allc,y
        beq     :+
        sep     #$20
        .a8
        lda     win
        sta     a:CT_WIN,x
        rep     #$20
        .a16
        iny
        iny
        bra     :-
:       lda     val+2
        sta     sb_vol+SB_POS
        lda     val+8
        sta     sb_snd+SB_POS
        lda     aval+AV_HPOS
        sta     sb_hpos+SB_POS
        lda     #T                      ; the line under the page buttons (etched)
        jsr     etch
        lda     #SEPY                   ; the line above the buttons
        jsr     etch
        stz     page
        ldx     #.loword(s_atari)       ; (0.15) "settings atari": the Classic Atari page
        jsr     isarg
        bcc     :+
        inc     page
:       jsr     showpage

loop:   lda     #0
        jsr     ui_getev
        bcs     loop
        jsr     curlist
        jsr     ui_event
        cmp     #UA_CLICK
        jeq     onclick
        cmp     #UA_CHANGE
        bne     :+
        cpx     #.loword(sb_hpos)
        bne     @vol
        lda     sb_hpos+SB_POS          ; the horizontal position
        sta     aval+AV_HPOS
        jsr     draw_hpos
        bra     @rel
@vol:   cpx     #.loword(sb_vol)
        bne     @snd
        lda     sb_vol+SB_POS           ; the beep volume
        sta     val+2
        tax
        lda     #1
        sys     SYS_SETTING
        jsr     draw_vol
        bra     @rel
@snd:   cpx     #.loword(sb_snd)
        bne     @rel
        lda     sb_snd+SB_POS           ; (0.18) the sound volume
        sta     val+8
        tax
        lda     #4
        sys     SYS_SETTING
        jsr     draw_snd
        bra     @rel
:       cmp     #UA_NONE
        bne     @rel
        lda     ui_ev
        and     #$00FF
        cmp     #WE_CLOSE
        jeq     cancel
        cmp     #WE_BUTTON
        bne     loop
        lda     ui_ev+6
        and     #1
        bne     onpress
@rel:   lda     ui_ev                   ; a release: a toggle the library drew raised
        and     #$00FF                  ; (pressed, then left) shows its state again
        cmp     #WE_BUTTON
        jne     loop
        lda     ui_ev+6
        and     #1
        jne     loop
        jsr     sync_flags
        jmp     loop

; a press outside the controls: a swatch (Desktop page)?
onpress:
        lda     page
        jne     loop
        lda     ui_ev+4
        sec
        sbc     #SWY
        bmi     @no
        cmp     #SWS
        bcs     @no
        lda     ui_ev+2
        sec
        sbc     #SWX
        bpl     :+
@no:    jmp     loop
:
        ldx     #0
:       cmp     #SWP
        bcc     :+
        sbc     #SWP
        inx
        bra     :-
:       cmp     #SWS
        jcs     loop
        cpx     #NSW
        jcs     loop
        txa                             ; preset X: 6 bytes
        asl     a
        sta     z:t0
        asl     a
        adc     z:t0
        tax
        lda     presets,x
        sta     desk
        lda     presets+2,x
        sta     desk+2
        lda     presets+4,x
        sta     desk+4
        jsr     setpal
        jsr     draw_sw
        jmp     loop

; UA_CLICK on button X
onclick:
        cpx     #.loword(b_save)
        jeq     do_save
        cpx     #.loword(b_cancel)
        jeq     cancel
        cpx     #.loword(b_test)
        bne     :+
        lda     #CH_INFO                ; (0.16) the information chime at the chosen
        ldx     val+2                   ; volume (0.15 played all four in a row)
        sys     SYS_CHIME
        jmp     loop
:       cpx     #.loword(b_stest)
        bne     :+
        jsr     snd_test
        jmp     loop
:       cpx     #.loword(b_svtest)      ; (0.24) the screen saver now
        bne     :+
        ldx     #.loword(p_saver)
        ldy     #0
        lda     #0
        jsr     ui_launch
        jmp     loop
:       cpx     #.loword(b_dflt)
        bne     @tog
        lda     page
        bne     :+
        ldx     #.loword(dflt)          ; Desktop: the factory values, applied
        ldy     #.loword(cur)
        jsr     copy16
        jsr     apply_all
        jsr     redraw_vals
        jmp     loop
:       ldx     #.loword(adflt)         ; Classic Atari: the firmware's defaults
        ldy     #.loword(aval)
        jsr     copya
        jsr     redraw_atari
        jmp     loop
@tog:   stx     z:t0                    ; a toggle: which group, which button
        jsr     curgrp
@g:     lda     (gp)
        jeq     loop
        sta     z:t2
        lda     z:t0
        sec
        sbc     z:t2
        bcc     @n
        ldx     #0
:       cmp     #BT_SIZE
        bcc     :+
        sbc     #BT_SIZE
        inx
        bra     :-
:       txa
        ldy     #2
        cmp     (gp),y
        bcs     @n
        asl     a
        ldy     #4
        clc
        adc     (gp),y
        tax
        lda     a:0,x                   ; its value
        sta     z:t1
        ldy     #6                      ; -> the group's variable
        lda     (gp),y
        tax
        lda     z:t1
        sta     a:0,x
        cpx     #.loword(page)
        bne     :+
        jsr     showpage                ; a page button
        jmp     loop
:       txa                             ; a kernel setting (cur + 0 .. 9)?
        sec
        sbc     #.loword(cur)
        cmp     #NSET * 2
        bcs     :+
        lsr     a
        ldx     z:t1
        sys     SYS_SETTING
:       jsr     sync_flags
        jmp     loop
@n:     lda     z:gp
        clc
        adc     #8
        sta     z:gp
        bra     @g

cancel: ldx     #.loword(orig)
        ldy     #.loword(cur)
        jsr     copy16
        jsr     apply_all
quit:   lda     win
        sys     SYS_WCLOSE
        jsr     stopws
        exit    0

stopws: lda     wsown
        beq     :+
        sys     SYS_WSSTOP
:       rts

; Save: /atari.ini when a Classic Atari value changed, /SYSTEM/CONFIG, then close (a failure:
; an alert, the panel stays); after a new /atari.ini: "Restart now" or "Later"
do_save:
        ldx     #0                      ; a Classic Atari value changed?
:       lda     aval,x
        cmp     aorig,x
        bne     @ini
        inx
        inx
        cpx     #NAK * 2
        bcc     :-
        bra     @cfg
@ini:   lda     aerr                    ; (the file could not be read: not overwritten)
        bne     @aerr
        jsr     abuild
        ptr     p_ini
        jsr     wfile
        bcs     @aerr
        ldx     #.loword(aval)          ; saved: now the file's values
        ldy     #.loword(aorig)
        jsr     copya
        lda     #1
        sta     rpend
@cfg:   jsr     build
        ptr     p_cfg
        jsr     wfile
        bcs     @err
        lda     rpend
        jeq     quit
        ldx     #.loword(al_rst)        ; Restart now / Later
        jsr     ui_alert
        cmp     #0
        jne     quit
        lda     #SR_FULLRESTART         ; the Desktop closes everything and restarts
        sys     SYS_SYSREQ
        jcc     quit
        lda     #1                      ; no Desktop: the full restart ourselves
        sys     SYS_RESTART
        ldx     #.loword(al_rerr)       ; (it returned: it failed)
        jsr     ui_alert
        jmp     quit
@aerr:  ldx     #.loword(al_aerr)
        bra     :+
@err:   ldx     #.loword(al_err)
:       jsr     ui_alert
        jmp     loop

; X, Y = path: obuf (olen bytes) written to it (created / truncated). C set: failed.
wfile:  lda     #O_CREATE
        sys     SYS_OPEN
        bcs     @out
        sta     fh
        sta     rw
        lda     #.loword(obuf)
        sta     rw+1
        lda     #^obuf
        sta     rw+3
        lda     olen
        sta     rw+4
        ptr     rw
        sys     SYS_WRITE
        bcs     @werr
        cmp     olen
        bne     @werr
        lda     fh
        sys     SYS_CLOSE
@out:   rts
@werr:  lda     fh
        sys     SYS_CLOSE
        sec
        rts

; ---------------------------------------------------------------- pages
; the current page's control list -> X, its group table -> gp
curlist:
        lda     page
        asl     a
        tax
        lda     plists,x
        tax
        rts
curgrp: lda     page
        asl     a
        tax
        lda     pgrps,x
        sta     z:gp
        rts

; page: the area under the page buttons cleared, its controls drawn
showpage:
        lda     #1
        sys     SYS_WSHOLD
        jsr     curgrp                  ; the toggles drawn plain first (sync_flags
@c:     lda     (gp)                    ; marks the current ones)
        beq     @d
        sta     z:bp
        ldy     #2
        lda     (gp),y
        sta     z:cnt
:       ldx     z:bp
        lda     a:CT_FLAGS,x
        and     #$FFFF ^ UF_PRESSED
        sta     a:CT_FLAGS,x
        txa
        clc
        adc     #BT_SIZE
        sta     z:bp
        dec     z:cnt
        bne     :-
        lda     z:gp
        clc
        adc     #8
        sta     z:gp
        bra     @c
@d:     lda     win
        sta     z:ui_win
        stz     z:ui_x
        lda     #T + 2
        sta     z:ui_y
        lda     #W
        sta     z:ui_w
        lda     #SEPY - T - 2
        sta     z:ui_h
        lda     #WD_FILL | (C_BODY << 8)
        jsr     ui_rect
        jsr     curlist
        jsr     ui_drawall
        jsr     sync_flags
        lda     page
        bne     :+
        jsr     draw_sw
        jsr     draw_vol
        jsr     draw_snd
        bra     :++
:       jsr     draw_hpos
:       lda     #0
        sys     SYS_WSHOLD
        rts

; an etched line across the window at y = A
etch:   sta     z:ui_y
        lda     win
        sta     z:ui_win
        lda     #LX
        sta     z:ui_x
        lda     #W - 2 * LX
        sta     z:ui_w
        lda     #1
        sta     z:ui_h
        lda     #WD_FILL | (C_MID << 8)
        jsr     ui_rect
        inc     z:ui_y
        lda     #WD_FILL | (C_WHITE << 8)
        jmp     ui_rect

; ---------------------------------------------------------------- drawing
; the toggles' UF_PRESSED = "is the current value"; redraw those that changed (the groups
; of the page shown)
sync_flags:
        jsr     curgrp
@g:     lda     (gp)
        beq     @out
        sta     z:bp
        ldy     #2
        lda     (gp),y
        sta     z:cnt
        ldy     #4
        lda     (gp),y
        sta     z:vp
        ldy     #6
        lda     (gp),y
        tax
        lda     a:0,x
        sta     z:want
@b:     lda     (vp)
        cmp     z:want
        bne     :+
        lda     #UF_PRESSED
        bra     :++
:       lda     #0
:       sta     z:t0
        ldx     z:bp
        lda     a:CT_FLAGS,x
        and     #UF_PRESSED
        cmp     z:t0
        beq     :+
        lda     a:CT_FLAGS,x
        eor     #UF_PRESSED
        sta     a:CT_FLAGS,x
        jsr     ui_draw
        ldx     z:bp
        lda     a:CT_FLAGS,x
        and     #UF_PRESSED
        beq     :+
        jsr     selpaint
:       lda     z:bp
        clc
        adc     #BT_SIZE
        sta     z:bp
        inc     z:vp
        inc     z:vp
        dec     z:cnt
        bne     @b
        lda     z:gp
        clc
        adc     #8
        sta     z:gp
        bra     @g
@out:   rts

; button X (drawn pressed by the library): the selected look, C_SELECT with a white label
selpaint:
        lda     win
        sta     z:ui_win
        lda     a:CT_X,x
        inc     a
        inc     a
        sta     z:ui_x
        lda     a:CT_Y,x
        inc     a
        inc     a
        sta     z:ui_y
        lda     a:CT_W,x
        sec
        sbc     #4
        sta     z:ui_w
        lda     a:CT_H,x
        sec
        sbc     #4
        sta     z:ui_h
        lda     #WD_FILL | (C_SELECT << 8)
        jsr     ui_rect
        ldx     z:bp
        lda     a:BT_LABEL,x
        tax
        lda     #0
        jsr     ui_twidth
        sta     z:t0
        ldx     z:bp
        lda     a:CT_W,x
        sec
        sbc     z:t0
        lsr     a
        clc
        adc     a:CT_X,x
        sta     z:ui_x
        lda     a:CT_H,x
        sec
        sbc     #8
        lsr     a
        clc
        adc     a:CT_Y,x
        sta     z:ui_y
        stz     z:ui_font
        lda     a:BT_LABEL,x
        tax
        lda     #C_WHITE | ($FF << 8)
        jmp     ui_text

; after Defaults (Classic Atari page)
redraw_atari:
        jsr     sync_flags
        ldx     #.loword(sb_hpos)
        lda     aval+AV_HPOS
        jsr     ui_sbset
        jmp     draw_hpos

; after Defaults (Desktop page): every control shows the values
redraw_vals:
        jsr     sync_flags
        ldx     #.loword(sb_vol)
        lda     val+2
        jsr     ui_sbset
        jsr     draw_vol
        ldx     #.loword(sb_snd)
        lda     val+8
        jsr     ui_sbset
        jsr     draw_snd
        ; fall through
; the colour swatches, the current one in a black ring
draw_sw:
        lda     win
        sta     z:ui_win
        ldx     #0                      ; sel = the preset equal to desk ($FFFF none)
        ldy     #0
@s:     lda     presets,x
        cmp     desk
        bne     :+
        lda     presets+2,x
        cmp     desk+2
        bne     :+
        lda     presets+4,x
        cmp     desk+4
        beq     @f
:       txa
        clc
        adc     #6
        tax
        iny
        cpy     #NSW
        bcc     @s
        ldy     #$FFFF
@f:     sty     z:sel
        stz     z:i
@l:     lda     z:i                     ; x = SWX + 24 i
        asl     a
        asl     a
        asl     a
        sta     z:t0
        asl     a
        adc     z:t0
        adc     #SWX
        sta     z:sx
        ldx     #C_BODY << 8
        lda     z:i
        cmp     z:sel
        bne     :+
        ldx     #C_BLACK << 8
:       stx     z:rc
        lda     z:sx                    ; the ring: 2 pixels, 1 pixel outside the frame
        sec
        sbc     #3
        sta     z:ui_x
        lda     #SWY - 3
        sta     z:ui_y
        lda     #SWS + 6
        sta     z:ui_w
        sta     z:ui_h
        lda     z:rc
        ora     #WD_FRAME
        jsr     ui_rect
        inc     z:ui_x
        inc     z:ui_y
        dec     z:ui_w
        dec     z:ui_w
        dec     z:ui_h
        dec     z:ui_h
        lda     z:rc
        ora     #WD_FRAME
        jsr     ui_rect
        lda     z:sx                    ; the frame
        sta     z:ui_x
        lda     #SWY
        sta     z:ui_y
        lda     #SWS
        sta     z:ui_w
        sta     z:ui_h
        lda     #WD_FRAME | (C_DARK << 8)
        jsr     ui_rect
        inc     z:ui_x                  ; the colour: a checker of two system colours
        inc     z:ui_y
        lda     #SWS - 2
        sta     z:ui_w
        sta     z:ui_h
        lda     z:i
        asl     a
        tax
        lda     swcol,x
        xba
        and     #$00FF
        sta     z:ui_c2
        lda     swcol,x
        xba
        and     #$FF00
        ora     #WD_DITHER
        jsr     ui_rect
        inc     z:i
        lda     z:i
        cmp     #NSW
        jcc     @l
        rts

; the beep volume's number, right-aligned left of the Test button
draw_vol:
        lda     val+2
        ldx     #R_BEEP + 6
        bra     draw_num
; (0.18) the sound volume's number, the same in its row
draw_snd:
        lda     val+8
        ldx     #R_SND + 6
        bra     draw_num
; the horizontal position's number, right of its scroll bar
draw_hpos:
        lda     aval+AV_HPOS
        ldx     #RA_HPOS + 6
; number A right-aligned in 20 pixels at VOLX, y = X
draw_num:
        stx     z:sx
        ldy     #0
        jsr     pnum
        lda     #0
        jsr     pchr
        lda     win
        sta     z:ui_win
        lda     #VOLX
        sta     z:ui_x
        lda     z:sx
        sta     z:ui_y
        lda     #20
        sta     z:ui_w
        lda     #UI_LINE
        sta     z:ui_h
        lda     #WD_FILL | (C_BODY << 8)
        jsr     ui_rect
        ldx     #.loword(obuf)
        lda     #0
        jsr     ui_twidth
        eor     #$FFFF
        sec
        adc     #VOLX + 20
        sta     z:ui_x
        stz     z:ui_font
        ldx     #.loword(obuf)
        lda     #C_BLACK | (C_BODY << 8)
        jmp     ui_text

; ---------------------------------------------------------------- the sound Test
; (0.18) a short soft tone through Lau at the chosen sound volume (Lau's master volume
; follows setting 4); without Lau (ENODEV) the information chime at that volume
snd_test:
        jsr     gensnd
        ptr     spb
        sys     SYS_SPLAY
        bcc     @out
        cmp     #ENODEV
        bne     @out
        lda     #CH_INFO
        ldx     val+8
        sys     SYS_CHIME
@out:   rts

; snd, once: SNDN samples of tone (a sine and a little of its octave, 24 samples a period:
; 667 Hz at 16 kHz), its level falling by 1/16 every 64 samples (to about 4 % at the end)
gensnd: lda     sndok
        bne     @out
        inc     sndok
        lda     #255
        sta     z:env
        stz     z:i
        ldy     #0
@s:     ldx     z:i
        lda     tone,x
        and     #$00FF
        cmp     #$80                    ; C: negative
        php
        bcc     :+
        eor     #$00FF                  ; |s|
        inc     a
:       sta     z:t0                    ; |s| * env / 256
        lda     z:env
        xba
        sta     z:t1
        lda     #0
        ldx     #8
@m:     asl     a
        asl     z:t1
        bcc     :+
        clc
        adc     z:t0
:       dex
        bne     @m
        xba
        and     #$00FF
        plp
        bcc     :+
        eor     #$FFFF
        inc     a
:       sep     #$20
        .a8
        sta     snd,y
        rep     #$20
        .a16
        inc     z:i
        lda     z:i
        cmp     #24
        bcc     :+
        stz     z:i
:       iny
        tya
        and     #63
        bne     :+
        lda     z:env                   ; env -= env / 16
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        sta     z:t0
        lda     z:env
        sec
        sbc     z:t0
        sta     z:env
:       cpy     #SNDN
        bcc     @s
@out:   rts

; ---------------------------------------------------------------- settings
; every value of cur to the kernel
apply_all:
        ldx     #0
:       phx
        txa
        lsr     a
        pha
        lda     val,x
        tax
        pla
        sys     SYS_SETTING
        plx
        inx
        inx
        cpx     #NSET * 2
        bne     :-
        ; fall through
; the desktop colours (palette 2 and 3)
setpal: lda     #C_DESK
        ldx     desk                    ; red | green << 8
        ldy     desk+2
        jsr     @one
        lda     #C_DESK2
        ldx     desk+3
        ldy     desk+5
@one:   pha
        tya
        and     #$00FF
        tay
        pla
        sys     SYS_WSPAL
        rts

; 18 bytes X -> Y (cur, orig, dflt)
copy16: lda     #8
        bra     :+
; 16 bytes X -> Y (aval, aorig, adflt)
copya:  lda     #7
:       sta     z:t0
:       lda     a:0,x
        sta     a:0,y
        inx
        inx
        iny
        iny
        dec     z:t0
        bpl     :-
        rts

; the defaults, then /SYSTEM/CONFIG if there is one (cfgok = 1)
load_cfg:
        ldx     #.loword(dflt)
        ldy     #.loword(cur)
        jsr     copy16
        stz     cfgok
        ptr     p_cfg
        lda     #O_READ
        sys     SYS_OPEN
        bcs     @out
        sta     fh
        sta     rw
        lda     #.loword(fbuf)
        sta     rw+1
        lda     #^fbuf
        sta     rw+3
        lda     #FBMAX - 1
        sta     rw+4
        ptr     rw
        sys     SYS_READ
        bcc     :+
        lda     #0
:       sta     z:t0
        lda     fh
        sys     SYS_CLOSE
        ldx     z:t0
        sep     #$20
        .a8
        stz     fbuf,x
        rep     #$20
        .a16
        lda     #1
        sta     cfgok
        jsr     parse
@out:   rts

; the lines of fbuf (zero-terminated) -> cur
parse:  lda     #.loword(fbuf)
        sta     z:q
@line:  lda     (q)
        and     #$00FF
        jeq     @done
        ldx     #0                      ; which key starts the line?
@key:   lda     keys,x
        jeq     @skip
        sta     z:kp
        ldy     #0
:       lda     (kp),y
        and     #$00FF
        beq     @hit
        sta     z:t0
        lda     (q),y
        and     #$00FF
        cmp     z:t0
        bne     @nk
        iny
        bra     :-
@nk:    inx
        inx
        bra     @key
@hit:   tya                             ; past "key="
        clc
        adc     z:q
        sta     z:q
        stx     z:k
        cpx     #4
        bcs     @num
        jsr     getnum                  ; desk / desk2: three numbers 0-255
        bcs     @skip
        sta     c0
        jsr     getnum
        bcs     @skip
        sta     c0+2
        jsr     getnum
        bcs     @skip
        sta     c0+4
        lda     z:k                     ; desk + 0 / 3
        lsr     a
        sta     z:t0
        asl     a
        adc     z:t0
        tax
        ldy     #0
:       lda     c0,y
        cmp     #256
        bcc     :+
        lda     #255
:       sep     #$20
        .a8
        sta     desk,x
        rep     #$20
        .a16
        inx
        iny
        iny
        cpy     #6
        bcc     :--
        bra     @skip
@num:   jsr     getnum                  ; one number, clamped to its range
        bcs     @skip
        pha
        lda     z:k                     ; lims + 4 (key - 2), val + 2 (key - 2)
        asl     a
        tay
        pla
        cmp     lims-8,y
        bcs     :+
        lda     lims-8,y
:       cmp     lims-8+2,y
        bcc     :+
        lda     lims-8+2,y
:       ldx     z:k
        sta     val-4,x
@skip:  lda     (q)                     ; to the next line
        and     #$00FF
        beq     @done
        inc     z:q
        cmp     #10
        bne     @skip
        jmp     @line
@done:  rts

; a decimal number at (q) (spaces before it, a comma after it skipped) -> A, C set: none
getnum: stz     z:n
        stz     z:nd
:       lda     (q)
        and     #$00FF
        cmp     #' '
        bne     @d
        inc     z:q
        bra     :-
@d:     lda     (q)
        and     #$00FF
        sec
        sbc     #'0'
        bcc     @e
        cmp     #10
        bcs     @e
        sta     z:t1
        lda     z:n
        cmp     #1000                   ; (larger numbers stay >= 1000: clamped anyway)
        bcs     :+
        asl     a
        sta     z:t2
        asl     a
        asl     a
        adc     z:t2
        adc     z:t1
        sta     z:n
:       inc     z:nd
        inc     z:q
        bra     @d
@e:     lda     (q)
        and     #$00FF
        cmp     #','
        bne     :+
        inc     z:q
:       lda     z:nd
        bne     :+
        sec
        rts
:       lda     z:n
        clc
        rts

; the file's text -> obuf, olen = its length
build:  ldy     #0
        ldx     #.loword(s_head)
        jsr     pstr
        ldx     #.loword(k_desk)
        lda     #0
        jsr     prgb
        ldx     #.loword(k_desk2)
        lda     #3
        jsr     prgb
        ldx     #0
:       phx
        lda     keys+4,x
        tax
        jsr     pstr
        plx
        lda     val,x
        phx
        jsr     pnum
        lda     #10
        jsr     pchr
        plx
        inx
        inx
        cpx     #NSET * 2
        bcc     :-
        sty     olen
        rts

; key X, then the three bytes desk + A as "r,g,b\n"
prgb:   sta     z:k
        jsr     pstr
        ldx     z:k
        lda     desk,x
        jsr     pnum8
        lda     #','
        jsr     pchr
        ldx     z:k
        lda     desk+1,x
        jsr     pnum8
        lda     #','
        jsr     pchr
        ldx     z:k
        lda     desk+2,x
        jsr     pnum8
        lda     #10
        bra     pchr

; string X at obuf + Y
pstr:   lda     a:0,x
        and     #$00FF
        beq     :+
        jsr     pchr
        inx
        bra     pstr
:       rts

pnum8:  and     #$00FF
; A in decimal at obuf + Y
pnum:   sta     z:n
        stz     z:nd
@d:     lda     #0                      ; n / 10, A = the remainder
        ldx     #16
:       asl     z:n
        rol     a
        cmp     #10
        bcc     :+
        sbc     #10
        inc     z:n
:       dex
        bne     :--
        clc
        adc     #'0'
        pha
        inc     z:nd
        lda     z:n
        bne     @d
:       pla
        jsr     pchr
        dec     z:nd
        bne     :-
        rts

; character A at obuf + Y
pchr:   sep     #$20
        .a8
        sta     obuf,y
        rep     #$20
        .a16
        iny
        rts

; ---------------------------------------------------------------- /atari.ini
; aval = the defaults, then the file's values (as the firmware reads them); aorig = aval.
; abuf / alen / aend = the file; aerr = 1: it could not be read (or is too large): Save
; will not overwrite it.
load_ini:
        ldx     #.loword(adflt)
        ldy     #.loword(aval)
        jsr     copya
        stz     alen
        stz     aerr
        ptr     p_ini
        lda     #O_READ
        sys     SYS_OPEN
        bcc     @open
        cmp     #ENOENT                 ; no file (or no such folder): the defaults
        beq     @end
        cmp     #EIO + 4
        beq     @end
        cmp     #EIO + 5
        beq     @end
        bra     @bad
@open:  sta     fh
        sta     rw
@rd:    lda     alen                    ; read until the end (or the buffer is full)
        cmp     #AMAX
        bcs     @big
        clc
        adc     #.loword(abuf)
        sta     rw+1
        lda     #^abuf
        sta     rw+3
        lda     #AMAX
        sec
        sbc     alen
        sta     rw+4
        ptr     rw
        sys     SYS_READ
        bcs     @rerr
        cmp     #0
        beq     @eof
        clc
        adc     alen
        sta     alen
        bra     @rd
@big:   lda     #2
        bra     :+
@rerr:  lda     #1
:       sta     aerr
@eof:   lda     fh
        sys     SYS_CLOSE
        lda     aerr
        bne     @end
        jsr     aparse
@end:   lda     alen
        clc
        adc     #.loword(abuf)
        sta     z:aend
        lda     #0                      ; (a zero after it: the CR LF search reads a word)
        sta     (aend)
        ldx     #.loword(aval)
        ldy     #.loword(aorig)
        jmp     copya
@bad:   lda     #1
        sta     aerr
        bra     @end

; the lines of abuf -> aval (a line without "=" ends it, as in the firmware)
aparse: lda     alen
        clc
        adc     #.loword(abuf)
        sta     z:aend
        lda     #.loword(abuf)
        sta     z:q
@l:     lda     z:q
        cmp     z:aend
        bcs     @out
        jsr     aline
        cmp     #$FFFE
        beq     @out
        cmp     #NAK * 2
        bcs     @nx
        jsr     aset
@nx:    lda     z:le
        inc     a
        sta     z:q
        bra     @l
@out:   rts

; the line at q (up to aend): le = its end (the LF, or aend), A = the key's index * 2 when it
; is a line of a known key (vs .. ve: its value, blanks trimmed), $FFFF a line to keep as it
; is (empty, comment, section, other key), $FFFE a line without "=". Keeps Y.
aline:  phy
        ldx     z:q                     ; the end
:       cpx     z:aend
        bcs     :+
        lda     a:0,x
        and     #$00FF
        cmp     #10
        beq     :+
        inx
        bra     :-
:       stx     z:le
        ldx     z:q                     ; trimmed: ks .. ve
:       cpx     z:le
        jcs     @keep                   ; empty
        lda     a:0,x
        jsr     isspc
        bcc     :+
        inx
        bra     :-
:       stx     z:ks
        ldx     z:le
:       dex
        lda     a:0,x
        jsr     isspc
        bcs     :-
        inx
        stx     z:ve
        ldx     z:ks
        lda     a:0,x
        and     #$00FF
        cmp     #'['
        beq     @keep
        cmp     #';'
        beq     @keep
        cmp     #'#'
        beq     @keep
:       cpx     z:ve                    ; the "="
        bcs     @inval
        lda     a:0,x
        and     #$00FF
        cmp     #'='
        beq     :+
        inx
        bra     :-
:       stx     z:ke
        inx                             ; the value: blanks before it skipped
:       cpx     z:ve
        bcs     :+
        lda     a:0,x
        jsr     isspc
        bcc     :+
        inx
        bra     :-
:       stx     z:vs
        ldx     z:ke                    ; the key: blanks after it dropped
:       cpx     z:ks
        beq     :+
        dex
        lda     a:0,x
        jsr     isspc
        bcs     :-
        inx
:       stx     z:ke
        ldy     #0                      ; which key?
@k:     lda     akeys,y
        beq     @keep
        sta     z:kp
        ldx     z:ks
:       lda     (kp)
        and     #$00FF
        beq     @kend
        sta     z:t0
        cpx     z:ke
        bcs     @nk
        lda     a:0,x
        and     #$00FF
        cmp     z:t0
        bne     @nk
        inx
        inc     z:kp
        bra     :-
@kend:  cpx     z:ke
        bne     @nk
        tya
        ply
        rts
@nk:    iny
        iny
        bra     @k
@keep:  ply
        lda     #$FFFF
        rts
@inval: ply
        lda     #$FFFE
        rts

; C set: the byte A (low 8 bits) is a blank (as the firmware's isspace: 9-13, 32)
isspc:  and     #$00FF
        cmp     #' '
        beq     @y
        cmp     #9
        bcc     @n
        cmp     #14
        bcs     @n
@y:     sec
        rts
@n:     clc
        rts

; key A (index * 2), value vs .. ve -> aval (the firmware's reading of each key)
aset:   sta     z:k
        cmp     #AV_BOOT
        bne     @num
        ldx     z:vs                    ; boot: "ash" exactly, else BASIC
        lda     z:ve
        sec
        sbc     z:vs
        cmp     #3
        bne     @basic
        lda     a:0,x
        cmp     #'a' | ('s' << 8)
        bne     @basic
        lda     a:2,x
        and     #$00FF
        cmp     #'h'
        bne     @basic
        lda     #1
        bra     @st
@basic: lda     #0
        bra     @st
@num:   jsr     aatoi
        ldx     z:k
        cpx     #0
        bne     @nram
        lda     z:nh                    ; ram: 128 or 320, anything else 320 (0.16:
        bne     @r320                   ; as the firmware, which has only these two)
        ldy     #0
:       lda     v_ram,y
        cmp     z:nl
        beq     @st
        iny
        iny
        cpy     #4
        bcc     :-
@r320:  lda     #320
        bra     @st
@nram:  cpx     #6
        bne     @nscan
        lda     z:nl                    ; scanlines: & 3
        and     #3
        bra     @st
@nscan: cpx     #AV_HPOS
        bne     @bool
        lda     z:nh                    ; hpos: clamped to 0-48
        bmi     @zero
        bne     @h48
        lda     z:nl
        cmp     #49
        bcc     @st
@h48:   lda     #48
        bra     @st
@bool:  lda     z:nl                    ; kbdlayout, joystick, basic, fastdisk: non-zero = 1
        ora     z:nh
        beq     @st
        lda     #1
        bra     @st
@zero:  lda     #0
@st:    ldx     z:k
        sta     aval,x
        rts

; C atoi of vs .. ve (spaces, a sign, digits; 32 bits, an overflow gives INT_MAX / INT_MIN)
; -> nh:nl
aatoi:  stz     z:nl
        stz     z:nh
        stz     z:neg
        ldx     z:vs
:       cpx     z:ve
        jcs     @done
        lda     a:0,x
        and     #$00FF
        cmp     #' '
        bne     :+
        inx
        bra     :-
:       cmp     #'-'
        bne     :+
        inc     z:neg
        bra     @sg
:       cmp     #'+'
        bne     @dig
@sg:    inx
@dig:   cpx     z:ve
        bcs     @done
        lda     a:0,x
        and     #$00FF
        sec
        sbc     #'0'
        bcc     @done
        cmp     #10
        bcs     @done
        sta     z:t1
        lda     z:nh                    ; base > INT_MAX / 10 (214748364 = $0CCCCCCC), or
        cmp     #$0CCC                  ; = and the digit > 7: overflow
        bcc     @ok
        bne     @ovf
        lda     z:nl
        cmp     #$CCCC
        bcc     @ok
        bne     @ovf
        lda     z:t1
        cmp     #8
        bcs     @ovf
@ok:    asl     z:nl                    ; n * 10 + digit
        rol     z:nh
        lda     z:nl
        sta     z:t2
        lda     z:nh
        sta     z:t0
        asl     z:nl
        rol     z:nh
        asl     z:nl
        rol     z:nh
        lda     z:nl
        clc
        adc     z:t2
        sta     z:nl
        lda     z:nh
        adc     z:t0
        sta     z:nh
        lda     z:nl
        clc
        adc     z:t1
        sta     z:nl
        bcc     :+
        inc     z:nh
:       inx
        bra     @dig
@ovf:   lda     #$FFFF                  ; INT_MAX, or INT_MIN when negative
        sta     z:nl
        lda     #$7FFF
        sta     z:nh
        lda     z:neg
        beq     :+
        stz     z:nl
        lda     #$8000
        sta     z:nh
:       rts
@done:  lda     z:neg
        beq     :+
        lda     z:nl                    ; - n
        eor     #$FFFF
        clc
        adc     #1
        sta     z:nl
        lda     z:nh
        eor     #$FFFF
        adc     #0
        sta     z:nh
:       rts

; the new /atari.ini -> obuf, olen: the file's lines, those of the known keys with the new
; values, then the keys it lacks
abuild: stz     z:seen
        stz     z:crlf
        ldx     #.loword(abuf)          ; CR LF anywhere: the file uses CR LF
:       cpx     z:aend
        bcs     :+
        lda     a:0,x
        inx
        cmp     #13 | (10 << 8)
        bne     :-
        inc     z:crlf
:       ldy     #0
        lda     alen                    ; a new file: a comment first
        bne     :+
        ldx     #.loword(s_ahead)
        jsr     pstr
:       lda     #.loword(abuf)
        sta     z:q
@l:     lda     z:q
        cmp     z:aend
        bcs     @app
        jsr     aline
        cmp     #NAK * 2
        bcs     @copy
        sta     z:k                     ; a known key: "key=value", the line's own end
        tax
        lda     abit,x
        tsb     z:seen
        jsr     akv
        ldx     z:le                    ; (a CR before the end: kept)
        dex
        lda     a:0,x
        and     #$00FF
        cmp     #13
        bne     :+
        lda     #13
        jsr     pchr
:       ldx     z:le
        cpx     z:aend
        bcs     @next
        lda     #10
        jsr     pchr
        bra     @next
@copy:  ldx     z:q                     ; any other line: as it is (with its LF)
:       cpx     z:le
        bcs     :+
        lda     a:0,x
        jsr     pchr
        inx
        bra     :-
:       cpx     z:aend
        bcs     @next
        lda     #10
        jsr     pchr
@next:  lda     z:le
        inc     a
        sta     z:q
        bra     @l
@app:   lda     z:seen                  ; the keys missing
        cmp     #(1 << NAK) - 1
        beq     @out
        lda     alen                    ; the last line without its line end: one first
        beq     :+
        ldx     z:aend
        dex
        lda     a:0,x
        and     #$00FF
        cmp     #10
        beq     :+
        jsr     peol
:       ldx     #0
@m:     stx     z:k
        lda     abit,x
        and     z:seen
        bne     :+
        jsr     akv
        jsr     peol
:       ldx     z:k
        inx
        inx
        cpx     #NAK * 2
        bcc     @m
@out:   sty     olen
        rts

; the line end of the file (CR LF or LF) at obuf + Y
peol:   lda     z:crlf
        beq     :+
        lda     #13
        jsr     pchr
:       lda     #10
        jmp     pchr

; "key=value" of key k at obuf + Y
akv:    ldx     z:k
        lda     akeys,x
        tax
        jsr     pstr
        lda     #'='
        jsr     pchr
        ldx     z:k
        cpx     #AV_BOOT
        bne     :++
        ldx     #.loword(s_basic)
        lda     aval+AV_BOOT
        beq     :+
        ldx     #.loword(s_ash)
:       jmp     pstr
:       lda     aval,x
        jmp     pnum

; ---------------------------------------------------------------- data
.macro  mkbtn   bx, by, bw, bf, bl
        .byte   UT_BUTTON, 0
        .word   bx, by, bw, UI_BTNH, bf, bl
.endmacro
.macro  mklab   lx, ly, lt
        .byte   UT_LABEL, 0
        .word   lx, ly, CX - LX - 4, UI_LINE, 0, lt
.endmacro

        .segment "RODATA"
s_atari: .byte  "atari", 0
s_apply: .byte  "apply", 0
p_cfg:  .byte   "/SYSTEM/CONFIG", 0
p_ini:  .byte   "/atari.ini", 0
t_title: .byte  "Settings", 0
s_head: .byte   "# Horizon settings (written by Settings)", 10, 0
s_ahead: .byte  "# Classic Atari settings (written by Settings; read at power-on)", 10, 0
k_desk: .byte   "desk=", 0
k_desk2: .byte  "desk2=", 0
k_mouse: .byte  "mouse=", 0
k_beep: .byte   "beep=", 0
k_rdel: .byte   "repeat_delay=", 0
k_rrate: .byte  "repeat_rate=", 0
k_sound: .byte  "sound=", 0
k_saver: .byte  "saver=", 0
p_saver: .byte  "/SYSTEM/SAVER.PRG", 0
; (the numeric keys in the order of the kernel settings 0-5: val's)
keys:   .addr   k_desk, k_desk2, k_mouse, k_beep, k_rdel, k_rrate, k_sound, k_saver, 0
lims:   .word   1, 4, 0, 15, 0, 250, 1, 100, 0, 15, 0, 3600
; defaults: mouse, beep, delay, rate, sound, saver (words), desk, desk2 (r, g, b bytes) = cur's
; layout
dflt:   .word   1, 8, 40, 5, 8, 300
        .byte   36, 92, 112, 46, 104, 124
; /atari.ini: the keys (aval's order), the firmware's defaults, a bit for each key
ak_ram: .byte   "ram", 0
ak_kbd: .byte   "kbdlayout", 0
ak_joy: .byte   "joystick", 0
ak_scan: .byte  "scanlines", 0
ak_boot: .byte  "boot", 0
ak_hpos: .byte  "hpos", 0
ak_bas: .byte   "basic", 0                      ; (0.27)
ak_fast: .byte  "fastdisk", 0
akeys:  .addr   ak_ram, ak_kbd, ak_joy, ak_scan, ak_boot, ak_hpos, ak_bas, ak_fast, 0
adflt:  .word   128, 0, 0, 0, 0, 0, 1, 1
abit:   .word   1, 2, 4, 8, 16, 32, 64, 128
s_basic: .byte  "basic", 0
s_ash:  .byte   "ash", 0
; the presets (desk, desk2) and the two system colours of their swatch's checker (the
; nearest mean among the fixed colours; tools: a 6x6x6 cube search)
presets:
        .byte   36, 92, 112,  46, 104, 124       ; teal (the default)
        .byte   52, 72, 120,  62, 84, 134        ; slate
        .byte   24, 40, 80,   32, 50, 94         ; navy
        .byte   44, 96, 64,   54, 108, 74        ; forest
        .byte   96, 104, 56,  108, 116, 66       ; moss
        .byte   88, 56, 104,  100, 66, 118       ; plum
        .byte   112, 44, 56,  126, 54, 66        ; wine
        .byte   148, 84, 52,  160, 96, 62        ; rust
        .byte   152, 140, 116, 164, 152, 128     ; sand
        .byte   64, 68, 76,   74, 78, 86         ; graphite
swcol:  .byte   66, 67, 60, 67, 24, 60, 65, 66, 101, 101
        .byte   96, 96, 95, 131, 137, 137, 144, 246, 7, 238
; toggle groups of each page: {first button, count, values, the variable}, 0 (a group's
; buttons follow each other)
grp_d:  .addr   b_pg1
        .word   2
        .addr   v_01, page
        .addr   b_m1
        .word   4
        .addr   v_mouse, cur
        .addr   b_d1
        .word   4
        .addr   v_delay, cur + 4
        .addr   b_r1
        .word   3
        .addr   v_rate, cur + 6
        .addr   b_sv1                   ; (0.24)
        .word   4
        .addr   v_saver, cur + 10
        .word   0
grp_a:  .addr   b_pg1
        .word   2
        .addr   v_01, page
        .addr   b_ram1
        .word   2
        .addr   v_ram, aval
        .addr   b_kbd1
        .word   2
        .addr   v_01, aval + 2
        .addr   b_joy1
        .word   2
        .addr   v_01, aval + 4
        .addr   b_sc1
        .word   4
        .addr   v_scan, aval + 6
        .addr   b_bt1
        .word   2
        .addr   v_01, aval + AV_BOOT
        .addr   b_bas1                  ; (0.27)
        .word   2
        .addr   v_10, aval + AV_BAS
        .addr   b_fd1
        .word   2
        .addr   v_10, aval + AV_FAST
        .word   0
pgrps:  .addr   grp_d, grp_a
plists: .addr   ctl_d, ctl_a
v_mouse: .word  1, 2, 3, 4
v_delay: .word  0, 25, 40, 60
v_rate: .word   10, 5, 3
v_saver: .word  0, 60, 300, 600
v_01:   .word   0, 1
v_10:   .word   1, 0                    ; (0.27: on, the default, first)
v_ram:  .word   128, 320
v_scan: .word   0, 1, 2, 3
t_desk: .byte   "Desktop:", 0
t_mouse: .byte  "Mouse speed:", 0
t_delay: .byte  "Repeat delay:", 0
t_rate: .byte   "Repeat rate:", 0
t_try:  .byte   "Try here:", 0
t_beep: .byte   "Alert volume:", 0
t_svol: .byte   "Sound volume:", 0
t_saver: .byte  "Screen saver:", 0
s_1m:   .byte   "1 min", 0
s_5m:   .byte   "5 min", 0
s_10m:  .byte   "10 min", 0
t_ram:  .byte   "Memory:", 0
t_kbd:  .byte   "Keyboard:", 0
t_joy:  .byte   "Arrow keys:", 0
t_scan: .byte   "Scanlines:", 0
t_hpos: .byte   "H position:", 0
t_boot: .byte   "Boot:", 0
t_bas:  .byte   "Disk boot:", 0
t_fast: .byte   "Disk loading:", 0
s_pg1:  .byte   "Desktop", 0
s_pg2:  .byte   "Classic Atari", 0
s_1:    .byte   "1", 0
s_2:    .byte   "2", 0
s_3:    .byte   "3", 0
s_4:    .byte   "4", 0
s_off:  .byte   "Off", 0
s_025:  .byte   "0.25 s", 0
s_04:   .byte   "0.4 s", 0
s_06:   .byte   "0.6 s", 0
s_slow: .byte   "Slow", 0
s_med:  .byte   "Medium", 0
s_fast: .byte   "Fast", 0
s_k128: .byte   "128 KB", 0
s_k320: .byte   "320 KB", 0
s_katari: .byte "Atari layout", 0
s_kpc:  .byte   "PC layout (US)", 0
s_cursor: .byte "Cursor keys", 0
s_joy:  .byte   "Joystick", 0
s_25:   .byte   "25%", 0
s_50:   .byte   "50%", 0
s_75:   .byte   "75%", 0
s_bbasic: .byte "BASIC", 0
s_bash: .byte   "ASH cartridge", 0
s_wbas: .byte   "With BASIC", 0
s_nobas: .byte  "Without BASIC", 0
s_sio:  .byte   "Serial port", 0
s_test: .byte   "Test", 0
; one period of the sound Test's tone: round(100 sin x + 22 sin 2x), signed 8-bit
tone:   .byte   0, 37, 69, 93, 106, 108, 100, 86, 68, 49, 31, 15
        .byte   0, 241, 225, 207, 188, 170, 156, 148, 150, 163, 187, 219
s_save: .byte   "Save", 0
s_cancel: .byte "Cancel", 0
s_dflt: .byte   "Defaults", 0
m_err:  .byte   "The settings could not be saved.", 0
m_aerr: .byte   "The Classic Atari settings", 10, "could not be saved.", 0
m_rst:  .byte   "The Classic Atari settings take", 10, "effect when the machine restarts.", 0
m_rerr: .byte   "The machine cannot restart now.", 10, "The Classic Atari settings take", 10, "effect at the next restart.", 0
s_ok:   .byte   "OK", 0
s_rnow: .byte   "Restart now", 0
s_later: .byte  "Later", 0
al_err: .word   3, t_title, m_err, s_ok, 0, 0
al_aerr: .word  3, t_title, m_aerr, s_ok, 0, 0
al_rst: .word   2, t_title, m_rst, s_rnow, s_later, 0
al_rerr: .word  3, t_title, m_rerr, s_ok, 0, 0
; the control lists of the pages (the page buttons and the bottom row on both)
ctl_d:  .addr   b_pg1, b_pg2, l_desk, l_mouse, l_delay, l_rate, l_try, l_beep, l_svol
        .addr   b_m1, b_m2, b_m3, b_m4, b_d1, b_d2, b_d3, b_d4, b_r1, b_r2, b_r3
        .addr   f_try, sb_vol, b_test, sb_snd, b_stest
        .addr   l_saver, b_sv1, b_sv2, b_sv3, b_sv4, b_svtest, b_dflt, b_cancel, b_save, 0
ctl_a:  .addr   b_pg1, b_pg2, l_ram, l_kbd, l_joy, l_scan, l_hpos, l_boot, l_bas, l_fast
        .addr   b_ram1, b_ram2, b_kbd1, b_kbd2
        .addr   b_joy1, b_joy2, b_sc1, b_sc2, b_sc3, b_sc4, sb_hpos, b_bt1, b_bt2
        .addr   b_bas1, b_bas2, b_fd1, b_fd2
        .addr   b_dflt, b_cancel, b_save, 0
; every control (their CT_WIN)
allc:   .addr   l_desk, l_mouse, l_delay, l_rate, l_try, l_beep, l_svol
        .addr   b_m1, b_m2, b_m3, b_m4, b_d1, b_d2, b_d3, b_d4, b_r1, b_r2, b_r3
        .addr   f_try, sb_vol, b_test, sb_snd, b_stest
        .addr   l_saver, b_sv1, b_sv2, b_sv3, b_sv4, b_svtest
        .addr   b_pg1, b_pg2, b_dflt, b_cancel, b_save
        .addr   l_ram, l_kbd, l_joy, l_scan, l_hpos, l_boot, l_bas, l_fast
        .addr   b_ram1, b_ram2, b_kbd1, b_kbd2
        .addr   b_joy1, b_joy2, b_sc1, b_sc2, b_sc3, b_sc4, sb_hpos, b_bt1, b_bt2
        .addr   b_bas1, b_bas2, b_fd1, b_fd2, 0

        .segment "DATA"
wblk:   .word   (640 - W - 2) / 2, 20, W, H
        .faraddr t_title
        .byte   0
b_pg1:  mkbtn   LX, TABY, TABW, 0, s_pg1        ; the page buttons
b_pg2:  mkbtn   LX + TABW + 4, TABY, TABW, 0, s_pg2
l_desk:  mklab  LX, SWY + 4, t_desk
l_mouse: mklab  LX, R_MOUSE + 6, t_mouse
l_delay: mklab  LX, R_DELAY + 6, t_delay
l_rate:  mklab  LX, R_RATE + 6, t_rate
l_try:   mklab  LX, R_TRY + 4, t_try
l_beep:  mklab  LX, R_BEEP + 6, t_beep
l_svol:  mklab  LX, R_SND + 6, t_svol
b_m1:   mkbtn   CX, R_MOUSE, 56, 0, s_1         ; (a group's buttons follow each other)
b_m2:   mkbtn   CX + 60, R_MOUSE, 56, 0, s_2
b_m3:   mkbtn   CX + 120, R_MOUSE, 56, 0, s_3
b_m4:   mkbtn   CX + 180, R_MOUSE, 56, 0, s_4
b_d1:   mkbtn   CX, R_DELAY, 56, 0, s_off
b_d2:   mkbtn   CX + 60, R_DELAY, 56, 0, s_025
b_d3:   mkbtn   CX + 120, R_DELAY, 56, 0, s_04
b_d4:   mkbtn   CX + 180, R_DELAY, 56, 0, s_06
b_r1:   mkbtn   CX, R_RATE, 76, 0, s_slow
b_r2:   mkbtn   CX + 80, R_RATE, 76, 0, s_med
b_r3:   mkbtn   CX + 160, R_RATE, 76, 0, s_fast
f_try:  .byte   UT_FIELD, 0
        .word   CX, R_TRY, CW, UI_FLDH, UF_FOCUS, tbuf, 64, 0, 0, 0, 0
sb_vol: .byte   UT_HSCROLL, 0
        .word   CX, R_BEEP + 3, VOLX - 4 - CX, UI_SBW, 0
        .word   0, 15, 1, 1, 0, 0
b_test: mkbtn   CX + 180, R_BEEP, 56, 0, s_test
sb_snd: .byte   UT_HSCROLL, 0                   ; (0.18) the sound volume
        .word   CX, R_SND + 3, VOLX - 4 - CX, UI_SBW, 0
        .word   0, 15, 1, 1, 0, 0
b_stest: mkbtn  CX + 180, R_SND, 56, 0, s_test
l_saver: mklab  LX, R_SAVER + 6, t_saver       ; (0.24) the screen saver
b_sv1:  mkbtn   CX, R_SAVER, 44, 0, s_off
b_sv2:  mkbtn   CX + 48, R_SAVER, 44, 0, s_1m
b_sv3:  mkbtn   CX + 96, R_SAVER, 44, 0, s_5m
b_sv4:  mkbtn   CX + 144, R_SAVER, 44, 0, s_10m
b_svtest: mkbtn CX + 192, R_SAVER, 44, 0, s_test
; the sound Test: SNDN samples of snd at 16 kHz, 8-bit, both volumes 255, any voice
spb:    .faraddr snd
        .faraddr SNDN
        .faraddr 0
        .word   $1555
        .byte   255, 255, 0, SP_ANY, 0
l_ram:  mklab   LX, RA_RAM + 6, t_ram
l_kbd:  mklab   LX, RA_KBD + 6, t_kbd
l_joy:  mklab   LX, RA_JOY + 6, t_joy
l_scan: mklab   LX, RA_SCAN + 6, t_scan
l_hpos: mklab   LX, RA_HPOS + 6, t_hpos
l_boot: mklab   LX, RA_BOOT + 6, t_boot
l_bas:  mklab   LX, RA_BAS + 6, t_bas           ; (0.27)
l_fast: mklab   LX, RA_FAST + 6, t_fast
b_ram1: mkbtn   CX, RA_RAM, 116, 0, s_k128
b_ram2: mkbtn   CX + 120, RA_RAM, 116, 0, s_k320
b_kbd1: mkbtn   CX, RA_KBD, 116, 0, s_katari
b_kbd2: mkbtn   CX + 120, RA_KBD, 116, 0, s_kpc
b_joy1: mkbtn   CX, RA_JOY, 116, 0, s_cursor
b_joy2: mkbtn   CX + 120, RA_JOY, 116, 0, s_joy
b_sc1:  mkbtn   CX, RA_SCAN, 56, 0, s_off
b_sc2:  mkbtn   CX + 60, RA_SCAN, 56, 0, s_25
b_sc3:  mkbtn   CX + 120, RA_SCAN, 56, 0, s_50
b_sc4:  mkbtn   CX + 180, RA_SCAN, 56, 0, s_75
sb_hpos: .byte  UT_HSCROLL, 0
        .word   CX, RA_HPOS + 3, VOLX - 4 - CX, UI_SBW, 0
        .word   0, 48, 4, 1, 0, 0
b_bt1:  mkbtn   CX, RA_BOOT, 116, 0, s_bbasic
b_bt2:  mkbtn   CX + 120, RA_BOOT, 116, 0, s_bash
b_bas1: mkbtn   CX, RA_BAS, 116, 0, s_wbas       ; (0.27) basic=1, basic=0
b_bas2: mkbtn   CX + 120, RA_BAS, 116, 0, s_nobas
b_fd1:  mkbtn   CX, RA_FAST, 116, 0, s_fast     ; fastdisk=1, fastdisk=0
b_fd2:  mkbtn   CX + 120, RA_FAST, 116, 0, s_sio
b_dflt: mkbtn   LX, R_BTN, 72, 0, s_dflt
b_cancel: mkbtn W - LX - 64 - 8 - 64, R_BTN, 64, UF_CANCEL, s_cancel
b_save: mkbtn   W - LX - 64, R_BTN, 64, UF_DEFAULT, s_save

        .segment "BSS"
argl:   .res    2
argx:   .res    2
wsown:  .res    2
win:    .res    2
cfgok:  .res    2
fh:     .res    2
olen:   .res    2
page:   .res    2                       ; 0 Desktop, 1 Classic Atari
rpend:  .res    2                       ; /atari.ini written: offer the restart
aerr:   .res    2                       ; /atari.ini unreadable (1) or too large (2)
alen:   .res    2
rw:     .res    6
cur:    .res    18                      ; mouse, beep, delay, rate, sound, saver (words), desk, desk2
val     = cur
desk    = cur + NSET * 2
orig:   .res    18
aval:   .res    16                      ; ram, kbdlayout, joystick, scanlines, boot, hpos,
aorig:  .res    16                      ; (0.27) basic, fastdisk
c0:     .res    6                       ; (parse: three numbers)
tbuf:   .res    64
obuf:   .res    AMAX + 256
fbuf:   .res    FBMAX
abuf:   .res    AMAX + 2
sndok:  .res    2                       ; snd made
snd:    .res    SNDN                    ; the sound Test's sample (signed 8-bit)

        .segment "ZEROPAGE"
t0:     .res    2
t1:     .res    2
t2:     .res    2
q:      .res    2
kp:     .res    2
k:      .res    2
n:      .res    2
nd:     .res    2
bp:     .res    2
vp:     .res    2
cnt:    .res    2
want:   .res    2
sel:    .res    2
i:      .res    2
sx:     .res    2
rc:     .res    2
gp:     .res    2
env:    .res    2
aend:   .res    2
le:     .res    2
ks:     .res    2
ke:     .res    2
vs:     .res    2
ve:     .res    2
nl:     .res    2
nh:     .res    2
neg:    .res    2
seen:   .res    2
crlf:   .res    2
