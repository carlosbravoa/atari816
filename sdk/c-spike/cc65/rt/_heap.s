;
; Ullrich von Bassewitz, 03.06.1998 - heap variables and initialization.
;
; Atari816/Horizon: cc65's version initialises the heap pointers with
; ".word __BSS_RUN__+__BSS_SIZE__". ld65's o65 output stores that linker-generated value
; without the segment base ($01DD for a bss of $1DD bytes, not $137B), so the heap would
; start inside the program's code. Here the start is a label in the segment HEAPSTART,
; which the linker config (hz/horizon.cfg) puts after BSS: an ordinary, relocated address.

        .constructor    initheap, 24
        .import         __STACKSIZE__
        .importzp       c_sp

        .include        "_heap.inc"

.data

___heaporg:     .word   0
___heapptr:     .word   0
___heapend:     .word   0
___heapfirst:   .word   0
___heaplast:    .word   0

.segment        "HEAPSTART"
heapstart:

.segment        "ONCE"

initheap:
        lda     #<heapstart
        sta     ___heaporg
        sta     ___heapptr
        lda     #>heapstart
        sta     ___heaporg+1
        sta     ___heapptr+1
        sec
        lda     c_sp
        sbc     #<__STACKSIZE__
        sta     ___heapend
        lda     c_sp+1
        sbc     #>__STACKSIZE__
        sta     ___heapend+1
        rts
