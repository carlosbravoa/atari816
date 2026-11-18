; HEXVIEW - Hex View, a hex dump viewer for Horizon (Atari816). An SDK example.
;
; Shows any file as a hex dump, one line per 16 bytes:
;
;   000120  4C 69 6E 65 20 30 30 30 30 31 20 6F 66 20 74 68  Line 00001 of th
;   offset  the 16 bytes in hex                              the 16 characters
;
; in the fixed 8 x 12 font, black on white in a sunken box, with a scroll bar at its right
; and a status line under it (the size, the offset of the top line).
;
; Opening a file: File > Open... (ctrl+O), the argument ("hexview /docs/NOTES.TXT" in the
; shell), or a file dropped from Files onto the window. The file is read into a 64 KB
; bank of its own (SYS_BALLOC) and read back from there with long addressing; files over
; 64 KB show their first 64 KB.
; Moving: the scroll bar (arrows, track, thumb, mouse wheel), Up / Down (a line),
; PgUp / PgDn (a page), Home / End, View > Go to offset... (ctrl+G, a hexadecimal offset).
; Scrolling moves the lines that stay with one WD_COPY and draws only the lines that come
; in. The window can be resized: the box gets more or fewer lines.
; File > Close, ctrl+W or the close box end it.
;
; What it shows a learner, in order: the start (window system, controls library, a bank,
; the window, the argument), the event loop, the menus and keys, loading a file into the
; bank, the layout, drawing a line, scrolling with WD_COPY, the status line.
;
; Registers: A, X, Y are 16-bit everywhere (.a16 / .i16); the few 8-bit sections (single
; bytes) switch with sep #$20 / .a8 and back with rep #$20 / .a16 right away.

        .include "horizon.inc"
        .include "ui.inc"

; ---------------------------------------------------------------- the layout (pixels)
;
;  +--------------------------------------------- content (CW x CH) ---+
;  |  8                                                                 |
;  |  +-- the box (sunken, BW x BH) --------------------------+--+      |
;  |  | 3 px padding, then VIS lines of 12 pixels, 8 x 12     |sb|      |
;  |  | characters, white                                     |  |      |
;  |  +-------------------------------------------------------+--+      |
;  |  4                                                                 |
;  |  status line (UI font, 12 high)                                    |
;  |  8                                                                 |
;  +--------------------------------------------------------------------+

WIN_X   = 8                             ; where the window opens (outer top left)
WIN_Y   = 28
WIN_W   = 624                           ; its first content size: 20 lines of 73 columns
WIN_H   = 280
BOXX    = UI_GAP                        ; the sunken box
BOXY    = UI_GAP
PAD     = 3                             ; white between the box's bevel and the text
ROWH    = 12                            ; a line of the fixed font
COLW    = 8                             ; a character of the fixed font
COLS    = 73                            ; characters in a full line (see mkline)
TXTX    = BOXX + 1 + PAD                ; the first character's left edge (12)
TXTY    = BOXY + 1 + PAD                ; the first line's top (12)
MAXVIS  = 32                            ; lines at most (the screen has room for 28)
MINW    = 128                           ; sizes below these are laid out as these
MINH    = 64                            ;   (the kernel clips whatever does not fit)
HALF    = $8000                         ; the file is read in two halves of 32 KB

        .segment "CODE"
        .a16
        .i16

; ================================================================ start
; The loader starts us with A = the argument's length and X = its address (in bank 0):
; keep them before any call changes A and X.
start:  sta     argl
        stx     argx
        sys     SYS_WSSTART             ; the window system (already running under the
        bcc     :+                      ;   Desktop: A = 0; started by us: A = 1)
        print   "hexview: no window system (not enough memory)\n"
        exit    1
:       sta     z:wsown                 ; remember: only its starter may stop it
        jsr     ui_init                 ; the controls library, after SYS_WSSTART

; A bank of 64 KB for the file. Its address is kept in a 3-byte long pointer in zero
; page: fptr = bank:0000. lda [fptr],y then reads byte Y of the file.
        sys     SYS_BALLOC              ; -> A = the bank number
        bcc     :+
        ldx     #.loword(al_mem)        ; (the alert works without a window of ours)
        jsr     ui_alert
        jmp     quit
:       sta     z:fptr+2                ; the bank byte (and the spare 4th byte: 0)
        stz     z:fptr                  ; offset 0000

        ptr     wopen
        sys     SYS_WOPEN               ; -> A = window
        jcs     quit
        sta     z:win
        sep     #$20                    ; our one control, the scroll bar, lives in it
        .a8
        sta     sb+CT_WIN               ; (CT_WIN is a byte)
        rep     #$20
        .a16
        ptr     menus                   ; the menu bar shows these while we have the focus
        lda     z:win
        sys     SYS_WMENU

        lda     #WIN_W                  ; the content size we asked for
        sta     cw
        lda     #WIN_H
        sta     ch
        jsr     nofile                  ; nothing loaded yet
        jsr     relayout                ; the box, the lines, the scroll bar, the status

; The argument: "hexview /docs/FILE.BIN" in the shell gives "/docs/FILE.BIN" (or
; "\"/docs/My file.bin\""). next_arg copies its first word (quotes make one word).
        lda     argl
        beq     loop
        ldx     argx
        jsr     args_init               ; u_p = the argument string
        ptr     path
        lda     #128
        jsr     next_arg                ; -> path, A = length; C set: none
        bcs     loop
        jsr     load

; ================================================================ the event loop
; ui_getev waits for the next event (into ui_ev); ui_event gives it to the controls
; first. The scroll bar reports UA_CHANGE when the user moved it (arrows, track, thumb,
; wheel: it has already redrawn itself). Everything it did not use is ours (UA_NONE).
loop:   lda     #0                      ; 0 = wait for the next event
        jsr     ui_getev                ; -> ui_ev: u8 type, u8 window, u16 a, b, c
        bcs     loop
        ldx     #.loword(ctls)
        jsr     ui_event                ; -> A = UA_*, X = the control that acted
        cmp     #UA_CHANGE
        bne     @own
        lda     sb+SB_POS               ; the scroll bar's new position = the top line
        jsr     scrollto
        bra     loop
@own:   cmp     #UA_NONE
        bne     loop
        lda     ui_ev
        and     #$00FF                  ; the event's type
        cmp     #WE_KEY
        beq     onkey
        cmp     #WE_MENU
        jeq     onmenu
        cmp     #WE_RESIZE
        jeq     onresize
        cmp     #WE_DROP
        jeq     ondrop
        cmp     #WE_CLOSE               ; the close box, ctrl+W, Alt+F4, Shut down
        jeq     quit
        bra     loop

; ---- keys: a = HID usage, b = modifiers | down << 8
onkey:  lda     ui_ev+4
        bit     #$0100
        beq     loop                    ; a release: nothing to do
        and     #$0011                  ; left or right ctrl held?
        bne     @ctrl
        lda     ui_ev+2
        cmp     #$52                    ; Up: one line back
        bne     :+
        lda     top
        beq     loop
        dec     a
        jsr     scrollto
        bra     loop
:       cmp     #$51                    ; Down: one line on (scrollto stops at the end)
        bne     :+
        lda     top
        inc     a
        jsr     scrollto
        bra     loop
:       cmp     #$4B                    ; PgUp: a page back, not before the start
        bne     :++
        lda     top
        sec
        sbc     vis
        bcs     :+
        lda     #0
:       jsr     scrollto
        jmp     loop
:       cmp     #$4E                    ; PgDn: a page on
        bne     :+
        lda     top
        clc
        adc     vis
        jsr     scrollto
        jmp     loop
:       cmp     #$4A                    ; Home: the start
        bne     :+
        lda     #0
        jsr     scrollto
        jmp     loop
:       cmp     #$4D                    ; End: the last page ($FFFF is clamped to it)
        jne     loop
        lda     #$FFFF
        jsr     scrollto
        jmp     loop
@ctrl:  lda     ui_ev+2                 ; HID usage: $04 = A ... $1D = Z
        cmp     #$12                    ; ctrl+O
        jeq     m_open
        cmp     #$0A                    ; ctrl+G
        jeq     m_goto
        jmp     loop                    ; (ctrl+W never comes: the kernel sends WE_CLOSE)

; ---- WE_MENU: a = menu (0 = File, 1 = View), b = item (separators count)
onmenu: lda     ui_ev+4
        tax                             ; X = item
        lda     ui_ev+2
        bne     @view
        cpx     #0
        jeq     m_open                  ; File > Open...
        cpx     #2
        jeq     quit                    ; File > Close (item 1 is the separator)
        jmp     loop
@view:  cpx     #0
        jeq     m_goto                  ; View > Go to offset...
        cpx     #2
        bne     :+
        lda     #0                      ; View > Start of file
        jsr     scrollto
        jmp     loop
:       cpx     #3
        jne     loop
        lda     #$FFFF                  ; View > End of file
        jsr     scrollto
        jmp     loop

; ---- WE_RESIZE: a, b = the new content size. Lay everything out again and redraw.
onresize:
        lda     ui_ev+2
        sta     cw
        lda     ui_ev+4
        sta     ch
        jsr     relayout
        jmp     loop

; ---- WE_DROP: a file dragged from Files (or the Desktop) and released on our window.
; SYS_WDROPGET gives the string that came with it: the file's full path.
ondrop: lda     ui_ev+1
        and     #$00FF                  ; the window it was dropped on (ours)
        ptr     path                    ; (ptr sets X and Y only)
        sys     SYS_WDROPGET
        jcs     loop
        jsr     load
        jmp     loop

; ---- File > Open... (ctrl+O): the file dialog, then load the path it gives
m_open: stz     path                    ; no suggested name
        lda     #0                      ; 0 = an Open dialog
        ldx     #.loword(path)          ; a 128-byte buffer for the full path
        ldy     #.loword(t_open)        ; the dialog's title
        jsr     ui_filedlg              ; C set: cancelled
        jcs     loop
        jsr     load
        jmp     loop

; ---- View > Go to offset... (ctrl+G): ask for a hexadecimal offset, show its line
m_goto: lda     hasfile
        jeq     loop
        lda     top                     ; suggest the offset shown now (all selected:
        asl     a                       ;   typing replaces it)
        asl     a
        asl     a
        asl     a
        ldx     #.loword(askbuf)
        jsr     hex6
        ldx     #.loword(ask)
        jsr     ui_ask                  ; C set: cancelled
        jcs     loop
        jsr     parsehex                ; -> A = the offset (at most the last byte)
        bcc     :+
        ldx     #.loword(al_hex)        ; not a hexadecimal number
        jsr     ui_alert
        jmp     loop
:       lsr     a                       ; offset / 16 = its line: on top (or as near
        lsr     a                       ;   the top as the end of the file allows)
        lsr     a
        lsr     a
        jsr     scrollto
        jmp     loop

; ---- the end: close the window, stop the window system if we started it
quit:   lda     z:win                   ; (closing is optional: exit closes our windows)
        sys     SYS_WCLOSE
        lda     z:wsown
        beq     :+
        sys     SYS_WSSTOP              ; we started the window system: stop it
:       exit    0

; ================================================================ loading a file
; path = the file's path -> read into the bank (at most 64 KB), shown from its start.
; On an error: an alert "Cannot open NAME." and the view as it was (unless the reading
; itself failed half way: then the bank holds a part of it, and we show no file).
load:   jsr     basename                ; fname = the name part, for the title and messages
        ptr     stblk                   ; stat {u24 path, u24 out}: the size, the attributes
        sys     SYS_STAT
        jcs     @fail
        lda     statout+4               ; attributes: bit 4 = a folder
        and     #$0010
        jne     @fail
        lda     statout                 ; u32 size
        sta     fsize
        lda     statout+2
        sta     fsize+2
        ptr     path
        lda     #O_READ
        sys     SYS_OPEN                ; -> A = handle
        jcs     @fail
        sta     z:fh
        stz     n2
        lda     #0                      ; the first 32 KB to bank:0000
        jsr     rdhalf
        jcs     @rderr
        sta     n1
        cmp     #HALF                   ; all of it: maybe there is more
        bne     @read
        lda     #HALF                   ; the next 32 KB to bank:8000
        jsr     rdhalf
        jcs     @rderr
        sta     n2
@read:  lda     z:fh
        sys     SYS_CLOSE
; total = lines, lastoff = the offset of the last byte (n1 + n2 - 1: up to $FFFF, while
; n1 + n2 itself may be 65536, one too many for 16 bits)
        lda     n1
        bne     :+
        stz     total                   ; an empty file: no lines
        stz     lastoff
        bra     @ok
:       dec     a
        clc
        adc     n2
        sta     lastoff
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        inc     a
        sta     total
@ok:    lda     #1
        sta     hasfile
        stz     top
        jsr     settitle
        jsr     setmenus
        print   "hexview: "             ; the console line (the log under the Desktop)
        ptr     fname
        jsr     out_str
        print   ", "
        jsr     u32dec
        ptr     numbuf
        jsr     out_str
        print   " bytes\n"
        jmp     relayout                ; new scroll bar range, all lines, the status

@rderr: lda     z:fh                    ; the bank holds a part of it now: no file
        sys     SYS_CLOSE
        jsr     nofile
        jsr     settitle
        jsr     setmenus
        jsr     relayout
@fail:  ldx     #.loword(s_cant)        ; "Cannot open NAME."
        ldy     #.loword(msgbuf)
        jsr     ui_strcpy
        ldx     #.loword(fname)
        ldy     #.loword(msgbuf + 12)   ; (after "Cannot open ")
        jsr     ui_strcpy
        clc
        adc     #.loword(msgbuf + 12)
        tax
        lda     #'.'                    ; '.' and the 0 after it (16-bit store)
        sta     a:0,x
        ldx     #.loword(al_open)
        jmp     ui_alert

; A = where in the bank -> read 32 KB of handle fh there; A = bytes read, C set: error.
; The block is {u8 handle, u24 buffer, u16 length}: the buffer is bank:A.
rdhalf: sta     iob+1                   ; buffer offset (iob+1, iob+2)
        sep     #$20
        .a8
        lda     z:fh
        sta     iob                     ; u8 handle
        lda     z:fptr+2
        sta     iob+3                   ; the buffer's bank byte
        rep     #$20
        .a16
        lda     #HALF
        sta     iob+4                   ; u16 length
        ptr     iob
        sys     SYS_READ                ; -> A = bytes read (fewer: the end of the file)
        rts

; nothing loaded
nofile: stz     hasfile
        stz     total
        stz     lastoff
        stz     top
        stz     fsize
        stz     fsize+2
        rts

; fname = the part of path after its last '/' (at most 21 characters: the title holds 31)
basename:
        ldx     #0
        ldy     #0                      ; Y = where the name starts
:       lda     path,x
        and     #$00FF
        beq     :++
        inx
        cmp     #'/'
        bne     :+
        txy                             ; a '/': the name starts after it
:       bra     :--
:       ldx     #0
:       lda     path,y
        and     #$00FF
        beq     :+
        cpx     #21
        bcs     :+
        sep     #$20
        .a8
        sta     fname,x
        rep     #$20
        .a16
        inx
        iny
        bra     :-
:       sep     #$20
        .a8
        stz     fname,x
        rep     #$20
        .a16
        rts

; the window's title: "Hex View" or "Hex View: NAME"
settitle:
        ldx     #.loword(t_win)
        ldy     #.loword(tbuf)
        jsr     ui_strcpy
        lda     hasfile
        beq     :+
        ldx     #.loword(s_colon)
        ldy     #.loword(tbuf + 8)      ; (after "Hex View")
        jsr     ui_strcpy
        ldx     #.loword(fname)
        ldy     #.loword(tbuf + 10)
        jsr     ui_strcpy
:       lda     z:win
        ptr     tbuf
        sys     SYS_WTITLE
        rts

; View's items dimmed without a file (they start with a state byte: see menus)
setmenus:
        ldy     #MS_DIM
        lda     hasfile
        beq     :+
        ldy     #0
:       lda     z:win                   ; (a syscall keeps X and Y)
        ldx     #1 | (0 << 8)           ; menu 1 (View), item 0: Go to offset...
        sys     SYS_WMSTATE
        lda     z:win
        ldx     #1 | (2 << 8)           ; item 2: Start of file
        sys     SYS_WMSTATE
        lda     z:win
        ldx     #1 | (3 << 8)           ; item 3: End of file
        sys     SYS_WMSTATE
        rts

; ================================================================ the layout
; From the content size cw x ch: the box, the lines it holds (vis), the characters a line
; shows (ncols), the scroll bar's place and range, the status line's place. Then draws
; it all, the screen held so that nothing shows half drawn.
relayout:
        lda     cw                      ; (a window made very small: laid out as MINW x MINH;
        cmp     #MINW                   ;   what does not fit is clipped)
        bcs     :+
        lda     #MINW
:       sec
        sbc     #2 * BOXX
        sta     bw                      ; box width
        sec
        sbc     #2 + UI_SBW
        sta     tw                      ; the white text area inside it, left of the bar
        sec
        sbc     #2 * PAD                ; characters that fit: (tw - 2 PAD) / 8, at most 73
        lsr     a
        lsr     a
        lsr     a
        cmp     #COLS
        bcc     :+
        lda     #COLS
:       sta     ncols
        lda     ch
        cmp     #MINH
        bcs     :+
        lda     #MINH
:       sta     z:t0
        sec
        sbc     #UI_GAP + UI_LINE
        sta     statusy                 ; the status line: 8 above the bottom
        lda     z:t0
        sec
        sbc     #BOXY + 4 + UI_LINE + UI_GAP
        sta     bh                      ; box height
        sec
        sbc     #2 + 2 * PAD            ; lines that fit: (bh - 2 - 2 PAD) / 12
        ldy     #0
:       cmp     #ROWH
        bcc     :+
        sbc     #ROWH
        iny
        bra     :-
:       tya
        bne     :+
        inc     a                       ; (at least one)
:       cmp     #MAXVIS
        bcc     :+
        lda     #MAXVIS
:       sta     vis
        jsr     setmax                  ; maxtop for this vis; top kept in range
        lda     top
        cmp     maxtop
        bcc     :+
        lda     maxtop
        sta     top
:
; the scroll bar: inside the box's right edge, as high as the inside of the box
        lda     #BOXX + 1
        clc
        adc     tw
        sta     sb+CT_X
        lda     #BOXY + 1
        sta     sb+CT_Y
        lda     #UI_SBW
        sta     sb+CT_W
        lda     bh
        sec
        sbc     #2
        sta     sb+CT_H
        lda     top
        sta     sb+SB_POS               ; position = the top line
        lda     maxtop
        sta     sb+SB_MAX               ; the largest top line
        lda     vis
        sta     sb+SB_PAGE              ; a page = the lines shown
        lda     #1
        sta     sb+SB_STEP              ; an arrow = one line
; draw: the body, the box, the lines, the bar, the status line
        lda     #1
        sys     SYS_WSHOLD              ; the screen waits until we release it
        lda     z:win
        sta     z:ui_win                ; (the ui_* drawing helpers draw in ui_win)
        stz     z:ui_x
        stz     z:ui_y
        lda     cw
        sta     z:ui_w
        lda     ch
        sta     z:ui_h
        lda     #WD_FILL | (C_BODY << 8) ; all of it: the old box may be anywhere now
        jsr     ui_rect
        lda     #BOXX
        sta     z:ui_x
        lda     #BOXY
        sta     z:ui_y
        lda     bw
        sta     z:ui_w
        lda     bh
        sta     z:ui_h
        lda     #WD_FILL | (C_WHITE << 8)
        jsr     ui_rect
        lda     #1                      ; 1 = sunken: dark top-left, white bottom-right
        jsr     ui_bevel
        jsr     drawall
        ldx     #.loword(sb)
        jsr     ui_draw
        jsr     status
        lda     #0
        sys     SYS_WSHOLD
        rts

; maxtop = total - vis (0 when everything fits)
setmax: lda     total
        sec
        sbc     vis
        bcs     :+
        lda     #0
:       sta     maxtop
        rts

; ================================================================ drawing the lines
; every line of the box
drawall:
        stz     z:row
:       lda     z:row
        jsr     drawrow
        inc     z:row
        lda     z:row
        cmp     vis
        bcc     :-
        rts

; A = a row of the box (0 = the top) -> its line drawn: the file's line top + A.
; One win_draw: the text with its paper (white), so it replaces what was there.
drawrow:
        pha
        clc
        adc     top
        jsr     mkline                  ; -> lbuf
        pla
        jsr     mul12
        clc
        adc     #TXTY
        sta     blk+6                   ; y (the top of the line)
        lda     #WD_TEXT | (C_BLACK << 8)
        sta     blk                     ; op, c1 = ink
        lda     #C_WHITE | (1 << 8)
        sta     blk+2                   ; c2 = paper, font 1 = fixed 8 x 12
        lda     #TXTX
        sta     blk+4                   ; x
        lda     #.loword(lbuf)
        sta     blk+12                  ; u24 ptr: the string (offset, then the bank:
        lda     #^lbuf                  ;   this 16-bit store writes blk+15 too: the block
        sta     blk+14                  ;   is 16 bytes long for that)
        lda     z:win
        ptr     blk
        sys     SYS_WDRAW
        rts

; A = a line of the file -> lbuf = its text, cut to ncols characters:
;   0         1         2         3         4         5         6         7
;   0123456789012345678901234567890123456789012345678901234567890123456789012
;   000120  4C 69 6E 65 20 30 30 30 30 31 20 6F 66 20 74 68  Line 00001 of th
; A line past the end of the file (the box is taller than the file): spaces.
mkline: cmp     total
        bcc     @data
        ldx     #0
        lda     #' ' | (' ' << 8)
:       sta     lbuf,x
        inx
        inx
        cpx     #COLS + 1
        bcc     :-
        jmp     @cut
@data:  asl     a                       ; line * 16 = the offset of its first byte
        asl     a
        asl     a
        asl     a
        sta     z:off
        ldx     #.loword(lbuf)          ; the offset: "00" and four hex digits (a file
        jsr     hex6                    ;   in one bank is under $10000)
        lda     #' ' | (' ' << 8)
        sta     lbuf+6
        ldx     #.loword(lbuf + 8)      ; X = where the next hex pair goes
        lda     #.loword(lbuf + 57)
        sta     z:cpos                  ; where the next character goes
        ldy     z:off                   ; Y = the byte's offset in the bank
@byte:  cpy     lastoff                 ; past the last byte (the last line of a file)?
        beq     :+
        bcs     @none
:       sep     #$20                    ; read one byte: 8-bit, so that the read never
        .a8                             ;   touches the byte after it (byte $FFFF would
        lda     [fptr],y                ;   read the next bank: a fault)
        rep     #$20
        .a16
        and     #$00FF
        sta     z:bval
        jsr     hex8                    ; two hex digits at X, X + 2
        lda     z:bval
        cmp     #' '                    ; printable (32-126): itself; else '.'
        bcc     :+
        cmp     #127
        bcc     @put
:       lda     #'.'
        bra     @put
@none:  lda     #' ' | (' ' << 8)       ; no byte: two spaces and a space
        sta     a:0,x
        inx
        inx
        lda     #' '
@put:   phx                             ; the character column
        ldx     z:cpos
        sep     #$20
        .a8
        sta     a:0,x
        lda     #' '
        plx                             ; (plx with I16: two bytes, as phx pushed)
        sta     a:0,x                   ; a space after the hex pair
        rep     #$20
        .a16
        inx
        inc     z:cpos
        iny
        lda     z:cpos
        cmp     #.loword(lbuf + 57 + 16)
        bcc     @byte
        sep     #$20
        .a8
        lda     #' '
        sta     lbuf+56                 ; two spaces before the characters
        rep     #$20
        .a16
@cut:   ldx     ncols                   ; the end: as many characters as fit the box
        sep     #$20
        .a8
        stz     lbuf,x
        rep     #$20
        .a16
        rts

; A = a byte (0-255), X = an address in the code bank -> two hex digits there; X + 2.
; Keeps Y.
hex8:   phy
        pha
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        tay
        sep     #$20
        .a8
        lda     hexd,y
        sta     a:0,x
        rep     #$20
        .a16
        pla
        and     #$000F
        tay
        sep     #$20
        .a8
        lda     hexd,y
        sta     a:1,x
        rep     #$20
        .a16
        inx
        inx
        ply
        rts

; A = an offset, X = an address -> "00XXXX" and a 0 there (an offset of 6 digits); X + 6.
; Keeps Y.
hex6:   sta     z:t1
        lda     #'0' | ('0' << 8)
        sta     a:0,x
        inx
        inx
        lda     z:t1
        xba
        and     #$00FF
        jsr     hex8
        lda     z:t1
        and     #$00FF
        jsr     hex8
        sep     #$20
        .a8
        stz     a:0,x
        rep     #$20
        .a16
        rts

; A = A * 12 (rows to pixels). C clear after.
mul12:  sta     z:t0
        asl     a
        adc     z:t0                    ; 3 A (C was clear: A < $8000)
        asl     a
        asl     a                       ; 12 A
        rts

; ================================================================ scrolling
; A = the top line wanted (clamped to 0 .. maxtop). The lines that stay on screen move
; with one WD_COPY of the box's inside; only the lines that come in are drawn. A jump of
; a page or more draws every line. Then the scroll bar's thumb and the status line.
scrollto:
        cmp     maxtop
        bcc     :+
        lda     maxtop
:       cmp     top
        bne     :+
        rts                             ; no change
:       sta     z:ntop
        lda     #1
        sys     SYS_WSHOLD              ; copy + new lines + thumb: shown as one change
        lda     z:ntop
        sec
        sbc     top
        bcc     @back
; forwards by d = ntop - top lines: rows d .. vis-1 move up to 0 .., rows vis-d .. come in
        sta     z:d
        cmp     vis
        bcs     @all
        jsr     mul12
        adc     #TXTY
        pha                             ; source y = the top of row d
        lda     vis
        sec
        sbc     z:d
        jsr     mul12
        tay                             ; height = (vis - d) rows
        ldx     #TXTY                   ; destination y = the top of row 0
        pla
        jsr     copyrows
        lda     z:ntop
        sta     top
        lda     vis
        sec
        sbc     z:d
        sta     z:row                   ; the first row that comes in
:       lda     z:row
        jsr     drawrow
        inc     z:row
        lda     z:row
        cmp     vis
        bcc     :-
        bra     @done
; backwards by d = top - ntop lines: rows 0 .. vis-d-1 move down to d .., rows 0 .. d-1
; come in
@back:  eor     #$FFFF                  ; d = -(ntop - top)
        inc     a
        sta     z:d
        cmp     vis
        bcs     @all
        lda     vis
        sec
        sbc     z:d
        jsr     mul12
        tay                             ; height = (vis - d) rows
        lda     z:d
        jsr     mul12
        adc     #TXTY
        tax                             ; destination y = the top of row d
        lda     #TXTY                   ; source y = the top of row 0
        jsr     copyrows
        lda     z:ntop
        sta     top
        stz     z:row
:       lda     z:row
        jsr     drawrow
        inc     z:row
        lda     z:row
        cmp     z:d
        bcc     :-
        bra     @done
@all:   lda     z:ntop                  ; a page or more: every line
        sta     top
        jsr     drawall
@done:  lda     sb+SB_POS               ; the thumb: when the bar itself moved, it shows
        cmp     top                     ;   the new position already
        beq     :+
        lda     top                     ; ui_sbpos: SB_POS = where the thumb is drawn now,
        ldx     #.loword(sb)            ;   A = the new position
        jsr     ui_sbpos
:       jsr     status
        lda     #0
        sys     SYS_WSHOLD
        rts

; A = source y, X = destination y, Y = height: the strip of the box's inside (all its
; width left of the scroll bar) moves up or down. WD_COPY: x, y, w, h = the source; the
; destination x in c1 | c2 << 8, its y in the low word of ptr. They may overlap.
copyrows:
        sta     blk+6                   ; source y
        stx     blk+12                  ; destination y
        sty     blk+10                  ; height
        lda     #WD_COPY
        sta     blk                     ; op (and c1, rewritten next)
        lda     #BOXX + 1
        sta     blk+1                   ; destination x (c1 | c2 << 8)
        sta     blk+4                   ; source x: the same (a vertical move)
        lda     tw
        sta     blk+8                   ; width
        lda     z:win
        ptr     blk
        sys     SYS_WDRAW
        rts

; ================================================================ the status line
; "70000 bytes (the first 64 KB shown)   Top line at offset 00FF00", in the UI font on the
; body under the box; the rest of the line filled with the body colour (a shorter text
; must cover a longer one). Two win_draw calls, no blank moment between them.
status: stz     z:sl                    ; build it in stbuf
        lda     hasfile
        bne     :+
        ldx     #.loword(s_nofile)
        jsr     scat
        bra     @draw
:       jsr     u32dec
        ldx     #.loword(numbuf)
        jsr     scat
        ldx     #.loword(s_bytes)
        jsr     scat
        lda     fsize+2                 ; over 65,536 bytes: only a part is shown
        beq     @off
        cmp     #1
        bne     :+
        lda     fsize
        beq     @off
:       ldx     #.loword(s_trunc)
        jsr     scat
@off:   ldx     #.loword(s_off)
        jsr     scat
        lda     z:sl
        clc
        adc     #.loword(stbuf)
        tax
        lda     top
        asl     a
        asl     a
        asl     a
        asl     a
        jsr     hex6
@draw:  lda     z:win
        sta     z:ui_win
        lda     #BOXX
        sta     z:ui_x
        lda     statusy
        sta     z:ui_y
        stz     z:ui_font               ; the UI font
        ldx     #.loword(stbuf)
        lda     #C_BLACK | (C_BODY << 8) ; ink | paper << 8
        jsr     ui_text
        ldx     #.loword(stbuf)
        lda     #0
        jsr     ui_twidth               ; -> A = its width
        clc
        adc     #BOXX
        sta     z:ui_x                  ; from its end to the right edge: body colour
        lda     cw
        sec
        sbc     z:ui_x
        bcc     @out
        beq     @out
        sta     z:ui_w
        lda     #UI_LINE
        sta     z:ui_h
        lda     #WD_FILL | (C_BODY << 8)
        jsr     ui_rect
@out:   rts

; X = a string -> appended to stbuf at sl
scat:   lda     z:sl
        clc
        adc     #.loword(stbuf)
        tay
        jsr     ui_strcpy               ; -> A = its length
        clc
        adc     z:sl
        sta     z:sl
        rts

; fsize (32 bits) -> numbuf in decimal. Divides by 10 bit by bit (32 steps per digit);
; the digits come out last first and are turned round at the end.
u32dec: lda     fsize
        sta     z:q
        lda     fsize+2
        sta     z:q+2
        ldy     #0                      ; digits made
@digit: stz     z:rem
        ldx     #32
:       asl     z:q                     ; q = q * 2, its top bit into rem
        rol     z:q+2
        rol     z:rem
        lda     z:rem
        cmp     #10
        bcc     :+
        sbc     #10                     ; rem >= 10: subtract, a 1 bit in the quotient
        sta     z:rem
        inc     z:q
:       dex
        bne     :--
        lda     z:rem
        ora     #'0'
        sep     #$20
        .a8
        sta     dbuf,y
        rep     #$20
        .a16
        iny
        lda     z:q
        ora     z:q+2
        bne     @digit
        ldx     #0
:       dey                             ; turn them round into numbuf
        sep     #$20
        .a8
        lda     dbuf,y
        sta     numbuf,x
        rep     #$20
        .a16
        inx
        cpy     #0
        bne     :-
        sep     #$20
        .a8
        stz     numbuf,x
        rep     #$20
        .a16
        rts

; askbuf = a hexadecimal number (spaces and a leading '$' allowed) -> A = it, at most
; lastoff (the last byte). C set: no digits, or something else than a hex digit.
parsehex:
        stz     z:t0                    ; the value
        stz     z:t1                    ; digits seen
        stz     z:t2                    ; 1: it went over $FFFF
        ldx     #0
@next:  lda     askbuf,x
        and     #$00FF
        beq     @end
        inx
        cmp     #' '
        beq     @next
        cmp     #'$'
        beq     @next
        cmp     #'0'                    ; '0'-'9' -> 0-9
        bcc     @bad
        cmp     #'9' + 1
        bcc     @dec
        and     #$00DF                  ; a-f -> A-F
        cmp     #'A'
        bcc     @bad
        cmp     #'F' + 1
        bcs     @bad
        sbc     #'A' - 10 - 1           ; (C clear here: subtracts one more)
        bra     @add
@dec:   sec
        sbc     #'0'
@add:   sta     z:t3
        lda     z:t0
        and     #$F000                  ; a digit more would not fit 16 bits
        beq     :+
        lda     #1
        sta     z:t2
:       lda     z:t0
        asl     a
        asl     a
        asl     a
        asl     a
        ora     z:t3
        sta     z:t0
        inc     z:t1
        bra     @next
@end:   lda     z:t1
        beq     @bad
        lda     z:t2
        bne     @last
        lda     z:t0
        cmp     lastoff
        bcc     @ok
@last:  lda     lastoff
@ok:    clc
        rts
@bad:   sec
        rts

; ================================================================ data
        .segment "RODATA"
wopen:  .word   WIN_X, WIN_Y, WIN_W, WIN_H ; {i16 x, y (outer top left), u16 content w, h,
        .faraddr t_win                  ;  u24 title, u8 flags}
        .byte   WF_RESIZE               ; a size grip: WE_RESIZE
t_win:  .byte   "Hex View", 0
s_colon: .byte  ": ", 0
; The menus. The View items start with a state byte (MS_STATE | MS_DIM: greyed) so that
; SYS_WMSTATE can change them: setmenus enables them once a file is loaded.
menus:  .byte   "File", 0
        .byte   "Open...", 9, "Ctrl+O", 0      ; 9 = TAB: the shortcut text, right-aligned
        .byte   "-", 0                         ; a separator (it counts as an item)
        .byte   "Close", 9, "Ctrl+W", 0
        .byte   0                              ; end of the File menu
        .byte   "View", 0
        .byte   MS_STATE | MS_DIM, "Go to offset...", 9, "Ctrl+G", 0
        .byte   "-", 0
        .byte   MS_STATE | MS_DIM, "Start of file", 9, "Home", 0
        .byte   MS_STATE | MS_DIM, "End of file", 9, "End", 0
        .byte   0
        .byte   0                              ; end of the menus
t_open: .byte   "Open a file", 0
hexd:   .byte   "0123456789ABCDEF"
s_nofile: .byte "No file. Open one with File > Open... or drop one here from Files.", 0
s_bytes: .byte  " bytes", 0
s_trunc: .byte  " (the first 64 KB shown)", 0
s_off:  .byte   "      Top line at offset ", 0
s_cant: .byte   "Cannot open ", 0       ; (12 characters: see load)
t_title: .byte  "Hex View", 0
s_ok:   .byte   "OK", 0
s_go:   .byte   "Go", 0
m_mem:  .byte   "Not enough memory for Hex View.", 10, "Close a program and try again.", 0
m_hex:  .byte   "The offset is a hexadecimal number,", 10, "such as 1F0.", 0
t_goto: .byte   "Go to offset", 0
p_goto: .byte   "Offset (hexadecimal):", 0
al_mem: .word   1, t_title, m_mem, s_ok, 0, 0      ; ui_alert blocks: kind 1 = warning
al_open: .word  1, t_title, msgbuf, s_ok, 0, 0
al_hex: .word   1, t_title, m_hex, s_ok, 0, 0
ask:    .word   t_goto, p_goto, askbuf, 8, s_go   ; ui_ask: title, prompt, buffer, size, OK
stblk:  .faraddr path, statout          ; SYS_STAT {u24 path, u24 out}

        .segment "DATA"                 ; controls: the library writes into them
ctls:   .addr   sb, 0                   ; the control list: just the scroll bar
sb:     .byte   UT_VSCROLL, 0           ; type, window (set at the start)
        .word   0, 0, UI_SBW, 0, 0      ; x, y, w, h, flags (set by relayout)
        .word   0, 0, 0, 1, 0, 0        ; SB_POS, SB_MAX, SB_PAGE, SB_STEP, internal

        .segment "BSS"
argl:   .res    2                       ; the argument's length and address (bank 0)
argx:   .res    2
cw:     .res    2                       ; the content size
ch:     .res    2
bw:     .res    2                       ; the box size
bh:     .res    2
tw:     .res    2                       ; the white text area's width (left of the bar)
statusy: .res   2                      ; the status line's y
vis:    .res    2                       ; lines in the box
ncols:  .res    2                       ; characters of a line shown (73: all)
hasfile: .res   2                       ; 1: a file is loaded
fsize:  .res    4                       ; its size (u32: it may be over 64 KB)
total:  .res    2                       ; its lines (of what was loaded)
lastoff: .res   2                       ; the offset of its last byte
top:    .res    2                       ; the line at the top of the box
maxtop: .res    2                       ; the largest top
n1:     .res    2                       ; bytes read into the first / second half
n2:     .res    2
path:   .res    128                     ; the file's path (dialog, argument, drop)
fname:  .res    24                      ; its name part
tbuf:   .res    40                      ; the window title
msgbuf: .res    48                      ; "Cannot open NAME."
lbuf:   .res    80                      ; a line of the dump
stbuf:  .res    128                     ; the status line
numbuf: .res    12                      ; a decimal number
dbuf:   .res    12                      ; (its digits, last first)
askbuf: .res    8                       ; Go to offset's field
statout: .res   10                      ; SYS_STAT's record: u32 size, u8 attr, u32 time
iob:    .res    6                       ; {u8 handle, u24 buffer, u16 length}
blk:    .res    16                      ; a win_draw block

        .segment "ZEROPAGE"
wsown:  .res    2                       ; 1: we started the window system
win:    .res    2                       ; our window
fptr:   .res    4                       ; long pointer to the file's bank: bank:0000
fh:     .res    2                       ; the open file's handle
row:    .res    2                       ; a row counter
ntop:   .res    2                       ; scrollto: the new top
d:      .res    2                       ; scrollto: lines moved
off:    .res    2                       ; mkline: the line's first offset
cpos:   .res    2                       ; mkline: where the next character goes
bval:   .res    2                       ; mkline: the byte
sl:     .res    2                       ; status: its length so far
q:      .res    4                       ; u32dec: the number being divided
rem:    .res    2                       ; u32dec: the remainder
t0:     .res    2                       ; scratch
t1:     .res    2
t2:     .res    2
t3:     .res    2
