; ws.s - the Horizon window system, v0 (stage 1): 640x360 x 8 bpp desktop, windows with
; their own backing bitmaps, a compositor thread, the window manager (raise, drag, close)
; and the window syscalls.
;
; Surfaces. The screen and every window bitmap are "surfaces": a power-of-two stride
; (2^K bytes, at least the width), so a 64 KB bank holds 2^(16-K) whole lines and no line
; ever crosses a bank. A surface has up to 8 banks, one per block of lines. The screen is
; 640x360 with stride 1024 (64 lines per bank, 6 contiguous banks: NV_BASE, NV_STRIDE).
; Surface descriptor (16 bytes): +0 width, +2 height, +4 K, +6 L = 16 - K, +8 banks[8].
;
; Pixel work. Everything goes through gfx_fill (one span of one colour pattern) and
; gfx_copy (one span copied, MVN). Those two are the place for a blitter later.
;
; Windows. A window's bitmap holds the whole window: 1 pixel border, a 14-line title bar
; (close box, title), a separator line, and the content area. Programs draw only in the
; content area, in content coordinates, through win_draw; the kernel clips and records
; the damaged screen rectangle. Windows stay fully on the screen.
;
; Compositor. A kernel thread (a task slot with no user part, priority 1). When there is
; damage it waits one tick (to batch), then repaints each damaged rectangle line by line:
; the desktop pattern, then the windows bottom to top. Between lines it lets interrupts
; in and yields when a reschedule is due. The hardware pointer is drawn by Marga.
;
; Window manager (in the same thread). The left button: on a window that is not on top,
; raises it; on the close box, sends the window a close event; on the title bar, drags
; the window (live, composited on every move); in the content area, sends a button event
; (button changes are sent while the pointer is in the top window's content). Keys go to
; the top window (the keyboard focus).

        .a16
        .i16

NWIN     = 16
NWEV     = 32                           ; events queued per window (index math: 32)
TITLE_H  = 14
CONT_Y   = 16                           ; content area: x 1 .. w-2, y 16 .. h-2
BOT_H    = 12                           ; bottom strip of a resizable window (+1 border)
MENU_H   = 16                           ; the menu bar: windows stay below it
WF_RESIZE = 1                           ; window flags (win_open)
WF_PLAIN  = 2                           ;   no frame and title: content = the window
WF_BACK   = 4                           ;   backdrop: always at the bottom
WF_OVER   = 8                           ;   overlay (kernel): always on top
WF_TERM   = 16                          ;   a terminal
WF_MODAL  = 32                          ;   while open, its owner's other windows send
                                        ;   clicks to it (a dialog)
WF_HOVER  = 64                          ;   motion events without a button (and WE_LEAVE)
TB_MAX   = 15                           ; (0.14) the title bar's buttons: box x = w - TB_*
TB_MIN   = 28
WS_MIN   = 1                            ; w_st (0.14): minimized (out of the z list)
WS_MAX   = 2                            ;   maximized (w_rx .. w_rh: the geometry before)
WE_MENUOPEN = 13                        ; (0.14) one of the backdrop's menus opens: a = it
WE_STATUS = 12                          ; (0.14) a click on the status text (to the backdrop)
MENU_SZ  = 2048                         ; the menu bank: window i's menus at i * MENU_SZ,
MB_DROP  = $8000                        ;   the strings dropped on each window (128 each),
MB_WMENU = $8800                        ;   the Windows menu ("Windows", its items: 1 KB)
WMENU_W  = $0100                        ; (the Windows menu's mb_win)
km_p     = $D0                          ; DP: a 24-bit pointer into the menu bank
SCR_W    = 640
SCR_H    = 360
WS_CTRL  = $09                          ; NV_CTRL: ENABLE, mode 0 (8 bpp), POINTER_EN

; direct page (gfx temporaries; lost across k_block / k_yield)
kg_p    = $90                           ; destination pointer (24 bits)
kg_s    = $94                           ; source pointer
kg_n    = $98                           ; span length
kg_c    = $9A                           ; colour word (pattern for an even address)
kg_x    = $9C
kg_y    = $9E
kg_w    = $A0
kg_h    = $A2
kg_sf   = $A4                           ; surface descriptor (bank 1 offset)
kg_t    = $A6
kg_u    = $A8
kg_v    = $AA
kg_cx0  = $AC                           ; clip rectangle (surface coordinates)
kg_cy0  = $AE
kg_cx1  = $B0
kg_cy1  = $B2
kg_fg   = $B4
kg_bg   = $B6
kg_i    = $B8
kg_ln   = $BA                           ; text: pointer to the string (24 bits)
kg_dx   = $BE
kg_dy   = $C0
kg_e    = $C2                           ; the window a syscall works on
kg_q    = $C4                           ; gfx_line / gfx_text scratch
kg_sx   = $C6                           ; gfx_line steps (surf_line uses kg_t)
kg_sy   = $C8

        .include "palette.inc"

ws_notitle: .byte 0

; ================================================================ surfaces
; kg_p = address of line A (x = 0) of surface kg_sf
surf_line:
        ldx     kg_sf
        sta     kg_t
        lda     a:6,x                   ; L
        tay
        lda     kg_t
:       lsr     a                       ; line block = y >> L
        dey
        bne     :-
        clc
        adc     kg_sf
        tax
        lda     a:8,x                   ; its bank
        and     #$00FF
        sta     kg_p+2
        ldx     kg_sf
        lda     a:6,x                   ; y & (2^L - 1)
        tay
        lda     #1
:       asl     a
        dey
        bne     :-
        dec     a
        and     kg_t
        ldy     a:4,x                   ; << K
:       asl     a
        dey
        bne     :-
        sta     kg_p
        rts

; ================================================================ the pixel core
; (the two routines a blitter replaces)

; fill kg_n bytes at kg_p with the colour pattern kg_c (low byte at even addresses)
gfx_fill:
        lda     kg_n
        bne     :+
        rts
:       phb
        a8
        lda     kg_p+2
        pha
        plb
        a16
        ldx     kg_p
        txa
        lsr     a
        bcc     @even
        a8                              ; odd start: one byte (the pattern's odd byte)
        lda     kg_c+1
        sta     a:0,x
        a16
        inx
        dec     kg_n
@even:  lda     kg_n
        lsr     a
        sta     kg_t                    ; words
        lda     kg_c
@w16:   ldy     kg_t
        cpy     #16
        bcc     @w1
        sta     a:0,x
        sta     a:2,x
        sta     a:4,x
        sta     a:6,x
        sta     a:8,x
        sta     a:10,x
        sta     a:12,x
        sta     a:14,x
        sta     a:16,x
        sta     a:18,x
        sta     a:20,x
        sta     a:22,x
        sta     a:24,x
        sta     a:26,x
        sta     a:28,x
        sta     a:30,x
        pha
        txa
        clc
        adc     #32
        tax
        pla
        ldy     kg_t
        tya
        sec
        sbc     #16
        sta     kg_t
        lda     kg_c
        bra     @w16
@w1:    ldy     kg_t
        beq     @tail
:       sta     a:0,x
        inx
        inx
        dey
        bne     :-
@tail:  lda     kg_n
        lsr     a
        bcc     :+
        a8                              ; odd end: the even byte
        lda     kg_c
        sta     a:0,x
        a16
:       plb
        rts

; copy kg_n bytes from kg_s to kg_p (no bank crossing; MVN)
gfx_copy:
        lda     kg_s
        sta     kt0
        lda     kg_s+2
        sta     kt1
        lda     kg_p
        sta     kt2
        lda     kg_p+2
        sta     kt3
        lda     kg_n
        jmp     kmemcpy

; ================================================================ drawing on a surface
; All take the surface in kg_sf and clip to kg_cx0..kg_cx1, kg_cy0..kg_cy1 (exclusive
; ends, surface coordinates). Coordinates are signed 16-bit.

; fill rectangle kg_x, kg_y, kg_w, kg_h with colour kg_fg
gfx_rect:
        jsr     clip_rect
        bcs     @out
        lda     bl_on
        beq     @sw
        lda     kg_y                    ; the blitter: one FILL (surfaces are linear)
        jsr     surf_line
        jsr     surf_stride
        sta     kg_t
        jsr     bl_wait
        lda     kg_t
        sta     f:BL_DSTR
        lda     kg_p
        clc
        adc     kg_x
        sta     f:BL_DST
        lda     kg_w
        sta     f:BL_W
        lda     kg_h
        sta     f:BL_H
        a8
        lda     kg_p+2
        sta     f:BL_DST+2
        lda     kg_fg
        sta     f:BL_FG
        lda     #BO_FILL
        sta     f:BL_OP
        lda     #0                      ; (a move may have left BACKWARDS set)
        sta     f:BL_FLAGS
        lda     #1
        sta     f:BL_CTRL
        a16
        rts
@sw:    lda     kg_fg
        and     #$00FF
        sta     kg_c
        xba
        ora     kg_c
        sta     kg_c
@line:  lda     kg_y
        jsr     surf_line
        lda     kg_p
        clc
        adc     kg_x
        sta     kg_p
        lda     kg_w
        sta     kg_n
        jsr     gfx_fill
        inc     kg_y
        dec     kg_h
        bne     @line
@out:   rts

; a checker of kg_fg and kg_bg over kg_x, kg_y, kg_w, kg_h (the CPU: the blitter has no
; pattern fill); pixel (x, y) is kg_bg where x + y is odd
gfx_dither:
        jsr     clip_rect
        bcs     @out
        jsr     bl_wait
@line:  lda     kg_y
        jsr     surf_line
        lda     kg_p
        clc
        adc     kg_x
        sta     kg_p
        lda     kg_w
        sta     kg_n
        lda     kg_bg
        xba
        and     #$FF00
        sta     kg_c
        lda     kg_fg
        and     #$00FF
        ora     kg_c
        sta     kg_c
        lda     kg_y
        lsr     a
        bcc     :+
        lda     kg_c
        xba
        sta     kg_c
:       jsr     gfx_fill
        inc     kg_y
        dec     kg_h
        bne     @line
@out:   rts

; a copy inside the surface: the source kg_x, kg_y, kg_w, kg_h and the destination kg_dx,
; kg_dy, both clipped to the clip rectangle (what is cut from one is cut from the other).
; C set: nothing left.
gfx_mclip:
        lda     kg_x
        pha
        lda     kg_y
        pha
        jsr     clip_rect               ; the source
        ply                             ; (the destination moves with what was cut)
        plx
        bcs     @out
        jsr     @mv
        lda     kg_x                    ; then the destination
        sta     kg_sx
        lda     kg_y
        sta     kg_sy
        lda     kg_dx
        sta     kg_x
        pha
        lda     kg_dy
        sta     kg_y
        pha
        jsr     clip_rect
        ply
        plx
        bcs     @out
        lda     kg_x                    ; the source moves with what was cut
        sta     kg_dx
        stx     kg_t
        sec
        sbc     kg_t
        clc
        adc     kg_sx
        sta     kg_x
        lda     kg_y
        sta     kg_dy
        sty     kg_t
        sec
        sbc     kg_t
        clc
        adc     kg_sy
        sta     kg_y
        clc
@out:   rts
@mv:    stx     kg_t                    ; kg_dx += kg_x - old x, kg_dy += kg_y - old y
        lda     kg_x
        sec
        sbc     kg_t
        clc
        adc     kg_dx
        sta     kg_dx
        sty     kg_t
        lda     kg_y
        sec
        sbc     kg_t
        clc
        adc     kg_dy
        sta     kg_dy
        rts

; move kg_w x kg_h pixels of surface kg_sf from kg_x, kg_y to kg_dx, kg_dy (clipped; the
; two may overlap). The blitter: one COPY, BACKWARDS when the destination lies after the
; source. The CPU: line by line, bottom up when moving down, MVP within a line moving
; right; interrupts are served every 8 lines.
gfx_move:
        lda     kg_y
        jsr     surf_line
        lda     kg_p
        clc
        adc     kg_x
        sta     kg_s
        lda     kg_p+2
        sta     kg_s+2
        lda     kg_dy
        jsr     surf_line
        lda     kg_p
        clc
        adc     kg_dx
        sta     kg_p
        lda     bl_on
        beq     @sw
        jsr     surf_stride
        sta     kg_t
        lda     kg_p+2                  ; BACKWARDS when the destination is after the source
        cmp     kg_s+2
        bne     :+
        lda     kg_p
        cmp     kg_s
:       lda     #0
        rol     a                       ; (C: destination >= source)
        sta     kg_u
        jsr     bl_wait
        lda     kg_t
        sta     f:BL_SSTR
        sta     f:BL_DSTR
        lda     kg_s
        sta     f:BL_SRC
        lda     kg_p
        sta     f:BL_DST
        lda     kg_w
        sta     f:BL_W
        lda     kg_h
        sta     f:BL_H
        a8
        lda     kg_s+2
        sta     f:BL_SRC+2
        lda     kg_p+2
        sta     f:BL_DST+2
        lda     #BO_COPY
        sta     f:BL_OP
        lda     kg_u
        sta     f:BL_FLAGS
        lda     #1
        sta     f:BL_CTRL
        a16
        rts
@sw:    lda     kg_y                    ; the CPU (kg_y, kg_dy, kg_h kept for the caller)
        pha
        lda     kg_dy
        pha
        lda     kg_h
        pha
        jsr     @cpu
        pla
        sta     kg_h
        pla
        sta     kg_dy
        pla
        sta     kg_y
        rts
@cpu:   lda     kg_w
        sta     kg_n
        stz     kg_i                    ; line step: +1, or -1 from the last line
        lda     kg_dy
        cmp     kg_y
        beq     @row
        bmi     @line
        lda     kg_h
        dec     a
        clc
        adc     kg_y
        sta     kg_y
        lda     kg_h
        dec     a
        clc
        adc     kg_dy
        sta     kg_dy
        dec     kg_i
        bra     @line
@row:   lda     kg_dx                   ; the same lines, moving right: MVP
        cmp     kg_x
        beq     @out
        bmi     @line
        lda     #1
        sta     kg_i
@line:  lda     kg_y
        jsr     surf_line
        lda     kg_p
        clc
        adc     kg_x
        sta     kg_s
        lda     kg_p+2
        sta     kg_s+2
        lda     kg_dy
        jsr     surf_line
        lda     kg_p
        clc
        adc     kg_dx
        sta     kg_p
        lda     kg_i
        cmp     #1
        bne     :+
        lda     kg_s                    ; MVP: from the last bytes
        clc
        adc     kg_n
        dec     a
        sta     kt0
        lda     kg_s+2
        sta     kt1
        lda     kg_p
        clc
        adc     kg_n
        dec     a
        sta     kt2
        lda     kg_p+2
        sta     kt3
        lda     kg_n
        jsr     kmemmove
        bra     :++
:       jsr     gfx_copy
:       lda     kg_i                    ; the next line
        bmi     :+
        inc     kg_y
        inc     kg_dy
        bra     :++
:       dec     kg_y
        dec     kg_dy
:       lda     kg_h
        and     #7
        cmp     #1
        bne     :+
        jsr     irq_poll
:       dec     kg_h
        bne     @line
@out:   rts

; clip kg_x, kg_y, kg_w, kg_h to the clip rectangle. C set: nothing left.
clip_rect:
        lda     kg_x                    ; x0 = max(x, cx0)
        clc
        adc     kg_w
        sta     kg_t                    ; x1 = x + w
        lda     kg_y
        clc
        adc     kg_h
        sta     kg_u                    ; y1 = y + h
        lda     kg_x
        sec
        sbc     kg_cx0
        bvc     :+
        eor     #$8000
:       bpl     :+
        lda     kg_cx0
        sta     kg_x
:       lda     kg_y
        sec
        sbc     kg_cy0
        bvc     :+
        eor     #$8000
:       bpl     :+
        lda     kg_cy0
        sta     kg_y
:       lda     kg_t                    ; x1 = min(x1, cx1)
        sec
        sbc     kg_cx1
        bvc     :+
        eor     #$8000
:       bmi     :+
        lda     kg_cx1
        sta     kg_t
:       lda     kg_u
        sec
        sbc     kg_cy1
        bvc     :+
        eor     #$8000
:       bmi     :+
        lda     kg_cy1
        sta     kg_u
:       lda     kg_t                    ; w = x1 - x0 > 0 ?
        sec
        sbc     kg_x
        bvc     :+
        eor     #$8000
:       bmi     @none
        beq     @none
        sta     kg_w
        lda     kg_u
        sec
        sbc     kg_y
        bvc     :+
        eor     #$8000
:       bmi     @none
        beq     @none
        sta     kg_h
        clc
        rts
@none:  sec
        rts

; one pixel kg_x, kg_y in colour kg_fg (clipped)
gfx_pixel:
        lda     kg_x
        sec
        sbc     kg_cx0
        bvc     :+
        eor     #$8000
:       bmi     @out
        lda     kg_x
        sec
        sbc     kg_cx1
        bvc     :+
        eor     #$8000
:       bpl     @out
        lda     kg_y
        sec
        sbc     kg_cy0
        bvc     :+
        eor     #$8000
:       bmi     @out
        lda     kg_y
        sec
        sbc     kg_cy1
        bvc     :+
        eor     #$8000
:       bpl     @out
        lda     kg_y
        jsr     surf_line
        ldy     kg_x
        a8
        lda     kg_fg
        sta     [kg_p],y
        a16
@out:   rts

; frame (1 pixel outline) kg_x, kg_y, kg_w, kg_h in colour kg_fg
gfx_frame:
        lda     kg_x
        pha
        lda     kg_y
        pha
        lda     kg_w
        pha
        lda     kg_h
        pha
        lda     #1                      ; top
        sta     kg_h
        jsr     gfx_rect
        lda     5,s                     ; bottom
        sta     kg_y
        lda     1,s
        clc
        adc     kg_y
        dec     a
        sta     kg_y
        lda     7,s
        sta     kg_x
        lda     3,s
        sta     kg_w
        lda     #1
        sta     kg_h
        jsr     gfx_rect
        lda     7,s                     ; left
        sta     kg_x
        lda     5,s
        sta     kg_y
        lda     #1
        sta     kg_w
        lda     1,s
        sta     kg_h
        jsr     gfx_rect
        lda     7,s                     ; right
        clc
        adc     3,s
        dec     a
        sta     kg_x
        lda     5,s
        sta     kg_y
        lda     #1
        sta     kg_w
        lda     1,s
        sta     kg_h
        jsr     gfx_rect
        pla
        pla
        pla
        pla
        rts

; line from kg_x, kg_y to kg_w, kg_h (end point) in colour kg_fg (Bresenham, clipped
; per pixel)
gfx_line:
        jsr     bl_wait                 ; (the CPU draws the pixels)
        ldx     #1                      ; dx = |x1 - x0|, sx
        lda     kg_w
        sec
        sbc     kg_x
        bpl     :+
        eor     #$FFFF
        inc     a
        ldx     #$FFFF
:       sta     kg_dx
        stx     kg_sx                    ; sx
        ldx     #1                      ; dy = -|y1 - y0|, sy
        lda     kg_h
        sec
        sbc     kg_y
        bpl     :+
        eor     #$FFFF
        inc     a
        ldx     #$FFFF
:       eor     #$FFFF
        inc     a
        sta     kg_dy
        stx     kg_sy                    ; sy
        lda     kg_dx
        clc
        adc     kg_dy
        sta     kg_q                    ; err = dx + dy
@loop:  jsr     gfx_pixel
        lda     kg_x
        cmp     kg_w
        bne     :+
        lda     kg_y
        cmp     kg_h
        beq     @out
:       lda     kg_q
        asl     a                       ; e2 = 2 err
        sta     kg_v
        sec                             ; e2 >= dy ?
        sbc     kg_dy
        bvc     :+
        eor     #$8000
:       bmi     :+
        lda     kg_q
        clc
        adc     kg_dy
        sta     kg_q
        lda     kg_x
        clc
        adc     kg_sx
        sta     kg_x
:       lda     kg_v                    ; e2 <= dx ?
        sec
        sbc     kg_dx
        bvc     :+
        eor     #$8000
:       beq     :+
        bpl     @loop
:       lda     kg_q
        clc
        adc     kg_dx
        sta     kg_q
        lda     kg_y
        clc
        adc     kg_sy
        sta     kg_y
        bra     @loop
@out:   rts

; width in pixels of the zero-terminated string at [kg_ln] in font A (0 UI, 1 fixed)
text_width:
        sta     kg_i
        stz     kg_t
        ldy     #0
@c:     lda     [kg_ln],y
        and     #$00FF
        beq     @out
        ldx     kg_i
        bne     @fx
        jsr     uif_index
        lda     uif_w,x
        and     #$00FF
        bra     @add
@fx:    lda     #8
@add:   clc
        adc     kg_t
        sta     kg_t
        iny
        cpy     #200
        bcc     @c
@out:   lda     kg_t
        rts

; X = UI font index of character A (32-126; others are '?')
uif_index:
        cmp     #' '
        bcc     :+
        cmp     #$7F
        bcc     :++
:       lda     #'?'
:       sec
        sbc     #' '
        tax
        rts

; text: the string at [kg_ln] at kg_x, kg_y (top of the line), font kg_i (0 UI: 9 rows of
; ink in an 11-line line; 1 fixed: 8x12), colour kg_fg, background kg_bg ($FF = none)
gfx_text:
        lda     kg_i
        jsr     text_width
        sta     kg_dx                   ; total width
        lda     kg_bg                   ; opaque: the background first
        and     #$00FF
        cmp     #$FF
        beq     @ink
        lda     kg_x
        pha
        lda     kg_y
        pha
        lda     kg_fg
        pha
        lda     kg_bg
        sta     kg_fg
        lda     kg_dx
        sta     kg_w
        lda     #12                     ; (UI font: line height 12)
        sta     kg_h
        jsr     gfx_rect
        pla
        sta     kg_fg
        pla
        sta     kg_y
        pla
        sta     kg_x
@ink:   lda     bl_on
        beq     :+
        jmp     text_blit
:       stz     kg_v                    ; row
        lda     kg_x
        sta     kg_dy                   ; (start x)
@row:   lda     kg_y                    ; this row on the surface, inside the clip?
        clc
        adc     kg_v
        ldx     kg_i
        bne     :+
        inc     a                       ; (UI font: one blank line above the ink)
:       sta     kg_q
        sec
        sbc     kg_cy0
        bvc     :+
        eor     #$8000
:       jmi     @nextr
        lda     kg_q
        sec
        sbc     kg_cy1
        bvc     :+
        eor     #$8000
:       jpl     @nextr
        lda     kg_q
        jsr     surf_line
        lda     kg_dy
        sta     kg_x
        ldy     #0                      ; characters
@ch:    phy
        lda     [kg_ln],y
        and     #$00FF
        beq     @endr
        jsr     uif_index               ; X = character - 32
        lda     kg_i
        bne     @fixed
        lda     uif_w,x
        and     #$00FF
        sta     kg_w                    ; advance
        txa                             ; bitmap row: index * 9 + row
        asl     a
        asl     a
        asl     a
        sta     kg_t
        txa
        clc
        adc     kg_t
        adc     kg_v
        tax
        lda     uif_bm,x
        bra     @bits
@fixed: lda     #8
        sta     kg_w
        txa                             ; font: (index + 32) * 12 + row
        clc
        adc     #32
        asl     a
        asl     a
        sta     kg_t
        asl     a
        clc
        adc     kg_t
        adc     kg_v
        tax
        lda     font,x
@bits:  and     #$00FF
        sta     kg_t
        ldx     kg_x                    ; the pixels of this row of the glyph
@px:    lda     kg_t
        and     #$00FF
        beq     @adv
        asl     kg_t
        and     #$0080
        beq     @skip
        txa                             ; inside the clip?
        sec
        sbc     kg_cx0
        bvc     :+
        eor     #$8000
:       bmi     @skip
        txa
        sec
        sbc     kg_cx1
        bvc     :+
        eor     #$8000
:       bpl     @skip
        txy
        a8
        lda     kg_fg
        sta     [kg_p],y
        a16
@skip:  inx
        bra     @px
@adv:   lda     kg_x
        clc
        adc     kg_w
        sta     kg_x
        ply
        iny
        brl     @ch
@endr:  ply
@nextr: inc     kg_v
        lda     kg_v
        ldx     kg_i
        bne     :+
        cmp     #UIF_H
        jcc     @row
        rts
:       cmp     #12
        jcc     @row
        rts

; gfx_text's ink with the blitter: one EXPAND_KEY per glyph from the font table (1 bpp,
; bit 7 leftmost), clipped with the source offset (rows) and SRC_BIT (columns)
text_blit:
        ldx     #1                      ; UI font: rows 1-9 of the line; fixed: rows 0-11
        lda     #UIF_H
        ldy     kg_i
        beq     :+
        ldx     #0
        lda     #12
:       sta     kg_h
        txa
        clc
        adc     kg_y
        sta     kg_u                    ; gy: the glyphs' top row
        sec                             ; gy0 = max(gy, cy0)
        sbc     kg_cy0
        bvc     :+
        eor     #$8000
:       bmi     :+
        lda     kg_u
        bra     :++
:       lda     kg_cy0
:       sta     kg_v
        lda     kg_u                    ; gy1 = min(gy + rows, cy1)
        clc
        adc     kg_h
        sta     kg_t
        sec
        sbc     kg_cy1
        bvc     :+
        eor     #$8000
:       bmi     :+
        lda     kg_cy1
        sta     kg_t
:       lda     kg_t                    ; rows drawn = gy1 - gy0 > 0 ?
        sec
        sbc     kg_v
        bvc     :+
        eor     #$8000
:       bmi     @none
        bne     :+
@none:  rts
:       sta     kg_h
        lda     kg_v
        sec
        sbc     kg_u
        sta     kg_q                    ; rows cut at the top
        lda     kg_v
        jsr     surf_line               ; kg_p = the first row drawn
        jsr     surf_stride
        sta     kg_t
        jsr     bl_wait
        lda     kg_t
        sta     f:BL_DSTR
        lda     #1
        sta     f:BL_SSTR
        lda     kg_h
        sta     f:BL_H
        a8
        lda     kg_fg
        sta     f:BL_FG
        lda     #BO_EXPK
        sta     f:BL_OP
        lda     #KBANK
        sta     f:BL_SRC+2
        lda     kg_p+2
        sta     f:BL_DST+2
        a16
        lda     kg_x                    ; the whole string inside the clip sideways (the
        sec                             ; usual case): the short loop
        sbc     kg_cx0
        bvc     :+
        eor     #$8000
:       bmi     @slow
        lda     kg_x
        clc
        adc     kg_dx
        sec
        sbc     kg_cx1
        bvc     :+
        eor     #$8000
:       beq     :+
        bpl     @slow
:       jmp     text_fast
@slow:  stz     kg_c                    ; character index
@ch:    ldy     kg_c
        cpy     #200
        bcc     :+
        rts
:       lda     [kg_ln],y
        and     #$00FF
        bne     :+
        rts
:       jsr     uif_index               ; X = character - 32
        lda     kg_i
        bne     @fx
        lda     uif_w,x
        and     #$00FF
        sta     kg_w                    ; advance
        dec     a
        sta     kg_n                    ; ink columns
        txa                             ; uif_bm + index * 9
        asl     a
        asl     a
        asl     a
        sta     kg_t
        txa
        clc
        adc     kg_t
        adc     #.loword(uif_bm)
        bra     @src
@fx:    lda     #8
        sta     kg_w
        sta     kg_n
        txa                             ; font + (index + 32) * 12
        clc
        adc     #32
        asl     a
        asl     a
        sta     kg_t
        asl     a
        clc
        adc     kg_t
        adc     #.loword(font)
@src:   cpx     #0                      ; (a space: nothing to draw)
        beq     @next
        clc
        adc     kg_q
        sta     kg_s
        lda     kg_x                    ; x0 = max(x, cx0)
        sec
        sbc     kg_cx0
        bvc     :+
        eor     #$8000
:       bmi     :+
        lda     kg_x
        bra     :++
:       lda     kg_cx0
:       sta     kg_v
        lda     kg_x                    ; x1 = min(x + ink, cx1)
        clc
        adc     kg_n
        sta     kg_t
        sec
        sbc     kg_cx1
        bvc     :+
        eor     #$8000
:       bmi     :+
        lda     kg_cx1
        sta     kg_t
:       lda     kg_t                    ; width = x1 - x0 > 0 ?
        sec
        sbc     kg_v
        bvc     :+
        eor     #$8000
:       bmi     @next
        beq     @next
        sta     kg_t
        jsr     bl_wait
        lda     kg_t
        sta     f:BL_W
        lda     kg_s
        sta     f:BL_SRC
        lda     kg_p
        clc
        adc     kg_v
        sta     f:BL_DST
        lda     kg_v                    ; first source bit: 7 - (x0 - x), in bits 4-6
        sec
        sbc     kg_x
        eor     #$FFFF
        clc
        adc     #8
        asl     a
        asl     a
        asl     a
        asl     a
        a8
        sta     f:BL_FLAGS
        lda     #1
        sta     f:BL_CTRL
        a16
@next:  lda     kg_x
        clc
        adc     kg_w
        sta     kg_x
        inc     kg_c
        jmp     @ch

; (text_blit) the string fits the clip sideways: per glyph only its source, destination
; (and the UI font's width) and START; every glyph starts at its source bit 7
text_fast:
        a8
        lda     #$70
        sta     f:BL_FLAGS
        a16
        ldy     #0
        lda     kg_i
        beq     @ui
        lda     #8                      ; the fixed font: 8 columns each
        sta     f:BL_W
@fx:    lda     [kg_ln],y
        and     #$00FF
        beq     @out
        cmp     #' '
        beq     @fsp
        bcc     @fq
        cmp     #$7F
        bcc     :+
@fq:    lda     #'?'
:       asl     a                       ; font + character * 12 + rows cut
        asl     a
        sta     kg_t
        asl     a
        adc     kg_t
        adc     #.loword(font)
        adc     kg_q
        tax
        lda     kg_p
        clc
        adc     kg_x
        a8
:       pha
        lda     f:BL_CTRL
        lsr     a
        pla
        bcs     :-
        a16
        sta     f:BL_DST
        txa
        sta     f:BL_SRC
        a8
        lda     #1
        sta     f:BL_CTRL
        a16
@fsp:   lda     kg_x
        clc
        adc     #8
        sta     kg_x
        iny
        cpy     #200
        bcc     @fx
@out:   rts
@ui:    lda     [kg_ln],y               ; the UI font: its advance, ink one column less
        and     #$00FF
        beq     @out
        jsr     uif_index
        lda     uif_w,x
        and     #$00FF
        sta     kg_w
        cpx     #0
        beq     @usp
        dec     a
        sta     kg_n
        txa                             ; uif_bm + index * 9 + rows cut
        asl     a
        asl     a
        asl     a
        sta     kg_t
        txa
        adc     kg_t
        adc     #.loword(uif_bm)
        adc     kg_q
        tax
        a8
:       lda     f:BL_CTRL
        lsr     a
        bcs     :-
        a16
        lda     kg_n
        sta     f:BL_W
        txa
        sta     f:BL_SRC
        lda     kg_p
        clc
        adc     kg_x
        sta     f:BL_DST
        a8
        lda     #1
        sta     f:BL_CTRL
        a16
@usp:   lda     kg_x
        clc
        adc     kg_w
        sta     kg_x
        iny
        cpy     #200
        bcc     @ui
        rts

; ================================================================ the blitter (REV $08)
; Registers stay as written, so a run of similar blits rewrites only what changes. Every
; user waits for BUSY to drop before writing a register (bl_wait); a blit is started and
; left running, so the CPU works meanwhile. Only the compositor may sleep on the BLITTER
; interrupt (bl_mode 1); it keeps its state in BSS across that sleep.
BL_SRC      = $00DA00
BL_SSTR     = $00DA03
BL_DST      = $00DA05
BL_DSTR     = $00DA08
BL_W        = $00DA0A
BL_H        = $00DA0C
BL_FG       = $00DA0E
BL_BG       = $00DA0F
BL_KEY      = $00DA10
BL_OP       = $00DA11
BL_FLAGS    = $00DA12
BL_CTRL     = $00DA13
BO_FILL     = 0
BO_COPY     = 1
BO_KEY      = 2
BO_EXP      = 3
BO_EXPK     = 4

; until the blitter is idle (keeps A, X, Y)
bl_wait:
        pha
        lda     bl_on
        beq     @out
        a8
:       lda     f:BL_CTRL
        lsr     a
        bcs     :-
        a16
@out:   pla
        rts

; before the CPU reads memory the blitter wrote: the 65C816's cache does not see the
; blitter's writes (CACHE_FLUSH sweeps it, about 18 us). (0.30) Also without the window
; system on REV $09+ (fill_runs draws there too: list_wait, vsync)
bl_flush:
        lda     bl_on
        beq     @off
        jsr     bl_wait
@fl:    a8
        sta     f:CACHE_FLUSH
        a16
@out:   rts
@off:   lda     ws_on
        bne     @out
        lda     k_rev
        cmp     #$09
        bcs     @fl
        rts

; bl_on / bl_mode from SYS_REV and ws_config
bl_config:
        jsr     bl_flush                ; (the CPU may draw from now on)
        stz     bl_on
        lda     bl_force
        lsr     a
        bcs     :+
        lda     k_rev
        cmp     #$08
        bcc     :+
        inc     bl_on
:       lda     bl_force
        lsr     a
        and     #1
        sta     bl_mode
        rts

; X = window*2's surface (kg_sf) -> A = its stride (2^K)
surf_stride:
        ldx     kg_sf
        ldy     a:4,x
        lda     #1
:       asl     a
        dey
        bne     :-
        rts

; ================================================================ direct drawing
; A window whose content is fully in view (no window above it overlaps it) and over which
; no repaint is pending draws on the screen itself: one pass instead of two (its bitmap,
; then the compositor's copy of the same pixels to the screen), and a scroll (WD_COPY) is
; one copy on the screen. The window is then "stale": its bitmap is behind the screen
; until it is brought up to date (win_unstale, win_syncr: a copy from the screen back).
; That happens before anything else needs the bitmap: before its content is drawn into
; the bitmap again (it is partly covered, or a repaint over it is pending), before the
; window moves or changes size, and in the compositor before a rectangle over it is
; repainted (only that part while the window is still fully in view). The screen holds
; the window's true content all that time: only the compositor writes over a window's
; place, and it brings a covered stale window up to date before its first repaint there.

; window X's content on the screen -> kg_cx0 .. kg_cy1 (exclusive ends; keeps X)
win_scrclip:
        lda     w_x,x
        clc
        adc     w_cx,x
        sta     kg_cx0
        lda     w_y,x
        clc
        adc     w_cy,x
        sta     kg_cy0
        lda     w_x,x
        clc
        adc     w_w,x
        sec
        sbc     w_cx,x
        sta     kg_cx1
        lda     w_y,x
        clc
        adc     w_h,x
        sec
        sbc     w_cb,x
        sta     kg_cy1
        rts

; C set if no window above window X overlaps its content (set in kg_cx0 .. kg_cy1;
; keeps X)
win_visible:
        stx     vs_w
        jsr     win_scrclip
        ldy     #0
@find:  tya
        lsr     a
        cmp     z_n
        bcs     @no                     ; (not in the z list)
        lda     z_list,y
        iny
        iny
        cmp     vs_w
        bne     @find
@above: tya
        lsr     a
        cmp     z_n
        bcs     @yes
        lda     z_list,y
        iny
        iny
        tax
        lda     w_x,x
        cmp     kg_cx1
        bcs     @above
        clc
        adc     w_w,x
        cmp     kg_cx0
        beq     @above
        bcc     @above
        lda     w_y,x
        cmp     kg_cy1
        bcs     @above
        clc
        adc     w_h,x
        cmp     kg_cy0
        beq     @above
        bcc     @above
@no:    ldx     vs_w
        clc
        rts
@yes:   ldx     vs_w
        sec
        rts

; C set if no damage rectangle (pending, or the one being repainted) meets kg_cx0 ..
; kg_cy1 (keeps Y)
dmg_clear:
        ldx     #0
@d:     cpx     d_n
        bcs     @busy
        lda     d_x0,x
        cmp     kg_cx1
        bcs     @n
        lda     d_x1,x
        cmp     kg_cx0
        beq     @n
        bcc     @n
        lda     d_y0,x
        cmp     kg_cy1
        bcs     @n
        lda     d_y1,x
        cmp     kg_cy0
        beq     @n
        bcc     @n
        clc
        rts
@n:     inx
        inx
        bra     @d
@busy:  lda     ws_busy
        beq     @ok
        lda     cr_x0
        cmp     kg_cx1
        bcs     @ok
        lda     cr_x1
        cmp     kg_cx0
        beq     @ok
        bcc     @ok
        lda     cr_y0
        cmp     kg_cy1
        bcs     @ok
        lda     cr_y1
        cmp     kg_cy0
        beq     @ok
        bcc     @ok
        clc
        rts
@ok:    sec
        rts

; drawing into window kg_e: on the screen (C set, wo_dir = 1: kg_sf = the screen, the
; clip = its content there, wo_x / wo_y = the window's position to add to surface
; coordinates; the window becomes stale) or into its bitmap (C clear, wo_dir = 0: kg_sf
; and the clip as win_surf / win_clip, offset 0; brought up to date first if stale)
win_target:
        ldx     kg_e
        lda     ws_nodir                ; (ws_config bit 2: always the bitmap)
        bne     @bmp
        jsr     win_visible
        bcc     @bmp
        jsr     dmg_clear
        bcc     @bmp
        ldx     kg_e
        lda     #1
        sta     w_stale,x
        sta     wo_dir
        lda     w_x,x
        sta     wo_x
        lda     w_y,x
        sta     wo_y
        lda     #.loword(ws_scr)
        sta     kg_sf
        sec
        rts
@bmp:   ldx     kg_e
        jsr     win_unstale
        ldx     kg_e
        jsr     win_surf
        jsr     win_clip
        stz     wo_x
        stz     wo_y
        stz     wo_dir
        clc
        rts

; the target win_target chose for window kg_e, again (after other drawing)
win_retarget:
        ldx     kg_e
        lda     wo_dir
        beq     :+
        lda     #.loword(ws_scr)
        sta     kg_sf
        jmp     win_scrclip
:       jsr     win_surf
        jmp     win_clip

; window X stale: its whole content copied from the screen into its bitmap (keeps X)
win_unstale:
        lda     w_stale,x
        bne     :+
        rts
:       stz     w_stale,x
        phx
        jsr     win_scrclip
        lda     kg_cx0
        sta     kg_x
        lda     kg_cy0
        sta     kg_y
        lda     kg_cx1
        sec
        sbc     kg_cx0
        sta     kg_w
        lda     kg_cy1
        sec
        sbc     kg_cy0
        sta     kg_h
        jsr     win_syncr
        plx
        rts

; the screen rectangle kg_x, kg_y, kg_w, kg_h (inside window X's content) copied into
; window X's bitmap: one blitter COPY, or line by line
win_syncr:
        stx     sy_w
        lda     kg_w
        beq     :+
        bmi     :+
        lda     kg_h
        beq     :+
        bpl     :++
:       rts
:       lda     kg_y
        sta     kg_dy
        lda     #.loword(ws_scr)        ; the source: the screen
        sta     kg_sf
        lda     kg_y
        jsr     surf_line
        lda     kg_p
        clc
        adc     kg_x
        sta     kg_s
        lda     kg_p+2
        sta     kg_s+2
        ldx     sy_w                    ; the destination: the bitmap
        jsr     win_surf
        ldx     sy_w
        lda     kg_y
        sec
        sbc     w_y,x
        jsr     surf_line
        ldx     sy_w
        lda     kg_x
        sec
        sbc     w_x,x
        sta     kg_dx                   ; (x in the bitmap)
        clc
        adc     kg_p
        sta     kg_p
        lda     bl_on
        beq     @sw
        jsr     surf_stride
        sta     kg_t
        jsr     bl_wait
        lda     #1024
        sta     f:BL_SSTR
        lda     kg_t
        sta     f:BL_DSTR
        lda     kg_s
        sta     f:BL_SRC
        lda     kg_p
        sta     f:BL_DST
        lda     kg_w
        sta     f:BL_W
        lda     kg_h
        sta     f:BL_H
        a8
        lda     kg_s+2
        sta     f:BL_SRC+2
        lda     kg_p+2
        sta     f:BL_DST+2
        lda     #BO_COPY
        sta     f:BL_OP
        lda     #0
        sta     f:BL_FLAGS
        lda     #1
        sta     f:BL_CTRL
        a16
@out:   rts
@sw:    lda     kg_w                    ; the CPU: a line at a time
        sta     kg_n
@l:     lda     #.loword(ws_scr)
        sta     kg_sf
        lda     kg_dy
        jsr     surf_line
        lda     kg_p
        clc
        adc     kg_x
        sta     kg_s
        lda     kg_p+2
        sta     kg_s+2
        ldx     sy_w
        jsr     win_surf
        ldx     sy_w
        lda     kg_dy
        sec
        sbc     w_y,x
        jsr     surf_line
        lda     kg_p
        clc
        adc     kg_dx
        sta     kg_p
        lda     kg_w
        sta     kg_n
        jsr     gfx_copy
        inc     kg_dy
        lda     kg_dy
        and     #3
        bne     :+
        jsr     irq_poll
:       dec     kg_h
        bne     @l
        rts

; (compositor) before the rectangle cr_x0 .. cr_y1 is repainted: every stale window it
; meets is brought up to date there (all of it if the window is no longer fully in view)
cr_unstale:
        ldx     #0
@w:     lda     w_used,x
        beq     @n
        lda     w_stale,x
        beq     @n
        stx     kg_e
        jsr     win_visible
        bcs     :+
        jsr     win_unstale
        bra     @n0
:       lda     kg_cx0                  ; the part of the content inside the rectangle
        cmp     cr_x0
        bcs     :+
        lda     cr_x0
:       sta     kg_x
        lda     kg_cy0
        cmp     cr_y0
        bcs     :+
        lda     cr_y0
:       sta     kg_y
        lda     kg_cx1
        cmp     cr_x1
        bcc     :+
        lda     cr_x1
:       sec
        sbc     kg_x
        beq     @n0
        bmi     @n0
        sta     kg_w
        lda     kg_cy1
        cmp     cr_y1
        bcc     :+
        lda     cr_y1
:       sec
        sbc     kg_y
        beq     @n0
        bmi     @n0
        sta     kg_h
        jsr     win_syncr
@n0:    ldx     kg_e
@n:     inx
        inx
        cpx     #NWIN * 2
        bne     @w
        rts

; ================================================================ the window table
; X = window * 2 -> kg_sf = its surface descriptor
win_surf:
        txa
        asl     a
        asl     a
        asl     a
        clc
        adc     #.loword(w_surf)
        sta     kg_sf
        rts

; clip rectangle = window X's content area (surface coordinates)
win_clip:
        lda     w_cx,x
        sta     kg_cx0
        lda     w_cy,x
        sta     kg_cy0
        lda     w_w,x
        sec
        sbc     w_cx,x
        sta     kg_cx1
        lda     w_h,x
        sec
        sbc     w_cb,x
        sta     kg_cy1
        rts

; clip rectangle = the whole window X
win_clip_all:
        stz     kg_cx0
        stz     kg_cy0
        lda     w_w,x
        sta     kg_cx1
        lda     w_h,x
        sta     kg_cy1
        rts

; draw the frame and title bar of window X (active = on top)
win_decor:
        lda     w_fl,x
        bit     #WF_PLAIN
        beq     :+
        rts
:       phx
        jsr     win_surf
        jsr     win_clip_all
        plx
        phx
        stz     kg_x                    ; border
        stz     kg_y
        lda     w_w,x
        sta     kg_w
        lda     w_h,x
        sta     kg_h
        lda     #C_BLACK
        sta     kg_fg
        jsr     gfx_frame
        plx
        phx
        lda     #C_TITLE_OFF            ; the title bar
        cpx     ws_top
        bne     :+
        lda     #C_TITLE
:       sta     kg_fg
        lda     #1
        sta     kg_x
        sta     kg_y
        lda     w_w,x
        dec     a
        dec     a
        sta     kg_w
        lda     #TITLE_H
        sta     kg_h
        jsr     gfx_rect
        plx
        phx
        lda     #1                      ; the separator
        sta     kg_x
        lda     #TITLE_H + 1
        sta     kg_y
        lda     w_w,x
        dec     a
        dec     a
        sta     kg_w
        lda     #1
        sta     kg_h
        lda     #C_BLACK
        sta     kg_fg
        jsr     gfx_rect
        lda     #4                      ; the close box
        sta     kg_x
        lda     #3
        sta     kg_y
        lda     #10
        sta     kg_w
        sta     kg_h
        lda     #C_BLACK
        sta     kg_fg
        jsr     gfx_frame
        lda     #5
        sta     kg_x
        lda     #4
        sta     kg_y
        lda     #8
        sta     kg_w
        sta     kg_h
        lda     #C_LIGHT
        sta     kg_fg
        jsr     gfx_rect
        plx
        phx
        txa                             ; the title text (white or dark)
        asl     a
        asl     a
        asl     a
        asl     a                       ; window*2*16 = window*32
        clc
        adc     #.loword(w_title)
        sta     kg_ln
        lda     #KBANK
        sta     kg_ln+2
        lda     #20
        sta     kg_x
        lda     #2
        sta     kg_y
        stz     kg_i
        lda     #$FF
        sta     kg_bg
        lda     #C_LIGHT
        cpx     ws_top
        bne     :+
        lda     #C_WHITE
:       sta     kg_fg
        lda     w_fl,x                  ; (0.14: not under the buttons)
        jsr     tb_has
        bcc     :+
        lda     w_w,x
        sec
        sbc     #TB_MIN + 3
        sta     kg_cx1
:       jsr     gfx_text
        lda     1,s
        tax
        jsr     win_clip_all
        jsr     tb_draw
        plx
        lda     w_fl,x
        bit     #WF_RESIZE
        bne     :+
        rts
:       phx                             ; resizable: the bottom strip and the grip
        lda     #1
        sta     kg_x
        sta     kg_h
        lda     w_h,x
        sec
        sbc     #BOT_H + 1
        sta     kg_y
        lda     w_w,x
        dec     a
        dec     a
        sta     kg_w
        lda     #C_BLACK
        sta     kg_fg
        jsr     gfx_rect
        plx
        phx
        lda     #1
        sta     kg_x
        lda     w_h,x
        sec
        sbc     #BOT_H
        sta     kg_y
        lda     w_w,x
        dec     a
        dec     a
        sta     kg_w
        lda     #BOT_H - 1
        sta     kg_h
        lda     #C_LIGHT
        sta     kg_fg
        jsr     gfx_rect
        plx
        phx
        lda     w_w,x                   ; the grip: two nested frames, bottom right
        sec
        sbc     #12
        sta     kg_x
        lda     w_h,x
        sec
        sbc     #11
        sta     kg_y
        lda     #10
        sta     kg_w
        lda     #9
        sta     kg_h
        lda     #C_DARK
        sta     kg_fg
        jsr     gfx_frame
        plx
        phx
        lda     w_w,x
        sec
        sbc     #12
        sta     kg_x
        lda     w_h,x
        sec
        sbc     #11
        sta     kg_y
        lda     #6
        sta     kg_w
        lda     #5
        sta     kg_h
        lda     #C_DARK
        sta     kg_fg
        jsr     gfx_frame
        plx
        rts

; damage window X's whole rectangle on the screen
win_damage:
        lda     w_x,x
        sta     kg_x
        lda     w_y,x
        sta     kg_y
        lda     w_w,x
        sta     kg_w
        lda     w_h,x
        sta     kg_h
        ; fall through
; add the screen rectangle kg_x, kg_y, kg_w, kg_h to the damage (clipped to the screen)
damage:
        stz     kg_cx0
        stz     kg_cy0
        lda     #SCR_W
        sta     kg_cx1
        lda     #SCR_H
        sta     kg_cy1
        jsr     clip_rect
        jcs     @out
        lda     kg_x                    ; as x0, y0, x1, y1
        clc
        adc     kg_w
        sta     kg_t
        lda     kg_y
        clc
        adc     kg_h
        sta     kg_u
        ldx     #0                      ; overlapping (or touching) a rectangle: merge
@m:     cpx     d_n
        bcs     @new
        lda     kg_x
        cmp     d_x1,x
        beq     :+
        bcs     @nm
:       lda     d_x0,x
        cmp     kg_t
        beq     :+
        bcs     @nm
:       lda     kg_y
        cmp     d_y1,x
        beq     :+
        bcs     @nm
:       lda     d_y0,x
        cmp     kg_u
        beq     :+
        bcs     @nm
:
@un:    lda     kg_x                    ; union into it
        cmp     d_x0,x
        bcs     :+
        sta     d_x0,x
:       lda     kg_y
        cmp     d_y0,x
        bcs     :+
        sta     d_y0,x
:       lda     kg_t
        cmp     d_x1,x
        bcc     :+
        sta     d_x1,x
:       lda     kg_u
        cmp     d_y1,x
        jcc     @wake
        sta     d_y1,x
        bra     @wake
@nm:    inx
        inx
        bra     @m
@new:   cpx     #8 * 2                  ; full: into the rectangle whose union with it
        jcc     @add                    ; has the smallest half perimeter
        lda     #$FFFF
        sta     kg_v
        ldx     #0
@b:     lda     kg_t                    ; union width: max(x1) - min(x0)
        cmp     d_x1,x
        bcs     :+
        lda     d_x1,x
:       sta     kg_i
        lda     kg_x
        cmp     d_x0,x
        bcc     :+
        lda     d_x0,x
:       eor     #$FFFF
        sec
        adc     kg_i
        sta     kg_i
        lda     kg_u                    ; + union height
        cmp     d_y1,x
        bcs     :+
        lda     d_y1,x
:       sta     kg_ln
        lda     kg_y
        cmp     d_y0,x
        bcc     :+
        lda     d_y0,x
:       eor     #$FFFF
        sec
        adc     kg_ln
        clc
        adc     kg_i
        cmp     kg_v
        bcs     :+
        sta     kg_v
        stx     kg_ln+2
:       inx
        inx
        cpx     #8 * 2
        bne     @b
        ldx     kg_ln+2
        jmp     @un
@add:       lda     kg_x
        sta     d_x0,x
        lda     kg_y
        sta     d_y0,x
        lda     kg_t
        sta     d_x1,x
        lda     kg_u
        sta     d_y1,x
        inx
        inx
        stx     d_n
@wake:  lda     #W_WS
        ldy     #0
        jmp     k_wake_all
@out:   rts

damage_all:
        stz     d_x0
        stz     d_y0
        lda     #SCR_W
        sta     d_x1
        lda     #SCR_H
        sta     d_y1
        lda     #2
        sta     d_n
        rts

; ================================================================ the compositor
; repaint the screen rectangle cr_x0, cr_y0 .. cr_x1, cr_y1 (state in BSS: may yield)
composite:
        lda     cr_y0
        sta     cr_y
@band:  lda     cr_y
        cmp     cr_y1
        bcc     :+
        rts
:       lda     cr_y1                   ; band end: the next window top or bottom edge
        sta     cr_ye
        ldy     #0
@be:    tya
        lsr     a
        cmp     z_n
        bcs     @bd
        ldx     z_list,y
        lda     w_y,x
        jsr     @cut
        lda     w_y,x
        clc
        adc     w_h,x
        jsr     @cut
        iny
        iny
        bra     @be
@cut:   cmp     cr_y                    ; cr_y < A < cr_ye: the band ends at A
        beq     :+
        bcc     :+
        cmp     cr_ye
        bcs     :+
        sta     cr_ye
:       rts
@bd:    lda     cr_x0
        sta     cr_x
@seg:   lda     cr_x
        cmp     cr_x1
        bcc     :+
        lda     cr_ye
        sta     cr_y
        bra     @band
:       lda     cr_x1                   ; the top-most window at cr_x; higher windows that
        sta     cr_xe                   ; start further right end the segment
        lda     #NONE
        sta     cr_w
        lda     z_n
        asl     a
        tay
@wn:    dey
        dey
        bmi     @draw
        ldx     z_list,y
        lda     cr_y                    ; in the band?
        cmp     w_y,x
        bcc     @wn
        lda     w_y,x
        clc
        adc     w_h,x
        cmp     cr_y
        beq     @wn
        bcc     @wn
        lda     w_x,x
        cmp     cr_x
        beq     @own
        bcc     @lft
        cmp     cr_xe                   ; starts further right
        bcs     @wn
        sta     cr_xe
        bra     @wn
@lft:   lda     w_x,x
        clc
        adc     w_w,x
        cmp     cr_x
        beq     @wn
        bcc     @wn
@own:   stx     cr_w
        lda     w_x,x
        clc
        adc     w_w,x
        cmp     cr_xe
        bcs     @draw
        sta     cr_xe
@draw:  jsr     cr_region
        lda     cr_xe
        sta     cr_x
        bra     @seg

; draw [cr_x, cr_xe) x [cr_y, cr_ye) from window cr_w or the desktop
cr_region:
        lda     bl_on
        beq     :+
        jmp     cr_bregion
:       lda     cr_y                    ; the CPU: line by line
        sta     cr_l
@l:     lda     cr_l
        cmp     cr_ye
        bcc     :+
        rts
:       ldx     cr_w
        cpx     #NONE
        beq     @desk
        jsr     win_surf                ; source: the window's line
        lda     cr_l
        sec
        sbc     w_y,x
        jsr     surf_line
        ldx     cr_w
        lda     cr_x
        sec
        sbc     w_x,x
        clc
        adc     kg_p
        sta     kg_s
        lda     kg_p+2
        sta     kg_s+2
        jsr     cr_dline
        lda     cr_xe
        sec
        sbc     cr_x
        sta     kg_n
        jsr     gfx_copy
        bra     @nx
@desk:  jsr     cr_dline                ; the desktop pattern
        lda     cr_xe
        sec
        sbc     cr_x
        sta     kg_n
        lda     cr_l
        lsr     a
        lda     #C_DESK | (C_DESK2 << 8)
        bcc     :+
        xba
:       sta     kg_c
        jsr     gfx_fill
@nx:    inc     cr_l
        lda     cr_l                    ; every 4 lines: interrupts, other tasks
        and     #3
        bne     @l
        jsr     cr_yield
        bra     @l

; kg_p = the screen at (cr_x, cr_l)
cr_dline:
        lda     #.loword(ws_scr)
        sta     kg_sf
        lda     cr_l
        jsr     surf_line
        lda     kg_p
        clc
        adc     cr_x
        sta     kg_p
        rts

cr_yield:
        jsr     irq_poll
        lda     need_resched
        beq     :+
        jsr     k_yield
:       rts

; the region with the blitter: one COPY from the window, or two COPYs of the dither row
; (each line parity, destination stride 2048, source stride 0)
cr_bregion:
        ldx     cr_w
        cpx     #NONE
        beq     @desk
        jsr     win_surf
        lda     cr_y
        sec
        sbc     w_y,x
        jsr     surf_line               ; the window's first line
        ldx     cr_w
        lda     cr_x
        sec
        sbc     w_x,x
        clc
        adc     kg_p
        sta     kg_s
        lda     kg_p+2
        sta     kg_s+2
        jsr     surf_stride
        sta     kg_v                    ; (surf_line uses kg_t)
        lda     cr_y
        sta     cr_l
        jsr     cr_dline
        lda     cr_ye
        sec
        sbc     cr_y
        sta     kg_n
        jsr     bl_wait
        lda     kg_v
        sta     f:BL_SSTR
        lda     kg_s
        sta     f:BL_SRC
        lda     #1024
        sta     f:BL_DSTR
        a8
        lda     kg_s+2
        sta     f:BL_SRC+2
        a16
        jsr     cr_bgo
        jmp     cr_yield
@desk:  lda     cr_y
        sta     cr_l
        lda     cr_ye
        sec
        sbc     cr_y
        inc     a
        lsr     a
        jsr     cr_bdesk
        lda     cr_y
        inc     a
        sta     cr_l
        lda     cr_ye
        sec
        sbc     cr_y
        lsr     a
        beq     :+
        jsr     cr_bdesk
:       jmp     cr_yield

; A lines of the desktop: cr_l, cr_l + 2, ... from cr_x to cr_xe
cr_bdesk:
        sta     kg_n
        jsr     cr_dline
        jsr     bl_wait
        lda     cr_l
        eor     cr_x
        and     #1
        clc
        adc     #.loword(ws_dtile)
        sta     f:BL_SRC
        lda     #0
        sta     f:BL_SSTR
        lda     #2048
        sta     f:BL_DSTR
        a8
        lda     #KBANK
        sta     f:BL_SRC+2
        a16
        ; fall through

; COPY to kg_p, cr_xe - cr_x wide, kg_n lines; then on (bl_mode 0) or, for a large blit
; in bl_mode 1, sleep until its interrupt
cr_bgo: lda     kg_p
        sta     f:BL_DST
        lda     kg_n
        sta     f:BL_H
        lda     cr_xe
        sec
        sbc     cr_x
        sta     f:BL_W
        sta     kg_t
        a8
        lda     kg_p+2
        sta     f:BL_DST+2
        lda     #BO_COPY
        sta     f:BL_OP
        lda     #0
        sta     f:BL_FLAGS
        a16
        lda     bl_mode
        beq     @go
        lda     kg_n                    ; large: at least 32 lines of 128 pixels
        cmp     #32
        bcc     @go
        lda     kg_t
        cmp     #128
        bcc     @go
        stz     bl_done
        a8
        lda     #3                      ; START, IRQ_EN
        sta     f:BL_CTRL
        a16
:       lda     bl_done
        bne     :+
        lda     #W_BLIT
        ldy     #0
        jsr     k_block
        bra     :-
:       rts
@go:    a8
        lda     #1
        sta     f:BL_CTRL
        a16
        rts

; ================================================================ the thread
ws_thread:
        lda     ws_quit
        beq     :+
        jmp     ws_end
:       jsl     k2_service              ; (0.18) the full screen and sprites after a focus change
        lda     wb_n                    ; a button change?
        beq     :+
        jsr     wm_button
        bra     ws_thread
:       lda     wk_n                    ; a key?
        beq     :+
        jsr     wm_key
        bra     ws_thread
:       lda     ws_wheel                ; wheel steps?
        beq     :+
        jsr     wm_wheel
        bra     ws_thread
:       lda     ws_tflag                ; timers due?
        beq     :+
        jsr     wm_timers
        bra     ws_thread
:       lda     mn_kill                 ; the menu's window closed
        beq     :+
        jsr     mn_close
        bra     ws_thread
:       lda     mn_open                 ; a menu open and the pointer moved?
        bmi     :+
        lda     ms_x
        cmp     mn_lx
        bne     @mt
        lda     ms_y
        cmp     mn_ly
        beq     :+
@mt:    jsr     mn_track
        bra     ws_thread
:       jsl     k2_fsmove               ; (0.18) the full screen: its window gets the pointer
        bcs     @wdmg
        lda     cap_w                   ; a button held in a window, the pointer moved?
        bmi     :+
        lda     ms_x
        cmp     cap_lx
        bne     @mo
        lda     ms_y
        cmp     cap_ly
        beq     :+
@mo:    jsr     wm_motion
        jmp     ws_thread
:       lda     rs_w                    ; resizing and the pointer moved?
        bmi     :+
        lda     ms_x
        cmp     rs_lx
        bne     @rs
        lda     ms_y
        cmp     rs_ly
        beq     :+
@rs:    jsr     wm_rsdrag
        brl     ws_thread
:       lda     drag_w                  ; dragging and the pointer moved?
        bmi     :+
        lda     ms_x
        cmp     drag_lx
        bne     @drag
        lda     ms_y
        cmp     drag_ly
        beq     :+
@drag:  jsr     wm_drag
        jmp     ws_thread
:       lda     ms_x                    ; the pointer moved: hover events
        cmp     hov_lx
        bne     @hov
        lda     ms_y
        cmp     hov_ly
        beq     :+
@hov:   jsr     wm_hover
        jmp     ws_thread
@wdmg:
:       lda     d_n                     ; damage (or terminal output): wait a tick, then
        ora     tm_pend                 ; repaint
        beq     @idle
        lda     #1
        jsr     k_sleep_ticks
        stz     ws_hcnt
@hold:  lda     ws_hn                   ; a program holds the screen (ws_hold): up to 5
        beq     @paint                  ; ticks more (its release wakes us)
        lda     ws_hcnt
        cmp     #5
        bcs     @paint
        inc     ws_hcnt
        lda     #1
        jsr     k_sleep_ticks
        bra     @hold
@paint: jsr     term_flush
        jsr     ws_paint
        jsl     k2_painted              ; (0.18) sprites follow the windows
        jmp     ws_thread
@idle:  lda     #W_WS
        ldy     #0
        jsr     k_block
        jmp     ws_thread

; a key from the ring: F12 ($FF) to the backdrop, other keys to the focused window (a
; terminal takes them into its own queue)
wm_key: lda     wk_h
        asl     a
        tax
        lda     wk_u,x
        sta     kg_t
        lda     wk_m,x
        sta     kg_u
        lda     wk_h
        inc     a
        and     #15
        sta     wk_h
        dec     wk_n
        jsr     hk_pre                  ; (0.15) the held keys: C set: dropped
        bcs     @out
        lda     kg_t                    ; (the menus' code uses kg_t, kg_u)
        sta     hk_kt
        lda     kg_u
        sta     hk_ku
        jsr     wm_kbd                  ; the window manager's own keys (ws13.s)
        bcc     :+
        lda     hk_kt                   ; (0.15: and its release)
        sta     kg_t
        lda     hk_ku
        sta     kg_u
        jmp     hk_eat
:
        lda     kg_t
        cmp     #$FF
        bne     @focus
        lda     z_n
        beq     @focus
        ldx     z_list
        lda     w_fl,x
        bit     #WF_BACK
        bne     @ev
@focus: ldx     ws_top
        bmi     @out
        lda     w_fl,x
        bit     #WF_TERM
        beq     @ev
        jmp     term_key
@ev:    jsr     hk_add                  ; (0.15) the keys it holds
        lda     #WE_KEY
        sta     kg_v
        lda     #0
        jmp     wev_push
@out:   rts

; WE_MOTION to the window holding the press: the pointer in its content, c = buttons.
; Coalesced: a motion event still waiting in its queue just gets the new position.
wm_motion:
        lda     ms_x
        sta     cap_lx
        sta     wm_x
        lda     ms_y
        sta     cap_ly
        sta     wm_y
        ldx     cap_w
        ; fall through
; WE_MOTION (wm_x, wm_y, buttons wm_btn) to window X, coalesced
wm_motx:
        lda     w_used,x
        beq     @out
        lda     w_qn,x                  ; the last queued event a motion?
        beq     @push
        clc
        adc     w_qh,x
        dec     a
        and     #NWEV - 1
        sta     kg_i
        txa                             ; window*2*16 = window*NWEV
        asl     a
        asl     a
        asl     a
        asl     a
        clc
        adc     kg_i
        asl     a
        asl     a
        asl     a
        tay
        lda     w_ev,y
        and     #$00FF
        cmp     #WE_MOTION
        bne     @push
        lda     wm_x
        sec
        sbc     w_x,x
        sec
        sbc     w_cx,x
        sta     w_ev+2,y
        lda     wm_y
        sec
        sbc     w_y,x
        sec
        sbc     w_cy,x
        sta     w_ev+4,y
@out:   rts
@push:  lda     wm_x
        sec
        sbc     w_x,x
        sec
        sbc     w_cx,x
        sta     kg_t
        lda     wm_y
        sec
        sbc     w_y,x
        sec
        sbc     w_cy,x
        sta     kg_u
        lda     #WE_MOTION
        sta     kg_v
        lda     wm_btn
        ora     ws_mods                 ; c = buttons | modifiers << 8
        jmp     wev_push

; the pointer moved: the WF_HOVER window under it gets WE_MOTION (c = buttons; none
; while a menu, a drag or a resize runs, or while another window holds a press: that one
; gets the motion), the one it left gets WE_LEAVE
wm_hover:
        lda     ms_x
        sta     hov_lx
        sta     wm_x
        lda     ms_y
        sta     hov_ly
        sta     wm_y
        stz     kg_q                    ; 1: send the motion
        ldx     #NONE
        lda     mn_open
        bpl     @to
        lda     drag_w
        bpl     @to
        lda     rs_w
        bpl     @to
        lda     cap_w
        bmi     @hit
        cmp     hov_w                   ; a press held: the hover window stays only if it
        bne     @to                     ; holds it (and gets its motion from there)
        tax
        bra     @to
@hit:   jsr     wm_hit
        cpx     #NONE
        beq     @to
        lda     w_fl,x
        and     #WF_HOVER
        bne     :+
        ldx     #NONE
        bra     @to
:       inc     kg_q
@to:    cpx     hov_w
        beq     @same
        phx
        ldx     hov_w
        bmi     :+
        lda     #WE_LEAVE
        jsr     wev_push0
:       plx
        stx     hov_w
@same:  lda     kg_q
        beq     @out
        jmp     wm_motx
@out:   rts

; wheel steps: to the window under the pointer (not the menu bar)
wm_wheel:
        lda     ws_wheel
        stz     ws_wheel
        sta     kg_t
        jsl     k2_fswheel              ; (0.18) the full screen: its window's
        bcs     @out
        lda     ms_x
        sta     wm_x
        lda     ms_y
        sta     wm_y
        jsr     wm_hit
        cpx     #NONE
        beq     @out
        lda     w_fl,x
        bit     #WF_OVER
        bne     @out
        stz     kg_u
        lda     #WE_WHEEL
        sta     kg_v
        lda     #0
        jmp     wev_push
@out:   rts

; WE_TICK for every window whose timer came due
wm_timers:
        stz     ws_tflag
        ldx     #0
@w:     lda     w_net,x                 ; (0.22) WE_NET: a = the stream handles with news
        beq     @t
        stz     w_net,x
        ldy     w_used,x
        beq     @t
        sta     kg_t
        stz     kg_u
        lda     #WE_NET
        sta     kg_v
        phx
        lda     #0
        jsr     wev_push
        plx
@t:     lda     w_tdue,x
        beq     @n
        stz     w_tdue,x
        lda     w_used,x
        beq     @n
        stz     kg_t
        stz     kg_u
        lda     #WE_TICK
        sta     kg_v
        phx
        lda     #0
        jsr     wev_push
        plx
@n:     inx
        inx
        cpx     #NWIN * 2
        bne     @w
        rts

; (the 10 ms tick, interrupt service) count the window timers down
ws_tick:
        lda     ws_on
        beq     @out
        ldx     #0
@w:     lda     w_tper,x
        beq     @n
        dec     w_tcnt,x
        bne     @n
        sta     w_tcnt,x
        lda     #1
        sta     w_tdue,x
        sta     ws_tflag
@n:     inx
        inx
        cpx     #NWIN * 2
        bne     @w
        lda     ws_tflag
        beq     @out
        lda     #W_WS
        ldy     #0
        jmp     k_wake_all
@out:   rts

; ---- $7C win_timer(A = window, X = period in 10 ms ticks, 0 = off): WE_TICK events ----
sys_wtimer:
        ldx     cur
        lda     t_a,x
        jsr     win_arg
        bcc     :+
        jmp     err_inval
:       txy
        ldx     cur
        lda     t_x,x
        tyx
        sta     w_tcnt,x
        sta     w_tper,x
        stz     w_tdue,x
        lda     #0
        jmp     set_ok

; repaint all the damage (its wall time, in microseconds, goes to ws_last for ws_stats)
ws_paint:
        lda     d_n
        bne     :+
        rts
:       inc     ws_busy
        jsr     now_us
        lda     kt5
        sta     ws_t0
        lda     kt6
        sta     ws_t0+2
@next:  lda     d_n
        bne     :+
        jsr     now_us
        lda     kt5
        sec
        sbc     ws_t0
        sta     ws_last
        lda     kt6
        sbc     ws_t0+2
        sta     ws_last+2
        stz     ws_busy
        rts
:       sec                             ; take the last rectangle
        sbc     #2
        sta     d_n
        tax
        lda     d_x0,x
        sta     cr_x0
        lda     d_y0,x
        sta     cr_y0
        lda     d_x1,x
        sta     cr_x1
        lda     d_y1,x
        sta     cr_y1
        jsr     cr_unstale
        jsr     composite
        bra     @next

; kt5:kt6 = UPTIME (microseconds)
now_us: a8
        lda     f:UPTIME                ; latches the upper bytes
        a16
        and     #$00FF
        sta     kt5
        lda     f:UPTIME+1
        xba
        and     #$FF00
        ora     kt5
        sta     kt5
        lda     f:UPTIME+2
        sta     kt6
        rts

; the end: the text console back, the banks freed, the thread ends
ws_end: jsr     bl_wait
        jsl     k2_ws_end               ; (0.18) no sprites, no full screen
        lda     #W_WS                   ; ws_stop waits for this
        ldy     #1
        jsr     k_wake_all
        stz     ws_on
        ldx     #0                      ; windows still open: their banks
:       lda     w_used,x
        beq     :+
        stz     w_used,x
        phx
        jsr     win_free_banks
        plx
:       inx
        inx
        cpx     #NWIN * 2
        bne     :--
        jsr     ws_text_mode
        lda     ws_mbank
        jsr     bank_free
        lda     #6
        sta     kt5
        ldx     ws_sbank
:       txa
        phx
        jsr     bank_free
        plx
        inx
        dec     kt5
        bne     :-
        ldx     cur
        lda     #TS_FREE
        sta     t_state,x
        jmp     k_pick_run

; ================================================================ window manager
; one button change from the queue
wm_button:
        lda     wb_h                    ; take it
        asl     a
        tax
        lda     wb_btn,x
        sta     kg_e
        sta     wm_nbtn                 ; (0.15: kg_e does not survive a menu or a raise)
        lda     wb_x,x
        sta     wm_x
        lda     wb_y,x
        sta     wm_y
        lda     wb_h
        inc     a
        and     #7
        sta     wb_h
        dec     wb_n
        jsl     k2_fsbtn                ; (0.18) the full screen: its window's
        bcc     :+
        rts
:       stz     km_alt                  ; (Alt and a click: no menu at its release)
        lda     mn_open                 ; a menu is open: it takes the buttons
        bmi     :+
        jsr     mn_button
        jmp     @done
:       lda     kg_e
        and     #1
        bne     @down
        lda     wm_btn                  ; the left button released
        and     #1
        jeq     @other
        lda     drag_w                  ; a drag ends
        bmi     :+
        jsr     wm_drag
        lda     #NONE
        sta     drag_w
        jmp     @done
:       lda     rs_w                    ; a resize ends: the program is told
        bmi     :+
        jsr     wm_rsdrag
        ldx     rs_w
        lda     #NONE
        sta     rs_w
        lda     w_used,x
        jeq     @done
        lda     #WE_RESIZE
        sta     kg_v
        lda     w_w,x
        sec
        sbc     w_cx,x
        sec
        sbc     w_cx,x
        sta     kg_t
        lda     w_h,x
        sec
        sbc     w_cy,x
        sec
        sbc     w_cb,x
        sta     kg_u
        lda     #0
        jsr     wev_push
        jmp     @done
:       ldx     cap_w                   ; the release goes where the press went
        bmi     @dn
        lda     #NONE
        sta     cap_w
        lda     w_used,x
        beq     @dn
        jsr     wm_bev
@dn:    jmp     @done
@down:  lda     wm_btn                  ; a new press of the left button?
        and     #1
        jne     @other
        jsr     wm_hit                  ; X = window under the pointer (or NONE)
        cpx     #NONE
        jeq     @done
        lda     w_fl,x
        bit     #WF_OVER                ; the menu bar
        beq     :+
        jsr     mn_press
        jmp     @done
:       bit     #WF_BACK                ; the backdrop: its own events, no raise
        beq     :+
        stx     cap_w
        jsr     cap_here
        jsr     wm_bev
        jmp     @done
:       jsr     wm_modal                ; its owner has a dialog open: that one instead
        cpx     ws_top
        beq     @top
        jsr     wm_raise                ; a click on a lower window raises it
        jmp     @done
@top:   lda     wm_y                    ; the title bar?
        sec
        sbc     w_y,x
        cmp     w_cy,x
        jcs     @grip
        sta     kg_t
        lda     wm_x
        sec
        sbc     w_x,x
        cmp     #3                      ; the close box (3 .. 14)
        bcc     :+
        cmp     #15
        bcs     :+
        lda     kg_t
        cmp     #2
        bcc     :+
        cmp     #14
        bcs     :+
        lda     #WE_CLOSE
        jsr     wev_push0
        jmp     @done
:       lda     wm_x                    ; (0.14) minimize, maximize
        sec
        sbc     w_x,x
        jsr     tb_press
        jcs     @done
        lda     w_fl,x                  ; a double click on the title: maximize / back
        jsr     tb_has
        bcc     @drag
        lda     w_fl,x
        bit     #WF_RESIZE
        beq     @drag
        cpx     tb_w
        bne     @drag
        lda     ticks
        sec
        sbc     tb_t
        cmp     #50
        bcs     @drag
        lda     #NONE
        sta     tb_w
        jsr     win_maxtog
        jmp     @done
@drag:  stx     tb_w
        lda     ticks
        sta     tb_t
        lda     w_st,x                  ; (maximized: it stays)
        and     #WS_MAX
        jne     @done
        stx     drag_w                  ; start a drag
        lda     wm_x
        sec
        sbc     w_x,x
        sta     drag_dx
        lda     wm_y
        sec
        sbc     w_y,x
        sta     drag_dy
        lda     wm_x
        sta     drag_lx
        lda     wm_y
        sta     drag_ly
        jmp     @done
@grip:  lda     w_fl,x                  ; the bottom strip's right end: resize
        bit     #WF_RESIZE
        beq     @cont
        lda     wm_y
        sec
        sbc     w_y,x
        clc
        adc     w_cb,x
        cmp     w_h,x
        bcc     @cont
        lda     wm_x
        sec
        sbc     w_x,x
        clc
        adc     #16
        cmp     w_w,x
        bcc     @cont
        stx     rs_w
        lda     w_st,x                  ; (no longer maximized)
        and     #$FFFF ^ WS_MAX
        sta     w_st,x
        lda     w_x,x                   ; offsets: pointer - bottom right corner
        clc
        adc     w_w,x
        sta     kg_t
        lda     wm_x
        sec
        sbc     kg_t
        sta     rs_ox
        lda     w_y,x
        clc
        adc     w_h,x
        sta     kg_t
        lda     wm_y
        sec
        sbc     kg_t
        sta     rs_oy
        lda     wm_x
        sta     rs_lx
        lda     wm_y
        sta     rs_ly
        jmp     @done
@cont:  stx     cap_w                   ; the content
        jsr     cap_here
        jsr     wm_bev
        jmp     @done
@other: ldx     cap_w                   ; other buttons: to the window holding the press,
        bmi     @ocap                   ; else the top window
        jsr     wm_bev
        lda     wm_nbtn                 ; all up: the capture ends
        bne     @done
        lda     #NONE
        sta     cap_w
        bra     @done
@ocap:  lda     wm_btn                  ; a first press over the top window: it holds the
        bne     @otop                   ; press (motion events, the release) like a left one
        jsr     wm_hit
        cpx     #NONE
        beq     @otop
        lda     w_fl,x                  ; (0.14) over a backdrop: it holds the press
        bit     #WF_BACK
        bne     :+
        cpx     ws_top
        bne     @otop
:       lda     w_fl,x
        bit     #WF_OVER
        bne     @otop
        stx     cap_w
        jsr     cap_here
        jsr     wm_bev
        bra     @done
@otop:  ldx     ws_top
        bmi     @done
        jsr     wm_bev
@done:  lda     wm_nbtn
        sta     wm_btn
        rts

; the capture starts at the press position (no motion event for it); keeps X
cap_here:
        lda     wm_x
        sta     cap_lx
        lda     wm_y
        sta     cap_ly
        rts

; X = window clicked: if its owner has a WF_MODAL window open (another one), X = that
; window (and the error beep)
wm_modal:
        jsr     wm_modal0
        bcc     :+
        phx
        jsr     k_errbeep
        plx
:       rts
; the same without the beep; C set: X is that dialog
wm_modal0:
        lda     w_owner,x
        sta     kg_t
        stx     kg_u
        ldy     #0
@m:     lda     w_used,y
        beq     @n
        lda     w_fl,y
        bit     #WF_MODAL
        beq     @n
        lda     w_owner,y
        cmp     kg_t
        bne     @n
        cpy     kg_u
        beq     @n
        tyx
        sec
        rts
@n:     iny
        iny
        cpy     #NWIN * 2
        bne     @m
        ldx     kg_u
        clc
        rts

; a button event for window X: content coordinates of (wm_x, wm_y), buttons kg_e
wm_bev: lda     wm_x
        sec
        sbc     w_x,x
        sec
        sbc     w_cx,x
        sta     kg_t
        lda     wm_y
        sec
        sbc     w_y,x
        sec
        sbc     w_cy,x
        sta     kg_u
        lda     #WE_BUTTON
        sta     kg_v
        lda     wm_nbtn
        ora     ws_mods                 ; c = buttons | modifiers << 8
        jmp     wev_push

; follow the pointer with the size of window rs_w
wm_rsdrag:
        lda     ms_x
        sta     rs_lx
        lda     ms_y
        sta     rs_ly
        ldx     rs_w
        lda     rs_lx                   ; outer width = pointer - offset - x
        sec
        sbc     rs_ox
        sec
        sbc     w_x,x
        bmi     :+
        cmp     #96
        bcs     :++
:       lda     #96
:       sta     kg_w
        lda     #SCR_W
        sec
        sbc     w_x,x
        cmp     kg_w
        bcs     :+
        sta     kg_w
:       lda     rs_ly
        sec
        sbc     rs_oy
        sec
        sbc     w_y,x
        bmi     :+
        cmp     #CONT_Y + BOT_H + 24
        bcs     :++
:       lda     #CONT_Y + BOT_H + 24
:       sta     kg_h
        lda     #SCR_H
        sec
        sbc     w_y,x
        cmp     kg_h
        bcs     :+
        sta     kg_h
:       lda     kg_w
        cmp     w_w,x
        bne     :+
        lda     kg_h
        cmp     w_h,x
        beq     @out
:       jmp     win_resize
@out:   rts

; X = top-most window containing (wm_x, wm_y), or NONE
wm_hit: ldy     z_n
@z:     dey
        bmi     @none
        tya
        asl     a
        tax
        lda     z_list,x
        tax
        lda     wm_x
        sec
        sbc     w_x,x
        bcc     @z
        cmp     w_w,x
        bcs     @z
        lda     wm_y
        sec
        sbc     w_y,x
        bcc     @z
        cmp     w_h,x
        bcs     @z
        rts
@none:  ldx     #NONE
        rts

; window X's class in the z order: 0 backdrop, 1 normal, 2 overlay
w_class:
        lda     w_fl,x
        bit     #WF_OVER
        beq     :+
        lda     #2
        rts
:       bit     #WF_BACK
        beq     :+
        lda     #0
        rts
:       lda     #1
        rts

; take window kg_e out of the z list
z_remove:
        ldy     #0
        ldx     #0
:       cpx     z_n
        bcs     :++
        txa
        asl     a
        phx
        tax
        lda     z_list,x
        plx
        cmp     kg_e
        beq     :+
        phx
        pha
        tya
        asl     a
        tax
        pla
        sta     z_list,x
        plx
        iny
:       inx
        bra     :--
:       sty     z_n
        rts

; put window kg_e into the z list: on top of its class
z_insert:
        ldx     kg_e
        jsr     w_class
        sta     kg_t
        ldy     #0                      ; p = the first entry of a higher class
@p:     cpy     z_n
        bcs     @ins
        tya
        asl     a
        tax
        lda     z_list,x
        tax
        jsr     w_class
        cmp     kg_t
        beq     :+
        bcs     @ins
:       iny
        bra     @p
@ins:   sty     kg_u
        lda     z_n                     ; move p .. n-1 up by one
        asl     a
        tax
@mv:    txa
        lsr     a
        cmp     kg_u
        beq     :+
        lda     z_list-2,x
        sta     z_list,x
        dex
        dex
        bra     @mv
:       lda     kg_e
        sta     z_list,x
        inc     z_n
        rts

; raise window X to the top of its class (redraws the two title bars, damages both)
wm_raise:
        stx     kg_e
        jsr     z_remove
        jsr     z_insert
        ; fall through
; ws_top = the top-most normal window (else the top-most backdrop, else NONE); redraw
; the old and new title bars and the menu bar
wm_retop:
        ldx     ws_top
        phx
        lda     #NONE
        sta     kg_t
        ldy     z_n
@f:     dey
        bmi     @nf
        tya
        asl     a
        tax
        lda     z_list,x
        tax
        lda     w_fl,x
        bit     #WF_OVER
        bne     @f
        bit     #WF_BACK
        beq     @got
        lda     kg_t                    ; (the top-most backdrop)
        cmp     #NONE
        bne     @f
        stx     kg_t
        bra     @f
@nf:    ldx     kg_t
@got:   stx     ws_top
        jsr     ws_focus                ; (0.15) WE_UNFOCUS, WE_FOCUS
        plx                             ; the old top: inactive title
        cpx     ws_top
        beq     @same
        cpx     #NONE
        beq     :+
        lda     w_used,x
        beq     :+
        jsr     win_decor
        jsr     win_damage
:       ldx     ws_top
        cpx     #NONE
        beq     :+
        jsr     win_decor
        jsr     win_damage
:       jmp     bar_draw                ; the focused program's menus
@same:  rts

; move the dragged window to follow the pointer
wm_drag:
        lda     ms_x
        sta     drag_lx
        lda     ms_y
        sta     drag_ly
        ldx     drag_w
        lda     drag_lx                 ; new x = pointer - offset, kept on the screen
        sec
        sbc     drag_dx
        bpl     :+
        lda     #0
:       sta     kg_t
        lda     #SCR_W
        sec
        sbc     w_w,x
        cmp     kg_t
        bcs     :+
        sta     kg_t
:       lda     drag_ly
        sec
        sbc     drag_dy
        bpl     :+
        lda     #0
:       sta     kg_u
        lda     #SCR_H
        sec
        sbc     w_h,x
        cmp     kg_u
        bcs     :+
        sta     kg_u
:       lda     kg_t
        cmp     w_x,x
        bne     :+
        lda     kg_u
        cmp     w_y,x
        beq     @out
:       lda     kg_t                    ; (win_damage uses kg_t, kg_u)
        sta     drag_nx
        lda     kg_u
        sta     drag_ny
        jsr     win_unstale
        jsr     win_damage              ; old place
        ldx     drag_w
        lda     drag_nx
        sta     w_x,x
        lda     drag_ny
        sta     w_y,x
        jsr     win_damage              ; new place
@out:   rts

; ================================================================ events
; event for window X: type A, a = b = c = 0
wev_push0:
        sta     kg_v
        stz     kg_t
        stz     kg_u
        lda     #0
        ; fall through
; event for window X: type kg_v, a = kg_t, b = kg_u, c = A. Wakes the owner.
wev_push:
        pha
        lda     w_qn,x
        cmp     #NWEV
        bcs     @drop                   ; full: dropped
        cmp     #NWEV * 3 / 4           ; nearly full: key releases are dropped first
        bcc     :+
        lda     kg_v
        cmp     #WE_KEY
        bne     :+
        lda     kg_u                    ; (b = modifiers | down << 8)
        cmp     #$0100
        bcs     :+
@drop:  pla
        rts
:       lda     w_qn,x
       clc
        adc     w_qh,x
        and     #NWEV - 1
        sta     kg_i                    ; slot: (window * NWEV + n) * 8
        txa                             ; window*2*16 = window*NWEV
        asl     a
        asl     a
        asl     a
        asl     a
        clc
        adc     kg_i
        asl     a
        asl     a
        asl     a
        tay
        lda     kg_v
        sta     w_ev,y
        lda     kg_t
        sta     w_ev+2,y
        lda     kg_u
        sta     w_ev+4,y
        pla
        sta     w_ev+6,y
        inc     w_qn,x
        lda     #W_WEVENT               ; its owner may wait
        ldy     #0
        jmp     k_wake_all

; ================================================================ input hooks
; (interrupt service: mouse.s and input.s call these while the window system runs)

; a mouse event: queue a button change for the window manager, wake it
ws_mouse:
        lda     ms_dw                   ; wheel steps add up
        and     #$00FF
        beq     :+
        jsr     sext8
        clc
        adc     ws_wheel
        sta     ws_wheel
:       lda     ms_btn
        cmp     wb_last
        beq     :+
        sta     wb_last
        lda     wb_n
        cmp     #8
        bcs     :+
        clc
        adc     wb_h
        and     #7
        asl     a
        tax
        lda     ms_btn
        sta     wb_btn,x
        lda     ms_x
        sta     wb_x,x
        lda     ms_y
        sta     wb_y,x
        inc     wb_n
:       lda     #W_WS
        ldy     #0
        jmp     k_wake_all

; a key event (A = usage, X = modifiers | down << 8): to the top window. A modifier key
; ($E0-$E7) keeps the modifiers for the button and motion events (ws_mods)
ws_key: cmp     #$E0
        bcc     :+
        cmp     #$E8
        bcs     :+
        pha
        txa
        xba
        and     #$FF00
        sta     ws_mods
        pla
:       pha
        lda     wk_n
        cmp     #16
        bcc     :+
        pla                             ; full: dropped
        rts
:       clc
        adc     wk_h
        and     #15
        asl     a
        tay
        pla
        sta     wk_u,y
        txa
        sta     wk_m,y
        inc     wk_n
        lda     #W_WS
        ldy     #0
        jmp     k_wake_all

; ================================================================ modes
ws_text_mode:
        jsr     ptr_arrow
        jsr     scr_palette             ; the console's palette, mode 1, its framebuffer
        lda     #FB_STRIDE
        sta     f:NV_STRIDE
        sta     vs_stride
        jsr     scr_set_base
        lda     scr_ctrl
        and     #$08
        ora     #SCR_CTRL
        sta     scr_ctrl
        jsr     nv_ctrl
        a8
        lda     #4                      ; pointer colours for 4 bpp
        sta     f:PTR_C1
        sta     vs_pc
        lda     #5
        sta     f:PTR_C1+1
        sta     vs_pc+1
        a16
        rts

ws_desk_mode:
        lda     #0                      ; the system palette
        ldx     #.loword(ws_palette)
        ldy     #256
        jsr     pal_load
        jsl     k2_pal_apply            ; (0.18) and the front program's own entries
        lda     #1024
        sta     f:NV_STRIDE
        sta     vs_stride
        lda     ws_sbank                ; NV_BASE = first screen bank
        xba
        sta     f:NV_BASE+1
        sta     vs_base+1
        lda     #WS_CTRL
        sta     scr_ctrl
        jsr     nv_ctrl
        a8
        lda     #C_BLACK                ; pointer: black outline, white fill
        sta     f:PTR_C1
        sta     vs_pc
        lda     #C_WHITE
        sta     f:PTR_C1+1
        sta     vs_pc+1
        lda     #C_YELLOW
        sta     f:PTR_C1+2
        sta     vs_pc+2
        a16
        rts

; ================================================================ syscalls
; ---- $70 ws_start: the desktop on the screen, the window system running ----
sys_wsstart:
        lda     ws_on                   ; (already running: A = 0)
        beq     :+
        lda     #0
        jmp     set_ok
:       lda     #6                      ; 6 contiguous banks for the screen
        jsr     bank_run
        bcc     :+
@nomem: lda     #ENOMEM
        jmp     set_err
:       sta     ws_sbank
        lda     #1                      ; (0.14) the menu bank
        jsr     bank_run
        bcc     :++
        lda     #6
        sta     kt5
        ldx     ws_sbank
:       txa
        phx
        jsr     bank_free
        plx
        inx
        dec     kt5
        bne     :-
        bra     @nomem
:       sta     ws_mbank
        lda     #MB_WMENU               ; the Windows menu's title (its items come when
        sta     km_p                    ; it opens)
        lda     ws_mbank
        sta     km_p+2
        ldy     #0
        a8
:       lda     wl_title,y
        sta     [km_p],y
        iny
        cpy     #wl_title_end - wl_title
        bne     :-
        a16
        ldx     #0                      ; the desktop's dither row
        lda     #C_DESK | (C_DESK2 << 8)
:       sta     ws_dtile,x
        inx
        inx
        cpx     #642
        bne     :-
        jsr     bl_config
        lda     #SCR_W                  ; the screen surface
        sta     ws_scr
        lda     #SCR_H
        sta     ws_scr+2
        lda     #10
        sta     ws_scr+4
        lda     #6
        sta     ws_scr+6
        ldx     #0
        lda     ws_sbank
:       sta     ws_scr+8,x
        inc     a
        inx
        cpx     #6
        bne     :-
        ldx     #0                      ; no windows
        lda     #0
:       sta     w_used,x
        inx
        inx
        cpx     #NWIN * 2
        bne     :-
        stz     z_n
        stz     d_n
        stz     wb_n
        stz     wb_h
        stz     ws_quit
        lda     ms_btn
        sta     wb_last
        sta     wm_btn
        lda     #NONE
        sta     ws_top
        sta     drag_w
        sta     rs_w
        sta     cap_w
        sta     hov_w
        sta     hov_lx
        sta     mb_w
        sta     dd_w
        sta     mn_open
        sta     pop_task                ; (0.15)
        sta     fo_w
        ldx     #HK_N * 2 - 2
:       sta     hk_w,x
        dex
        dex
        bpl     :-
        stz     mn_kill
        stz     km_alt
        stz     ws_mods
        stz     wk_n
        stz     wk_h
        stz     ws_wheel
        stz     ws_tflag
        stz     ws_stat
        ldx     cur
        stx     ws_owner
        lda     #1
        sta     ws_on
        jsr     bar_make
        jsr     damage_all
        jsr     ws_desk_mode
        lda     #.loword(kpath)         ; the thread: a kernel task "WS", priority 1
        tax                             ; (its name comes from kpath)
        lda     #'W' | ('S' << 8)
        sta     kpath
        lda     #0
        sta     kpath+2
        lda     #1
        sta     kt0
        lda     #NONE
        sta     kt1
        jsr     task_create
        bcc     :+
        jmp     set_err
:       stx     ws_thr
        txa
        xba
        clc
        adc     #KSTK_BASE + KSTK_SIZE - 3
        sta     t_ksp,x
        phx
        tax
        lda     #.loword(ws_thread - 1)
        sta     f:$000001,x
        plx
        lda     #1
        sta     t_wbank,x               ; (no user part; B0WIN harmless)
        lda     #1                      ; A = 1: started by this call
        jmp     set_ok

; ---- $71 ws_stop: the starter ends the window system (its windows close) ----
sys_wsstop:
        lda     ws_on
        beq     :+
        lda     ws_owner                ; the starter only
        cmp     cur
        beq     :++
:       jmp     err_inval
:       lda     #1
        sta     ws_quit
        lda     #W_WS
        ldy     #0
        jsr     k_wake_all
:       lda     ws_on                   ; wait for the thread to finish
        beq     :+
        lda     #W_WS
        ldy     #1
        jsr     k_block
        bra     :-
:       lda     #0
        jmp     set_ok

; X = window * 2 of the caller's window A, C set if it is not one
win_arg:
        cmp     #NWIN
        bcs     @bad
        asl     a
        tax
        lda     w_used,x
        beq     @bad
        lda     w_owner,x
        cmp     cur
        bne     @bad
        clc
        rts
@bad:   sec
        rts

; ---- $72 win_open(X, Y = {i16 x, i16 y, u16 width, u16 height, u24 title}) -> A = window
; width and height are the content area's ----
sys_wopen:
        lda     ws_on
        bne     :+
        jmp     err_inval
:       lda     #12                     ; {x, y, width, height, u24 title, u8 flags}
        jsr     get_block
        bcc     :+
        jmp     err_fault
:       jsr     win_find
        bcc     :+
        lda     #EAGAIN
        jmp     set_err
:       stx     kg_e
        lda     kblk+11                 ; flags (a program cannot make an overlay)
        and     #WF_RESIZE | WF_PLAIN | WF_BACK | WF_TERM | WF_MODAL | WF_HOVER
        sta     w_fl,x
        lda     kblk
        sta     kg_x
        lda     kblk+2
        sta     kg_y
        lda     kblk+4
        sta     kg_w
        lda     kblk+6
        sta     kg_h
        jsr     win_geom
        jsr     win_make
        bcc     :+
        lda     #ENOMEM
        jmp     set_err
:       ldx     kg_e                    ; a terminal: its state
        lda     w_fl,x
        bit     #WF_TERM
        beq     @title
        jsr     term_open
        bcc     @title
        ldx     kg_e
        stz     tm_bank,x
        jsr     win_close
        lda     #ENOMEM
        jmp     set_err
@title: lda     kblk+8                  ; the title (31 characters at most)
        sta     kt0
        lda     kblk+10
        and     #$00FF
        sta     kt1
        lda     #1
        sta     kt2
        stz     kt3
        jsr     uaccess
        bcc     :+
        lda     #.loword(ws_notitle)    ; (no readable title)
        sta     kphys
        lda     #KBANK
        sta     kphys+2
:       lda     kphys
        sta     kp1
        lda     kphys+2
        sta     kp1+2
        lda     kg_e
        asl     a
        asl     a
        asl     a
        asl     a
        clc
        adc     #.loword(w_title)
        tax
        ldy     #0
        a8
:       lda     [kp1],y
        beq     @tz
        sta     a:0,x
        inx
        iny
        cpy     #31
        bne     :-
@tz:    lda     #0
        sta     a:0,x
        a16
        ldx     kg_e                    ; the frame again, with the title
        jsr     win_decor
        ldx     kg_e
        jsr     win_damage
        lda     kg_e
        lsr     a
        jmp     set_ok

; X = a free window slot (C set: none)
win_find:
        ldx     #0
:       lda     w_used,x
        beq     :+
        inx
        inx
        cpx     #NWIN * 2
        bne     :-
        sec
        rts
:       clc
        rts

; window X (flags set): margins from its flags, outer size from the content size kg_w x
; kg_h, position kg_x, kg_y kept on the screen (below the menu bar unless an overlay)
win_geom:
        lda     #1                      ; margins
        sta     w_cx,x
        lda     #CONT_Y
        sta     w_cy,x
        lda     #1
        sta     w_cb,x
        lda     w_fl,x
        bit     #WF_RESIZE
        beq     :+
        lda     #BOT_H + 1
        sta     w_cb,x
        lda     w_fl,x
:       bit     #WF_PLAIN
        beq     :+
        stz     w_cx,x
        stz     w_cy,x
        stz     w_cb,x
:       lda     #MENU_H                 ; the top limit
        sta     kg_t
        lda     w_fl,x
        bit     #WF_OVER
        beq     :+
        stz     kg_t
:       lda     kg_w                    ; outer width = content + 2 cx, 8 .. 640
        clc
        adc     w_cx,x
        adc     w_cx,x
        cmp     #SCR_W + 1
        bcc     :+
        lda     #SCR_W
:       cmp     #8
        bcs     :+
        lda     #8
:       sta     w_w,x
        lda     #SCR_H                  ; outer height = content + cy + cb, 8 .. 360 - top
        sec
        sbc     kg_t
        sta     kg_u
        lda     kg_h
        clc
        adc     w_cy,x
        adc     w_cb,x
        cmp     kg_u
        bcc     :+
        lda     kg_u
:       cmp     #8
        bcs     :+
        lda     #8
:       sta     w_h,x
        lda     kg_x                    ; x: 0 .. 640 - w
        bpl     :+
        lda     #0
:       sta     kg_u
        lda     #SCR_W
        sec
        sbc     w_w,x
        cmp     kg_u
        bcs     :+
        sta     kg_u
:       lda     kg_u
        sta     w_x,x
        lda     kg_y                    ; y: top .. 360 - h
        bmi     :+
        cmp     kg_t
        bcs     :++
:       lda     kg_t
:       sta     kg_u
        lda     #SCR_H
        sec
        sbc     w_h,x
        cmp     kg_u
        bcs     :+
        sta     kg_u
:       lda     kg_u
        sta     w_y,x
        rts

; window kg_e (geometry set): its surface, owner = cur, the body colour, the frame, on
; top of its class. C set: no memory.
win_make:
        ldx     kg_e
        lda     w_w,x
        sta     kg_w
        lda     w_h,x
        sta     kg_h
        jsr     surf_alloc
        bcc     :+
        rts
:       ldx     kg_e
        lda     cur
        sta     w_owner,x
        stz     w_qn,x
        stz     w_qh,x
        stz     w_tper,x
        stz     w_tdue,x
        stz     w_stale,x
        stz     w_st,x
        jsr     menu_ptr                ; no menus
        a8
        lda     #0
        sta     [kg_ln]
        a16
        ldx     kg_e
        txa                             ; no title yet (w_title + window * 32)
        asl     a
        asl     a
        asl     a
        asl     a
        tay
        lda     #0
        sta     w_title,y
        lda     #1
        sta     w_used,x
        jsr     win_surf                ; the whole window: the body colour
        jsr     win_clip_all
        ldx     kg_e
        stz     kg_x
        stz     kg_y
        lda     w_w,x
        sta     kg_w
        lda     w_h,x
        sta     kg_h
        lda     #C_BODY
        sta     kg_fg
        jsr     gfx_rect
        jsr     z_insert
        ldx     kg_e
        jsr     win_decor
        ldx     kg_e
        jsr     wm_retop
        ldx     kg_e
        jsr     win_damage
        clc
        rts

; window X's surface for an outer size kg_w x kg_h: stride 2^K >= width, contiguous
; banks (so the surface is linear). The descriptor's width and height are its capacity.
; C set: no memory.
surf_alloc:
        stx     sa_x
        jsr     win_surf
        lda     kg_w                    ; K = bits of (w - 1), at least 6
        dec     a
        ldy     #0
:       iny
        lsr     a
        bne     :-
        cpy     #6
        bcs     :+
        ldy     #6
:       tya
        ldy     kg_sf
        sta     a:4,y                   ; K
        eor     #$FFFF
        sec
        adc     #16
        sta     a:6,y                   ; L = 16 - K
        tay                             ; banks = (h - 1) >> L + 1
        lda     kg_h
        dec     a
:       lsr     a
        dey
        bne     :-
        inc     a
        sta     kg_n
        jsr     bank_run
        bcc     :+
        rts
:       ldy     kg_sf
        ldx     #0
        a8
:       sta     a:8,y
        inc     a
        iny
        inx
        cpx     kg_n
        bne     :-
        a16
        ldx     sa_x
        lda     kg_n
        sta     w_nb,x
        jsr     win_surf
        ldy     kg_sf                   ; capacity: 2^K x banks << L
        ldx     a:4,y
        lda     #1
:       asl     a
        dex
        bne     :-
        sta     a:0,y
        ldx     a:6,y
        lda     kg_n
:       asl     a
        dex
        bne     :-
        sta     a:2,y
        ldx     sa_x
        clc
        rts

; window X gets the outer size kg_w x kg_h (live resize). A new surface when the old one
; is too small (the old content is copied); the new area gets the body colour.
win_resize:
        stx     sa_x
        lda     kg_w                    ; (the bitmap up to date first)
        pha
        lda     kg_h
        pha
        jsr     win_unstale
        pla
        sta     kg_h
        pla
        sta     kg_w
        jsr     bl_wait
        lda     kg_w                    ; (win_damage uses kg_w, kg_h)
        pha
        lda     kg_h
        pha
        jsr     win_damage              ; the old place
        pla
        sta     kg_h
        pla
        sta     kg_w
        ldx     sa_x
        lda     w_w,x
        sta     sa_ow
        lda     w_h,x
        sta     sa_oh
        jsr     win_surf
        ldy     kg_sf
        lda     kg_w
        cmp     a:0,y
        beq     :+
        bcs     @new
:       lda     kg_h
        cmp     a:2,y
        jeq     @fits
        jcc     @fits
@new:   ldx     #0                      ; keep the old descriptor and bank count
        ldy     kg_sf
:       lda     a:0,y
        sta     sa_os,x
        iny
        iny
        inx
        inx
        cpx     #16
        bne     :-
        ldx     sa_x
        lda     w_nb,x
        pha
        jsr     surf_alloc
        bcc     :+
        pla                             ; no memory: the old surface and size stay
        ldx     sa_x
        jsr     win_surf
        ldy     kg_sf
        ldx     #0
@rs:    lda     sa_os,x
        sta     a:0,y
        iny
        iny
        inx
        inx
        cpx     #16
        bne     @rs
        ldx     sa_x
        jmp     win_damage
:       ldx     sa_x                    ; copy min(w) x min(h) from the old surface
        jsr     win_surf
        lda     kg_w
        pha
        lda     kg_h
        pha
        lda     sa_ow
        cmp     kg_w
        bcs     :+
        sta     kg_w
:       lda     sa_oh
        cmp     kg_h
        bcs     :+
        sta     kg_h
:       jsr     bl_flush                ; (the CPU reads what the blitter drew)
        stz     kg_i                    ; line by line (old surface: sa_os)
@cp:    lda     kg_i
        cmp     kg_h
        bcs     @cpd
        lda     #.loword(sa_os)
        sta     kg_sf
        lda     kg_i
        jsr     surf_line
        lda     kg_p
        sta     kg_s
        lda     kg_p+2
        sta     kg_s+2
        ldx     sa_x
        jsr     win_surf
        lda     kg_i
        jsr     surf_line
        jsr     bl_wait
        lda     kg_w
        sta     kg_n
        jsr     gfx_copy
        inc     kg_i
        bra     @cp
@cpd:   pla
        sta     kg_h
        pla
        sta     kg_w
        pla                             ; free the old banks
        sta     kg_n
        ldx     #0
:       cpx     kg_n
        bcs     @fits
        lda     sa_os+8,x
        and     #$00FF
        phx
        jsr     bank_free
        plx
        inx
        bra     :-
@fits:  ldx     sa_x
        lda     kg_w
        sta     w_w,x
        lda     kg_h
        sta     w_h,x
        jsr     win_surf                ; the new area: the body colour (the old frame
        jsr     win_clip_all            ; lines too)
        ldx     sa_x
        lda     sa_ow
        sec
        sbc     #BOT_H + 2
        bpl     :+
        lda     #0
:       sta     kg_x
        stz     kg_y
        lda     w_w,x
        sta     kg_w
        lda     w_h,x
        sta     kg_h
        lda     #C_BODY
        sta     kg_fg
        jsr     gfx_rect                ; right part (from the old right edge)
        ldx     sa_x
        jsr     win_clip_all
        ldx     sa_x
        stz     kg_x
        lda     sa_oh
        sec
        sbc     #BOT_H + 2
        bpl     :+
        lda     #0
:       sta     kg_y
        lda     w_w,x
        sta     kg_w
        lda     w_h,x
        sta     kg_h
        lda     #C_BODY
        sta     kg_fg
        jsr     gfx_rect                ; bottom part (from the old bottom strip)
        ldx     sa_x
        jsr     win_decor
        ldx     sa_x
        jmp     win_damage

; free window X's banks
win_free_banks:
        jsr     bl_wait                 ; (a blit may still be writing there)
        jsr     win_surf
        stz     kg_i
:       lda     kg_i
        cmp     w_nb,x
        bcs     :+
        phx
        lda     kg_sf
        clc
        adc     kg_i
        tay
        lda     a:8,y
        and     #$00FF
        jsr     bank_free
        plx
        jsr     win_surf
        inc     kg_i
        bra     :-
:       rts

; close window X (owner checked by the caller)
win_close:
        jsl     k2_wclose               ; (0.18) its sprites, its full screen
        stx     kg_e
        jsr     term_close              ; (a terminal: its bank, its tasks)
        ldx     kg_e
        stz     w_used,x
        jsr     win_damage
        ldx     kg_e
        jsr     win_free_banks
        jsr     z_remove                ; out of the z list
        ldx     kg_e
        stz     w_tper,x
        lda     rs_w
        cmp     kg_e
        bne     :+
        lda     #NONE
        sta     rs_w
:       lda     cap_w
        cmp     kg_e
        bne     :+
        lda     #NONE
        sta     cap_w
:       lda     hov_w
        cmp     kg_e
        bne     :+
        lda     #NONE
        sta     hov_w
:       jsr     mn_closed               ; (its menus may be open)
        lda     drag_w
        cmp     kg_e
        bne     :+
        lda     #NONE
        sta     drag_w
:       lda     #NONE                   ; (the old top is gone: no redraw for it)
        sta     ws_top
        jmp     wm_retop

; ---- $73 win_close(A = window) ----
sys_wclose:
        ldx     cur
        lda     t_a,x
        jsr     win_arg
        bcc     :+
        jmp     err_inval
:       jsr     win_close
        lda     #0
        jmp     set_ok

; close every window of the current task (at exit)
ws_task_exit:
        jsr     ws_unhold
        lda     ws_on
        beq     @out
        jsr     ptr_arrow               ; (it may have changed the pointer)
        ldx     #0
:       lda     w_used,x
        beq     :+
        lda     w_owner,x
        cmp     cur
        bne     :+
        phx
        jsr     win_close
        plx
:       inx
        inx
        cpx     #NWIN * 2
        bne     :--
        lda     ws_owner                ; the starter ends: the window system ends
        cmp     cur
        bne     @out
        lda     #1
        sta     ws_quit
        lda     #W_WS
        ldy     #0
        jsr     k_wake_all
@out:   rts

; ---- $74 win_draw(A = window, X, Y = {u8 op, u8 c1, u8 c2, u8 font, i16 x, i16 y,
;      i16 w, i16 h, u24 ptr}) - in content coordinates ----
; op 1 fill rectangle (c1), 2 frame (c1), 3 line to (w, h) (c1), 4 text at x, y: the
; string at ptr, font (0 UI, 1 fixed 8x12), c1 ink, c2 paper ($FF = none), 5 blit an
; 8 bpp image w x h from ptr (rows of w bytes)
sys_wdraw:
        ldx     cur
        lda     t_a,x
        jsr     win_arg
        bcc     :+
        jmp     err_inval
:       stx     kg_e
        lda     #15
        jsr     get_block
        bcc     :+
@flt:   jmp     err_fault
:       lda     kblk                    ; (0.14: ops 10 and 11 have a 17-byte block)
        and     #$00FF
        cmp     #10
        bcc     :+
        lda     #17
        jsr     get_block
        bcs     @flt
:       jsr     win_target              ; the bitmap, or the screen (wo_x, wo_y)
        ldx     kg_e
        lda     w_cx,x                  ; content -> surface coordinates: + wd_ox, wd_oy
        clc
        adc     wo_x
        sta     wd_ox
        lda     w_cy,x
        clc
        adc     wo_y
        sta     wd_oy
        lda     kblk+4
        clc
        adc     wd_ox
        sta     kg_x
        lda     kblk+6
        clc
        adc     wd_oy
        sta     kg_y
        lda     kblk+8
        sta     kg_w
        lda     kblk+10
        sta     kg_h
        lda     kblk+1
        and     #$00FF
        sta     kg_fg
        lda     kblk+2
        and     #$00FF
        sta     kg_bg
        lda     kblk
        and     #$00FF
        cmp     #1
        bne     :+
        jsr     gfx_rect
        jmp     @dmg
:       cmp     #2
        bne     :+
        jsr     gfx_frame
        ldx     kg_e
        lda     kblk+4                  ; (damage: the rectangle)
        clc
        adc     w_cx,x
        sta     kg_x
        lda     kblk+6
        clc
        adc     w_cy,x
        sta     kg_y
        lda     kblk+8
        sta     kg_w
        lda     kblk+10
        sta     kg_h
        jmp     @dmgr
:       cmp     #3
        bne     @text
        lda     kg_w                    ; end point in surface coordinates too
        clc
        adc     wd_ox
        sta     kg_w
        lda     kg_h
        clc
        adc     wd_oy
        sta     kg_h
        lda     kg_x
        pha
        lda     kg_y
        pha
        lda     kg_w
        pha
        lda     kg_h
        pha
        jsr     gfx_line
        pla                             ; damage: the bounding box
        sta     kg_h
        pla
        sta     kg_w
        pla
        sta     kg_y
        pla
        sta     kg_x
        lda     kg_w
        cmp     kg_x
        bcs     :+
        tay
        lda     kg_x
        sta     kg_w
        sty     kg_x
:       lda     kg_w
        sec
        sbc     kg_x
        inc     a
        sta     kg_w
        lda     kg_h
        cmp     kg_y
        bcs     :+
        tay
        lda     kg_y
        sta     kg_h
        sty     kg_y
:       lda     kg_h
        sec
        sbc     kg_y
        inc     a
        sta     kg_h
        jmp     @dmgr
@text:  cmp     #4
        bne     @blit
        lda     kblk+12                 ; the string (checked: at least its first byte
        sta     kt0                     ; readable; up to 199 characters drawn)
        lda     kblk+14
        and     #$00FF
        sta     kt1
        lda     #1
        sta     kt2
        stz     kt3
        jsr     uaccess
        bcc     :+
        jmp     err_fault
:       lda     kphys
        sta     kg_ln
        lda     kphys+2
        sta     kg_ln+2
        lda     kblk+3
        and     #$0001
        sta     kg_i
        jsr     win_retarget
        jsr     gfx_text
        ldx     kg_e
        lda     kblk+4                  ; damage: the line
        clc
        adc     w_cx,x
        sta     kg_x
        lda     kblk+6
        clc
        adc     w_cy,x
        sta     kg_y
        lda     kg_dx
        sta     kg_w
        lda     #12
        sta     kg_h
        jmp     @dmgr
@blit:  cmp     #7
        bne     :+
        lda     wo_x                    ; (on the screen: the checker's phase as in the
        eor     wo_y                    ; window, whose position may be odd)
        lsr     a
        bcc     @dith
        lda     kg_fg
        ldx     kg_bg
        sta     kg_bg
        stx     kg_fg
@dith:  jsr     gfx_dither
        jmp     @dmg
:       cmp     #9
        bne     :++
        lda     kblk+1                  ; op 9: the rectangle moves to (c1 | c2 << 8,
        clc                             ; the low word of ptr)
        adc     wd_ox
        sta     kg_dx
        lda     kblk+12
        clc
        adc     wd_oy
        sta     kg_dy
        jsr     gfx_mclip
        bcs     :+
        jsr     gfx_move
        lda     kg_dx                   ; damage: where it went
        sta     kg_x
        lda     kg_dy
        sta     kg_y
        jmp     @dmgr
:       lda     #0
        jmp     set_ok
:       cmp     #10
        bne     :+
        jsr     ws_expand
        bcs     @flt2
        jsr     bl_wait                 ; (0.15) the source is the program's memory: done
        jmp     @dmgr                   ; reading it before the program runs again
@flt2:  jmp     err_fault
:       cmp     #5
        beq     :+
        cmp     #6
        beq     :+
        cmp     #8
        beq     :+
        cmp     #11
        beq     :+
        jmp     err_inval
:       jsr     ws_blit
        bcs     @flt2
        jsr     bl_wait                 ; (0.15, as for op 10)
        jmp     @dmgr
@dmg:   lda     wo_dir                  ; (drawn on the screen: nothing to repaint)
        bne     @nod
        ldx     kg_e
        lda     kblk+4                  ; damage: the (unclipped) rectangle
        clc
        adc     w_cx,x
        sta     kg_x
        lda     kblk+6
        clc
        adc     w_cy,x
        sta     kg_y
        lda     kblk+8
        sta     kg_w
        lda     kblk+10
        sta     kg_h
@dmgr:  lda     wo_dir
        bne     @nod
        ldx     kg_e                    ; (minimized: its bitmap only)
        lda     w_st,x
        and     #WS_MIN
        bne     @nod
        ldx     kg_e                    ; surface -> screen; clipped to the content
        jsr     win_clip
        jsr     clip_rect
        bcs     @nod
        ldx     kg_e
        lda     kg_x
        clc
        adc     w_x,x
        sta     kg_x
        lda     kg_y
        clc
        adc     w_y,x
        sta     kg_y
        jsr     damage
@nod:   lda     #0
        jmp     set_ok

; op 5: an image of kg_w x kg_h bytes at the caller's kblk+12 -> kg_x, kg_y (clipped)
ws_blit:
        lda     kblk+12                 ; the whole image must be readable
        sta     kt0
        lda     kblk+14
        and     #$00FF
        sta     kt1
        lda     kg_w                    ; source stride: the width, or (op 8) c1 | c2 << 8
        sta     kg_dx
        lda     kblk
        and     #$00FF
        cmp     #8
        bne     :+
        lda     kblk+1
        sta     kg_dx
:       cmp     #11                     ; (op 11: the stride at +15; 0: the width)
        bne     :+
        lda     kblk+15
        beq     :+
        sta     kg_dx
:       lda     kg_dx                   ; readable: stride * (h - 1) + w
        sta     kt2
        stz     kt6
        ldy     kg_h
        jeq     @ok
        dey
        beq     :++
:       lda     kt6
        clc
        adc     kt2
        jcs     @bad
        sta     kt6
        dey
        bne     :-
:       lda     kt6
        clc
        adc     kg_w
        jcs     @bad
        sta     kt2
        stz     kt3
        jsr     uaccess
        jcs     @bad
        lda     kphys
        sta     kg_s
        lda     kphys+2
        sta     kg_s+2
        lda     kg_x                    ; clip; the source moves by what was cut
        sta     kg_t
        lda     kg_y
        sta     kg_u
        lda     kg_t
        pha
        lda     kg_u
        pha
        jsr     clip_rect
        pla
        sta     kg_dy                   ; original y
        pla
        sta     kg_v                    ; original x
        jcs     @ok
        lda     kg_y                    ; source += (y - y0) * stride + (x - x0)
        sec
        sbc     kg_dy
        tay
        beq     :++
:       lda     kg_s
        clc
        adc     kg_dx
        sta     kg_s
        dey
        bne     :-
:       lda     kg_x
        sec
        sbc     kg_v
        clc
        adc     kg_s
        sta     kg_s
        lda     bl_on
        beq     @sw
        lda     kg_y                    ; the blitter: one COPY or COPY_KEY
        jsr     surf_line
        jsr     surf_stride
        sta     kg_t
        jsr     bl_wait
        lda     kg_t
        sta     f:BL_DSTR
        lda     kg_dx
        sta     f:BL_SSTR
        lda     kg_s
        sta     f:BL_SRC
        lda     kg_p
        clc
        adc     kg_x
        sta     f:BL_DST
        lda     kg_w
        sta     f:BL_W
        lda     kg_h
        sta     f:BL_H
        a8
        lda     kg_s+2
        sta     f:BL_SRC+2
        lda     kg_p+2
        sta     f:BL_DST+2
        lda     kblk+2
        sta     f:BL_KEY
        lda     #0
        sta     f:BL_FLAGS
        lda     kblk                    ; ops 6 and 11: COPY_KEY
        cmp     #6
        beq     :+
        cmp     #11
        bne     :++
:       lda     #BO_KEY
        bra     :++
:       lda     #BO_COPY
:       sta     f:BL_OP
        lda     #1
        sta     f:BL_CTRL
        a16
        bra     @ok
@sw:    lda     kg_y                    ; the CPU, a row at a time (kg_y and kg_h are the
        pha                             ; caller's damage rectangle: kept)
        lda     kg_h
        pha
@row:   lda     kg_y
        jsr     surf_line
        lda     kg_p
        clc
        adc     kg_x
        sta     kg_p
        lda     kblk
        and     #$00FF
        cmp     #6
        beq     @key
        cmp     #11
        beq     @key
        lda     kg_w
        sta     kg_n
        jsr     gfx_copy
        bra     @nr
@key:   ldy     #0                      ; ops 6, 11: pixels equal to c2 are skipped
        a8
:       lda     [kg_s],y
        cmp     kblk+2
        beq     :+
        sta     [kg_p],y
:       iny
        cpy     kg_w
        bne     :--
        a16
@nr:    lda     kg_s
        clc
        adc     kg_dx
        sta     kg_s
        inc     kg_y
        dec     kg_h
        bne     @row
        pla
        sta     kg_h
        pla
        sta     kg_y
@ok:    clc
        rts
@bad:   sec
        rts

; (0.14) op 10: a 1 bpp image (bit 7 leftmost) of kg_w x kg_h at the caller's kblk+12,
; its first pixel at bit kblk+3 (0 = the leftmost of the first byte), rows kblk+15 bytes
; apart (0: as many as one row needs): set bits in ink kg_fg, clear ones in kg_bg ($FF:
; left as they are) -> kg_x, kg_y (clipped). The blitter: one EXPAND / EXPAND_KEY; the
; CPU: pixel by pixel. C set: the source is not readable.
ws_expand:
        lda     kblk+3
        and     #7
        sta     kg_q                    ; the first bit (0 = the leftmost)
        clc                             ; bytes a row needs: (bit + w + 7) / 8
        adc     kg_w
        adc     #7
        lsr     a
        lsr     a
        lsr     a
        sta     kt4
        lda     kblk+15                 ; the stride (0: those bytes)
        bne     :+
        lda     kt4
:       sta     kg_dx
        lda     kblk+12                 ; readable: stride * (h - 1) + a row's bytes
        sta     kt0
        lda     kblk+14
        and     #$00FF
        sta     kt1
        stz     kt6
        ldy     kg_h
        jeq     @ok
        dey
        beq     :++
:       lda     kt6
        clc
        adc     kg_dx
        jcs     @bad
        sta     kt6
        dey
        bne     :-
:       lda     kt6
        clc
        adc     kt4
        jcs     @bad
        sta     kt2
        stz     kt3
        jsr     uaccess
        jcs     @bad
        lda     kphys
        sta     kg_s
        lda     kphys+2
        sta     kg_s+2
        lda     kg_x                    ; clip; the source moves by what was cut
        pha
        lda     kg_y
        pha
        jsr     clip_rect
        pla
        sta     kg_dy                   ; original y
        pla
        sta     kg_v                    ; original x
        jcs     @ok
        lda     kg_y                    ; source += (y - y0) * stride
        sec
        sbc     kg_dy
        tay
        beq     :++
:       lda     kg_s
        clc
        adc     kg_dx
        sta     kg_s
        dey
        bne     :-
:       lda     kg_x                    ; bit += x - x0; source += bit / 8
        sec
        sbc     kg_v
        clc
        adc     kg_q
        pha
        and     #7
        sta     kg_q
        pla
        lsr     a
        lsr     a
        lsr     a
        clc
        adc     kg_s
        sta     kg_s
        lda     bl_on
        beq     @sw
        lda     kg_y                    ; the blitter: one EXPAND (EXPAND_KEY: no paper)
        jsr     surf_line
        jsr     surf_stride
        sta     kg_t
        jsr     bl_wait
        lda     kg_t
        sta     f:BL_DSTR
        lda     kg_dx
        sta     f:BL_SSTR
        lda     kg_s
        sta     f:BL_SRC
        lda     kg_p
        clc
        adc     kg_x
        sta     f:BL_DST
        lda     kg_w
        sta     f:BL_W
        lda     kg_h
        sta     f:BL_H
        lda     kg_q                    ; SRC_BIT: 7 = the leftmost
        eor     #7
        asl     a
        asl     a
        asl     a
        asl     a
        a8
        sta     f:BL_FLAGS
        lda     kg_s+2
        sta     f:BL_SRC+2
        lda     kg_p+2
        sta     f:BL_DST+2
        lda     kg_fg
        sta     f:BL_FG
        lda     kg_bg
        sta     f:BL_BG
        cmp     #$FF
        beq     :+
        lda     #BO_EXP
        bra     :++
:       lda     #BO_EXPK
:       sta     f:BL_OP
        lda     #1
        sta     f:BL_CTRL
        a16
@ok:    clc
        rts
@bad:   sec
        rts
@sw:    jsr     bl_wait
        lda     kg_y                    ; the CPU (kg_y and kg_h: the caller's damage)
        pha
        lda     kg_h
        pha
@row:   lda     kg_y
        jsr     surf_line
        lda     kg_p
        clc
        adc     kg_x
        sta     kg_p
        lda     kg_s
        sta     kp0
        lda     kg_s+2
        sta     kp0+2
        lda     #$80                    ; the mask of the first bit
        ldy     kg_q
        beq     :++
:       lsr     a
        dey
        bne     :-
:       sta     kt1
        a8
        lda     [kp0]
        a16
        and     #$00FF
        sta     kt0
        lda     kg_w
        sta     kt2
@px:    lda     kt0
        and     kt1
        beq     @off
        lda     kg_fg
        bra     @put
@off:   lda     kg_bg
        and     #$00FF
        cmp     #$FF
        beq     @skip
@put:   a8
        sta     [kg_p]
        a16
@skip:  inc     kg_p
        dec     kt2
        beq     @nr
        lsr     kt1
        bne     @px
        lda     #$80
        sta     kt1
        inc     kp0
        a8
        lda     [kp0]
        a16
        and     #$00FF
        sta     kt0
        bra     @px
@nr:    lda     kg_s
        clc
        adc     kg_dx
        sta     kg_s
        inc     kg_y
        dec     kg_h
        bne     @row
        pla
        sta     kg_h
        pla
        sta     kg_y
        clc
        rts

; ---- $75 win_event(A = 0 wait, 1 poll; X, Y = 8-byte buffer) -> the next event of any
; of the caller's windows: {u8 type, u8 window, u16 a, u16 b, u16 c}. EAGAIN when polling
; and there is none. Interruptible by kill. ----
sys_wevent:
        ldx     cur
        lda     t_x,x
        sta     kt0
        lda     t_y,x
        sta     kt1
        lda     #8
        sta     kt2
        lda     #1
        sta     kt3
        jsr     uaccess
        bcc     :+
        jmp     err_fault
:       ldx     #0                      ; a window of ours with an event
@w:     lda     w_used,x
        beq     @nx
        lda     w_owner,x
        cmp     cur
        bne     @nx
        lda     w_qn,x
        bne     @take
@nx:    inx
        inx
        cpx     #NWIN * 2
        bne     @w
        ldx     cur
        lda     t_a,x
        beq     :+
        lda     #EAGAIN
        jmp     set_err
:       lda     t_killed,x
        beq     :+
        jmp     err_inval
:       lda     #W_WEVENT
        ldy     #0
        jsr     k_block
        bra     sys_wevent
@take:  stx     kg_e
        lda     w_qh,x                  ; its oldest event
        sta     kg_i
        txa                             ; window*2*16 = window*NWEV
        asl     a
        asl     a
        asl     a
        asl     a
        clc
        adc     kg_i
        asl     a
        asl     a
        asl     a
        tay
        lda     kphys
        sta     kp1
        lda     kphys+2
        sta     kp1+2
        lda     w_ev,y                  ; type | window << 8
        and     #$00FF
        sta     kg_t
        lda     kg_e
        lsr     a
        xba
        ora     kg_t
        sta     [kp1]
        tyx
        ldy     #2
        lda     w_ev+2,x
        sta     [kp1],y
        ldy     #4
        lda     w_ev+4,x
        sta     [kp1],y
        ldy     #6
        lda     w_ev+6,x
        sta     [kp1],y
        ldx     kg_e
        lda     w_qh,x
        inc     a
        and     #NWEV - 1
        sta     w_qh,x
        dec     w_qn,x
        lda     #0
        jmp     set_ok

; ---- $76 win_twidth(X, Y = string, A = font) -> A = its width in pixels ----
sys_wtwidth:
        ldx     cur
        lda     t_x,x
        sta     kt0
        lda     t_y,x
        sta     kt1
        lda     #1
        sta     kt2
        stz     kt3
        jsr     uaccess
        bcc     :+
        jmp     err_fault
:       lda     kphys
        sta     kg_ln
        lda     kphys+2
        sta     kg_ln+2
        ldx     cur
        lda     t_a,x
        and     #$0001
        jsr     text_width
        jmp     set_ok

; ---- $77 ws_sync: wait until the screen shows everything drawn so far ----
sys_wssync:
        lda     ws_on
        beq     @ok
        lda     d_n
        ora     ws_busy
        ora     tm_pend
        beq     @ok
        lda     #1                      ; let the compositor run, then look again
        jsr     k_sleep_ticks
        bra     sys_wssync
@ok:    lda     #0
        jmp     set_ok

; ---- $78 win_move(A = window, X = x, Y = y) ----
sys_wmove:
        ldx     cur
        lda     t_a,x
        jsr     win_arg
        bcc     :+
        jmp     err_inval
:       stx     kg_e
        jsr     win_unstale
        jsr     win_damage
        ldx     kg_e
        ldy     cur
        lda     t_x,y                   ; kept on the screen
        bpl     :+
        lda     #0
:       sta     kg_t
        lda     #SCR_W
        sec
        sbc     w_w,x
        cmp     kg_t
        bcs     :+
        sta     kg_t
:       lda     kg_t
        sta     w_x,x
        lda     t_y,y
        bpl     :+
        lda     #0
:       sta     kg_t
        lda     #SCR_H
        sec
        sbc     w_h,x
        cmp     kg_t
        bcs     :+
        sta     kg_t
:       lda     kg_t
        sta     w_y,x
        jsr     win_damage
        lda     #0
        jmp     set_ok

; ---- $8B ws_hold(A = 1 hold, 0 release): while a program draws one change in several
; calls, the compositor keeps the screen as it is (no half-drawn state is shown), at most
; 5 ticks; the release repaints at once. Released at the program's exit. ----
sys_wshold:
        ldx     cur
        lda     t_a,x
        beq     :+
        lda     ws_hl,x                 ; hold
        bne     @ok
        inc     a
        sta     ws_hl,x
        inc     ws_hn
        bra     @ok
:       jsr     ws_unhold
@ok:    lda     #0
        jmp     set_ok

; the current task's hold ends (release, exit); the last one wakes the compositor if it
; waits for it
ws_unhold:
        ldx     cur
        lda     ws_hl,x
        beq     @out
        stz     ws_hl,x
        dec     ws_hn
        bne     @out
        lda     ws_on
        beq     @out
        ldx     ws_thr
        lda     t_state,x
        cmp     #TS_BLOCKED
        bne     @out
        lda     t_wreason,x
        cmp     #W_SLEEP
        bne     @out
        jmp     k_wake
@out:   rts

; ---- $79 ws_redraw: damage the whole screen (for measurements) ----
sys_wsredraw:
        lda     ws_on
        beq     :+
        jsr     damage_all
        lda     #W_WS
        ldy     #0
        jsr     k_wake_all
:       lda     #0
        jmp     set_ok

; ---- $7B ws_config(A = bit 0 blitter off, bit 1 the compositor sleeps on the blitter
; interrupt) -> A = 1 if the blitter is in use (for measurements and tests), (0.16) X = the
; hardware revision (SYS_REV: About tells from it what the machine has) ----
sys_wscfg:
        ldx     cur
        lda     t_a,x
        and     #4
        sta     ws_nodir
        lda     t_a,x
        and     #3
        sta     bl_force
        lda     k_rev
        sta     t_x,x
        jsr     bl_config
        lda     bl_on
        jmp     set_ok

; ---- $7A ws_stats -> A, X = microseconds the last repaint took (low, high) ----
sys_wsstats:
        ldx     cur
        lda     ws_last+2
        sta     t_x,x
        lda     ws_last
        jmp     set_ok

