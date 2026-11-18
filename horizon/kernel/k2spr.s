; k2spr.s - (0.18) Marga's 16 sprites for programs (REV $0B; ENODEV before).
;
; A program takes sprites with spr_alloc for one of its windows; positions are relative to that
; window's content (to the screen while the window is in full-screen mode, k2fs.s). Marga reads
; the images by itself, behind FREDDIE II, so every image range is checked against the caller's
; memory (its window, code bank, banks it allocated), as for samples.
;
; The rule for windows: hardware sprites cannot be cut to a window's shape, so a window's
; sprites are shown only while the window has the keyboard focus, nothing lies over its content
; (no other window, menu or pop-up), the desktop is on the screen, and only those that lie
; wholly inside the content area; the others are hidden until that holds again. Their screen
; position follows the window (synchronised after every repaint, so a moved window takes them
; along). The mouse pointer stays in front of every sprite (Marga).
;
; Every change goes into the kernel's copy of the 16 records; the vertical blank interrupt
; writes the changed copy to Marga and commits it (NV_SPR_COMMIT), so one call's changes
; appear together, from the next frame on. A task's sprites are freed when it ends (exit,
; kill, crash) or closes their window; a sprite whose image lies in a bank the task frees is
; hidden and loses its image.

SPR_EN      = $01               ; CTRL bits (the record's byte 7)
SPR_BPP4    = $40
SPR_WIDE    = $10
SPR_TALL    = $20
SPR_MAG     = $08
SP_IMG      = $8000             ; (sp_ctl) an image was given and is valid

        .segment "BSS"
sp_own:     .res    32          ; slot*2 + 1, 0 = free
sp_win:     .res    32          ; its window*2
sp_x:       .res    32          ; position (content, or full-screen, coordinates)
sp_y:       .res    32
sp_ia:      .res    32          ; the image's physical address: bits 0-15, bank
sp_ib:      .res    32
sp_ctl:     .res    32          ; CTRL | PAL << 8 | SP_IMG
sp_b0:      .res    32          ; the banks the image lies in (first, last)
sp_b1:      .res    32
sp_rec:     .res    128         ; the records as Marga should have them
spr_dirty:  .res    2           ; sp_rec changed: the next vertical blank writes it
spr_vis:    .res    2           ; (spr_sync) the window whose sprites may show, NONE

        .segment "K0BSS": far
sp_tab:     .res    160         ; spr_set's table, copied

        .segment "K2CODE"

; C set (and ENODEV set as the result) before REV $0B
spr_old:
        lda     k_rev
        cmp     #$0B
        bcs     :+
        lda     #ENODEV
        jsl     f_set_err
        sec
        rts
:       clc
        rts

; sprite A (any value) -> X = sprite * 2; C set if it is not the caller's
spr_mine:
        cmp     #16
        bcs     @no
        asl     a
        tax
        lda     cur
        inc     a
        cmp     sp_own,x
        bne     @no
        clc
        rts
@no:    sec
        rts

; ---- $91 spr_alloc(A = count 1-16, X = window) -> A = the first sprite ----
; count sprites in a row (sprite 0 is in front of 1, ...), hidden, without an image.
; ENODEV before REV $0B, EINVAL not the caller's window or a bad count, EAGAIN none free.
k2_spralloc:
        jsr     spr_old
        bcc     :+
        rtl
:       ldx     cur
        lda     t_x,x
        jsl     f_win_arg
        bcc     :+
        jmp     k2_inval
:       stx     kx4                     ; window*2
        ldx     cur
        lda     t_a,x
        beq     @bad
        cmp     #17
        bcs     @bad
        sta     kx5
        ldy     #0                      ; the first run of count free ones
@try:   tya
        clc
        adc     kx5
        cmp     #17
        bcs     @full
        tya
        asl     a
        tax
        lda     kx5
        sta     kx6
:       lda     sp_own,x
        bne     @next
        inx
        inx
        dec     kx6
        bne     :-
        tya                             ; free: take them
        sta     kx6
        asl     a
        tax
        lda     kx5
        sta     kx7
:       lda     cur
        inc     a
        sta     sp_own,x
        lda     kx4
        sta     sp_win,x
        stz     sp_ctl,x
        stz     sp_x,x
        stz     sp_y,x
        inx
        inx
        dec     kx7
        bne     :-
        lda     kx6
        jsl     f_set_ok
        rtl
@next:  iny
        bra     @try
@full:  lda     #EAGAIN
        jmp     k2_err
@bad:   jmp     k2_inval

; ---- $92 spr_free(A = first, X = count; A = $FFFF: every sprite of the caller) ----
k2_sprfree:
        jsr     spr_old
        bcc     :+
        rtl
:       ldx     cur
        lda     t_a,x
        cmp     #$FFFF
        bne     @some
        jsr     spr_drop
        jmp     k2_ok0
@some:  sta     kx4
        lda     t_x,x
        beq     @bad
        sta     kx5
        clc                             ; all of them the caller's first
        adc     kx4
        cmp     #17
        bcs     @bad
        lda     kx4
        ldy     kx5
:       pha
        jsr     spr_mine
        pla
        bcs     @bad
        inc     a
        dey
        bne     :-
        lda     kx4
        asl     a
        tax
:       stz     sp_own,x
        stz     sp_ctl,x
        inx
        inx
        dec     kx5
        bne     :-
        jsr     spr_sync
        jmp     k2_ok0
@bad:   jmp     k2_inval

; every sprite of the current task freed (its end, spr_free $FFFF)
spr_drop:
        lda     cur
        inc     a
        sta     kx6
        ldx     #30
:       lda     sp_own,x
        cmp     kx6
        bne     :+
        stz     sp_own,x
        stz     sp_ctl,x
:       dex
        dex
        bpl     :--
        jmp     spr_sync

; ---- $93 spr_set(A = count 1-16, X, Y = count entries of 10 bytes) ----
; Entry: u8 sprite, u8 CTRL (Marga's: EN 1 shown, HFLIP 2, VFLIP 4, MAG 8, WIDE 16 (4 bpp),
; TALL 32, BPP4 64, BEHIND 128), i16 x, i16 y, u24 image (16-byte aligned), u8 PAL (the 4 bpp
; palette bank 0-15). Every field of each sprite; all of them appear together from the next
; frame on. Checked first, then set: EINVAL (a sprite not the caller's, an unaligned image, a
; bad count), EFAULT (an image not wholly in the caller's memory: 256 or 512 bytes at 8 bpp,
; 128 to 512 at 4 bpp), and then nothing changes.
k2_sprset:
        jsr     spr_old
        bcc     :+
        rtl
:       ldx     cur
        lda     t_a,x
        jeq     @bad
        cmp     #17
        jcs     @bad
        sta     kx5
        asl     a                       ; * 10
        asl     a
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
        ldy     kt2                     ; a copy (the checks below use kphys)
        dey
        tyx
        a8
:       lda     [kp2],y
        sta     sp_tab,x
        dex
        dey
        bpl     :-
        a16
        stz     kx4                     ; first every entry checked
@chk:   jsr     spr_ent
        bcc     :+
        jmp     k2_err
:       lda     kx4
        clc
        adc     #10
        sta     kx4
        dec     kx5
        bne     @chk
        lda     kx4                     ; then set (spr_ent again, now storing)
        sta     kx5
        stz     kx4
@set:   jsr     spr_ent                 ; (X: the entry; kx6 the sprite * 2)
        ldy     kx6
        lda     sp_tab+1,x
        and     #$00FF
        ora     #SP_IMG
        sta     sp_ctl,y
        lda     sp_tab+2,x
        sta     sp_x,y
        lda     sp_tab+4,x
        sta     sp_y,y
        lda     sp_tab+9,x              ; PAL
        and     #$000F
        xba
        ora     sp_ctl,y
        sta     sp_ctl,y
        lda     kphys
        sta     sp_ia,y
        lda     kphys+2
        and     #$00FF
        sta     sp_ib,y
        lda     hr_b0
        sta     sp_b0,y
        lda     hr_b1
        sta     sp_b1,y
        lda     kx4
        clc
        adc     #10
        sta     kx4
        cmp     kx5
        bcc     @set
        jsr     spr_sync
        jmp     k2_ok0
@bad:   jmp     k2_inval

; entry at sp_tab + kx4 checked: C clear (kx6 = sprite * 2, X = kx4, kphys / hr_b0 / hr_b1:
; the image), C set with A = the error
spr_ent:
        ldx     kx4
        lda     sp_tab,x
        and     #$00FF
        jsr     spr_mine
        bcs     @inv
        stx     kx6
        ldx     kx4
        lda     sp_tab+6,x              ; the image: 16-byte aligned
        bit     #$000F
        bne     @inv
        sta     kt0
        lda     sp_tab+8,x
        and     #$00FF
        sta     kt1
        lda     sp_tab+1,x              ; its size from CTRL
        jsr     spr_size
        sta     kt2
        stz     kt3
        jsr     hw_range
        bcs     @flt
        ldx     kx4
        clc
        rts
@inv:   lda     #EINVAL
        sec
        rts
@flt:   lda     #EFAULT
        sec
        rts

; CTRL in A -> the image's size in bytes: rows (TALL: 32, else 16) * bytes a row (8 bpp: 16;
; 4 bpp: 8, WIDE 16)
spr_size:
        and     #$00FF
        sta     kx7
        ldy     #16                     ; bytes a row
        and     #SPR_BPP4
        beq     :+
        lda     kx7
        and     #SPR_WIDE
        bne     :+
        ldy     #8
:       tya                             ; * 16 rows
        asl     a
        asl     a
        asl     a
        asl     a
        tay
        lda     kx7
        and     #SPR_TALL
        beq     :+
        tya                             ; * 32
        asl     a
        rts
:       tya
        rts

; ---- $94 spr_move(A = sprite, X = x, Y = y): its position only (the cheap call) ----
k2_sprmove:
        jsr     spr_old
        bcc     :+
        rtl
:       ldx     cur
        lda     t_a,x
        jsr     spr_mine
        bcs     @bad
        txy
        ldx     cur
        lda     t_x,x
        sta     sp_x,y
        lda     t_y,x
        sta     sp_y,y
        jsr     spr_sync
        jmp     k2_ok0
@bad:   jmp     k2_inval

; ---- $95 spr_show(A = sprite, X = 1 show, 0 hide) ----
; EINVAL: not the caller's sprite, or shown without an image (none given, or its bank freed)
k2_sprshow:
        jsr     spr_old
        bcc     :+
        rtl
:       ldx     cur
        lda     t_a,x
        jsr     spr_mine
        bcs     @bad
        txy
        ldx     cur
        lda     t_x,x
        bne     @show
        lda     sp_ctl,y
        and     #$FFFF ^ SPR_EN
        bra     @set
@show:  lda     sp_ctl,y
        bpl     @bad                    ; (no image)
        ora     #SPR_EN
@set:   sta     sp_ctl,y
        jsr     spr_sync
        jmp     k2_ok0
@bad:   jmp     k2_inval

; ---- the records from the sprites' state: each sprite's record as Marga should have it now,
; into sp_rec; a change arms the vertical blank (which writes them). Syscall or window-system
; thread context (it uses the window system's clip variables).
spr_sync:
        lda     k_rev
        cmp     #$0B
        bcs     :+
        rts
:       lda     #NONE                   ; the window whose sprites may show
        sta     spr_vis
        lda     fs_act
        beq     @desk
        lda     fs_w
        sta     spr_vis
        bra     @each
@desk:  jsr     pal_live
        bcc     @each
        ldx     fo_w
        bmi     @each
        lda     w_st,x
        and     #1                      ; (WS_MIN)
        bne     @each
        jsl     f_win_visible           ; nothing over its content (kg_cx0 .. kg_cy1 = it)
        bcc     @each
        stx     spr_vis
@each:  ldx     #30
@spr:   stx     kx6
        jsr     spr_rec1
        ldx     kx6
        dex
        dex
        bpl     @spr
        rts

; sprite kx6 (*2): its record built in kx0 .. kx3 and compared with sp_rec
spr_rec1:
        stz     kx0
        stz     kx1
        stz     kx2
        stz     kx3
        lda     sp_own,x
        jeq     @put
        lda     sp_win,x
        cmp     spr_vis
        jne     @put
        lda     sp_ctl,x
        jpl     @put  ; (no image)
        and     #SPR_EN
        jeq     @put
        lda     sp_x,x
        sta     kx0
        lda     sp_y,x
        sta     kx1
        lda     fs_act                  ; full screen: as given, Marga cuts at the edges
        bne     @rec
        lda     kx0                     ; a window: + its content's place, wholly inside
        clc
        adc     kg_cx0
        sta     kx0
        lda     kx1
        clc
        adc     kg_cy0
        sta     kx1
        lda     kx0
        cmp     kg_cx0
        jmi     @hide
        lda     kx1
        cmp     kg_cy0
        bmi     @hide
        lda     sp_ctl,x                ; on-screen size: 16 or 32 (WIDE 4 bpp, TALL) << MAG
        and     #SPR_BPP4 | SPR_WIDE
        cmp     #SPR_BPP4 | SPR_WIDE
        lda     #16
        bcc     :+
        lda     #32
:       sta     kx2
        lda     #16
        sta     kx3
        lda     sp_ctl,x
        and     #SPR_TALL
        beq     :+
        asl     kx3
:       lda     sp_ctl,x
        and     #SPR_MAG
        beq     :+
        asl     kx2
        asl     kx3
:       lda     kx0
        clc
        adc     kx2
        cmp     kg_cx1
        beq     :+
        bpl     @hide
:       lda     kx1
        clc
        adc     kx3
        cmp     kg_cy1
        beq     @rec
        bpl     @hide
@rec:   lda     kx0                     ; Marga's range: X -1024 .. 1023, Y -512 .. 511
        clc
        adc     #1024
        cmp     #2048
        bcs     @hide
        lda     kx1
        clc
        adc     #512
        cmp     #1024
        bcs     @hide
        lda     sp_ia,x                 ; bytes 4, 5: IMG bits 4-7 | PAL, IMG bits 8-15
        and     #$FFF0
        sta     kx2
        lda     sp_ctl,x
        xba
        and     #$000F
        ora     kx2
        sta     kx2
        lda     sp_ctl,x                ; bytes 6, 7: IMG bits 16-23, CTRL
        and     #$00FF
        xba
        ora     sp_ib,x
        sta     kx3
        bra     @put
@hide:  stz     kx0
        stz     kx1
        stz     kx2
        stz     kx3
@put:   lda     kx6                     ; compare with sp_rec + sprite * 8
        asl     a
        asl     a
        tax
        lda     kx0
        cmp     sp_rec,x
        bne     @chg
        lda     kx1
        cmp     sp_rec+2,x
        bne     @chg
        lda     kx2
        cmp     sp_rec+4,x
        bne     @chg
        lda     kx3
        cmp     sp_rec+6,x
        bne     @chg
        rts
@chg:   lda     kx0
        sta     sp_rec,x
        lda     kx1
        sta     sp_rec+2,x
        lda     kx2
        sta     sp_rec+4,x
        lda     kx3
        sta     sp_rec+6,x
        lda     #1
        sta     spr_dirty
        jmp     vbl_arm

; (k2_vbl, the vertical blank) the records to Marga and committed, unless Marga still copies
; the last ones (PENDING); SPR_EN on once a record is enabled. Interrupt context: no kx*.
spr_vbl:
        lda     spr_dirty
        beq     @out
        a8
        lda     f:NV_SPR_COMMIT
        lsr     a
        a16
        bcs     @out
        ldx     #126
:       lda     sp_rec,x
        sta     f:NV_SPR_REC,x
        dex
        dex
        bpl     :-
        a8
        sta     f:NV_SPR_COMMIT
        lda     #1
        sta     f:NV_SPR_CTRL           ; (SPR_EN: sprites drawn)
        a16
        stz     spr_dirty
@out:   rts

; (bank_free) bank A goes: the current task's sprites that read it lose their image (hidden)
spr_bank:
        sta     kx5
        lda     cur
        inc     a
        sta     kx6
        ldx     #30
@s:     lda     sp_own,x
        cmp     kx6
        bne     @n
        lda     kx5
        cmp     sp_b0,x
        bcc     @n
        lda     sp_b1,x
        cmp     kx5
        bcc     @n
        stz     sp_ctl,x
@n:     dex
        dex
        bpl     @s
        jmp     spr_sync

; (a window closes) its sprites are freed
spr_wgone:
        stx     kx5
        ldx     #30
:       lda     sp_own,x
        beq     :+
        lda     sp_win,x
        cmp     kx5
        bne     :+
        stz     sp_own,x
        stz     sp_ctl,x
:       dex
        dex
        bpl     :--
        rts
