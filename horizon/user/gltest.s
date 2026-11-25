; GLTEST - (0.31) the line editor's test (make test: tests/gltest.keys, tests/gltest.py).
; Reads lines with ulib's getline into a 256-byte buffer (255 characters at most) and prints
; each as "gltest: N: TEXT" (N its length); an empty line ends it. (ctrl-C prints "gltest:
; ctrl-C" and goes on when the keyboard is its own; started by the shell, ctrl-C kills it.)
; Not on the card: the test copies it there (/GLTEST.PRG).
        .include "horizon.inc"

BUFSIZE = 256

        .segment "CODE"
        .a16
        .i16
start:  print   "gltest: type lines ("
        sys     SYS_CSIZE
        jsr     put_dec
        print   " columns)\n"
@loop:  print   "? "
        ptr     line
        lda     #BUFSIZE
        jsr     getline
        bcs     @brk
        sta     z:n
        cmp     #0
        beq     @end
        print   "gltest: "
        lda     z:n
        jsr     put_dec
        print   ": "
        ptr     line
        jsr     out_str
        jsr     put_nl
        jmp     @loop
@brk:   print   "gltest: ctrl-C\n"
        jmp     @loop
@end:   print   "gltest: done\n"
        exit    0

        .segment "BSS"
line:   .res    BUFSIZE + 2

        .segment "ZEROPAGE"
n:      .res    2
