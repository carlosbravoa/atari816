; fast.s - the simulator's hottest loops in 65816 assembly (the Atari816 build only; the
; PC's twins run the C they replace, which stays in the engine). Each gives exactly the
; C's results: make test compares the whole state with the PC's twins every 100 ticks.
;
; Copyright (C) 2026 the Atari816 project. GPL-3 with EA's additional terms.
        .p816
        .a16
        .i16
        .include "model.inc"
        .importzp __rg

ANIMBIT = $0800
LOMASK  = $03FF

; void port_animate(unsigned short __far *map, unsigned n, const short __far *table)
; g_ani.c's animateTiles: every one of the n words with ANIMBIT becomes table[its low 10
; bits] with its upper 6 bits kept. The map with DBR (a far block: one bank), the table
; long indirect (only the animated tiles read it). About 20 cycles a tile not animated.
        FUNC _port_animate
        lda     ARGS,s
        sta     __rg+0                  ; the map's offset
        lda     ARGS+2,s
        sta     __rg+2                  ; its bank
        lda     ARGS+4,s
        asl     a
        clc
        adc     __rg+0
        sta     __rg+8                  ; the end's offset
        lda     ARGS+6,s
        sta     __rg+4                  ; the table, far
        lda     ARGS+8,s
        sta     __rg+6
        phb
        sep     #$20
        .a8
        lda     __rg+2
        pha
        plb                             ; DBR = the map's bank
        rep     #$20
        .a16
        ldx     __rg+0
        cpx     __rg+8
        bcs     @done
@loop:  lda     a:0,x
        bit     #ANIMBIT
        bne     @anim
@next:  inx
        inx
        cpx     __rg+8
        bcc     @loop
@done:  plb
        RET
@anim:  sta     __rg+10                 ; the tile
        and     #LOMASK
        asl     a
        tay
        lda     [__rg+4],y              ; table[tile & LOMASK]
        sta     __rg+12
        lda     __rg+10
        and     #($FFFF ^ LOMASK)       ; ALLBITS: the upper 6 bits
        ora     __rg+12
        sta     a:0,x
        bra     @next

; unsigned sim_rand(void) - rand.c's: next = next * 1103515245 + 12345 (32 bits), the
; result bits 8-23 of next. The product from port_rand_tab[b] = b * 1103515245 for each
; byte b of next (rand.c makes the table): next * C = T[n0] + T[n1] << 8 + T[n2] << 16
; + T[n3] << 24 (mod 2^32). About 100 cycles; cc816's __mul32 about 500.
        .import _port_rand_next, _port_rand_tab
        FUNC _sim_rand
        lda     _port_rand_next
        and     #$00FF
        asl     a
        asl     a
        tax                             ; n0 * 4
        lda     _port_rand_next
        xba
        and     #$00FF
        asl     a
        asl     a
        tay                             ; n1 * 4
        lda     _port_rand_tab,y        ; T1's bytes 0-1
        xba
        and     #$FF00                  ; T1 << 8: its low word
        clc
        adc     _port_rand_tab,x        ; + T0's low word
        sta     __rg+0
        lda     _port_rand_tab+2,x      ; T0's high word
        adc     _port_rand_tab+1,y      ; + T1's bytes 1-2 (T1 << 8: its high word), carry
        sta     __rg+2
        lda     _port_rand_next+2
        and     #$00FF
        asl     a
        asl     a
        tax                             ; n2 * 4
        lda     _port_rand_next+2
        xba
        and     #$00FF
        asl     a
        asl     a
        tay                             ; n3 * 4
        lda     _port_rand_tab,y
        xba
        and     #$FF00                  ; T3 << 24: its high word
        clc
        adc     _port_rand_tab,x        ; + T2 << 16: its high word (T2's low word)
        clc
        adc     __rg+2
        sta     __rg+2
        lda     __rg+0                  ; + 12345
        clc
        adc     #12345
        sta     _port_rand_next
        lda     __rg+2
        adc     #0
        sta     _port_rand_next+2
        lda     _port_rand_next+1       ; bits 8-23
        RET
