; syscall.s - syscall table and the small syscalls.
; A handler runs on the caller's kernel stack (a16 i16, D = KDP, DBR = $01) and finds the
; arguments in the saved registers t_a / t_x / t_y. It returns its result with set_ok /
; set_err (A = value / error code); that sets the saved A and the carry flag of the saved P.

        .a16
        .i16

sys_tab:
        .word   .loword(sys_exit), .loword(sys_yield), .loword(sys_sleep), .loword(sys_getpid), .loword(sys_uptime), .loword(sys_putc), .loword(sys_puts)    ; $00
        .word   .loword(sys_csize), .loword(sys_chdir), .loword(sys_getcwd), .loword(sys_restart), .loword(sys_sync), .loword(sys_sysreq), .loword(sys_tget)
        .word   .loword(sys_tset), .loword(sys_vsync)
        .word   .loword(sys_balloc), .loword(sys_bfree), .loword(sys_minfo)    ; $10
        .word   .loword(sys_nosys), .loword(sys_nosys), .loword(sys_nosys), .loword(sys_nosys), .loword(sys_nosys), .loword(sys_nosys)
        .word   .loword(sys_nosys), .loword(sys_nosys), .loword(sys_nosys), .loword(sys_nosys), .loword(sys_nosys), .loword(sys_nosys), .loword(sys_nosys)
        .word   .loword(sys_open), .loword(sys_close), .loword(sys_read), .loword(sys_write), .loword(sys_seek), .loword(sys_stat), .loword(sys_readdir)    ; $20
        .word   .loword(sys_delete), .loword(sys_mkdir), .loword(sys_rename)
        .word   .loword(sys_nosys), .loword(sys_nosys), .loword(sys_nosys), .loword(sys_nosys), .loword(sys_nosys), .loword(sys_nosys)
        .assert (* - sys_tab) = $30 * 2, error, "syscall table: spawn must be $30"
        .word   .loword(sys_spawn), .loword(sys_wait), .loword(sys_kill), .loword(sys_tinfo)    ; $30
        .word   .loword(sys_single), .loword(sys_nosys), .loword(sys_nosys), .loword(sys_nosys), .loword(sys_nosys), .loword(sys_nosys)
        .word   .loword(sys_nosys), .loword(sys_nosys), .loword(sys_nosys), .loword(sys_nosys), .loword(sys_nosys), .loword(sys_nosys)
        .word   .loword(sys_pcreate), .loword(sys_send), .loword(sys_recv), .loword(sys_pclose)    ; $40
        .word   .loword(sys_nosys), .loword(sys_nosys), .loword(sys_nosys), .loword(sys_nosys), .loword(sys_nosys), .loword(sys_nosys), .loword(sys_nosys)
        .word   .loword(sys_nosys), .loword(sys_nosys), .loword(sys_nosys), .loword(sys_nosys), .loword(sys_nosys)
        .word   .loword(sys_iclaim), .loword(sys_iread), .loword(sys_irelease), .loword(sys_ilend), .loword(sys_ipoll)
        .word   .loword(sys_joy), .loword(sys_nosys), .loword(sys_nosys), .loword(sys_nosys), .loword(sys_nosys)
        .word   .loword(sys_nosys), .loword(sys_nosys), .loword(sys_nosys), .loword(sys_nosys), .loword(sys_nosys), .loword(sys_minject)  ; $5F
        .word   .loword(sys_classic), .loword(sys_cmount), .loword(sys_ceject), .loword(sys_cboot)  ; $60
        .word   .loword(sys_cquery), .loword(sys_beep), .loword(sys_sndw), .loword(sys_chime), .loword(sys_splay), .loword(sys_sstop)
        .word   .loword(sys_sstat), .loword(sys_sset), .loword(sys_stimer), .loword(sys_nosys), .loword(sys_nosys), .loword(sys_nosys)    ; $6A (0.17: $68-$6B Lau; 0.26: $6C the music timer)
        .assert (* - sys_tab) = $70 * 2, error, "syscall table: ws_start must be $70"
        .word   .loword(sys_wsstart), .loword(sys_wsstop), .loword(sys_wopen), .loword(sys_wclose)  ; $70
        .word   .loword(sys_wdraw), .loword(sys_wevent), .loword(sys_wtwidth), .loword(sys_wssync)
        .word   .loword(sys_wmove), .loword(sys_wsredraw), .loword(sys_wsstats), .loword(sys_wscfg)
        .word   .loword(sys_wtimer), .loword(sys_wmenu), .loword(sys_wstat), .loword(sys_wterm)
        .assert (* - sys_tab) = $80 * 2, error, "syscall table: clip_put must be $80"
        .word   .loword(sys_clput), .loword(sys_clget), .loword(sys_winfo), .loword(sys_winat)
        .word   .loword(sys_wdrop), .loword(sys_wdropget), .loword(sys_wspal), .loword(sys_setting)
        .word   .loword(sys_wtitle), .loword(sys_wptr), .loword(sys_wmouse), .loword(sys_wshold)    ; $88
        .word   .loword(sys_wmstate), .loword(sys_wscloseall), .loword(sys_wgeom), .loword(sys_tname) ; $8C
        .word   .loword(sys_wpopup)     ; $90
        .repeat K2_NSYS - $91           ; (0.18) $91-: the second code segment (k2.s)
        .word   .loword(sys_k2)
        .endrepeat
        .word   .loword(sys_wfront)     ; $A0 (BASIC 2.0)
        .word   .loword(sys_k3), .loword(sys_k3), .loword(sys_k3)   ; $A1-$A3 (0.19): sheets, k3.s
        .assert (* - sys_tab) / 2 = K3_NSYS, error, "syscall table: K3_SYS0 .. K3_NSYS - 1 go to k3.s"
NSYS = (* - sys_tab) / 2

; (0.18) $91-: k2.s dispatches them (X = number * 2)
sys_k2: jsl     k2_sys
        rts
; (0.19) $A1-: k3.s (the third code segment) dispatches them (X = number * 2)
sys_k3: jsl     k3_sys
        rts

; ---- result helpers ----
set_ok: ldx     cur
        sta     t_a,x
        lda     t_p,x
        and     #$FFFE
        sta     t_p,x
        rts
set_err:
        ldx     cur
        sta     t_a,x
        lda     t_p,x
        ora     #$0001
        sta     t_p,x
        rts
err_inval:
        lda     #EINVAL
        bra     set_err
err_fault:
        lda     #EFAULT
        bra     set_err

sys_nosys:
        lda     #ENOSYS
        bra     set_err

; $00 exit(A = code)
sys_exit:
        ldx     cur
        lda     t_a,x
        jmp     do_exit

; $01 yield
sys_yield:
        lda     #1
        sta     need_resched
        lda     #0
        bra     set_ok

; $02 sleep(A = milliseconds), 10 ms resolution, rounded up
sys_sleep:
        ldx     cur
        lda     t_a,x
        beq     sys_yield
        ldx     #10
        jsr     udiv16
        cpx     #0
        beq     :+
        inc     a
:       jsr     k_sleep_ticks
        lda     #0
        bra     set_ok

; $03 getpid -> A = task id
sys_getpid:
        ldx     cur
        lda     t_id,x
        bra     set_ok

; $04 uptime -> A = milliseconds low, X = high (10 ms resolution)
sys_uptime:
        ldx     cur
        lda     ms_hi
        sta     t_x,x
        lda     ms_lo
        bra     set_ok

; $05 putc(A)
sys_putc:
        ldx     cur
        lda     t_a,x
        jsr     term_putc               ; (a terminal window)
        bcc     :+
        ldx     cur
        lda     t_a,x
        jsr     uputc
:
        lda     #0
        brl     set_ok

; $06 puts(X, Y = zero-terminated string)
sys_puts:
        ldx     cur
        lda     t_x,x
        sta     kt0
        lda     t_y,x
        sta     kt1
        lda     #1
        sta     kt2
        stz     kt3
        jsr     uaccess
        bcs     err_fault
        lda     kphys
        sta     kp1
        lda     kphys+2
        sta     kp1+2
        ldy     #0                      ; the terminator must be inside the region
@scan:  tya
        clc
        adc     kt0
        jcs     err_fault
        ldx     kt4
        beq     :+
        cmp     kt4
        jcs     err_fault
:       lda     [kp1],y
        and     #$00FF
        beq     @print
        iny
        bne     @scan
        brl     err_fault
@print: jsr     term_puts               ; (a terminal window)
        bcs     :+
        lda     #0
        jmp     set_ok
:       lda     kphys+2                 ; keep the pointer on the stack: printing may yield
        pha
        lda     kphys
        pha
        jsr     con_lock
@chunk: lda     1,s                     ; copy up to 127 bytes into the task's buffer
        sta     kp1
        lda     3,s
        sta     kp1+2
        jsr     iobuf_of
        tax
        ldy     #0
        a8
:       lda     [kp1],y
        sta     a:0,x
        beq     :+
        inx
        iny
        cpy     #127
        bne     :-
        lda     #0
        sta     a:0,x
:       a16
        tya
        clc
        adc     1,s
        sta     1,s
        jsr     iobuf_of
        jsr     con_write
        lda     1,s                     ; stopped on the terminator?
        sta     kp1
        lda     3,s
        sta     kp1+2
        lda     [kp1]
        and     #$00FF
        bne     @chunk
        pla
        pla
        jsr     con_unlock
        lda     #0
        jmp     set_ok

; $07 con_size -> A = columns, X = rows of the screen console's text area
sys_csize:
        jsr     term_csize
        bcs     :+
        jmp     set_ok
:       ldx     cur
        lda     #SCR_ROWS
        sta     t_x,x
        lda     #SCR_COLS
        jmp     set_ok

; $10 bank_alloc -> A = bank
sys_balloc:
        ldx     cur
        lda     t_id,x
        jsr     bank_alloc
        bcc     :+
        lda     #ENOMEM
        jmp     set_err
:       jmp     set_ok

; $11 bank_free(A = bank): only an extra bank of the caller
sys_bfree:
        ldx     cur
        lda     t_a,x
        cmp     #$0100
        bcs     @bad
        cmp     t_wbank,x
        beq     @bad
        cmp     t_cbank,x
        beq     @bad
        tay
        lda     bank_st,y
        and     #$00FF
        cmp     t_id,x
        bne     @bad
        tya
        jsr     au_bank_gone            ; (0.17) its voices reading the bank stop first
        jsl     k2_bank_gone            ; (0.18) its list, sprites, full screen reading it
        jsr     bank_free
        lda     #0
        jmp     set_ok
@bad:   jmp     err_inval

; $12 mem_info -> A = free banks, X = banks usable by tasks (free, owned or kernel scratch)
sys_minfo:
        stz     kt6
        stz     kt7
        ldx     #0
@loop:  lda     bank_st,x
        and     #$00FF
        cmp     #BK_NONE
        beq     @next
        inc     kt7
        cmp     #BK_FREE
        bne     @next
        inc     kt6
@next:  inx
        cpx     #$100
        bne     @loop
        ldx     cur
        lda     kt7
        sta     t_x,x
        lda     kt6
        jmp     set_ok

; A / X -> A = quotient, X = remainder (16-bit unsigned)
udiv16: sta     kt6
        stx     kt7
        lda     #0
        ldx     #16
@loop:  asl     kt6
        rol     a
        cmp     kt7
        bcc     :+
        sbc     kt7
        inc     kt6
:       dex
        bne     @loop
        tax
        lda     kt6
        rts
