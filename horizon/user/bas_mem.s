; bas_mem.s - variables, arrays, the string heap and its garbage collector, banks.
;
; Variables (bank VB): slot i at VB:8 i (VSLOTS): a number {lo, hi, type, len} (an integer:
; type 0; a float: {flo, fhi, ft, flen}, bas_fp.s), a % number {i32}, a string {u16 offset,
; u16 bank, u16 length}, an array {u16 offset, u16 bank} of its block (bank 0: not
; dimensioned yet). VB:VNAMEP + 2 i = its name record, VB:VKIND + i = its kind (0 number,
; 1 string, 2 number array, 3 string array). Name records {u16 next in the hash chain,
; u16 slot offset, u8 kind, u8 length, the name} from VB:VNAMES; 256 hash chains (sbucket).
; Names are made when a line is tokenized, so a program never looks a name up.
;
; Arrays (banks AB, filled from the bottom, freed by RUN / CLR / NEW): a block {u8 ndims,
; u8 element size, u16 elements, u16 size of each dimension}, then the elements, zeroed:
; 4 bytes {lo, hi} for integers, 6 for strings {offset, bank, length}, 8 for a tagged number
; array {lo, hi, type, len} (bas_expr.s). A number array starts with integers; the first
; float stored in it makes it tagged (arr_promote: a new block, the old one is left until
; RUN / CLR). A % array stays of integers. One block at most 64 KB.
; A subscript runs 0 .. n (DIM A(n) has n + 1 elements); an array used without DIM gets
; 0 .. 10 in each of the dimensions used.
;
; The string heap (banks SB): blocks {u16 length (bit 15: mark), u16 forward offset, u8
; forward bank, the bytes}, allocated upwards in the current bank. A string value points
; at the bytes. When the banks are full the collector runs:
;   1. mark: every string reachable from a root gets its mark (roots: the accumulator, the
;      value stack, string variables, string array elements);
;   2. walk the heap in order: each marked block gets its new place (packed from the start,
;      banks in order; a block never crosses a bank), stored in its header;
;   3. every root is pointed at the new place;
;   4. walk again and slide each marked block down (a block only ever moves down, so the
;      blocks not moved yet are intact), clearing its mark.
; Linear in the heap size; strings are immutable, so two variables may share one block.
; After a collection with less than a quarter of a bank free, a new bank is added (up to
; MAXSB).

        .segment "CODE"
        .a16
        .i16
VSLOTS  = $0000
VNAMEP  = $4000
VKIND   = $5000
VNAMES  = $6000
VNLIM   = $FFE0
MAXVAR  = 2048
MAXAB   = 32
ABLIM   = $FFF0
MAXSB   = 16
SBLIM   = $FFF0

; the banks of a new session -> C set: not enough memory
mem_init:
        phk
        phk
        pla
        and     #$00FF
        sta     codebk
        sys     SYS_BALLOC
        bcs     @no
        stz     z:vb
        sta     z:vb+2
        sta     z:vb4+2
        ldx     #4
        stx     z:vb4
        sys     SYS_BALLOC
        bcs     @no
        stz     z:ib
        sta     z:ib+2
        sta     z:ipt+2
        lda     #LPTR
        sta     z:ipt
        sys     SYS_BALLOC
        bcs     @no
        sta     cbank
        sys     SYS_BALLOC
        bcs     @no
        sta     fbank
        stz     z:fbp
        sta     z:fbp+2
        sys     SYS_BALLOC
        bcs     @no
        sta     sbk
        tax
        a8
        lda     #1
        sta     isheap,x
        a16
        lda     #2
        sta     nsbx2
        stz     stop
        stz     scur
        lda     #1
        sta     pgen
        sta     gcolor
        jsr     sym_reset
        sys     SYS_UPTIME
        ora     #1
        sta     rseed
        stx     rseed+2
        clc
        rts
@no:    sec
        rts

; ---------------------------------------------------------------- names
sym_reset:
        stz     nsym
        lda     #VNAMES
        sta     namep
        ldx     #0
:       stz     sbucket,x
        inx
        inx
        cpx     #512
        bcc     :-
        rts

; the name nbuf (nlen characters, with a '$' for strings) of kind A -> A = its slot's
; offset (made if new: E_VARS when full)
sym_find:
        sta     sf_kind
        lda     sf_kind                 ; hash = kind, then h * 5 + c for each character
        ldx     #0
:       cpx     nlen
        bcs     :+
        sta     z:gh
        asl     a
        asl     a
        clc
        adc     z:gh
        sta     z:gh
        lda     nbuf,x
        and     #$00FF
        clc
        adc     z:gh
        inx
        bra     :-
:       and     #$00FF
        asl     a
        sta     sf_h
        tax
        lda     sbucket,x
@chain: beq     @new
        sta     z:gp
        lda     z:vb+2
        sta     z:gp+2
        ldy     #4
        lda     [gp],y                  ; kind, length
        and     #$00FF
        cmp     sf_kind
        bne     @next
        ldy     #5
        lda     [gp],y
        and     #$00FF
        cmp     nlen
        bne     @next
        ldx     #0
        ldy     #6
:       cpx     nlen
        bcs     @hit
        lda     [gp],y
        and     #$00FF
        sta     z:gh
        lda     nbuf,x
        and     #$00FF
        cmp     z:gh
        bne     @next
        inx
        iny
        bra     :-
@hit:   ldy     #2
        lda     [gp],y
        rts
@next:  lda     [gp]
        bra     @chain
@new:   lda     nsym
        cmp     #MAXVAR
        jcs     @full
        lda     namep
        clc
        adc     nlen
        adc     #6
        jcs     @full
        cmp     #VNLIM
        jcs     @full
        lda     namep                   ; the record
        sta     z:gp
        lda     z:vb+2
        sta     z:gp+2
        ldx     sf_h
        lda     sbucket,x
        sta     [gp]
        lda     z:gp
        sta     sbucket,x
        lda     nsym
        asl     a
        asl     a
        asl     a
        ldy     #2
        sta     [gp],y
        lda     sf_kind
        ldy     #4
        a8
        sta     [gp],y
        lda     nlen
        iny
        sta     [gp],y
        ldx     #0
        iny
:       cpx     nlen
        bcs     :+
        lda     nbuf,x
        sta     [gp],y
        inx
        iny
        bra     :-
:       a16
        tya
        clc
        adc     namep
        sta     namep
        lda     nsym                    ; name pointer, kind
        asl     a
        clc
        adc     #VNAMEP
        tay
        lda     z:gp
        sta     [vb],y
        lda     nsym
        clc
        adc     #VKIND
        tay
        lda     sf_kind
        a8
        sta     [vb],y
        a16
        lda     nsym                    ; the slot, zeroed
        asl     a
        asl     a
        asl     a
        tay
        lda     #0
        sta     [vb],y
        iny
        iny
        sta     [vb],y
        iny
        iny
        sta     [vb],y
        iny
        iny
        sta     [vb],y
        inc     nsym
        lda     nsym
        dec     a
        asl     a
        asl     a
        asl     a
        rts
@full:  err     E_VARS

; slot offset A -> X = its name (zero-terminated, in snbuf)
sym_name:
        lsr     a
        lsr     a
        clc
        adc     #VNAMEP
        tay
        lda     [vb],y
        sta     z:gp
        lda     z:vb+2
        sta     z:gp+2
        ldy     #5
        lda     [gp],y
        and     #$00FF
        sta     z:gh
        ldx     #0
        ldy     #6
        a8
:       cpx     z:gh
        bcs     :+
        lda     [gp],y
        sta     snbuf,x
        inx
        iny
        bra     :-
:       stz     snbuf,x
        a16
        ldx     #.loword(snbuf)
        rts

; ---------------------------------------------------------------- RUN, CLR
; no values: variables zero / empty, arrays and strings gone; no loops; DATA from the start
clr_all:
        lda     nsym
        asl     a
        asl     a
        asl     a
        tax
        ldy     #0
        lda     #0
:       sty     z:gh
        cpx     z:gh
        beq     :+
        sta     [vb],y
        iny
        iny
        bra     :-
:       ldx     #0                      ; the array banks
:       cpx     nab
        bcs     :+
        phx
        txa
        asl     a
        tax
        lda     abk,x
        sys     SYS_BFREE
        plx
        inx
        bra     :-
:       stz     nab
        ldx     #2                      ; the string heap: its first bank, empty
:       cpx     nsbx2
        bcs     :+
        phx
        lda     sbk,x
        pha
        and     #$00FF
        tax
        a8
        stz     isheap,x
        a16
        pla
        sys     SYS_BFREE
        plx
        inx
        inx
        bra     :-
:       lda     #2
        sta     nsbx2
        stz     stop
        stz     scur
        stz     csp
        stz     vsp
        stz     dline
        stz     dptr
        rts

; ---------------------------------------------------------------- arrays
; DIM: dimkind (0 numbers, 1 strings), dimvar (slot), dimn (dimensions * 2), dimsz
arr_dim:
        ldy     dimvar
        iny
        iny
        lda     [vb],y
        beq     :+
        err     E_REDIM
:       lda     dimkind
        sta     ac_kind
        lda     dimvar
        sta     ac_var
        lda     dimn
        sta     ac_n
        ldx     #.loword(dimsz)
        ; fall through
; a block for slot ac_var: ac_kind (0 integers, 1 strings, 2 tagged numbers), ac_n / 2
; dimensions of the sizes at X -> gp
arr_create:
        stx     ac_sz
        lda     #1                      ; elements = the product
        sta     ac_tot
        ldy     #0
:       cpy     ac_n
        bcs     :+
        phy
        tya
        clc
        adc     ac_sz
        tax
        lda     a:0,x
        ldx     ac_tot
        jsr     umul16
        ply
        cpx     #0
        jne     @big
        sta     ac_tot
        iny
        iny
        bra     :-
:       lda     ac_tot                  ; bytes: elements * 4, 6 or 8, + 4 + 2 n
        asl     a
        jcs     @big
        sta     z:gh
        asl     a
        jcs     @big
        ldx     ac_kind
        beq     :+
        cpx     #2
        beq     @x8
        adc     z:gh
        jcs     @big
        bra     :+
@x8:    asl     a
        jcs     @big
:       sta     ac_ebytes
        clc
        adc     #4
        jcs     @big
        adc     ac_n
        jcs     @big
        cmp     #ABLIM
        jcs     @big
        sta     ac_bytes
        lda     nab                     ; room in the current bank?
        beq     @newb
        lda     aboff
        clc
        adc     ac_bytes
        bcs     @newb
        cmp     #ABLIM
        bcc     @take
@newb:  lda     nab
        cmp     #MAXAB
        jcs     @mem
        sys     SYS_BALLOC
        jcs     @mem
        sta     abcur
        pha
        lda     nab
        asl     a
        tax
        pla
        sta     abk,x
        inc     nab
        stz     aboff
@take:  lda     aboff
        sta     z:gp
        lda     abcur
        sta     z:gp+2
        lda     aboff
        clc
        adc     ac_bytes
        sta     aboff
        lda     ac_kind                 ; the header: ndims, element size 4 + 2 kind
        asl     a
        adc     #4
        xba
        sta     z:gh
        lda     ac_n
        lsr     a
        ora     z:gh
        sta     [gp]
        ldy     #2
        lda     ac_tot
        sta     [gp],y
        ldx     #0
        ldy     #4
:       cpx     ac_n
        bcs     :+
        phx
        txa
        clc
        adc     ac_sz
        tax
        lda     a:0,x
        plx
        sta     [gp],y
        inx
        inx
        iny
        iny
        bra     :-
:       lda     ac_ebytes               ; the elements: zero
        sty     z:gh
        clc
        adc     z:gh
        sta     z:gh
        lda     #0
:       cpy     z:gh
        bcs     :+
        sta     [gp],y
        iny
        iny
        bra     :-
:       ldy     ac_var                  ; the slot
        lda     z:gp
        sta     [vb],y
        iny
        iny
        lda     z:gp+2
        sta     [vb],y
        rts
@big:   err     E_MEM
@mem:   err     E_MEM

; slot A (an array of X = 0 numbers / 1 strings), tp at "(": the subscripts -> ap = the
; element, A = its size (4, 6, 8) (Subscript out of range). One subscript is the fast way; more go on the value stack.
arr_elem:
        pha
        phx
        lda     [tp]
        and     #$00FF
        cmp     #'('
        jne     syn_err
        inc     z:tp
        jsr     eval_int
        lda     [tp]
        and     #$00FF
        cmp     #')'
        jne     @multi
        inc     z:tp
        plx
        stx     ae_kind
        pla
        sta     ae_slot
        lda     fhi
        jne     @bad
@one:   ldy     ae_slot                 ; the block
        iny
        iny
        lda     [vb],y
        beq     @auto1
        sta     z:gp+2
        ldy     ae_slot
        lda     [vb],y
        sta     z:gp
        lda     flo
        ldy     #4
        cmp     [gp],y
        jcs     @bad
        lda     [gp]
        cmp     #$0401                  ; one dimension of integers (the fast way)
        bne     @o1
        lda     flo
        asl     a                       ; + 6 + index * 4 (6, 8)
        asl     a
        adc     #6
        adc     z:gp
        sta     z:ap
        lda     z:gp+2
        sta     z:ap+2
        lda     #4
        rts
@o1:    tax
        and     #$00FF
        cmp     #1
        jne     @bad
        txa
        xba
        and     #$00FF
        sta     ae_esz
        lda     flo
        asl     a
        asl     a
        ldx     ae_esz
        cpx     #6
        bne     @o8
        clc
        adc     flo
        adc     flo
        bra     :+
@o8:    asl     a
:       adc     #6
        adc     z:gp
        sta     z:ap
        lda     z:gp+2
        sta     z:ap+2
        lda     ae_esz
        rts
@auto1: lda     ae_kind                 ; (not dimensioned: 0 .. 10)
        sta     ac_kind
        lda     ae_slot
        sta     ac_var
        lda     #2
        sta     ac_n
        pei     (flo)
        ldx     #.loword(adsz)
        jsr     arr_create
        pla
        sta     flo
        brl     @one
@multi: lda     vsp                     ; several: on the value stack
        sta     ae_base
        lda     fhi
        jne     @bad
        jsr     vpush
@i:     lda     [tp]
        and     #$00FF
        cmp     #','
        bne     :+
        inc     z:tp
        lda     ae_base
        pha
        jsr     eval_int
        pla
        sta     ae_base
        lda     fhi
        jne     @bad
        jsr     vpush
        bra     @i
:       lda     #')'
        jsr     expect
        plx
        stx     ae_kind
        pla
        sta     ae_slot
        lda     vsp
        sec
        sbc     ae_base
        lsr     a
        lsr     a
        sta     ae_n                    ; dimensions * 2
        ldy     ae_slot
        iny
        iny
        lda     [vb],y
        bne     @have
        lda     ae_kind                 ; not dimensioned: 0 .. 10 each
        sta     ac_kind
        lda     ae_slot
        sta     ac_var
        lda     ae_n
        sta     ac_n
        cmp     #9
        jcs     @bad
        ldx     #.loword(adsz)
        jsr     arr_create
        ldy     ae_slot
        iny
        iny
        lda     [vb],y
@have:  sta     z:gp+2
        ldy     ae_slot
        lda     [vb],y
        sta     z:gp
        lda     [gp]                    ; dimensions match?
        and     #$00FF
        asl     a
        cmp     ae_n
        bne     @bad
        stz     ae_lin
        ldx     ae_base
        ldy     #4
@d:     cpx     vsp
        bcs     @addr
        lda     vstk+2,x                ; the subscript < the size?
        cmp     [gp],y
        bcs     @bad
        sta     ae_i
        phx
        phy
        lda     [gp],y
        ldx     ae_lin
        jsr     umul16
        clc
        adc     ae_i
        sta     ae_lin
        ply
        plx
        iny
        iny
        txa
        clc
        adc     #8
        tax
        bra     @d
@addr:  lda     ae_base
        sta     vsp
        sty     z:gh                    ; (Y = the elements' start: 4 + 2 n)
        lda     [gp]
        xba
        and     #$00FF
        sta     ae_esz
        lda     ae_lin
        asl     a
        asl     a
        ldx     ae_esz
        cpx     #4
        beq     :+
        cpx     #8
        beq     @a8
        clc
        adc     ae_lin
        adc     ae_lin
        bra     :+
@a8:    asl     a
:       clc
        adc     z:gh
        clc
        adc     z:gp
        sta     z:ap
        lda     z:gp+2
        sta     z:ap+2
        lda     ae_esz
        rts
@bad:   err     E_SUBS

; the number array of integers that holds the element ap made tagged: a new block of 8-byte
; elements, the integers copied; ap = the same element in it (Out of memory beyond 64 KB)
arr_promote:
        stz     gi                      ; which array? (a number array whose block holds ap)
@s:     lda     gi
        cmp     nsym
        bcc     :+
        err     E_SUBS                  ; (never)
:       clc
        adc     #VKIND
        tay
        lda     [vb],y
        and     #$00FF
        cmp     #2
        bne     @n
        lda     gi
        asl     a
        asl     a
        asl     a
        sta     pr_slot
        tay
        iny
        iny
        lda     [vb],y
        cmp     z:ap+2
        bne     @n
        sta     z:gq+2
        dey
        dey
        lda     [vb],y
        sta     z:gq
        cmp     z:ap
        bcs     @n
        lda     [gq]
        cmp     #$0400                  ; (integers)
        bcc     @n
        cmp     #$0500
        bcs     @n
        and     #$00FF                  ; its elements: 4 + 2 n ..
        asl     a
        adc     #4
        sta     pr_hdr
        ldy     #2
        lda     [gq],y
        asl     a
        asl     a
        adc     pr_hdr
        adc     z:gq
        cmp     z:ap
        beq     @n
        bcs     @hit
@n:     inc     gi
        bra     @s
@hit:   lda     z:ap                    ; the index
        sec
        sbc     z:gq
        sec
        sbc     pr_hdr
        lsr     a
        lsr     a
        sta     pr_idx
        lda     [gq]                    ; its dimensions
        and     #$00FF
        asl     a
        sta     ac_n
        ldx     #0
        ldy     #4
:       cpx     ac_n
        bcs     :+
        lda     [gq],y
        sta     pr_dims,x
        inx
        inx
        iny
        iny
        bra     :-
:       sty     pr_hdr
        ldy     #2
        lda     [gq],y
        sta     pr_n
        lda     #2
        sta     ac_kind
        lda     pr_slot
        sta     ac_var
        ldx     #.loword(pr_dims)
        jsr     arr_create              ; -> gp
        lda     z:gq
        clc
        adc     pr_hdr
        sta     z:gq
        lda     z:gp
        clc
        adc     pr_hdr
        sta     z:gr
        lda     z:gp+2
        sta     z:gr+2
@c:     lda     pr_n
        beq     @done
        lda     [gq]
        sta     [gr]
        ldy     #2
        lda     [gq],y
        sta     [gr],y
        lda     z:gq
        clc
        adc     #4
        sta     z:gq
        lda     z:gr
        clc
        adc     #8
        sta     z:gr
        dec     pr_n
        bra     @c
@done:  lda     pr_idx
        asl     a
        asl     a
        asl     a
        clc
        adc     pr_hdr
        adc     z:gp
        sta     z:ap
        lda     z:gp+2
        sta     z:ap+2
        rts

; the PEEK / POKE memory -> ep (bank KB, offset 0): made zero on first use
kb_get: lda     kbank
        bne     :+
        sys     SYS_BALLOC
        bcc     @ok
        err     E_MEM
@ok:    sta     kbank
        sta     z:ep+2
        stz     z:ep
        ldy     #0
        lda     #0
@z:     sta     [ep],y
        iny
        iny
        bne     @z
        lda     kbank
:       sta     z:ep+2
        stz     z:ep
        rts

; ---------------------------------------------------------------- the string heap
; A bytes -> ap = a new string's bytes (the collector may run: every string a caller
; still needs must be in acc or on the value stack). Keeps t0-t7, bp, cp, dp, ep.
str_alloc:
        sta     sa_len
        clc
        adc     #5
        sta     sa_size
        stz     sa_gc
@try:   ldx     scur
        lda     stop,x
        clc
        adc     sa_size
        bcs     @full
        cmp     #SBLIM
        bcs     @full
        lda     stop,x
        sta     z:ap
        lda     sbk,x
        sta     z:ap+2
        lda     sa_len
        sta     [ap]
        lda     stop,x
        clc
        adc     sa_size
        sta     stop,x
        lda     z:ap
        clc
        adc     #5
        sta     z:ap
        rts
@full:  lda     scur                    ; a later bank (empty since the last collection)
        inc     a
        inc     a
        cmp     nsbx2
        bcs     :+
        sta     scur
        bra     @try
:       lda     sa_gc
        bne     @grow
        inc     sa_gc
        jsr     gc
        ldx     scur                    ; little room left: a new bank as well
        lda     stop,x
        cmp     #$C000
        bcc     @try
        txa
        inc     a
        inc     a
        cmp     nsbx2
        bcc     @try
@grow:  lda     nsbx2
        cmp     #MAXSB * 2
        bcs     @mem
        sys     SYS_BALLOC
        bcs     @mem
        ldx     nsbx2
        sta     sbk,x
        stz     stop,x
        stx     scur
        inx
        inx
        stx     nsbx2
        tax
        a8
        lda     #1
        sta     isheap,x
        a16
        jmp     @try
@mem:   lda     sa_gc                   ; (collect once more before giving up)
        bne     :+
        inc     sa_gc
        jsr     gc
        jmp     @try
:       err     E_MEM

; the garbage collector (see the top of this file)
gc:     stz     gcmode                  ; 1. mark
        jsr     gc_roots
        stz     gd                      ; 2. forward
        stz     gdoff
        stz     gs
@b:     lda     gs
        cmp     nsbx2
        jcs     @upd
        tax
        lda     sbk,x
        sta     z:gp+2
        stz     z:gp
        lda     stop,x
        sta     gtop
@blk:   lda     z:gp
        cmp     gtop
        bcs     @nb
        lda     [gp]
        sta     gl
        and     #$7FFF
        clc
        adc     #5
        sta     gsz
        lda     gl
        bpl     @skip
        lda     gdoff                   ; its place
        clc
        adc     gsz
        bcs     :+
        cmp     #SBLIM
        bcc     @ok
:       ldx     gd
        lda     gdoff
        sta     newtop,x
        inx
        inx
        stx     gd
        stz     gdoff
@ok:    lda     gdoff
        clc
        adc     #5
        ldy     #2
        sta     [gp],y
        ldx     gd
        lda     sbk,x
        ldy     #4
        a8
        sta     [gp],y
        a16
        lda     gdoff
        clc
        adc     gsz
        sta     gdoff
@skip:  lda     z:gp
        clc
        adc     gsz
        sta     z:gp
        bra     @blk
@nb:    inc     gs
        inc     gs
        brl     @b
@upd:   ldx     gd
        lda     gdoff
        sta     newtop,x
        lda     #1                      ; 3. the roots to the new places
        sta     gcmode
        jsr     gc_roots
        stz     gs                      ; 4. slide
@mb:    lda     gs
        cmp     nsbx2
        bcs     @fin
        tax
        lda     sbk,x
        sta     z:gp+2
        stz     z:gp
        lda     stop,x
        sta     gtop
@mblk:  lda     z:gp
        cmp     gtop
        bcs     @mnb
        lda     [gp]
        sta     gl
        and     #$7FFF
        clc
        adc     #5
        sta     gsz
        lda     gl
        bpl     @mskip
        ldy     #2
        lda     [gp],y
        sec
        sbc     #5
        sta     z:gq
        ldy     #4
        lda     [gp],y
        and     #$00FF
        sta     z:gq+2
        ldy     #0
        a8
:       lda     [gp],y
        sta     [gq],y
        iny
        cpy     gsz
        bcc     :-
        a16
        lda     gl
        and     #$7FFF
        sta     [gq]
@mskip: lda     z:gp
        clc
        adc     gsz
        sta     z:gp
        bra     @mblk
@mnb:   inc     gs
        inc     gs
        bra     @mb
@fin:   ldx     #0                      ; 5. the new tops
@t:     cpx     nsbx2
        bcs     @tend
        cpx     gd
        beq     @tcur
        bcs     @tz
        lda     newtop,x
        bra     @tset
@tcur:  lda     gdoff
        bra     @tset
@tz:    lda     #0
@tset:  sta     stop,x
        inx
        inx
        bra     @t
@tend:  lda     gd
        sta     scur
        rts

; every root through gc_one
gc_roots:
        lda     ft                      ; the accumulator (in the direct page: bank 0)
        cmp     #T_STR
        bne     :+
        lda     #flo
        sta     z:gr
        stz     z:gr+2
        jsr     gc_one
:       ldx     #0                      ; the value stack
@v:     cpx     vsp
        bcs     @vars
        lda     vstk,x
        cmp     #T_STR
        bne     :+
        txa
        clc
        adc     #.loword(vstk+2)
        sta     z:gr
        lda     codebk
        sta     z:gr+2
        phx
        jsr     gc_one
        plx
:       txa
        clc
        adc     #8
        tax
        bra     @v
@vars:  stz     gi                      ; the variables
@s:     lda     gi
        cmp     nsym
        bcs     @out
        clc
        adc     #VKIND
        tay
        lda     [vb],y
        and     #$00FF
        cmp     #1
        beq     @str
        cmp     #3
        beq     @sarr
@n:     inc     gi
        bra     @s
@str:   lda     gi
        asl     a
        asl     a
        asl     a
        sta     z:gr
        lda     z:vb+2
        sta     z:gr+2
        jsr     gc_one
        bra     @n
@sarr:  lda     gi                      ; a string array: each element
        asl     a
        asl     a
        asl     a
        tay
        iny
        iny
        lda     [vb],y
        beq     @n
        sta     z:gr+2
        dey
        dey
        lda     [vb],y
        sta     z:gr
        ldy     #2
        lda     [gr],y
        sta     gcnt
        lda     [gr]
        and     #$00FF
        asl     a
        clc
        adc     #4
        adc     z:gr
        sta     z:gr
@e:     lda     gcnt
        beq     @n
        dec     gcnt
        jsr     gc_one
        lda     z:gr
        clc
        adc     #6
        sta     z:gr
        bra     @e
@out:   rts

; the string descriptor at gr {offset, bank, length}: mark its block (gcmode 0) or point it
; at the block's new place (gcmode 1). Not in the heap (literals, empty): nothing.
gc_one: ldy     #4
        lda     [gr],y
        beq     @out
        ldy     #2
        lda     [gr],y
        and     #$00FF
        tax
        lda     isheap,x
        and     #$00FF
        beq     @out
        lda     [gr]
        sec
        sbc     #5
        sta     z:gh
        ldy     #2
        lda     [gr],y
        sta     z:gh+2
        lda     gcmode
        bne     @upd
        lda     [gh]
        ora     #$8000
        sta     [gh]
@out:   rts
@upd:   ldy     #2
        lda     [gh],y
        sta     [gr]
        ldy     #4
        lda     [gh],y
        and     #$00FF
        ldy     #2
        sta     [gr],y
        rts

        .segment "BSS"
fbank:  .res    2
kbank:  .res    2
nsym:   .res    2
namep:  .res    2
sf_kind: .res   2
sf_h:   .res    2
sbucket: .res   512
snbuf:  .res    40
nab:    .res    2
abcur:  .res    2
aboff:  .res    2
abk:    .res    MAXAB * 2
ac_kind: .res   2
ac_var: .res    2
ac_n:   .res    2
ac_sz:  .res    2
ac_tot: .res    2
ac_ebytes: .res 2
ac_bytes: .res  2
ae_base: .res   2
ae_kind: .res   2
ae_slot: .res   2
ae_n:   .res    2
ae_lin: .res    2
ae_esz: .res    2               ; the element's size (4, 6, 8)
ae_idx: .res    2               ; its index in the array
pr_dims: .res   8
pr_hdr: .res    2
pr_slot: .res   2
pr_idx: .res    2
pr_n:   .res    2
ae_i:   .res    2
nsbx2:  .res    2               ; heap banks * 2
scur:   .res    2               ; the bank being filled (index * 2)
sbk:    .res    MAXSB * 2
stop:   .res    MAXSB * 2
newtop: .res    MAXSB * 2
isheap: .res    256
sa_len: .res    2
sa_size: .res   2
sa_gc:  .res    2
gcmode: .res    2
gd:     .res    2
gdoff:  .res    2
gs:     .res    2
gtop:   .res    2
gl:     .res    2
gsz:    .res    2
gi:     .res    2
gcnt:   .res    2

        .segment "RODATA"
adsz:   .word   11, 11, 11, 11
