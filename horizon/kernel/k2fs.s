; k2fs.s - (0.18) full-screen mode: a program takes the whole screen for one of its windows.
;
; fs_enter gives the kernel a framebuffer in the program's own memory (its whole range, every
; row Marga may read, checked to be the caller's), a mode (640x360x8, 640x360x4, 320x180x8),
; and from then on, while that window has the keyboard focus, Marga shows that framebuffer with
; the program's own palette (all 256 entries), its scroll registers (REV $0B), its sprites in
; screen coordinates and its raster table; the menu bar and the other windows are not shown.
; The window itself stays a normal window on the desktop (what the program drew in it).
;
; Leaving: fs_leave, closing the window, the program's end (exit, kill, crash), freeing a bank
; the framebuffer lies in. The user can always leave: Alt+Tab, Alt+Esc and F12 minimize the
; full-screen window (the desktop comes back as it was; F12 then shows the classic machine),
; whatever the program does; Alt+F4 sends it WE_CLOSE. Whenever the window loses the focus (a
; window of another program comes up, the Windows menu, ...) the desktop comes back too, and
; the program gets WE_UNFOCUS; when the window gets the focus again (Alt+Tab, the Windows menu,
; a click on it) its screen is shown again as it was (the framebuffer is its own memory; the
; kernel keeps mode, base, stride, scroll registers, palette, raster table and sprites) and it
; gets WE_FOCUS. While shown, keys, buttons, motion and the wheel go to that window, with the
; pointer's position on the screen (in 320x180 pixels in that mode); the window manager keeps
; only the keys above. One program at a time (EAGAIN for another one, even while the first one
; is in the background).
;
; Scroll registers and NV_BASE are written in the vertical blank interrupt (whole frames only).
; The raster table changes palette entries at given lines: the LINE interrupt comes one line
; early, the handler waits for the line to begin and writes the colour in the horizontal blank,
; so a change is exact from that line on while the CPU runs a program or idles (kernel work with
; interrupts masked, such as a file read or a CPU blit, can delay it). In the vertical blank
; the entries get their colours of the palette back, so every frame starts the same.

FS_PTR      = 1                 ; fs_enter flags: the mouse pointer is shown (not in 320x180)

; (0.30) these two in the video-state block (vstate.s, version 2: offset 800), for screenshots
        .segment "VSTATE"
fs_act:     .res    2           ; its screen is on Marga now
fs_scr:     .res    14          ; scroll set: x, y, x2, y2, vheight, split line, ctrl
        .assert fs_act = $01F000 + 800, lderror, "video state: fs_act must be at offset 800"

        .segment "BSS"
fs_on:      .res    2           ; a program is in full-screen mode (fs_w, fs_task)
fs_w:       .res    2           ; its window*2
fs_task:    .res    2           ; its slot*2
fs_mode:    .res    2           ; 0 640x360x8, 1 640x360x4, 2 320x180x8
fs_flags:   .res    2
fs_base:    .res    4           ; physical address of row 0
fs_stride:  .res    2
fs_rows:    .res    2
fs_b0:      .res    2           ; the banks the framebuffer lies in
fs_b1:      .res    2
fs_new:     .res    14          ; (fs_scroll's block, checked before it is taken)
fs_dirty:   .res    2           ; the registers change at the next vertical blank
fs_lx:      .res    2           ; the pointer's last position (motion events)
fs_ly:      .res    2
rs_n:       .res    2           ; raster table: entries
rs_i:       .res    2           ; the next one (LINE interrupt)
rs_tab:     .res    16*6        ; {u16 line, u8 index, u8 r, g, b}

        .segment "K2CODE"

; C set if the current task is the full-screen program
fs_mine:
        lda     fs_on
        beq     @no
        lda     fs_task
        cmp     cur
        bne     @no
        sec
        rts
@no:    clc
        rts

; ---- $96 fs_enter(A = window, X, Y = 10-byte block) ----
; Block: u8 mode (0 640x360x8, 1 640x360x4, 2 320x180x8), u8 flags (FS_PTR 1: the pointer shown),
; u16 stride (bytes a row, a multiple of 16, at least 640 / 320 / 320), u16 rows (360 / 360 /
; 180 .. 1024), u24 base (256-byte aligned: row 0), u8 0. Rows * stride bytes from base must be
; the caller's memory (EFAULT). Again for the same window: a new framebuffer, mode or geometry
; (page flipping), from the next frame on; the scroll set must still fit (EINVAL). EAGAIN:
; another window is in full-screen mode. The window must not be a backdrop or a terminal.
k2_fsenter:
        lda     ws_on
        bne     :+
        jmp     k2_inval
:       ldx     cur
        lda     t_a,x
        jsl     f_win_arg
        bcc     :+
        jmp     k2_inval
:       lda     w_fl,x
        and     #4 | 16                 ; (WF_BACK, WF_TERM)
        beq     :+
        jmp     k2_inval
:       stx     kx6
        lda     fs_on
        beq     :+
        cpx     fs_w
        beq     :+
        lda     #EAGAIN
        jmp     k2_err
:       ldx     cur
        lda     t_x,x
        sta     kt0
        lda     t_y,x
        sta     kt1
        lda     #10
        sta     kt2
        stz     kt3
        jsl     f_uaccess
        bcc     :+
        jmp     k2_fault
:       lda     kphys
        sta     kp2
        lda     kphys+2
        sta     kp2+2
        ldy     #0
        lda     [kp2],y                 ; mode, flags
        and     #$00FF
        cmp     #3
        bcs     @inv
        sta     kx0
        lda     [kp2],y
        xba
        and     #$00FF
        sta     kx1
        ldy     #2
        lda     [kp2],y                 ; stride: 16 | it, >= the bytes of a line, <= 4096
        sta     kx2
        bit     #$000F
        bne     @inv
        cmp     #4097
        bcs     @inv
        ldx     #640
        lda     kx0
        beq     :+
        ldx     #320
:       cpx     kx2
        beq     :+
        bcs     @inv
:       ldy     #4                      ; rows: 360 (180 in 320x180) .. 1024
        lda     [kp2],y
        sta     kx3
        cmp     #1025
        bcs     @inv
        ldx     #360
        lda     kx0
        cmp     #2
        bne     :+
        ldx     #180
:       cpx     kx3
        beq     :+
        bcs     @inv
:       ldy     #6                      ; base: 256-byte aligned
        lda     [kp2],y
        bit     #$00FF
        bne     @inv
        sta     kt0
        ldy     #8
        lda     [kp2],y
        and     #$00FF
        sta     kt1
        lda     kx2                     ; rows * stride bytes (24 bits)
        ldx     kx3
        jsr     mul16
        sta     kt2
        stx     kt3
        jsr     hw_range
        bcc     :+
        jmp     k2_fault
@inv:   jmp     k2_inval
:       ldx     #12                     ; the scroll set kept must fit the new geometry
:       lda     fs_scr,x
        sta     fs_new,x
        dex
        dex
        bpl     :-
        lda     fs_on
        bne     @kept
        ldx     #12                     ; (new: no scrolling)
:       stz     fs_new,x
        dex
        dex
        bpl     :-
@kept:  lda     kx0
        ldx     kx2
        ldy     kx3
        jsr     fs_check
        bcs     @inv
        lda     kx0                     ; taken
        sta     fs_mode
        lda     kx1
        sta     fs_flags
        lda     kx2
        sta     fs_stride
        lda     kx3
        sta     fs_rows
        lda     kphys
        sta     fs_base
        lda     kphys+2
        and     #$00FF
        sta     fs_base+2
        lda     hr_b0
        sta     fs_b0
        lda     hr_b1
        sta     fs_b1
        ldx     #12
:       lda     fs_new,x
        sta     fs_scr,x
        dex
        dex
        bpl     :-
        lda     fs_on
        bne     @again
        inc     fs_on                   ; new: the window, the palette as now shown
        lda     kx6
        sta     fs_w
        lda     cur
        sta     fs_task
        stz     rs_n
        ldx     #766
:       lda     vs_pal,x
        sta     fs_pal,x
        dex
        dex
        bpl     :-
        lda     ms_x
        sta     fs_lx
        lda     ms_y
        sta     fs_ly
        jsr     fs_update
        jmp     k2_ok0
@again: lda     fs_act                  ; the same window again: the next frame
        beq     :+
        jsr     fs_ctrl
        lda     #1
        sta     fs_dirty
        jsr     vbl_arm
:       jmp     k2_ok0

; A * X (16 x 16 bits) -> A = low word, X = high word. Shifts the smaller factor, low bit
; first, and stops when it runs out (y * stride, (h - 1) * stride: a few steps). Uses kt4-kt7.
mul16:  stx     kt7
        cmp     kt7                     ; the larger one is shifted up, the smaller down
        bcs     :+
        sta     kt7
        txa
:       sta     kt6
        stz     kt5                     ; (its high word)
        stz     kt4                     ; the product: kt4 (low), X (high)
        ldx     #0
@b:     lsr     kt7
        bcc     @n
        lda     kt4
        clc
        adc     kt6
        sta     kt4
        txa
        adc     kt5
        tax
@n:     lda     kt7
        beq     @out
        asl     kt6
        rol     kt5
        bra     @b
@out:   lda     kt4
        rts

; the scroll set fs_new checked for mode A, stride X, rows Y: C set if Marga could read past the
; framebuffer (or a value is out of range)
fs_check:
        sta     kx4                     ; mode
        stx     kx5                     ; stride
        sty     kx7                     ; rows
        lda     fs_new+12               ; ctrl: HWRAP 1, SPLIT 2
        and     #$FFFC
        bne     @bad
        lda     fs_new+8                ; vheight: 0, or 1 .. rows
        cmp     #1025
        bcs     @bad
        cmp     kx7
        beq     :+
        bcs     @bad
:       ldy     #360                    ; rows on the screen
        lda     kx4
        cmp     #2
        bne     :+
        ldy     #180
:       sty     kt5
        lda     fs_new+12
        and     #2
        beq     @one
        lda     fs_new+10               ; the split line: 1 .. 359 (even in 320x180)
        beq     @bad
        cmp     #360
        bcs     @bad
        ldx     kx4
        cpx     #2
        bne     :+
        lsr     a
        bcs     @bad
:       sta     kt4                     ; rows of the first set
        lda     fs_new+2
        ldy     kt4
        jsr     fs_rowsok
        bcs     @bad
        lda     kt5
        sec
        sbc     kt4
        tay
        lda     fs_new+6
        jsr     fs_rowsok
        bcs     @bad
        lda     fs_new+4
        jsr     fs_xok
        bcs     @bad
        bra     :+
@one:   lda     fs_new+2
        ldy     kt5
        jsr     fs_rowsok
        bcs     @bad
:       lda     fs_new
        jmp     fs_xok
@bad:   sec
        rts

; rows from A on, Y of them, in the framebuffer (kx7 rows, vheight fs_new+8): C set if not
fs_rowsok:
        cmp     #1024
        bcs     @bad
        ldx     fs_new+8
        beq     @lin
        cmp     fs_new+8                ; below vheight: it wraps inside 0 .. vheight - 1
        bcc     @ok
@lin:   sty     kt6                     ; else rows A .. A + Y - 1
        clc
        adc     kt6
        cmp     kx7
        beq     @ok
        bcs     @bad
@ok:    clc
        rts
@bad:   sec
        rts

; scroll x = A (pixels): C set if a line would read past its row
fs_xok: cmp     #4096
        bcs     @bad
        ldx     kx4                     ; 4 bpp: two pixels a byte
        cpx     #1
        bne     :+
        lsr     a
:       sta     kt6                     ; bytes skipped
        lda     fs_new+12
        and     #1
        beq     @nowrap
        lda     kt6                     ; HWRAP: inside the row
        cmp     kx5
        bcs     @bad
        clc
        rts
@nowrap:
        ldx     #640                    ; bytes + a line's bytes <= stride
        lda     kx4
        beq     :+
        ldx     #320
:       stx     kt7
        lda     kt6
        clc
        adc     kt7
        cmp     kx5
        beq     :+
        bcs     @bad
:       clc
        rts
@bad:   sec
        rts

; ---- $97 fs_leave(A = window) ----
k2_fsleave:
        ldx     cur
        lda     t_a,x
        jsl     f_win_arg
        bcs     @bad
        lda     fs_on
        beq     @bad
        cpx     fs_w
        bne     @bad
        jsr     fs_end
        jmp     k2_ok0
@bad:   jmp     k2_inval

; full-screen mode ends (the desktop back if it was shown)
fs_end: stz     fs_on
        stz     rs_n
        jmp     fs_update

; ---- $98 fs_scroll(X, Y = 14-byte block): the scroll registers (REV $0B) ----
; Block: u16 x, u16 y (the first set: the row on line 0, the pixels skipped), u16 x2, u16 y2
; (the second set, from the split line), u16 vheight (rows of the virtual bitmap; 0 no
; vertical wrap), u16 split line (1-359, even in 320x180), u8 ctrl (1 HWRAP: a row is a ring
; of stride bytes, 2 SPLIT), u8 0. Taken at the next vertical blank, all together. Checked
; against the framebuffer: every row and byte Marga would read must lie in it (EINVAL). Only the
; full-screen program (EINVAL); ENODEV before REV $0B.
k2_fsscroll:
        lda     k_rev
        cmp     #$0B
        bcs     :+
        lda     #ENODEV
        jmp     k2_err
:       jsr     fs_mine
        bcs     :+
        jmp     k2_inval
:       ldx     cur
        lda     t_x,x
        sta     kt0
        lda     t_y,x
        sta     kt1
        lda     #14
        sta     kt2
        stz     kt3
        jsl     f_uaccess
        bcc     :+
        jmp     k2_fault
:       lda     kphys
        sta     kp2
        lda     kphys+2
        sta     kp2+2
        ldy     #12
:       lda     [kp2],y
        tyx
        sta     fs_new,x
        dey
        dey
        bpl     :-
        lda     fs_new+12
        and     #$00FF
        sta     fs_new+12
        lda     fs_mode
        ldx     fs_stride
        ldy     fs_rows
        jsr     fs_check
        bcc     :+
        jmp     k2_inval
:       ldx     #12
:       lda     fs_new,x
        sta     fs_scr,x
        dex
        dex
        bpl     :-
        lda     fs_act
        beq     :+
        lda     #1
        sta     fs_dirty
        jsr     vbl_arm
:       jmp     k2_ok0

; ---- $99 fs_raster(A = count 0-16, X, Y = count entries of 6 bytes) ----
; Entry: u16 line (1-359; with the split: the split line or later), u8 palette index, u8 red,
; green, blue. From that line on the entry has that colour; lines ascending (equal ones are
; written in order in the same blank). Every frame starts with the palette's own colours.
; Count 0: off. Only the full-screen program (EINVAL); ENODEV before REV $09.
k2_fsraster:
        lda     k_rev
        cmp     #$09
        bcs     :+
        lda     #ENODEV
        jmp     k2_err
:       jsr     fs_mine
        bcs     :+
        jmp     k2_inval
:       ldx     cur
        lda     t_a,x
        cmp     #17
        bcc     :+
        jmp     k2_inval
:       sta     kx5
        cmp     #0                      ; (STA kept cmp #17's flags: count 0 is the test)
        bne     :+
        stz     rs_n                    ; off
        jsr     rs_off
        jmp     k2_ok0
:       asl     a                       ; * 6
        adc     kx5
        asl     a
        sta     kt2
        stz     kt3
        lda     t_x,x
        sta     kt0
        lda     t_y,x
        sta     kt1
        jsl     f_uaccess
        bcc     :+
        jmp     k2_fault
:       lda     kphys
        sta     kp2
        lda     kphys+2
        sta     kp2+2
        lda     #1                      ; lines: ascending, 1-359, from the split line on
        sta     kx6
        lda     fs_scr+12
        and     #2
        beq     :+
        lda     fs_scr+10
        sta     kx6
:       ldy     #0
        ldx     kx5
@chk:   lda     [kp2],y
        cmp     kx6
        bcc     @bad
        cmp     #360
        bcs     @bad
        sta     kx6
        tya
        clc
        adc     #6
        tay
        dex
        bne     @chk
        stz     rs_n                    ; (the interrupt sees no table while it changes)
        ldy     kt2
        dey
        tyx
        a8
:       lda     [kp2],y
        sta     rs_tab,x
        dex
        dey
        bpl     :-
        a16
        lda     kx5
        sta     rs_n
        lda     fs_act
        beq     :+
        jsr     vbl_arm
:       jmp     k2_ok0
@bad:   jmp     k2_inval

; the LINE interrupt off, the compare value back to "never" (keeps nothing)
rs_off: a8
        lda     f:IRQ_EN
        and     #$FF ^ IRQ_LINE
        sta     f:IRQ_EN
        lda     #IRQ_LINE
        sta     f:IRQ_STATUS
        a16
        lda     fs_act                  ; (the split keeps its line)
        beq     :+
        lda     fs_scr+12
        and     #2
        beq     :+
        lda     fs_scr+10
        bra     :++
:       lda     #511
:       sta     f:NV_LINE_CMP
        rts

; ---- shown or not: the full-screen program's window has the focus, it is not minimized, the
; desktop is on the screen. Window-system thread or syscall context.
fs_update:
        lda     fs_on
        beq     @no
        lda     ws_on
        beq     @no
        lda     cls_on
        bne     @no
        ldx     fs_w
        cpx     fo_w
        bne     @no
        lda     w_st,x
        and     #1                      ; (WS_MIN)
        bne     @no
        lda     fs_act
        bne     @out
        jmp     fs_show
@no:    lda     fs_act
        beq     @out
        jmp     fs_hide
@out:   rts

; NV_CTRL for the full screen: ENABLE, the mode, the pointer if asked for (not in 320x180)
fs_ctrl:
        lda     fs_mode
        asl     a
        ora     #1
        sta     kx7
        lda     fs_mode
        cmp     #2
        beq     :+
        lda     fs_flags
        and     #FS_PTR
        beq     :+
        lda     kx7
        ora     #8
        sta     kx7
:       lda     kx7
        sta     scr_ctrl                ; (the classic machine's return and the mouse use it)
        jsl     f_nv_ctrl
        rts

fs_show:
        lda     #1
        sta     fs_act
        jsr     fs_ctrl
        jsr     fs_regs                 ; base, stride, scroll (at once: the switch itself)
        ldx     #0                      ; its palette
        stx     kx5
@p:     lda     kx5
        asl     a
        adc     kx5
        tax
        lda     fs_pal+2,x
        and     #$00FF
        tay
        lda     fs_pal,x
        tax
        lda     kx5
        jsr     pal_hw
        inc     kx5
        lda     kx5
        cmp     #256
        bcc     @p
        stz     rs_i
        jsr     spr_sync
        lda     ms_x                    ; (no motion event for the switch)
        sta     fs_lx
        lda     ms_y
        sta     fs_ly
        jmp     vbl_arm

fs_hide:
        jsr     fs_noscroll
        jsl     f_ws_desk_mode          ; the desktop's screen and palette (k2_pal_apply too)
        jsl     f_damage_all
        jmp     spr_sync

; no full screen on Marga: the raster interrupt off, the scroll registers at their reset values
fs_noscroll:
        stz     fs_act
        stz     fs_dirty
        jsr     rs_off
        lda     k_rev
        cmp     #$0B
        bcc     :+
        lda     #0
        sta     f:NV_SCROLLX
        sta     f:NV_SCROLLX+2
        sta     f:NV_SCROLLX+4
        sta     f:NV_SCROLLX+6
        sta     f:NV_SCROLLX+8
        a8
        sta     f:NV_SCROLL_CTRL
        a16
:       rts

; the full-screen registers now: NV_BASE, NV_STRIDE, the scroll set and the split line
; (interrupt context too: no kx*)
fs_regs:
        lda     fs_stride
        sta     f:NV_STRIDE
        sta     vs_stride
        lda     fs_base+1
        sta     f:NV_BASE+1
        sta     vs_base+1
        a8
        lda     fs_base
        sta     f:NV_BASE
        sta     vs_base
        a16
        lda     k_rev
        cmp     #$0B
        bcc     @out
        ldx     #8
:       lda     fs_scr,x
        sta     f:NV_SCROLLX,x
        dex
        dex
        bpl     :-
        a8
        lda     fs_scr+12
        sta     f:NV_SCROLL_CTRL
        a16
        and     #2
        beq     @out
        lda     fs_scr+10
        sta     f:NV_LINE_CMP
@out:   rts

; (vertical blank, interrupt context) the full-screen screen: registers that changed, the raster
; table's colours back and its first line armed -> A non-zero: the next blank is needed too
fs_vbl: lda     fs_act
        bne     :+
        lda     #0
        rts
:       lda     fs_dirty
        beq     :+
        stz     fs_dirty
        jsr     fs_regs
:       lda     rs_n
        bne     :+
        rts                             ; (A = 0)
:       stz     ki4                     ; the table's entries get their palette colours back
        lda     rs_n
        sta     ki7
@back:  ldx     ki4
        lda     rs_tab+2,x
        and     #$00FF
        sta     ki3
        asl     a
        adc     ki3
        tax
        lda     fs_pal+2,x
        and     #$00FF
        tay
        lda     fs_pal,x
        tax
        lda     ki3
        jsr     pal_hw
        lda     ki4
        clc
        adc     #6
        sta     ki4
        dec     ki7
        bne     @back
        stz     rs_i
        lda     fs_scr+12               ; the first interrupt: one line before the first entry,
        and     #2                      ; or with the split at the split line (latched there)
        beq     :+
        lda     fs_scr+10
        bra     @cmp
:       lda     rs_tab
        dec     a
@cmp:   sta     f:NV_LINE_CMP
        a8
        lda     #IRQ_LINE
        sta     f:IRQ_STATUS
        lda     f:IRQ_EN
        ora     #IRQ_LINE
        sta     f:IRQ_EN
        a16
        lda     #1
        rts

; ---- (irq_service, first) the LINE interrupt: the raster table's entries due now ----
        .export k2_line: far
k2_line:
        a8
        lda     #IRQ_LINE
        sta     f:IRQ_STATUS
        a16
        lda     fs_act
        beq     @stop
@next:  lda     rs_i
        cmp     rs_n
        bcs     @stop
        asl     a                       ; entry * 6
        adc     rs_i
        asl     a
        tax
        lda     rs_tab,x                ; its line
        sta     ki5
        dec     a                       ; more than a line ahead: the interrupt one line before
        dec     a
        sta     ki6
        lda     f:NV_LINE               ; (the low byte first: it latches the high one)
        cmp     #360
        bcs     @stop
        cmp     ki6
        bcs     @near
        lda     ki5
        dec     a
        sta     f:NV_LINE_CMP
        rtl
@near:  lda     #400                    ; wait for the line to begin (at most two lines)
        sta     ki6
@w:     lda     f:NV_LINE
        cmp     ki5
        bcs     @due
        dec     ki6
        bne     @w
@due:   lda     rs_i                    ; its colour, in the horizontal blank
        asl     a
        adc     rs_i
        asl     a
        tax
        lda     rs_tab+3,x
        pha
        lda     rs_tab+5,x
        and     #$00FF
        tay
        lda     rs_tab+2,x
        plx
        jsr     pal_hw
        inc     rs_i
        bra     @next
@stop:  lda     #511                    ; (the split line was latched at line 0 already)
        sta     f:NV_LINE_CMP
        rtl

; ---- the window manager's hooks while the full screen is shown ----

; (wm_kbd, first) key kg_t, modifiers | down << 8 in kg_u -> A = 0: the window manager as
; usual, 1: taken, 2: the program's (the window manager does nothing with it)
        .export k2_fskey: far
k2_fskey:
        lda     fs_act
        bne     :+
        lda     #0
        rtl
:       lda     kg_t
        cmp     #$FF                    ; F12: out, then the backdrop shows the classic machine
        bne     :+
        jsr     fs_escape
        lda     #0
        rtl
:       lda     kg_u
        and     #KM_ALT2
        beq     @prog
        lda     kg_t
        cmp     #$3D                    ; Alt+F4: WE_CLOSE (the window manager)
        bne     :+
        lda     #0
        rtl
:       cmp     #$2B                    ; Alt+Tab, Alt+Esc: out (on the press)
        beq     :+
        cmp     #$29
        bne     @prog
:       lda     kg_u
        cmp     #$0100
        bcc     @took
        jsr     fs_escape
@took:  lda     #1
        rtl
@prog:  lda     #2
        rtl

; the full-screen window minimized: the desktop comes back (keeps kg_t, kg_u, kg_v)
fs_escape:
        lda     kg_t
        pha
        lda     kg_u
        pha
        lda     kg_v
        pha
        ldx     fs_w
        jsl     f_win_minimize
        jsr     fs_update
        jsr     pal_front
        pla
        sta     kg_v
        pla
        sta     kg_u
        pla
        sta     kg_t
        rts

; (classic_show, before the classic machine gets the screen) out of the full screen
        .export k2_classic: far
k2_classic:
        lda     fs_act
        beq     :+
        jsr     fs_escape
:       rtl

; (wm_button, after it took the change: wm_nbtn, wm_x, wm_y) C set: the full-screen window's
; (WE_BUTTON with the pointer on the screen; it holds the press while a button is down)
        .export k2_fsbtn: far
k2_fsbtn:
        lda     fs_act
        bne     :+
        clc
        rtl
:       jsr     fs_xy
        lda     #WE_BUTTON
        sta     kg_v
        lda     wm_nbtn
        sta     wm_btn
        ldx     #NONE
        and     #7
        beq     :+
        ldx     fs_w
:       stx     cap_w
        lda     wm_nbtn
        ora     ws_mods
        ldx     fs_w
        jsl     f_wev_push
        sec
        rtl

; the pointer (wm_x, wm_y) on the full screen -> kg_t, kg_u (halved in 320x180)
fs_xy:  lda     wm_x
        ldx     wm_y
        ldy     fs_mode
        cpy     #2
        bne     :+
        lsr     a
        pha
        txa
        lsr     a
        tax
        pla
:       sta     kg_t
        stx     kg_u
        rts

; (ws_thread, before the window manager's own pointer work) C set while the full screen is
; shown: a move goes to the window as WE_MOTION (coalesced) while a button is down or it has
; WF_HOVER
        .export k2_fsmove: far
k2_fsmove:
        lda     fs_act
        bne     :+
        clc
        rtl
:       lda     ms_x
        cmp     fs_lx
        bne     :+
        lda     ms_y
        cmp     fs_ly
        beq     @out
:       lda     ms_x
        sta     fs_lx
        sta     wm_x
        lda     ms_y
        sta     fs_ly
        sta     wm_y
        ldx     fs_w
        lda     wm_btn
        bne     :+
        lda     w_fl,x
        and     #64                     ; (WF_HOVER)
        beq     @out
:       jsr     fs_xy                   ; wm_motx subtracts the window's content origin: add it
        lda     kg_t
        clc
        adc     w_x,x
        clc
        adc     w_cx,x
        sta     wm_x
        lda     kg_u
        clc
        adc     w_y,x
        clc
        adc     w_cy,x
        sta     wm_y
        jsl     f_wm_motx
@out:   sec
        rtl

; (wm_wheel, first) C set: the steps (A) went to the full-screen window
        .export k2_fswheel: far
k2_fswheel:
        ldx     fs_act
        bne     :+
        clc
        rtl
:       sta     kg_t
        stz     kg_u
        lda     #WE_WHEEL
        sta     kg_v
        ldx     fs_w
        lda     #0
        jsl     f_wev_push
        sec
        rtl
