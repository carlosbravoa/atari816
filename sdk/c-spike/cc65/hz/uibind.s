; uibind.s - C bindings (cc65) for a few routines of Horizon's controls library (ui.lib).
;
; ui.lib routines are called with JSR and 16-bit A/X/Y, structures in the code bank (DBR):
; exactly what a cc65 pointer is. A shim stores the C arguments, switches to 16-bit
; registers, calls, switches back and returns A (and the carry as a value where useful).
; ui.lib's own zero page (ui_*) and ulib's are placed by ld65 next to cc65's in the direct page.

        .p816
        .smart  off

        .import         ui_init, ui_getev, ui_drawall, ui_event, ui_ev
        .importzp       ptr1
        .export         _ui_init, _ui_getev, _ui_drawall, _ui_event, _ui_ctl
        .export         _ui_ev := ui_ev         ; the event record (8 bytes, code bank)

        .segment "CODE"
        .a8
        .i8

; void ui_init(void);
_ui_init:
        rep     #$30
        jsr     ui_init
        sep     #$30
        rts

; unsigned char __fastcall__ ui_getev(unsigned char poll);  -> 1 = an event in ui_ev
_ui_getev:
        rep     #$30
        .a16
        .i16
        and     #$00FF
        jsr     ui_getev
        sep     #$30
        .a8
        .i8
        lda     #0
        rol     a                       ; C set = none
        eor     #1
        ldx     #0
        rts

; void __fastcall__ ui_drawall(void **list);
_ui_drawall:
        sta     ptr1
        stx     ptr1+1
        rep     #$30
        .a16
        .i16
        ldx     ptr1
        jsr     ui_drawall
        sep     #$30
        .a8
        .i8
        rts

; unsigned char __fastcall__ ui_event(void **list);  -> UA_*, ui_ctl = the control
_ui_event:
        sta     ptr1
        stx     ptr1+1
        rep     #$30
        .a16
        .i16
        ldx     ptr1
        jsr     ui_event
        stx     _ui_ctl
        sep     #$30
        .a8
        .i8
        ldx     #0
        rts

        .segment "BSS"
_ui_ctl: .res   2
