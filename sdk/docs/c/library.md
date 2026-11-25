# The C library, header by header

Every header a C program for Horizon can include, and every function in it. This page is
the index; the behaviour on Horizon (files, the console, the heap, time, errors) is in
[reference.md](reference.md), "The C library on Horizon", and the sections it names.
Floating point and `math.h`: reference.md, "Floating point". The syscalls (`hz_*` of
`hzsys.h`): [syscalls.md](syscalls.md).

Where they are: the C library's headers in `sdk/c/cc816/include`, the SDK's own in
`sdk/c/include`. hcc puts both on the include path. The code is `sdk/c/lib` (C) and
`sdk/c/rt` (assembly: the startup, the arithmetic, the memory and string routines, soft
float, `setjmp`), built split, one function a module, so a program links only what it
calls.

## The SDK's headers

| Header | What | Chapter |
| --- | --- | --- |
| `horizon.h` | every syscall as a C function (it includes `hzsys.h`, generated), the parameter blocks, the error codes, the helpers below | [syscalls.md](syscalls.md), [reference.md](reference.md) "Syscalls from C" |
| `hzsys.h` | generated from horizon.inc, ABI.md and `sdk/c/tools/syscalls.tab` by `gensys.py`: the constants of horizon.inc, the `SYS_*` numbers, the `hz_*` prototypes. Include `horizon.h`, not this | [syscalls.md](syscalls.md) |
| `hui.h` (and the generated `huigen.h`) | Horizon's controls library: windows with buttons, fields, lists, scroll bars, menus, dialogs, alerts | [apps.md](apps.md) |
| `hgame.h` | hgame, the game library: screens, the blitter, images, sprites, maps, input, sound, music, fixed point | [games.md](games.md) |
| `conio.h`, `joystick.h` | cc65's console and joystick interfaces, on hgame | [games.md](games.md), "From cc65" |
| `dirent.h` | `opendir`, `readdir`, `rewinddir`, `closedir` (below) | here |

### horizon.h: the helpers

The functions of `horizon.h` that are not syscalls (they are in `sdk/c/lib`):

| Function or macro | What |
| --- | --- |
| `unsigned hz_syscall(unsigned n, unsigned a, unsigned x, unsigned y)` | any syscall by number (a newer kernel's): A, X, Y in, A out; sets `hz_errno`, `hz_x`, `hz_y` |
| `const char *hz_strerror(unsigned code)` | a Horizon error code in words |
| `int hz_errno_to_errno(unsigned code)` | the `errno.h` value for a Horizon error code (what the C library does before it sets `errno`) |
| `hz_ms()` | milliseconds since reset, as an `unsigned long` (a macro for `hz_uptime()`) |
| `int hz_spawn_path(const char *path, const char *args, unsigned prio)` | start a program with an argument string (0: none) at a priority (0-3, `| SP_DETACH`) |
| `int hz_stat_path(const char *path, hz_fileinfo *st)` | `stat` of a path: 0 and `*st` filled, or -1 |
| `int hz_prog_dir(char *buf, unsigned size)` | (Horizon 0.28) the folder of the program's own file, ending in `/`; -1 before 0.28 (`HZ_ENOSYS`). 128 bytes always fit |
| `void __far *hz_far_alloc(void)`, `hz_far_free(p)` | a bank of 64 KB (offset 0), NULL when none is free; give it back |
| `hz_far_copy(dst, src, n)`, `hz_far_set(dst, c, n)` | copy or fill up to 65,535 bytes between any banks (MVN, about 12 cycles a byte) |
| `hz_farptr(bank, off)`, `HZ_FARPTR(bank, off)` | a far pointer to bank:offset |
| `HZ_OFF(p)`, `HZ_BANK(p)` | a pointer's offset and bank |
| `HZ_U24(field, p)`, `HZ_U24B(field, bank, off)` | fill a parameter block's 3-byte pointer from a C pointer, or from a bank and an offset |
| `HZ_STATIC_ASSERT(cond, name)` | a compile-time check (`horizon.h` checks every block's size with it) |
| `unsigned hz_stack_free(void)` | bytes free on the hardware stack below S now |
| `unsigned hz_sstack_free(void)` | bytes free on the software stack now |
| `int hz_stack_check(void)` | 0 when both stacks' guard zones are intact, -1 when one overflowed |
| `hz_heap_free()`, `hz_heap_largest()`, `hz_heap_peak()` | the heap's free bytes, the biggest block `malloc` can give now, the most in use at once (with far data the first and the last are `unsigned long`) |
| `int hz_getline(char *buf, unsigned size)` | a line from the keyboard with editing; -1 on ctrl-C, -2 on ctrl-D at the start of the line |
| `unsigned hz_key_ascii(unsigned usage, unsigned mods)` | a key event as ASCII (US layout; `KEY_*` for the arrows), 0 for none |

`hz_errno`, `hz_x` and `hz_y` are variables (the error code and the X and Y registers of
the last call). The stacks and the heap: reference.md, "The heap and the stacks".

### dirent.h

`DIR *opendir(path)`, `struct dirent *readdir(d)`, `rewinddir(d)`, `closedir(d)`. An entry
has `d_name` (up to 127 characters), `d_size` and `d_attr` (`HZ_ATTR_DIR`,
`HZ_ATTR_RDONLY`). Entries come without `.` and `..`, in the card's order. No file handle
is used, so a folder can be read while four files are open.

## The C library's headers

"Yes" means as C says; the notes say where Horizon differs.

| Header | Functions and macros | Notes |
| --- | --- | --- |
| `assert.h` | `assert` | a failed one prints the expression, the file and the line on stderr, then `abort()` (exit code 3); `NDEBUG` turns it off |
| `ctype.h` | `isalnum`, `isalpha`, `isblank`, `iscntrl`, `isdigit`, `isgraph`, `islower`, `isprint`, `ispunct`, `isspace`, `isupper`, `isxdigit`, `tolower`, `toupper` | ASCII only (the "C" locale) |
| `errno.h` | `errno` and `EPERM` ... `EILSEQ` (POSIX's names) | the C library sets it from Horizon's codes (reference.md: "errno, strerror, perror") |
| `fcntl.h` | `open`, `creat`, `O_RDONLY` ... `O_APPEND` (`O_BINARY`, `O_TEXT` are 0) | POSIX descriptors over Horizon's file calls; unbuffered writes; 4 handles in the whole system, shared with `fopen` |
| `float.h` | `FLT_*`, `DBL_*`, `LDBL_*` | all three are IEEE single precision: `DBL_DIG` is 6 |
| `inttypes.h` | `PRId8` ... `SCNx64`, `imaxabs`, `imaxdiv`, `strtoimax`, `strtoumax` | `intmax_t` is `long long`; the four functions are `llabs`, `lldiv`, `strtoll`, `strtoull` |
| `iso646.h` | `and`, `or`, `not`, `bitand`, ... | yes |
| `limits.h` | `CHAR_BIT`, `INT_MAX` (32767), `LONG_MAX`, `LLONG_MAX`, ... | `int` is 16 bits; `CHAR_MIN` is 0 unless `-fsigned-char` |
| `math.h` | `acos`, `asin`, `atan`, `atan2`, `cbrt`, `ceil`, `copysign`, `cos`, `cosh`, `exp`, `exp2`, `expm1`, `fabs`, `fdim`, `floor`, `fma`, `fmax`, `fmin`, `fmod`, `frexp`, `hypot`, `ilogb`, `ldexp`, `log`, `log10`, `log1p`, `log2`, `logb`, `lrint`, `lround`, `modf`, `nearbyint`, `nextafter`, `pow`, `remainder`, `rint`, `round`, `scalbn`, `sin`, `sinh`, `sqrt`, `tan`, `tanh`, `trunc`; `fpclassify`, `signbit`, `isnan`, `isinf`, `isfinite`, `isnormal`; the `f` and `l` forms as macros | accuracy and sizes: reference.md, "Floating point". No `errno`: a domain error gives NaN. `-lm` is accepted and not needed |
| `setjmp.h` | `setjmp`, `longjmp`, `sigsetjmp`, `siglongjmp`, `_setjmp`, `_longjmp` | reference.md, "setjmp and longjmp" |
| `signal.h` | `signal`, `raise`, `SIG*` | Horizon has no signals: both fail (`SIG_ERR`, -1) |
| `stdarg.h` | `va_list`, `va_start`, `va_arg`, `va_end`, `va_copy` | `va_list` is a far pointer into the stack |
| `stdbool.h` | `bool`, `true`, `false` | yes |
| `stddef.h` | `size_t`, `ptrdiff_t`, `wchar_t` (all 16 bits), `NULL`, `offsetof` | one object is at most 65,535 bytes |
| `stdint.h` | `int8_t` ... `uint64_t`, `intptr_t`, `intmax_t`, the `_MIN`, `_MAX` and `_C` macros | `intptr_t` is 16 bits, 32 with far data |
| `stdio.h` | `fopen`, `freopen`, `fclose`, `fflush`, `setbuf`, `setvbuf`, `remove`, `rename`, `tmpfile`, `tmpnam`, `fgetc`, `getc`, `getchar`, `fgets`, `ungetc`, `fputc`, `putc`, `putchar`, `fputs`, `puts`, `fread`, `fwrite`, `fseek`, `ftell`, `rewind`, `fgetpos`, `fsetpos`, `feof`, `ferror`, `clearerr`, `perror`, `printf`, `fprintf`, `sprintf`, `snprintf`, `vprintf`, `vfprintf`, `vsprintf`, `vsnprintf`, `scanf`, `fscanf`, `sscanf`, `vscanf`, `vfscanf`, `vsscanf` | stdout and stderr are the console, stdin the keyboard; `FOPEN_MAX` is 4 (Horizon's handles); `tmpfile` and `tmpnam` return NULL; `freopen` takes files only; `setbuf(f, NULL)` is `setvbuf(f, NULL, _IONBF, 0)`. The formats: reference.md, "printf family", "scanf family" |
| `stdlib.h` | `malloc`, `calloc`, `realloc`, `free`, `exit`, `_Exit`, `abort`, `atexit`, `abs`, `labs`, `llabs`, `div`, `ldiv`, `lldiv`, `atoi`, `atol`, `atoll`, `atof`, `strtol`, `strtoul`, `strtoll`, `strtoull`, `strtod`, `strtof`, `strtold`, `rand`, `srand`, `qsort`, `bsearch`, `getenv`, `system` | `RAND_MAX` is 32767 (`rand` is the classic linear congruential generator); `abort` ends with exit code 3; `getenv` returns NULL and `system` fails |
| `string.h` | `memcpy`, `memmove`, `memset`, `memcmp`, `memchr`, `strlen`, `strcpy`, `strncpy`, `strcat`, `strncat`, `strcmp`, `strncmp`, `strcoll`, `strxfrm`, `strchr`, `strrchr`, `strstr`, `strspn`, `strcspn`, `strpbrk`, `strtok`, `strerror`, `strdup`, `strnlen`, `strcasecmp`, `strncasecmp` | `memcpy`, `memmove`, `memset`, `strlen`, `strcpy`, `memcmp` are assembly (`rt/mem.s`, MVN); `strcoll` is `strcmp` and `strxfrm` a copy (no locales) |
| `strings.h` | `strcasecmp`, `strncasecmp` | the same as `string.h`'s |
| `time.h` | `time`, `clock`, `difftime`, `mktime`, `gmtime`, `localtime`, `asctime`, `ctime`, `strftime` | `time_t` counts seconds since 1970 from Horizon's clock, no time zones (`localtime` is `gmtime`); `CLOCKS_PER_SEC` is 50; **`difftime` returns a `long`**, not a `double` (no float code for it) |
| `uchar.h` | `char16_t`, `char32_t` | the types of `u"..."` and `U"..."`; no conversion functions |
| `unistd.h` | `read`, `write`, `lseek`, `close`, `unlink`, `isatty` | descriptors 0-2 are the console; one `read` or `write` moves at most 32,767 bytes (`ssize_t` is a 16-bit `int`) |
| `wchar.h` | `wcslen`, `wcscpy`, `wcsncpy`, `wcscat`, `wcscmp`, `wcsncmp`, `wcschr`, `wcsrchr`, `wmemcpy`, `wmemmove`, `wmemset`, `wmemcmp`, `wmemchr` | `wchar_t` is 16 bits; no locales, no wide input or output |

Not there: `complex.h`, `fenv.h`, `locale.h`, `threads.h`, `stdatomic.h`, `wctype.h`, and
the functions reference.md lists as not supported. A program that needs one of them gets
an error at `#include` (no such file), not a silent stub.

## How it is tested

`sdk/c/tests/libc` (86 checks: formats, strings, sorting, the heap, files, folders, time,
far memory, errno, argv, the keyboard, `atexit`) runs in both code models and with far
data; `tests/rt` checks the assembly routines against tables made on the PC; `tests/fpu`
checks floating point and `math.h` bit for bit. All of them are in `make -C sdk/c test`
([testing.md](../testing.md)).
