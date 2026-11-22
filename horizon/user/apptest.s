; APPTEST - (0.29) the apps tests' program (make test-29; not on the card: tests/mkapps.py
; puts copies into app folders). It prints one line: its name, task_path, its current
; folder and its argument string; with a file as its argument, that file's first line.
; Built several times (-D): NEEDV needs Horizon 0.99, NEEDM 60,000 KB of free memory,
; NEEDO the OPL2, NEEDOK Horizon 0.29 and 64 KB (it runs), none: no HZ_NEEDS block.
        .include "horizon.inc"
        .include "needs.inc"

        .segment "CODE"
        .a16
        .i16
start:
.if .defined(NEEDV)
        HZ_NEEDS "NEEDV", 0, 99, 0, 0, 0
.elseif .defined(NEEDM)
        HZ_NEEDS "NEEDM", 0, 29, 0, 0, 60000
.elseif .defined(NEEDO)
        HZ_NEEDS "NEEDO", 0, 29, 0, NEED_OPL2, 0
.elseif .defined(NEEDOK)
        HZ_NEEDS "NEEDOK", 0, 29, 0, 0, 64
.endif
        sta     z:alen                  ; (the start conditions, kept by HZ_NEEDS)
        stx     z:aoff
        print   "apptest: "
        ptr     buf
        lda     #128
        sys     SYS_TPATH
        bcs     :+
        ptr     buf
        jsr     out_str
:       print   " in "
        ptr     buf
        lda     #128
        sys     SYS_GETCWD
        bcs     :+
        ptr     buf
        jsr     out_str
:       print   " args ["
        ldx     z:aoff                  ; (the argument string: in the window, bank 0)
        ldy     #0
        jsr     out_str
        print   "]\n"
        lda     z:alen                  ; a file named: its first line
        jeq     @out
        ldx     z:aoff
        jsr     args_init
        ptr     buf
        lda     #128
        jsr     next_arg
        bcs     @out
        ptr     buf
        lda     #O_READ
        sys     SYS_OPEN
        bcs     @out
        sta     z:fh
        sta     rw
        lda     #.loword(line)
        sta     rw+1
        lda     #^line
        sta     rw+3
        lda     #79
        sta     rw+4
        ptr     rw
        sys     SYS_READ
        bcc     :+
        lda     #0
:       tax
        stz     line,x
        ldx     #0
:       lda     line,x
        and     #$00FF
        beq     :+
        cmp     #10
        beq     :+
        inx
        bra     :-
:       stz     line,x
        lda     z:fh
        sys     SYS_CLOSE
        print   "apptest: the file says: "
        ptr     line
        jsr     out_str
        jsr     put_nl
@out:   exit    0

        .segment "BSS"
buf:    .res    130
line:   .res    82
rw:     .res    6

        .segment "ZEROPAGE"
alen:   .res    2
aoff:   .res    2
fh:     .res    2
