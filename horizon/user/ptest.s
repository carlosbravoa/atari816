; PTEST - (0.28) a test of task_path (SYS_TPATH $35) and of program files of 64 KB or more,
; run by make test-28 from the text shell (tests/ptest.keys) and from the Desktop's Programs
; menu (tests/ptestd.keys). It is not on the card: the test copies build/ptest.prg there,
; also as larger files with data after the o65 (tests/mkptest.py). Each line it prints starts
; with "ptest":
;   path: PATH (N)        task_path with a 128-byte buffer: the program file's path, length
;   small: error 01       a buffer of the path's length (no room for the 0): EINVAL
;   cwd: DIR              the current folder (getcwd), for comparison
;   file: below 64 KB / 64 KB or more    its own file, STATed by that path
;   tail: PTESTEND / none     its last 8 bytes (the data tests/mkptest.py appended)
;   bss: clear / NOT CLEAR    its 4 KB of bss are zero (data after the o65 never reaches
;                             the program's memory)
        .include "horizon.inc"

        .segment "CODE"
        .a16
        .i16
start:  ptr     path
        lda     #128
        sys     SYS_TPATH
        bcc     :+
        pha
        print   "ptest path: error "
        pla
        jsr     put_hex8
        jsr     put_nl
        exit    1
:       sta     plen
        print   "ptest path: "
        ptr     path
        jsr     out_str
        print   " ("
        lda     plen
        jsr     put_dec
        print   ")\n"

        print   "ptest small: "
        ptr     path2
        lda     plen                    ; no room for the terminator
        sys     SYS_TPATH
        jsr     res

        print   "ptest cwd: "
        ptr     cwd
        lda     #128
        sys     SYS_GETCWD
        ptr     cwd
        jsr     out_str
        jsr     put_nl

        ; its own file, by that path
        print   "ptest file: "
        ptr     sblk
        sys     SYS_STAT
        bcc     :+
        jsr     res
        bra     @tail
:       sta     fsize
        stx     fsize+2
        txa
        bne     :+
        print   "below 64 KB\n"
        bra     @tail
:       print   "64 KB or more\n"
@tail:  print   "ptest tail: "
        ptr     path
        lda     #0                      ; read
        sys     SYS_OPEN
        bcc     :+
        jsr     res
        bra     @bss
:       sta     handle
        sep     #$20
        .a8
        sta     rblk
        rep     #$20
        .a16
        lda     fsize
        sec
        sbc     #8
        tax
        lda     fsize+2
        sbc     #0
        tay
        lda     handle
        sys     SYS_SEEK
        ptr     rblk
        sys     SYS_READ
        bcc     :+
        lda     #0
:       sta     got
        lda     handle
        sys     SYS_CLOSE
        lda     got
        cmp     #8
        bne     @none
        ldx     #6
:       lda     tail,x
        cmp     mark,x
        bne     @none
        dex
        dex
        bpl     :-
        print   "PTESTEND\n"
        bra     @bss
@none:  print   "none\n"
@bss:   print   "ptest bss: "
        ldx     #4096 - 2
:       lda     zero,x
        bne     :+
        dex
        dex
        bpl     :-
        print   "clear\n"
        exit    0
:       print   "NOT CLEAR\n"
        exit    0

; C clear: "ok", else "error XX"
res:    bcs     :+
        print   "ok\n"
        rts
:       pha
        print   "error "
        pla
        jsr     put_hex8
        jmp     put_nl

        .segment "RODATA"
mark:   .byte   "PTESTEND"

        .segment "DATA"
sblk:   .faraddr path                   ; stat {u24 path, u24 out}
        .faraddr srec
rblk:   .byte   0                       ; read {u8 handle, u24 buffer, u16 length}
        .faraddr tail
        .word   8

        .segment "BSS"
plen:   .res    2
fsize:  .res    4
handle: .res    2
got:    .res    2
path:   .res    128
path2:  .res    128
cwd:    .res    128
srec:   .res    10
tail:   .res    8
zero:   .res    4096
