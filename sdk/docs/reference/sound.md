# Sound

Native sound on the current boards (hardware REV $07 and later) is the **POKEY of the
classic machine** (four square-wave / noise voices), lent to Horizon while that machine is
frozen (always, while the desktop is shown). Programs reach it only through two syscalls.
REV $07 to $0B had a second POKEY ("POKEY 2") for this, and **four 8-bit DACs** (two left,
two right); REV $0C has one POKEY with a register bank of its own for Horizon, mono, and no
DACs (writes to them do nothing: use Lau). Code written for POKEY 2 runs unchanged.

Hardware REV $0A adds **Lau**, the 8-voice sample player (`Docs/02-register-spec.md`,
"Lau"): signed 8- or 16-bit PCM from RAM, 48 kHz output, a pitch and two volumes per voice,
loops. Horizon 0.17 gives programs four calls for it ($68-$6B, below). On older boards they
return ENODEV: ask SYS_SSTAT once at the start and fall back to POKEY.

Hardware REV $0C adds the **OPL2**, a YM3812 FM synthesizer (the AdLib's chip: nine
two-operator voices; `Docs/02-register-spec.md`, "OPL2"). Horizon 0.27 gives programs one
call for it ($6D, below) and plays MIDI files on it.

The emulator makes no sound. `run816.py --log-sound` (emu816 `--log-sound`) logs every
accepted write (`sound $DB01 = $AC`) in `emu.err`, `run816.py --log-lau` every write to Lau
(`lau $DB20 = $00`), emu816 `--log-opl` every OPL2 register write (`opl $B0 = $31`): test
your sound code with those (`emu816 --wav FILE` records Lau; the OPL2's sound is not
modelled, only its registers and timers).

### $65 beep (SYS_BEEP)
In: A = pitch (POKEY AUDF value), X = duration in 10 ms ticks (0 = silence: channel 1
off; before Horizon 0.15 every voice and the DACs), Y = volume 0-15. A pure tone on POKEY
channel 1, stopped by the kernel's tick; a new beep replaces the one playing. Ignored before
REV $07 and while the classic machine runs. The UI's error beep is the chime (`ui_beep`,
SYS_CHIME, Horizon 0.15), on a channel no program uses.
```asm
        lda     #$50            ; pitch
        ldx     #10             ; 100 ms
        ldy     #8              ; volume
        sys     SYS_BEEP
```

### $66 sound_write (SYS_SNDW)
In: A = register $00-$13, X = value (low byte). A raw write to $00:DB00 + A: $00-$0F POKEY,
$10-$13 the DACs (0 and 1 left, 2 and 3 right; none on REV $0C). EINVAL above $13. Each call costs about
50 us (emulator), so a note change is cheap, sample playback through the DACs is not.
```asm
        lda     #$00            ; AUDF1: the pitch of channel 1
        ldx     #60
        sys     SYS_SNDW
        lda     #$01            ; AUDC1: pure tone ($A0), volume 10
        ldx     #$A0 | 10
        sys     SYS_SNDW
```

**Silence when you stop playing.** Since Horizon 0.15 the kernel silences the channels
and DACs a program wrote when it ends (and puts AUDCTL and SKCTL back); before 0.15 a
tone left on kept playing. Within a program, turn a voice off with its AUDC = 0:
```asm
        lda     #$01            ; AUDC1
        ldx     #0              ; volume 0
        sys     SYS_SNDW
```
If you changed AUDCTL ($08), set it back to 0 when the music stops.

## POKEY registers (writes through SYS_SNDW)

| Register | Name | Meaning |
| --- | --- | --- |
| $00, $02, $04, $06 | AUDF1-4 | the pitch of channel 1-4 (a divider: higher = lower note) |
| $01, $03, $05, $07 | AUDC1-4 | bits 7-5 distortion, bit 4 volume only (the output is the volume level: a DAC), bits 3-0 volume |
| $08 | AUDCTL | bit 0 15 kHz base clock (else 64 kHz), 1 high-pass filter on channel 2 by 4, 2 high-pass on 1 by 3, 3 join channels 4 + 3 (16 bits), 4 join 2 + 1, 5 channel 3 from 1.79 MHz, 6 channel 1 from 1.79 MHz, 7 the 9-bit noise polynomial (else 17-bit) |
| $09 | STIMER | (any value) restart the channel counters together |
| $0F | SKCTL | serial / keyboard control; the kernel writes 3 at boot (POKEY out of reset). Leave it |

REV $0C takes exactly these registers (of SKCTL, bits 0 and 1); the others never did anything
useful for sound.

Distortion (the high nibble of AUDC) in practice:

| AUDC high nibble | Sound |
| --- | --- |
| $A (or $E) | pure square tone |
| $8 | white noise (explosions, hits; pitch = colour of the noise) |
| $C | buzzy tone (engines, "bass") |
| $2 / $4 / $6 | rough, metallic noises |
| $0 | crackling noise |

Pitch: on the 64 kHz clock, f = 63921 / (2 x (AUDF + 1)) Hz, so AUDF = 31960 / f - 1
(BASIC's SOUND uses this: 125-15980 Hz). On the 15 kHz clock (AUDCTL bit 0), 15700 instead
of 63921. With a channel on 1.79 MHz (AUDCTL bits 5 / 6), f = 1789790 / (2 x (AUDF + 4));
joined 16-bit pairs (bits 3 / 4, low byte in the lower channel): f = 1789790 / (2 x
(AUDF16 + 7)), fine tuning for music. (Standard Atari POKEY formulas with the NTSC clock;
the board's POKEY runs from the 1.79 MHz classic clock tick. Not measured here.)

Notes (64 kHz clock, pure tone): AUDF for an octave from middle C:

| Note | C4 | D4 | E4 | F4 | G4 | A4 | B4 | C5 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Hz | 262 | 294 | 330 | 349 | 392 | 440 | 494 | 523 |
| AUDF | 121 | 108 | 96 | 91 | 81 | 72 | 64 | 60 |

## The DACs (REV $07 to $0B only)

`SYS_SNDW` registers $10-$13: four 8-bit DACs (0, 1 left; 2, 3 right), the value is the
output level. REV $0C does not have them. Without a timer interrupt or DMA for programs, a program can only change a
level per syscall (about 50 us each): clicks, ramps, a few hundred Hz of a coarse wave
while the program does nothing else. Lau, the sample player, is the answer (REV $0A,
Horizon 0.17: below).

## A sound effect engine

Games change the pitch and volume of a voice a little every tick (20 ms): a rising "pick
up" blip, a falling "game over", a noise burst that fades. See `sfx_*` in
`sdk/templates/game/main.s`: per voice a pitch, a pitch step, a volume, a volume step and a
length, and two SYS_SNDW calls per voice per tick.

```asm
; every tick: voice 0 (channel 1) slides its pitch and fades
        lda     z:t0            ; pitch
        and     #$00FF
        tax
        lda     #$00            ; AUDF1
        sys     SYS_SNDW
        lda     z:t1            ; volume 0-15
        ora     #$A0            ; pure tone
        tax
        lda     #$01            ; AUDC1
        sys     SYS_SNDW
        dec     z:t0            ; higher
        lda     z:t1
        beq     :+
        dec     z:t1            ; quieter
:
```

## Samples: Lau (Horizon 0.17)

Lau reads the samples from RAM by itself while it plays, past the memory protection, so the
kernel checks that the whole sample lies in **your own memory** (the window, the code bank,
banks from SYS_BALLOC; a range may run across consecutive banks you own), and remembers which
task started each voice. Keep the sample where it is, unchanged, while it plays (changing it
is heard: streaming into a loop works). Your voices stop when your program ends (also when it
is killed) and when you free a bank one of them plays from; all voices stop while the
classic machine is shown. **The sound volume** (Horizon 0.18: setting 4, `SYS_SETTING`,
0-15, default 8; [system.md](system.md)) is Lau's master volume, x 17: the user's choice for
every program's samples, separate from the alert volume (setting 1, the beeps and chimes on
POKEY; 0.17 used that one for Lau too). At the default one voice at 255 reaches about a
quarter of full scale; leave the setting to the user and choose your voices' volumes.

The pitch is the step per 48 kHz output sample in 2.14 fixed point: $4000 plays a 48 kHz
recording at its own pitch, $2000 a 24 kHz one, $1555 a 16 kHz one; a semitone up is x
1.0595. There is no interpolation: samples made near 48 kHz, or played near their own rate,
sound cleanest. 16 kHz 8-bit is a good size for game effects (16 KB a second).

The emulator plays Lau exactly (`emu816 --wav FILE` writes its output, `--log-lau` logs the
writes; `run816.py --log-lau` passes that on). `sdk/examples/deepdive` makes its two samples
at run time (`makesound`) and plays them with SP_ANY.

### $68 sample_play (SYS_SPLAY)
In: X, Y = a 16-byte block: u24 address of the first sample, u24 length in samples, u24 loop
start (with SPF_LOOP), u16 pitch, u8 left and u8 right volume (0-255), u8 flags (SPF_LOOP 1,
SPF_16 2: 16-bit little-endian samples at an even address), u8 voice (0-7, or SP_ANY $FF: the
first voice not playing, else your voice that started first), u8 0. Out: A = the voice.
Errors: ENODEV no Lau; EFAULT the sample is not all in your memory; EINVAL no samples, an
odd 16-bit address, a loop shorter than 4 samples, a voice above 7; EAGAIN the voice plays
for another program (SP_ANY: all eight play and none is yours).
```asm
        ptr     boom
        sys     SYS_SPLAY       ; A = the voice (C set: A = ENODEV -> POKEY)
        rts
boom:   .faraddr boom_pcm       ; the samples (here in the code bank)
        .faraddr 3200           ; 3200 samples: 0.2 s at 16 kHz
        .faraddr 0              ; (loop start)
        .word   $1555           ; 16 kHz
        .byte   200, 200        ; left, right
        .byte   0               ; 8-bit, no loop
        .byte   SP_ANY, 0
boom_pcm: .res  3200            ; (signed 8-bit samples)
```
The block's offsets are `SPB_ADDR` .. `SPB_VOICE` in horizon.inc.

### $69 sample_stop (SYS_SSTOP)
In: A = one of your voices, or $FFFF: all of them. EINVAL: not your voice.
```asm
        lda     #$FFFF
        sys     SYS_SSTOP       ; silence (e.g. the game pauses)
```

### $6A sample_stat (SYS_SSTAT)
Out: A = your voices still playing (bit n = voice n), X = all voices playing. ENODEV without
Lau: the cheapest test for it.
```asm
        sys     SYS_SSTAT
        bcs     :+              ; no Lau: use POKEY
        lda     #1
        sta     have_lau
:       rts
have_lau: .res  2
```

### $6B sample_set (SYS_SSET)
In: A = one of your voices, X = pitch, Y = left volume | right volume << 8. Taken at the next
output sample: slides, fades and panning without restarting the sample. EINVAL: not your
voice.
```asm
        lda     #0              ; voice 0: an octave down, panned left
        ldx     #$0AAA
        ldy     #$40FF
        sys     SYS_SSET
```

### $6C sample_timer (SYS_STIMER)
In: A = one of your ports ($FFFF: off), X = the period's low 16 bits, Y = its high 8 bits, in
microseconds (1,000 or more). Out: A = the generation. Horizon 0.26: **the music timer**
(TIMER1, REV $0A+). At every period the kernel puts {u8 $FF, u8 the generation, u16 the
count of periods since the start, 12 x 0} into the port (when there is room; the count goes on
anyway and follows the microsecond clock: a jump means periods passed, run that many ticks) and wakes you in `recv`. Called again while it runs, the
new period counts from the next one on: a tempo change without a gap. Each start from off is a
new generation, so messages queued before a restart can be ignored. One owner at a time
(EAGAIN); ENODEV without Lau; it stops at your end. Run the task that waits for it at
**priority 0** (spawn's priority byte) and its ticks come within a fraction of a millisecond,
whatever other programs do. 1 ms is the shortest period.
```asm
        sys     SYS_PCREATE
        sta     z:n                     ; the port
        ldx     #.loword(20000)         ; 20 ms: 125 BPM
        ldy     #^20000
        sys     SYS_STIMER
:       lda     z:n
        ptr     buf
        sys     SYS_RECV                ; buf = {$FF, generation, count}
        ; ... one tick
        bra     :-
```
`SPF_KEEP` (4, Horizon 0.26) in sample_play's flags marks a voice as music: it plays on while
the classic Atari is shown (the others stop).

## FM: the OPL2 (Horizon 0.27, REV $0C)

### $6D opl_write (SYS_OPLW)
In: A = an OPL2 register $00-$F5 and X = its value; or A = $FFFE (probe: nothing written),
$FFFF (reset: every register 0, about 10 ms) or $FFFD (release). Out: A = the chip's status
($06 when idle). Each write costs about 45 us (the kernel waits as a YM3812 needs). **One
owner**: the first program that writes or resets owns the chip until it ends or releases it;
another program's write gets EAGAIN meanwhile (the probe always answers). When the owner ends
or releases, all notes are keyed off; while the classic machine is shown the notes are keyed
off too, the rest stays. Errors: ENODEV before REV $0C, EINVAL another A above $F5, EAGAIN.
The registers are the YM3812's (any AdLib programming guide applies).
```asm
        lda     #$FFFE
        sys     SYS_OPLW        ; C set: no OPL2 (ENODEV)
        bcs     nofm
        lda     #$FFFF
        sys     SYS_OPLW        ; reset: the chip is ours (C set: EAGAIN, in use)
        bcs     nofm
        lda     #$20            ; modulator of channel 0: multiple 1
        ldx     #$01
        sys     SYS_OPLW
        lda     #$40            ; its level: -24 dB
        ldx     #$10
        sys     SYS_OPLW
        lda     #$60            ; attack 15, decay 0
        ldx     #$F0
        sys     SYS_OPLW
        lda     #$80            ; sustain 0 dB, release 7
        ldx     #$07
        sys     SYS_OPLW
        lda     #$23            ; the carrier: the same, full level
        ldx     #$01
        sys     SYS_OPLW
        lda     #$43
        ldx     #$00
        sys     SYS_OPLW
        lda     #$63
        ldx     #$F0
        sys     SYS_OPLW
        lda     #$83
        ldx     #$07
        sys     SYS_OPLW
        lda     #$A0            ; 440 Hz: F-number $241, block 4
        ldx     #$41
        sys     SYS_OPLW
        lda     #$B0            ; key on
        ldx     #$32
        sys     SYS_OPLW
        ; ... later
        lda     #$FFFD
        sys     SYS_OPLW        ; notes off, the chip is free again
nofm:   rts
```
`horizon/user/opldemo.s` (the OPL2 program) is a small synthesizer on this call;
`horizon/user/midplay.s` is the MIDI player of the music engine.

## Music: modules, WAV and MIDI files (Horizon 0.26, 0.27)

Two ways to have music in a program.

**The engine**, `/SYSTEM/MUSICD.PRG`: start it with `spawn` at **priority 0** with the
arguments `-p PORT` (a port you created). It answers `MS_HELLO` with its own port, then takes
16-byte commands: `MC_PATH` (the file's path, 14 characters a message) and `MC_LOAD`,
`MC_PLAY`, `MC_PAUSE`, `MC_STOP`, `MC_SEEK`, `MC_VOL`, `MC_SEP`, `MC_LOOP`, `MC_READ` (bytes of
the module or of its info block), `MC_QUIT`; it sends `MS_STATUS` (state, order, row,
pattern, time, the level of each channel) after every tick. `horizon/user/music.inc` has the
whole protocol; `horizon/user/music.s` (the Music program) uses all of it. It plays MOD files
(4-8 channels, 15 or 31 samples), WAV files (PCM 8/16-bit, mono or stereo, read whole into
memory) and, on REV $0C (Horizon 0.27), MIDI files (.MID, on the OPL2, which it owns while
such a song plays), from the card, `/PC:` or an `http(s)://` / `ftp://` URL. It ends with your program.
Nothing to link; your program keeps its own loop.

**The replayer library**, `horizon/build/modplay.o` (`horizon/user/modplay.s`, API in
`horizon/user/modplay.inc`): link it and play a module that lies in your memory yourself.
Put its address and length in `mp_mod` / `mp_mlen`, call `mp_open` (C set: not a module),
`mp_play` (A = the first order; the first tick runs at once), then `mp_tick` every
`mp_tickus` microseconds: the music timer above gives you exactly that. `mp_tick` returns
`MPF_TEMPO` (give the timer the new `mp_tickus`) and `MPF_END` (the song ended; with
`mp_loop` = 1 it goes on from the start). `mp_pause`, `mp_resume`, `mp_stop`, `mp_seek` (A =
order), `mp_setvol` (0-64), `mp_setsep` (stereo separation 0-64, default 32). State to show:
`mp_order`, `mp_row`, `mp_pat`, `mp_speed`, `mp_bpm`, `mp_tenths` (time played), `mp_lev`
(8 bytes: the level of each channel 0-64, when `mp_meter` is 1).

- **Voices:** a module of N channels takes Lau's voices 8 - N .. 7: a 4-channel module leaves
  voices 0-3 to your sound effects (`SP_ANY` takes the lowest free voice, so effects and
  music never meet). Set `mp_keep` to `SPF_KEEP` for music that plays on while the classic
  Atari is shown.
- **Timing:** tick the music from a task at priority 0 that waits for the music timer
  (as `/SYSTEM/MUSICD.PRG` does): steady whatever the rest does. A game that calls `mp_tick`
  from its frame loop instead (60 frames, 50 ticks a second at 125 BPM: count microseconds
  and tick when one is due) is late by up to a frame now and then: fine for simple tunes.
- **Cost:** about 0.3 ms of CPU a tick for the library (4 channels), plus the kernel's wake-up.
- `mp_cbuf` (u24, a 64 KB bank you allocated, or 0) is only for a sample offset (9xx) that
  lands inside a sample's loop.

`sdk/examples/tune` plays a module in 30 lines of code: read the file into a bank, `mp_open`,
`mp_play`, then wait for the timer and `mp_tick` until `MPF_END`.

More modules: copy `.MOD` files to the card, or fetch one in the shell with
`get http://... /Music/NAME.MOD`; double-click it in Files to play it in Music.

## BASIC

`SOUND v, f, vol`, `SOUND v, pitch, distortion, vol` (Atari BASIC's form), `SOUND`, `BEEP`:
see `horizon/BASIC.md`, "Sound". BASIC 2.0 plays samples on Lau too (`horizon/BASIC.md`,
"Samples"): `WAVE s, shape, ms, half` makes a sine, square, triangle, saw or noise sample with
a decay (no file needed), `WAVE s, "FILE.WAV"` loads a PCM .WAV (8 or 16 bits, mono) or raw
signed 8-bit samples at 16 kHz, `PLAY s, note, volume, pan, voice` plays one (`note`: semitones
or a name such as `"C#5"`; one `sample_play` each), `PLAY OFF` stops them, `NOTE("A4")` is 9.

### $67 sound_chime (SYS_CHIME)
In: A = CH_INFO 0, CH_WARN 1, CH_QUESTION 2 or CH_ERROR 3; X = volume 0-15 ($FFFF: the
user's alert volume setting). Horizon 0.15: the soft two-note chime of the user interface
(pure tone, the volume falling every 10 ms, 0.22 s). It plays on a POKEY channel no
program owns; if a program owns all four, it borrows channel 4 and gives the program's
values back after it. The controls library's alerts and `ui_beep` use it.
```asm
        lda     #CH_INFO
        ldx     #$FFFF          ; the setting's volume
        sys     SYS_CHIME
```

Sound ownership (Horizon 0.15): every channel, DAC and the rest of POKEY (AUDCTL, SKCTL)
remembers the task that wrote it last; when that task ends, its channels and DACs are
silenced (AUDCTL and SKCTL go back to 0 and 3), so a game killed while it plays leaves no
tone hanging.
