; mbox.s - I/O processor mailbox and the file syscalls.
;
; Requests are 16-byte messages built in the task's t_msg and copied into the request ring
; ($00:B000). TAG = slot + 1 (0 is the I/O processor's own events). The task then blocks
; (W_IO, not interruptible) until mb_drain, run from the IOP interrupt, has copied the
; answer with its TAG into t_rsp. Key events ($E0) go to the input queue.
; The four file handles are global in the I/O processor; fh_owner records which task has
; each one, and a task's handles are closed when it exits.

        .a16
        .i16

mb_init:
        a8
        lda     #0
        sta     f:MB_REQ_BASE           ; bases 0: the I/O processor resets its side
        sta     f:MB_REQ_BASE+1
        sta     f:MB_REQ_BASE+2
        sta     f:MB_RSP_BASE
        sta     f:MB_RSP_BASE+1
        sta     f:MB_RSP_BASE+2
        sta     f:MB_REQ_HEAD
        sta     f:MB_RSP_TAIL
        jsr     mb_now
        sta     kt0
:       jsr     mb_now                  ; give it at least one poll (> 65 ms) to see that
        sec
        sbc     kt0
        cmp     #2
        bcc     :-
        lda     #<REQ_RING
        sta     f:MB_REQ_BASE
        lda     #>REQ_RING
        sta     f:MB_REQ_BASE+1
        lda     #^REQ_RING
        sta     f:MB_REQ_BASE+2
        lda     #<RSP_RING
        sta     f:MB_RSP_BASE
        lda     #>RSP_RING
        sta     f:MB_RSP_BASE+1
        lda     #^RSP_RING
        sta     f:MB_RSP_BASE+2
        jsr     mb_now
        sta     kt0
:       lda     f:MB_STATUS
        and     #$01
        bne     @ready
        jsr     mb_now
        sec
        sbc     kt0
        cmp     #46                     ; about 3 s
        bcc     :-
        a16
        kpanic  "no I/O processor"
@ready: lda     f:MB_RSP_HEAD           ; nothing received before now is ours
        sta     f:MB_RSP_TAIL
        a16
        rts

        .a8
mb_now: lda     f:UPTIME                ; latches the upper bytes
        lda     f:UPTIME+2              ; 65.536 ms units
        rts
        .a16

; Y = message offset of the current task (slot*16); the message is cleared, OP = A
msg_new:
        pha
        lda     cur
        asl     a
        asl     a
        asl     a
        tay
        lda     #0
        sta     t_msg,y
        sta     t_msg+2,y
        sta     t_msg+4,y
        sta     t_msg+6,y
        sta     t_msg+8,y
        sta     t_msg+10,y
        sta     t_msg+12,y
        sta     t_msg+14,y
        pla
        a8
        sta     t_msg,y
        a16
        rts

; A = offset of the current task's I/O buffer (in bank KBANK)
iobuf_of:
        lda     cur
        xba
        lsr     a                       ; slot*2*128
        clc
        adc     #.loword(t_iobuf)
        rts

; kpath -> the current task's I/O buffer; A = its offset
path_to_iobuf:
        jsr     iobuf_of
        tay
        ldx     #0
:       lda     kpath,x
        sta     a:0,y
        iny
        iny
        inx
        inx
        cpx     #128
        bne     :-
        bra     iobuf_of

; message BUF = the current task's I/O buffer (Y = message offset; keeps Y)
msg_buf_iobuf:
        jsr     iobuf_of
        sta     t_msg+4,y
        a8
        lda     #KBANK
        sta     t_msg+6,y
        a16
        rts

; ---- send the current task's message and wait for the answer ----
; Returns A = result (ARG0 low byte, Z set = OK); the answer is in t_rsp.
mb_call:
        ldx     cur
        stz     t_iodone,x
        txa
        asl     a
        asl     a
        asl     a
        tay
        txa
        lsr     a
        inc     a
        a8
        sta     t_msg+1,y               ; TAG
        lda     f:MB_REQ_HEAD
        inc     a
        cmp     f:MB_REQ_TAIL
        a16
        bne     @put
        lda     #1                      ; ring full (cannot happen with 16 tasks): wait a tick
        jsr     k_sleep_ticks
        bra     mb_call
@put:   lda     f:MB_REQ_HEAD
        and     #$00FF
        asl     a
        asl     a
        asl     a
        asl     a
        tax
        lda     #8
        sta     kt6
:       lda     t_msg,y
        sta     f:REQ_RING,x
        inx
        inx
        iny
        iny
        dec     kt6
        bne     :-
        a8
        lda     f:MB_REQ_HEAD
        inc     a
        sta     f:MB_REQ_HEAD           ; doorbell
        a16
@wait:  ldx     cur
        lda     t_iodone,x
        bne     @done
        lda     #W_IO
        ldy     #0
        jsr     k_block
        bra     @wait
@done:  lda     cur
        asl     a
        asl     a
        asl     a
        tay
        lda     t_rsp+8,y
        and     #$00FF
        rts

; Y = answer offset of the current task (slot*16)
rsp_of: lda     cur
        asl     a
        asl     a
        asl     a
        tay
        rts

; ---- IOP interrupt: take every answer and event out of the response ring ----
mb_drain:
        a8
        lda     f:MB_RSP_TAIL
        cmp     f:MB_RSP_HEAD
        a16
        bne     :+
        rts
:       and     #$00FF
        asl     a
        asl     a
        asl     a
        asl     a
        tax
        lda     f:RSP_RING,x
        and     #$00FF
        cmp     #MBEV_KEY
        beq     @key
        cmp     #MBEV_MOUSE
        beq     @mouse
        cmp     #MBEV_NET
        jeq     @net
        cmp     #$80
        jcc     @next
        cmp     #$E0
        jcs     @next
        lda     f:RSP_RING+1,x          ; TAG -> slot
        and     #$00FF
        dec     a
        cmp     #NSLOT
        jcs     @next
        asl     a
        sta     kt5                     ; slot*2
        asl     a
        asl     a
        asl     a
        tay
        lda     #8
        sta     kt6
:       lda     f:RSP_RING,x
        sta     t_rsp,y
        inx
        inx
        iny
        iny
        dec     kt6
        bne     :-
        ldx     kt5
        lda     #1
        sta     t_iodone,x
        lda     t_state,x
        cmp     #TS_BLOCKED
        bne     @next
        lda     t_wreason,x
        cmp     #W_IO
        bne     @next
        jsr     k_wake
        bra     @next
@key:   lda     f:RSP_RING+12,x         ; modifiers | down << 8
        pha
        lda     f:RSP_RING+8,x          ; HID usage
        and     #$00FF
        plx
        jsr     key_put
        bra     @next
@net:   lda     f:RSP_RING+8,x          ; (0.22) a connection's news: WE_NET to its owner
        and     #NFILE-1
        jsr     net_event
        bra     @next
@mouse: lda     f:RSP_RING+8,x          ; dx, dy
        pha
        and     #$00FF
        sta     ms_dx
        pla
        xba
        and     #$00FF
        sta     ms_dy
        lda     f:RSP_RING+10,x         ; wheel
        and     #$00FF
        sta     ms_dw
        lda     f:RSP_RING+12,x         ; buttons
        and     #$00FF
        sta     ms_nb
        jsr     mouse_event
@next:  a8
        lda     f:MB_RSP_TAIL
        inc     a
        sta     f:MB_RSP_TAIL
        a16
        brl     mb_drain

; (0.22, IOP interrupt) event $E4: stream handle A has news -> WE_NET (a = its bit) for the
; first window of the task that owns it (none: nothing; a program without windows polls)
net_event:
        tay
        asl     a
        tax
        lda     fh_owner,x
        beq     @out
        dec     a
        sta     kt5                     ; the owner (cur)
        lda     #1
:       dey
        bmi     :+
        asl     a
        bra     :-
:       sta     kt6
        ldx     #0
@w:     lda     w_used,x
        beq     @n
        lda     w_owner,x
        cmp     kt5
        bne     @n
        lda     w_net,x
        ora     kt6
        sta     w_net,x
        lda     #1
        sta     ws_tflag
        lda     #W_WS
        ldy     #0
        jmp     k_wake_all
@n:     inx
        inx
        cpx     #NWIN*2
        bne     @w
@out:   rts

; ---- helpers for the file syscalls ----
; A = I/O processor result -> error code for set_err
; (0.22) the same, and X = the answer's ARG1 (open, stat of a URL: the HTTP status)
io_errx:
        pha
        jsr     rsp_of
        lda     t_rsp+12,y
        ldx     cur
        sta     t_x,x
        pla
io_err: and     #$00FF
        clc
        adc     #EIO_BASE
        rts

; A = handle -> C clear if the current task owns it (X = handle*2)
fh_check:
        cmp     #NFILE
        bcs     @bad
        asl     a
        tax
        lda     cur
        inc     a
        cmp     fh_owner,x
        bne     @bad
        clc
        rts
@bad:   sec
        rts

; copy A bytes of user memory at (t_x, t_y) into kblk. C set = EFAULT.
get_block:
        sta     kt2
        ldx     cur
        lda     t_x,x
        sta     kt0
        lda     t_y,x
        sta     kt1
        stz     kt3
        jsr     uaccess
        bcs     @out
        lda     kphys
        sta     kp1
        lda     kphys+2
        sta     kp1+2
        ldy     #0
        a8
:       lda     [kp1],y
        sta     kblk,y
        iny
        cpy     kt2
        bne     :-
        a16
        clc
@out:   rts

; ---- $20 open(X, Y = path, A = mode) -> A = handle ----
sys_open:
        ldx     cur
        lda     t_a,x
        cmp     #4
        bcc     :+
        jmp     err_inval
:       ldy     t_y,x
        lda     t_x,x
        tax
        jsr     copy_upath
        bcc     :+
        jmp     set_err
:       jsr     path_to_iobuf
        lda     #MBOP_OPEN
        jsr     msg_new
        jsr     msg_buf_iobuf
        ldx     cur
        lda     t_a,x
        a8
        sta     t_msg+7,y               ; FLAGS = mode
        a16
        jsr     mb_call
        beq     :+
        jsr     io_errx
        jmp     set_err
:       jsr     rsp_of
        lda     t_rsp+12,y
        cmp     #NFILE
        bcc     :+
        lda     #EIO_BASE
        jmp     set_err
:       pha
        asl     a
        tax
        lda     cur
        inc     a
        sta     fh_owner,x
        pla
        jmp     set_ok

; ---- $21 close(A = handle) ----
sys_close:
        ldx     cur
        lda     t_a,x
        jsr     fh_check
        bcc     :+
        jmp     err_inval
:       txa
        lsr     a
        jsr     fh_close
        beq     :+
        jsr     io_err
        jmp     set_err
:       jmp     set_ok

; close handle A for the current task (blocks); A = result
fh_close:
        pha
        lda     #MBOP_CLOSE
        jsr     msg_new
        pla
        sta     t_msg+8,y
        asl     a
        tax
        stz     fh_owner,x
        jmp     mb_call

; close every handle of the current task (at exit)
files_close_cur:
        ldx     #0
@loop:  phx
        lda     cur
        inc     a
        cmp     fh_owner,x
        bne     :+
        txa
        lsr     a
        jsr     fh_close
:       plx
        inx
        inx
        cpx     #NFILE*2
        bne     @loop
        rts

; ---- $22 read / $23 write (X, Y = block {u8 handle, u24 buffer, u16 length}) -> A = bytes ----
sys_read:
        lda     #MBOP_READ
        bra     rw_common
sys_write:
        lda     #MBOP_WRITE
rw_common:
        pha
        lda     #6
        jsr     get_block
        bcc     :+
        pla
        jmp     err_fault
:       lda     kblk
        and     #$00FF
        jsr     fh_check
        bcc     :+
        pla
        jmp     err_inval
:       lda     kblk+1                  ; buffer
        sta     kt0
        lda     kblk+3
        and     #$00FF
        sta     kt1
        lda     kblk+4
        sta     kt2
        pla
        pha
        ldx     #1                      ; READ writes user memory: kt3 = 1
        cmp     #MBOP_READ
        beq     :+
        ldx     #0
:       stx     kt3
        jsr     uaccess
        bcc     :+
        pla
        jmp     err_fault
:       pla
        jsr     msg_new
        lda     kblk+4
        sta     t_msg+2,y               ; LEN
        lda     kphys
        sta     t_msg+4,y               ; BUF
        lda     kphys+2
        a8
        sta     t_msg+6,y
        a16
        lda     kblk
        and     #$00FF
        sta     t_msg+8,y               ; ARG0 = handle
        jsr     mb_call
        beq     :+
        jsr     io_err
        jmp     set_err
:       jsr     rsp_of
        lda     t_rsp+12,y
        jmp     set_ok

; ---- $24 seek(A = handle, X = offset low, Y = offset high) -> A, X = new position ----
sys_seek:
        ldx     cur
        lda     t_a,x
        jsr     fh_check
        bcc     :+
        jmp     err_inval
:       lda     #MBOP_SEEK
        jsr     msg_new
        ldx     cur
        lda     t_a,x
        sta     t_msg+8,y
        lda     t_x,x
        sta     t_msg+12,y
        lda     t_y,x
        sta     t_msg+14,y
        jsr     mb_call
        beq     :+
        jsr     io_err
        jmp     set_err
:       jsr     rsp_of
        ldx     cur
        lda     t_rsp+14,y
        sta     t_x,x
        lda     t_rsp+12,y
        jmp     set_ok

; path pointer at kblk+A (u24) -> kpath -> the task's I/O buffer. C set: A = error.
block_path:
        tax
        lda     kblk+2,x
        and     #$00FF
        tay
        lda     kblk,x
        tax
        jsr     copy_upath
        bcs     :+
        jsr     path_to_iobuf
        clc
:       rts

; ---- $25 stat(X, Y = block {u24 path, u24 out}) -> out = 9-byte record, A, X = size ----
sys_stat:
        lda     #6
        jsr     get_block
        bcc     :+
        jmp     err_fault
:       lda     kblk+3                  ; out: 9 writable bytes
        sta     kt0
        lda     kblk+5
        and     #$00FF
        sta     kt1
        lda     #9
        sta     kt2
        lda     #1
        sta     kt3
        jsr     uaccess
        bcc     :+
        jmp     err_fault
:       lda     kphys+2                 ; keep across the mailbox wait
        pha
        lda     kphys
        pha
        lda     #0
        jsr     block_path
        bcc     :+
        ply
        ply
        jmp     set_err
:       lda     #MBOP_STAT
        jsr     msg_new
        jsr     msg_buf_iobuf
        jsr     mb_call
        beq     :+
        ply
        ply
        jsr     io_errx
        jmp     set_err
:       pla
        sta     kp1
        pla
        sta     kp1+2
        jsr     iobuf_of
        tax
        ldy     #0
        a8
:       lda     a:0,x
        sta     [kp1],y
        inx
        iny
        cpy     #9
        bne     :-
        a16
        jsr     rsp_of
        ldx     cur
        lda     t_rsp+14,y
        sta     t_x,x
        lda     t_rsp+12,y
        jmp     set_ok

; ---- $26 readdir(X, Y = block {u24 path, u24 buffer, u16 length, u16 skip}) -> A = entries ----
; The I/O processor reads the path from the buffer and writes the entries over it.
sys_readdir:
        lda     #10
        jsr     get_block
        bcc     :+
        jmp     err_fault
:       lda     #0
        jsr     block_path
        bcc     :+
        jmp     set_err
:       lda     kblk+3
        sta     kt0
        lda     kblk+5
        and     #$00FF
        sta     kt1
        lda     kblk+6
        sta     kt2
        lda     #1
        sta     kt3
        jsr     uaccess
        bcc     :+
        jmp     err_fault
:       ldy     #0                      ; the path must fit in the buffer
:       lda     kpath,y
        and     #$00FF
        beq     :+
        iny
        bra     :-
:       iny
        cpy     kblk+6
        beq     :+
        bcc     :+
        jmp     err_inval
:       sty     kt7
        lda     kphys
        sta     kp1
        lda     kphys+2
        sta     kp1+2
        ldy     #0
        a8
:       lda     kpath,y
        sta     [kp1],y
        iny
        cpy     kt7
        bne     :-
        a16
        lda     #MBOP_READDIR
        jsr     msg_new
        lda     kblk+6
        sta     t_msg+2,y               ; LEN
        lda     kphys
        sta     t_msg+4,y
        lda     kphys+2
        a8
        sta     t_msg+6,y
        a16
        lda     kblk+8
        sta     t_msg+8,y               ; ARG0 = entries to skip
        jsr     mb_call
        beq     :+
        jsr     io_err
        jmp     set_err
:       jsr     rsp_of
        lda     t_rsp+12,y
        jmp     set_ok

; ---- $27 delete(X, Y = path), $28 mkdir(X, Y = path) ----
sys_delete:
        lda     #MBOP_DELETE
        bra     path_op
sys_mkdir:
        lda     #MBOP_MKDIR
path_op:
        pha
        ldx     cur
        ldy     t_y,x
        lda     t_x,x
        tax
        jsr     copy_upath
        bcc     :+
        ply
        jmp     set_err
:       jsr     path_to_iobuf
        pla
        jsr     msg_new
        jsr     msg_buf_iobuf
        jsr     mb_call
        beq     :+
        jsr     io_err
        jmp     set_err
:       jmp     set_ok

; ---- $29 rename(X, Y = {u24 old path, u24 new path}): renames or moves a file or folder
; on the card. Both paths resolved like any other. ----
sys_rename:
        lda     #6
        jsr     get_block
        bcc     :+
        jmp     err_fault
:       lda     kblk+3                  ; the new path, for later
        pha
        lda     kblk+5
        and     #$00FF
        pha
@lock:  lda     kren_busy               ; one rename at a time (kren is shared)
        beq     :+
        jsr     k_yield
        bra     @lock
:       inc     kren_busy
        lda     kblk+2
        and     #$00FF
        tay
        ldx     kblk
        jsr     copy_upath
        bcs     @err2
        ldx     #0                      ; "old\0"
        a8
:       lda     kpath,x
        sta     kren,x
        inx
        cmp     #0
        bne     :-
        a16
        stx     kren_n
        ply
        plx
        phx
        phy
        jsr     copy_upath
        bcs     @err2
        ply
        ply
        ldx     #0                      ; "new\0"
        ldy     kren_n
        a8
:       lda     kpath,x
        sta     kren,y
        inx
        iny
        cmp     #0
        bne     :-
        a16
        lda     #MBOP_RENAME
        jsr     msg_new
        lda     #.loword(kren)
        sta     t_msg+4,y
        a8
        lda     #KBANK
        sta     t_msg+6,y
        a16
        jsr     mb_call
        stz     kren_busy
        beq     :+
        jsr     io_err
        jmp     set_err
:       lda     #0
        jmp     set_ok
@err2:  stz     kren_busy
        ply
        ply
        jmp     set_err

; ---- $08 chdir(X, Y = path): the current directory (must exist and be a directory) ----
sys_chdir:
        ldx     cur
        ldy     t_y,x
        lda     t_x,x
        tax
        jsr     copy_upath
        bcc     :+
        jmp     set_err
:       jsr     path_to_iobuf           ; path at +0, a copy at +128 for STAT
        lda     kpath
        cmp     #'/'                    ; "/" itself: FatFs cannot STAT the root
        beq     @set
        jsr     iobuf_of
        tax
        ldy     #64
:       lda     a:0,x
        sta     a:128,x
        inx
        inx
        dey
        bne     :-
        lda     #MBOP_STAT
        jsr     msg_new
        jsr     iobuf_of
        clc
        adc     #128
        sta     t_msg+4,y
        a8
        lda     #KBANK
        sta     t_msg+6,y
        a16
        jsr     mb_call
        beq     :+
        jsr     io_err
        jmp     set_err
:       jsr     iobuf_of                ; attr: a directory?
        tax
        lda     a:128+4,x
        and     #$0010
        bne     @set
        jmp     err_inval
@set:   jsr     iobuf_of                ; iobuf -> t_cwd[cur]
        tax
        lda     cur
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        clc
        adc     #.loword(t_cwd)
        tay
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
        lda     #0
        jmp     set_ok

; ---- $09 getcwd(X, Y = buffer, A = its size) -> A = length ----
sys_getcwd:
        lda     cur                     ; X = t_cwd of the task, Y = length
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        clc
        adc     #.loword(t_cwd)
        sta     kt6
        tax
        ldy     #0
:       lda     a:0,x
        and     #$00FF
        beq     :+
        inx
        iny
        bra     :-
:       sty     kt7
        ldx     cur
        iny                             ; with the terminator
        tya
        cmp     t_a,x
        beq     :+
        bcc     :+
        jmp     err_inval
:       sta     kt2
        lda     t_x,x
        sta     kt0
        lda     t_y,x
        sta     kt1
        lda     #1
        sta     kt3
        jsr     uaccess
        bcc     :+
        jmp     err_fault
:       lda     kphys
        sta     kp1
        lda     kphys+2
        sta     kp1+2
        ldx     kt6
        ldy     #0
        a8
:       lda     a:0,x
        sta     [kp1],y
        inx
        iny
        cpy     kt2
        bne     :-
        a16
        lda     kt7
        jmp     set_ok

; ---- $35 task_path(X, Y = buffer, A = its size) -> A = length (0.28) ----
; The absolute path of the caller's program file, as the loader found it: kept in the window
; bank at $8000 (loader.s), out of the window's sight. Zero-terminated; EINVAL if the buffer is
; too small (as getcwd).
sys_tpath:
        ldx     cur
        lda     t_wbank,x
        sta     kp0+2
        lda     #$8000
        sta     kp0
        ldy     #0                      ; the length (at most 127)
:       lda     [kp0],y
        and     #$00FF
        beq     :+
        iny
        cpy     #127
        bne     :-
:       sty     kt7
        iny                             ; with the terminator
        tya
        cmp     t_a,x
        beq     :+
        bcc     :+
        jmp     err_inval
:       sta     kt2
        lda     t_x,x
        sta     kt0
        lda     t_y,x
        sta     kt1
        lda     #1
        sta     kt3
        jsr     uaccess
        bcc     :+
        jmp     err_fault
:       lda     kphys
        sta     kp1
        lda     kphys+2
        sta     kp1+2
        ldy     #0                      ; (uaccess keeps kp0)
        a8
        bra     @test
:       lda     [kp0],y
        sta     [kp1],y
        iny
@test:  cpy     kt7
        bne     :-
        lda     #0
        sta     [kp1],y
        a16
        lda     kt7
        jmp     set_ok
