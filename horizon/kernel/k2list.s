; k2list.s - (0.18) draw lists: many blits in one call, run by Ali as one command list.
;
; draw_list takes records from the caller's memory, checks each one (its source must lie in
; the caller's memory: Ali reads RAM by itself), clips it to the target and turns it into one of
; Ali's 24-byte records in the window system's bank. The target is the window's content (on the
; screen itself while nothing lies over it and no repaint over it is pending, else its bitmap,
; which the compositor then shows: the per-call rule of win_draw), or the framebuffer of the
; window's full-screen mode (k2fs.s: all of its rows and its whole stride). Then, with command
; lists (REV $09) and the blitter in use, Ali runs them all with one LIST write and the call
; returns at once; a record may wait for the vertical blank first (tear-free updates). Without
; lists (REV $08) the kernel starts them one by one, without the blitter (REV $07) the CPU draws
; them; the result is the same.
; (0.19) The records go to SL_LIST ($7F:8400, kdefs.inc), in the console framebuffer's last bank
; past its 60 cell rows (kernel memory), so they are written with long,X stores; sheet_draw
; (k3.s, the third code segment) makes them there too and uses this file's routines through
; the far wrappers at its end.
;
; While the list runs, its sources are still being read and its target written: the program
; must leave them alone until list_wait says it is done (vsync and the next draw_list wait for
; it too, and list_wait also makes the CPU see what Ali wrote). A task's running list is
; stopped (Ali's ABORT) when the task ends or frees a bank; the window system's own blits wait
; for it as for any blit. A call may cover at most 460,800 pixels (two screens).

LS_FILL     = 0                 ; record ops
LS_COPY     = 1
LS_KEY      = 2
LS_EXPAND   = 3
LS_EXPANDK  = 4
LS_MOVE     = 5
LS_VBL      = 1                 ; record flags: wait for the vertical blank first
LS_MAX      = 128               ; records a call
LS_AREA     = 460800

        .segment "BSS"
ls_task:    .res    2           ; slot*2 + 1 of the task whose list Ali runs, 0 none
ls_n:       .res    2           ; records made
ls_o:       .res    2           ; (0.19) the next record's offset in SL_LIST (24 * ls_n)
sl_dirty:   .res    2           ; (0.19) records below this offset may have FLAGS / RFLAGS set
sl_init:    .res    2           ; (0.19) SL_LIST's bytes 18-23 were cleared once (k3.s)
ls_i:       .res    2           ; (the CPU and REV $08: the one running)
ls_cnt:     .res    2           ; records given
ls_vbl:     .res    2           ; a WAIT_VBL for the next record made
ls_area:    .res    4
ls_okb:     .res    2           ; a bank of the caller's checked in this call (0 none)
ls_k:       .res    2           ; the target's stride is 2^ls_k (K >= 8), else 0
ls_base:    .res    4           ; the target: row 0's address, bytes a row
ls_str:     .res    2
ls_ox:      .res    2           ; content -> target coordinates
ls_oy:      .res    2
ls_cx0:     .res    2           ; the clip (target coordinates, ends exclusive)
ls_cy0:     .res    2
ls_cx1:     .res    2
ls_cy1:     .res    2
ls_dmg:     .res    8           ; what was drawn (a bitmap: damage), x0 y0 x1 y1
ls_bmp:     .res    2           ; the target is the window's bitmap (damage at the end)
ls_vis:     .res    2           ; ... and nothing lies over its content (the list copies it)
ls_up:      .res    4           ; the caller's records (physical)
lr:         .res    20          ; the record being made
lr_x:       .res    2           ; clipped destination
lr_y:       .res    2
lr_w:       .res    2
lr_h:       .res    2
lr_sx:      .res    2           ; LS_MOVE: the source in target coordinates
lr_sy:      .res    2
lr_s:       .res    4           ; the source (physical)
lr_ss:      .res    2           ; its stride
lr_bit:     .res    2           ; EXPAND: its first bit (0 = bit 7)
lr_d:       .res    4           ; the destination's address

        .segment "K2CODE"

; ---- $9C draw_list(A = window | count << 8, X, Y = count records of 20 bytes) -> A = the
; records drawn (those clipped away are left out) ----
; Record: u8 op (0 fill, 1 copy, 2 keyed copy, 3 expand, 4 expand keyed, 5 move), u8 flags
; (bit 0 LS_VBL: wait for the vertical blank before this one; bits 4-6 expand: the first
; source bit, 0 = bit 7), u8 c1 (fill colour, expand ink), u8 c2 (copy key, expand paper), i16 x,
; i16 y, u16 w, u16 h (the destination), then for copy, keyed copy, expand: u24 source, u8 0,
; u16 source stride (0: the width; expand: the bytes a row needs), u16 0; for move: i16 sx, i16
; sy (the source rectangle in the same target), u16 0, u16 0, u16 0. Coordinates: the window's
; content, or the full-screen framebuffer (in bytes in 640x360x4). Errors (nothing drawn):
; EINVAL a bad window, op or count, more than 460,800 pixels; EFAULT the records or a source
; not wholly in the caller's memory.
k2_drawlist:
        jsr     ls_idle                 ; (blocks: before anything is kept in kx / kg)
        lda     ws_on
        bne     :+
@inv:   jmp     k2_inval
:       ldx     cur
        lda     t_a,x
        and     #$00FF
        jsl     f_win_arg
        bcs     @inv
        stx     kg_e
        ldx     cur
        lda     t_a+1,x
        and     #$00FF
        beq     @inv
        cmp     #LS_MAX + 1
        bcs     @inv
        sta     ls_cnt
        asl     a                       ; * 20
        asl     a
        adc     ls_cnt
        asl     a
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
        sta     ls_up
        lda     kphys+2
        and     #$00FF
        sta     ls_up+2
        jsr     ls_target
        jsr     ls_begin
        stz     ls_i
@rec:   lda     ls_i                    ; each record: copied, checked, clipped, made
        cmp     ls_cnt
        bcs     @made
        jsr     ls_one
        bcc     :+
        jmp     k2_err
:       inc     ls_i
        bra     @rec
@made:  jsr     ls_finish
        lda     ls_cnt
        jsl     f_set_ok
        rtl

; a call's start: no records, no WAIT_VBL pending, no area, no bank checked, no damage
ls_begin:
        stz     ls_n
        stz     ls_o
        stz     ls_vbl
        stz     ls_area
        stz     ls_area+2
        stz     ls_okb
        lda     #$7FFF                  ; (no damage yet)
        sta     ls_dmg
        sta     ls_dmg+2
        stz     ls_dmg+4                ; (clipped: never below 0)
        stz     ls_dmg+6
        rts

; the records made run (ls_n -> ls_cnt, the result): the damage first, then Ali's one list
; (REV $09+), its records started one by one (REV $08), or the CPU
ls_finish:
        lda     ls_n
        sta     ls_cnt                  ; (the result: records drawn, not the copy below)
        beq     @done
        jsr     ls_damage
        lda     k_rev                   ; run them
        cmp     #$09
        bcc     @noli
        lda     bl_on
        beq     @cpu
        jsl     f_bl_wait               ; (win_target may have started a blit)
        a8                              ; one list
        lda     #<SL_LIST
        sta     f:BL_LIST
        lda     #>SL_LIST
        sta     f:BL_LIST+1
        lda     #^SL_LIST
        sta     f:BL_LIST+2
        a16
        lda     ls_n
        sta     f:BL_COUNT
        lda     cur
        inc     a
        sta     ls_task
        a8
        lda     #4 | 2                  ; LIST, IRQ_EN: the BLITTER interrupt at its end
        sta     f:BL_CTRL
        a16
        rts
@noli:  lda     bl_on
        beq     @cpu
        jmp     ls_single
@cpu:   jmp     ls_cpu
@done:  rts

; ---- $9D list_wait(A = 0 wait, 1 ask) -> A = 1 while a list of the caller still runs ----
; Waiting also makes the CPU see what Ali wrote (CACHE_FLUSH).
k2_listwait:
        ldx     cur
        lda     t_a,x
        beq     @wait
        lda     ls_task
        beq     @no
        dec     a
        cmp     cur
        bne     @no
        a8
        lda     f:BL_CTRL
        lsr     a
        a16
        bcc     @end
        lda     #1
        jsl     f_set_ok
        rtl
@end:   stz     ls_task
        jsl     f_bl_flush
@no:    jmp     k2_ok0
@wait:  jsr     ls_idle
        jsl     f_bl_flush
        jmp     k2_ok0

; (vsync, after the blank) the caller's list done first, and seen by the CPU
        .export k2_lwait: far
k2_lwait:
        lda     ls_task
        beq     @out
        dec     a
        cmp     cur
        bne     @out
        jsr     ls_idle
        jsl     f_bl_flush
@out:   rtl

; until Ali is idle: a list (whose end interrupts) blocks the caller, a single blit is waited for
ls_idle:
        a8
        lda     f:BL_CTRL
        a16
        and     #$00FF
        bit     #1
        beq     @done
        bit     #4                      ; LIST
        beq     @spin
        ldx     cur
        lda     t_killed,x
        bne     @spin
        lda     #W_BLIT
        ldy     #0
        jsl     f_k_block
        bra     ls_idle
@spin:  jsl     f_bl_wait
@done:  stz     ls_task
        rts

; (the task ends, frees a bank) its running list stopped
ls_stop:
        lda     ls_task
        beq     @out
        dec     a
        cmp     cur
        bne     @out
        a8
        lda     f:BL_CTRL
        and     #4 | 1
        cmp     #4 | 1
        bne     :+
        lda     #8                      ; ABORT (BUSY drops within a few cycles)
        sta     f:BL_CTRL
:       a16
        jsl     f_bl_wait
        stz     ls_task
@out:   rts

; the target of window kg_e: its full-screen framebuffer, or its content where win_target puts
; it (the screen or its bitmap) -> ls_base, ls_str, ls_ox, ls_oy, the clip, ls_bmp
ls_target:
        stz     ls_bmp
        lda     fs_on
        beq     @win
        lda     kg_e
        cmp     fs_w
        bne     @win
        lda     fs_base
        sta     ls_base
        lda     fs_base+2
        sta     ls_base+2
        lda     fs_stride
        sta     ls_str
        sta     ls_cx1
        lda     fs_rows
        sta     ls_cy1
        stz     ls_ox
        stz     ls_oy
        stz     ls_cx0
        stz     ls_cy0
        stz     ls_k
        rts
@win:   stz     ls_vis
        jsl     f_win_target            ; kg_sf, the clip (kg_cx0 ..), wo_x, wo_y, wo_dir
        lda     wo_dir
        eor     #1
        sta     ls_bmp
        ldx     kg_e
        lda     w_cx,x
        clc
        adc     wo_x
        sta     ls_ox
        lda     w_cy,x
        clc
        adc     wo_y
        sta     ls_oy
        lda     kg_cx0
        sta     ls_cx0
        lda     kg_cy0
        sta     ls_cy0
        lda     kg_cx1
        sta     ls_cx1
        lda     kg_cy1
        sta     ls_cy1
        ldx     kg_sf                   ; the surface: +4 K (stride 2^K), +8 its first bank
        lda     a:8,x
        and     #$00FF
        sta     ls_base+2
        stz     ls_base
        ldy     a:4,x
        lda     #1
:       asl     a
        dey
        bne     :-
        sta     ls_str
        lda     a:4,x                   ; K - 7 for ls_emit (K is 8 or more for every surface)
        sec
        sbc     #7
        bpl     :+
        lda     #0
:       sta     ls_k
        lda     ls_bmp                  ; (0.19: only for a bitmap, after win_target, which
        beq     :+                      ; asked it too) nothing over its content? (a repaint
        ldx     kg_e                    ; is pending: the list copies what it drew)
        jsl     f_win_visible           ; (it sets kg_cx0 .., already taken)
        bcc     :+
        inc     ls_vis
:       rts

; record ls_i: copied, checked, clipped, made into Ali's record ls_n. C set: A = the error
ls_one: lda     ls_i                    ; copy it (20 bytes)
        asl     a
        asl     a
        adc     ls_i
        asl     a
        asl     a
        clc
        adc     ls_up
        sta     kp1
        lda     ls_up+2
        adc     #0
        sta     kp1+2
        ldy     #18
:       lda     [kp1],y
        sta     lr,y
        dey
        dey
        bpl     :-
        lda     lr                      ; op
        and     #$00FF
        cmp     #LS_MOVE + 1
        bcc     :+
        jmp     @inv
:       lda     lr+1                    ; WAIT_VBL carries over to the next record made
        and     #LS_VBL
        tsb     ls_vbl
        lda     lr+4                    ; the destination in target coordinates
        clc
        adc     ls_ox
        sta     lr_x
        lda     lr+6
        clc
        adc     ls_oy
        sta     lr_y
        lda     lr+8
        cmp     #4097
        bcs     :+
        sta     lr_w
        lda     lr+10
        cmp     #4097
        bcs     :+
        sta     lr_h
        lda     lr                      ; the source checked (all of it, before clipping)
        and     #$00FF
        beq     @clip                   ; (fill)
        cmp     #LS_MOVE
        beq     @move
        jsr     ls_src
        bcc     @clip
        lda     #EFAULT
        sec
        rts
:       clc                             ; (an empty or huge rectangle: left out; sources of an
        rts                             ; empty one are not read)
@move:  lda     lr+12
        clc
        adc     ls_ox
        sta     lr_sx
        lda     lr+14
        clc
        adc     ls_oy
        sta     lr_sy
        jsr     ls_mclip
        bcc     @make
        clc
        rts
@clip:  lda     lr_w
        beq     :-
        lda     lr_h
        beq     :-
        jsr     ls_clip
        bcc     @make
        clc
        rts
@make:  lda     lr_w                    ; the area: at most LS_AREA in all (up to 16 x 16
        ora     lr_h                    ; counted as 256)
        cmp     #17
        bcs     :+
        lda     #256
        ldx     #0
        bra     @add
:       lda     lr_w
        ldx     lr_h
        jsr     mul16
@add:   clc
        adc     ls_area
        sta     ls_area
        txa
        adc     ls_area+2
        sta     ls_area+2
        cmp     #^LS_AREA
        bcc     :+
        bne     @inv
        lda     ls_area
        cmp     #.loword(LS_AREA) + 1
        bcs     @inv
:       jsr     ls_emit
        clc
        rts
@inv:   lda     #EINVAL
        sec
        rts

; copy, keyed copy, expand: the source range (stride * (h - 1) + a row) must be the caller's
; -> lr_s (physical), lr_ss, lr_bit. C set: EFAULT.
ls_src: lda     lr+1                    ; expand: the first bit, a row's bytes
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        and     #7
        sta     lr_bit
        lda     lr
        and     #$00FF
        sta     kx2
        lda     lr_w                    ; a row: w bytes (expand: (bit + w + 7) / 8)
        ldx     kx2
        cpx     #LS_EXPAND
        bcc     :+
        clc
        adc     lr_bit
        adc     #7
        lsr     a
        lsr     a
        lsr     a
:       sta     kx0
        lda     lr+16                   ; the stride (0: a row)
        bne     :+
        lda     kx0
:       sta     lr_ss
        lda     lr+14                   ; the fast way: a bank of the caller's already checked in
        and     #$00FF                  ; this call, and stride * 16 + offset inside it (a
        beq     @full                   ; source of up to 16 rows)
        cmp     ls_okb
        bne     @full
        lda     lr_h
        cmp     #17
        bcs     @full
        lda     lr_ss
        cmp     #4096
        bcs     @full
        asl     a
        asl     a
        asl     a
        asl     a
        clc
        adc     lr+12
        bcc     @fast
        bne     @full                   ; (exactly $10000 is still inside)
@fast:  lda     lr+12
        sta     lr_s
        lda     ls_okb
        sta     lr_s+2
        clc
        rts
@full:  lda     lr_h
        dec     a
        ldx     lr_ss
        jsr     mul16                   ; stride * (h - 1) + a row
        clc
        adc     kx0
        sta     kt2
        txa
        adc     #0
        sta     kt3
        lda     lr+12
        sta     kt0
        lda     lr+14
        and     #$00FF
        sta     kt1
        jsr     hw_range
        bcs     @out
        lda     kt1                     ; a whole bank of the caller's: remembered
        beq     :+
        lda     hr_b0
        cmp     hr_b1
        bne     :+
        sta     ls_okb
:       lda     kphys
        sta     lr_s
        lda     kphys+2
        and     #$00FF
        sta     lr_s+2
        clc
@out:   rts

; the destination lr_x, lr_y, lr_w, lr_h cut to the clip; the source moved by the cut. C set:
; nothing left.
ls_clip:
        lda     ls_cx0                  ; left
        sec
        sbc     lr_x
        bmi     :+
        beq     :+
        jsr     @cutx
        bcs     @none
:       lda     ls_cy0                  ; top
        sec
        sbc     lr_y
        bmi     :+
        beq     :+
        jsr     @cuty
        bcs     @none
:       lda     lr_x                    ; right
        clc
        adc     lr_w
        sec
        sbc     ls_cx1
        bmi     :+
        beq     :+
        eor     #$FFFF
        sec
        adc     lr_w
        bmi     @none
        beq     @none
        sta     lr_w
:       lda     lr_y                    ; bottom
        clc
        adc     lr_h
        sec
        sbc     ls_cy1
        bmi     :+
        beq     :+
        eor     #$FFFF
        sec
        adc     lr_h
        bmi     @none
        beq     @none
        sta     lr_h
:       clc
        rts
@none:  sec
        rts
@cutx:  sta     kx1                     ; cut A columns on the left
        cmp     lr_w
        bcs     @cn
        clc
        adc     lr_x
        sta     lr_x
        lda     lr_w
        sec
        sbc     kx1
        sta     lr_w
        lda     lr
        and     #$00FF
        cmp     #LS_EXPAND
        bcc     :+
        lda     lr_bit                  ; expand: bits
        clc
        adc     kx1
        pha
        lsr     a
        lsr     a
        lsr     a
        jsr     @sadd
        pla
        and     #7
        sta     lr_bit
        clc
        rts
:       lda     kx1                     ; bytes
        jsr     @sadd
        clc
        rts
@cuty:  sta     kx1                     ; cut A rows at the top
        cmp     lr_h
        bcs     @cn
        clc
        adc     lr_y
        sta     lr_y
        lda     lr_h
        sec
        sbc     kx1
        sta     lr_h
        lda     kx1
        ldx     lr_ss
        jsr     mul16
        jsr     @sadd
        txa
        clc
        adc     lr_s+2
        sta     lr_s+2
        clc
        rts
@cn:    sec
        rts
@sadd:  clc                             ; lr_s += A
        adc     lr_s
        sta     lr_s
        bcc     :+
        inc     lr_s+2
:       rts

; move: source lr_sx, lr_sy and destination lr_x, lr_y (w, h) both cut to the clip, by the
; same amounts. C set: nothing left.
ls_mclip:
        lda     lr_w
        beq     @none
        lda     lr_h
        beq     @none
        ldx     #0                      ; x (offset 0), then y (offset 2): left / top cut
@two:   lda     ls_cx0,x
        sec
        sbc     lr_x,x
        sta     kx1
        lda     ls_cx0,x
        sec
        sbc     lr_sx,x
        cmp     kx1
        bmi     :+
        sta     kx1
:       lda     kx1
        bmi     @far
        beq     @far
        cmp     lr_w,x
        bcs     @none
        clc
        adc     lr_x,x
        sta     lr_x,x
        lda     lr_sx,x
        clc
        adc     kx1
        sta     lr_sx,x
        lda     lr_w,x
        sec
        sbc     kx1
        sta     lr_w,x
@far:   lda     lr_x,x                  ; right / bottom
        clc
        adc     lr_w,x
        sec
        sbc     ls_cx1,x
        sta     kx1
        lda     lr_sx,x
        clc
        adc     lr_w,x
        sec
        sbc     ls_cx1,x
        cmp     kx1
        bmi     :+
        sta     kx1
:       lda     kx1
        bmi     @nx
        beq     @nx
        cmp     lr_w,x
        bcs     @none
        lda     lr_w,x
        sec
        sbc     kx1
        sta     lr_w,x
@nx:    inx
        inx
        cpx     #4
        bcc     @two
        clc
        rts
@none:  sec
        rts

; Ali's record at SL_LIST + ls_o from lr_* (ls_o += 24, ls_n += 1); on a bitmap target the
; drawn rectangle joins ls_dmg. (0.19) Long,X stores; a record whose FLAGS or RFLAGS is not 0
; raises sl_dirty (sheet_draw's fast path leaves those bytes alone: k3.s, sl_clean).
ls_emit:
        lda     lr_y                    ; the destination: base + y * stride + x
        jsr     ls_rowad
        clc
        adc     lr_x
        bcc     :+
        inx
:       clc
        adc     ls_base
        sta     lr_d
        txa
        adc     ls_base+2
        sta     lr_d+2
        lda     lr                      ; op
        and     #$00FF
        sta     kx1
        cmp     #LS_MOVE
        bne     @nm
        lda     lr_sy                   ; move: the source in the target too
        jsr     ls_rowad
        clc
        adc     lr_sx
        bcc     :+
        inx
:       clc
        adc     ls_base
        sta     lr_s
        txa
        adc     ls_base+2
        sta     lr_s+2
        lda     ls_str
        sta     lr_ss
@nm:    stz     kx2                     ; FLAGS
        ldx     kx1
        cpx     #LS_EXPAND
        bcc     @fl
        cpx     #LS_MOVE
        bcs     @mv
        lda     #7                      ; SRC_BIT: 7 = the leftmost
        sec
        sbc     lr_bit
        asl     a
        asl     a
        asl     a
        asl     a
        sta     kx2
        bra     @fl
@mv:    lda     lr_d+2                  ; move: BACKWARDS when the destination lies after it
        cmp     lr_s+2
        bne     :+
        lda     lr_d
        cmp     lr_s
:       lda     #0
        rol     a
        sta     kx2
@fl:    lda     f:ls_ops,x              ; Ali's OP | FLAGS << 8
        and     #$00FF
        sta     kx1
        lda     kx2
        xba
        ora     kx1
        sta     kx1
        ldx     ls_o
        lda     lr_s                    ; 0-2 SRC, 3-4 SRC_STRIDE (each store's high byte is
        sta     f:SL_LIST,x             ; written again by the next one)
        lda     lr_s+2
        sta     f:SL_LIST+2,x
        lda     lr_ss
        sta     f:SL_LIST+3,x
        lda     lr_d                    ; 5-7 DST, 8-9 DST_STRIDE
        sta     f:SL_LIST+5,x
        lda     lr_d+2
        sta     f:SL_LIST+7,x
        lda     ls_str
        sta     f:SL_LIST+8,x
        lda     lr_w                    ; 10-11 WIDTH, 12-13 HEIGHT
        sta     f:SL_LIST+10,x
        lda     lr_h
        sta     f:SL_LIST+12,x
        lda     lr+2                    ; 14 FG, 15 BG (c1, c2), 16 KEY (c2)
        sta     f:SL_LIST+14,x
        lda     lr+3
        sta     f:SL_LIST+16,x
        lda     kx1                     ; 17 OP, 18 FLAGS
        sta     f:SL_LIST+17,x
        lda     ls_vbl                  ; 19 RFLAGS (WAIT_VBL), 20-23 0
        sta     f:SL_LIST+19,x
        lda     #0
        sta     f:SL_LIST+21,x
        sta     f:SL_LIST+22,x
        txa
        clc
        adc     #24
        sta     ls_o
        lda     kx1                     ; FLAGS or RFLAGS set: sheet_draw clears them first
        and     #$FF00
        ora     ls_vbl
        beq     :+
        lda     ls_o
        cmp     sl_dirty
        bcc     :+
        sta     sl_dirty
:       stz     ls_vbl
        inc     ls_n
        lda     ls_bmp                  ; the damage (a bitmap target): the union
        beq     @out
        lda     lr_x
        cmp     ls_dmg
        bpl     :+
        sta     ls_dmg
:       lda     lr_y
        cmp     ls_dmg+2
        bpl     :+
        sta     ls_dmg+2
:       lda     lr_x
        clc
        adc     lr_w
        cmp     ls_dmg+4
        bmi     :+
        sta     ls_dmg+4
:       lda     lr_y
        clc
        adc     lr_h
        cmp     ls_dmg+6
        bmi     @out
        sta     ls_dmg+6
@out:   rts

; A = row y of the target -> y * ls_str (A low, X high): shifts for a stride of 2^K (K >= 8:
; ls_k = K - 7), else mul16
ls_rowad:
        ldy     ls_k
        beq     @mul
:       dey
        beq     :+
        asl     a
        bra     :-
:       pha                             ; y << (K - 8): its high byte is the high word
        xba
        and     #$00FF
        tax
        pla
        xba
        and     #$FF00
        rts
@mul:   ldx     ls_str
        jmp     mul16

ls_ops: .byte   0, 1, 2, 3, 4, 1        ; Ali's OP: FILL, COPY, COPY_KEY, EXPAND, EXPAND_KEY, COPY

; drawn into the window's bitmap: the union repainted (on the screen, unless minimized). While
; nothing lies over the window, the list itself copies the union to the screen (one more
; record): no repaint queued, so the next frame's list can draw on the screen again (a queued
; repaint over it would send that one to the bitmap too, frame after frame)
ls_damage:
        lda     ls_bmp
        jeq     @out
        ldx     kg_e
        lda     w_st,x
        and     #1
        jne     @out
        lda     ls_vis
        jeq     @dmg
        lda     ls_dmg+4                ; anything drawn?
        cmp     ls_dmg
        jmi     @out
        jeq     @out
        lda     ls_dmg+2                ; the source: the bitmap at the union
        jsr     ls_rowad
        clc
        adc     ls_dmg
        bcc     :+
        inx
:       clc
        adc     ls_base
        sta     lr_s
        txa
        adc     ls_base+2
        sta     lr_s+2
        lda     ls_str
        sta     lr_ss
        ldx     kg_e                    ; the destination: the same place on the screen
        lda     ls_dmg
        clc
        adc     w_x,x
        sta     lr_x
        lda     ls_dmg+2
        clc
        adc     w_y,x
        sta     lr_y
        lda     ls_dmg+4
        sec
        sbc     ls_dmg
        sta     lr_w
        lda     ls_dmg+6
        sec
        sbc     ls_dmg+2
        sta     lr_h
        lda     ws_scr+8                ; the screen: its first bank, stride 2^K
        and     #$00FF
        sta     ls_base+2
        stz     ls_base
        ldy     ws_scr+4
        lda     #1
:       asl     a
        dey
        bne     :-
        sta     ls_str
        lda     ws_scr+4
        sec
        sbc     #7
        sta     ls_k
        lda     #LS_COPY
        sta     lr
        jmp     ls_emit
@dmg:
        lda     ls_dmg
        clc
        adc     w_x,x
        sta     kg_x
        lda     ls_dmg+2
        clc
        adc     w_y,x
        sta     kg_y
        lda     ls_dmg+4
        sec
        sbc     ls_dmg
        sta     kg_w
        lda     ls_dmg+6
        sec
        sbc     ls_dmg+2
        sta     kg_h
        jsl     f_damage
@out:   rts

; REV $08: the records started one by one (each waits for the one before; a WAIT_VBL record
; for the vertical blank); the last is left running
ls_single:
        stz     ls_i
@r:     lda     ls_i
        cmp     ls_n
        bcs     @out
        jsr     ls_recp
        jsl     f_bl_wait
        ldy     #19
        lda     [kp0],y
        lsr     a
        bcc     :+
        jsr     ls_vwait
        jsr     ls_recp
:       ldy     #0
        ldx     #0
:       lda     [kp0],y
        sta     f:BL_SRC,x
        iny
        iny
        inx
        inx
        cpx     #18
        bcc     :-
        a8
        lda     [kp0],y                 ; (byte 18: FLAGS)
        sta     f:BL_SRC+18
        lda     #1
        sta     f:BL_CTRL
        a16
        inc     ls_i
        bra     @r
@out:   rts

; kp0 -> record ls_i
ls_recp:
        lda     ls_i
        asl     a
        adc     ls_i
        asl     a
        asl     a
        asl     a
        adc     #.loword(SL_LIST)
        sta     kp0
        lda     #^SL_LIST
        sta     kp0+2
        rts

; until the next vertical blank (blocks; kp0 and the DP temporaries are lost)
ls_vwait:
        lda     vs_frame
        sta     ls_area
        jsl     f_vs_arm
@w:     ldx     cur
        lda     t_killed,x
        bne     @out
        lda     vs_frame
        cmp     ls_area
        bne     @out
        lda     #W_VSYNC
        ldy     #0
        jsl     f_k_block
        bra     @w
@out:   rts

; REV $07 (or the blitter turned off): the CPU runs the records, as Ali would
ls_cpu: jsl     f_bl_flush
        stz     ls_i
@r:     lda     ls_i
        cmp     ls_n
        bcs     @out
        jsr     ls_recp
        ldy     #19
        lda     [kp0],y
        lsr     a
        bcc     :+
        jsr     ls_vwait
        jsr     ls_recp
:       jsr     cpu_blit
        inc     ls_i
        bra     @r
@out:   rts

; one of Ali's records at kp0, by the CPU: kg_s source, kg_p destination, line by line
cpu_blit:
        ldy     #0
        lda     [kp0],y
        sta     kg_s
        ldy     #2
        lda     [kp0],y
        and     #$00FF
        sta     kg_s+2
        ldy     #3
        lda     [kp0],y
        sta     lr_ss
        ldy     #5
        lda     [kp0],y
        sta     kg_p
        ldy     #7
        lda     [kp0],y
        and     #$00FF
        sta     kg_p+2
        ldy     #8
        lda     [kp0],y
        sta     ls_str
        ldy     #10
        lda     [kp0],y
        sta     lr_w
        ldy     #12
        lda     [kp0],y
        sta     lr_h
        ldy     #14
        lda     [kp0],y
        sta     kx0                     ; FG | BG << 8
        ldy     #16
        lda     [kp0],y
        sta     kx1                     ; KEY | OP << 8
        ldy     #18
        lda     [kp0],y
        and     #$00FF
        sta     kx2                     ; FLAGS
        lsr     a
        bcc     @line
        lda     lr_h                    ; BACKWARDS: from the last line, right to left
        dec     a
        pha
        ldx     lr_ss
        jsr     mul16
        jsr     @sadd
        pla
        ldx     ls_str
        jsr     mul16
        clc
        adc     kg_p
        sta     kg_p
        txa
        adc     kg_p+2
        sta     kg_p+2
@line:  lda     kx1+1
        and     #$00FF
        sta     kx3                     ; op
        lda     kx2
        lsr     a
        bcs     @back
        ldy     #0
        ldx     kx3
        beq     @fill
        cpx     #3
        bcs     @exp
        a8
@cp:    lda     [kg_s],y                ; copy, keyed copy
        cpx     #2
        bne     :+
        cmp     kx1
        beq     @cn
:       sta     [kg_p],y
@cn:    iny
        cpy     lr_w
        bne     @cp
        a16
        bra     @next
@fill:  a8
        lda     kx0
:       sta     [kg_p],y
        iny
        cpy     lr_w
        bne     :-
        a16
        bra     @next
@back:  ldy     lr_w                    ; move backwards: right to left
        a8
:       dey
        lda     [kg_s],y
        sta     [kg_p],y
        cpy     #0
        bne     :-
        a16
        bra     @next
@exp:   lda     kx2                     ; expand: SRC_BIT (7 = bit 7) -> a mask
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        and     #7
        tax
        lda     f:@bits,x
        and     #$00FF
        sta     kx4                     ; the bit
        stz     kx5                     ; the source byte offset
        ldy     #0
@px:    phy
        ldy     kx5
        lda     [kg_s],y
        ply
        and     kx4
        a8
        beq     @zero
        lda     kx0
        sta     [kg_p],y
        bra     @nb
@zero:  lda     kx3
        cmp     #4                      ; EXPAND_KEY: 0 bits leave it
        beq     @nb
        lda     kx0+1
        sta     [kg_p],y
@nb:    a16
        lsr     kx4
        bcc     :+
        lda     #$80
        sta     kx4
        inc     kx5
:       iny
        cpy     lr_w
        bne     @px
@next:  lda     kx2                     ; the next line (up when backwards)
        lsr     a
        bcs     @up
        lda     lr_ss
        clc
        adc     kg_s
        sta     kg_s
        bcc     :+
        inc     kg_s+2
:       lda     ls_str
        clc
        adc     kg_p
        sta     kg_p
        bcc     :+
        inc     kg_p+2
        bra     :+
@up:    lda     kg_s
        sec
        sbc     lr_ss
        sta     kg_s
        bcs     *+4
        dec     kg_s+2
        lda     kg_p
        sec
        sbc     ls_str
        sta     kg_p
        bcs     :+
        dec     kg_p+2
:       lda     lr_h
        and     #7
        bne     :+
        jsl     f_irq_poll              ; (interrupts every 8 lines)
:       dec     lr_h
        beq     :+
        jmp     @line
:       rts
@sadd:  clc
        adc     kg_s
        sta     kg_s
        txa
        adc     kg_s+2
        sta     kg_s+2
        rts
@bits:  .byte   1, 2, 4, 8, 16, 32, 64, 128

; ---- (0.19) for the third code segment (k3.s, sheet_draw): this file's routines as JSL / RTL
; wrappers (k3.s runs from bank $7F, so it cannot JSR here), and the variables it uses
        .export f2_idle: far, f2_stop: far, f2_setup: far, f2_clip: far, f2_emit: far
        .export f2_finish: far, f2_range: far, f2_mul: far
        .export ls_n, ls_o, ls_cnt, ls_vbl, ls_bmp, ls_base, ls_str, ls_ox, ls_oy
        .export ls_cx0, ls_cy0, ls_cx1, ls_cy1, lr, lr_x, lr_y, lr_w, lr_h, lr_s, lr_ss, lr_bit
        .export sl_dirty, sl_init, hr_b0, hr_b1
f2_idle:    jsr     ls_idle             ; until Ali is idle (blocks)
            rtl
f2_stop:    jsr     ls_stop             ; the caller's running list stopped
            rtl
f2_setup:   jsr     ls_target           ; the target of window kg_e, a call's start
            jsr     ls_begin
            rtl
f2_clip:    jsr     ls_clip             ; lr_x .. cut to the clip (C set: nothing left)
            rtl
f2_emit:    jsr     ls_emit             ; Ali's record at ls_o
            rtl
f2_finish:  jsr     ls_finish           ; the records run -> ls_cnt
            rtl
f2_range:   jsr     hw_range            ; a range the caller owns (C set: no)
            rtl
f2_mul:     jsr     mul16               ; A * X -> A low, X high
            rtl
