; GREET - console program template for Horizon (Atari816).
;
; Shows: the argument string, printing text and numbers (ulib), reading a line from the
; keyboard (getline), a file written and read back, the exit code.
;
;   > greet one "two words" three
;   Hello from task 5. Up for 3 s.
;   argument 1: one
;   ...
;   What is your name? Ada
;   Hello, Ada! Your name has 3 letters.
;   GREET.LOG now has 1 line(s).
;
; Run it from the text shell (or in the Desktop's Terminal). Build: make; run: make run.

        .include "horizon.inc"          ; syscall numbers, macros: sys, print, ptr, exit

        .segment "CODE"
        .a16                            ; a program starts with A, X, Y 16-bit (P = $00)
        .i16

start:  sta     z:alen                  ; A = length of the argument string,
        jsr     args_init               ; X = where it is (bank 0): ulib's u_p points at it

; ---- who and when
        print   "Hello from task "
        sys     SYS_GETPID              ; -> A = task id
        jsr     put_dec                 ; prints A as an unsigned decimal number
        print   ". Up for "
        sys     SYS_UPTIME              ; -> A = ms low word, X = ms high word
        jsr     ms_to_s                 ; -> A = seconds
        jsr     put_dec
        print   " s.\n"                 ; ulib buffers a line and prints it at the \n

; ---- the arguments, one per line ("quoted text" is one argument)
        stz     z:n
@arg:   ptr     word                    ; X, Y = buffer (Y = bank of the label)
        lda     #WORDLEN                ; its size
        jsr     next_arg                ; -> A = length; C set when there are no more
        bcs     @noarg
        inc     z:n
        print   "argument "
        lda     z:n
        jsr     put_dec
        print   ": "
        ptr     word
        jsr     out_str
        jsr     put_nl
        jmp     @arg                    ; (print puts its text inline: a BRA may not reach)
@noarg:

; ---- a line from the keyboard
        print   "What is your name? "
        jsr     out_flush               ; (the prompt has no \n: send it now)
        ptr     name
        lda     #NAMELEN                ; at most NAMELEN - 1 characters
        jsr     getline                 ; echo, Backspace, arrows; C set on ctrl-C
        jcs     @bye                    ; (jcs: a long BCS, from horizon.inc)
        sta     z:len
        print   "Hello, "
        ptr     name
        jsr     out_str
        print   "! Your name has "
        lda     z:len
        jsr     put_dec
        print   " letters.\n"

; ---- a file: append the name to GREET.LOG (in the current directory), count its lines
        ptr     logname
        lda     #O_APPEND               ; 3: append (the file is created when missing)
        sys     SYS_OPEN                ; -> A = handle 0-3, C set + A = error
        jcs     ioerr
        sta     z:fh
        ldx     z:len                   ; name + LF
        lda     #10
        sta     name,x                  ; (16-bit store: also writes a 0 after it: fine)
        inx
        stx     iob+4                   ; length
        lda     z:fh
        sta     iob                     ; u8 handle (the high byte goes to iob+1 and is
        lda     #.loword(name)          ;   overwritten next)
        sta     iob+1                   ; u24 buffer: offset ...
        lda     #^name
        sep     #$20                    ; ... and bank (one byte)
        .a8
        sta     iob+3
        rep     #$20
        .a16
        ptr     iob
        sys     SYS_WRITE               ; -> A = bytes written
        jcs     ioerr
        lda     z:fh
        sys     SYS_CLOSE

        ptr     logname                 ; read it back, 128 bytes at a time
        lda     #O_READ
        sys     SYS_OPEN
        jcs     ioerr
        sta     z:fh
        sta     iob
        lda     #.loword(buf)
        sta     iob+1
        lda     #^buf
        sep     #$20
        .a8
        sta     iob+3
        rep     #$20
        .a16
        lda     #128
        sta     iob+4
        stz     z:n                     ; lines
@rd:    ptr     iob
        sys     SYS_READ                ; -> A = bytes read (0 = end of file)
        jcs     ioerr
        tay
        beq     @eof
        ldx     #0
@cnt:   lda     buf,x
        and     #$00FF
        cmp     #10
        bne     :+
        inc     z:n
:       inx
        dey
        bne     @cnt
        bra     @rd
@eof:   lda     z:fh
        sys     SYS_CLOSE
        ptr     logname
        jsr     out_str
        print   " now has "
        lda     z:n
        jsr     put_dec
        print   " line(s).\n"
@bye:   exit    0                       ; flushes the output, then SYS_EXIT with code 0

ioerr:  pha                             ; A = error: $40 + FatFs code for file errors
        print   "file error $"
        pla
        jsr     put_hex8
        jsr     put_nl
        exit    1

; X:A milliseconds (X = high word) -> A = seconds (the low 16 bits of the quotient).
; A 32 / 16 bit restoring division: the dividend t:q shifts left through the remainder
; in A; each quotient bit goes into bit 0 of q.
ms_to_s:
        sta     z:q                     ; low word
        stx     z:t                     ; high word
        lda     #0                      ; remainder
        ldy     #32
@d:     asl     z:q
        rol     z:t
        rol     a
        cmp     #1000
        bcc     :+
        sbc     #1000                   ; (C is set here: no SEC needed)
        inc     z:q
:       dey
        bne     @d
        lda     z:q
        rts

        .segment "RODATA"
logname: .byte  "GREET.LOG", 0

        .segment "BSS"                  ; cleared by the loader, in the code bank
WORDLEN = 64
NAMELEN = 40
word:   .res    WORDLEN
name:   .res    NAMELEN + 2
buf:    .res    128
iob:    .res    6                       ; {u8 handle, u24 buffer, u16 length}

        .segment "ZEROPAGE"             ; the task's direct page (bank 0), cleared
alen:   .res    2
n:      .res    2
len:    .res    2
fh:     .res    2
t:      .res    2
q:      .res    2
