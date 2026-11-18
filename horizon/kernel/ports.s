; ports.s - message ports: 16 ports, each owned by the task that created it, with a queue
; of 8 messages of 16 bytes. Anyone may send (EAGAIN when the queue is full); only the
; owner receives, blocking (W_RECV, interruptible) while the queue is empty. A task's
; ports are closed when it exits.

        .a16
        .i16

; A = port -> X = port*2 with C clear if the port is open
port_check:
        cmp     #NPORT
        bcs     @bad
        asl     a
        tax
        lda     p_owner,x
        beq     @bad
        clc
        rts
@bad:   sec
        rts

; Y = queue entry offset of message A (0..7) in port X (port*2)
port_entry:
        and     #PQLEN - 1
        asl     a
        asl     a
        asl     a
        asl     a
        sta     kt6
        txa
        xba
        lsr     a                       ; port*2*256 / 4 = port*128
        lsr     a
        clc
        adc     kt6
        tay
        rts

; ---- $40 port_create -> A = port ----
sys_pcreate:
        ldx     #0
:       lda     p_owner,x
        beq     @free
        inx
        inx
        cpx     #NPORT*2
        bne     :-
        lda     #EAGAIN
        jmp     set_err
@free:  lda     cur
        inc     a
        sta     p_owner,x
        stz     p_head,x
        stz     p_count,x
        txa
        lsr     a
        jmp     set_ok

; ---- $41 send(A = port, X, Y = 16-byte message) ----
sys_send:
        ldx     cur
        lda     t_a,x
        jsr     port_check
        bcc     :+
        jmp     err_inval
:       lda     p_count,x
        cmp     #PQLEN
        bcc     :+
        lda     #EAGAIN
        jmp     set_err
:       phx
        lda     #16
        jsr     get_block
        plx
        bcc     :+
        jmp     err_fault
:       lda     p_head,x
        clc
        adc     p_count,x
        jsr     port_entry
        phx
        ldx     #0
:       lda     kblk,x
        sta     p_queue,y
        iny
        iny
        inx
        inx
        cpx     #16
        bne     :-
        plx
        inc     p_count,x
        txa
        lsr     a
        tay
        lda     #W_RECV
        jsr     k_wake_all
        lda     #0
        jmp     set_ok

; ---- $42 recv(A = port, X, Y = 16-byte buffer): blocks while the queue is empty ----
sys_recv:
        ldx     cur
        lda     t_a,x
        jsr     port_check
        bcs     @inval
        lda     cur
        inc     a
        cmp     p_owner,x
        bne     @inval
        ldy     cur                     ; buffer writable?
        lda     t_x,y
        sta     kt0
        lda     t_y,y
        sta     kt1
        lda     #16
        sta     kt2
        lda     #1
        sta     kt3
        jsr     uaccess
        bcs     @fault
        ldx     cur
        lda     t_a,x
        asl     a
        tax
        lda     p_count,x
        bne     @take
        ldy     cur
        lda     t_killed,y
        bne     @inval
        txa
        lsr     a
        tay
        lda     #W_RECV
        jsr     k_block
        bra     sys_recv                ; check everything again
@take:  lda     kphys
        sta     kp1
        lda     kphys+2
        sta     kp1+2
        lda     p_head,x
        jsr     port_entry
        phx
        ldx     #0
:       lda     p_queue,y
        phy
        txy
        sta     [kp1],y
        ply
        iny
        iny
        inx
        inx
        cpx     #16
        bne     :-
        plx
        lda     p_head,x
        inc     a
        and     #PQLEN - 1
        sta     p_head,x
        dec     p_count,x
        lda     #0
        jmp     set_ok
@inval: jmp     err_inval
@fault: jmp     err_fault

; ---- $43 port_close(A = port) ----
sys_pclose:
        ldx     cur
        lda     t_a,x
        jsr     port_check
        bcs     @inval
        lda     cur
        inc     a
        cmp     p_owner,x
        bne     @inval
        stz     p_owner,x
        lda     #0
        jmp     set_ok
@inval: jmp     err_inval

; close the current task's ports (at exit)
ports_close_cur:
        lda     cur
        inc     a
        ldx     #0
:       cmp     p_owner,x
        bne     :+
        stz     p_owner,x
:       inx
        inx
        cpx     #NPORT*2
        bne     :--
        rts
