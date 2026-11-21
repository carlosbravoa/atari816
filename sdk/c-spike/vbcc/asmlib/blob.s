; blob.s - ca65 side of the "assembly library as a blob" proof: ulib (an ld65 object, ca65
; syntax) linked by ld65 into one block at code bank $0100, with a jump table that vbcc C
; calls with JSL. tools/o65blob.py turns ld65's o65 output into the raw block plus the list
; of its bank bytes; ulibwrap.s puts the block first in the C program's text.
;
; vbcc (large model) calls an entry with JSL: first argument in A (a 32-bit pointer: A =
; offset, X = bank), result in A; DBR = the code bank, D = 0, 16-bit registers: what
; ulib expects. ulib's direct page variables are linked at $50.. (blob.cfg), above vbcc's
; r0..r31 and btmp0..3 ($00..$4F).

        .p816
        .smart  off
        .include "horizon.inc"

        .segment "BLOBHDR"
        .a16
        .i16
        .byte   $4C, $FF, $FF           ; JMP to the C startup: ulibwrap.s puts its own here

; the jump table: 4 bytes an entry, in this order (ulibwrap.s has the offsets)
        jsr     b_puts                  ; +3  void ul_puts(const char *s)
        rtl
        jsr     put_dec                 ; +7  void ul_putdec(unsigned v)
        rtl
        jsr     out_flush               ; +11 void ul_flush(void)
        rtl
        jsr     put_hex16               ; +15 void ul_puthex(unsigned v)
        rtl

        .segment "CODE"
b_puts: txy                             ; C: A = offset, X = bank; ulib: X = offset, Y = bank
        tax
        jmp     put_str
