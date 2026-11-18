; FTEST - exercises create/write/seek/read/stat/mkdir/delete on the SD card and cleans up.
        .include "horizon.inc"
        .segment "CODE"
        .a16
        .i16
start:  ptr     fname                   ; create, write 11 bytes
        lda     #O_CREATE
        sys     SYS_OPEN
        bcc     *+5
        jmp     err
        sta     z:h
        jsr     setblk
        lda     #.loword(text)
        sta     z:blk+1
        lda     #11
        sta     z:blk+4
        ldx     #blk
        ldy     #0
        sys     SYS_WRITE
        bcc     *+5
        jmp     err
        pha
        print   "files: wrote "
        pla
        jsr     put_dec
        jsr     put_nl
        lda     z:h                     ; seek 6, read 4
        ldx     #6
        ldy     #0
        sys     SYS_SEEK
        bcc     *+5
        jmp     err
        jsr     setblk
        lda     #4
        sta     z:blk+4
        ldx     #blk
        ldy     #0
        sys     SYS_READ
        bcc     *+5
        jmp     err
        tax
        sep     #$20
        .a8
        stz     buf,x
        rep     #$20
        .a16
        print   "files: read back \""
        ptr     buf
        jsr     out_str
        print   "\"\n"
        lda     z:h
        sys     SYS_CLOSE
        bcc     *+5
        jmp     err
        lda     #.loword(fname)         ; stat
        jsr     dostat
        bcc     *+5
        jmp     err
        print   "files: size "
        lda     out
        jsr     put_dec
        print   " attr $"
        lda     out+4
        jsr     put_hex8
        jsr     put_nl
        ptr     dname                   ; mkdir, stat it, delete both
        sys     SYS_MKDIR
        bcc     *+5
        jmp     err
        lda     #.loword(dname)
        jsr     dostat
        bcc     *+5
        jmp     err
        print   "files: dir attr $"
        lda     out+4
        jsr     put_hex8
        jsr     put_nl
        ptr     dname
        sys     SYS_DELETE
        bcc     *+5
        jmp     err
        ptr     fname
        sys     SYS_DELETE
        bcc     *+5
        jmp     err
        lda     #.loword(fname)
        jsr     dostat
        jcc     err
        pha
        print   "files: after delete, stat error $"
        pla
        jsr     put_hex8
        jsr     put_nl
        exit    0
err:    pha
        print   "files: error $"
        pla
        jsr     put_hex8
        jsr     put_nl
        exit    1

; blk = {handle, buf, ?}
setblk: lda     z:h
        sta     z:blk
        lda     #.loword(buf)
        sta     z:blk+1
        sep     #$20
        .a8
        lda     #^buf
        sta     z:blk+3
        rep     #$20
        .a16
        rts

; stat the path at A (this bank) into out
dostat: sta     z:sblk
        lda     #.loword(out)
        sta     z:sblk+3
        sep     #$20
        .a8
        lda     #^out
        sta     z:sblk+2
        sta     z:sblk+5
        rep     #$20
        .a16
        ldx     #sblk
        ldy     #0
        sys     SYS_STAT
        rts

        .segment "RODATA"
fname:  .byte   "/TMP.TXT", 0
dname:  .byte   "/TDIR", 0
text:   .byte   "hello file\n"
        .segment "BSS"
buf:    .res    16
out:    .res    9
        .segment "ZEROPAGE"
h:      .res    2
blk:    .res    6
sblk:   .res    6
