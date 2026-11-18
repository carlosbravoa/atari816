; SH - the Horizon shell (/SYSTEM/SH.PRG). Prompt "> ".
;   built-ins: help, ls [path] (alias dir), cat file, cd [path], pwd, ps, mem, kill id, cls, atari,
;     exit, restart [full], shutdown (both ask the Desktop when one runs), mount file [1-4], eject d1-d4|cart|xex, boot, run file (Atari software),
;     rm path..., mkdir path, mv from to, cp from to (into a folder: keeps the name)
;   Arguments may be quoted: "River Raid (Title Version).xex". Paths are relative to the
;     current directory (cd, kept by the kernel per task and inherited by programs).
;   Any other word runs a program: a word with a '/' or ending in .PRG is that file
;     (relative to the current directory); otherwise <WORD>.PRG from the first of /BIN,
;     /SYSTEM, /SYSTEM/TESTS that has it. The rest of the
;     line is its argument string. A foreground job gets the keyboard lent (ctrl-C kills
;     it); its exit code is printed when it is not 0. "... &" runs it in the background;
;     finished background jobs are reported as "[done] id exit code" before the prompt.
;   The shell's own argument string, if any, is run as its first command (INIT starts
;     "SH files": the file browser).
;   line editing: backspace, left/right, up/down = the last 8 lines (ulib getline)
        .include "horizon.inc"
        .include "ui.inc"

LINEMAX = 80
NJOBS   = 8

        .segment "CODE"
        .a16
        .i16
start:  sta     z:alen
        stx     z:aoff
:       sys     SYS_ICLAIM              ; ours (or lent to us by INIT)? else wait for it
        bcc     :+
        lda     #10
        sys     SYS_SLEEP
        bra     :-
:       sys     SYS_CSIZE
        sta     z:cols
        stx     z:rows
        print   "Horizon shell. Type help.\n"
        jsr     ui_clkload              ; (0.14) the clock: the last saved time, if not set
        lda     z:alen                  ; a first command from our arguments
        beq     prompt
        cmp     #LINEMAX
        bcs     prompt
        tay
        sep     #$20
        .a8
        lda     #0
        sta     line,y
        rep     #$20
        .a16
        stz     z:u_p+2
:       dey
        bmi     :+
        lda     z:aoff                  ; (window, bank 0)
        sta     z:u_p
        lda     [u_p],y
        sep     #$20
        .a8
        sta     line,y
        rep     #$20
        .a16
        bra     :-
:       jsr     execute
prompt: jsr     reap
        print   "> "
        jsr     out_flush
        ldx     #.loword(line)
        ldy     #^line
        lda     #LINEMAX
        jsr     getline
        bcs     prompt                  ; ctrl-C: drop the line
        jsr     reap
        jsr     execute
        bra     prompt

; ---- run the command in line ----
execute:
        lda     #.loword(line)
        sta     z:u_p
        lda     #^line
        sta     z:u_p+2
        jsr     str_skip
        cmp     #0
        bne     :+
        rts
:       stz     z:bg                    ; a trailing '&' (spaces around it allowed)
        ldy     #0
:       lda     line,y
        and     #$00FF
        beq     :+
        iny
        bra     :-
:       dey                             ; back over trailing spaces
        bmi     @word
        lda     line,y
        and     #$00FF
        cmp     #' '
        beq     :-
        cmp     #'&'
        bne     @word
        inc     z:bg
        jsr     @zero
:       dey                             ; trailing spaces before the '&'
        bmi     @word
        lda     line,y
        and     #$00FF
        cmp     #' '
        bne     @word
        jsr     @zero
        bra     :-
@word:  ldx     #.loword(cmdraw)        ; the command word (may be quoted)
        ldy     #^cmdraw
        lda     #128
        jsr     next_arg
        cmp     #16                     ; cmd = lower case, for the built-ins
        bcs     external
        tay
:       lda     cmdraw,y
        and     #$00FF
        cmp     #'A'
        bcc     :+
        cmp     #'Z' + 1
        bcs     :+
        ora     #$20
:       sep     #$20
        .a8
        sta     cmd,y
        rep     #$20
        .a16
        dey
        bpl     :--
        jsr     str_skip
        ldx     #0
@bi:    lda     bnames,x
        and     #$00FF
        beq     external
        phx
        ldy     #0
:       lda     bnames,x
        and     #$00FF
        sta     z:t0
        lda     cmd,y
        and     #$00FF
        cmp     z:t0
        bne     :+
        cmp     #0
        beq     @match
        inx
        iny
        bra     :-
:       plx                             ; next name: 8 bytes each
        txa
        clc
        adc     #8
        tax
        bra     @bi
@match: plx
        txa
        lsr     a
        lsr     a                       ; 8 bytes per name -> 2 bytes per handler
        tax
        jsr     (bfuncs,x)
        rts
@zero:  sep     #$20
        .a8
        lda     #0
        sta     line,y
        rep     #$20
        .a16
        rts

; ---- a program ----
external:
        jsr     str_skip
        ldx     #.loword(cmdraw)        ; a path ('/' in it, or .PRG at the end)?
        ldy     #^cmdraw
        jsr     is_path
        bcc     @bin
        ldx     #0
:       lda     cmdraw,x
        sta     path,x
        inx
        inx
        cpx     #128
        bcc     :-
        stz     z:search
        brl     @spawn2
@bin:   stz     z:pfx                   ; prefix + upper(word) + ".PRG": /BIN, /SYSTEM,
@try:   ldx     z:pfx                   ; /SYSTEM/TESTS in turn
        lda     pfxs,x
        sta     z:sp
        ldx     #0
        sep     #$20
        .a8
:       lda     (sp)
        beq     :+
        sta     path,x
        inc     z:sp
        inx
        bra     :-
:       rep     #$20
        .a16
        ldy     #0
:       lda     cmdraw,y
        and     #$00FF
        beq     :+
        cmp     #'a'
        bcc     @up
        cmp     #'z' + 1
        bcs     @up
        and     #$00DF
@up:    sep     #$20
        .a8
        sta     path,x
        rep     #$20
        .a16
        inx
        iny
        cpx     #100
        bcc     :-
:       ldy     #0
:       lda     binsuf,y
        sta     path,x
        inx
        iny
        cpy     #5
        bcc     :-
        lda     #1
        sta     z:search
        ldx     z:pfx                   ; not the last folder: is it there? (a failed
        cpx     #(NPFX - 1) * 2         ; spawn would use up a task id)
        bcs     @spawn2
        lda     #.loword(path)
        sta     sblk
        lda     #.loword(dbuf)
        sta     sblk+3
        sep     #$20
        .a8
        lda     #^path
        sta     sblk+2
        lda     #^dbuf
        sta     sblk+5
        rep     #$20
        .a16
        ldx     #.loword(sblk)
        ldy     #^sblk
        sys     SYS_STAT
        bcc     @spawn2
        jmp     @next
@spawn2:
        lda     [u_p]                   ; arguments: the rest of the line, if any
        and     #$00FF
        beq     :+
        lda     z:u_p
        sta     z:u_arg
        lda     z:u_p+2
        sta     z:u_arg+2
        bra     :++
:       stz     z:u_arg
        stz     z:u_arg+2
:       ldx     #.loword(path)
        ldy     #^path
        lda     #2
        jsr     spawn
        bcc     :+
        ldx     z:search                ; not found: the next folder of the search path
        beq     @err
        cmp     #$44
        beq     @next
        cmp     #$45
        bne     @err
@next:  ldx     z:pfx
        inx
        inx
        stx     z:pfx
        cpx     #NPFX * 2
        jcc     @try
        lda     #$44
@err:   pha
        print   "sh: "
        ldx     #.loword(cmdraw)
        ldy     #^cmdraw
        jsr     out_str
        print   ": "
        pla
        jsr     errmsg
        jmp     put_nl
:       sta     z:job
        lda     z:bg
        beq     @fg
        ldx     #0                      ; remember the background job
:       lda     jobs,x
        beq     :+
        inx
        inx
        cpx     #NJOBS * 2
        bcc     :-
        bra     @bgmsg                  ; no room: it is still reaped by nobody (orphan)
:       lda     z:job
        sta     jobs,x
@bgmsg: print   "[bg] "
        lda     z:job
        jsr     put_dec
        jmp     put_nl
@fg:    lda     z:job                   ; foreground: lend the keyboard (ctrl-C kills it), wait
        ldx     #1
        sys     SYS_ILEND
        lda     z:job
        sys     SYS_WAIT
        bcs     :+
        cmp     #0
        beq     :+
        pha
        print   "exit "
        pla
        jsr     put_hex16
        jsr     put_nl
:       rts

; C set if the word at X, Y names a file: it has a '/' or ends in ".PRG"
is_path:
        stx     z:sp
        tya
        sta     z:sp+2
        ldy     #0
:       lda     [sp],y
        and     #$00FF
        beq     :+
        cmp     #'/'
        beq     @yes
        iny
        bra     :-
:       cpy     #4
        bcc     @no
        dey
        dey
        dey
        dey
        lda     [sp],y                 ; ".P", "RG"
        and     #$DFFF
        cmp     #'.' | ('P' << 8)
        bne     @no
        iny
        iny
        lda     [sp],y
        and     #$DFDF
        cmp     #'R' | ('G' << 8)
        bne     @no
@yes:   sec
        rts
@no:    clc
        rts

; report finished background jobs
reap:   ldx     #0
@loop:  lda     jobs,x
        beq     @next
        phx
        jsr     task_state
        plx
        cmp     #4                      ; zombie
        bne     @next
        phx
        lda     jobs,x
        sta     z:job
        sys     SYS_WAIT
        sta     z:t0
        print   "[done] "
        lda     z:job
        jsr     put_dec
        print   " exit "
        lda     z:t0
        jsr     put_hex16
        jsr     put_nl
        plx
        stz     jobs,x
@next:  inx
        inx
        cpx     #NJOBS * 2
        bcc     @loop
        rts

; A = task id -> A = its state (0 if there is no such task)
task_state:
        sta     z:t1
        ldx     #0
:       phx
        txa
        jsr     tinfo
        plx
        lda     info
        and     #$00FF
        cmp     z:t1
        bne     :+
        lda     info+1
        and     #$00FF
        rts
:       inx
        cpx     #16
        bcc     :--
        lda     #0
        rts

; task_info of slot A into info
tinfo:  ldx     #.loword(info)
        ldy     #^info
        sys     SYS_TINFO
        rts

; print spawn error A: "not found" for $44 / $45, a sentence for the other causes of a
; program that cannot start, "error $xx" otherwise
errmsg: cmp     #$44
        beq     :+
        cmp     #$45
        bne     :++
:       print   "not found"
        rts
:       cmp     #ENOMEM
        bne     :+
        print   "not enough memory to start it. Close a program and try again."
        rts
:       cmp     #EAGAIN
        bne     :+
        print   "too many programs are running. Close one and try again."
        rts
:       cmp     #EINVAL
        bne     :+
        print   "not a Horizon program (or a damaged file)"
        rts
:       cmp     #ERUNNING
        bne     :+
        print   "already running (its window was raised)"
        rts
:       pha
        print   "error $"
        pla
        jmp     put_hex8

; next argument -> fname; A = length, Z set if none
getword:
        ldx     #.loword(fname)
        ldy     #^fname
        lda     #128
        jmp     next_arg

; ---------------------------------------------------------------- built-ins
b_help: print   "built-ins: help, ls [path] (or dir), cat file, cd [path], pwd, ps, date [set],\n"
        print   "  mem, kill id, cls, atari, exit, files (the file browser), restart [full], shutdown\n"
        print   "files: rm path..., mkdir path, mv from to, cp from to (to: a folder too)\n"
        print   "Atari: mount file [1-4], eject d1-d4|cart|xex, boot, run file\n"
        print   "other words run <WORD>.PRG from /BIN, /SYSTEM or /SYSTEM/TESTS (or a .PRG path);\n"
        print   "  the rest of the line is its argument; a trailing & runs it in the background\n"
        print   "names with spaces: \"in quotes\"; ctrl-C stops the foreground job\n"
        rts

b_exit: exit    0

; restart [full]: asks the Desktop (it closes the programs first); without one, asks here
b_restart:
        jsr     getword
        stz     z:t0                    ; 0 Horizon only, 1 full ("full")
        cmp     #0
        beq     :+
        lda     fname
        ora     #$2020
        cmp     #'f' | ('u' << 8)
        jne     @use
        inc     z:t0
:       lda     z:t0
        clc
        adc     #SR_RESTART
        sys     SYS_SYSREQ
        bcs     :+
        rts                             ; the Desktop does it
:       print   "Restart Horizon? All programs will be closed (y/n) "
        jsr     yesno
        jcs     @out
        jsr     out_flush
        jsr     ui_clksave              ; (the clock for the next start)
        lda     z:t0
        sys     SYS_RESTART
        pha
        print   "restart: the machine cannot be restarted, error $"
        pla
        jsr     put_hex8
        jmp     put_nl
@use:   print   "usage: restart [full]\n"
@out:   rts

; shutdown: asks the Desktop; without one: every other program ends, the files are closed,
; the card is flushed, then "It is now safe to switch off" (R: restart)
b_shutdown:
        lda     #SR_SHUTDOWN
        sys     SYS_SYSREQ
        bcs     :+
        rts
:       print   "Shut down the Atari816? All programs will be closed (y/n) "
        jsr     yesno
        jcs     @out
        jsr     out_flush
        jsr     ui_clksave
        lda     #1
        sys     SYS_SYNC
        bcc     :+
        pha
        print   "shutdown: the card could not be synced, error $"
        pla
        jsr     put_hex8
        jsr     put_nl
:       lda     #12                     ; the screen cleared
        jsr     out_char
        print   "\n\n\n\n\n\n\n\n\n\n\n\n                       It is now safe to switch off the Atari816.\n\n"
        print   "                              Press R to restart.\n"
        jsr     out_flush
@key:   jsr     read_char
        ora     #$20
        cmp     #'r'
        bne     @key
        lda     #1
        sys     SYS_RESTART
@out:   rts

; a y / n answer (echoed) -> C clear: yes
yesno:  jsr     out_flush
:       jsr     read_char
        ora     #$20
        cmp     #'y'
        beq     :+
        cmp     #'n'
        bne     :-
        print   "n\n"
        sec
        rts
:       print   "y\n"
        clc
        rts

; (0.14) date: the date and time; date YYYY-MM-DD HH:MM[:SS] sets the clock (and saves it
; in /SYSTEM/CLOCK: the board has no battery clock)
b_date: jsr     getword
        cmp     #0
        jeq     @show
        ldx     #.loword(fname)         ; the date, then the time: one string
        ldy     #.loword(dbuf)
        jsr     scpy
        sta     z:t0
        tax
        lda     #' '
        sta     dbuf,x
        jsr     getword
        cmp     #0
        jeq     @use
        lda     z:t0
        clc
        adc     #.loword(dbuf + 1)
        tay
        ldx     #.loword(fname)
        jsr     scpy
        ldx     #.loword(dbuf)
        jsr     ui_clkparse
        jcs     @use
        jsr     ui_clkjoin
        ldy     #CLK_SET
        sys     SYS_TSET
        jsr     ui_clksave
@show:  sys     SYS_TGET
        cpy     #CLK_NONE
        bne     :+
        print   "date: not set (date YYYY-MM-DD HH:MM sets it)\n"
        rts
:       phy
        jsr     ui_clksplit
        ldy     #.loword(dbuf)
        jsr     ui_clklong
        ldx     #.loword(dbuf)
        ldy     #^dbuf
        jsr     out_str
        lda     #' '
        jsr     out_char
        ldy     #.loword(dbuf)
        jsr     ui_clkfmt
        ldx     #.loword(dbuf + 11)     ; (the time part)
        ldy     #^dbuf
        jsr     out_str
        ply
        cpy     #CLK_SET
        beq     :+
        print   " (the last time saved: not set yet)"
:       jmp     put_nl
@use:   print   "usage: date [YYYY-MM-DD HH:MM[:SS]]\n"
        rts
; copy the string X to Y (program bank) -> A = its length
scpy:   sty     z:t1
        sep     #$20
        .a8
:       lda     a:0,x
        sta     a:0,y
        beq     :+
        inx
        iny
        bra     :-
:       rep     #$20
        .a16
        tya
        sec
        sbc     z:t1
        rts

b_cls:  lda     #12                     ; form feed: clear the screen
        jsr     out_char
        jmp     out_flush

; show the classic Atari until the system key
b_atari:
        print   "F12 returns to Horizon\n"
        jsr     out_flush
        sys     SYS_CLASSIC
        bcc     :+
        print   "atari: the keyboard is not ours\n"
:       rts

b_mem:  sys     SYS_MINFO
        stx     z:t0
        sta     z:t1
        jsr     put_dec
        print   " of "
        lda     z:t0
        jsr     put_dec
        print   " banks free ("
        lda     z:t1
        xba                             ; * 64 KB
        lsr     a
        lsr     a
        jsr     put_dec
        print   " KB)\n"
        rts

b_kill: jsr     parse_dec
        bcs     :+
        sys     SYS_KILL
        bcc     @ok
        print   "kill: no such task\n"
@ok:    rts
:       print   "usage: kill id\n"
        rts

; cd [path] (no path: "/")
b_cd:   jsr     getword
        bne     :+
        lda     #'/'
        sta     fname
:       ldx     #.loword(fname)
        ldy     #^fname
        sys     SYS_CHDIR
        bcc     @ok
        pha
        print   "cd: "
        pla
        cmp     #EINVAL
        bne     :+
        print   "not a directory (or too long)\n"
        rts
:       jsr     errmsg
        jmp     put_nl
@ok:    rts

b_pwd:  ldx     #.loword(fname)
        ldy     #^fname
        lda     #128
        sys     SYS_GETCWD
        ldx     #.loword(fname)
        ldy     #^fname
        jsr     out_str
        jmp     put_nl

b_ps:   print   " ID STATE  PRI BANKS PARENT NAME\n"
        stz     z:t2
@slot:  lda     z:t2
        jsr     tinfo
        lda     info
        and     #$00FF
        beq     @next
        ldx     #3
        jsr     put_decw
        lda     #' '
        jsr     out_char
        lda     info+1                  ; state name, 6 characters
        and     #$00FF
        asl     a
        asl     a
        asl     a
        clc
        adc     #.loword(states)
        tax
        ldy     #^states
        jsr     out_str
        lda     info+2
        and     #$00FF
        ldx     #3
        jsr     put_decw
        lda     info+3
        and     #$00FF
        ldx     #6
        jsr     put_decw
        lda     info+4
        and     #$00FF
        ldx     #7
        jsr     put_decw
        lda     #' '
        jsr     out_char
        ldx     #0
:       lda     info+5,x
        and     #$00FF
        cmp     #' '
        beq     :+
        phx
        jsr     out_char
        plx
        inx
        cpx     #8
        bcc     :-
:       jsr     put_nl
@next:  inc     z:t2
        lda     z:t2
        cmp     #16
        bcc     @slot
        rts

; ls / dir [path]: one entry per line, the name column as wide as the screen allows, sizes
; right-aligned; a page at a time (any key: next page, q / Esc / ctrl-C: stop)
b_dir:  jsr     getword
        bne     :+
        lda     #'.'
        sta     fname
:       stz     z:t2                    ; entries to skip
        stz     z:lines
        lda     z:cols                  ; name column
        sec
        sbc     #12
        sta     z:namew
@call:  lda     #.loword(fname)         ; block: path, buffer, length, skip
        sta     blk
        lda     #^fname
        sta     blk+2
        lda     #.loword(dbuf)
        sta     blk+3
        lda     #^dbuf
        sta     blk+5                   ; (16-bit: high byte of length rewritten below)
        lda     #DBUFLEN
        sta     blk+6
        lda     z:t2
        sta     blk+8
        ldx     #.loword(blk)
        ldy     #^blk
        sys     SYS_READDIR
        bcc     :+
        pha
        print   "dir: "
        pla
        jsr     errmsg
        jmp     put_nl
:       cmp     #0
        bne     :+
        rts
:       sta     z:t0                    ; entries in this batch
        clc
        adc     z:t2
        sta     z:t2
        ldx     #0
@ent:   stx     z:t1
        jsr     more                    ; page full? (C set: stop)
        bcc     :+
        rts
:       print   "  "
        ldx     z:t1
        lda     dbuf+5,x
        and     #$00FF
        sta     z:t3                    ; name length
        stz     z:t4                    ; characters printed
@ch:    lda     z:t4
        cmp     z:t3
        bcs     @pad
        inc     a
        cmp     z:namew                 ; longer than the column: the last one shows '>'
        bcc     :+
        lda     z:t3
        cmp     z:namew
        beq     :+
        lda     #'>'
        jsr     out_char
        inc     z:t4
        bra     @pad
:       lda     z:t1
        clc
        adc     z:t4
        tax
        lda     dbuf+6,x
        jsr     out_char
        inc     z:t4
        bra     @ch
@pad:   lda     z:t4
        cmp     z:namew
        bcs     :+
        lda     #' '
        jsr     out_char
        inc     z:t4
        bra     @pad
:       ldx     z:t1
        lda     dbuf+4,x
        and     #$10
        beq     :+
        print   "     <DIR>\n"
        bra     @nx
:       lda     dbuf,x                  ; size: 24 bits as KB above 65535 bytes
        sta     z:t4
        lda     dbuf+2,x
        and     #$00FF
        beq     :+
        lda     dbuf+1,x                ; size / 1024 (rounded down), "K"
        lsr     a
        lsr     a
        ldx     #9
        jsr     put_decw
        print   "K\n"
        bra     @nx
:       lda     z:t4
        ldx     #10
        jsr     put_decw
        jsr     put_nl
@nx:    inc     z:lines
        lda     z:t1
        clc
        adc     #6
        ldx     z:t1
        pha
        lda     dbuf+5,x
        and     #$00FF
        sta     z:t3
        pla
        clc
        adc     z:t3
        tax
        dec     z:t0
        beq     :+
        jmp     @ent
:       jmp     @call

; before a dir line: after rows - 1 lines, ask for a key. C set = stop.
more:   lda     z:lines
        inc     a
        cmp     z:rows
        bcs     :+
        clc
        rts
:       stz     z:lines
        print   "-- more: any key, q to stop --"
        jsr     out_flush
        jsr     read_char
        pha
        lda     #13                     ; erase the prompt line
        jsr     out_char
        lda     #27
        jsr     out_char
        lda     #'K'
        jsr     out_char
        jsr     out_flush
        pla
        cmp     #'q'
        beq     @stop
        cmp     #'Q'
        beq     @stop
        cmp     #27
        beq     @stop
        cmp     #3
        beq     @stop
        clc
        rts
@stop:  sec
        rts

; cat file
b_cat:  jsr     getword
        bne     :+
        print   "usage: cat file\n"
        rts
:       ldx     #.loword(fname)
        ldy     #^fname
        lda     #0
        sys     SYS_OPEN
        bcc     :+
        pha
        print   "cat: "
        pla
        jsr     errmsg
        jmp     put_nl
:       sta     blk                     ; block: handle, buffer, length
        lda     #.loword(dbuf)
        sta     blk+1
        sep     #$20
        .a8
        lda     #^dbuf
        sta     blk+3
        rep     #$20
        .a16
        lda     #63
        sta     blk+4
@more:  ldx     #.loword(blk)
        ldy     #^blk
        sys     SYS_READ
        bcs     @done
        cmp     #0
        beq     @done
        tax
        sep     #$20
        .a8
        stz     dbuf,x
        rep     #$20
        .a16
        ldx     #.loword(dbuf)
        ldy     #^dbuf
        jsr     out_str
        bra     @more
@done:  jsr     out_flush               ; a last line without '\n'
        lda     blk
        and     #$00FF
        sys     SYS_CLOSE
        rts

; ---------------------------------------------------------------- files
; rm path... : delete each (files, and empty folders)
b_rm:   stz     z:t0
@next:  jsr     getword
        bne     @one
        lda     z:t0
        bne     :+
        print   "usage: rm path...\n"
:       rts
@one:   inc     z:t0
        ldx     #.loword(fname)
        ldy     #^fname
        sys     SYS_DELETE
        bcc     @next
        pha
        print   "rm: "
        jsr     pr_fname
        pla
        jsr     errmsg
        jsr     put_nl
        bra     @next

; mkdir path
b_mkdir:
        jsr     getword
        bne     :+
        print   "usage: mkdir path\n"
        rts
:       ldx     #.loword(fname)
        ldy     #^fname
        sys     SYS_MKDIR
        bcc     :+
        pha
        print   "mkdir: "
        jsr     pr_fname
        pla
        jsr     errmsg
        jmp     put_nl
:       rts

; "name: " for an error message
pr_fname:
        ldx     #.loword(fname)
        ldy     #^fname
        jsr     out_str
        print   ": "
        rts

; the two names of mv / cp: fname = from, fname2 = to (a folder: to/<last part of from>).
; C set: usage printed
two_names:
        jsr     getword
        jeq     @use
        ldx     #.loword(fname2)
        ldy     #^fname2
        lda     #128
        jsr     next_arg
        jeq     @use
        lda     #.loword(fname2)        ; "to" a folder?
        sta     sblk
        lda     #.loword(dbuf)
        sta     sblk+3
        sep     #$20
        .a8
        lda     #^fname2
        sta     sblk+2
        lda     #^dbuf
        sta     sblk+5
        rep     #$20
        .a16
        ldx     #.loword(sblk)
        ldy     #^sblk
        sys     SYS_STAT
        bcs     @ok
        lda     dbuf+4
        and     #$0010
        beq     @ok
        ldx     #0                      ; the last part of "from" (after the last '/')
        ldy     #0
:       lda     fname,y
        and     #$00FF
        beq     :++
        cmp     #'/'
        bne     :+
        tya
        inc     a
        tax
:       iny
        bra     :--
:       stx     z:t1
        ldy     #0                      ; the end of "to"
:       lda     fname2,y
        and     #$00FF
        beq     :+
        iny
        bra     :-
:       dey
        lda     fname2,y                ; add a '/' unless there is one
        and     #$00FF
        cmp     #'/'
        beq     :+
        iny
        lda     #'/'
        jsr     @put
:       iny
        ldx     z:t1
:       lda     fname,x
        and     #$00FF
        jsr     @put
        cmp     #0
        beq     @ok
        inx
        iny
        cpy     #250
        bcc     :-
@ok:    clc
        rts
@use:   sec
        rts
@put:   sep     #$20
        .a8
        sta     fname2,y
        rep     #$20
        .a16
        rts

; mv from to: rename, or move on the card
b_mv:   jsr     two_names
        bcc     :+
        print   "usage: mv from to\n"
        rts
:       lda     #.loword(fname)
        sta     sblk
        lda     #.loword(fname2)
        sta     sblk+3
        sep     #$20
        .a8
        lda     #^fname
        sta     sblk+2
        lda     #^fname2
        sta     sblk+5
        rep     #$20
        .a16
        ldx     #.loword(sblk)
        ldy     #^sblk
        sys     SYS_RENAME
        bcc     :+
        pha
        print   "mv: "
        jsr     pr_fname
        pla
        jsr     errmsg
        jmp     put_nl
:       rts

; cp from to: copy a file, 32 KB at a time through a bank of its own
b_cp:   jsr     two_names
        bcc     :+
        print   "usage: cp from to\n"
        rts
:       ldx     #.loword(fname)
        ldy     #^fname
        lda     #O_READ
        sys     SYS_OPEN
        bcc     :+
        pha
        print   "cp: "
        jsr     pr_fname
        pla
        jsr     errmsg
        jmp     put_nl
:       sta     z:t2                    ; source handle
        ldx     #.loword(fname2)
        ldy     #^fname2
        lda     #O_CREATE
        sys     SYS_OPEN
        bcc     :+
        pha
        print   "cp: "
        ldx     #.loword(fname2)
        ldy     #^fname2
        jsr     out_str
        print   ": "
        pla
        jsr     errmsg
        jsr     put_nl
        bra     @close1
:       sta     z:t3                    ; destination handle
        sys     SYS_BALLOC
        bcc     :+
        print   "cp: no memory\n"
        bra     @close2
:       sta     z:t4                    ; the buffer bank
@loop:  lda     z:t2                    ; read up to 32 KB
        jsr     @blk
        sys     SYS_READ
        bcs     @err
        cmp     #0
        beq     @done
        sta     blk+4
        lda     z:t3                    ; write them
        sep     #$20
        .a8
        sta     blk
        rep     #$20
        .a16
        ldx     #.loword(blk)
        ldy     #^blk
        sys     SYS_WRITE
        bcs     @err
        bra     @loop
@err:   pha
        print   "cp: "
        pla
        jsr     errmsg
        jsr     put_nl
@done:  lda     z:t4
        sys     SYS_BFREE
@close2:
        lda     z:t3
        sys     SYS_CLOSE
@close1:
        lda     z:t2
        sys     SYS_CLOSE
        rts
@blk:   sep     #$20                    ; block {handle A, buffer t4:0000, 32768}
        .a8
        sta     blk
        lda     z:t4
        sta     blk+3
        rep     #$20
        .a16
        stz     blk+1
        lda     #32768
        sta     blk+4
        ldx     #.loword(blk)
        ldy     #^blk
        rts

; ---------------------------------------------------------------- Atari software
; mount file [drive 1-4]: the kind comes from the extension (adds to what is mounted)
b_mount:
        jsr     getword
        bne     :+
        print   "usage: mount file [1-4]\n"
        rts
:       lda     #1                      ; drive: default D1:
        sta     z:t2
        jsr     str_skip
        cmp     #0
        beq     @go
        jsr     parse_dec
        bcs     @bad
        sta     z:t2
        dec     a
        cmp     #4
        bcs     @bad
        jsr     str_skip
        cmp     #0
        beq     @go
@bad:   print   "mount: the drive must be 1-4\n"
        rts
@go:    lda     z:t2
        dec     a
        xba
        ldx     #.loword(fname)
        ldy     #^fname
        sys     SYS_CMOUNT
        bcc     :+
        pha
        print   "mount: "
        pla
        jmp     cerr
:       sta     z:t1
        ldx     #.loword(fname)
        ldy     #^fname
        jsr     out_str
        lda     z:t1
        cmp     #1
        bne     :+
        print   " is in D"
        lda     z:t2
        jsr     put_dec
        print   ":\n"
        rts
:       cmp     #2
        bne     :+
        print   " is the executable (it boots from D1:)\n"
        rts
:       print   " is the cartridge\n"
        rts

; eject d1-d4 | cart | xex
b_eject:
        jsr     getword
        lda     fname                   ; "d1".."d4"
        and     #$FFDF                  ; (upper case first letter)
        cmp     #'D' | ('1' << 8)
        bcc     @word
        cmp     #'D' | ('5' << 8)
        bcs     @word
        lda     fname + 2
        and     #$00FF
        bne     @word
        lda     fname + 1
        and     #$00FF
        sec
        sbc     #'1'
        xba
        ora     #1                      ; disk, slot
        bra     @do
@word:  ldx     #.loword(w_cart)
        jsr     fname_is
        bne     :+
        lda     #3
        bra     @do
:       ldx     #.loword(w_xex)
        jsr     fname_is
        bne     :+
        lda     #2
        bra     @do
:       print   "usage: eject d1-d4|cart|xex\n"
        rts
@do:    sys     SYS_CEJECT
        bcc     :+
        pha
        print   "eject: "
        pla
        jmp     cerr
:       rts

; boot: cold boot with what is mounted, then the Atari until F12
b_boot: print   "booting the Atari: F12 returns to Horizon\n"
        jsr     out_flush
        sys     SYS_CBOOT
        bcc     :+
        pha
        print   "boot: "
        pla
        jmp     cerr
:       rts

; run file: start this, and only this (see ulib atari_run)
b_run:  jsr     getword
        bne     :+
        print   "usage: run file\n"
        rts
:       print   "booting the Atari: F12 returns to Horizon\n"
        jsr     out_flush
        ldx     #.loword(fname)
        ldy     #^fname
        jsr     atari_run
        bcc     :+
        pha
        print   "run: "
        pla
        jmp     cerr
:       rts

; print the meaning of a classic op error A, and a newline
cerr:   cmp     #$44
        jeq     @nf
        cmp     #$45
        jeq     @nf
        cmp     #$C3
        bne     :+
        print   "unknown file type (.atr .xfd .xex .com .exe .car .rom .bin)\n"
        rts
:       cmp     #$C4
        bne     :+
        print   "not a valid or supported image\n"
        rts
:       cmp     #$C5
        bne     :+
        print   "the firmware menu is open: close it and try again\n"
        rts
:       cmp     #$C2
        bne     :+
        print   "not supported by this firmware: update it\n"
        rts
:       cmp     #1
        bne     :+
        print   "the keyboard is not ours\n"
        rts
:       pha
        print   "error $"
        pla
        jsr     put_hex8
        jmp     put_nl
@nf:    print   "file not found\n"
        rts

; fname equal (case-insensitive) to the lower-case word at X (this bank)? Z set = yes
fname_is:
        ldy     #0
:       lda     a:0,x
        and     #$00FF
        sta     z:t3
        lda     fname,y
        and     #$00FF
        cmp     #'A'
        bcc     :+
        cmp     #'Z' + 1
        bcs     :+
        ora     #$20
:       cmp     z:t3
        bne     :+
        cmp     #0
        beq     :+
        inx
        iny
        bra     :--
:       rts

        .segment "RODATA"
w_cart: .byte   "cart", 0
w_xex:  .byte   "xex", 0
bnames: .byte   "help", 0, 0, 0, 0
        .byte   "dir", 0, 0, 0, 0, 0
        .byte   "cat", 0, 0, 0, 0, 0
        .byte   "ps", 0, 0, 0, 0, 0, 0
        .byte   "mem", 0, 0, 0, 0, 0
        .byte   "kill", 0, 0, 0, 0
        .byte   "exit", 0, 0, 0, 0
        .byte   "cls", 0, 0, 0, 0, 0
        .byte   "atari", 0, 0, 0
        .byte   "mount", 0, 0, 0
        .byte   "eject", 0, 0, 0
        .byte   "boot", 0, 0, 0, 0
        .byte   "run", 0, 0, 0, 0, 0
        .byte   "cd", 0, 0, 0, 0, 0, 0
        .byte   "pwd", 0, 0, 0, 0, 0
        .byte   "ls", 0, 0, 0, 0, 0, 0
        .byte   "rm", 0, 0, 0, 0, 0, 0
        .byte   "mkdir", 0, 0, 0
        .byte   "mv", 0, 0, 0, 0, 0, 0
        .byte   "cp", 0, 0, 0, 0, 0, 0
        .byte   "restart", 0
        .byte   "shutdown"              ; (8 characters: the table's end is its terminator)
        .byte   "date", 0, 0, 0, 0
        .byte   0
bfuncs: .addr   b_help, b_dir, b_cat, b_ps, b_mem, b_kill, b_exit, b_cls, b_atari
        .addr   b_mount, b_eject, b_boot, b_run, b_cd, b_pwd, b_dir
        .addr   b_rm, b_mkdir, b_mv, b_cp, b_restart, b_shutdown, b_date
; the search path for a command word
pfxs:   .addr   pf_bin, pf_sys, pf_tests
NPFX    = (* - pfxs) / 2
pf_bin: .byte   "/BIN/", 0
pf_sys: .byte   "/SYSTEM/", 0
pf_tests: .byte "/SYSTEM/TESTS/", 0
binsuf: .byte   ".PRG", 0
states: .byte   "FREE  ", 0, 0
        .byte   "READY ", 0, 0
        .byte   "RUN   ", 0, 0
        .byte   "BLOCK ", 0, 0
        .byte   "ZOMBIE", 0, 0

        .segment "BSS"
DBUFLEN = 256
line:   .res    LINEMAX + 2
cmd:    .res    16
cmdraw: .res    128
fname:  .res    128
fname2: .res    256
path:   .res    128
info:   .res    16
blk:    .res    10
sblk:   .res    6
dbuf:   .res    DBUFLEN + 2
jobs:   .res    NJOBS * 2

        .segment "ZEROPAGE"
pfx:    .res    2                       ; the search path's folder tried (* 2)
search: .res    2                       ; non-zero: a command word (try the next folder)
t0:     .res    2
t1:     .res    2
t2:     .res    2
t3:     .res    2
t4:     .res    2
bg:     .res    2
job:    .res    2
alen:   .res    2
aoff:   .res    2
cols:   .res    2
rows:   .res    2
lines:  .res    2
namew:  .res    2
sp:     .res    4
