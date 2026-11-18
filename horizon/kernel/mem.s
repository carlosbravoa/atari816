; mem.s - 64 KB bank allocator, FREDDIE II bank table, user pointer checks, memory copy.
;
; bank_st[] holds one owner byte per bank and the FREDDIE II table always mirrors it:
;   BK_FREE   -> $00 (not valid)        BK_NONE -> $00, or $C0 for banks $00/$01 (kernel)
;   BK_KERNEL -> $C0 (valid, owner 0)   task id -> $C0 | id
; Free RAM for tasks: banks $02-$0F, $12-$1F, $40-$7F (and never above RAM_BANKS).

        .a16
        .i16

bank_init:
        ldx     #0
@loop:  lda     #BK_NONE
        cpx     #$02
        bcc     @set
        cpx     #$10
        bcc     @free
        cpx     #$12
        bcc     @set
        cpx     #$20
        bcc     @free
        cpx     #$40
        bcc     @set
        cpx     #$80
        bcs     @set
@free:  a8                              ; within the installed RAM?
        txa
        cmp     f:RAM_BANKS
        a16
        beq     :+
        bcs     @none
:       lda     #BK_FREE
        bra     @set
@none:  lda     #BK_NONE
@set:   jsr     bank_set
        inx
        cpx     #$100
        bne     @loop
        ldx     #FB_BANK                ; the screen's framebuffer
:       lda     #BK_KERNEL
        jsr     bank_set
        inx
        cpx     #FB_BANK + FB_NBANKS
        bne     :-
        rts

; bank X <- state A (low byte). Writes bank_st and the FREDDIE II entry. Keeps X.
bank_set:
        a8
        sta     bank_st,x
        jsr     pte_of
        pha
        txa
        sta     f:PT_INDEX
        pla
        sta     f:PT_DATA
        a16
        rts

; (a8) A = state, X = bank -> A = table entry
        .a8
pte_of: cmp     #BK_FREE
        beq     @inv
        cmp     #BK_KERNEL
        beq     @kern
        cmp     #BK_NONE
        bne     @task
        cpx     #$02                    ; banks $00/$01: kernel
        bcc     @kern
@inv:   lda     #0
        rts
@kern:  lda     #PTE_VALID | PTE_WRITE
        rts
@task:  ora     #PTE_VALID | PTE_WRITE
        rts
        .a16

; allocate the lowest free bank for owner A (task id or BK_KERNEL) -> A = bank, C set if none
bank_alloc:
        sta     kt6
        ldx     #2
@loop:  lda     bank_st,x
        and     #$00FF
        beq     @found
        inx
        cpx     #$80
        bne     @loop
        sec
        rts
@found: lda     kt6
        jsr     bank_set
        txa
        clc
        rts

; allocate A contiguous free banks for the kernel (the highest run below $7C)
; -> A = the first, C set if there is no such run. (0.18) The highest run below $70 first:
; banks $70-$7B are where the I/O processor puts a cartridge's image (its SDRAM from
; $400000, see mb_ptr in core/firmware/firmware.c), so they are taken last (classic.s)
bank_run:
        sta     kt6
        ldx     #CART_B0 - 1
        jsr     @try
        bcc     :+
        ldx     #$7B
        bra     @try
:       rts
@try:   txa
        sec
        sbc     kt6
        bmi     @none
        inc     a
        cmp     #2
        bcc     @none
        sta     kt4                     ; first = X - n + 1
        ldy     kt6
        phx
:       lda     bank_st,x
        and     #$00FF
        bne     @busy
        dex
        dey
        bne     :-
        plx
        ldx     kt4
        ldy     kt6
:       lda     #BK_KERNEL
        phy
        jsr     bank_set
        ply
        inx
        dey
        bne     :-
        lda     kt4
        clc
        rts
@busy:  plx
        dex
        bra     @try
@none:  sec
        rts

; free bank A (no checks)
bank_free:
        tax
        lda     #BK_FREE
        jmp     bank_set

; free every bank owned by task id A
banks_free_id:
        sta     kt6
        ldx     #2
@loop:  lda     bank_st,x
        and     #$00FF
        cmp     kt6
        bne     :+
        lda     #BK_FREE
        jsr     bank_set
:       inx
        cpx     #$80
        bne     @loop
        rts

; ---- user pointer check for the current task ----
; In: kt0 = offset, kt1 = bank (Y argument), kt2 = length, kt3 = 0 read / 1 write.
; Out: C clear and kphys = physical address, kt4 = end of the accessible region (offset,
; 0 = $10000); C set if any byte of the range is not accessible. A range never crosses a
; bank (or the end of the window).
uaccess:
        lda     kt1
        cmp     #$0100
        bcs     @bad
        cmp     #0
        bne     @bank
        ; bank 0: only the window $0000-$7FFF
        lda     kt0
        clc
        adc     kt2
        bcs     @bad
        cmp     #$8001
        bcs     @bad
        ldx     cur
        lda     t_wbank,x
        sta     kphys+2
        lda     #$8000
        sta     kt4
        bra     @ok
@bank:  lda     kt0
        clc
        adc     kt2
        bcc     :+
        bne     @bad                    ; beyond $10000
:       ldx     kt1
        lda     bank_st,x
        and     #$00FF
        a8
        jsr     pte_of
        a16
        and     #$00FF
        sta     kt5
        and     #PTE_VALID
        beq     @bad
        lda     kt5
        and     #$003F
        cmp     #63
        beq     :+
        ldy     cur
        cmp     t_id,y
        bne     @bad
:       lda     kt3
        beq     :+
        lda     kt5
        and     #PTE_WRITE
        beq     @bad
:       lda     kt1
        sta     kphys+2
        stz     kt4
@ok:    lda     kt0
        sta     kphys
        clc
        rts
@bad:   sec
        rts

; ---- copy a user path (X = offset, Y = bank) to kpath: absolute and normalised ----
; A relative path is taken from the task's current directory; "." and ".." components
; and repeated '/' are resolved here (the I/O processor's FatFs has no relative paths).
; The result is at most 127 characters. Returns C clear, or C set with A = EFAULT /
; EINVAL (too long).
copy_upath:
        jsr     copy_ustr
        bcs     @out
        ldx     #0                      ; (0.22) a URL ("scheme://..."): passed on as it is
:       lda     kpath,x
        and     #$00DF                  ; (letters: either case)
        cmp     #'A'
        bcc     :+
        cmp     #'Z' + 1
        bcs     :+
        inx
        bra     :-
:       cpx     #2
        bcc     @path
        lda     kpath,x
        cmp     #':' | ('/' << 8)
        bne     @path
        lda     kpath+2,x
        and     #$00FF
        cmp     #'/'
        bne     @path
        clc
        rts
@path:
        ldx     #126                    ; kpath -> kraw
:       lda     kpath,x
        sta     kraw,x
        dex
        dex
        bpl     :-
        jmp     path_resolve
@out:   rts

; kraw (with the current task's directory first, if relative) -> kpath, normalised
path_resolve:
        stz     kt0                     ; output length
        lda     kraw
        and     #$00FF
        cmp     #'/'
        beq     @raw
        lda     cur
        cmp     #NONE
        beq     @raw
        asl     a                       ; slot*2*64 = slot*128
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        clc
        adc     #.loword(t_cwd)
        tax
        jsr     @feed
        bcs     @long
@raw:   ldx     #.loword(kraw)
        jsr     @feed
        bcs     @long
        ldy     kt0
        bne     :+
        a8
        lda     #'/'
        sta     kpath
        a16
        ldy     #1
:       a8
        lda     #0
        sta     kpath,y
        a16
        clc
        rts
@long:  lda     #EINVAL
        sec
        rts

; append the components of the string at X (bank 1) to kpath[0 .. kt0)
@feed:  lda     a:0,x
        and     #$00FF
        bne     :+
        clc
        rts
:       cmp     #'/'
        bne     @comp
        inx
        bra     @feed
@comp:  stx     kt1                     ; component start
:       inx                             ; X = its end ('/' or 0)
        lda     a:0,x
        and     #$00FF
        beq     :+
        cmp     #'/'
        bne     :-
:       txa
        sec
        sbc     kt1
        sta     kt2                     ; length
        ldy     kt1
        cmp     #1
        bne     :+
        lda     a:0,y
        and     #$00FF
        cmp     #'.'
        beq     @feed                   ; "." : nothing
        bra     @add
:       cmp     #2
        bne     @add
        lda     a:0,y
        cmp     #'.' | ('.' << 8)
        bne     @add
        ldy     kt0                     ; ".." : drop the last component
        beq     @feed
:       dey
        beq     :+
        lda     kpath,y
        and     #$00FF
        cmp     #'/'
        bne     :-
:       sty     kt0
        bra     @feed
@add:   lda     kt0                     ; '/' + component, if it fits
        sec
        adc     kt2
        cmp     #128
        bcc     :+
        rts                             ; C set: too long
:       ldy     kt0
        a8
        lda     #'/'
        sta     kpath,y
        a16
        iny
        phx
        ldx     kt1
:       a8
        lda     a:0,x
        sta     kpath,y
        a16
        iny
        inx
        dec     kt2
        bne     :-
        plx
        sty     kt0
        jmp     @feed

; ---- copy a user string (X = offset, Y = bank) to kpath (128 bytes, zero-terminated) ----
; Returns C clear, or C set with A = EFAULT / EINVAL (longer than 127 characters).
copy_ustr:
        stx     kt0
        sty     kt1
        lda     #1
        sta     kt2
        stz     kt3
        jsr     uaccess
        bcs     @fault
        lda     kphys
        sta     kp1
        lda     kphys+2
        sta     kp1+2
        ldy     #0
@loop:  tya                             ; offset of byte Y still inside the region?
        clc
        adc     kt0
        bcs     @fault
        ldx     kt4
        beq     @get
        cmp     kt4
        bcs     @fault
@get:   a8
        lda     [kp1],y
        sta     kpath,y
        a16
        and     #$00FF
        beq     @done
        iny
        cpy     #128
        bne     @loop
        lda     #EINVAL                 ; too long
        sec
        rts
@done:  clc
        rts
@fault: lda     #EFAULT
        sec
        rts

; ---- memory copy with MVN: kt0/kt1 = source offset/bank, kt2/kt3 = destination, A = count ----
kmemcpy:
        cmp     #0
        beq     @out
        dec     a
        pha
        a8
        lda     kt3
        sta     mvn_op+1
        lda     kt1
        sta     mvn_op+2
        a16
        ldx     kt0
        ldy     kt2
        pla
        phb
        jsr     mvn_op
        plb
@out:   rts

; the same with MVP (overlapping, destination after the source): kt0 / kt2 = the LAST
; source / destination byte
kmemmove:
        cmp     #0
        beq     @out
        pha
        a8
        lda     #$44                    ; MVP
        sta     mvn_op
        a16
        pla
        jsr     kmemcpy
        a8
        lda     #$54                    ; MVN again
        sta     mvn_op
        a16
@out:   rts

; zero A bytes at kt2/kt3
kmemzero:
        cmp     #0
        beq     @out
        pha
        lda     kt2
        sta     kp2
        lda     kt3
        sta     kp2+2
        a8
        lda     #0
        sta     [kp2]
        a16
        pla
        dec     a
        beq     @out
        pha
        lda     kt2                     ; source = first byte, destination = next
        sta     kt0
        inc     kt2
        lda     kt3
        sta     kt1
        pla
        jmp     kmemcpy
@out:   rts
