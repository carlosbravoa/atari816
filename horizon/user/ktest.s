; KTEST - (0.15) a test of the kernel additions of 0.15, run from the text shell by
; tests/ktest.src (make test): it prints what it sees, compared with tests/ktest.txt, and
; its sound writes are logged by emu816 (--log-sound) and compared with tests/ktest.err.
;   1. joystick: SYS_JOY read, the test aid (directions and triggers ORed in), off again
;   2. vsync: 30 vertical blanks take 500 ms (16.7 ms each)
;   3. the chime: the four kinds at volume 8 (their envelopes in the sound log)
;   4. sound ownership: "ktest snd" writes POKEY 2 and a DAC and exits: the kernel silences
;      them; then this task holds all four channels and asks for a chime: it borrows
;      channel 4 and gives it back as it was; at the exit it is silenced too
;   5. the window system (started here): window A (WF_HOVER, a menu) prints its events. Keys
;      from the script: o opens window B (A gets the releases of the keys it holds, then
;      WE_UNFOCUS; B WE_FOCUS; the real releases come to nobody), c closes B, p (or the
;      menu key) a pop-up menu (SYS_WPOPUP) at the pointer (from the keyboard: at 10, 10),
;      a right press in A one at the pointer, q ends. Motion events print only when their
;      buttons field changes (after a menu: 0000, no phantom bit).
        .include "horizon.inc"

        .segment "CODE"
        .a16
        .i16
start:  sta     z:alen
        jsr     args_init
        lda     z:alen                  ; "ktest snd": the child of part 4
        beq     :+
        jmp     child
:       print   "ktest 1: joystick "
        lda     #0
        sys     SYS_JOY
        jsr     pjoy
        lda     #1                      ; the test aid: port 1 up + port 2 right, trigger 2
        ldx     #JOY_UP | (JOY_RIGHT << 4)
        ldy     #2
        sys     SYS_JOY
        lda     #0
        sys     SYS_JOY
        jsr     pjoy
        lda     #1
        ldx     #0
        ldy     #0
        sys     SYS_JOY
        lda     #0
        sys     SYS_JOY
        jsr     pjoy
        jsr     put_nl

        print   "ktest 2: vsync "
        sys     SYS_VSYNC               ; (in step with the blanks first)
        sys     SYS_UPTIME
        sta     z:t0
        ldx     #30
:       phx
        sys     SYS_VSYNC
        plx
        dex
        bne     :-
        sys     SYS_UPTIME
        sec
        sbc     z:t0
        cmp     #490                    ; 30 x 16.68 ms = 500 ms
        bcc     @vbad
        cmp     #511
        bcs     @vbad
        print   "30 in 500 ms: ok"
        bra     :+
@vbad:  pha
        print   "30 in ms: "
        pla
        jsr     put_dec
:       jsr     put_nl

        print   "ktest 3: chimes\n"
        jsr     out_flush
        stz     z:t0
:       lda     z:t0
        ldx     #8
        sys     SYS_CHIME
        lda     #300
        sys     SYS_SLEEP
        inc     z:t0
        lda     z:t0
        cmp     #4
        bcc     :-

        print   "ktest 4: sound owners\n"
        jsr     out_flush
        lda     #.loword(a_snd)         ; the child writes, exits: silenced
        sta     z:u_arg
        lda     #^a_snd
        sta     z:u_arg+2
        ptr     p_self
        lda     #1
        jsr     spawn
        bcs     :+
        sys     SYS_WAIT
:       lda     #100
        sys     SYS_SLEEP
        ldx     #0                      ; all four channels ours: AUDF = $50 + 2 i, AUDC = $A3
:       phx
        txa
        asl     a
        pha
        clc
        adc     #$50
        tax
        pla
        sys     SYS_SNDW
        lda     1,s
        asl     a
        inc     a
        ldx     #$A3
        sys     SYS_SNDW
        plx
        inx
        cpx     #4
        bcc     :-
        lda     #CH_ERROR               ; the chime: channel 4 borrowed and given back
        ldx     #4
        sys     SYS_CHIME
        lda     #300
        sys     SYS_SLEEP

        print   "ktest 5: windows\n"
        jsr     out_flush
        sys     SYS_WSSTART
        bcc     :+
        print   "no window system\n"
        exit    1
:       ptr     wa
        sys     SYS_WOPEN
        sta     z:wina
        lda     #$FF
        sta     z:winb
        lda     z:wina
        ptr     menus
        sys     SYS_WMENU
        lda     #$FFFF
        sta     z:lastc
loop:   lda     #0
        ptr     ev
        sys     SYS_WEVENT
        bcs     loop
        lda     ev
        and     #$00FF
        cmp     #WE_MOTION
        bne     @show
        lda     ev+6                    ; motion: only a change of its buttons field
        cmp     z:lastc
        beq     loop
        sta     z:lastc
@show:  print   "ev "
        lda     ev
        and     #$00FF
        jsr     put_dec
        lda     ev+1                    ; the window: A or B
        and     #$00FF
        cmp     z:wina
        bne     :+
        print   " A"
        bra     :++
:       print   " B"
:       lda     ev
        and     #$00FF
        cmp     #WE_MOTION              ; (motion: its position depends on timing)
        beq     :+
        lda     #' '
        jsr     out_char
        lda     ev+2
        jsr     put_hex16
        lda     #' '
        jsr     out_char
        lda     ev+4
        jsr     put_hex16
:       lda     #' '
        jsr     out_char
        lda     ev+6
        jsr     put_hex16
        jsr     put_nl
        lda     ev
        and     #$00FF
        cmp     #WE_BUTTON
        jeq     onbtn
        cmp     #WE_KEY
        jne     loop
        lda     ev+4                    ; a key down
        cmp     #$0100
        jcc     loop
        lda     ev+2
        cmp     #$12                    ; o: window B
        bne     :+
        lda     z:winb
        cmp     #$FF
        jne     loop
        ptr     wb
        sys     SYS_WOPEN
        sta     z:winb
        jmp     loop
:       cmp     #$06                    ; c: B closed
        bne     :+
        lda     z:winb
        cmp     #$FF
        jeq     loop
        sys     SYS_WCLOSE
        lda     #$FF
        sta     z:winb
        jmp     loop
:       cmp     #$13                    ; p: a pop-up menu at the pointer
        bne     :+
        lda     #POP_HERE
        ldx     #0
        jsr     popup
        jmp     loop
:       cmp     #$65                    ; the menu key: from the keyboard, at 10, 10
        bne     :+
        lda     #10
        ldx     #POP_KEY
        jsr     popup
        jmp     loop
:       cmp     #$14                    ; q: the end
        jne     loop
        sys     SYS_WSSTOP
        print   "ktest: done\n"
        exit    0
onbtn:  lda     ev+6                    ; a right press: a pop-up menu at the pointer
        and     #2
        jeq     loop
        lda     #POP_HERE
        ldx     #0
        jsr     popup
        jmp     loop

; A = x (POP_HERE: the pointer; else x = y = A), X = flags: the pop-up menu in window A,
; its answer printed
popup:  pha
        phx
        lda     #.loword(pitems)
        sta     pblk
        lda     #^pitems
        sta     pblk+2
        pla
        sta     pblk+7
        pla
        sta     pblk+3
        sta     pblk+5
        lda     z:wina
        ptr     pblk
        sys     SYS_WPOPUP
        pha
        print   "popup "
        pla
        jsr     put_hex16
        jmp     put_nl

; A = directions, X = triggers: "dd tt "
pjoy:   phx
        jsr     put_hex8
        lda     #' '
        jsr     out_char
        pla
        jsr     put_hex8
        lda     #' '
        jmp     out_char

; "ktest snd": POKEY 2 channel 1 and 3, AUDCTL, DAC 0 written; then the exit
child:  ldx     #$40
        lda     #0
        sys     SYS_SNDW
        ldx     #$A6
        lda     #1
        sys     SYS_SNDW
        ldx     #$60
        lda     #4
        sys     SYS_SNDW
        ldx     #$A5
        lda     #5
        sys     SYS_SNDW
        ldx     #$01                    ; AUDCTL: the 15 kHz clock
        lda     #8
        sys     SYS_SNDW
        ldx     #$80
        lda     #$10                    ; DAC 0
        sys     SYS_SNDW
        lda     #50
        sys     SYS_SLEEP
        exit    0

        .segment "RODATA"
p_self: .byte   "/SYSTEM/TESTS/KTEST.PRG", 0
a_snd:  .byte   "snd", 0
menus:  .byte   "Test", 0, "First", 0, "Second", 0, 0, 0
pitems: .byte   "One", 0, "Two", 0, "-", 0, MS_STATE | MS_DIM, "Dimmed", 0, "Three", 0, 0
wa:     .word   100, 100, 200, 100
        .faraddr t_a
        .byte   WF_HOVER
wb:     .word   350, 100, 150, 80
        .faraddr t_b
        .byte   0
t_a:    .byte   "A", 0
t_b:    .byte   "B", 0

        .segment "BSS"
ev:     .res    8
pblk:   .res    9

        .segment "ZEROPAGE"
alen:   .res    2
t0:     .res    2
wina:   .res    2
winb:   .res    2
lastc:  .res    2
