; ulib.s - user library linked into every program.
;   Output is line-buffered: out_char / out_str / put_* append to a buffer that goes to the
;   console with ONE puts per line (at '\n', when full, or at out_flush), so a line is never
;   spliced with another task's output. The exit macro flushes.
;   Keyboard: key_ascii (HID usage -> ASCII, US layout, shift, caps lock, ctrl), read_char,
;   getline (echo, backspace, ctrl-C), (0.21) key_keep (characters kept for read_char:
;   type-ahead).
;   Strings: str_skip (spaces), parse_dec, through the long pointer u_p.
; All routines: a16 i16; A, X, Y are clobbered unless noted.

        .include "horizon.inc"

        .segment "CODE"
        .a16
        .i16

; ---------------------------------------------------------------- output
; append character A
out_char:
put_char:
        pha
        ldx     z:u_olen
        sep     #$20
        .a8
        sta     out_buf,x
        rep     #$20
        .a16
        inx
        stx     z:u_olen
        pla
        and     #$00FF
        cmp     #10
        beq     out_flush
        cpx     #OUTMAX
        bcs     out_flush
        rts

; send the buffered characters (one puts)
out_flush:
        ldx     z:u_olen
        beq     :+
        sep     #$20
        .a8
        stz     out_buf,x
        rep     #$20
        .a16
        stz     z:u_olen
        ldx     #.loword(out_buf)
        ldy     #^out_buf
        cop     SYS_PUTS
:       rts

put_nl: lda     #10
        bra     out_char

; append the zero-terminated string at X (offset), Y (bank)
out_str:
put_str:
        stx     z:u_s
        tya
        sta     z:u_s+2
        ldy     #0
:       lda     [u_s],y
        and     #$00FF
        beq     :+
        phy
        jsr     out_char
        ply
        iny
        bra     :-
:       rts

put_hex16:
        pha
        xba
        jsr     put_hex8
        pla
put_hex8:
        and     #$00FF
        pha
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        jsr     @nib
        pla
@nib:   and     #$000F
        cmp     #10
        bcc     :+
        adc     #6
:       adc     #'0'
        jmp     out_char

; A = unsigned 16-bit, decimal
put_dec:
        ldy     #0
@div:   ldx     #16                     ; A / 10
        sta     z:u_t
        lda     #0
@bit:   asl     z:u_t
        rol     a
        cmp     #10
        bcc     :+
        sbc     #10
        inc     z:u_t
:       dex
        bne     @bit
        pha                             ; digit
        iny
        lda     z:u_t
        bne     @div
@out:   pla
        clc
        adc     #'0'
        phy
        jsr     out_char
        ply
        dey
        bne     @out
        rts

; A = value, X = width: decimal, right-aligned with spaces
put_decw:
        stx     z:u_w
        pha
        ldy     #1                      ; Y = number of digits
:       cmp     #10
        bcc     :+
        iny
        jsr     div10
        bra     :-
:       sty     z:u_t
        lda     z:u_w
        sec
        sbc     z:u_t
        beq     :++
        bcc     :++
        tax
:       phx
        lda     #' '
        jsr     out_char
        plx
        dex
        bne     :-
:       pla
        jmp     put_dec

; A = A / 10 (keeps X, Y)
div10:  phx
        sta     z:u_t
        lda     #0
        ldx     #16
@bit:   asl     z:u_t
        rol     a
        cmp     #10
        bcc     :+
        sbc     #10
        inc     z:u_t
:       dex
        bne     @bit
        lda     z:u_t
        plx
        rts

; ---------------------------------------------------------------- keyboard
; A = HID usage, X = modifiers | down << 8 -> A = ASCII, 0 if the event gives none.
; Caps lock ($39) toggles on key down. Ctrl + letter gives 1-26 (ctrl-C = 3).
; Arrows: KEY_RIGHT $80, KEY_LEFT $81, KEY_DOWN $82, KEY_UP $83; KEY_HOME $84, KEY_PGUP
; $85, KEY_DEL $86, KEY_END $87, KEY_PGDN $88.
key_ascii:
        stx     z:u_t
        cpx     #$0100                  ; key up: nothing
        bcc     @none
        cmp     #$4F                    ; arrows: HID $4F right, $50 left, $51 down, $52 up
        bcc     :+
        cmp     #$53
        bcs     @none
        clc
        adc     #$80 - $4F
        rts
:       cmp     #$4A                    ; HID $4A home, $4B page up, $4C delete, $4D end,
        bcc     :+                      ; $4E page down
        clc
        adc     #$84 - $4A
        rts
:       cmp     #$39
        bne     :+
        lda     z:u_caps
        eor     #1
        sta     z:u_caps
        bra     @none
:       cmp     #$39
        bcs     @none
        cmp     #$04
        bcc     @none
        tax
        lda     z:u_t                   ; shift?
        and     #$0022
        beq     @plain
        lda     ktab_shift - 4,x
        bra     @got
@plain: lda     ktab - 4,x
@got:   and     #$00FF
        beq     @none
        cmp     #'a'                    ; letters: caps lock inverts, ctrl gives 1-26
        bcc     @nlet
        cmp     #'z' + 1
        bcc     @letter
        cmp     #'A'
        bcc     @nlet
        cmp     #'Z' + 1
        bcs     @nlet
@letter:
        ldx     z:u_caps
        beq     :+
        eor     #$20
:       pha
        lda     z:u_t
        and     #$0011
        beq     :+
        pla
        and     #$001F
        rts
:       pla
@nlet:  rts
@none:  lda     #0
        rts

; (0.21) A = a character kept for read_char: type-ahead read by a program while it was busy
; (the shell's cp and mv look for ctrl-C between two pieces). KEEPMAX at most; more are dropped.
key_keep:
        ldx     u_nkeep
        cpx     #KEEPMAX
        bcs     :+
        sep     #$20
        .a8
        sta     u_keep,x
        rep     #$20
        .a16
        inc     u_nkeep
:       rts

; wait for a key that gives a character -> A ((0.21) the characters kept by key_keep first)
read_char:
        lda     u_nkeep
        beq     :++
        lda     u_keep
        and     #$00FF
        pha
        ldx     #0
:       lda     u_keep+1,x
        sep     #$20
        .a8
        sta     u_keep,x
        rep     #$20
        .a16
        inx
        cpx     #KEEPMAX - 1
        bcc     :-
        dec     u_nkeep
        pla
        rts
:       cop     SYS_IREAD
        jcs     @err
        jsr     key_ascii
        cmp     #0
        beq     :-
        rts
@err:   lda     #10                     ; not ours (any more): don't spin, then behave
        cop     SYS_SLEEP               ; like ctrl-C
        lda     #3
        rts

; read a line into X (offset), Y (bank), at most A - 1 characters (and at most HISTLEN and
; the console width - 3),
; echoing it. Editing: backspace, left/right to move inside the line (inserting there),
; up/down to walk through the last 8 lines entered. Returns A = length (the line is
; zero-terminated), C set on ctrl-C.
getline:
        dec     a
        cmp     #HISTLEN
        bcc     :+
        lda     #HISTLEN
:       sta     z:u_max
        stx     z:u_s
        tya
        sta     z:u_s+2
        stz     z:u_len
        stz     z:u_pos
        cop     SYS_CSIZE               ; never longer than the screen line (prompt + cursor)
        sec
        sbc     #3
        cmp     z:u_max
        bcs     :+
        sta     z:u_max
:       lda     z:u_hcnt
        sta     z:u_hsel                ; browsing position: hcnt = the new line
@key:   jsr     out_flush
        jsr     read_char
        cmp     #13
        bne     :+
        jmp     @enter
:       cmp     #3
        bne     :+
        jmp     @break
:       cmp     #8
        jeq     @bs
        cmp     #KEY_LEFT
        jeq     @left
        cmp     #KEY_RIGHT
        jeq     @right
        cmp     #KEY_UP
        bne     :+
        jmp     @up
:       cmp     #KEY_DOWN
        bne     :+
        jmp     @down
:       cmp     #' '
        bcc     @key
        cmp     #$7F
        bcs     @key
        ldy     z:u_len                 ; insert at u_pos
        cpy     z:u_max
        bcs     @key
        sta     z:u_t
:       cpy     z:u_pos                 ; shift the tail right
        beq     :+
        dey
        jsr     @getc
        iny
        jsr     @putc
        dey
        bra     :-
:       lda     z:u_t
        jsr     @putc
        inc     z:u_len
        jsr     @tail                   ; echo from u_pos, then back to u_pos + 1
        inc     z:u_pos
        lda     z:u_len
        sec
        sbc     z:u_pos
        jsr     @bsn
        jmp     @key
@bs:    lda     z:u_pos
        beq     @key0
        dec     z:u_pos
        lda     #8
        jsr     out_char
        ldy     z:u_pos                 ; shift the tail left
:       iny
        cpy     z:u_len
        beq     :+
        bcs     :+
        jsr     @getc
        dey
        jsr     @putc
        iny
        bra     :-
:       dec     z:u_len
        jsr     @tail
        lda     #' '
        jsr     out_char
        lda     z:u_len
        sec
        sbc     z:u_pos
        inc     a
        jsr     @bsn
@key0:  jmp     @key
@left:  lda     z:u_pos
        beq     @key0
        dec     z:u_pos
        lda     #8
        jsr     out_char
        jmp     @key
@right: ldy     z:u_pos
        cpy     z:u_len
        bcs     @key0
        jsr     @getc
        jsr     out_char
        inc     z:u_pos
        jmp     @key
@up:    lda     z:u_hsel
        beq     @key0
        dec     a
        bra     @recall
@down:  lda     z:u_hsel
        cmp     z:u_hcnt
        bcs     @key0
        inc     a
@recall:
        sta     z:u_hsel
        jsr     @erase
        lda     z:u_hsel                ; hcnt = an empty new line
        cmp     z:u_hcnt
        bcs     @rdone
        jsr     @hptr                   ; Y = history entry offset
        ldx     #0
:       lda     hist,y
        and     #$00FF
        beq     @rdone
        phx
        phy
        txy
        jsr     @putc
        jsr     out_char
        ply
        plx
        inx
        iny
        stx     z:u_len
        bra     :-
@rdone: lda     z:u_len
        sta     z:u_pos
        jmp     @key
@enter: jsr     @term
        jsr     put_nl
        lda     z:u_len                 ; into the history (not empty lines)
        beq     @hdone
        lda     z:u_hcnt
        cmp     #NHIST
        bcc     :+
        jsr     @hshift
        lda     #NHIST - 1
:       jsr     @hptr
        tyx
        ldy     #0
:       jsr     @getc
        sep     #$20
        .a8
        sta     hist,x
        rep     #$20
        .a16
        inx
        iny
        cmp     #0
        bne     :-
        inc     z:u_hcnt
@hdone: lda     z:u_len
        clc
        rts
@break: jsr     @term
        lda     #'^'
        jsr     out_char
        lda     #'C'
        jsr     out_char
        jsr     put_nl
        lda     #0
        sec
        rts

; helpers: Y = index; @getc A = buf[Y], @putc buf[Y] = A (keep X Y)
@getc:  lda     [u_s],y
        and     #$00FF
        rts
@putc:  sep     #$20
        .a8
        sta     [u_s],y
        rep     #$20
        .a16
        rts
@term:  ldy     z:u_len
        lda     #0
        bra     @putc
; echo buf[u_pos .. u_len)
@tail:  ldy     z:u_pos
:       cpy     z:u_len
        bcs     :+
        jsr     @getc
        phy
        jsr     out_char
        ply
        iny
        bra     :-
:       rts
; A backspaces
@bsn:   tax
        beq     :++
:       phx
        lda     #8
        jsr     out_char
        plx
        dex
        bne     :-
:       rts
; erase the line on screen, cursor to its start; the line becomes empty
@erase: lda     z:u_pos
        jsr     @bsn
        lda     z:u_len
        tax
        beq     :++
:       phx
        lda     #' '
        jsr     out_char
        plx
        dex
        bne     :-
:       lda     z:u_len
        jsr     @bsn
        stz     z:u_len
        stz     z:u_pos
        rts
; Y = offset of history entry A
@hptr:  xba                             ; * 128 (HISTLEN + 1 <= 128)
        lsr     a
        tay
        rts
; drop the oldest entry
@hshift:
        ldx     #0
:       lda     hist + 128,x
        sta     hist,x
        inx
        inx
        cpx     #(NHIST - 1) * 128
        bcc     :-
        dec     z:u_hcnt
        rts

; ---------------------------------------------------------------- tasks
; spawn X, Y = path, A = priority, u_arg = argument string (u24, 0 = none) -> A = id / C
spawn:
        stx     spblk
        sep     #$20
        .a8
        sta     spblk+6
        tya
        sta     spblk+2
        lda     z:u_arg+2
        sta     spblk+5
        rep     #$20
        .a16
        lda     z:u_arg
        sta     spblk+3
        ldx     #.loword(spblk)
        ldy     #^spblk
        cop     SYS_SPAWN
        rts

; flush the output, then exit with code A
exit_a: pha
        jsr     out_flush
        pla
        cop     SYS_EXIT

; the argument string a program starts with (X = offset in the window, A = length) -> u_p
args_init:
        stx     z:u_p
        stz     z:u_p+2
        rts

; ---------------------------------------------------------------- Atari software
; A = kind of file X, Y by its extension: 1 disk (.atr .xfd), 2 executable (.xex .com
; .exe), 3 cartridge (.car .rom .bin), 0 unknown. (The I/O processor's own rule.)
atari_kind:
        lda     #8 * 4                  ; (the table's first 8 entries)
        bra     ak_go
; (0.23) as atari_kind, and 4 (CK_BASRUN) for a BASIC program (.bas .lst): what "Run in
; Atari" (atari_run) can start
atari_rkind:
        lda     #10 * 4
ak_go:  sta     u_kend
        stx     z:u_s
        tya
        sta     z:u_s+2
        ldy     #0                      ; Y = the last '.'
        ldx     #$FFFF
:       lda     [u_s],y
        and     #$00FF
        beq     :++
        cmp     #'.'
        bne     :+
        tyx
:       iny
        bra     :--
:       stx     z:u_t                   ; exactly 3 characters after it?
        cpx     #$FFFF
        beq     @none
        tya
        sec
        sbc     z:u_t
        cmp     #4
        bne     @none
        ldx     #0                      ; compare with the table, upper case
@ext:   ldy     z:u_t
        iny
        lda     [u_s],y
        and     #$DFDF
        cmp     ext_tab,x
        bne     @next
        lda     ext_tab+2,x             ; third letter
        and     #$00FF
        sta     z:u_w
        iny
        iny
        lda     [u_s],y
        and     #$00DF
        cmp     z:u_w
        bne     @next
        lda     ext_tab+3,x
        and     #$00FF
        rts
@next:  inx
        inx
        inx
        inx
        cpx     u_kend
        bcc     @ext
@none:  lda     #0
        rts

; run Atari file X, Y: "start this, and only this". Ejects what would get in the way (a
; disk or executable ejects the cartridge; a cartridge ejects the executable and D1:;
; D2:-D4: stay), mounts it (D1: / executable / cartridge by its extension) and boots.
; (0.23) A BASIC program (.bas .lst, a listing or a tokenised Atari BASIC file): "Run in
; Atari": the cartridge ejected, mounted as CK_BASRUN (the I/O processor makes it the boot
; disk on D1:, in place of D1: and the executable), the Atari cold booted with BASIC on.
; Returns only on an error (C set, A = code) or after F12 (C clear). u_p is kept.
atari_run:
        stx     z:u_r
        tya
        sta     z:u_r+2
        jsr     atari_rkind
        sta     u_kind
        cmp     #3
        beq     @cart
        cmp     #0
        beq     @mount
        lda     #CK_CART                ; disk / executable / BASIC: no cartridge
        sys     SYS_CEJECT
        bra     @mount
@cart:  lda     #CK_XEX                 ; cartridge: no executable, nothing in D1:
        sys     SYS_CEJECT
        lda     #CK_DISK                ; (slot 0)
        sys     SYS_CEJECT
@mount: ldx     z:u_r
        ldy     z:u_r+2
        lda     u_kind                  ; BASIC: CK_BASRUN; else by extension, D1:
        cmp     #CK_BASRUN
        beq     :+
        lda     #0
:       sys     SYS_CMOUNT
        bcs     @out
        sys     SYS_CBOOT
@out:   rts

; ---------------------------------------------------------------- strings
; next argument at u_p (after spaces) -> X, Y (buffer of A bytes, zero-terminated).
; "Quoted text" may contain spaces. Returns A = length, Z set (and C set) if there was
; none; u_p is left after it.
next_arg:
        dec     a
        sta     z:u_max
        stx     z:u_d
        tya
        sta     z:u_d+2
        jsr     str_skip
        ldx     #0                      ; X = 1 inside quotes
        cmp     #0
        beq     @none
        cmp     #'"'
        bne     :+
        inx
        inc     z:u_p
:       ldy     #0
@loop:  lda     [u_p]
        and     #$00FF
        beq     @end
        cpx     #0
        bne     @inq
        cmp     #' '
        beq     @end
        bra     @ch
@inq:   cmp     #'"'
        bne     @ch
        inc     z:u_p                   ; closing quote
        bra     @end
@ch:    cpy     z:u_max
        bcs     :+
        sep     #$20
        .a8
        sta     [u_d],y
        rep     #$20
        .a16
        iny
:       inc     z:u_p
        bra     @loop
@end:   lda     #0
        sep     #$20
        .a8
        sta     [u_d],y
        rep     #$20
        .a16
        tya
        clc
        rts
@none:  lda     #0
        sep     #$20
        .a8
        sta     [u_d]
        rep     #$20
        .a16
        lda     #0
        sec
        rts

; u_p (long pointer) past spaces; A = the character there
str_skip:
:       lda     [u_p]
        and     #$00FF
        cmp     #' '
        bne     :+
        inc     z:u_p
        bra     :-
:       rts

; decimal number at u_p (after spaces) -> A, u_p past it. C set if there is no digit.
parse_dec:
        jsr     str_skip
        stz     z:u_t
        ldx     #0                      ; digits seen
@loop:  lda     [u_p]
        and     #$00FF
        sec
        sbc     #'0'
        bcc     @end
        cmp     #10
        bcs     @end
        pha
        lda     z:u_t                   ; u_t = u_t * 10 + digit
        asl     a
        sta     z:u_w
        asl     a
        asl     a
        clc
        adc     z:u_w
        sta     z:u_t
        pla
        clc
        adc     z:u_t
        sta     z:u_t
        inc     z:u_p
        inx
        bra     @loop
@end:   lda     z:u_t
        cpx     #1                      ; C clear if X >= 1 ... inverted below
        bcs     :+
        sec
        rts
:       clc
        rts

        .segment "RODATA"
; HID usages $04-$38, US layout
ktab:   .byte   "abcdefghijklmnopqrstuvwxyz"
        .byte   "1234567890"
        .byte   13, 27, 8, 9, ' '
        .byte   "-=[]\\", 0, ";'`,./"
ktab_shift:
        .byte   "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        .byte   "!@#$%^&*()"
        .byte   13, 27, 8, 9, ' '
        .byte   "_+{}|", 0, ":\"~<>?"

        .segment "RODATA"
ext_tab: .byte  "ATR", 1, "XFD", 1, "XEX", 2, "COM", 2, "EXE", 2, "CAR", 3, "ROM", 3, "BIN", 3
        .byte   "BAS", 4, "LST", 4      ; (0.23) atari_rkind only: CK_BASRUN

        .segment "BSS"
NHIST   = 8
HISTLEN = 127
hist:   .res    NHIST * 128
spblk:  .res    8
KEEPMAX = 80                            ; a shell line
u_keep: .res    KEEPMAX + 1                     ; (0.21) key_keep's characters
u_nkeep: .res   2
OUTMAX = 120
out_buf: .res   OUTMAX + 2
u_kend: .res    2                       ; (0.23) atari_kind's table end; atari_run's kind
u_kind: .res    2

        .segment "ZEROPAGE"
u_t:    .res    2
u_w:    .res    2
u_s:    .res    4
u_p:    .res    4
u_olen: .res    2
u_caps: .res    2
u_len:  .res    2
u_max:  .res    2
u_arg:  .res    4
u_d:    .res    4
u_r:    .res    4
u_pos:  .res    2
u_hcnt: .res    2
u_hsel: .res    2
