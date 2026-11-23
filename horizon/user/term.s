; TERM - a terminal window running the shell (/BIN/TERM.PRG; the shell is /SYSTEM/SH.PRG). The window is a kernel
; terminal (WF_TERM, 76 x 24 cells of the 8x12 font); the shell is attached to it
; (SYS_WTERM, inherited), so it and every program it starts print there and read their
; keys there, unchanged. The close box ends the shell; when the shell ends, the window
; closes. Without a Desktop it starts the window system itself (and stops it at the end).
; (0.31) TERM [-e] PROG [ARGS]: runs the program PROG ("quoted" when it has spaces) with
; the arguments ARGS in the window instead of the shell (the Desktop and Files start a
; program with console= in its APP.INF, or Run with..., so); the title is its file's name.
; When it ends, the window says so ("--- NAME ended (code N). Press a key to close."; the
; log gets "term: NAME ended (code N)") and closes at a key or the close box; with -e it
; closes at once when the code is 0. The close box while it runs kills it.
        .include "horizon.inc"

        .segment "CODE"
        .a16
        .i16
start:  sta     z:argl
        stx     z:argx
        sys     SYS_WSSTART
        jcs     fail
        sta     z:own
        sys     SYS_GETPID              ; a little offset per terminal: x 11 or 19, y 24-48
        pha                             ; (610 x 305 outside: always fully on screen)
        and     #1
        asl     a
        asl     a
        asl     a
        clc
        adc     #11
        sta     wblk
        pla
        and     #3
        asl     a
        asl     a
        asl     a
        clc
        adc     #24
        sta     wblk+2
        ptr     wblk
        sys     SYS_WOPEN
        jcs     fail2
        sta     z:win
        sys     SYS_WTERM               ; attach: the shell inherits it
        jcs     fail2
        stz     z:u_arg
        stz     z:u_arg+2
        stz     z:em
        stz     z:run
        lda     z:argl                  ; (0.31) a program to run?
        jeq     @sh
        ldx     z:argx
        jsr     args_init
        ptr     prog
        lda     #128
        jsr     next_arg
        jeq     @sh
        lda     prog                    ; "-e": closed at once after code 0
        cmp     #'-' | ('e' << 8)
        bne     :+
        lda     prog+2
        and     #$00FF
        bne     :+
        inc     z:em
        ptr     prog
        lda     #128
        jsr     next_arg
        jeq     @sh
:       inc     z:run
        jsr     mkname                  ; its name: the title
        lda     z:win
        ptr     name
        sys     SYS_WTITLE
        jsr     str_skip                ; the rest: its arguments (in this window)
        lda     z:u_p
        sta     z:u_arg
        ptr     prog
        lda     #1
        jsr     spawn
        bcc     @pid
        sta     z:code                  ; not started: said in the window
        print   "term: cannot start "
        ptr     prog
        jsr     out_str
        print   " (error $"
        lda     z:code
        jsr     put_hex8
        print   ")\n"
        jsr     out_flush
        lda     z:win
        ldx     #50
        sys     SYS_WTIMER
        jmp     ended2
@sh:    ptr     p_sh
        lda     #1
        jsr     spawn
        jcs     fail2
@pid:   sta     z:pid
        ldx     #0                      ; its keys (ctrl-C belongs to the shell)
        sys     SYS_ILEND
        lda     #$FF                    ; detach this task
        sys     SYS_WTERM
        lda     z:win                   ; look after the shell twice a second
        ldx     #50
        sys     SYS_WTIMER

loop:   lda     #0
        ptr     ev
        sys     SYS_WEVENT
        bcs     loop
        lda     ev
        and     #$00FF
        cmp     #WE_CLOSE
        beq     @close
        cmp     #WE_TICK
        bne     loop
        jsr     alive
        bcs     loop
        bra     @reap
@close: lda     z:pid
        sys     SYS_KILL
        stz     z:run                   ; (closed by the user: nothing to show)
@reap:  lda     z:pid
        sys     SYS_WAIT
        sta     z:code
        lda     z:run
        jeq     done
        lda     z:win                   ; (0.31) the program's end, in the window
        sys     SYS_WTERM
        print   "\n--- "
        jsr     endtxt
        print   ".\n"
        jsr     out_flush
        lda     #$FF
        sys     SYS_WTERM
        print   "term: "                ; and in the log
        jsr     endtxt
        jsr     put_nl
        jsr     out_flush
        lda     z:em                    ; -e and code 0: closed at once
        beq     :+
        lda     z:code
        beq     done
:       lda     z:win                   ; a key or the close box closes it
        sys     SYS_WTERM
:       sys     SYS_IPOLL               ; (the keys typed while it ran: dropped)
        bcc     :-
ended2: print   "Press a key to close.\n"
        jsr     out_flush
:       lda     #0
        ptr     ev
        sys     SYS_WEVENT
        bcs     :-
        lda     ev
        and     #$00FF
        cmp     #WE_CLOSE
        beq     done
        cmp     #WE_TICK
        bne     :-
:       sys     SYS_IPOLL               ; (the terminal's keys: a press)
        bcs     :--
        txa
        and     #$0100
        beq     :-
done:   lda     z:win
        sys     SYS_WCLOSE
        lda     z:own
        beq     :+
        sys     SYS_WSSTOP
:       exit    0

; "NAME ended (code N)" (killed: "NAME was stopped")
endtxt: ptr     name
        jsr     out_str
        lda     z:code
        cmp     #$FF80
        bne     :+
        print   " was stopped"
        rts
:       print   " ended (code "
        lda     z:code
        jsr     put_dec
        print   ")"
        rts

; the title: the program's file name without its extension (prog -> name)
mkname: ldx     #0
        ldy     #0
:       lda     prog,x                  ; (after the last '/')
        and     #$00FF
        beq     :+
        inx
        cmp     #'/'
        bne     :-
        txy
        bra     :-
:       ldx     #0
:       lda     prog,y
        and     #$00FF
        beq     :+
        cmp     #'.'
        beq     :+
        sta     name,x
        inx
        iny
        cpx     #31
        bcc     :-
:       stz     name,x
        rts

fail2:  lda     z:own
        beq     fail
        sys     SYS_WSSTOP
fail:   print   "term: cannot open a terminal\n"
        exit    1

; C set while the shell runs (it is in the task table and not a zombie)
alive:  stz     z:t
@s:     lda     z:t
        ptr     info
        sys     SYS_TINFO
        bcs     @n
        lda     info
        and     #$00FF
        cmp     z:pid
        bne     @n
        lda     info+1
        and     #$00FF
        cmp     #4
        beq     @dead
        sec
        rts
@n:     inc     z:t
        lda     z:t
        cmp     #16
        bcc     @s
@dead:  clc
        rts

        .segment "RODATA"
p_sh:   .byte   "/SYSTEM/SH.PRG", 0
t_term: .byte   "Terminal", 0

        .segment "DATA"
wblk:   .word   8, 24, 76 * 8, 24 * 12  ; 610 x 305 outside: fits below the bar
        .faraddr t_term
        .byte   WF_TERM

        .segment "BSS"
ev:     .res    8
info:   .res    16
prog:   .res    130                     ; (0.31) the program run, its name
name:   .res    34

        .segment "ZEROPAGE"
own:    .res    2
win:    .res    2
pid:    .res    2
t:      .res    2
argl:   .res    2                       ; (0.31) the argument string
argx:   .res    2
em:     .res    2                       ; -e
run:    .res    2                       ; a program, not the shell
code:   .res    2                       ; its exit code
