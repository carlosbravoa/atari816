; k3.s - (0.19) the kernel's third code segment, run from bank $7F $E000-$EFFF (kernel.cfg):
; sheets, cheap queued drawing from art a program registered once.
;
; Its own assembly unit, like k2.s: bank $01 reaches it with JSL (syscall.s's sys_k3, k2.s's
; hooks), and it reaches bank $01 only through kfar.s's wrappers and k2.s only through the f2_*
; wrappers at the end of k2list.s. The usual kernel conventions hold (a16 i16, D = KDP, DBR =
; $01); the bank $01 variables are read as always, the tables of this unit in bank 0 (K0BSS)
; and in bank $7F with long addressing. The fast loop of sheet_draw runs with DBR = the bank of
; the caller's records and reaches bank $01 with long addressing there.
;
; A sheet is a rectangle of the program's own memory holding 8 bpp art: {address, stride,
; width, height}. sheet_new checks it once (the rule of every address Ali reads: the caller's
; window, code bank or banks it allocated, across consecutive banks it owns; never the kernel's,
; another program's or a shared bank), keeps the physical address of each of its rows in a row
; table (SROW_LO / SROW_HI: 4096 rows for all sheets) and gives a handle. sheet_draw's records
; then name a sheet and a rectangle in it: the kernel only checks small numbers against the
; sheet's size, and the source address is the row table's entry + sx.
;
; sheet_draw makes Ali's records in SL_LIST (as draw_list does, k2list.s) and runs them the same
; way. The fast path: the target is drawn directly (the window's content on the screen while
; nothing lies over it and no repaint over it is pending, or the full-screen framebuffer), the
; record is a copy or a keyed copy of the sheet seen in the record before (the sheet and op are
; checked when they change), and it lies wholly inside the clip: then its destination is the
; target's row table (DROW_LO / DROW_HI, made again only when the target moved) + x, and only the
; changing bytes of Ali's record are written (FLAGS, RFLAGS and 20-23 stay 0: sl_clean). Every
; other record (fills, LS_VBL, clipping, a bitmap target) goes through sh_one: checked in full,
; clipped and made by k2list.s's ls_clip and ls_emit.
;
; Bank $7F, past the console's 60 cell rows ($7F:8400) and below the pointer images ($7F:F000):
;   $8400-$8FFF  SL_LIST: Ali's records (128 x 24), draw_list's and sheet_draw's
;   $9000-$9FFF  DROW_LO / DROW_HI: the fast path's rows of the target (1024)
;   $A000-$DFFF  SROW_LO / SROW_HI: the sheets' rows (4096)
;   $E000-$EFFF  this code
        .p816
        .smart  -
        .feature string_escapes

        .include "hw.inc"
        .include "kdefs.inc"

        .import f_set_ok: far, f_set_err: far, f_win_arg: far, f_uaccess: far
        .import t_a, t_x, t_y, ws_on
        .import f2_idle: far, f2_stop: far, f2_setup: far, f2_clip: far, f2_emit: far
        .import f2_finish: far, f2_range: far, f2_mul: far
        .import ls_n, ls_o, ls_cnt, ls_vbl, ls_bmp, ls_base, ls_str, ls_ox, ls_oy
        .import ls_cx0, ls_cy0, ls_cx1, ls_cy1, lr, lr_x, lr_y, lr_w, lr_h, lr_s, lr_ss, lr_bit
        .import sl_dirty, sl_init, hr_b0, hr_b1

SH_N        = 32                ; sheets (system-wide; each one the program's that made it)
SR_N        = 4096              ; rows of all sheets
DR_N        = 1024              ; rows of a target (the full screen's most)
SROW_LO     = $7FA000           ; the sheets' rows: address bits 0-15
SROW_HI     = $7FC000           ;   bits 16-23
DROW_LO     = $7F9000           ; the target's rows from the clip's corner
DROW_HI     = $7F9800
SH_FILL     = 0                 ; record ops (the same numbers as LS_FILL, LS_COPY, LS_KEY)
SH_COPY     = 1
SH_KEY      = 2
SH_VBL      = $80               ; + wait for the vertical blank first
LS_MAX      = 128
LS_AREA     = 460800
LS_VBL      = 1

; direct page: the window system's gfx temporaries (kg_*, $90-$C9; kg_e $C2 is kept), free
; while a syscall runs here; ls_clip / ls_emit / mul16 use only kx1, kx2, kt4-kt7
kps     = $90                   ; -> SROW_LO of the sheet seen last (24 bits)
kpsh    = $94                   ; -> its SROW_HI
kpd     = $98                   ; -> DROW_LO
kpdh    = $9C                   ; -> DROW_HI
sc_hop  = $A0                   ; the sheet seen last: its record word 0 (sheet | op << 8)
sc_op   = $A2                   ;   Ali's OP << 8
sc_w1   = $A4                   ;   width + 1 (0: no sheet: every record to sh_one)
sc_h1   = $A6                   ;   height + 1
sc_ss   = $A8                   ;   stride
c_ox    = $AA                   ; content -> clip coordinates
c_oy    = $AC
c_cw1   = $AE                   ; the clip's width + 1, height + 1
c_ch1   = $B0
c_ds    = $B2                   ; the target's stride
k_w     = $B4                   ; the record: w, h, x (clip coordinates), sx, sy
k_h     = $B6
k_x     = $B8
k_sx    = $BA
k_sy    = $BC
k_i     = $BE                   ; the record's offset in its bank
k_il    = $C0                   ; the last record's
k3b     = $C4                   ; the records' bank
kg_e    = $C2                   ; (ws.s) the window
kx0     = $E0                   ; (k2.s) a temporary

        .segment "BSS"
sr:         .res    16          ; a record (sh_one), sheet_new's block
sh_big:     .res    4           ; sheet_draw: pixels of the records beyond 16 x 16
sh_nbig:    .res    2           ;   their number
sh_skip:    .res    2           ;   records left out (empty, clipped away)
sh_rows:    .res    2           ; rows of SROW in use
sh_t:       .res    2
dr_b:       .res    4           ; DROW: the clip's corner, the stride, the rows made
dr_s:       .res    2
dr_n:       .res    2

        .segment "K0BSS": far
sh_own:     .res    SH_N * 2    ; slot*2 + 1 of the owner, 0 = free
sh_w:       .res    SH_N * 2
sh_h:       .res    SH_N * 2
sh_ss:      .res    SH_N * 2    ; stride
sh_row:     .res    SH_N * 2    ; its first row in SROW (* 2)
sh_b0:      .res    SH_N * 2    ; the banks it lies in (physical, first, last)
sh_b1:      .res    SH_N * 2

        .segment "K3CODE"
        .a16
        .i16

; syscalls K3_SYS0 ..: syscall.s's sys_k3 comes here with X = number * 2
        .export k3_sys: far
k3_sys: jmp     (.loword(k3_tab) - K3_SYS0 * 2,x)
k3_tab: .word   .loword(k3_new), .loword(k3_free), .loword(k3_draw)    ; $A1
        .assert (* - k3_tab) / 2 + K3_SYS0 = K3_NSYS, error, "k3_tab: one entry per syscall"

k3_ok0: lda     #0
        jsl     f_set_ok
        rtl
k3_inval:
        lda     #EINVAL
        bra     k3_err
k3_again:
        lda     #EAGAIN
        bra     k3_err
k3_fault:
        lda     #EFAULT
k3_err: jsl     f_set_err
        rtl

; ---- $A1 sheet_new(X, Y = {u24 address, u8 0, u16 stride, u16 width, u16 height}) -> A = the
; sheet (1-32) ----
; Width 1-4096, height 1-1024, stride >= width: else EINVAL. stride * (height - 1) + width bytes
; from the address must be the caller's own memory: else EFAULT. EAGAIN: 32 sheets exist, or
; their rows would pass 4096.
k3_new: ldx     cur
        lda     t_x,x
        sta     kt0
        lda     t_y,x
        sta     kt1
        lda     #10
        sta     kt2
        stz     kt3
        jsl     f_uaccess
        bcc     :+
        jmp     k3_fault
:       ldy     #8
:       lda     [kphys],y
        sta     sr,y
        dey
        dey
        bpl     :-
        bra     :+
@inv:   jmp     k3_inval
:       lda     sr+6                    ; width 1-4096
        beq     @inv
        cmp     #4097
        bcs     @inv
        lda     sr+8                    ; height 1-1024
        beq     @inv
        cmp     #DR_N + 1
        bcs     @inv
        lda     sr+4                    ; stride >= width
        cmp     sr+6
        bcc     @inv
        lda     sr+8                    ; the range: stride * (height - 1) + width
        dec     a
        ldx     sr+4
        jsl     f2_mul
        clc
        adc     sr+6
        sta     kt2
        txa
        adc     #0
        sta     kt3
        lda     sr
        sta     kt0
        lda     sr+2
        and     #$00FF
        sta     kt1
        jsl     f2_range                ; -> kphys, hr_b0, hr_b1
        bcc     :+
        jmp     k3_fault
:       ldx     #0                      ; a free sheet
:       lda     sh_own,x
        beq     :+
        inx
        inx
        cpx     #SH_N * 2
        bcc     :-
        jmp     k3_again
:       lda     sh_rows                 ; room for its rows
        clc
        adc     sr+8
        cmp     #SR_N + 1
        bcc     :+
        jmp     k3_again
:       lda     cur
        inc     a
        sta     sh_own,x
        lda     sr+6
        sta     sh_w,x
        lda     sr+8
        sta     sh_h,x
        lda     sr+4
        sta     sh_ss,x
        lda     hr_b0
        sta     sh_b0,x
        lda     hr_b1
        sta     sh_b1,x
        stx     sh_t
        lda     sh_rows
        asl     a
        sta     sh_row,x
        tax
        lda     sh_rows
        clc
        adc     sr+8
        sta     sh_rows
        lda     sr+8                    ; its rows: the physical address + r * stride
        sta     kt0
        lda     kphys+2
        and     #$00FF
        tay
        lda     kphys
@row:   sta     f:SROW_LO,x
        pha
        tya
        sta     f:SROW_HI,x
        pla
        clc
        adc     sr+4
        bcc     :+
        iny
:       inx
        inx
        dec     kt0
        bne     @row
        lda     sh_t
        lsr     a
        inc     a
        jsl     f_set_ok
        rtl

; ---- $A2 sheet_free(A = sheet, $FFFF: every sheet of the caller's) ----
; The caller's running list is stopped first (as at bank_free). EINVAL: not the caller's sheet.
k3_free:
        ldx     cur
        lda     t_a,x
        cmp     #$FFFF
        beq     @all
        jsr     sh_mine
        bcs     @inv
        phx
        jsl     f2_stop
        plx
        jsr     sh_drop
        jmp     k3_ok0
@all:   jsl     f2_stop
        jsr     sh_dropall
        jmp     k3_ok0
@inv:   jmp     k3_inval

; sheet A (any value) -> X = its index * 2; C set: not one of the caller's
sh_mine:
        dec     a
        cmp     #SH_N
        bcs     @no
        asl     a
        tax
        lda     cur
        inc     a
        cmp     sh_own,x
        bne     @no
        clc
        rts
@no:    sec
        rts

; every sheet of the caller freed
sh_dropall:
        ldx     #0
@s:     lda     cur
        inc     a
        cmp     sh_own,x
        bne     :+
        jsr     sh_drop
:       inx
        inx
        cpx     #SH_N * 2
        bcc     @s
        rts

; sheet X (index * 2) freed: the rows of the sheets after it in SROW move down (keeps X)
sh_drop:
        lda     #0
        sta     sh_own,x
        lda     sh_h,x
        asl     a
        sta     kt0                     ; its rows' bytes (in each table)
        lda     sh_row,x
        sta     kt1                     ; where they start
        clc
        adc     kt0
        sta     kt2                     ; where the rows after them start
        lda     sh_rows
        sec
        sbc     sh_h,x
        sta     sh_rows
        asl     a
        sec
        sbc     kt1
        sta     kt3                     ; the bytes after them
        phx
        lda     kt3
        beq     @fix
        phb
        lda     kt2
        clc
        adc     #.loword(SROW_LO)
        tax
        lda     kt1
        clc
        adc     #.loword(SROW_LO)
        tay
        lda     kt3
        dec     a
        mvn     #^SROW_LO, #^SROW_LO
        lda     kt2
        clc
        adc     #.loword(SROW_HI)
        tax
        lda     kt1
        clc
        adc     #.loword(SROW_HI)
        tay
        lda     kt3
        dec     a
        mvn     #^SROW_HI, #^SROW_HI
        plb
@fix:   ldx     #0                      ; the sheets after it: their rows are kt0 lower now
@s:     lda     sh_own,x
        beq     :+
        lda     sh_row,x
        cmp     kt1
        bcc     :+
        sec
        sbc     kt0
        sta     sh_row,x
:       inx
        inx
        cpx     #SH_N * 2
        bcc     @s
        plx
        rts

; ---- hooks (from k2.s's) ----
; (do_exit) the task's sheets freed
        .export k3_task_exit: far
k3_task_exit:
        jsr     sh_dropall
        rtl

; (bank_free, bank A) the caller's sheets that lie in it freed
        .export k3_bank_gone: far
k3_bank_gone:
        sta     sh_t
        ldx     #0
@s:     lda     cur
        inc     a
        cmp     sh_own,x
        bne     @n
        lda     sh_t
        cmp     sh_b0,x
        bcc     @n
        lda     sh_b1,x
        cmp     sh_t
        bcc     @n
        jsr     sh_drop
@n:     inx
        inx
        cpx     #SH_N * 2
        bcc     @s
        rtl

; ---- $A3 sheet_draw(A = window | count << 8 (1-128), X, Y = count records of 16 bytes) -> A =
; the records drawn (those clipped away are left out) ----
; Record: u8 sheet (1-32; a fill: 0), u8 op (SH_FILL 0, SH_COPY 1, SH_KEY 2; + SH_VBL $80: wait
; for the vertical blank first), u8 colour (fill) or key (keyed copy), u8 0, u16 sx, u16 sy
; (the source in the sheet), u16 w, u16 h, i16 x, i16 y (the destination: the window's content,
; or its full-screen framebuffer). Errors (nothing drawn): EINVAL a bad window, count or op, a
; sheet not the caller's, sx + w or sy + h past the sheet, more than 460,800 pixels; EFAULT the
; records not wholly in the caller's memory.
k3_draw:
        jsl     f2_idle                 ; (blocks: before anything is kept)
        lda     ws_on
        bne     :+
@inv:   jmp     k3_inval
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
        asl     a                       ; * 16
        asl     a
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
        jmp     k3_fault
:       lda     kphys                   ; the records: the first at k_i, the last at k_il, in
        pha                             ; bank k3b (kp1 for sh_one), set after f2_setup (it may
        clc                             ; draw: the window system's DP temporaries)
        adc     kt2
        sec
        sbc     #16
        pha
        lda     kphys+2
        and     #$00FF
        pha
        jsl     f2_setup                ; the target (ls_*), no records yet
        pla
        sta     kp1+2
        sta     k3b
        stz     kp1
        pla
        sta     k_il
        pla
        sta     k_i
        stz     sh_skip
        stz     sh_nbig
        stz     sh_big
        stz     sh_big+2
        jsr     sl_clean
        lda     ls_bmp                  ; a bitmap target: every record by sh_one
        bne     sh_slow
        jsr     dr_build                ; the target's rows (C set: too many, or no clip)
        bcc     sh_fast
sh_slow:
        jsr     sh_one
        bcs     sh_err
        lda     k_i
        cmp     k_il
        bcs     sh_end
        adc     #16
        sta     k_i
        bra     sh_slow

; made: the records given less those left out; the area: (made - big ones) * 256 + the big
; ones' pixels, at most LS_AREA; then they run (k2list.s, ls_finish)
sh_end: ldx     cur
        lda     t_a+1,x
        and     #$00FF
        sec
        sbc     sh_skip
        sta     ls_n
        sec
        sbc     sh_nbig
        xba                             ; (at most 128: * 256)
        clc
        adc     sh_big
        tax
        lda     sh_big+2
        adc     #0
        cmp     #^LS_AREA
        bcc     @ok
        bne     @big
        cpx     #.loword(LS_AREA) + 1
        bcs     @big
@ok:    jsl     f2_finish
        lda     ls_cnt
        jsl     f_set_ok
        rtl
@big:   lda     #EINVAL
sh_err: jsl     f_set_err
        rtl

; the fast path (see the top). DBR = the records' bank, X = the record's offset in SL_LIST,
; Y = the record's in its bank; bank $01 with long addressing.
sh_fast:
        lda     ls_ox                   ; content -> clip coordinates, the clip's size
        sec
        sbc     ls_cx0
        sta     c_ox
        lda     ls_oy
        sec
        sbc     ls_cy0
        sta     c_oy
        lda     ls_cx1
        sec
        sbc     ls_cx0
        inc     a
        sta     c_cw1
        lda     ls_cy1
        sec
        sbc     ls_cy0
        inc     a
        sta     c_ch1
        lda     ls_str
        sta     c_ds
        lda     #.loword(DROW_LO)
        sta     kpd
        lda     #.loword(DROW_HI)
        sta     kpdh
        lda     #^DROW_LO               ; (SROW, DROW: bank $7F)
        sta     kpd+2
        sta     kpdh+2
        sta     kps+2
        sta     kpsh+2
        lda     #$FFFF                  ; no sheet seen yet
        sta     sc_hop
        stz     sc_w1
        ldx     ls_o                    ; (0)
        phb
        a8
        lda     k3b
        pha
        plb
        a16
        ldy     k_i
        jmp     @rec

; another sheet or op: checked, its values kept (a fill, WAIT_VBL, one pending, a sheet not
; the caller's: sh_one)
@sw:    sta     sc_hop
        xba
        and     #$00FF
        beq     @swno
        cmp     #SH_KEY + 1
        bcs     @swno
        xba
        sta     sc_op
        lda     f:ls_vbl
        bne     @swno
        lda     sc_hop
        and     #$00FF
        dec     a
        cmp     #SH_N
        bcs     @swno
        asl     a
        phx
        tax
        lda     cur
        inc     a
        cmp     sh_own,x
        bne     @swbad
        lda     sh_w,x
        inc     a
        sta     sc_w1
        lda     sh_h,x
        inc     a
        sta     sc_h1
        lda     sh_ss,x
        sta     sc_ss
        lda     sh_row,x
        clc
        adc     #.loword(SROW_LO)
        sta     kps
        adc     #.loword(SROW_HI - SROW_LO)
        sta     kpsh
        plx
        jmp     @go
@swbad: plx
@swno:  lda     #$FFFF
        sta     sc_hop
        stz     sc_w1
; the record by sh_one (it sets DBR $01 itself); a WAIT_VBL left pending (that record left
; out) sends the next one there too
@slow:  txa
        sta     f:ls_o
        jsr     sh_one
        bcs     @err
        lda     f:ls_o
        tax
        lda     f:ls_vbl
        beq     :+
        lda     #$FFFF
        sta     sc_hop
        stz     sc_w1
:       lda     k_i
        cmp     k_il
        bcs     @end
        adc     #16
        sta     k_i
        tay
        bra     @rec
@err:   plb
        jmp     sh_err
@end:   txa
        sta     f:ls_o
        plb
        jmp     sh_end
@sw1:   jmp     @sw
@sl1:   jmp     @slow

@rec:   lda     a:0,y                   ; sheet | op << 8: as the record before?
        cmp     sc_hop
        bne     @sw1
@go:    lda     a:2,y                   ; 16 KEY, 17 OP
        and     #$00FF
        ora     sc_op
        sta     f:SL_LIST+16,x
        lda     a:4,y                   ; sx, sy
        sta     k_sx
        lda     a:6,y
        sta     k_sy
        lda     a:8,y                   ; w: 1 .. width - sx
        beq     @sl1
        sta     f:SL_LIST+10,x
        sta     k_w
        clc
        adc     k_sx
        bcs     @sl1
        cmp     sc_w1
        bcs     @sl1
        lda     a:10,y                  ; h: 1 .. height - sy
        beq     @sl1
        sta     f:SL_LIST+12,x
        sta     k_h
        adc     k_sy                    ; (C clear here)
        bcs     @sl1
        cmp     sc_h1
        bcs     @sl1
        lda     a:12,y                  ; x: wholly inside the clip (a carry from the adding
        adc     c_ox                    ; only makes the right edge's test stricter)
        bmi     @sl1
        sta     k_x
        adc     k_w
        cmp     c_cw1
        bcs     @sl1
        lda     a:14,y                  ; y
        adc     c_oy
        bmi     @sl1
        tay
        adc     k_h
        cmp     c_ch1
        bcs     @sl1
        lda     k_w                     ; up to 16 x 16: counted as 256 pixels (sh_end)
        ora     k_h
        cmp     #17
        bcs     @big
@addr:  tya                             ; DST = row y of the clip + x
        asl     a
        tay
        lda     [kpd],y
        adc     k_x
        sta     f:SL_LIST+5,x
        lda     [kpdh],y
        adc     #0
        sta     f:SL_LIST+7,x
        lda     k_sy                    ; SRC = row sy of the sheet + sx
        asl     a
        tay
        lda     [kps],y
        adc     k_sx
        sta     f:SL_LIST,x
        lda     [kpsh],y
        adc     #0
        sta     f:SL_LIST+2,x
        lda     sc_ss                   ; the strides
        sta     f:SL_LIST+3,x
        lda     c_ds
        sta     f:SL_LIST+8,x
        txa                             ; the next record
        adc     #24
        tax
        lda     k_i
        cmp     k_il
        bcs     @end2
        adc     #16
        sta     k_i
        tay
        jmp     @rec
@end2:  jmp     @end
@big:   phx                             ; beyond 16 x 16: its pixels counted
        phy
        lda     k_w
        ldx     k_h
        jsl     f2_mul
        clc
        adc     f:sh_big
        sta     f:sh_big
        txa
        adc     f:sh_big+2
        sta     f:sh_big+2
        lda     f:sh_nbig
        inc     a
        sta     f:sh_nbig
        ply
        plx
        clc
        jmp     @addr

; record k_i (in bank kp1+2): copied to sr, checked, clipped, made by ls_emit at ls_o, or left
; out (sh_skip + 1). C set: A = the error. Keeps DBR (sets $01 inside).
sh_one: phb
        pea     KBANK * $0101
        plb
        plb
        ldy     k_i
        ldx     #0
:       lda     [kp1],y
        sta     sr,x
        iny
        iny
        inx
        inx
        cpx     #16
        bcc     :-
        lda     sr+1                    ; op, WAIT_VBL (it goes to the next record made)
        and     #$00FF
        cmp     #SH_VBL
        bcc     :+
        and     #$007F
        ldx     #LS_VBL
        stx     ls_vbl
:       cmp     #SH_KEY + 1
        bcs     @inv
        sta     lr                      ; (LS_FILL, LS_COPY, LS_KEY: the same numbers)
        lda     sr+2                    ; c1 = c2 = the colour or the key
        and     #$00FF
        sta     kx0
        xba
        ora     kx0
        sta     lr+2
        stz     lr_bit
        lda     sr+8                    ; empty: left out (its sheet not even looked at)
        beq     @skip
        sta     lr_w
        lda     sr+10
        beq     @skip
        sta     lr_h
        lda     lr
        bne     @src
        lda     lr_w                    ; a fill: at most 4096 x 4096 (Ali's most), else left out
        cmp     #4097
        bcs     @skip
        lda     lr_h
        cmp     #4097
        bcs     @skip
        bra     @dst
@skip:  inc     sh_skip
        plb
        clc
        rts
@inv:   lda     #EINVAL
        plb
        sec
        rts
@src:   lda     sr                      ; the sheet: the caller's
        and     #$00FF
        jsr     sh_mine
        bcs     @inv
        lda     sr+4                    ; sx + w <= its width, sy + h <= its height
        clc
        adc     lr_w
        bcs     @inv
        dec     a
        cmp     sh_w,x
        bcs     @inv
        lda     sr+6
        clc
        adc     lr_h
        bcs     @inv
        dec     a
        cmp     sh_h,x
        bcs     @inv
        lda     sh_ss,x
        sta     lr_ss
        lda     sr+6                    ; the source: row sy's address + sx
        asl     a
        clc
        adc     sh_row,x
        tax
        lda     f:SROW_LO,x
        clc
        adc     sr+4
        sta     lr_s
        lda     f:SROW_HI,x
        adc     #0
        sta     lr_s+2
@dst:   lda     sr+12                   ; the destination in target coordinates, clipped
        clc
        adc     ls_ox
        sta     lr_x
        lda     sr+14
        clc
        adc     ls_oy
        sta     lr_y
        jsl     f2_clip
        bcs     @skip
        lda     lr_w                    ; the area: beyond 16 x 16, its pixels
        ora     lr_h
        cmp     #17
        bcc     :+
        lda     lr_w
        ldx     lr_h
        jsl     f2_mul
        clc
        adc     sh_big
        sta     sh_big
        txa
        adc     sh_big+2
        sta     sh_big+2
        inc     sh_nbig
:       jsl     f2_emit
        plb
        clc
        rts

; The fast path writes only the bytes of Ali's records that change; FLAGS and RFLAGS (18, 19)
; and 20-23 stay 0. ls_emit raised sl_dirty past the records an earlier list gave a FLAGS or
; RFLAGS: those are cleared; the first time, bytes 18-23 of all 128.
sl_clean:
        lda     sl_init
        bne     @d
        inc     sl_init
        lda     #LS_MAX * 24
        sta     sl_dirty
        ldx     #LS_MAX * 24 - 24
@a:     lda     #0
        sta     f:SL_LIST+20,x
        sta     f:SL_LIST+22,x
        txa
        sec
        sbc     #24
        tax
        bcs     @a
@d:     ldx     sl_dirty
        beq     @out
        stz     sl_dirty
@c:     txa
        sec
        sbc     #24
        tax
        lda     #0
        sta     f:SL_LIST+18,x
        txa
        bne     @c
@out:   rts

; the fast path's rows of the target: DROW_LO / DROW_HI [r] = the address of (ls_cx0, ls_cy0 +
; r), r < ls_cy1 - ls_cy0; made again only when the clip's corner, the stride or the rows
; changed. C set: no clip, or more rows than DR_N (sh_one does those)
dr_build:
        bra     :+
@no:    sec
        rts
:       lda     ls_cx1
        sec
        sbc     ls_cx0
        beq     @no
        bmi     @no
        lda     ls_cy1
        sec
        sbc     ls_cy0
        beq     @no
        bmi     @no
        cmp     #DR_N + 1
        bcs     @no
        sta     kt0                     ; rows
        lda     ls_cy0                  ; the clip's corner
        ldx     ls_str
        jsl     f2_mul
        clc
        adc     ls_cx0
        bcc     :+
        inx
:       clc
        adc     ls_base
        sta     kt2
        txa
        adc     ls_base+2
        and     #$00FF
        sta     kt3
        lda     kt2
        cmp     dr_b
        bne     @make
        lda     kt3
        cmp     dr_b+2
        bne     @make
        lda     ls_str
        cmp     dr_s
        bne     @make
        lda     dr_n
        cmp     kt0
        bcs     @ok
@make:  lda     kt2
        sta     dr_b
        lda     kt3
        sta     dr_b+2
        lda     ls_str
        sta     dr_s
        lda     kt0
        sta     dr_n
        ldy     kt3
        lda     kt2
        ldx     #0
@r:     sta     f:DROW_LO,x
        pha
        tya
        sta     f:DROW_HI,x
        pla
        clc
        adc     ls_str
        bcc     :+
        iny
:       inx
        inx
        dec     kt0
        bne     @r
@ok:    clc
        rts
