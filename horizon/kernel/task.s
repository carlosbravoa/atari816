; task.s - task creation, exit, spawn, wait, kill.
;
; spawn creates a slot whose kernel stack starts in exec_entry (loader.s): the new task loads
; its own program, in its own kernel context, then posts the result to its parent, which
; is blocked in W_SPAWN. INIT is created the same way at boot, with no parent.
; A task that exits becomes a ZOMBIE until its parent's wait(); a task with no parent
; frees its slot at once. kill() marks the target; it exits at its next return to user
; mode, and an interruptible wait (sleep, wait, recv, input_read) is cut short.

        .a16
        .i16

; ---- create a task: path in kpath, kt0 = priority, kt1 = parent slot*2 or NONE.
; The argument string is empty (spawn fills t_args afterwards).
; Returns C clear and X = slot*2, or C set and A = EAGAIN. ----
task_create:
        ldx     #0
:       lda     t_state,x
        beq     @slot
        inx
        inx
        cpx     #NSLOT*2
        bne     :-
        lda     #EAGAIN
        sec
        rts
@slot:  ; a free task id (1..62, not used by any live or zombie task)
@nid:   lda     next_id
        sta     kt3
        inc     a
        cmp     #63
        bcc     :+
        lda     #1
:       sta     next_id
        ldy     #0
:       lda     t_state,y
        beq     :+
        lda     t_id,y
        cmp     kt3
        beq     @nid
:       iny
        iny
        cpy     #NSLOT*2
        bne     :--
        lda     kt3
        sta     t_id,x
        lda     #TS_READY
        sta     t_state,x
        lda     kt0
        sta     t_prio,x
        lda     kt1
        sta     t_parent,x
        stz     t_arglen,x
        txa
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a                       ; slot*128
        tay
        lda     #0
        sta     t_args,y
        stz     t_killed,x
        stz     t_wbank,x
        stz     t_cbank,x
        stz     t_tbank,x
        stz     t_iodone,x
        stz     t_exit,x
        stz     t_wreason,x
        lda     #$FFFF
        sta     t_pbr,x
        ; kernel stack: first resume = RTS into exec_entry
        txa
        xba
        clc
        adc     #KSTK_BASE + KSTK_SIZE - 3
        sta     t_ksp,x
        phx
        tax
        lda     #.loword(exec_entry - 1)
        sta     f:$000001,x
        plx
        ; path -> the task's own buffer
        txa
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a                       ; slot*2*128 = slot*256
        tay
        phx
        ldx     #0
:       lda     kpath,x
        sta     t_iobuf,y
        iny
        iny
        inx
        inx
        cpx     #128
        bne     :-
        plx
        jsr     set_name
        jsr     ph_set                  ; (sys13.s: single instance)
        jsr     cwd_inherit
        clc
        rts

; task X gets the current directory of its parent (kt1), or "/"
cwd_inherit:
        lda     #0                      ; the terminal too
        ldy     kt1
        cpy     #NONE
        beq     :+
        lda     t_term,y
:       sta     t_term,x
        phx
        txa
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        clc
        adc     #.loword(t_cwd)
        tay                             ; destination
        lda     kt1
        cmp     #NONE
        bne     :+
        lda     #'/'                    ; "/" and the terminator
        sta     a:0,y
        plx
        rts
:       asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        clc
        adc     #.loword(t_cwd)
        tax
        lda     #64
        sta     kt6
:       lda     a:0,x
        sta     a:0,y
        inx
        inx
        iny
        iny
        dec     kt6
        bne     :-
        plx
        rts

; name of task X from kpath: last path component, up to 8 characters, stops at '.'
set_name:
        phx
        txa                             ; (0.14: no display name yet)
        asl     a
        asl     a
        asl     a
        tay
        lda     #0
        sta     t_dname,y
        txa
        asl     a
        asl     a
        tay                             ; slot*8
        ldx     #0                      ; X = start of the last component
        stz     kt3
@find:  lda     kpath,x
        and     #$00FF
        beq     @found
        cmp     #'/'
        bne     :+
        txa
        inc     a
        sta     kt3
:       inx
        cpx     #128
        bne     @find
@found: ldx     kt3
        lda     #8
        sta     kt4
        a8
@copy:  lda     kpath,x
        beq     @pad
        cmp     #'.'
        beq     @pad
        sta     t_name,y
        inx
        iny
        dec     kt4
        bne     @copy
        bra     @done
@pad:   lda     #' '
:       sta     t_name,y
        iny
        dec     kt4
        bne     :-
@done:  a16
        plx
        rts

; ---- the current task ends with exit code A. Never returns. ----
do_exit:
        ldx     cur
        sta     t_exit,x
        jsr     files_close_cur         ; may block
        jsr     input_release_cur
        jsr     input_forget_cur
        jsr     scr_task_exit
        jsr     term_task_exit
        jsr     ws_task_exit
        jsr     snd_task_exit           ; (0.15) its sound channels and DACs silenced
        jsr     au_task_exit            ; (0.17) its sample voices stop (before its banks go)
        jsl     k2_task_exit            ; (0.18) its list, palette entries, sprites, full screen
        jsr     ports_close_cur
        ldx     cur
        lda     t_id,x
        jsr     banks_free_id
        ldx     cur
        lda     t_tbank,x
        beq     :+
        jsr     bank_free
:       ; children: orphans; zombie children are freed
        ldy     #0
@kids:  lda     t_state,y
        beq     @nk
        lda     t_parent,y
        cmp     cur
        bne     @nk
        lda     #NONE
        sta     t_parent,y
        lda     t_state,y
        cmp     #TS_ZOMBIE
        bne     @nk
        lda     #TS_FREE
        sta     t_state,y
@nk:    iny
        iny
        cpy     #NSLOT*2
        bne     @kids
        ldx     cur
        lda     t_det,x                 ; detached: nobody waits for it
        bne     @orphan
        lda     t_parent,x
        cmp     #NONE
        beq     @orphan
        lda     #TS_ZOMBIE
        sta     t_state,x
        lda     #W_WAIT                 ; a parent waiting for this child
        ldy     cur
        jsr     k_wake_all
        jmp     k_pick_run
@orphan:
        stz     t_det,x
        lda     #TS_FREE
        sta     t_state,x
        jmp     k_pick_run

; ---- $30 spawn(X, Y = block {u24 path, u24 args (0 = none), u8 priority}) -> A = id ----
; The child gets the argument string (at most 127 characters) at the top of its window.
sys_spawn:
        lda     #7
        jsr     get_block
        bcc     :+
        jmp     err_fault
:       lda     kblk+6                  ; priority 0-3; bit 7: detached (no parent: freed
        and     #$007F                  ; at its exit, nobody waits for it)
        cmp     #4
        bcc     :+
        jmp     err_inval
:       stz     kargs                   ; arguments -> kargs
        lda     kblk+3
        ora     kblk+4                  ; bytes 3, 4, 5 all zero = no arguments
        bne     :+
        lda     kblk+5
        and     #$00FF
        beq     @path
:       lda     kblk+5
        and     #$00FF
        tay
        ldx     kblk+3
        jsr     copy_ustr               ; (arguments are not paths)
        bcc     :+
        jmp     set_err
:       ldx     #0
:       lda     kpath,x
        sta     kargs,x
        inx
        inx
        cpx     #128
        bne     :-
@path:  lda     kblk+2
        and     #$00FF
        tay
        ldx     kblk
        jsr     copy_upath
        bcc     :+
        jmp     set_err
:       jsr     spawn_single            ; a single-instance program runs it: raised
        bcc     :+
        lda     #ERUNNING
        jmp     set_err
:       lda     kblk+6
        and     #$007F
        sta     kt0
        lda     cur
        sta     kt1
        jsr     task_create
        bcc     :+
        jmp     set_err
:       lda     kblk+6                  ; detached: freed at its exit (the parent still
        and     #$0080                  ; gets the load result)
        sta     t_det,x
        txa                             ; kargs -> the child's t_args, length -> t_arglen
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        tay
        phx
        ldx     #0
:       lda     kargs,x
        sta     t_args,y
        and     #$00FF
        beq     :+
        iny
        inx
        cpx     #127
        bne     :-
:       txa
        plx
        sta     t_arglen,x
        lda     t_id,x
        pha                             ; child id
        ldx     cur
        lda     #$FFFF
        sta     t_wres,x
@wait:  ldx     cur
        lda     t_wres,x
        cmp     #$FFFF
        bne     @done
        lda     #W_SPAWN
        jsr     k_block
        bra     @wait
@done:  ply
        cmp     #0
        beq     :+
        jmp     set_err
:       tya
        jmp     set_ok

; find a task by id: A = id -> X = slot*2 with C clear, or C set (FREE slots never match)
find_id:
        sta     kt6
        ldx     #0
:       lda     t_state,x
        beq     :+
        lda     t_id,x
        cmp     kt6
        beq     @hit
:       inx
        inx
        cpx     #NSLOT*2
        bne     :--
        sec
        rts
@hit:   clc
        rts

; ---- $31 wait(A = task id) -> A = exit code; frees the zombie ----
sys_wait:
        ldx     cur
        lda     t_a,x
        jsr     find_id
        bcs     @child
        lda     t_parent,x
        cmp     cur
        bne     @child
        phx
@loop:  plx
        phx
        lda     t_state,x
        cmp     #TS_ZOMBIE
        beq     @reap
        ldy     cur
        lda     t_killed,y
        bne     @intr
        txy
        lda     #W_WAIT
        jsr     k_block
        bra     @loop
@reap:  plx
        lda     #TS_FREE
        sta     t_state,x
        lda     t_exit,x
        jmp     set_ok
@intr:  plx
@child: lda     #ECHILD
        jmp     set_err

; ---- $32 kill(A = task id) ----
sys_kill:
        ldx     cur
        lda     t_a,x
        jsr     find_id
        bcs     @none
        lda     t_state,x
        cmp     #TS_ZOMBIE
        beq     @none
        jsr     kill_slot
        lda     #0
        jmp     set_ok
@none:  lda     #ECHILD
        jmp     set_err

; mark task X (slot*2) killed; cut an interruptible wait short. Safe from interrupt service.
kill_slot:
        lda     #1
        sta     t_killed,x
        lda     #EXIT_KILLED
        sta     t_killcode,x
        lda     t_state,x
        cmp     #TS_BLOCKED
        bne     @out
        lda     t_wreason,x
        cmp     #W_SLEEP
        beq     @wake
        cmp     #W_WAIT
        beq     @wake
        cmp     #W_RECV
        beq     @wake
        cmp     #W_CLASSIC
        beq     @wake
        cmp     #W_WEVENT
        beq     @wake
        cmp     #W_POP
        beq     @wake
        cmp     #W_VSYNC
        beq     @wake
        cmp     #W_INPUT
        bne     @out
@wake:  jmp     k_wake
@out:   rts

; ---- $33 task_info(A = slot 0-15, X, Y = 16-byte record) ----
; {u8 id (0 = free), u8 state, u8 priority, u8 banks owned, u8 parent id, 8 chars name,
;  u8 flags (TI_*), u8 windows, 1 spare}
sys_tinfo:
        ldx     cur
        lda     t_x,x
        sta     kt0
        lda     t_y,x
        sta     kt1
        lda     #16
        sta     kt2
        lda     #1
        sta     kt3
        jsr     uaccess
        bcc     :+
        jmp     err_fault
:       ldx     cur
        lda     t_a,x
        cmp     #NSLOT
        bcc     :+
        jmp     err_inval
:       asl     a
        tax                             ; X = the slot asked about
        ldy     #14
        lda     #0
:       sta     kblk,y
        dey
        dey
        bpl     :-
        lda     t_state,x
        bne     :+
        jmp     @copy                   ; free: all zero
:       a8
        lda     t_id,x
        sta     kblk
        lda     t_state,x
        sta     kblk+1
        lda     t_prio,x
        sta     kblk+2
        a16
        lda     t_parent,x
        cmp     #NONE
        beq     :+
        tay
        lda     t_id,y
        a8
        sta     kblk+4
        a16
:       lda     t_id,x                  ; banks owned
        sta     kt6
        ldy     #0
        stz     kt7
:       lda     bank_st,y
        and     #$00FF
        cmp     kt6
        bne     :+
        inc     kt7
:       iny
        cpy     #$100
        bne     :--
        a8
        lda     kt7
        sta     kblk+3
        a16
        phx                             ; flags (TI_*) and windows
        jsr     ws_task_info
        plx
        sta     kt6
        lda     t_single,x
        beq     :+
        lda     #8                      ; TI_SINGLE
        tsb     kt6
:       tya
        xba
        ora     kt6
        pha
        txa                             ; name
        asl     a
        asl     a
        tax
        ldy     #0
:       lda     t_name,x
        sta     kblk+5,y
        inx
        inx
        iny
        iny
        cpy     #8
        bne     :-
        stz     kblk+14
        pla
        sta     kblk+13
@copy:  lda     kphys
        sta     kp1
        lda     kphys+2
        sta     kp1+2
        ldy     #0
:       lda     kblk,y
        sta     [kp1],y
        iny
        iny
        cpy     #16
        bne     :-
        lda     #0
        jmp     set_ok
