; k2.s - (0.18) the kernel's second code segment, run from bank 0 $E100-$FEFF (kernel.cfg):
; the games round's calls (frame sync, palette ownership, sprites, full-screen mode, draw lists).
; Its own assembly unit, so a bank $01 routine can only be reached through the JSL wrappers of
; kfar.s (k2.inc); bank $01 calls the entry points here with JSL, and they end with RTL. The
; usual kernel conventions hold (a16 i16, D = KDP, DBR = $01): bank $01 variables are read as
; always; the bank 0 tables of this unit (K0BSS, K2DATA) are far labels, so ca65 reads them with
; long addressing, and an instruction that has no long form is an assembly error.
;
;   k2vbl.s   the vertical blank: frame counter, what is applied there, WE_VBL
;   k2pal.s   palette entries of programs (who holds which, shown while in front)
;   k2spr.s   sprites
;   k2fs.s    full-screen mode, scrolling, the raster table
;   k2list.s  draw lists (Ali's command lists); (0.19) the routines sheet_draw shares (k3.s)
        .p816
        .smart  -
        .feature string_escapes

        .include "hw.inc"
        .include "kdefs.inc"
        .include "k2.inc"
        .import k3_task_exit: far, k3_bank_gone: far    ; (0.19) the third code segment, k3.s

; Marga (Docs/02-register-spec.md) and the rest of the hardware this unit uses
NV_CTRL     = $00D900
NV_BASE     = $00D901
NV_STRIDE   = $00D904
NV_LINE     = $00D906
NV_LINE_CMP = $00D908
NV_STATUS   = $00D90A
NV_FRAME    = $00D90C
PAL_IDX     = $00D910
PAL_R       = $00D911
NV_SCROLLX  = $00D930           ; REV $0B: X, Y, X2, Y2, VHEIGHT (words), SCROLL_CTRL
NV_SCROLL_CTRL = $00D93A
NV_SPR_CTRL = $00D940           ; REV $0B: SPR_EN
NV_SPR_COMMIT = $00D941         ; write: copy the records in vertical blank; read bit 0 PENDING
NV_SPR_REC  = $00D980           ; 16 records of 8 bytes
PTR_X       = $00D920
BL_LIST     = $00DA14
BL_COUNT    = $00DA17
BL_CTRL     = $00DA13
IRQ_VBLANK  = $01
IRQ_LINE    = $02
BL_SRC      = $00DA00
ENODEV      = 9
KM_ALT2     = $44               ; HID modifiers: left / right Alt
WE_VBL      = 16                ; (0.18) the vertical blank (win_vbl)

; direct page: ws.s's (the window system's variables this unit shares)
kg_p    = $90
kg_s    = $94
kg_x    = $9C
kg_y    = $9E
kg_w    = $A0
kg_h    = $A2
kg_sf   = $A4
kg_t    = $A6
kg_u    = $A8
kg_v    = $AA
kg_cx0  = $AC
kg_cy0  = $AE
kg_cx1  = $B0
kg_cy1  = $B2
kg_e    = $C2
; this unit's: kx0-kx7 temporaries of syscalls and the window-system thread (lost across
; k_block, like kt*); ki0-ki7 the interrupt handlers' only (vertical blank, raster line)
kx0     = $E0
kx1     = $E2
kx2     = $E4
kx3     = $E6
kx4     = $E8
kx5     = $EA
kx6     = $EC
kx7     = $EE
ki0     = $F0
ki1     = $F2
ki2     = $F4
ki3     = $F6
ki4     = $F8
ki5     = $FA
ki6     = $FC
ki7     = $FE

; syscalls $91-$9F: kfar.s's sys_k2 comes here with X = number * 2
        .export k2_sys: far
        .segment "K2CODE"
        .a16
        .i16
k2_sys: jmp     (k2_tab - $91 * 2,x)
k2_tab: .addr   k2_spralloc, k2_sprfree, k2_sprset, k2_sprmove, k2_sprshow   ; $91
        .addr   k2_fsenter, k2_fsleave, k2_fsscroll, k2_fsraster             ; $96
        .addr   k2_palset, k2_palalloc                                       ; $9A
        .addr   k2_drawlist, k2_listwait                                     ; $9C
        .addr   k2_frame, k2_winvbl                                          ; $9E
        .assert (* - k2_tab) / 2 + $91 = K2_NSYS, error, "k2_tab: one entry per syscall $91 .. K2_NSYS - 1"

; results (jumped to from a syscall handler: they end it with RTL)
k2_ok0: lda     #0
        jsl     f_set_ok
        rtl
k2_inval:
        lda     #EINVAL
        bra     k2_err
k2_fault:
        lda     #EFAULT
k2_err: jsl     f_set_err
        rtl

; ---- a range Marga, Ali or Lau will read or write by itself, past FREDDIE II: kt0 offset,
; kt1 bank (0: the caller's window $0000-$7FFF), kt2 / kt3 length (24 bits, at least 1). It
; must lie wholly in the caller's own memory: its window, its code bank or banks it allocated,
; across consecutive banks it owns (not shared banks). -> kphys (physical, 24 bits), hr_b0 /
; hr_b1 the first and last physical bank. C set: EFAULT. Uses kt4 only.
        .segment "BSS"
hr_b0:  .res    2
hr_b1:  .res    2
        .segment "K2CODE"
hw_range:
        lda     kt2
        ora     kt3
        beq     @bad
        lda     kt1
        cmp     #$0100
        bcs     @bad
        cmp     #0
        bne     @banks
        lda     kt3                     ; the window: offset + length <= $8000
        bne     @bad
        lda     kt0
        clc
        adc     kt2
        bcs     @bad
        cmp     #$8001
        bcs     @bad
        ldx     cur
        lda     t_wbank,x
        sta     hr_b0
        sta     hr_b1
        sta     kphys+2
        lda     kt0
        sta     kphys
        clc
        rts
@bad:   sec
        rts
@banks: lda     kt0                     ; the last byte's bank: kt1:kt0 + length - 1
        clc
        adc     kt2
        tax
        lda     kt1
        adc     kt3
        cpx     #0
        bne     :+
        dec     a
:       cmp     #$0100
        bcs     @bad
        sta     hr_b1
        lda     kt1
        sta     hr_b0
        ldx     cur
        lda     t_id,x
        sta     kt4
        ldx     hr_b0
:       lda     bank_st,x               ; every one of them the caller's
        and     #$00FF
        cmp     kt4
        bne     @bad
        inx
        cpx     hr_b1
        bcc     :-
        beq     :-
        lda     kt0
        sta     kphys
        lda     kt1
        sta     kphys+2
        clc
        rts

; ---- hooks called from bank $01 ----

; (do_exit, before its banks are freed) what the task holds here goes: its list stopped, its
; palette entries back to the system, its sprites freed, its full screen ended, (0.19) its
; sheets freed (k3.s)
        .export k2_task_exit: far
k2_task_exit:
        jsr     ls_stop
        jsl     k3_task_exit
        jsr     pal_drop
        jsr     fs_mine
        bcc     :+
        jsr     fs_end
:       jsr     spr_drop
        rtl

; (bank_free, bank A) its list stopped; sprites reading the bank lose their image; a
; full-screen framebuffer there ends the full screen; (0.19) its sheets there are freed (keeps A)
        .export k2_bank_gone: far
k2_bank_gone:
        pha
        jsr     ls_stop
        lda     1,s
        jsl     k3_bank_gone
        lda     1,s
        jsr     spr_bank
        jsr     fs_mine
        bcc     @out
        lda     1,s
        cmp     fs_b0
        bcc     @out
        lda     fs_b1
        cmp     1,s
        bcc     @out
        jsr     fs_end
@out:   pla
        rtl

; (win_close, first: window X*2) its sprites go, its full screen ends, no WE_VBL (keeps X)
        .export k2_wclose: far
k2_wclose:
        phx
        jsr     spr_wgone
        lda     1,s
        tax
        lda     w_vbl,x
        beq     :+
        stz     w_vbl,x
        dec     vbl_n
:        lda     fs_on
        beq     :+
        lda     1,s
        cmp     fs_w
        bne     :+
        jsr     fs_end
:       plx
        rtl

; (ws_thread, first in its loop) what the focus change left to do here, WE_VBL due
        .export k2_service: far
k2_service:
        lda     k2_pend
        beq     :+
        stz     k2_pend
        jsr     fs_update
        jsr     spr_sync
:       lda     vbl_due
        beq     :+
        stz     vbl_due
        jsr     ev_vbl
:       rtl

; (ws_thread, after a repaint) the sprites follow windows that moved, rose or were covered
        .export k2_painted: far
k2_painted:
        jsr     spr_sync
        rtl

; (ws_end: the window system stops) no sprites, no full screen, no raster
        .export k2_ws_end: far
k2_ws_end:
        lda     fs_act
        beq     :+
        jsr     fs_noscroll
:       stz     fs_on
        stz     rs_n
        stz     pal_act
        lda     k_rev
        cmp     #$0B
        bcc     @out
        ldx     #30
:       stz     sp_own,x
        stz     sp_ctl,x
        dex
        dex
        bpl     :-
        ldx     #126
:       stz     sp_rec,x
        dex
        dex
        bpl     :-
        stz     spr_dirty
        lda     #0
        a8
        sta     f:NV_SPR_CTRL
        a16
        ldx     #126
:       sta     f:NV_SPR_REC,x
        dex
        dex
        bpl     :-
        a8
        sta     f:NV_SPR_COMMIT
        a16
@out:   rtl

        .segment "BSS"
k2_pend:    .res    2           ; the window-system thread has fs_update / spr_sync to do
        .segment "K2CODE"

        .include "k2vbl.s"
        .include "k2pal.s"
        .include "k2spr.s"
        .include "k2fs.s"
        .include "k2list.s"

        .segment "K2DATA": far
k2_data_end:    .byte   0
