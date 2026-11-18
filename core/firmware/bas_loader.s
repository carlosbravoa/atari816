; SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
; Copyright (c) 2026 Carlos Bravo
; bas_loader.s - the boot program of "Run in Atari" (step 3). The firmware serves it as the
; first sectors of a virtual disk on D1: (bas_loader.py makes bas_loader.h from it); the BASIC
; program follows from sector DATASEC on, as one stream of LEN bytes: an ATASCII listing (lines
; ending in $9B) or an Atari BASIC SAVE file. The classic machine boots it with BASIC enabled.
;
; At boot (the OS loads the sectors to $0700 and calls $0706):
;  - a "D:" handler goes into HATABS: read only, one file whatever the name: OPEN starts the
;    stream again, GET gives its bytes and then end of file (136);
;  - the screen editor's GET is hooked: BASIC's first input lines come from here instead of the
;    keyboard: ENTER "D:" and RUN (a listing) or RUN "D:" (a SAVE file). With the end of the
;    last line the hook is taken out again (the editor works as always: the program's INPUT,
;    the keyboard). Nothing of it is shown; BASIC shows its errors (a listing's bad lines) as
;    usual;
;  - MEMLO is raised above this program, so BASIC's memory starts after it.
; RESET (warm start): the OS rebuilds HATABS and calls DOSINI: MEMLO and the "D:" handler are
; set again (ENTER "D:" works again), the editor is not hooked again.
;
; The firmware patches: LEN (3 bytes, little-endian) at offset P_LEN, the mode (0 listing, 1
; SAVE file) at P_MODE. Assemble: ca65 bas_loader.s && ld65 -t none -o bas_loader.bin bas_loader.o
; (bas_loader.py does it).

HATABS  = $031A
MEMLO   = $02E7
DOSINI  = $000C
DUNIT   = $0301
DCOMND  = $0302
DBUFLO  = $0304
DAUX1   = $030A
DSKINV  = $E453
ICAX1Z  = $2A                   ; CIO's copy of the IOCB's AUX1 (zero page)

DATASEC = 5                     ; the stream's first sector (the loader is at most 4 sectors)

        .org    $0700
start:  .byte   0               ; boot flag
        .byte   NSEC            ; sectors to load
        .word   start           ; load address
        .word   warm            ; DOSINI (also run after the boot)
        ; $0706: the boot continuation
        ldx     #0
@find:  lda     HATABS,x        ; the editor's entry
        cmp     #'E'
        beq     @got
        inx
        inx
        inx
        cpx     #36
        bcc     @find
        bcs     @noe
@got:   stx     eidx
        lda     HATABS+1,x      ; its table: copied, GET replaced
        sta     eorg
        sta     $CB
        lda     HATABS+2,x
        sta     eorg+1
        sta     $CC
        ldy     #15
@cp:    lda     ($CB),y
        sta     etab,y
        dey
        bpl     @cp
        lda     #<(eget - 1)
        sta     etab+4
        lda     #>(eget - 1)
        sta     etab+5
        lda     #<etab
        sta     HATABS+1,x
        lda     #>etab
        sta     HATABS+2,x
@noe:   lda     mode            ; which input lines
        beq     :+
        lda     #lrun - lines
:       sta     epos
        jsr     warm
        clc
        rts

; DOSINI: MEMLO above us, the "D:" handler in HATABS (again after a RESET)
warm:   lda     #<endres
        sta     MEMLO
        lda     #>endres
        sta     MEMLO+1
        ldx     #0
@d:     lda     HATABS,x        ; an entry 'D' already, or the first free one
        cmp     #'D'
        beq     @set
        cmp     #0
        beq     @set
        inx
        inx
        inx
        cpx     #36
        bcc     @d
        rts
@set:   lda     #'D'
        sta     HATABS,x
        lda     #<dtab
        sta     HATABS+1,x
        lda     #>dtab
        sta     HATABS+2,x
dret:   rts

; ---- the editor's GET while hooked: the next byte of the input lines ----
eget:   stx     savex
        ldy     epos
        lda     lines,y
        iny
        sty     epos
        cmp     #$9B
        bne     @ok
        cpy     #lend0 - lines  ; the last line given: the editor is the editor again
        beq     @off
        cpy     #lend - lines
        bne     @ok
@off:   ldx     eidx
        lda     eorg
        sta     HATABS+1,x
        lda     eorg+1
        sta     HATABS+2,x
        lda     #$9B
@ok:    ldx     savex
        ldy     #1
        rts

; the lines: a listing: ENTER "D:" and RUN; a SAVE file: RUN "D:"
lines:  .byte   "ENTER ", $22, "D:", $22, $9B
        .byte   "RUN", $9B
lend0:
lrun:   .byte   "RUN ", $22, "D:", $22, $9B
lend:

; ---- the "D:" handler ----
dtab:   .word   dopen - 1, dok - 1, dget - 1, dnot - 1, dok - 1, dnot - 1
        jmp     dret

dopen:  lda     ICAX1Z          ; read only
        and     #$08
        bne     dnot
        lda     #DATASEC
        sta     secn
        lda     #0
        sta     secn+1
        lda     #128
        sta     bpos
        ldx     #2
:       lda     len,x
        sta     rem,x
        dex
        bpl     :-
dok:    ldy     #1
        rts
dnot:   ldy     #146            ; not implemented (writing)
        rts

dget:   stx     savex
        jsr     dget1
        ldx     savex
        rts
dget1:  lda     rem
        ora     rem+1
        ora     rem+2
        bne     :+
        ldy     #136            ; end of file
        rts
:       ldx     bpos
        bpl     @have
        lda     #1              ; the next sector
        sta     DUNIT
        lda     #$52
        sta     DCOMND
        lda     #<buf
        sta     DBUFLO
        lda     #>buf
        sta     DBUFLO+1
        lda     secn
        sta     DAUX1
        lda     secn+1
        sta     DAUX1+1
        jsr     DSKINV
        bpl     :+
        rts                     ; (Y = the SIO error)
:       inc     secn
        bne     :+
        inc     secn+1
:       ldx     #0
@have:  lda     rem             ; rem - 1
        bne     @lo
        lda     rem+1
        bne     @mid
        dec     rem+2
@mid:   dec     rem+1
@lo:    dec     rem
        lda     buf,x
        inx
        stx     bpos
        ldy     #1
        rts

; ---- data (patched by the firmware: len, mode) ----
len:    .byte   0, 0, 0         ; the stream's length
mode:   .byte   0               ; 0 a listing, 1 a SAVE file
eidx:   .byte   0
savex:  .byte   0
eorg:   .word   0
epos:   .byte   0
secn:    .word   0
bpos:   .byte   0
rem:    .byte   0, 0, 0
etab:   .res    16
endcode:
NSEC    = (endcode - start + 127) / 128
buf     = endcode               ; 128 bytes, not loaded
endres  = buf + 128

P_LEN   = len - start
P_MODE  = mode - start
.assert NSEC <= DATASEC - 1, error, "the loader is longer than its sectors"
.export P_LEN, P_MODE, NSEC
