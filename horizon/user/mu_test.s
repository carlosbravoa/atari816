; mu_test.s - Music's self test ("music -t", no window): the names shown for paths and URLs,
; arguments, which folder entries are songs, times, the error texts, the settings file read
; and written again, the playlist sorted. The output is compared with tests/music-t.txt.
; Included by music.s.

        .segment "CODE"

test_run:
        print   "music -t: the self test\n"
        print   "names:\n"              ; the name shown
        ldx     #.loword(tnames)
@n:     lda     a:0,x
        beq     @args
        phx
        tax
        ldy     #.loword(pbuf)
        jsr     ui_strcpy
        jsr     namepb
        jsr     tshow                   ; "  pbuf -> nbuf"
        plx
        inx
        inx
        bra     @n
@args:  print   "arguments:\n"          ; quotes and blanks taken off, made absolute
        ldx     #.loword(targs)
@a:     lda     a:0,x
        beq     @songs
        phx
        tax
        ldy     #.loword(pbuf)
        jsr     ui_strcpy
        print   "  ["
        ldx     #.loword(pbuf)
        ldy     pbank
        jsr     put_str
        ldx     #.loword(pbuf)
        jsr     unquote
        jsr     abspath
        print   "] -> ["
        ldx     #.loword(pbuf)
        ldy     pbank
        jsr     put_str
        print   "]\n"
        plx
        inx
        inx
        bra     @a
@songs: print   "songs in a folder:\n"  ; a folder's entries: songs?
        ldx     #.loword(tfold)
        ldy     #.loword(fbuf)
        jsr     ui_strcpy
        ldx     #.loword(tents)
@s:     lda     a:0,x
        jeq     @times
        phx
        tax                             ; the entry's name at dbuf + 6
        ldy     #.loword(dbuf + 6)
        jsr     ui_strcpy
        sta     z:t5
        stz     z:g7
        print   "  "
        ldx     #.loword(dbuf + 6)
        ldy     pbank
        jsr     put_str
        jsr     songname
        bcc     :+
        print   " -> "
        ldx     #.loword(pbuf)
        ldy     pbank
        jsr     put_str
        bra     :++
:       print   ": not a song"
:       jsr     put_nl
        plx
        inx
        inx
        bra     @s
@times: print   "times:"                ; tenths -> m:ss
        ldx     #0
:       phx
        lda     ttimes,x
        pha
        print   " "
        pla
        jsr     put_dec
        print   "="
        stz     sl
        plx
        phx
        lda     ttimes,x
        jsr     sappt10
        ldx     #.loword(sbuf)
        ldy     pbank
        jsr     put_str
        plx
        inx
        inx
        cpx     #2 * 6
        bcc     :-
        jsr     put_nl
        print   "errors:\n"             ; the load errors' texts
        ldx     #0
:       phx
        lda     tcodes,x
        pha
        print   "  $"
        pla
        pha
        jsr     put_hex8
        print   " "
        pla
        jsr     errtext
        ldy     pbank
        jsr     put_str
        jsr     put_nl
        plx
        inx
        inx
        cpx     #2 * NTCODES
        bcc     :-
        print   "settings read:\n"      ; a settings text read
        jsr     pl_init
        stz     lnl
        ldx     #0
:       lda     tcfg,x
        and     #$00FF
        beq     :+
        phx
        jsr     cfg_ch
        plx
        inx
        bra     :-
:       lda     #10
        jsr     cfg_ch
        print   "  volume "
        lda     vol
        jsr     put_dec
        print   ", separation "
        lda     msep
        jsr     put_dec
        print   ", repeat "
        lda     mrep
        jsr     put_dec
        print   ", shuffle "
        lda     shuf
        jsr     put_dec
        print   ", current "
        lda     cur
        jsr     put_dec
        jsr     put_nl
        jsr     tlist
        print   "settings written:\n"   ; and written again (to the console)
        lda     cur
        sta     lst_pl+LS_SEL
        lda     #1
        sta     wsink
        jsr     cfg_text
        print   "sorted:\n"             ; songs sorted by their paths (ignoring case)
        jsr     pl_init
        ldx     #.loword(tsort)
:       lda     a:0,x
        beq     :+
        phx
        tax
        ldy     #.loword(pbuf)
        jsr     ui_strcpy
        jsr     pl_add
        plx
        inx
        inx
        bra     :-
:       lda     #0
        jsr     pl_sort
        jsr     tlist
        print   "removed the second:\n"
        lda     #2
        sta     cur
        lda     #1
        jsr     pl_remove
        jsr     tlist
        print   "  current "
        lda     cur
        jsr     put_dec
        jsr     put_nl
        print   "music -t: done\n"
        exit    0

; "  pbuf -> nbuf"
tshow:  print   "  "
        ldx     #.loword(pbuf)
        ldy     pbank
        jsr     put_str
        print   " -> "
        ldx     #.loword(nbuf)
        ldy     pbank
        jsr     put_str
        jmp     put_nl

; the playlist printed, a row a line
tlist:  stz     z:g6
:       lda     z:g6
        cmp     pl_n
        bcs     :+
        jsr     pl_get
        print   "  "
        lda     z:g6
        inc     a
        jsr     put_dec
        print   ": "
        ldx     #.loword(pbuf)
        ldy     pbank
        jsr     put_str
        jsr     put_nl
        inc     z:g6
        bra     :-
:       rts

        .segment "RODATA"
tnames: .addr   :+, :++, :+++, :++++, :+++++, :++++++, 0
:       .byte   "/Music/HORIZON.MOD", 0
:       .byte   "LAU.MOD", 0
:       .byte   "http://example.com/mods/space%20debris.mod?x=1#top", 0
:       .byte   "ftp://ftp.example.org/", 0
:       .byte   "https://music.example.net", 0
:       .byte   "/PC:/songs/Song one.wav", 0
targs:  .addr   :+, :++, :+++, :++++, 0
:       .byte   34, "/Music/A B.MOD", 34, 0
:       .byte   "   /x.mod  ", 0
:       .byte   "http://h/a.mod", 0
:       .byte   "songs/b.wav", 0
tfold:  .byte   "/Music", 0
tents:  .addr   :+, :++, :+++, :++++, :+++++, :++++++, :+++++++, 0
:       .byte   "HORIZON.MOD", 0
:       .byte   "lau.mod", 0
:       .byte   "Voice.Wav", 0
:       .byte   "mod.tune", 0
:       .byte   "notes.txt", 0
:       .byte   ".mod", 0
:       .byte   "modern.mo", 0
ttimes: .word   0, 9, 10, 600, 1925, 65535
NTCODES = 9
tcodes: .word   $44, $47, E_NOLINK, E_LOST, E_HTTP, ENOMEM, EMS_FORMAT, $C2, $99
tcfg:   .byte   "# a comment", 10
        .byte   "volume=48", 13, 10
        .byte   "Separation=20", 10
        .byte   "repeat=One", 10
        .byte   "shuffle=on", 10
        .byte   "current=2", 10
        .byte   "/Music/LAU.MOD", 10
        .byte   "  /Music/HORIZON.MOD  ", 10
        .byte   "http://example.com/x.mod", 10
        .byte   "/music/lau.mod", 10
        .byte   "a line that means nothing", 10
        .byte   "volume=99", 10
        .byte   "/PC:/a.wav", 0
tsort:  .addr   :+, :++, :+++, :++++, 0
:       .byte   "/F/b.mod", 0
:       .byte   "/F/C.MOD", 0
:       .byte   "/F/a.wav", 0
:       .byte   "/F/B2.mod", 0
        .segment "CODE"
