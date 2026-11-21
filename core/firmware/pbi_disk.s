; SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
; Copyright (c) 2026 Carlos Bravo
; pbi_disk.s - the ROM of the classic machine's PBI disk ($D800-$DFFF while the OS has the
; device selected; see core/README.md, "Fast disk").
;
; The XL operating system offers every SIO call (SIOV, $E459) to the parallel bus devices
; before it uses the serial port: it selects each device in PDVMSK ($D1FF), calls $D805, and
; takes the call as done when that returns with carry set and the status in Y. This device
; answers "read a sector" and "status" of D1:-D8: when the I/O processor has a disk there:
; it asks the I/O processor, which leaves the bytes in this ROM's last page, and copies them
; to the caller's buffer. No serial transfer: about 3 ms a sector instead of 90. Anything
; else (writes, format, other devices, a drive the I/O processor does not have) is declined
; and goes over the serial port as before; so does a program with its own serial routines.
;
; Assembled by pbi_disk.py into pbi_disk.h (kept in the repository).

DDEVIC  = $0300
DCOMND  = $0302
DSTATS  = $0303
DBUFLO  = $0304
DBUFHI  = $0305
DBYTLO  = $0308
PDVMSK  = $0247
BUFRLO  = $32                   ; SIO's own pointer (free during a call it never sees)
PBIREQ  = $D1FE                 ; W: bit 0 = the request bit

        .org    $D800
        .word   0               ; checksum (not checked by the OS)
        .byte   1               ; revision
        .byte   $80             ; ID 1
        .byte   0               ; device type
        jmp     sio             ; $D805 SIO
        jmp     irq             ; $D808 interrupt
        .byte   $91             ; $D80B ID 2
        .byte   0               ; $D80C no CIO device name
        .word   nocio-1, nocio-1, nocio-1, nocio-1, nocio-1, nocio-1
        jmp     init            ; $D819

init:   lda     PDVMSK          ; device 0 is here
        ora     #$01
        sta     PDVMSK
irq:    rts
nocio:  clc
        rts

sio:    lda     DDEVIC
        cmp     #$31
        bne     no
        lda     DCOMND
        cmp     #'R'
        beq     ask
        cmp     #'S'
        bne     no
ask:    lda     P_DONE          ; the request bit := not the served bit
        eor     #$01
        sta     PBIREQ
:       cmp     P_DONE          ; until the I/O processor has served it
        bne     :-
        ldy     P_RESULT        ; 0 not mine, 1 the bytes are in P_BUF, $80+ an SIO error
        beq     no
        bmi     done
        lda     DBUFLO
        sta     BUFRLO
        lda     DBUFHI
        sta     BUFRLO+1
        ldy     #0
:       lda     P_BUF,y
        sta     (BUFRLO),y
        iny
        cpy     DBYTLO          ; 4, 128 or 0 = 256 (checked by the I/O processor)
        bne     :-
        ldy     #1
done:   sty     DSTATS
        sec
        rts
no:     clc
        rts

        .res    $DEF0 - *, $FF
P_DONE:   .byte 0               ; written by the I/O processor
P_RESULT: .byte 0
        .res    $DF00 - *, $FF
P_BUF:  .res    256, 0
