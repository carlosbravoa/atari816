; emu816 test of the PC volume (PC link step 1, --pc-folder): a list of mailbox requests,
; each printed as "LABEL RESULT VALUE" (and what STAT, READDIR and READ wrote). The run
; script runs it with the volume present, absent, and with the link dropped and back
; (--pc-drop-at, --pc-back-at), and compares each output with tests/expected/pctest*.txt.
        .include "common.inc"

MB_REQ_BASE = $00DD00
MB_REQ_HEAD = $00DD03
MB_RSP_BASE = $00DD05
MB_RSP_HEAD = $00DD08
MB_RSP_TAIL = $00DD09
MB_STATUS   = $00DD0A
REQ_RING    = $0E0000
RSP_RING    = $0E1000
RDBUF       = $0D0000
WORK        = $0D4000           ; the path (and what STAT / READDIR write over it)
LOADBUF     = $0C0000
ptr         = $10               ; direct page: 24-bit pointer
cnt         = $13
step        = $16               ; the current step (offset in bank $01)
until       = $18               ; UPTIME+2 at which a wait gives up
tries       = $1A

; a step: mode, target result (mode 3), label, path (0 = none: BUF as given), request
M_PLAIN = 0                     ; the result and the value
M_STAT  = 1                     ; + the 9 bytes STAT wrote
M_DIR   = 2                     ; + the entries READDIR wrote
M_WAIT  = 3                     ; repeat until the result is the target (2 s at most)
M_READ  = 4                     ; + the bytes read, as text
M_END   = $FF

        .macro  STEP mode, target, label, path, op, len, buf, flags, arg0, arg1
        .byte   mode, target
        .word   .loword(label), .loword(path)
        .byte   op, 0
        .word   len
        .faraddr buf
        .byte   flags
        .dword  arg0
        .dword  arg1
        .endmacro

        .segment "CODE"
        .a8
        .i16
start:  clc
        xce
        rep     #$10
        sep     #$20
        ldx     #$01FF
        txs
        phk
        plb
        print   m_hello
        lda     #$00                    ; rings at $0E:0000 and $0E:1000
        sta     f:MB_REQ_BASE
        sta     f:MB_REQ_BASE+1
        sta     f:MB_RSP_BASE
        lda     #$10
        sta     f:MB_RSP_BASE+1
        lda     #$0E
        sta     f:MB_REQ_BASE+2
        sta     f:MB_RSP_BASE+2
:       lda     f:MB_STATUS
        and     #$01
        beq     :-

        ldx     #.loword(steps)
        stx     step
next:   ldx     step
        lda     a:0,x
        cmp     #M_END
        bne     :+
        print   m_done
        stp
:       cmp     #M_WAIT
        bne     once
        lda     f:UPTIME                ; latches the upper bytes
        lda     f:UPTIME+2              ; 65.5 ms units
        clc
        adc     #31                     ; about 2 s
        sta     until
:       jsr     do_step
        ldx     step
        cmp     a:1,x
        beq     show
        lda     f:UPTIME
        lda     f:UPTIME+2
        cmp     until
        bne     :-
        bra     show
once:   jsr     do_step
show:   ldx     step                    ; "LABEL RR VVVVVVVV"
        ldy     a:2,x
        tyx
        jsr     puts
        lda     #' '
        jsr     putc
        lda     rsp+8
        jsr     puthex
        lda     #' '
        jsr     putc
        ldx     rsp+14
        jsr     puthex16
        ldx     rsp+12
        jsr     puthex16
        ldx     step
        lda     a:0,x
        cmp     #M_STAT
        beq     p_stat
        cmp     #M_DIR
        beq     p_dir
        cmp     #M_READ
        beq     p_read
p_end:  jsr     crlf
        rep     #$20
        .a16
        lda     step
        clc
        adc     #22
        sta     step
        sep     #$20
        .a8
        jmp     next

p_stat: lda     rsp+8                   ; size, attr, time (high bytes first)
        bne     p_end
        lda     #' '
        jsr     putc
        ldx     #3
:       lda     f:WORK,x
        jsr     puthex
        dex
        bpl     :-
        lda     #' '
        jsr     putc
        lda     f:WORK+4
        jsr     puthex
        lda     #' '
        jsr     putc
        ldx     #8
:       lda     f:WORK,x
        jsr     puthex
        dex
        cpx     #4
        bne     :-
        bra     p_end

p_read: lda     rsp+8
        bne     p_end
        lda     #' '
        jsr     putc
        ldx     rsp+12
        stx     cnt
        ldx     #0
:       cpx     cnt
        beq     p_end
        lda     f:RDBUF,x
        jsr     putc
        inx
        bra     :-

p_dir:  lda     rsp+8
        bne     p_end
        lda     rsp+12
        sta     cnt
        lda     #^WORK
        sta     ptr+2
        ldx     #.loword(WORK)
        stx     ptr
dloop:  lda     cnt
        bne     :+
        jmp     p_end
:
        jsr     crlf
        print   m_sp
        ldy     #3                      ; size, high byte first
:       lda     [ptr],y
        jsr     puthex
        dey
        bpl     :-
        lda     #' '
        jsr     putc
        ldy     #4
        lda     [ptr],y                 ; attr
        jsr     puthex
        lda     #' '
        jsr     putc
        ldy     #5
        lda     [ptr],y                 ; name length
        sta     cnt+1
        ldy     #6
:       lda     [ptr],y
        jsr     putc
        iny
        dec     cnt+1
        bne     :-
        rep     #$20
        .a16
        tya                             ; next entry = 6 + namelen
        clc
        adc     ptr
        sta     ptr
        sep     #$20
        .a8
        dec     cnt
        bra     dloop

; the current step: its path (128 bytes) to WORK, the request sent, the answer to rsp.
; Returns A = result low byte.
do_step:
        ldx     step
        ldy     a:4,x                   ; the path
        beq     :++
        ldx     #0
:       lda     a:0,y
        sta     f:WORK,x
        iny
        inx
        cpx     #128
        bne     :-
:       ldx     step
        ldy     #0
:       lda     a:6,x
        sta     msg,y
        inx
        iny
        cpy     #16
        bne     :-
        ldx     step
        ldy     a:4,x
        beq     :+
        lda     #<WORK                  ; BUF = WORK
        sta     msg+4
        lda     #>WORK
        sta     msg+5
        lda     #^WORK
        sta     msg+6
:       rep     #$20
        .a16
        lda     f:MB_REQ_HEAD
        and     #$00FF
        asl
        asl
        asl
        asl
        tax
        sep     #$20
        .a8
        ldy     #0
:       lda     msg,y
        sta     f:REQ_RING,x
        inx
        iny
        cpy     #16
        bne     :-
        lda     f:MB_REQ_HEAD
        inc
        sta     f:MB_REQ_HEAD           ; doorbell
        sei
        lda     #$40                    ; IOP interrupt; with I set WAI only waits for it
        sta     f:IRQ_EN
:       lda     f:MB_RSP_HEAD
        cmp     f:MB_RSP_TAIL
        bne     :+
        wai
        bra     :-
:       lda     #$00
        sta     f:IRQ_EN
        rep     #$20
        .a16
        lda     f:MB_RSP_TAIL
        and     #$00FF
        asl
        asl
        asl
        asl
        tax
        sep     #$20
        .a8
        ldy     #0
:       lda     f:RSP_RING,x
        sta     rsp,y
        inx
        iny
        cpy     #16
        bne     :-
        lda     f:MB_RSP_TAIL
        inc
        sta     f:MB_RSP_TAIL
        lda     rsp+8
        rts

;            mode     tgt  label     path        op   len   buf      fl arg0     arg1
steps:
        STEP M_DIR,   0,   l_root,   p_root,     $07, $400, 0,       0, 0,       0
        STEP M_DIR,   0,   l_skip3,  p_root,     $07, $400, 0,       0, 3,       0
        STEP M_STAT,  0,   l_statpc, p_pc,       $06, 0,    0,       0, 0,       0
        STEP M_STAT,  0,   l_statlc, p_pclc,     $06, 0,    0,       0, 0,       0
        STEP M_DIR,   0,   l_pcdir,  p_pc,       $07, $400, 0,       0, 0,       0
        STEP M_DIR,   0,   l_pcsub,  p_pcsub,    $07, $400, 0,       0, 0,       0
        STEP M_STAT,  0,   l_statn,  p_notesuc,  $06, 0,    0,       0, 0,       0
        STEP M_PLAIN, 0,   l_openw,  p_new,      $01, 0,    0,       2, 0,       0
        STEP M_PLAIN, 0,   l_write,  0,          $04, 37,   wdata,   0, 0,       0
        STEP M_PLAIN, 0,   l_close,  0,          $02, 0,    0,       0, 0,       0
        STEP M_PLAIN, 0,   l_openr,  p_newlc,    $01, 0,    0,       0, 0,       0
        STEP M_READ,  0,   l_read,   0,          $03, $100, RDBUF,   0, 0,       0
        STEP M_PLAIN, 0,   l_seek,   0,          $05, 0,    0,       0, 0,       6
        STEP M_PLAIN, 0,   l_close,  0,          $02, 0,    0,       0, 0,       0
        STEP M_STAT,  0,   l_statnw, p_new,      $06, 0,    0,       0, 0,       0
        STEP M_PLAIN, 0,   l_mkdir,  p_made,     $08, 0,    0,       0, 0,       0
        STEP M_PLAIN, 0,   l_mkroot, p_pc,       $08, 0,    0,       0, 0,       0
        STEP M_PLAIN, 0,   l_rename, p_ren,      $0A, 0,    0,       0, 0,       0
        STEP M_PLAIN, 0,   l_renx,   p_renx,     $0A, 0,    0,       0, 0,       0
        STEP M_PLAIN, 0,   l_renx2,  p_renx2,    $0A, 0,    0,       0, 0,       0
        STEP M_PLAIN, 0,   l_dotdot, p_dotdot,   $06, 0,    0,       0, 0,       0
        STEP M_PLAIN, 0,   l_link,   p_link,     $06, 0,    0,       0, 0,       0
        STEP M_PLAIN, 0,   l_linkw,  p_linkw,    $01, 0,    0,       2, 0,       0
        STEP M_PLAIN, 0,   l_nofile, p_nofile,   $06, 0,    0,       0, 0,       0
        STEP M_PLAIN, 0,   l_nopath, p_nopath,   $06, 0,    0,       0, 0,       0
        STEP M_PLAIN, 0,   l_delne,  p_pcsub,    $09, 0,    0,       0, 0,       0
        STEP M_PLAIN, 0,   l_delrt,  p_pc,       $09, 0,    0,       0, 0,       0
        STEP M_PLAIN, 0,   l_load,   p_notesuc,  $10, 0,    0,       0, LOADBUF, 0
        STEP M_PLAIN, 0,   l_mount,  p_atr,      $18, 0,    0,       0, 0,       0
        STEP M_STAT,  0,   l_card,   p_hello,    $06, 0,    0,       0, 0,       0
        STEP M_PLAIN, 0,   l_pcx,    p_pcx,      $06, 0,    0,       0, 0,       0
        STEP M_PLAIN, 0,   l_openh,  p_notesuc,  $01, 0,    0,       0, 0,       0
        STEP M_PLAIN, 0,   l_openh2, p_deep,     $01, 0,    0,       0, 0,       0
        STEP M_WAIT,  $87, l_wdrop,  p_pc,       $06, 0,    0,       0, 0,       0
        STEP M_READ,  0,   l_readh,  0,          $03, 5,    RDBUF,   0, 0,       0
        STEP M_PLAIN, 0,   l_closeh, 0,          $02, 0,    0,       0, 0,       0
        STEP M_PLAIN, 0,   l_openx,  p_notesuc,  $01, 0,    0,       0, 0,       0
        STEP M_DIR,   0,   l_skip3,  p_root,     $07, $400, 0,       0, 3,       0
        STEP M_WAIT,  0,   l_wback,  p_pc,       $06, 0,    0,       0, 0,       0
        STEP M_DIR,   0,   l_skip3,  p_root,     $07, $400, 0,       0, 3,       0
        STEP M_PLAIN, 0,   l_readh2, 0,          $03, 5,    RDBUF,   0, 1,       0
        STEP M_PLAIN, 0,   l_seekh2, 0,          $05, 0,    0,       0, 1,       0
        STEP M_PLAIN, 0,   l_closh2, 0,          $02, 0,    0,       0, 1,       0
        STEP M_PLAIN, 0,   l_sync,   0,          $1C, 0,    0,       0, 0,       0
        .byte   M_END

p_root:   .byte "/", 0
p_pc:     .byte "/PC:", 0
p_pclc:   .byte "/pc:", 0
p_pcsub:  .byte "/PC:/sub", 0
p_notesuc: .byte "/PC:/NOTES.TXT", 0
p_new:    .byte "/PC:/New File.txt", 0
p_newlc:  .byte "/pc:/new file.TXT", 0
p_made:   .byte "/PC:/Made", 0
p_ren:    .byte "/PC:/New File.txt", 0, "/PC:/Made/Moved.txt", 0
p_renx:   .byte "/HELLO.TXT", 0, "/PC:/HELLO.TXT", 0
p_renx2:  .byte "/PC:/Notes.txt", 0, "/N.TXT", 0
p_dotdot: .byte "/PC:/../HELLO.TXT", 0
p_link:   .byte "/PC:/out", 0
p_linkw:  .byte "/PC:/out/new.txt", 0
p_nofile: .byte "/PC:/nothere", 0
p_nopath: .byte "/PC:/nodir/x", 0
p_atr:    .byte "/PC:/GAME.ATR", 0
p_hello:  .byte "/HELLO.TXT", 0
p_pcx:    .byte "/PC:X", 0
p_deep:   .byte "/PC:/sub/Deep.bin", 0
wdata:    .byte "Written by pctest into the PC folder.", 0
l_root:   .byte "ROOT", 0
l_skip3:  .byte "ROOTSKIP3", 0
l_statpc: .byte "STATPC", 0
l_statlc: .byte "STATPCLC", 0
l_pcdir:  .byte "PCDIR", 0
l_pcsub:  .byte "PCSUB", 0
l_statn:  .byte "STATNOTES", 0
l_openw:  .byte "OPENW", 0
l_write:  .byte "WRITE", 0
l_close:  .byte "CLOSE", 0
l_openr:  .byte "OPENR", 0
l_read:   .byte "READ", 0
l_seek:   .byte "SEEK", 0
l_statnw: .byte "STATNEW", 0
l_mkdir:  .byte "MKDIR", 0
l_mkroot: .byte "MKDIRROOT", 0
l_rename: .byte "RENAME", 0
l_renx:   .byte "RENAMEX", 0
l_renx2:  .byte "RENAMEX2", 0
l_dotdot: .byte "DOTDOT", 0
l_link:   .byte "LINKOUT", 0
l_linkw:  .byte "LINKOUTW", 0
l_nofile: .byte "NOFILE", 0
l_nopath: .byte "NOPATH", 0
l_delne:  .byte "DELNOTEMPTY", 0
l_delrt:  .byte "DELROOT", 0
l_load:   .byte "LOAD", 0
l_mount:  .byte "MOUNT", 0
l_card:   .byte "CARD", 0
l_pcx:    .byte "PCX", 0
l_openh:  .byte "OPENH", 0
l_openh2: .byte "OPENH2", 0
l_wdrop:  .byte "WAITDROP", 0
l_readh:  .byte "READH", 0
l_closeh: .byte "CLOSEH", 0
l_openx:  .byte "OPENAFTER", 0
l_wback:  .byte "WAITBACK", 0
l_readh2: .byte "READH2", 0
l_seekh2: .byte "SEEKH2", 0
l_closh2: .byte "CLOSEH2", 0
l_sync:   .byte "SYNC", 0
m_hello:  .byte "PCTEST", 10, 0
m_sp:     .byte "  ", 0
m_done:   .byte "DONE", 10, 0
msg:      .res 16
rsp:      .res 16
