; PRINTD - sends one print job to the PC as a PDF (/SYSTEM/PRINTD.PRG, 0.23). No window.
;   PRINTD PATH: PATH is a print job on the card (normally /Printouts/YYYY-MM-DD HH.MM.SS
;   NAME.txt; with or without double quotes around it, blanks before and after ignored).
;   The PC link's gateway turns a file it gets as /PC:/Printouts/BASE.pdf into a PDF (A4,
;   Courier) when the file starts with the print marker (ABI.md, "Printing"). So PRINTD:
;   1. asks STAT "/PC:" for the gateway's services: without the PC volume, or without
;      PCS_PRINT (an older gateway): exit code 2;
;   2. makes the folder /PC:/Printouts (it may be there already);
;   3. creates /PC:/Printouts/BASE.pdf (BASE = the job's file name without ".txt") and
;      writes the marker: ESC "A816PRINT 1" LF, "title=" NAME LF, "date=YYYY-MM-DD HH:MM"
;      LF, an empty line (LF). NAME and the date come from the job's name when it has the
;      form "YYYY-MM-DD HH.MM.SS NAME" (NAME: what follows the date and time); otherwise
;      NAME is the whole base name and the date is the job file's own (its STAT time);
;   4. copies the job's bytes after it as they are, in pieces of 16 KB, and closes the file.
;   Exit codes: 0 sent; 1 not sent (no such job, a read or write error, the PC link lost:
;   every call then fails within a few seconds, nothing waits for ever); 2 no PC, or its
;   gateway cannot make PDFs. After an error once the PDF file was created, the partial file
;   on the PC is deleted (the gateway also drops an unfinished file when the link is lost).
;   Quiet: it prints only a usage line when it gets no path. Printer (Send to PC) and the
;   Desktop (a new job sent at once) start it.
        .include "horizon.inc"

PIECE   = 16384                         ; the copy's piece
PMAX    = 128                           ; a path (127 characters at most)
FORMLEN = 20                            ; "YYYY-MM-DD HH.MM.SS " in front of NAME

        .segment "ZEROPAGE"
ap:     .res    4                       ; the argument string (bank 0)

        .segment "CODE"
        .a16
        .i16
start:  stx     z:ap
        stz     z:ap+2
        cmp     #0
        jeq     usage
        ldy     #0                      ; blanks before it
:       lda     [ap],y
        and     #$00FF
        cmp     #' '
        bne     :+
        iny
        bra     :-
:       stz     quote
        cmp     #'"'
        bne     :+
        inc     quote
        iny
:       ldx     #0                      ; the path into job (to the end, or the closing quote)
@cp:    lda     [ap],y
        and     #$00FF
        beq     @end
        cmp     #'"'
        bne     :+
        lda     quote
        bne     @end
        lda     #'"'
:       cpx     #PMAX - 1
        jcs     fail
        sep     #$20
        .a8
        sta     job,x
        rep     #$20
        .a16
        inx
        iny
        bra     @cp
@end:   sep     #$20
        .a8
        stz     job,x
        rep     #$20
        .a16
:       cpx     #0                      ; blanks after it
        jeq     usage
        lda     job-1,x
        and     #$00FF
        cmp     #' '
        bne     :+
        dex
        sep     #$20
        .a8
        stz     job,x
        rep     #$20
        .a16
        bra     :-
:       stx     jlen

; the gateway: the PC volume and its print service
        ldx     #.loword(p_pc)
        jsr     stat
        bcs     nopc
        lda     stb                     ; (the size: the service bits)
        and     #PCS_PRINT
        bne     :+
nopc:   exit    2

; the job: there, a file; BASE = its last part without ".txt"
:       ldx     #.loword(job)
        jsr     stat
        jcs     fail
        lda     stb+4
        and     #$0010
        jne     fail
        ldx     jlen                    ; the last '/'
:       dex
        bmi     :+
        lda     job,x
        and     #$00FF
        cmp     #'/'
        bne     :-
:       inx
        stx     bbeg
        lda     jlen
        sta     bend
        sec
        sbc     bbeg
        cmp     #5                      ; ".txt" (any case) after at least one character
        bcc     :+
        ldx     jlen
        lda     job-4,x
        and     #$DFFF                  ; ("." stays, the letters upper case)
        cmp     #'.' | ('T' << 8)
        bne     :+
        lda     job-2,x
        and     #$DFDF
        cmp     #'X' | ('T' << 8)
        bne     :+
        txa
        sec
        sbc     #4
        sta     bend
:       lda     bend
        sec
        sbc     bbeg
        jeq     fail
        clc
        adc     #20                     ; "/PC:/Printouts/" + BASE + ".pdf" + 0 <= 128
        cmp     #PMAX + 1
        jcs     fail

; the PDF's path
        ldx     #.loword(p_dir)
        ldy     #.loword(out)
        jsr     strcpy
        ldx     #.loword(s_slash)
        jsr     strcpy
        ldx     bbeg
        jsr     baseat
        ldx     #.loword(s_pdf)
        jsr     strcpy

; the marker block in hdr: the title and the date
        ldx     #.loword(s_mark)
        ldy     #.loword(hdr)
        jsr     strcpy
        sty     hp
        ldx     bbeg                    ; the form "YYYY-MM-DD HH.MM.SS NAME"?
        ldy     #0
@form:  lda     form,y
        and     #$00FF
        beq     @isform
        cmp     #'9'
        bne     @lit
        lda     job,x
        and     #$00FF
        cmp     #'0'
        bcc     @plain
        cmp     #'9' + 1
        bcs     @plain
        bra     @next
@lit:   sta     tmp
        lda     job,x
        and     #$00FF
        cmp     tmp
        bne     @plain
@next:  cpx     bend
        bcs     @plain
        inx
        iny
        bra     @form
@isform:
        cpx     bend                    ; (a NAME after it)
        bcs     @plain
        ldy     hp
        stx     tmp                     ; title=NAME
        ldx     #.loword(s_title)
        jsr     strcpy
        ldx     tmp
        jsr     baseat
        ldx     #.loword(s_date)        ; date=YYYY-MM-DD HH:MM
        jsr     strcpy
        lda     bbeg
        sta     tmp
        ldx     #10                     ; the date
        jsr     cpjob
        lda     #' '
        jsr     putc
        lda     bbeg
        clc
        adc     #11
        sta     tmp
        ldx     #2                      ; HH
        jsr     cpjob
        lda     #':'
        jsr     putc
        lda     bbeg
        clc
        adc     #14
        sta     tmp
        ldx     #2                      ; MM
        jsr     cpjob
        bra     @hend
@plain: ldy     hp                      ; title=BASE, the date the job's own
        ldx     #.loword(s_title)
        jsr     strcpy
        ldx     bbeg
        jsr     baseat
        ldx     #.loword(s_date)
        jsr     strcpy
        lda     stb+7                   ; FAT date: year - 1980 << 9 | month << 5 | day
        xba
        lsr     a
        and     #$007F
        clc
        adc     #1980
        ldx     #4
        jsr     putn
        lda     #'-'
        jsr     putc
        lda     stb+7
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        and     #$000F
        jsr     put2
        lda     #'-'
        jsr     putc
        lda     stb+7
        and     #$001F
        jsr     put2
        lda     #' '
        jsr     putc
        lda     stb+5                   ; FAT time: hour << 11 | minute << 5 | second / 2
        xba
        lsr     a
        lsr     a
        lsr     a
        and     #$001F
        jsr     put2
        lda     #':'
        jsr     putc
        lda     stb+5
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        and     #$003F
        jsr     put2
@hend:  lda     #10                     ; the line's end, then the empty line
        jsr     putc
        lda     #10
        jsr     putc
        sty     hp

; the job opened, the folder made, the PDF created, the marker written
        ptr     job
        lda     #O_READ
        sys     SYS_OPEN
        jcs     fail
        sta     jh
        ptr     p_dir
        sys     SYS_MKDIR               ; (there already: fine; other errors: the create says)
        ptr     out
        lda     #O_CREATE
        sys     SYS_OPEN
        jcs     fail
        sta     ph
        lda     hp                      ; (its length)
        sec
        sbc     #.loword(hdr)
        tay
        lda     #.loword(hdr)
        ldx     #^hdr
        jsr     write
        bcs     bad
@copy:  lda     jh                      ; the job's bytes, 16 KB at a time
        sta     rw
        lda     #.loword(buf)
        sta     rw+1
        sep     #$20
        .a8
        lda     #^buf
        sta     rw+3
        rep     #$20
        .a16
        lda     #PIECE
        sta     rw+4
        ptr     rw
        sys     SYS_READ
        bcs     bad
        sta     cnt
        cmp     #0
        beq     @done
        tay
        lda     #.loword(buf)
        ldx     #^buf
        jsr     write
        bcs     bad
        lda     cnt
        cmp     #PIECE
        beq     @copy                   ; (fewer bytes: the end)
@done:  lda     ph
        sys     SYS_CLOSE
        bcs     bad2
        lda     jh
        sys     SYS_CLOSE
        exit    0

; an error after the create: the partial file deleted
bad:    lda     ph
        sys     SYS_CLOSE
bad2:   ptr     out
        sys     SYS_DELETE
        lda     jh
        sys     SYS_CLOSE
fail:   exit    1

usage:  print   "usage: printd PATH (a print job: sent to the PC as a PDF)\n"
        exit    1

; X = path -> stb (STAT). C set: an error
stat:   stx     sblk
        lda     #.loword(stb)
        sta     sblk+3
        sep     #$20
        .a8
        lda     #^stb
        sta     sblk+2
        sta     sblk+5
        rep     #$20
        .a16
        ptr     sblk
        sys     SYS_STAT
        rts

; A = buffer, X = its bank, Y = length: written to the PDF. C set: an error or a short write
write:  sta     rw+1
        sty     rw+4
        sty     tmp
        lda     ph
        sep     #$20
        .a8
        sta     rw
        txa
        sta     rw+3
        rep     #$20
        .a16
        ptr     rw
        sys     SYS_WRITE
        bcs     :+
        cmp     tmp                     ; (all of it?)
        bne     :+
        clc
        rts
:       sec
        rts

; X = string copied to Y (with its 0) -> Y at the 0
strcpy: lda     a:0,x
        and     #$00FF
        sep     #$20
        .a8
        sta     a:0,y
        rep     #$20
        .a16
        beq     :+
        inx
        iny
        bra     strcpy
:       rts

; job from X to bend appended at Y (zero-terminated; Y at the 0)
baseat: cpx     bend
        bcs     :+
        lda     job,x
        jsr     putc
        inx
        bra     baseat
:       lda     #0
        sep     #$20
        .a8
        sta     a:0,y
        rep     #$20
        .a16
        rts

; X characters of job from tmp appended at Y
cpjob:  phx
        ldx     tmp
        lda     job,x
        inc     tmp
        plx
        jsr     putc
        dex
        bne     cpjob
        rts

; A = 0-99 as two digits at Y
put2:   ldx     #2
; A = number, X = digits (1-4) at Y
putn:   sta     tmp
        txa
        asl     a
        eor     #$FFFF
        clc
        adc     #9                      ; the first power: pow + 8 - 2 X
        tax
@d:     lda     #'0'
        sta     dig
:       lda     tmp
        cmp     pow,x
        bcc     :+
        sbc     pow,x
        sta     tmp
        inc     dig
        bra     :-
:       lda     dig
        jsr     putc
        inx
        inx
        cpx     #8
        bcc     @d
        rts

; A = a byte stored at Y, Y + 1 (keeps X)
putc:   sep     #$20
        .a8
        sta     a:0,y
        rep     #$20
        .a16
        iny
        rts

        .segment "RODATA"
p_pc:   .byte   "/PC:", 0
p_dir:  .byte   "/PC:/Printouts", 0
s_slash: .byte  "/", 0
s_pdf:  .byte   ".pdf", 0
s_mark: .byte   $1B, "A816PRINT 1", 10, 0
s_title: .byte  "title=", 0
s_date: .byte   10, "date=", 0
form:   .byte   "9999-99-99 99.99.99 ", 0
pow:    .word   1000, 100, 10, 1

        .segment "BSS"
quote:  .res    2
jlen:   .res    2
bbeg:   .res    2
bend:   .res    2
hp:     .res    2
tmp:    .res    2
dig:    .res    2
cnt:    .res    2
jh:     .res    2
ph:     .res    2
sblk:   .res    6
rw:     .res    6
stb:    .res    10
job:    .res    PMAX + 2
out:    .res    PMAX + 8
hdr:    .res    PMAX * 2 + 64
buf:    .res    PIECE
