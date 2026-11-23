; vstate.s - the video-state block: a copy of what Marga shows, at a fixed address
; ($01:F000) for tools that read memory from outside (the PC link's screenshot: the
; Marga's palette and registers cannot be read back). Layout in ABI.md, "Video state".
; Every write of NV_CTRL, NV_BASE, NV_STRIDE, the palette and the pointer registers goes
; through here or stores its copy next to the write; vs_seq counts the changes (not the
; pointer moves), so a reader can tell a torn read.
; (0.30) Version 2: the hardware revision (k_rev itself lives at offset 30) and, after the
; palette at offset 800, the full-screen program's scroll set (k2fs.s keeps fs_act and fs_scr
; there), so a screenshot needs no search of the kernel's code. Old readers see version 1's
; fields where they were.

VS_VERSION = 2

        .segment "VSTATE"
vs_blk:
vs_magic:   .res    4           ; "HZVS"
vs_ver:     .res    1           ; VS_VERSION
vs_hlen:    .res    1           ; header length: the palette starts there (32)
vs_seq:     .res    2           ; + 1 at every change but pointer moves
vs_ctrl:    .res    1           ; NV_CTRL as written (0 while the classic machine is shown)
vs_base:    .res    3           ; NV_BASE
vs_stride:  .res    2           ; NV_STRIDE
vs_state:   .res    1           ; bit 0 the classic machine is shown, bit 1 the desktop runs
vs_dctrl:   .res    1           ; NV_CTRL of the native screen when it is shown (scr_ctrl)
vs_px:      .res    2           ; PTR_X, PTR_Y (the hot spot)
vs_py:      .res    2
vs_hot:     .res    1           ; PTR_HOT
vs_img:     .res    3           ; PTR_IMG
vs_pc:      .res    3           ; PTR_C1-C3
vs_shape:   .res    1           ; 0 arrow, 1 drag, 2 crosshair, 3 column resize, 4 row resize (ws_pointer)
vs_btn:     .res    2           ; the mouse buttons now
k_rev:      .res    2           ; (0.30) SYS_REV (the kernel's variable; 0 before snd_init)
vs_pal:     .res    768         ; the palette as written to Marga: R, G, B for 0-255
vs_end:                         ; (0.30) k2fs.s: fs_act (2) and fs_scr (14) follow (offset 800)
        .assert vs_pal - vs_blk = 32, error, "video state: header must be 32 bytes"

        .segment "CODE"

; boot, before the screen: the header, then the whole system palette into Marga (the
; console sets its own entries 0-5 over it), so the copy is exact from the start
vs_init:
        ldx     #0
:       stz     vs_blk,x
        inx
        inx
        cpx     #__VSTATE_SIZE__        ; (0.30) with k2fs.s's part after the palette
        bcc     :-
        lda     #'H' | ('Z' << 8)
        sta     vs_magic
        lda     #'V' | ('S' << 8)
        sta     vs_magic+2
        lda     #VS_VERSION | ((vs_pal - vs_blk) << 8)
        sta     vs_ver
        lda     #0
        ldx     #.loword(ws_palette)
        ldy     #256
        ; fall through
; Y entries from the table at X (bank $01, R G B) into Marga from entry A, and into the
; copy
pal_load:
        sta     kt0
        sty     kt1
        a8
        sta     f:PAL_IDX
        a16
        asl     a
        clc
        adc     kt0
        tay
@e:     a8
        lda     a:0,x
        sta     f:PAL_R
        sta     vs_pal,y
        lda     a:1,x
        sta     f:PAL_R+1
        sta     vs_pal+1,y
        lda     a:2,x
        sta     f:PAL_R+2               ; (commits the entry, steps PAL_IDX)
        sta     vs_pal+2,y
        a16
        inx
        inx
        inx
        iny
        iny
        iny
        dec     kt1
        bne     @e
        inc     vs_seq
        rts

; NV_CTRL = A (low byte), with its copy, scr_ctrl's copy and the state bits (keeps X, Y)
nv_ctrl:
        a8
        sta     f:NV_CTRL
        sta     vs_ctrl
        lda     scr_ctrl
        sta     vs_dctrl
        lda     ws_on
        asl     a
        ora     cls_on
        and     #3
        sta     vs_state
        a16
        inc     vs_seq
        rts
