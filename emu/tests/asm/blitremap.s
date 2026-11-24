; emu816 test (REV $0D): Ali's colour remap, against the CPU's own reading of the table.
;   - TABLE (OP 5): 256 bytes from RAM into the table (an aligned one, and one 3 bytes into an
;     8-byte group), and a part of one (DST 16, WIDTH 16: entries 16-31);
;   - COPY_REMAP (OP 6): every pixel is table[source];
;   - COPY_KEY_REMAP (OP 7): the key is tested on the source pixel (key 7: those pixels are left);
;   - a plain COPY after the remapped ones (nothing of them left behind);
;   - a command list: a TABLE record, then a COPY_REMAP record;
;   - a FILL after them (with BL_FLAGS bit 1 set, which means nothing).
; Prints the microseconds of a 320 x 200 COPY, of the TABLE load and of a 320 x 200
; COPY_REMAP (classic machine running, Marga off: the emulator's model of the board, emu/blitter.c:
; a remapped copy costs a copy's time + 12%, a TABLE a 256-pixel copy's), then PIXELS OK.
;   COPY  64000 x 361 / 200 + 8         = 115,528 cycles = 8,068 us ($1F84)
;   TABLE 256 x 361 / 200 + 8           =     470 cycles =    32 us ($0020)
;   REMAP 71680 x 361 / 200 + 8         = 129,390 cycles = 9,036 us ($234C)
        .include "common.inc"

CACHE_FLUSH = $00D80A
BL       = $00DA00
BL_CTRL  = $00DA13
BL_LIST  = $00DA14
BL_COUNT = $00DA17
T1       = $020000              ; table 1: c -> c ^ $5A
T2       = $020103              ; table 2: c -> 255 - c (3 bytes into an 8-byte group)
LISTA    = $022000              ; two command records
SRC      = $040000              ; 320 x 200, pixel i = i * 7 (low byte)
D1       = $050000
D2       = $060000
D3       = $070000
D4       = $080000

t1      = $20
t2      = $22
bad     = $24
pp      = $26                   ; -> a parameter block (16 bits, this bank)
ptab    = $28                   ; -> the table to check against (24 bits)
pdst    = $2C                   ; -> the destination to check (24 bits)
key     = $30                   ; COPY_KEY's key, $FFFF none
n       = $32                   ; bytes to check
pre     = $34                   ; what the destination held before (keyed pixels)

        .a8
        .i16
start:  clc
        xce
        rep     #$10
        sep     #$20
        ldx     #$01FF
        txs
        phk
        plb
        print   m_hello
        stz     bad
        lda     #$FF                    ; (no key)
        sta     key
        sta     key+1
        rep     #$20                    ; the tables, the source, D3 = $EE
        .a16
        ldx     #0
:       txa
        sep     #$20
        .a8
        eor     #$5A
        sta     f:T1,x
        txa
        eor     #$FF
        sta     f:T2,x
        rep     #$20
        .a16
        inx
        cpx     #256
        bcc     :-
        ldx     #0
        lda     #0
:       sep     #$20
        .a8
        sta     f:SRC,x
        pha
        lda     #$EE
        sta     f:D3,x
        pla
        rep     #$20
        .a16
        clc
        adc     #7
        inx
        cpx     #64000
        bcc     :-
        sep     #$20
        .a8
        ; a 320 x 200 COPY, timed
        ldx     #.loword(p_copy)
        jsr     blit
        print   m_copy
        jsr     elapsed
        ; the table, timed
        ldx     #.loword(p_tab1)
        jsr     blit
        print   m_tab
        jsr     elapsed
        ; a 320 x 200 COPY_REMAP, timed
        ldx     #.loword(p_remap)
        jsr     blit
        print   m_remap
        jsr     elapsed
        sta     f:CACHE_FLUSH
        ldx     #.loword(D1)            ; COPY: the source as it is
        lda     #^D1
        ldy     #$FFFF                  ; (no table)
        jsr     check
        ldx     #.loword(D2)            ; REMAP: T1[source]
        lda     #^D2
        ldy     #.loword(T1)
        jsr     check
        ; COPY_KEY_REMAP, key 7, into D3 ($EE): those pixels stay $EE
        ldx     #.loword(p_key)
        jsr     blit
        sta     f:CACHE_FLUSH
        rep     #$20
        .a16
        lda     #7
        sta     key
        sep     #$20
        .a8
        ldx     #.loword(D3)
        lda     #^D3
        ldy     #.loword(T1)
        jsr     check
        ; table 2 (unaligned), a remapped copy with it; then a plain copy over it
        ldx     #.loword(p_tab2)
        jsr     blit
        ldx     #.loword(p_rm4)
        jsr     blit
        sta     f:CACHE_FLUSH
        ldx     #.loword(D4)
        lda     #^D4
        ldy     #.loword(T2)
        jsr     check
        ldx     #.loword(p_cp4)
        jsr     blit
        sta     f:CACHE_FLUSH
        ldx     #.loword(D4)
        lda     #^D4
        ldy     #$FFFF
        jsr     check
        ; FILL (FLAGS bit 1 set: nothing): FG as it is
        ldx     #.loword(p_fill)
        jsr     blit
        sta     f:CACHE_FLUSH
        ldx     #0
:       lda     f:D4,x
        cmp     #$33
        beq     :+
        inc     bad
:       inx
        cpx     #320
        bcc     :--
        ; a list: TABLE (T1), then COPY_REMAP into D1 (it held the plain copy)
        ldx     #0
:       lda     p_tab1,x
        sta     f:LISTA,x
        lda     p_remap1,x
        sta     f:LISTA+24,x
        inx
        cpx     #19
        bcc     :-
        lda     #0
        sta     f:LISTA+19
        sta     f:LISTA+24+19
        rep     #$20
        .a16
        lda     #.loword(LISTA)
        sta     f:BL_LIST
        lda     #2
        sta     f:BL_COUNT
        sep     #$20
        .a8
        lda     #^LISTA
        sta     f:BL_LIST+2
        lda     #4                      ; LIST
        sta     f:BL_CTRL
:       lda     f:BL_CTRL
        lsr
        bcs     :-
        sta     f:CACHE_FLUSH
        ldx     #.loword(D1)
        lda     #^D1
        ldy     #.loword(T1)
        jsr     check
        ; entries 16-31 from table 2 (DST 16, WIDTH 16), the rest still table 1: a copy of
        ; the first 256 source pixels (every colour once: 7 is odd) through it
        ldx     #.loword(p_part)
        jsr     blit
        ldx     #.loword(p_rm5)
        jsr     blit
        sta     f:CACHE_FLUSH
        rep     #$20
        .a16
        ldx     #0
@pt:    lda     f:SRC,x
        and     #$00FF
        tay
        sep     #$20
        .a8
        cpy     #16
        bcc     @t1
        cpy     #32
        bcs     @t1
        tya
        eor     #$FF                    ; T2
        bra     @cmp
@t1:    tya
        eor     #$5A                    ; T1
@cmp:   cmp     f:D2,x
        beq     :+
        inc     bad
:       rep     #$20
        .a16
        inx
        cpx     #256
        bcc     @pt
        sep     #$20
        .a8
        lda     bad
        bne     :+
        print   m_pass
        stp
:       print   m_fail
        stp

; the parameter block at X ($DA00-$DA12) written, START, BUSY waited for; t1 / t2 the uptime
; before and after
blit:   stx     pp
        ldy     #0
:       lda     (pp),y
        tyx
        sta     f:BL,x
        iny
        cpy     #19
        bcc     :-
        rep     #$20
        .a16
        lda     f:UPTIME
        sta     t1
        sep     #$20
        .a8
        lda     #1                      ; START
        sta     f:BL_CTRL
:       lda     f:BL_CTRL
        lsr
        bcs     :-
        rep     #$20
        .a16
        lda     f:UPTIME
        sta     t2
        sep     #$20
        .a8
        rts

; the destination A:X (320 x 200 from it, or n bytes) against the source through the table
; at $02:Y (Y = $FFFF: no table); key: source pixels of that colour must have stayed $EE. Clears
; key afterwards.
check:  stx     pdst
        sta     pdst+2
        sty     ptab
        lda     #^T1
        sta     ptab+2
        rep     #$20
        .a16
        ldx     #0
@px:    lda     f:SRC,x
        and     #$00FF
        cmp     key
        bne     @nk
        sep     #$20                    ; a keyed pixel: left alone
        .a8
        txy
        lda     [pdst],y
        cmp     #$EE
        beq     @ok
        bra     @bad
        .a16
@nk:    tay
        lda     ptab
        cmp     #$FFFF
        sep     #$20                    ; (Z kept)
        .a8
        beq     @plain
        lda     [ptab],y
        bra     @c
@plain: tya
@c:     txy
        cmp     [pdst],y
        beq     @ok
@bad:   inc     bad
@ok:    rep     #$20
        .a16
        inx
        cpx     #64000
        bcc     @px
        lda     #$FFFF
        sta     key
        sep     #$20
        .a8
        rts

elapsed:
        rep     #$20
        .a16
        lda     t2
        sec
        sbc     t1
        tax
        sep     #$20
        .a8
        jsr     puthex16
        jmp     crlf

; parameter blocks: SRC, SRC_STRIDE, DST, DST_STRIDE, WIDTH, HEIGHT, FG, BG, KEY, OP, FLAGS
.macro  blk src, sstr, dst, dstr, w, h, fg, key, op, flags
        .faraddr src
        .word   sstr
        .faraddr dst
        .word   dstr, w, h
        .byte   fg, 0, key, op, flags
.endmacro
p_copy:  blk SRC, 320, D1, 320, 320, 200, 0, 0, 1, 0
p_tab1:  blk T1, 0, 0, 0, 256, 1, 0, 0, 5, 0
p_remap: blk SRC, 320, D2, 320, 320, 200, 0, 0, 6, 0
p_key:   blk SRC, 320, D3, 320, 320, 200, 0, 7, 7, 0
p_tab2:  blk T2, 0, 0, 0, 256, 1, 0, 0, 5, 0
p_rm4:   blk SRC, 320, D4, 320, 320, 200, 0, 0, 6, 0
p_cp4:   blk SRC, 320, D4, 320, 320, 200, 0, 0, 1, 0
p_fill:  blk SRC, 320, D4, 320, 320, 1, $33, 0, 0, 2
p_remap1: blk SRC, 320, D1, 320, 320, 200, 0, 0, 6, 0
p_part:  blk T2 + 16, 0, 16, 0, 16, 1, 0, 0, 5, 0
p_rm5:   blk SRC, 256, D2, 256, 256, 1, 0, 0, 6, 0

m_hello: .byte "ALI REMAP", 10, 0
m_copy:  .byte "COPY 320X200 US ", 0
m_tab:   .byte "TABLE US ", 0
m_remap: .byte "COPY_REMAP 320X200 US ", 0
m_pass:  .byte "PIXELS OK", 10, "DONE", 10, 0
m_fail:  .byte "PIXELS WRONG", 10, "DONE", 10, 0
