# C library

Every header a C program for Horizon can include, and every function in it. This page is
the index. The behaviour on Horizon (files, the console, the heap, time, errors) is in
[reference.md](reference.md#c-library-on-horizon), "C library on Horizon", and the sections it names.
Floating point and `math.h`: reference.md, "Floating point". The syscalls (`hz_*` of
`hzsys.h`): [syscalls.md](syscalls.md).

The C library's headers are in `sdk/c/cc816/include`, the SDK's own in `sdk/c/include`.
hcc puts both on the include path. The code is in `sdk/c/lib` (C) and `sdk/c/rt`
(assembly: the start-up, the arithmetic, the memory and string routines, soft float,
`setjmp`). It is built with one function a module, so a program links only what it calls.

## SDK headers

- `horizon.h`: every syscall as a C function (it includes the generated `hzsys.h`), the
  parameter blocks, the error codes, and the helpers below. See [syscalls.md](syscalls.md)
  and [reference.md](reference.md), "Syscalls from C".
- `hzsys.h`: generated from horizon.inc, ABI.md and `sdk/c/tools/syscalls.tab` by
  `gensys.py`. It holds the constants of horizon.inc, the `SYS_*` numbers and the `hz_*`
  prototypes. Include `horizon.h`, not this header. See [syscalls.md](syscalls.md).
- `hui.h` (and the generated `huigen.h`): Horizon's controls library: windows with
  buttons, fields, lists, scroll bars, menus, dialogs, alerts. See [apps.md](apps.md).
- `hgame.h`: hgame, the game library: screens, the blitter, images, sprites, maps, input,
  sound, music, fixed point. See [games.md](games.md).
- `conio.h`, `joystick.h`: cc65's console and joystick interfaces, implemented on hgame.
  See [games.md](games.md#from-cc65-conio-joystick), "From cc65".
- `dirent.h`: `opendir`, `readdir`, `rewinddir`, `closedir` ([below](#direnth)).

### horizon.h helpers

The functions of `horizon.h` that are not syscalls (their code is in `sdk/c/lib`):

- `unsigned hz_syscall(unsigned n, unsigned a, unsigned x, unsigned y)`: any syscall by
  number (one of a newer kernel, for example). A, X and Y in, A out. Sets `hz_errno`,
  `hz_x` and `hz_y`.
- `const char *hz_strerror(unsigned code)`: a Horizon error code in words.
- `int hz_errno_to_errno(unsigned code)`: the `errno.h` value for a Horizon error code
  (the C library calls it before it sets `errno`).
- `hz_ms()`: milliseconds since reset, as an `unsigned long` (a macro for `hz_uptime()`).
- `int hz_spawn_path(const char *path, const char *args, unsigned prio)`: start a program
  with an argument string (0: none) at a priority (0-3, `| SP_DETACH`).
- `int hz_stat_path(const char *path, hz_fileinfo *st)`: `stat` of a path. Returns 0 with
  `*st` filled, or -1.
- `int hz_prog_dir(char *buf, unsigned size)`: (Horizon 0.28) the folder of the program's
  own file, ending in `/`. Returns -1 before 0.28 (`HZ_ENOSYS`). 128 bytes always suffice.
- `void __far *hz_far_alloc(void)`, `hz_far_free(p)`: allocate a bank of 64 KB (offset 0),
  NULL when none is free, and release it.
- `hz_far_copy(dst, src, n)`, `hz_far_set(dst, c, n)`: copy or fill up to 65,535 bytes
  between any banks (MVN, about 12 cycles a byte).
- `hz_farptr(bank, off)`, `HZ_FARPTR(bank, off)`: a far pointer to bank:offset.
- `HZ_OFF(p)`, `HZ_BANK(p)`: a pointer's offset and bank.
- `HZ_U24(field, p)`, `HZ_U24B(field, bank, off)`: fill a parameter block's 3-byte
  pointer from a C pointer, or from a bank and an offset.
- `HZ_STATIC_ASSERT(cond, name)`: a compile-time check (`horizon.h` checks every block's
  size with it).
- `unsigned hz_stack_free(void)`: bytes free on the hardware stack below S.
- `unsigned hz_sstack_free(void)`: bytes free on the software stack.
- `int hz_stack_check(void)`: 0 when both stacks' guard zones are intact, -1 when one
  overflowed.
- `hz_heap_free()`, `hz_heap_largest()`, `hz_heap_peak()`: the heap's free bytes, the
  biggest block `malloc` can return now, and the most in use at once. With far data the
  first and the last are `unsigned long`.
- `int hz_getline(char *buf, unsigned size)`: a line from the keyboard with editing.
  Returns -1 on ctrl-C, -2 on ctrl-D at the start of the line.
- `unsigned hz_key_ascii(unsigned usage, unsigned mods)`: a key event as ASCII (US layout,
  `KEY_*` for the arrows), 0 for none.

`hz_errno`, `hz_x` and `hz_y` are variables: the error code and the X and Y registers of
the last call. The stacks and the heap: [reference.md](reference.md#heap-and-stacks),
"Heap and stacks".

### dirent.h

`DIR *opendir(path)`, `struct dirent *readdir(d)`, `rewinddir(d)`, `closedir(d)`. An entry
has `d_name` (up to 127 characters), `d_size` and `d_attr` (`HZ_ATTR_DIR`,
`HZ_ATTR_RDONLY`). Entries come without `.` and `..`, in the card's order. Reading a
folder uses no file handle, so a folder can be read while four files are open.

## Standard headers

Each header behaves as the C standard specifies, except where the notes say otherwise.

- `assert.h`: `assert`. A failed assertion prints the expression, the file and the line
  on stderr, then calls `abort()` (exit code 3). `NDEBUG` turns it off.
- `ctype.h`: `isalnum`, `isalpha`, `isblank`, `iscntrl`, `isdigit`, `isgraph`, `islower`,
  `isprint`, `ispunct`, `isspace`, `isupper`, `isxdigit`, `tolower`, `toupper`. ASCII only
  (the "C" locale).
- `errno.h`: `errno` and `EPERM` ... `EILSEQ` (POSIX's names). The C library sets it from
  Horizon's codes (reference.md, "errno, strerror, perror").
- `fcntl.h`: `open`, `creat`, `O_RDONLY` ... `O_APPEND` (`O_BINARY` and `O_TEXT` are 0).
  POSIX descriptors over Horizon's file calls, with unbuffered writes. The whole system
  has 4 handles, shared with `fopen`.
- `float.h`: `FLT_*`, `DBL_*`, `LDBL_*`. All three types are IEEE single precision:
  `DBL_DIG` is 6.
- `inttypes.h`: `PRId8` ... `SCNx64`, `imaxabs`, `imaxdiv`, `strtoimax`, `strtoumax`.
  `intmax_t` is `long long`, and the four functions are `llabs`, `lldiv`, `strtoll` and
  `strtoull`.
- `iso646.h`: `and`, `or`, `not`, `bitand`, ...
- `limits.h`: `CHAR_BIT`, `INT_MAX` (32767), `LONG_MAX`, `LLONG_MAX`, ... `int` is 16 bits.
  `CHAR_MIN` is 0 unless `-fsigned-char` is given.
- `math.h`: `acos`, `asin`, `atan`, `atan2`, `cbrt`, `ceil`, `copysign`, `cos`, `cosh`,
  `exp`, `exp2`, `expm1`, `fabs`, `fdim`, `floor`, `fma`, `fmax`, `fmin`, `fmod`, `frexp`,
  `hypot`, `ilogb`, `ldexp`, `log`, `log10`, `log1p`, `log2`, `logb`, `lrint`, `lround`,
  `modf`, `nearbyint`, `nextafter`, `pow`, `remainder`, `rint`, `round`, `scalbn`, `sin`,
  `sinh`, `sqrt`, `tan`, `tanh`, `trunc`; `fpclassify`, `signbit`, `isnan`, `isinf`,
  `isfinite`, `isnormal`; the `f` and `l` forms as macros. Accuracy and sizes:
  reference.md, "Floating point". `errno` is not set: a domain error gives NaN. `-lm` is
  accepted and not needed.
- `setjmp.h`: `setjmp`, `longjmp`, `sigsetjmp`, `siglongjmp`, `_setjmp`, `_longjmp`. See
  reference.md, "setjmp and longjmp".
- `signal.h`: `signal`, `raise`, `SIG*`. Horizon has no signals: both fail (`SIG_ERR`,
  -1).
- `stdarg.h`: `va_list`, `va_start`, `va_arg`, `va_end`, `va_copy`. `va_list` is a far
  pointer into the stack.
- `stdbool.h`: `bool`, `true`, `false`.
- `stddef.h`: `size_t`, `ptrdiff_t`, `wchar_t` (all 16 bits), `NULL`, `offsetof`. One
  object is at most 65,535 bytes.
- `stdint.h`: `int8_t` ... `uint64_t`, `intptr_t`, `intmax_t`, the `_MIN`, `_MAX` and `_C`
  macros. `intptr_t` is 16 bits, 32 with far data.
- `stdio.h`: `fopen`, `freopen`, `fclose`, `fflush`, `setbuf`, `setvbuf`, `remove`,
  `rename`, `tmpfile`, `tmpnam`, `fgetc`, `getc`, `getchar`, `fgets`, `ungetc`, `fputc`,
  `putc`, `putchar`, `fputs`, `puts`, `fread`, `fwrite`, `fseek`, `ftell`, `rewind`,
  `fgetpos`, `fsetpos`, `feof`, `ferror`, `clearerr`, `perror`, `printf`, `fprintf`,
  `sprintf`, `snprintf`, `vprintf`, `vfprintf`, `vsprintf`, `vsnprintf`, `scanf`, `fscanf`,
  `sscanf`, `vscanf`, `vfscanf`, `vsscanf`. stdout and stderr are the console, stdin the
  keyboard. `FOPEN_MAX` is 4 (Horizon's handles). `tmpfile` and `tmpnam` return NULL.
  `freopen` takes files only. `setbuf(f, NULL)` is `setvbuf(f, NULL, _IONBF, 0)`. The
  formats: reference.md, "printf family", "scanf family".
- `stdlib.h`: `malloc`, `calloc`, `realloc`, `free`, `exit`, `_Exit`, `abort`, `atexit`,
  `abs`, `labs`, `llabs`, `div`, `ldiv`, `lldiv`, `atoi`, `atol`, `atoll`, `atof`,
  `strtol`, `strtoul`, `strtoll`, `strtoull`, `strtod`, `strtof`, `strtold`, `rand`,
  `srand`, `qsort`, `bsearch`, `getenv`, `system`. `RAND_MAX` is 32767 (`rand` is the
  classic linear congruential generator). `abort` ends with exit code 3. `getenv` returns
  NULL and `system` fails.
- `string.h`: `memcpy`, `memmove`, `memset`, `memcmp`, `memchr`, `strlen`, `strcpy`,
  `strncpy`, `strcat`, `strncat`, `strcmp`, `strncmp`, `strcoll`, `strxfrm`, `strchr`,
  `strrchr`, `strstr`, `strspn`, `strcspn`, `strpbrk`, `strtok`, `strerror`, `strdup`,
  `strnlen`, `strcasecmp`, `strncasecmp`. `memcpy`, `memmove`, `memset`, `strlen`,
  `strcpy` and `memcmp` are assembly (`rt/mem.s`, MVN). `strcoll` is `strcmp` and
  `strxfrm` a copy (no locales).
- `strings.h`: `strcasecmp`, `strncasecmp`, the same as `string.h`'s.
- `time.h`: `time`, `clock`, `difftime`, `mktime`, `gmtime`, `localtime`, `asctime`,
  `ctime`, `strftime`. `time_t` counts seconds since 1970 from Horizon's clock. There are
  no time zones (`localtime` is `gmtime`). `CLOCKS_PER_SEC` is 50. `difftime` returns a
  `long`, not a `double`, so that it needs no float code.
- `uchar.h`: `char16_t`, `char32_t`, the types of `u"..."` and `U"..."`. No conversion
  functions.
- `unistd.h`: `read`, `write`, `lseek`, `close`, `unlink`, `isatty`. Descriptors 0-2 are
  the console. One `read` or `write` moves at most 32,767 bytes (`ssize_t` is a 16-bit
  `int`).
- `wchar.h`: `wcslen`, `wcscpy`, `wcsncpy`, `wcscat`, `wcscmp`, `wcsncmp`, `wcschr`,
  `wcsrchr`, `wmemcpy`, `wmemmove`, `wmemset`, `wmemcmp`, `wmemchr`. `wchar_t` is 16
  bits. No locales, no wide input or output.

Not supported: `complex.h`, `fenv.h`, `locale.h`, `threads.h`, `stdatomic.h`, `wctype.h`,
and the functions reference.md lists as not supported. Including one of these headers is
an error (no such file).
