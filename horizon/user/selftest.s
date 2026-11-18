; SELFTEST - the regression script (run by the test INIT, or from the shell). Runs the
; demo programs, spawning them and waiting for each, then exits.
; It claims the keyboard first, so key events queue up (whenever the test's --keys script
; sends them) until KEYS, at the end, gets the keyboard lent and reads them.
        .include "horizon.inc"

        .segment "CODE"
        .a16
        .i16
start:  sys     SYS_ICLAIM
        print   "selftest: start\n"

        ldx     #.loword(p_hello)       ; 1. hello
        ldy     #0
        jsr     go
        jsr     wait_p

        ldx     #.loword(p_count)       ; 2. two counters at once
        ldy     #.loword(a_a)
        jsr     go
        sta     z:id1
        ldx     #.loword(p_count)
        ldy     #.loword(a_b)
        jsr     go
        sta     z:id2
        lda     z:id1
        jsr     wait_p
        lda     z:id2
        jsr     wait_p

        ldx     #.loword(p_spin)        ; 3. a CPU hog, a sleeper and a context checker
        ldy     #0
        jsr     go
        sta     z:id1
        ldx     #.loword(p_tick)
        ldy     #0
        jsr     go
        sta     z:id2
        ldx     #.loword(p_regs)
        ldy     #0
        jsr     go
        sta     z:id3
        lda     z:id2                   ; TICK ends while SPIN still runs: preemption
        jsr     wait_p
        lda     z:id1
        jsr     alive
        bcs     :+
        print   "selftest: TICK finished while SPIN still ran\n"
        bra     :++
:       print   "selftest: SPIN finished before TICK (no preemption?)\n"
:       lda     z:id1
        jsr     wait_p
        lda     z:id3
        jsr     wait_p

        lda     #1                      ; 4. crashes (modes 1-12), all at once
        sta     z:mode
:       lda     z:mode                  ; argument string = the mode in decimal
        cmp     #10
        bcc     :+
        sbc     #10
        ora     #'0' | ($00 << 8)
        xba
        ora     #'1'
        bra     :++
:       ora     #'0'
:       sta     argbuf
        stz     argbuf+2
        ldx     #.loword(p_crash)
        ldy     #.loword(argbuf)
        jsr     go
        pha
        lda     z:mode
        dec     a
        asl     a
        tax
        pla
        sta     z:ids,x
        inc     z:mode
        lda     z:mode
        cmp     #NCRASH + 1
        bcc     :---
        lda     #100                    ; mode 9 sleeps forever: kill it
        sys     SYS_SLEEP
        lda     z:ids + 16
        sys     SYS_KILL
        bcc     :+
        print   "selftest: kill failed\n"
:       ldx     #0
:       phx
        lda     z:ids,x
        jsr     wait_p
        plx
        inx
        inx
        cpx     #NCRASH * 2
        bcc     :-
        ldx     #.loword(p_crash)       ;    mode 13: SEI forever, ended by the watchdog
        ldy     #.loword(a_13)
        jsr     go
        jsr     wait_p

        ldx     #.loword(p_cat)         ; 5. files
        ldy     #0
        jsr     go
        jsr     wait_p
        ldx     #.loword(p_cat)         ;    two at once: both talk to the I/O processor
        ldy     #0
        jsr     go
        sta     z:id1
        ldx     #.loword(p_cat)
        ldy     #0
        jsr     go
        sta     z:id2
        lda     z:id1
        jsr     wait_p
        lda     z:id2
        jsr     wait_p
        ldx     #.loword(p_files)
        ldy     #0
        jsr     go
        jsr     wait_p
        ldx     #.loword(p_dir)
        ldy     #0
        jsr     go
        jsr     wait_p

        ldx     #.loword(p_mem)         ; 6. memory
        ldy     #0
        jsr     go
        jsr     wait_p
        sys     SYS_MINFO
        stx     z:id1
        pha
        print   "selftest: mem_info "
        pla
        jsr     put_dec
        print   " free of "
        lda     z:id1
        jsr     put_dec
        jsr     put_nl

        ldx     #.loword(p_ping)        ; 7. message ports (PING starts PONG)
        ldy     #0
        jsr     go
        jsr     wait_p

        ldx     #.loword(p_nope)        ; 8. a missing program
        ldy     #0
        jsr     go

        ldx     #.loword(p_keys)        ; 9. keyboard: lent to KEYS
        ldy     #0
        jsr     go
        sta     z:id1
        ldx     #0
        sys     SYS_ILEND
        bcc     :+
        print   "selftest: input_lend failed\n"
:       lda     z:id1
        jsr     wait_p
        sys     SYS_ICLAIM              ; it came back to us
        bcc     :+
        print   "selftest: the keyboard did not come back\n"
:       ldx     #.loword(p_mtest)       ; 10. mouse queue: lent to MTEST
        ldy     #0
        jsr     go
        sta     z:id1
        ldx     #0
        sys     SYS_ILEND
        lda     z:id1
        jsr     wait_p
        sys     SYS_IRELEASE

        print   "selftest: done\n"
        exit    0

NCRASH = 12

; spawn path X with arguments Y (offsets in this bank, Y = 0: none), priority 2.
; Returns A = id (0 on error, printed).
go:     sty     z:u_arg
        lda     #^p_hello
        sta     z:u_arg+2
        cpy     #0
        bne     :+
        stz     z:u_arg+2
:       ldy     #^p_hello
        lda     #2
        jsr     spawn
        bcc     :+
        pha
        print   "selftest: spawn error "
        pla
        jsr     put_hex8
        jsr     put_nl
        lda     #0
:       rts

; wait for task A and print its exit code
wait_p: cmp     #0
        beq     @out
        sta     z:wid
        sys     SYS_WAIT
        sta     z:code
        bcc     :+
        print   "selftest: wait error "
        lda     z:code
        jsr     put_hex8
        jsr     put_nl
        rts
:       print   "selftest: task "
        lda     z:wid
        jsr     put_dec
        print   " exit "
        lda     z:code
        jsr     put_hex16
        jsr     put_nl
@out:   rts

; is task A alive (and not a zombie)? C clear = yes
alive:  sta     z:wid
        ldx     #0
@loop:  phx
        txa
        lsr     a
        ldx     #.loword(info)
        ldy     #^info
        sys     SYS_TINFO
        plx
        lda     info
        and     #$00FF
        cmp     z:wid
        bne     @next
        lda     info+1
        and     #$00FF
        cmp     #4                      ; zombie
        beq     @no
        clc
        rts
@next:  inx
        inx
        cpx     #32
        bcc     @loop
@no:    sec
        rts

        .segment "RODATA"
p_hello: .byte  "/SYSTEM/TESTS/HELLO.PRG", 0
p_count: .byte  "/SYSTEM/TESTS/COUNT.PRG", 0
p_spin:  .byte  "/SYSTEM/TESTS/SPIN.PRG", 0
p_tick:  .byte  "/SYSTEM/TESTS/TICK.PRG", 0
p_regs:  .byte  "/SYSTEM/TESTS/REGS.PRG", 0
p_crash: .byte  "/SYSTEM/TESTS/CRASH.PRG", 0
p_cat:   .byte  "/BIN/CAT.PRG", 0
p_files: .byte  "/SYSTEM/TESTS/FTEST.PRG", 0
p_dir:   .byte  "/BIN/DIR.PRG", 0
p_mem:   .byte  "/BIN/MEM.PRG", 0
p_ping:  .byte  "/SYSTEM/TESTS/PING.PRG", 0
p_nope:  .byte  "/SYSTEM/TESTS/NOPE.PRG", 0
p_keys:  .byte  "/SYSTEM/TESTS/KEYS.PRG", 0
p_mtest: .byte  "/SYSTEM/TESTS/MTEST.PRG", 0
a_a:     .byte  "A", 0
a_b:     .byte  "B", 0
a_13:    .byte  "13", 0

        .segment "BSS"
argbuf: .res    4
info:   .res    16

        .segment "ZEROPAGE"
id1:    .res    2
id2:    .res    2
id3:    .res    2
mode:   .res    2
wid:    .res    2
code:   .res    2
ids:    .res    NCRASH * 2
