; MTEST - mouse queue unit test through the mouse_inject test syscall (needs the keyboard:
; claimed, or lent by its parent). The pointer starts wherever it is; MTEST first moves
; it to the top-left corner (clamping), then checks coalescing.
        .include "horizon.inc"
        .segment "CODE"
        .a16
        .i16
start:  sys     SYS_ICLAIM
        jsr     drain
        ldy     #12                     ; 12 x (-127, -127): clamped to (0, 0)
:       phy
        lda     #$81 | ($81 << 8)
        ldx     #0
        sys     SYS_MINJECT
        ply
        dey
        bne     :-
        jsr     next                    ; ... and coalesced into one event
        jsr     show
        ldy     #4                      ; 4 x (+25, +10): one event at (100, 40)
:       phy
        lda     #25 | (10 << 8)
        ldx     #0
        sys     SYS_MINJECT
        ply
        dey
        bne     :-
        lda     #0                      ; left button down: its own event
        ldx     #1 << 8
        sys     SYS_MINJECT
        lda     #5 | (5 << 8)           ; motion with the button held, twice
        ldx     #1 << 8
        sys     SYS_MINJECT
        lda     #5 | (5 << 8)
        ldx     #1 << 8
        sys     SYS_MINJECT
        lda     #0                      ; button up: its own event
        ldx     #0
        sys     SYS_MINJECT
        lda     #0                      ; wheel +2, +3: one event of +5
        ldx     #2
        sys     SYS_MINJECT
        lda     #0
        ldx     #3
        sys     SYS_MINJECT
        ldy     #5
:       phy
        jsr     next
        jsr     show
        ply
        dey
        bne     :-
        lda     #127 | (127 << 8)       ; far right/bottom: clamped to (639, 359)
        ldx     #0
        ldy     #8
:       phy
        lda     #127 | (127 << 8)
        ldx     #0
        sys     SYS_MINJECT
        ply
        dey
        bne     :-
        jsr     next
        jsr     show
        lda     #0                      ; ws_mouse: the pointer and buttons at any time
        ldx     #2 << 8                 ; (the right button down)
        sys     SYS_MINJECT
        lda     #$FF
        ptr     mbuf
        sys     SYS_WMOUSE
        sta     z:ea
        stx     z:ex
        print   "mtest: ws_mouse "
        lda     mbuf
        jsr     put_dec
        lda     #','
        jsr     out_char
        lda     mbuf+2
        jsr     put_dec
        print   " content "
        lda     mbuf+4
        jsr     put_dec
        lda     #','
        jsr     out_char
        lda     mbuf+6
        jsr     put_dec
        print   " buttons "
        lda     mbuf+8
        jsr     put_dec
        print   " = "
        lda     z:ea
        jsr     put_dec
        print   ", window "
        lda     z:ex
        jsr     put_dec
        lda     #3                      ; a window without the window system: EINVAL
        ptr     mbuf
        sys     SYS_WMOUSE
        bcc     :+
        pha
        print   ", window 3: error "
        pla
        jsr     put_dec
:       jsr     put_nl
        lda     #0                      ; the button up again
        ldx     #0
        sys     SYS_MINJECT
        jsr     drain
        lda     #$80 | ($80 << 8)       ; leave the pointer at (319, 179): -128, -128
        ldx     #0
        sys     SYS_MINJECT
        lda     #$80 | ($CC << 8)       ; -128, -52
        ldx     #0
        sys     SYS_MINJECT
        lda     #$C0                    ; -64, 0
        ldx     #0
        sys     SYS_MINJECT
        jsr     drain
        exit    0

; read the next event -> u_t.. (A, X, Y)
next:   sys     SYS_IREAD
        sta     z:ea
        stx     z:ex
        sty     z:ey
        rts
show:   print   "mtest: "
        lda     z:ea
        cmp     #$0200
        beq     @w
        print   "buttons "
        lda     z:ea
        and     #$0007
        jsr     put_dec
        print   " at "
        lda     z:ex
        jsr     put_dec
        lda     #','
        jsr     out_char
        lda     z:ey
        jsr     put_dec
        jmp     put_nl
@w:     print   "wheel "
        lda     z:ex
        jsr     put_dec
        jmp     put_nl
; drop queued events (non-blocking: there is no peek, so inject-and-read a marker)
drain:  lda     #0
        ldx     #$7F                    ; wheel +127 as an end marker
        sys     SYS_MINJECT
:       sys     SYS_IREAD
        cmp     #$0200
        bne     :-
        cpx     #$007F
        bcc     :-
        rts

        .segment "BSS"
mbuf:   .res    10
        .segment "ZEROPAGE"
ea:     .res    2
ex:     .res    2
ey:     .res    2
