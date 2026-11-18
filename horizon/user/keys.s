; KEYS - claims the keyboard (or uses it when lent by its parent), prints three key
; events, releases it.
        .include "horizon.inc"
        .segment "CODE"
        .a16
        .i16
start:  sys     SYS_ICLAIM
        jcs     @bad
        print   "keys: press 3 keys\n"
        lda     #3
        sta     z:n
@loop:  sys     SYS_IREAD
        jcs     @bad
        stx     z:mods
        pha
        print   "keys: usage $"
        pla
        jsr     put_hex8
        print   " mods $"
        lda     z:mods
        jsr     put_hex8
        lda     z:mods+1
        and     #$01
        beq     :+
        print   " down\n"
        bra     :++
:       print   " up\n"
:       dec     z:n
        bne     @loop
        sys     SYS_IRELEASE
        exit    0
@bad:   print   "keys: FAILED\n"
        exit    1

        .segment "ZEROPAGE"
n:      .res    2
mods:   .res    2
