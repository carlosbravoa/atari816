; sys13.s - 0.13: restart and shut down (the I/O processor's ops $1B SYS_RESTART and $1C
; SYS_SYNC), the Desktop request, single-instance programs.
;
; Single instance: every task keeps a hash of its program's absolute path (t_phash, set by
; task_create). A program that calls SYS_SINGLE is marked (t_single); spawning the same
; path again raises that task's windows instead and answers ERUNNING. SYS_SINGLE itself
; answers ERUNNING when another task already runs the same program (its windows raised).

        .a16
        .i16

MBOP_RESTART = $1B
MBOP_SYNC    = $1C
EV_SYSREQ    = 11                       ; WE_SYSREQ (horizon.inc)

        .segment "BSS"
t_phash:    .res    NSLOT*2             ; hash of the program's absolute path
t_single:   .res    NSLOT*2             ; non-zero: one instance only (SYS_SINGLE)
        .segment "CODE"

; ---- the hash of kpath (upper case: FAT names are case-insensitive) -> A ----
; h = h * 33 xor c. Clobbers X, kt6.
path_hash:
        stz     kt6
        ldx     #0
@c:     lda     kpath,x
        and     #$00FF
        beq     @out
        cmp     #'a'
        bcc     :+
        cmp     #'z' + 1
        bcs     :+
        and     #$00DF
:       pha
        lda     kt6                     ; * 33
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        clc
        adc     kt6
        eor     1,s
        sta     kt6
        pla
        inx
        cpx     #128
        bne     @c
@out:   lda     kt6
        rts

; (task_create) task X gets the hash of kpath; not single. Keeps X.
ph_set: phx
        jsr     path_hash
        plx
        sta     t_phash,x
        stz     t_single,x
        rts

; C set and X = slot*2 of a live task (not a zombie, not the caller) whose program hash
; is A; with kt5 = 1 only a single-instance one. C clear: none.
ph_find:
        sta     kt4
        ldx     #0
@s:     lda     t_state,x
        beq     @n
        cmp     #TS_ZOMBIE
        beq     @n
        cpx     cur
        beq     @n
        lda     t_phash,x
        cmp     kt4
        bne     @n
        lda     kt5
        beq     @hit
        lda     t_single,x
        bne     @hit
@n:     inx
        inx
        cpx     #NSLOT*2
        bne     @s
        clc
        rts
@hit:   sec
        rts

; (spawn, kpath = the program) a single-instance task runs it: its windows raised, C set
spawn_single:
        jsr     path_hash
        ldy     #1
        sty     kt5
        jsr     ph_find
        bcc     :+
        jsr     ws_task_raise
        sec
:       rts

; ---- $34 task_single: one instance of the caller's program ----
sys_single:
        ldx     cur
        lda     t_phash,x
        stz     kt5
        jsr     ph_find
        bcs     @run
        ldx     cur
        lda     #1
        sta     t_single,x
        lda     #0
        jmp     set_ok
@run:   phx
        jsr     ws_task_raise
        plx
        lda     t_id,x
        ldx     cur
        sta     t_x,x
        lda     #ERUNNING
        jmp     set_err

; ---- close every open file of every task (restart, shut down); blocks ----
files_close_all:
        ldx     #0
@l:     phx
        lda     fh_owner,x
        beq     :+
        txa
        lsr     a
        jsr     fh_close
:       plx
        inx
        inx
        cpx     #NFILE*2
        bne     @l
        rts

; ---- the I/O processor's SYS_SYNC -> A = result (Z set: OK); blocks ----
io_sync:
        lda     #MBOP_SYNC
        jsr     msg_new
        jmp     mb_call

; ---- $0A restart(A = 0 Horizon only, 1 full restart) ----
; Every file is closed and the card synced, then SYS_RESTART: the I/O processor resets the
; machine (it does not come back). An error (an old firmware: $C2) is returned.
sys_restart:
        ldx     cur
        lda     t_a,x
        cmp     #2
        bcc     :+
        jmp     err_inval
:       jsr     files_close_all
        jsr     io_sync
        lda     #MBOP_RESTART
        jsr     msg_new
        ldx     cur
        lda     t_a,x
        sta     t_msg+8,y               ; ARG0 = mode
        jsr     mb_call
        beq     @wait
        jsr     io_err
        jmp     set_err
@wait:  ldx     cur                     ; the reset comes
        lda     t_killed,x
        bne     :+
        lda     #10
        jsr     k_sleep_ticks
        bra     @wait
:       lda     #0
        jmp     set_ok

; ---- $0B sync(A = bit 0: end every other program first) ----
; Bit 0: every task except INIT (slot 0), the caller and the window system's thread is
; killed, and the call waits (3 s at most) until they are gone. Then every open file is
; closed and the I/O processor flushes the card (SYS_SYNC). Errors: the I/O result.
sys_sync:
        ldx     cur
        lda     t_a,x
        and     #1
        beq     @files
        ldx     #2                      ; (slot 0 is INIT)
:       jsr     sy_other
        bcc     :+
        phx
        jsr     kill_slot
        plx
:       inx
        inx
        cpx     #NSLOT*2
        bne     :--
        lda     #300                    ; wait until they are gone
        sta     kt5
@wait:  lda     kt5
        beq     @files
        ldx     #2
:       jsr     sy_other
        bcs     @sleep
        inx
        inx
        cpx     #NSLOT*2
        bne     :-
        bra     @files
@sleep: dec     kt5                     ; (k_block loses kt5: on the stack)
        lda     kt5
        pha
        lda     #1
        jsr     k_sleep_ticks
        pla
        sta     kt5
        bra     @wait
@files: jsr     files_close_all
        jsr     io_sync
        beq     :+
        jsr     io_err
        jmp     set_err
:       jmp     set_ok

; C set: slot X (not 0) is another live task the shut down ends (not the caller, not the
; window system's thread, not a zombie). Keeps X.
sy_other:
        cpx     cur
        beq     @no
        lda     t_state,x
        beq     @no
        cmp     #TS_ZOMBIE
        beq     @no
        lda     ws_on
        beq     @yes
        cpx     ws_thr
        beq     @no
@yes:   sec
        rts
@no:    clc
        rts

; ---- $0C sysreq(A = 1 shut down, 2 restart, 3 full restart, (0.31) 4 the apps changed):
; asks the Desktop ----
; The backdrop window gets WE_SYSREQ (a = the request, c = the caller's id). EINVAL without
; the window system or a backdrop.
sys_sysreq:
        ldx     cur
        lda     t_a,x
        beq     @bad
        cmp     #5
        bcs     @bad
        sta     kg_t
        lda     ws_on
        beq     @bad
        lda     z_n
        beq     @bad
        ldx     z_list
        lda     w_fl,x
        bit     #WF_BACK
        beq     @bad
        lda     #EV_SYSREQ
        sta     kg_v
        stz     kg_u
        phx
        ldx     cur
        lda     t_id,x
        plx
        jsr     wev_push
        lda     #0
        jmp     set_ok
@bad:   jmp     err_inval
