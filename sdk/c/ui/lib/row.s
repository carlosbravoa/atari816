; row.s - the list row callback. Every C list's LS_ROW is HUI_ROWCB (hui.h: UI_LIST), a
; JMP here; the list's C function is the 4 bytes after the library's structure
; (ui_list.rowfn). Called by the library (uilist.s) with JSR: A = row, ui_c = the list,
; ui_win, ui_x, ui_y = the row's top left, ui_rsel = 1 if selected. Returns X = the row's
; text in the code bank (the C function's string, or a copy of it in scratch buffer 2).
;
; The C function runs with the block's direct page saved (it may draw with ui_rect,
; ui_text ...; those change ui_x ... which the library needs back) and hui_incb set: a
; control routine called from it stops the program with a message (so this never nests:
; its state is static).
        .p816
        .smart  off
        .include "horizon.inc"
        .include "ui.inc"
        .include "huidefs.inc"

        .segment "BSS"
rinfo:  .res    8               ; ui_rowinfo: win, x, y, sel
rres:   .res    2
rrow:   .res    2
rlist:  .res    2
rfn:    .res    4

        .segment "RODATA"
empty:  .byte   0

        .segment "CODE"
        .a16
        .i16

hui_rowtramp:
        sta     rrow
        ldx     z:ui_c
        stx     rlist
        lda     a:LS_SIZE,x             ; the C function
        sta     rfn
        lda     a:LS_SIZE+2,x
        sta     rfn+2
        ora     rfn
        bne     :+
        ldx     #.loword(empty)         ; none: an empty row
        rts
:       lda     z:ui_win
        sta     rinfo
        lda     z:ui_x
        sta     rinfo+2
        lda     z:ui_y
        sta     rinfo+4
        lda     z:ui_rsel
        sta     rinfo+6
        ZSAVE
        lda     rfn
        sta     z:hui_fn
        lda     rfn+2
        sta     z:hui_fn+2
        inc     hui_incb
        lda     #^rinfo                 ; const ui_rowinfo *ri (o65: a bank byte only
        pha                             ;   as an immediate)
        pea     rinfo
        lda     rrow                    ; unsigned row
        pha
        lda     rlist                   ; ui_list *ls: A = offset, X = bank
        ldx     #^rinfo
        CALLC
        ply
        ply
        ply
        dec     hui_incb
        sta     z:hui_s                 ; the text (a C pointer)
        stx     z:hui_s+2
        ora     z:hui_s+2
        bne     :+
        lda     #.loword(empty)         ; NULL: empty
        bra     @set
:       ldx     #2                      ; elsewhere than the code bank: a copy
        jsr     hui_instr
@set:   sta     rres
        ZRESTORE
        ldx     rres
        rts
