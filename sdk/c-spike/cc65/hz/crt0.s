; crt0.s - cc65 C startup for a Horizon program (Atari816), 65816 native mode, 8-bit regs.
;
; Horizon starts the task native, A/X/Y 16-bit, PBR = DBR = code bank, D = 0 (direct page
; = cc65's zero page, at window $0000 in bank 0), S just below the argument string (bank 0).
; X = window offset of the argument string, A = its length.
;
; Memory of a C program (all C pointers are 16-bit offsets in the code bank):
;   code bank $0100..       text (STARTUP first), rodata, data, bss (the loader clears bss)
;   heap                    from the end of bss to c_sp - __STACKSIZE__ (cc65 malloc)
;   C stack (c_sp)          from $FFFF down (the top of the code bank)
;   bank 0 (window)         direct page (cc65 zp) at $0000, the 65816 hardware stack (JSR)
;
; We stay in native mode with M = X = 1 (sep #$30) for all C code; the kernel kills a
; task that enters emulation mode. Syscalls switch to 16-bit around COP (hzsys.s).

        .p816
        .smart  off

        .export         _exit
        .export         __STARTUP__ : absolute = 1      ; Mark as startup
        .export         _hz_bank, _hz_args
        .export         initmainargs            ; cc65 imports it when main takes argc/argv
        .import         initlib, donelib, callmain
        .import         __argc, __argv
        .importzp       c_sp, ptr1

        .segment "STARTUP"

        .a16
        .i16
start:  sta     ptr1                    ; length of the argument string (unused)
        ; the code bank, for pointers passed to syscalls (Y = bank)
        sep     #$20
        .a8
        phk
        pla
        sta     _hz_bank
        stz     _hz_bank+1
        ; copy the argument string (bank 0, window offset X) into the code bank
        ldy     #0
@cp:    lda     f:$000000,x
        sta     _hz_args,y
        beq     @cpd
        inx
        iny
        cpy     #127
        bcc     @cp
        lda     #0
        sta     _hz_args,y
@cpd:   sep     #$30                    ; from here on: 8-bit A, X, Y (cc65's 6502 code)
        .a8
        .i8
        ; C stack at the top of the code bank (first push goes to $FFFE)
        lda     #0
        sta     c_sp
        sta     c_sp+1
        ; argv: split a copy of the argument string at blanks, "quoted words" kept whole
        ldx     #0
@sc:    lda     _hz_args,x
        sta     argcopy,x
        beq     @scd
        inx
        bne     @sc
@scd:   lda     #<progname              ; argv[0]
        sta     argvtab
        lda     #>progname
        sta     argvtab+1
        ldy     #1                      ; argc
        ldx     #0                      ; index into argcopy
@skip:  lda     argcopy,x
        beq     @done
        cmp     #' '
        bne     @word
        inx
        bne     @skip
@word:  cpy     #MAXARGS
        bcs     @done
        cmp     #'"'
        bne     @plain
        inx                             ; quoted: the word starts after the quote
        jsr     storearg
@q:     lda     argcopy,x
        beq     @done
        cmp     #'"'
        beq     @end
        inx
        bne     @q
@plain: jsr     storearg
@p:     lda     argcopy,x
        beq     @done
        cmp     #' '
        beq     @end
        inx
        bne     @p
@end:   lda     #0                      ; terminate the word
        sta     argcopy,x
        inx
        bne     @skip
@done:  sty     __argc
        lda     #0
        sta     __argc+1
        tya                             ; argv[argc] = NULL
        asl     a
        tay
        lda     #0
        sta     argvtab,y
        sta     argvtab+1,y
        lda     #<argvtab
        sta     __argv
        lda     #>argvtab
        sta     __argv+1
        jsr     initlib                 ; constructors (heap, ...)
        jsr     callmain                ; main(argc, argv) -> A/X
_exit:  pha                             ; exit(code): A/X
        txa
        pha
        jsr     donelib                 ; destructors, atexit functions
        pla
        sta     ptr1+1
        pla
        sta     ptr1
        rep     #$30
        .a16
        .i16
        lda     ptr1
        cop     $00                     ; SYS_EXIT, never returns
        .a8
        .i8

; argc/argv are set up above, before the constructors
initmainargs:
        rts

; store argv[Y] = &argcopy[X], Y++
storearg: tya
        pha
        asl     a
        tay
        txa
        clc
        adc     #<argcopy
        sta     argvtab,y
        lda     #>argcopy
        adc     #0
        sta     argvtab+1,y
        pla
        tay
        iny
        rts

MAXARGS = 16

        .segment "RODATA"
progname: .byte "", 0

        .segment "BSS"
_hz_bank: .res  2                       ; the code bank (high byte 0)
_hz_args: .res  128                     ; the argument string, copied from bank 0
argcopy:  .res  128
argvtab:  .res  (MAXARGS + 1) * 2
