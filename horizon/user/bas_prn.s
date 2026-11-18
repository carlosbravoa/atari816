; bas_prn.s - (Horizon 0.23) printing: LPRINT and LLIST to a print job.
;
; A print job is the file `/PRN:BASIC` (opened with O_CREATE: the I/O processor writes it
; as /Printouts/YYYY-MM-DD HH.MM.SS BASIC.txt when it is closed). One job a run: it is
; opened by the first LPRINT or LLIST that prints something (its first character: an LLIST
; of no lines, or an LPRINT that fails before it prints, makes none) and closed by lp_end
; when BASIC is back at the
; prompt (main_ready: END, STOP, an error, a break, the end of the program or of a direct
; line), at RUN (run_clear: a new run, a new job) and when BASIC ends (quit_code). So a
; direct LPRINT or LLIST line is a job of its own, and an LLIST in a program writes into
; the run's job.
; While an LPRINT or LLIST statement runs, lpon is 1 and con_putc sends every character to
; lp_putc instead of the console: PRINT's code (numbers, strings, ; , TAB, SPC) and LIST's
; are the same for both. The job has its own column (lpcol) and a width of LPW for `,` and
; TAB; nothing wraps (the PC side wraps long lines). Line ends are LF. The characters wait
; in lpbuf and are written when it is full and at the end.
; An I/O error stops the program: "File error $XX" (in N), the job closed.

        .segment "CODE"
        .a16
        .i16
LPW     = 80                            ; the job's width for `,` and TAB
LPMAX   = 256                           ; lpbuf's size

; LPRINT [items]: PRINT to the job (st_print clears lpon at its end)
st_lprint:
        lda     #1
        sta     lpon
        jmp     st_print

; LLIST [n], LLIST [n]-[m]: LIST to the job
st_llist:
        jsr     list_args
        lda     #1
        sta     lpon
        jsr     list_range
        stz     lpon
        jmp     stmt_end

; character A into the job (from con_putc; A, X, Y clobbered), opened first when there is
; none; the column kept: LF, CR and FF start a line, BS goes back
lp_putc:
        ldx     lpjob
        bne     @in
        pha
        ptr     t_prn
        lda     #O_CREATE
        sys     SYS_OPEN
        jcs     lp_err
        sta     lph
        lda     #1
        sta     lpjob
        stz     lpn
        pla
@in:    ldx     lpn
        a8
        sta     lpbuf,x
        a16
        inx
        stx     lpn
        cmp     #32
        bcs     @c1
        cmp     #8
        beq     @bs
        cmp     #10
        beq     @c0
        cmp     #12
        beq     @c0
        cmp     #13
        bne     @full
@c0:    stz     lpcol
        bra     @full
@bs:    lda     lpcol
        beq     @full
        dec     lpcol
        bra     @full
@c1:    inc     lpcol
@full:  cpx     #LPMAX
        bcc     :+
        jsr     lp_flush
        bcs     lp_fail
:       rts

; lpbuf written -> C set, A = the I/O error
lp_flush:
        lda     lpn
        beq     @ok
        lda     lph
        sta     rblk
        lda     #.loword(lpbuf)
        sta     rblk+1
        lda     codebk
        sta     rblk+3
        lda     lpn
        sta     rblk+4
        ptr     rblk
        sys     SYS_WRITE
        bcs     @x
        cmp     lpn
        bne     @short
        stz     lpn
@ok:    clc
@x:     rts
@short: lda     #$47
        sec
        rts

; a write failed (A = the error): the job closed, "File error $XX"
lp_fail:
        pha
        stz     lpon
        stz     lpjob
        lda     lph
        sys     SYS_CLOSE
        pla
; the job could not be opened (A = the error)
lp_err: and     #$00FF
        sta     ioerr
        err     E_FILE

; the job finished: a line left open (LPRINT ...;) ended, the rest written, closed (nothing
; to do without one). A failure is said on the console ("File error $XX"; a script's exit
; code 1)
lp_end: stz     lpon
        lda     lpjob
        beq     @out
        stz     lpjob
        lda     lpcol                   ; (lp_putc leaves lpbuf never full)
        beq     :+
        stz     lpcol
        ldx     lpn
        lda     #10
        a8
        sta     lpbuf,x
        a16
        inc     lpn
:       jsr     lp_flush
        bcc     @close
        pha
        lda     lph
        sys     SYS_CLOSE
        pla
        bra     @err
@close: lda     lph
        sys     SYS_CLOSE
        bcc     @out
@err:   pha
        jsr     con_bol
        pla
        jsr     con_puterr
        lda     #1
        sta     serr
@out:   stz     lpcol
        rts

; the output's column and width -> pcol, pwid: the console's, or the job's (keeps A)
pr_pos: ldx     lpon
        bne     :+
        ldx     ccol
        stx     pcol
        ldx     ccols
        stx     pwid
        rts
:       ldx     lpcol
        stx     pcol
        ldx     #LPW
        stx     pwid
        rts

        .segment "RODATA"
t_prn:  .byte   "/PRN:BASIC", 0

        .segment "BSS"
lpon:   .res    2               ; 1: con_putc writes into the job
lpjob:  .res    2               ; 1: the job is open
lph:    .res    2               ; its handle
lpn:    .res    2               ; bytes waiting in lpbuf
lpcol:  .res    2               ; the job's column
ioerr:  .res    2               ; the I/O error of the next "File error" message (0: none)
pcol:   .res    2               ; (pr_pos)
pwid:   .res    2
lpbuf:  .res    LPMAX
