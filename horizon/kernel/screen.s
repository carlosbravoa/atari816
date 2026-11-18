; screen.s - text console on Marga: 78 x 29 characters of 8x12 pixels inside a border
; (8 pixels left and right, 6 lines top and bottom, paper colour), mode 1 (640x360, 4 bpp).
; Every console byte goes here as well as to DBG_OUT.
;
; Framebuffer: banks $7C-$7F (kernel owned), FB_ROWS = 60 cell rows of 12 lines, stride
; 320 bytes, so one cell row is 3840 bytes = 15 x 256 and NV_BASE (256-byte aligned) can
; point at any cell row. The screen shows 30 cell rows starting at scr_top; text row r is
; drawn 6 lines into cell row r, so the border lines and columns are never drawn and stay
; paper colour. A new line at the bottom moves NV_BASE down one cell row, clears the cell
; row that comes into view and the 6 border lines at the top (they still hold the lower
; half of the row that scrolled out). When the window reaches the end of the buffer, the
; visible rows are copied back to the top once and NV_BASE returns to the start.
; Pixels: 4 bpp, high nibble left. Palette 0 paper (dark blue), 1 ink, 2 cursor, 3 ink
; under the cursor. The cursor is an underline on cell line 11, drawn by XOR with $22 so
; drawing it twice removes it.
; Long operations (clears, the copy-back) work in steps of at most 2 KB (about 1 ms of
; MVN); between steps they service interrupts and yield when that is due, if the caller
; allows it (scr_coop: console writer in task context).
; Escape sequences (a VT52 subset, for full-screen programs): ESC Y row+32 col+32 moves
; the cursor, ESC K clears to the end of the line, ESC p / ESC q inverse video on / off,
; ESC f / ESC e text cursor off / on, ESC E clears the screen. ESC K clears in the current
; video mode (with ESC p on, it fills the rest of the line as a bar). They also reach
; DBG_OUT.
; scr_putc keeps A X Y and sets D/DBR itself, so it works from any kernel context.

        .a16
        .i16

NV_CTRL    = $00D900
NV_BASE    = $00D901
NV_STRIDE  = $00D904
PAL_IDX    = $00D910
PAL_R      = $00D911

FB_BANK    = $7C
FB_NBANKS  = 4
CELL_H     = 12                         ; character cell: 8 x 12 pixels
SCR_COLS   = 78                         ; text area: 78 x 29 characters, inside a border of
SCR_ROWS   = 29                         ; 8 pixels left/right and 6 lines top/bottom
WIN_ROWS   = 30                         ; the window: 30 cell rows of 12 lines (360 lines)
TXT_OFFSET = FB_STRIDE * 6 + 4          ; text starts 6 lines down, 8 pixels (4 bytes) in
FB_ROWS    = 60
FB_STRIDE  = 320
ROW_BYTES  = FB_STRIDE * CELL_H         ; 3840 = 15 pages
ROW_PAGES  = ROW_BYTES / 256
CHUNK      = 2048                       ; longest single clear/copy step (about 1 ms)
SCR_CTRL   = $03                        ; ENABLE, mode 1

scr_init:
        jsr     scr_palette
        jmp     scr_init2

; the console's palette entries 0-5 (also after the desktop used the whole palette)
scr_palette:
        lda     #0
        ldx     #.loword(pal_tab)
        ldy     #6
        jmp     pal_load

scr_init2:
        lda     #FB_STRIDE
        sta     f:NV_STRIDE
        sta     vs_stride
        stz     scr_top
        stz     scr_row
        stz     scr_col
        stz     scr_coop
        ldx     #0                      ; clear the 45 visible rows
:       phx
        txa
        jsr     scr_clear_row
        plx
        inx
        cpx     #WIN_ROWS
        bne     :-
        jsr     scr_set_base
        lda     #SCR_CTRL
        sta     scr_ctrl
        jsr     nv_ctrl
        lda     #1
        sta     scr_on
        jmp     scr_cursor

; palette: R G B for entries 0-3
pal_tab:
        .byte   $10, $20, $58           ; 0 paper: dark blue
        .byte   $D8, $E0, $F0           ; 1 ink: light grey-blue
        .byte   $F0, $C0, $40           ; 2 cursor: amber
        .byte   $10, $20, $58           ; 3 ink under the cursor: paper colour
        .byte   $00, $00, $00           ; 4 pointer outline: black
        .byte   $FF, $FF, $FF           ; 5 pointer fill: white

; ---- one character (A, low byte) ----
scr_putc:
        php
        rep     #$30
        pha
        phx
        phy
        phd
        phb
        pea     KBANK * $0101
        plb
        plb
        tax
        lda     #KDP
        tcd
        lda     scr_on
        jeq     @out
        lda     scr_hold                ; a writer that hides the cursor around a whole
        bne     :+                      ; string (con_write) sets scr_hold
        jsr     scr_cursor              ; off
:
        txa
        and     #$00FF
        ldy     scr_esc                 ; inside an escape sequence?
        beq     :+
        jsr     scr_escape
        bra     @done
:       cmp     #27
        bne     :+
        lda     #1
        sta     scr_esc
        bra     @done
:       cmp     #' '
        bcc     @ctl
        cmp     #$7F
        bcs     @done
        ldx     scr_col                 ; printable: wrap first if the line is full
        cpx     #SCR_COLS
        bcc     :+
        pha
        stz     scr_col
        jsr     scr_newline
        pla
:       jsr     scr_glyph
        inc     scr_col
        bra     @done
@ctl:   cmp     #10
        bne     :+
        stz     scr_col
        jsr     scr_newline
        bra     @done
:       cmp     #13
        bne     :+
        stz     scr_col
        bra     @done
:       cmp     #8
        bne     :+
        lda     scr_col
        beq     @done
        dec     scr_col
        bra     @done
:       cmp     #9
        bne     :+
        lda     scr_col
        ora     #7
        inc     a
        cmp     #SCR_COLS
        bcc     @tab
        lda     #SCR_COLS
@tab:   sta     scr_col
        bra     @done
:       cmp     #12
        bne     @done
        jsr     scr_clear
@done:  lda     scr_hold
        bne     @out
        jsr     scr_cursor              ; on
@out:   plb
        pld
        ply
        plx
        pla
        plp
        rts

; kp1 = address of text row (scr_top + scr_row), column scr_col
scr_cell:
        lda     scr_top
        clc
        adc     scr_row
        jsr     scr_row_addr
        lda     scr_col
        asl     a
        asl     a
        clc
        adc     #TXT_OFFSET
        clc
        adc     kp1
        sta     kp1
        bcc     :+
        inc     kp1+2
:       rts

; kp1 = address of text row A (0-89), column 0: $7C0000 + A * 2560
scr_row_addr:
        jsr     row_pages
        clc
        adc     #FB_BANK * 256          ; page number of the row
        pha
        and     #$00FF
        xba
        sta     kp1                     ; low 16 bits
        pla
        xba
        and     #$00FF
        sta     kp1+2                   ; bank (high byte of kp1+3 = 0)
        rts

; draw character A (32-126) at the cursor cell
scr_glyph:
        asl     a
        asl     a
        sta     kt1
        asl     a
        clc
        adc     kt1
        sta     kt1                     ; font offset: A * 12
        jsr     scr_cell
        ldx     kt1
        ldy     #0
        lda     #CELL_H
        sta     kt2
@line:  lda     font,x
        and     #$00FF
        pha
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        asl     a
        clc
        adc     scr_invoff              ; 0 normal, 32 inverse video
        phx
        tax
        lda     nib_tab,x               ; left 4 pixels
        sta     [kp1],y
        iny
        iny
        lda     3,s
        and     #$000F
        asl     a
        clc
        adc     scr_invoff
        tax
        lda     nib_tab,x               ; right 4 pixels
        sta     [kp1],y
        plx
        pla
        inx
        tya
        clc
        adc     #FB_STRIDE - 2
        tay
        dec     kt2
        bne     @line
        rts

; a task exits: if it switched the cursor off or inverse video on, switch them back
; (a killed full-screen program must not leave the console without a cursor)
scr_task_exit:
        lda     cur
        inc     a
        cmp     scr_owner
        bne     @out
        stz     scr_owner
        stz     scr_invoff
        stz     scr_esc
        lda     scr_curoff
        beq     @out
        stz     scr_curoff
        lda     scr_hold                ; a writer holding the cursor shows it later
        bne     @out
        lda     scr_on
        beq     @out
        jsr     scr_cursor
@out:   rts

; hide the cursor for a run of characters (kernel context): scr_hold until scr_show
scr_hide:
        lda     scr_on
        beq     :+
        jsr     scr_cursor
        inc     scr_hold
:       rts
scr_show:
        lda     scr_hold
        beq     :+
        stz     scr_hold
        jsr     scr_cursor
:       rts

; toggle the cursor (underline on cell line 7) unless the column is past the end
scr_cursor:
        lda     scr_curoff
        bne     :+
        lda     scr_col
        cmp     #SCR_COLS
        bcs     :+
        jsr     scr_cell
        ldy     #FB_STRIDE * (CELL_H - 1)
        lda     [kp1],y
        eor     #$2222
        sta     [kp1],y
        iny
        iny
        lda     [kp1],y
        eor     #$2222
        sta     [kp1],y
:       rts

; next line: down one row, or scroll
scr_newline:
        lda     scr_row
        cmp     #SCR_ROWS - 1
        bcs     :+
        inc     scr_row
        rts
:       lda     scr_top
        cmp     #FB_ROWS - WIN_ROWS
        bcs     @back
        inc     scr_top                 ; window one row down: clear the new bottom row
        clc
        adc     #WIN_ROWS
        jsr     scr_clear_row
        bra     scr_topband
@back:  ; copy rows top+1 .. top+44 to 0 .. 43, a row at a time, then clear row 44
        stz     scr_i
@cp:    lda     scr_top
        sec
        adc     scr_i                   ; top + 1 + i
        jsr     scr_row_addr
        lda     kp1
        sta     scr_src
        lda     kp1+2
        sta     scr_src+2
        lda     scr_i
        jsr     scr_row_addr
        lda     kp1
        sta     scr_dst
        lda     kp1+2
        sta     scr_dst+2
        lda     #ROW_BYTES
        jsr     lcopy
        jsr     scr_poll
        inc     scr_i
        lda     scr_i
        cmp     #WIN_ROWS - 1
        bcc     @cp
        stz     scr_top
        lda     #WIN_ROWS - 1
        jsr     scr_clear_row
        ; fall through
; the top border (the window's first 4 lines) still holds the lower half of the text row
; that has just scrolled out: clear it, then show the new window
scr_topband:
        lda     scr_top
        jsr     scr_row_addr
        lda     kp1
        sta     scr_dst
        lda     kp1+2
        sta     scr_dst+2
        lda     #TXT_OFFSET - 4             ; the 6 border lines
        jsr     lfill0
        jmp     scr_set_base

; FF: clear the screen, cursor home
scr_clear:
        stz     scr_top
        stz     scr_row
        stz     scr_col
        stz     scr_i
:       lda     scr_i
        jsr     scr_clear_row
        jsr     scr_poll
        inc     scr_i
        lda     scr_i
        cmp     #WIN_ROWS
        bcc     :-
        jmp     scr_set_base

; NV_BASE = start of row scr_top (taken at the next frame)
scr_set_base:
        lda     ws_on                   ; (0.18) not while the desktop has the screen: a
        bne     :+                      ; program printing under it moved NV_BASE
        lda     scr_top
        jsr     row_pages
        clc
        adc     #FB_BANK * 256
        sta     f:NV_BASE+1             ; $D902 (address 15:8), $D903 (23:16)
        sta     vs_base+1
:       rts

; A = A * ROW_PAGES (15): the page offset of cell row A
row_pages:
        sta     kt0
        asl     a
        asl     a
        asl     a
        asl     a
        sec
        sbc     kt0
        rts

; clear cell row A (all 3840 bytes)
scr_clear_row:
        jsr     scr_row_addr
        lda     kp1
        sta     scr_dst
        lda     kp1+2
        sta     scr_dst+2
        lda     #ROW_BYTES
        ; fall through
; zero A bytes at scr_dst (24-bit), split at bank boundaries
lfill0: sta     scr_n
@loop:  lda     scr_n
        beq     @out
        jsr     @room
        sta     scr_m
        lda     scr_dst
        sta     kt2
        lda     scr_dst+2
        sta     kt3
        lda     scr_m
        jsr     kmemzero
        lda     scr_m
        jsr     adv_dst
        jsr     scr_poll                ; between chunks: interrupts, maybe others
        bra     @loop
@out:   rts
@room:  lda     #0                      ; bytes to the end of the bank, at most scr_n
        sec
        sbc     scr_dst
        beq     :+                      ; 0 = a whole bank
        cmp     scr_n
        bcc     :++
:       lda     scr_n
:       cmp     #CHUNK
        bcc     :+
        lda     #CHUNK
:       rts

; copy A bytes from scr_src to scr_dst (24-bit), split at bank boundaries
lcopy:  sta     scr_n
@loop:  lda     scr_n
        beq     @out
        lda     #0
        sec
        sbc     scr_src
        beq     :+
        cmp     scr_n
        bcc     :++
:       lda     scr_n
:       sta     scr_m
        lda     #0
        sec
        sbc     scr_dst
        beq     :+
        cmp     scr_m
        bcs     :+
        sta     scr_m
:       lda     scr_m
        cmp     #CHUNK
        bcc     :+
        lda     #CHUNK
        sta     scr_m
:       lda     scr_src
        sta     kt0
        lda     scr_src+2
        sta     kt1
        lda     scr_dst
        sta     kt2
        lda     scr_dst+2
        sta     kt3
        lda     scr_m
        jsr     kmemcpy
        lda     scr_src
        clc
        adc     scr_m
        sta     scr_src
        bcc     :+
        inc     scr_src+2
:       lda     scr_m
        jsr     adv_dst
        jsr     scr_poll
        bra     @loop
@out:   rts

adv_dst:
        clc
        adc     scr_dst
        sta     scr_dst
        bcc     :+
        inc     scr_dst+2
:       sec
        lda     scr_n
        sbc     scr_m
        sta     scr_n
        rts

; between rows of a long operation: let interrupts in, and other tasks when due
scr_poll:
        lda     scr_coop
        beq     :+
        jsr     irq_poll
        lda     need_resched
        beq     :+
        jsr     k_yield
:       rts

; 4 pixels (a font nibble, bit 3 = left) -> 2 bytes of ink (1) / paper (0)
nib_tab:
        .repeat 16, n
        .word   ((n >> 3) & 1) << 4 | ((n >> 2) & 1) | (((n >> 1) & 1) << 12) | ((n & 1) << 8)
        .endrepeat
nib_inv:                                ; inverse video: ink and paper swapped (follows nib_tab)
        .repeat 16, m
        .word   (((15 - m) >> 3) & 1) << 4 | (((15 - m) >> 2) & 1) | ((((15 - m) >> 1) & 1) << 12) | (((15 - m) & 1) << 8)
        .endrepeat

; the byte after ESC (scr_esc = 1), or a coordinate after ESC Y (2: row, 3: column)
scr_escape:
        cpy     #2
        bcc     @cmd
        beq     @row
        sec                             ; column
        sbc     #32
        bcc     :+
        cmp     #SCR_COLS
        bcc     :++
:       lda     #SCR_COLS - 1
:       sta     scr_col
        stz     scr_esc
        rts
@row:   sec
        sbc     #32
        bcc     :+
        cmp     #SCR_ROWS
        bcc     :++
:       lda     #SCR_ROWS - 1
:       sta     scr_row
        lda     #3
        sta     scr_esc
        rts
@cmd:   stz     scr_esc
        cmp     #'Y'
        bne     :+
        lda     #2
        sta     scr_esc
        rts
:       cmp     #'p'
        bne     :+
        lda     #32
        sta     scr_invoff
        bra     @mine
@mine:  lda     cur                     ; this task changed the modes: reset at its exit
        inc     a
        sta     scr_owner
        rts
:       cmp     #'q'
        bne     :+
        stz     scr_invoff
        rts
:       cmp     #'f'
        bne     :+
        lda     #1
        sta     scr_curoff
        bra     @mine
:       cmp     #'e'
        bne     :+
        stz     scr_curoff
        rts
:       cmp     #'E'
        bne     :+
        jmp     scr_clear
:       cmp     #'K'
        bne     @out
        lda     scr_col                 ; clear to the end of the line (in the current
        pha                             ; video mode: inverse fills with ink)
:       lda     scr_col
        cmp     #SCR_COLS
        bcs     :+
        lda     #' '
        jsr     scr_glyph
        inc     scr_col
        bra     :-
:       pla
        sta     scr_col
@out:   rts

font:
        .res    32 * CELL_H, 0          ; control characters: never drawn
        .include "font.inc"
