; loader.s - o65 program loader. exec_entry is the first kernel code a new task runs, in its
; own context (so it can block on the mailbox): STAT the file, allocate the window bank,
; the code bank and a scratch bank, LOAD the file into the scratch bank, copy text+data
; to code bank $0100, clear bss and the zp area (window $0000), apply the relocations,
; free the scratch bank and return to user mode at the text base. The result goes to the
; parent blocked in spawn (INIT has no parent: a failure is a panic).
;
; o65 as written by ld65 (type = small): 16-bit header fields, any segment bases.
; Relocation entries are applied per segment: text, data and bss move to the code bank
; (offset delta = load address - link address, bank byte = code bank), zp moves to the
; direct page (bank 0). Types WORD, LOW, HIGH, SEG (bank byte) and SEGADR (24-bit).
; Undefined references are refused.
;
; (0.28) A program file of 64 KB or more (the large code model's one file: the o65, then data
; the program reads itself) is not LOADed whole: only its first 65,535 bytes are read into the
; scratch bank (ld_big), and the o65 must lie in them. What follows the o65 is never copied
; into the program's memory, as before for a smaller file. Files below 64 KB load as before.
; The loader also keeps the program's absolute path in the window bank at $8000 (the upper
; half, which the task's window does not show) for task_path ($35, sys_tpath).

        .a16
        .i16

ld_tlen  = $70
ld_dlen  = $72
ld_blen  = $74
ld_zlen  = $76
ld_toff  = $78                  ; file offset of text
ld_roff  = $7A                  ; read position in the relocation tables
ld_dt    = $7C                  ; offset deltas: text, data, bss, zp
ld_dd    = $7E
ld_db    = $80
ld_dz    = $82
ld_pos   = $84                  ; position being patched (code bank offset)
ld_size  = $86                  ; bytes loaded
ld_end   = $88                  ; end of text+data in the code bank
ld_type  = $8A

exec_entry:
        lda     cb_done                 ; (0.19) the first task: a cartridge the I/O processor
        bne     :+                      ; loaded by itself at power-on keeps its banks
        inc     cb_done
        jsr     cart_boot
:       ; STAT a copy of the path (the answer overwrites its buffer)
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
        jmp     ld_fail
:       jsr     rsp_of
        lda     t_rsp+14,y              ; (0.28) 64 KB or more: read in part (ld_big)
        bne     :+
        lda     t_rsp+12,y
        cmp     #26
        jcc     ld_inval
:
        ; banks: window and code owned by the task, scratch owned by the kernel
        ldx     cur
        lda     t_id,x
        jsr     bank_alloc
        jcs     ld_nomem
        ldx     cur
        sta     t_wbank,x
        a8
        sta     f:B0WIN
        a16
        lda     t_id,x
        jsr     bank_alloc
        jcs     ld_nomem
        ldx     cur
        sta     t_cbank,x
        lda     #BK_KERNEL
        jsr     bank_alloc
        jcs     ld_nomem
        ldx     cur
        sta     t_tbank,x
        ; LOAD the whole file to scratch:0000 (t_rsp still holds STAT's answer)
        jsr     rsp_of
        lda     t_rsp+14,y
        beq     @load
        jsr     ld_big                  ; (0.28) 64 KB or more: its first 65,535 bytes
        cmp     #0
        beq     :+
        jmp     ld_fail
:       lda     #$FFFF
        sta     ld_size
        bra     ld_parse
@load:  lda     #MBOP_LOAD
        jsr     msg_new
        jsr     msg_buf_iobuf
        ldx     cur
        lda     t_tbank,x
        sta     t_msg+10,y              ; ARG0 = tbank:0000
        jsr     mb_call
        beq     :+
        jsr     io_err
        jmp     ld_fail
:       jsr     rsp_of
        lda     t_rsp+14,y
        bne     ld_inval
        lda     t_rsp+12,y
        sta     ld_size
        ; ---- no more blocking from here: direct page state is safe ----
ld_parse:
        ldx     cur
        stz     kp0
        lda     t_tbank,x
        sta     kp0+2
        stz     kp1
        lda     t_cbank,x
        sta     kp1+2
        ldy     #0                      ; header
        lda     [kp0],y
        cmp     #$0001
        bne     ld_inval
        ldy     #2
        lda     [kp0],y
        cmp     #$366F                  ; "o6"
        bne     ld_inval
        ldy     #4
        lda     [kp0],y
        cmp     #$0035                  ; "5", version 0
        bne     ld_inval
        ldy     #6
        lda     [kp0],y
        and     #$6000                  ; 32-bit sizes or page relocation: not supported
        bne     ld_inval
        bra     ld_hdr

ld_inval:
        lda     #EINVAL
        jmp     ld_fail
ld_nomem:
        lda     #ENOMEM
        jmp     ld_fail

ld_hdr: ldy     #10
        lda     [kp0],y
        sta     ld_tlen
        ldy     #14
        lda     [kp0],y
        sta     ld_dlen
        ldy     #18
        lda     [kp0],y
        sta     ld_blen
        ldy     #22
        lda     [kp0],y
        sta     ld_zlen
        cmp     #$0101
        bcs     ld_inval
        ; deltas
        lda     #$0100
        ldy     #8
        sec
        sbc     [kp0],y
        sta     ld_dt
        lda     #$0100
        clc
        adc     ld_tlen
        bcs     ld_inval
        ldy     #12
        sec
        sbc     [kp0],y
        sta     ld_dd
        lda     #$0100
        clc
        adc     ld_tlen
        adc     ld_dlen
        bcs     ld_inval
        sta     ld_end
        ldy     #16
        sec
        sbc     [kp0],y
        sta     ld_db
        lda     ld_end
        clc
        adc     ld_blen
        bcs     ld_inval
        lda     #0
        ldy     #20
        sec
        sbc     [kp0],y
        sta     ld_dz
        ; skip the header options
        ldy     #26
@opt:   cpy     ld_size
        bcs     ld_inval
        lda     [kp0],y
        and     #$00FF
        beq     @optend
        sta     kt0
        tya
        clc
        adc     kt0
        jcs     ld_inval                ; (0.28) never wraps round the bank
        tay
        bra     @opt
@optend:
        iny
        sty     ld_toff
        tya                             ; relocation tables after text and data
        clc
        adc     ld_tlen
        jcs     ld_inval
        adc     ld_dlen
        jcs     ld_inval
        sta     ld_roff
        clc
        adc     #2
        jcs     ld_inval
        cmp     ld_size
        beq     :+
        jcs     ld_inval
:       ldy     ld_roff                 ; undefined references: none allowed
        lda     [kp0],y
        jne     ld_inval
        iny
        iny
        sty     ld_roff
        ; text + data -> code bank $0100
        ldx     cur
        lda     ld_toff
        sta     kt0
        lda     t_tbank,x
        sta     kt1
        lda     #$0100
        sta     kt2
        lda     t_cbank,x
        sta     kt3
        lda     ld_end
        sec
        sbc     #$0100
        jsr     kmemcpy
        ; bss and zp cleared
        ldx     cur
        lda     ld_end
        sta     kt2
        lda     t_cbank,x
        sta     kt3
        lda     ld_blen
        jsr     kmemzero
        ldx     cur
        stz     kt2
        lda     t_wbank,x
        sta     kt3
        lda     ld_zlen
        jsr     kmemzero
        ; relocations: text, then data
        lda     #$00FF
        sta     ld_pos
        jsr     reloc_seg
        jcs     ld_inval2
        lda     ld_tlen
        clc
        adc     #$00FF
        sta     ld_pos
        jsr     reloc_seg
        jcs     ld_inval2
        ; scratch bank no longer needed
        ldx     cur
        lda     t_tbank,x
        stz     t_tbank,x
        jsr     bank_free
        ; argument string (length L) -> window $7FFF-(L+1), ending at $7FFE (one spare byte
        ; so that 16-bit reads of the terminator stay in the window); X = its offset,
        ; A = L, S just below it
        ldx     cur
        lda     #$7FFE
        sec
        sbc     t_arglen,x
        sta     kt2                     ; offset in the window
        sta     t_x,x
        dec     a
        sta     t_s,x
        lda     t_arglen,x
        sta     t_a,x
        lda     t_wbank,x
        sta     kt3
        txa
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        asl     a
        clc
        adc     #.loword(t_args)
        sta     kt0
        lda     #KBANK
        sta     kt1
        lda     t_arglen,x
        inc     a
        jsr     kmemcpy
        ; (0.28) the program's absolute path (the I/O buffer still holds it) -> window bank
        ; $8000, for task_path
        jsr     iobuf_of
        sta     kt0
        lda     #KBANK
        sta     kt1
        lda     #$8000
        sta     kt2
        ldx     cur
        lda     t_wbank,x
        sta     kt3
        lda     #128
        jsr     kmemcpy
        ; user context: native, P = 0, D = 0, DBR = PBR = code bank, PC = $0100
        ldx     cur
        stz     t_y,x
        stz     t_d,x
        stz     t_p,x
        lda     #$0100
        sta     t_pc,x
        lda     t_cbank,x
        sta     t_pbr,x
        sta     t_dbr,x
        lda     #0
        jsr     ld_post
        jmp     ret_user

ld_inval2:
        lda     #EINVAL
; failure: A = error code. Frees everything, tells the parent, the slot becomes free.
ld_fail:
        pha
        ldx     cur
        lda     t_id,x
        jsr     banks_free_id
        ldx     cur
        lda     t_tbank,x
        beq     :+
        stz     t_tbank,x
        jsr     bank_free
:       pla
        ldx     cur
        ldy     t_parent,x
        cpy     #NONE
        bne     :+
        pha
        kprint  "[panic] cannot load INIT, error "
        pla
        jsr     kputhex8
        lda     #10
        jsr     kputc
        stp
:       jsr     ld_post
        ldx     cur
        lda     #TS_FREE
        sta     t_state,x
        jmp     k_pick_run

; (0.28) a program file of 64 KB or more: OPEN it, READ its first 65,535 bytes to scratch:0000
; (two pieces: $8000 bytes, then $7FFF), CLOSE it. The o65 must lie in those bytes; the rest
; of the file is not read. Blocks. Returns A = 0, or an error code.
ld_big: lda     #MBOP_OPEN
        jsr     msg_new
        jsr     msg_buf_iobuf           ; the path; FLAGS 0 = read
        jsr     mb_call
        beq     :+
        jmp     io_err
:       jsr     rsp_of
        lda     t_rsp+12,y
        cmp     #NFILE
        bcc     :+
        lda     #EIO_BASE
        rts
:       pha                             ; the handle (3,s in @rd)
        asl     a
        tax
        lda     cur
        inc     a
        sta     fh_owner,x              ; (the task's own while it loads)
        lda     #0
        ldx     #$8000
        jsr     @rd
        bne     @close
        lda     #$8000
        ldx     #$7FFF
        jsr     @rd
@close: pha                             ; the result; the handle at 3,s
        lda     3,s
        jsr     fh_close                ; (its own result ignored: the file was only read)
        pla
        plx
        cmp     #0
        rts
; A = offset in the scratch bank, X = length; the handle at 3,s. A = 0 (all of it read), or
; an error (Z clear)
@rd:    sta     kt0
        stx     kt1
        lda     #MBOP_READ
        jsr     msg_new
        lda     kt1
        sta     t_msg+2,y               ; LEN
        lda     kt0
        sta     t_msg+4,y               ; BUF = scratch:offset
        ldx     cur
        lda     t_tbank,x
        a8
        sta     t_msg+6,y
        a16
        lda     3,s
        sta     t_msg+8,y               ; ARG0 = handle
        jsr     mb_call
        beq     :+
        jmp     io_err
:       jsr     rsp_of
        lda     t_rsp+12,y
        cmp     t_msg+2,y               ; every byte asked for (the file is longer)
        bne     :+
        lda     #0
        rts
:       lda     #EINVAL
        rts

; result A -> the parent blocked in spawn
ld_post:
        ldx     cur
        ldy     t_parent,x
        cpy     #NONE
        beq     :+
        sta     t_wres,y
        tyx
        jsr     k_wake
:       rts

; ---- apply one relocation table (at ld_roff in the scratch bank) ----
; ld_pos = segment load address - 1. C set = bad table.
reloc_seg:
@loop:  jsr     @byte
        beq     @done
        cmp     #$FF
        bne     :+
        lda     ld_pos
        clc
        adc     #254
        sta     ld_pos
        bra     @loop
:       clc
        adc     ld_pos
        sta     ld_pos
        jsr     @byte
        sta     ld_type
        and     #$001F                  ; segment -> kd_lo = offset delta, kd_hi = bank
        cmp     #2
        bne     :+
        lda     ld_dt
        bra     @inbank
:       cmp     #3
        bne     :+
        lda     ld_dd
        bra     @inbank
:       cmp     #4
        bne     :+
        lda     ld_db
        bra     @inbank
:       cmp     #5
        bne     @bad
        lda     ld_dz
        sta     kd_lo
        stz     kd_hi
        bra     @type
@inbank:
        sta     kd_lo
        ldx     cur
        lda     t_cbank,x
        sta     kd_hi
@type:  lda     ld_type
        and     #$00E0
        cmp     #$80
        beq     @word
        cmp     #$20
        beq     @low
        cmp     #$40
        beq     @high
        cmp     #$C0
        beq     @segadr
        cmp     #$A0
        beq     @seg
@bad:   sec
        rts
@done:  clc
        rts

@word:  lda     #2
        jsr     @check
        bcs     @bad
        lda     [kp1],y
        clc
        adc     kd_lo
        sta     [kp1],y
        brl     @loop
@low:   lda     #1
        jsr     @check
        bcs     @bad
        a8
        lda     [kp1],y
        clc
        adc     kd_lo
        sta     [kp1],y
        a16
        brl     @loop
@high:  jsr     @byte                   ; low byte of the full value
        sta     kv_lo
        lda     #1
        jsr     @check
        bcs     @bad
        lda     [kp1],y
        and     #$00FF
        xba
        ora     kv_lo
        clc
        adc     kd_lo
        xba
        a8
        sta     [kp1],y
        a16
        brl     @loop
@segadr:
        lda     #3
        jsr     @check
        bcs     @bad
        lda     [kp1],y
        clc
        adc     kd_lo
        sta     [kp1],y
        iny
        iny
        a8
        lda     kd_hi
        sta     [kp1],y
        a16
        jmp     @loop
@seg:   jsr     @byte                   ; low 16 bits of the full value (unused)
        jsr     @byte
        lda     #1
        jsr     @check
        bcs     @bad
        a8
        lda     kd_hi
        sta     [kp1],y
        a16
        jmp     @loop

; next table byte -> A (Z set if 0)
@byte:  ldy     ld_roff
        cpy     ld_size
        bcs     @eof
        inc     ld_roff
        lda     [kp0],y
        and     #$00FF
        rts
@eof:   pla                             ; table runs past the file: bad
        sec
        rts

; A = bytes patched at ld_pos: must lie in $0100..ld_end. Y = ld_pos. C set = outside.
@check: clc
        adc     ld_pos
        bcs     :+
        cmp     ld_end
        beq     @in
        bcs     :+
@in:    ldy     ld_pos
        cpy     #$0100
        bcc     :+
        clc
        rts
:       sec
        rts
