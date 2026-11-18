; INIT - the first task (/SYSTEM/INIT.PRG): runs the Desktop, /SYSTEM/DESK.PRG, and starts
; it again whenever it exits. With /SYSTEM/NODESK on the card (the text-console tests), or
; when a key is held down at start (pressed in the first half second), it runs the shell, /SYSTEM/SH.PRG, instead, again whenever it exits, with "files" as its
; first command (the text file browser).
; INIT holds the keyboard and lends it to each shell (without the
; ctrl-C break), so the keyboard never goes back to the classic side in between: that
; would make the I/O processor report a key still held (the shell's last Enter) again.
        .include "horizon.inc"
        .segment "CODE"
        .a16
        .i16
start:  sys     SYS_ICLAIM
        ptr     nodesk                  ; /SYSTEM/NODESK: the text shell, no Desktop
        lda     #O_READ
        sys     SYS_OPEN
        jcc     tmode
        lda     #500                    ; a key held at start (any key): the text shell
        sys     SYS_SLEEP
@poll:  sys     SYS_IPOLL
        jcs     desk
        cmp     #$0100                  ; (mouse events: not keys)
        bcs     @poll
        cpx     #$0100                  ; down?
        bcc     @poll
        print   "init: a key at start: the text shell\n"
        jmp     loop
desk:   print   "init: starting /SYSTEM/DESK.PRG\n"
        stz     z:u_arg
        stz     z:u_arg+2
        ptr     dpath
        lda     #1
        jsr     spawn
        jcs     derr
        pha
        ldx     #0
        sys     SYS_ILEND
        pla
        sys     SYS_WAIT
        jmp     desk
derr:  print   "init: no Desktop, the shell instead\n"
        jmp     loop
tmode:  sys     SYS_CLOSE
loop:   print   "init: starting /SYSTEM/SH.PRG\n"
        lda     #.loword(sharg)         ; "files": the shell starts with the browser
        sta     z:u_arg
        lda     #^sharg
        sta     z:u_arg+2
        ptr     path
        lda     #1
        jsr     spawn
        jcs     @err
        pha
        ldx     #0                      ; no break: ctrl-C belongs to the shell
        sys     SYS_ILEND
        pla
        sys     SYS_WAIT
        jmp     loop
@err:   pha
        print   "init: cannot start the shell, error "
        pla
        jsr     put_hex8
        jsr     put_nl
        jsr     out_flush
        lda     #1000                   ; try again in a second
        sys     SYS_SLEEP
        jmp     loop

        .segment "RODATA"
path:   .byte   "/SYSTEM/SH.PRG", 0
dpath:  .byte   "/SYSTEM/DESK.PRG", 0
nodesk: .byte   "/SYSTEM/NODESK", 0
sharg:  .byte   "files", 0
