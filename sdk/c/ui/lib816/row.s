; row.s - the list row callback for cc816. Every C list's LS_ROW is hui_rowtramp (hui.h:
; UI_LIST, HUI_ROWCB); the list's C function is the word after the library's structure
; (ui_list.rowfn). Called by the library (uilist.s) with JSR: A = row, ui_c = the list,
; ui_win, ui_x, ui_y = the row's top left, ui_rsel = 1 if selected. Returns X = the row's
; text (the C function's string: cc816's pointers are in the code bank already).
;
; The C function runs with the library's direct page saved (it may draw with ui_rect,
; ui_text ...; those change ui_x ... which the library needs back) and hui_incb set: a
; control routine called from it stops the program with a message (so this never nests:
; its state is static).
        .p816
        .smart  off
        .include "horizon.inc"
        .include "ui.inc"
        .include "hui816.inc"
        .export _hui_rowtramp

        .segment "BSS"
rinfo:  .res    8               ; ui_rowinfo: win, x, y, sel
rres:   .res    2
rrow:   .res    2
rlist:  .res    2
rfn:    .res    2

        .segment "RODATA"
empty:  .byte   0

        .segment "CODE"
        .a16
        .i16

_hui_rowtramp:
hui_rowtramp:
        sta     rrow
        ldx     z:ui_c
        stx     rlist
        lda     a:LS_SIZE,x             ; the C function
        sta     rfn
        bne     :+
        ldx     #empty                  ; none: an empty row
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
        inc     hui_incb
        pea     rinfo                   ; const ui_rowinfo *ri
        lda     rrow                    ; unsigned row
        pha
        lda     rlist                   ; ui_list *ls
        pha
        ldx     #0
        jsr     (rfn,x)
        ply
        ply
        ply
        dec     hui_incb
        sta     rres                    ; the text
        ZRESTORE
        ldx     rres
        bne     :+
        ldx     #empty                  ; NULL: empty
:       rts
