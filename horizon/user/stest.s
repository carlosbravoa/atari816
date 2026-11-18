; STEST - (0.17) a test of the sample syscalls (Lau, the sample player), run from the text
; shell by tests/stest.keys (make test). It prints what it sees, compared with tests/stest.txt
; (tests/stest-nolau.txt on REV < $0A), and emu816 --log-lau logs every write to Lau, compared
; with tests/stest.err.
;   1. a sample in the code bank (8-bit, looped), one in the window (16-bit): played
;   2. refused: the kernel's bank, the framebuffer, a bank nobody owns, past the window, a
;      range running out of an own bank (EFAULT); an odd 16-bit address, no samples, a loop
;      shorter than 4, voice 8 (EINVAL)
;   3. a sample in an allocated bank: freeing the bank stops its voice
;   4. all 8 voices: a ninth sample takes the caller's oldest voice; stop one, stop all
;   5. sample_set on a voice that is not the caller's (EINVAL), on its own
;   6. a child plays and exits: its voice stops; a child plays and is killed: its voice
;      stops; while it plays, its voice cannot be taken (EAGAIN)
;   7. the sound volume setting (0.18: 4) moves the master volume (in the log)
; Without Lau (REV < $0A): sample_play returns ENODEV, and that is all.
        .include "horizon.inc"

        .macro  spb     addr, len, loop, pitch, vol, flags, voice
        .faraddr addr
        .faraddr len
        .faraddr loop
        .word   pitch
        .byte   vol, vol, flags, voice, 0
        .endmacro

        .segment "CODE"
        .a16
        .i16
start:  sta     z:alen
        jsr     args_init
        lda     z:alen
        beq     :+
        jmp     child
:       print   "stest 1: play\n"
        print   "  code bank, 8-bit, any voice: "
        ptr     b_code
        jsr     try
        jsr     pstat
        ldx     #0                      ; the 16-bit sample into the window at $1000
:       lda     smp16,x
        sta     f:$001000,x
        inx
        inx
        cpx     #64
        bcc     :-
        print   "  window, 16-bit, voice 2: "
        ptr     b_win
        jsr     try
        jsr     pstat

        print   "stest 2: refused\n"
        print   "  kernel bank: "
        ptr     b_kern
        jsr     try
        print   "  framebuffer: "
        ptr     b_fb
        jsr     try
        print   "  bank nobody owns: "
        ptr     b_free
        jsr     try
        print   "  past the window: "
        ptr     b_wend
        jsr     try
        print   "  odd 16-bit address: "
        ptr     b_odd
        jsr     try
        print   "  no samples: "
        ptr     b_zero
        jsr     try
        print   "  loop of 3: "
        ptr     b_short
        jsr     try
        print   "  voice 8: "
        ptr     b_v8
        jsr     try

        print   "stest 3: a bank freed\n"
        sys     SYS_BALLOC
        sta     z:bank
        sep     #$20
        .a8
        sta     b_bank+SPB_ADDR+2
        sta     b_cross+SPB_ADDR+2
        rep     #$20
        .a16
        sta     z:p+2
        stz     z:p
        ldy     #0
:       lda     smp8,y
        sta     [p],y
        iny
        iny
        cpy     #64
        bcc     :-
        print   "  running out of the bank: "
        ptr     b_cross
        jsr     try
        print   "  in the bank, voice 3: "
        ptr     b_bank
        jsr     try
        jsr     pstat
        lda     z:bank
        sys     SYS_BFREE
        print   "  freed: "
        jsr     pstat2

        print   "stest 4: eight voices\n"
        ldx     #6                      ; voices 1, 3-7 (0 and 2 play)
:       phx
        print   "  "
        ptr     b_code
        jsr     try
        plx
        dex
        bne     :-
        jsr     pstat
        print   "  a ninth: "
        ptr     b_code
        jsr     try
        print   "  stop 3: "
        lda     #3
        sys     SYS_SSTOP
        jsr     res
        jsr     pstat
        print   "  stop 3 again: "
        lda     #3
        sys     SYS_SSTOP
        jsr     res
        print   "  stop all: "
        lda     #$FFFF
        sys     SYS_SSTOP
        jsr     res
        jsr     pstat

        print   "stest 5: sample_set\n"
        print   "  not ours: "
        lda     #1
        ldx     #$2000
        ldy     #$4040
        sys     SYS_SSET
        jsr     res
        print   "  "
        ptr     b_code
        jsr     try
        print   "  ours: "
        lda     #0
        ldx     #$2000
        ldy     #$2080
        sys     SYS_SSET
        jsr     res
        lda     #$FFFF
        sys     SYS_SSTOP

        print   "stest 6: children\n"
        jsr     out_flush
        lda     #.loword(a_exit)        ; plays and exits
        sta     z:u_arg
        lda     #^a_exit
        sta     z:u_arg+2
        ptr     p_self
        lda     #1
        jsr     spawn
        bcs     :+
        sys     SYS_WAIT
:       print   "  after its exit: "
        jsr     pstat2
        lda     #.loword(a_kill)        ; plays voice 5 and sleeps
        sta     z:u_arg
        lda     #^a_kill
        sta     z:u_arg+2
        ptr     p_self
        lda     #1
        jsr     spawn
        sta     z:kid
        lda     #300
        sys     SYS_SLEEP
        print   "  while it plays: "
        jsr     pstat2
        print   "  its voice 5: "
        ptr     b_v5
        jsr     try
        lda     z:kid
        sys     SYS_KILL
        lda     z:kid
        sys     SYS_WAIT
        print   "  after the kill: "
        jsr     pstat2

        print   "stest 7: volume\n"
        lda     #4                      ; (0.18: the sound volume, setting 4)
        ldx     #15
        sys     SYS_SETTING
        sta     z:vol
        lda     #4
        ldx     #0
        sys     SYS_SETTING
        lda     #4
        ldx     z:vol
        sys     SYS_SETTING
        print   "stest: done\n"
        exit    0

; play the block X, Y: "voice N" or "error NN"; stops at ENODEV (no Lau)
try:    sys     SYS_SPLAY
        bcs     @err
        pha
        print   "voice "
        pla
        jsr     put_dec
        jmp     put_nl
@err:   cmp     #ENODEV
        beq     @nodev
        pha
        print   "error "
        pla
        jsr     put_hex8
        jmp     put_nl
@nodev: print   "no Lau: ENODEV (the program falls back to POKEY 2)\n"
        exit    0
; "ok" / "error NN" after a call
res:    bcs     @err
        print   "ok\n"
        rts
@err:   pha
        print   "error "
        pla
        jsr     put_hex8
        jmp     put_nl
; "  playing: mine MM, all AA"
pstat:  print   "  "
pstat2: sys     SYS_SSTAT
        phx
        pha
        print   "mine "
        pla
        jsr     put_hex8
        print   ", all "
        pla
        jsr     put_hex8
        jmp     put_nl

; the children: "x" plays (looped, any voice) and exits; "k" plays voice 5 and sleeps
child:  lda     f:0,x
        and     #$00FF
        cmp     #'k'
        beq     @k
        ptr     b_code
        sys     SYS_SPLAY
        lda     #50
        sys     SYS_SLEEP
        exit    0
@k:     ptr     b_v5
        sys     SYS_SPLAY
        lda     #10000
        sys     SYS_SLEEP
        exit    0

        .segment "RODATA"
smp8:   .repeat 64, I                   ; a triangle, 64 samples
        .byte   <((I .mod 32) * 8 - 128)
        .endrepeat
smp16:  .repeat 32, I
        .word   (I * 2048 - 32768) & $FFFF
        .endrepeat
p_self: .byte   "/SYSTEM/TESTS/STEST.PRG", 0
a_exit: .byte   "x", 0
a_kill: .byte   "k", 0
b_code: spb     smp8, 64, 0, $4000, 128, SPF_LOOP, SP_ANY
b_win:  spb     $001000, 32, 8, $2000, 96, SPF_LOOP | SPF_16, 2
b_kern: spb     $010000, 64, 0, $4000, 128, 0, SP_ANY
b_fb:   spb     $7C0000, 64, 0, $4000, 128, 0, SP_ANY
b_free: spb     $7B0000, 64, 0, $4000, 128, 0, SP_ANY
b_wend: spb     $007FF0, 32, 0, $4000, 128, 0, SP_ANY
b_odd:  spb     $001001, 8, 0, $4000, 128, SPF_16, SP_ANY
b_zero: spb     smp8, 0, 0, $4000, 128, 0, SP_ANY
b_short: spb    smp8, 64, 61, $4000, 128, SPF_LOOP, SP_ANY
b_v8:   spb     smp8, 64, 0, $4000, 128, 0, 8
b_v5:   spb     smp8, 64, 0, $4000, 128, SPF_LOOP, 5

        .segment "DATA"
b_bank: spb     $000000, 64, 0, $4000, 128, SPF_LOOP, 3
b_cross: spb    $00FFE0, 64, 0, $4000, 128, 0, SP_ANY

        .segment "ZEROPAGE"
alen:   .res    2
bank:   .res    2
p:      .res    4
kid:    .res    2
vol:    .res    2
