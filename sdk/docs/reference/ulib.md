# ulib and the macros of horizon.inc

`horizon/build/ulib.o` is linked into every program. Source: `horizon/user/ulib.s`.
All routines: `jsr`, A/X/Y 16-bit, A, X, Y clobbered unless noted. It uses 38 bytes of
your zero page (`u_*`).

## Macros (horizon.inc)

| Macro | Expands to | Notes |
| --- | --- | --- |
| `sys NAME` | `cop NAME` | a syscall |
| `print "text"` | `ldx`/`ldy` + `jsr out_str` + the text inline | buffered output; clobbers A, X, Y; at most 120 characters. The text sits in the code: a `bra` over a few prints may be out of range (use `jmp` or `jne`/`jeq`) |
| `ptr label` | `ldx #.loword(label)` / `ldy #^label` | X, Y = a pointer for a syscall |
| `exit n` | `jsr out_flush` / `lda #n` / `cop SYS_EXIT` | |
| `jeq`, `jne`, `jcc`, `jcs` `label` | a short branch over a `jmp` | long conditional branches; they keep `@cheap` labels working |

## Output (line-buffered)

Output collects in a buffer and goes to the console as one `puts` per line (at `\n`, when
the buffer is full, or at `out_flush`), so a line is never mixed with another program's.
**Flush before you wait for input** when the prompt has no line end.

| Routine | In |
| --- | --- |
| `out_char` / `put_char` | A = character |
| `out_str` / `put_str` | X, Y = zero-terminated string (X offset, Y bank: `ptr label`) |
| `put_nl` | - (a line feed) |
| `out_flush` | - |
| `put_dec` | A = unsigned 16-bit number, decimal |
| `put_decw` | A = number, X = width: right-aligned with spaces |
| `put_hex8` | A = byte, two hex digits |
| `put_hex16` | A = word, four hex digits |
| `div10` | A = A / 10 (keeps X, Y) |

```asm
        print   "free banks: "
        sys     SYS_MINFO
        jsr     put_dec
        jsr     put_nl
```

## Keyboard (console programs)

| Routine | In / out |
| --- | --- |
| `key_ascii` | A = HID usage, X = modifiers \| down << 8 (an input_read event, or a WE_KEY's a and b) -> A = ASCII, 0 if none. US layout, shift, caps lock; ctrl + letter = 1-26; arrows `KEY_RIGHT` $80, `KEY_LEFT` $81, `KEY_DOWN` $82, `KEY_UP` $83, `KEY_HOME` $84, `KEY_PGUP` $85, `KEY_DEL` $86, `KEY_END` $87, `KEY_PGDN` $88 |
| `read_char` | -> A = the next character typed (waits; SYS_IREAD) |
| `getline` | X, Y = buffer, A = its size -> A = length; echo, Backspace, Left / Right, Up / Down history (8 lines); C set on ctrl-C |

`key_ascii` works for window programs too: pass a WE_KEY event's a in A and b in X.

| Constant | Value |
| --- | --- |
| `KEY_RIGHT` | $80 |
| `KEY_LEFT` | $81 |
| `KEY_DOWN` | $82 |
| `KEY_UP` | $83 |
| `KEY_HOME` | $84 |
| `KEY_PGUP` | $85 |
| `KEY_DEL` | $86 |
| `KEY_END` | $87 |
| `KEY_PGDN` | $88 |

```asm
        lda     ev+2            ; a WE_KEY event: a = usage
        ldx     ev+4            ; b = modifiers | down << 8
        jsr     key_ascii       ; -> A = ASCII (0: none, or a release)
```

## Arguments and strings

| Routine | In / out |
| --- | --- |
| `args_init` | X = the argument string's address (as at start) -> `u_p` points at it |
| `next_arg` | X, Y = buffer, A = its size -> the next word at `u_p` copied (zero-terminated, cut to the size), A = length; C set if none. `"quoted text"` is one word |
| `str_skip` | `u_p` past spaces; A = the character there |
| `parse_dec` | the decimal number at `u_p` -> A; C set if no digit |

`u_p` is a 4-byte long pointer in zero page; you may point it anywhere (`stx z:u_p`,
`sty z:u_p+2`) to use `parse_dec` on your own strings.

## Tasks and Atari software

| Routine | In / out |
| --- | --- |
| `spawn` | X, Y = path, A = priority, `u_arg` = u24 argument string (0 = none) -> A = id, C on error |
| `exit_a` | A = exit code: flush, then SYS_EXIT |
| `atari_kind` | X, Y = file name -> A = 1 disk, 2 executable, 3 cartridge, 0 none (by the extension) |
| `atari_run` | X, Y = path: "start this, and only this" on the classic machine; returns after F12 (C set: error A). (0.23) A BASIC program (.bas .lst): "Run in Atari" (classic_mount `CK_BASRUN`) |
| `atari_rkind` | (0.23) As `atari_kind`, and 4 (`CK_BASRUN`) for .bas and .lst: what `atari_run` can start |
