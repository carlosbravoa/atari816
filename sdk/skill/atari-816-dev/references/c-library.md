# The C library on Horizon, and Horizon's calls from C

Read this when a C program uses the standard library (stdio, files, folders, time, math,
POSIX descriptors) or calls Horizon directly (`horizon.h`: `hz_*`). The language itself
(types, far data, stacks, warnings, hcc): references/c-language.md. Full text:
`sdk/docs/c/reference.md` ("The C library on Horizon", "Syscalls from C", "The heap and
the stacks"); headers `sdk/c/include/horizon.h`, `hzsys.h` (every syscall with a comment),
`sdk/c/cc816/include/*.h`.

## I want X -> call Y

All names checked against the headers; the marked ones run in the emulator.

| I want | Call |
| --- | --- |
| print text | `printf`, `puts`, `fputs(s, stderr)`; raw and unbuffered: `hz_puts(s)`, `hz_putc(c)` |
| read a line typed | `fgets(buf, n, stdin)` (tested); `hz_getline(buf, size)` (-1 ctrl-C, -2 ctrl-D) |
| read single keys | `u = hz_input_read(); c = hz_key_ascii(u, hz_x);` (tested, below) |
| poll keys without waiting | `hz_input_poll()`, then test `hz_errno` (`HZ_EAGAIN`: nothing queued) |
| read the joysticks | `hz_joystick()` (`JOY_*` bits, `hz_x` triggers) or `joystick.h`'s `joy_read(JOY_1)` |
| write/read a file | `fopen`/`fprintf`/`fgets`/`fread`/`fwrite`/`fclose` (tested) |
| a file's size | `fseek(f, 0, SEEK_END); ftell(f)` or `hz_stat_path(path, &info)` -> `info.size` (tested) |
| list a folder | `opendir`/`readdir`/`closedir` (`dirent.h`, tested) |
| make, delete, rename | `hz_mkdir(path)`; `remove(path)`; `rename(from, to)` (also across folders) (tested) |
| current folder | `hz_getcwd(buf, size)`, `hz_chdir(path)` (tested) |
| files next to my program | `hz_prog_dir(buf, 128)` -> `/APPS/` (tested); whole path: `hz_task_path(buf, 128)` |
| milliseconds | `hz_uptime()` (a `long`; `hz_ms()` is the same) (tested) |
| wait | `hz_sleep(ms)` (10 ms steps) (tested); next frame: `hz_vsync()`; give up the CPU: `hz_yield()` |
| date and time | `time(NULL)`, `gmtime`/`localtime`, `strftime` (tested); raw: `hz_time_get()` (seconds since 2000) |
| more memory | `hz_far_alloc()` (a 64 KB bank, `__far` pointer; c-language.md, "Far data"); raw: `hz_bank_alloc()` |
| how much memory | `hz_mem_info()` free banks, `hz_x` total (tested: 82 of 92); `hz_heap_free()`, `hz_heap_largest()` |
| run another program | `t = hz_spawn_path("/APPS/X.PRG", "args", 1); code = hz_wait(t);` (tested) |
| one instance only | `hz_task_single()` (-1 with `hz_errno == HZ_ERUNNING`: exit) |
| Horizon's version | `hz_sys_info()` (0x001D for 0.29, 0x001E for 0.30, 0x001F for 0.31; `hz_x` = hardware REV, 0x0C) (tested) |
| console size | `hz_con_size()` columns, `hz_x` rows (tested: 78 x 29) |
| my task id | `hz_getpid()` (tested) |
| a beep / chime | `hz_beep(pitch, ticks, volume)`; `hz_sound_chime(CH_INFO, 0xFFFF)` |
| a window | the controls library, `hui.h` (references/hui.md); raw: `hz_ws_start`, `hz_win_open`, `hz_win_draw`, `hz_win_event`, `hz_win_close`, `hz_ws_stop` |
| a game screen, sprites, sound | `hgame.h` (references/hgame.md); raw: `hz_fs_enter`, `hz_spr_*`, `hz_draw_list`, `hz_sample_play`, `hz_opl_write` |
| a syscall without a wrapper | `hz_syscall(SYS_NAME, a, x, y)` (tested with `SYS_GETPID`) |
| an error in words | `strerror(errno)` / `perror("x")` for the C library; `hz_strerror(hz_errno)` for `hz_` calls |
| check what the machine has | `hcc --needs opl2,mem=1024K` (references/packaging.md) |

## What the C library has

The library is built split (one function a module): only what a program uses is linked.
Float and `long long` printing and scanning are linked only when the program uses them.

| Header | What works |
| --- | --- |
| `stdio.h` | `printf` family (`%d %i %u %x %X %o %c %s %p %n %%`, `hh h l z t j`, `%f %F %e %E %g %G %a %A`, `%lld %llu %llx`, widths, `*`); `scanf` family incl. `%f`, `%lld`, `%[...]`; `fopen freopen fclose fflush setvbuf setbuf fread fwrite fgets fputs fgetc fputc getc putc getchar putchar puts ungetc fseek ftell rewind fgetpos fsetpos feof ferror clearerr perror remove rename` |
| `stdlib.h` | `malloc calloc realloc free`, `exit atexit _Exit abort`, `abs labs llabs div ldiv lldiv`, `atoi atol atoll atof strtol strtoul strtoll strtoull strtod strtof strtold`, `rand srand` (RAND_MAX 32767), `qsort bsearch` |
| `string.h` | `mem*`, `str*` incl. `strdup strnlen strtok strerror strcasecmp strncasecmp` (also `strings.h`) |
| `ctype.h` | all `is*`, `tolower`, `toupper` (take `int`; safe with unsigned `char`) |
| `math.h` | `sqrt fabs floor ceil trunc round rint lround fmod modf frexp ldexp copysign fmin fmax`, `sin cos tan asin acos atan atan2 exp exp2 log log10 log2 log1p expm1 pow cbrt hypot sinh cosh tanh`, `fpclassify isnan isinf isfinite` ...; `f`/`l` forms are macros. No errno; NaN / `HUGE_VAL` on errors |
| `time.h` | `time clock difftime mktime gmtime localtime asctime ctime strftime`; `CLOCKS_PER_SEC` 50; `difftime` returns `long`; no time zones |
| `setjmp.h` | `setjmp longjmp` (tested from 50 calls deep) |
| `fcntl.h`, `unistd.h` | `open creat read write lseek close unlink isatty` (POSIX descriptors, below) |
| `dirent.h` | `opendir readdir rewinddir closedir` |
| `errno.h`, `assert.h`, `stdint.h`, `inttypes.h`, `limits.h`, `float.h`, `stdbool.h`, `stddef.h`, `stdarg.h`, `wchar.h` (string functions only), `iso646.h` | yes |

`assert` failing prints the expression, file and line on stderr and exits with code 3.

## Not there

| | What happens | Instead |
| --- | --- | --- |
| `system()` | returns -1 (tested) | `hz_spawn_path` + `hz_wait` |
| `getenv()` | NULL (tested) | arguments (`argv`), a settings file next to the program |
| `signal()`, `raise()` | `SIG_ERR` (tested) | `atexit` for clean-up |
| `tmpfile`, `tmpnam` | NULL | a named file, `remove` it after |
| `freopen` of stdin/stdout/stderr | fails | `fopen` a file |
| locales, wide I/O, time zones, `fenv.h`, `lgamma tgamma erf`, `nan()` | absent | |
| `<conio.h>` of cc65 | *is* there, but different: below | |

## Console, stdin, arguments

- stdout and stderr go to the console (the screen in the shell, a terminal window, or
  the log `console.txt` under the Desktop). Line-buffered: a line goes out at `\n`, before
  stdin is read, and at exit. A prompt without `\n` is shown when you read.
- stdin is the keyboard: a line with echo and editing (Backspace, Left, Right). Ctrl-D or
  ctrl-C on an empty line is end of input (EOF). Keep `getchar()`'s result in an `int`.
- `main(int argc, char **argv)`: the argument string split at spaces, `"quoted words"`
  whole, at most 32. `argv[0]` is the name the menu bar shows ("Misc"), not a path. The
  return value is the exit code.
- `exit()` runs `atexit` functions, flushes and closes every FILE. `hz_exit(code)` ends at
  once without flushing.

Single keys (tested with an input script typing `Ann\n`, then `ab`, then `q`):

```c
#include <stdio.h>
#include <horizon.h>
int main(void)
{
    unsigned u, c;
    char line[40];
    printf("name? ");
    fgets(line, sizeof line, stdin);
    printf("got %s", line);
    for (;;) {
        u = hz_input_read();               /* waits for a key or mouse event */
        if (hz_errno) return 1;            /* the keyboard is not ours */
        if (u >= 0x100) continue;          /* mouse, wheel */
        c = hz_key_ascii(u, hz_x);         /* 0 for a release or a modifier */
        if (c == 'q') break;
        if (c) printf("key %u\n", c);      /* KEY_LEFT ... for arrows */
    }
    return 0;
}
```

In a window program keys come as `WE_KEY` events instead (references/hui.md).

## Files and paths

- **4 file handles for the whole system** (all programs together, `FOPEN_MAX` 4). The 5th
  `fopen` returns NULL with `errno == ENFILE` ("Too many open files in the system",
  tested). Close files at once; never keep a log open for the program's life. POSIX
  descriptors and `hz_open` share the same 4.
- `fopen` modes `r w a r+ w+ a+` (`b` ignored: no line-end conversion; `x`: fail if it
  exists). Bad mode: `EINVAL`. Missing file or folder: `ENOENT`.
- Each `fopen` takes a 1 KB buffer from the heap (tested: free heap drops by 1,028);
  128 bytes when 1 KB is not free, 2 bytes when not even that (slow but works).
  `setvbuf(f, NULL, _IONBF, 0)` gives the buffer back.
- `fseek`/`ftell` with 32-bit positions; `SEEK_END` from the size at open plus writes.
- Paths (tested): FAT32 with **long names** (tested: `LONGFILENAME_TEST.TXT`, `Mixed Case
  Name.txt` with spaces), **case-insensitive** (opened as `MIXED CASE NAME.TXT`, tested),
  `/` as separator, no drive letters, no `\`. Relative paths and `..` work from the
  current folder (tested). `FILENAME_MAX` is 128.
- **The current folder** is whatever started the program: the shell's folder; `/` from a
  desktop shortcut or a `/SYSTEM/PROGRAMS` entry; the folder Files shows; an app's own
  folder from the Programs menu's app list. Do not rely on it: always use `hz_prog_dir`
  for files next to the program:

```c
char path[128];                    /* tested: /APPS/LEVELS.DAT found */
FILE *f;
if (hz_prog_dir(path, sizeof path) < 0)
    strcpy(path, "");               /* Horizon before 0.28: the current folder */
strcat(path, "LEVELS.DAT");
f = fopen(path, "rb");
```

- Folders (`dirent.h`): `d_name` (up to 127 characters), `d_size`, `d_attr`
  (`HZ_ATTR_DIR`, `HZ_ATTR_RDONLY`); no `.`/`..`; uses no file handle; `opendir` of a
  missing folder returns NULL. Tested:

```c
DIR *d = opendir("/SUB");
struct dirent *e;
while ((e = readdir(d)) != NULL)
    printf("entry %s %lu%s\n", e->d_name, e->d_size, e->d_attr & HZ_ATTR_DIR ? " <dir>" : "");
closedir(d);
```

**POSIX descriptors** (`fcntl.h`, `unistd.h`), for Unix/DOS code: `O_RDONLY O_WRONLY
O_RDWR O_CREAT O_TRUNC O_EXCL O_APPEND` (`O_BINARY`, `O_TEXT` are 0). Descriptors 0-2 are
the console; files are 3 and up. No write buffer; a read-only descriptor reads ahead 512
bytes from the heap. One `read` or `write` moves at most 32,767 bytes (`ssize_t` is a
16-bit `int`): asked for more it returns 32,767 (a short count, not an error); loop until
done. Errors in `errno` (`ENOENT EEXIST EBADF ESPIPE ENFILE`). Tested:

```c
/* int fd, n; char line[16]; */
fd = open("/P.BIN", O_WRONLY | O_CREAT | O_TRUNC);
write(fd, "abcdef", 6);
close(fd);
fd = open("/P.BIN", O_RDONLY);
lseek(fd, 2, SEEK_SET);
n = read(fd, line, 10);         /* 4: "cdef" */
close(fd);
```

## Time

- `time(NULL)`: seconds since 1970 from Horizon's clock (set by the Desktop or the shell
  from /SYSTEM/CLOCK or the PC). Never set (the emulator): it counts from 2000-01-01
  (tested: `2000-01-01 00:00:03`).
- `clock()`: 50 ticks a second (20 ms). For timing use `hz_uptime()` (ms since reset, a
  `long`); it is the same at every emulator run.
- `hz_sleep(ms)`: 10 ms steps. Frame pacing: `hz_vsync()` (60 Hz) or hgame's frame calls.

## horizon.h: the rules

`#include <horizon.h>` gives every syscall as `hz_<name>` (generated `hzsys.h`: each has a
comment saying its arguments and result), the parameter blocks and helpers.

- **Results**: `int` functions return 0 / a value, or -1 on an error; `unsigned` ones
  $FFFF on an error; `long` ones (`hz_uptime`, `hz_seek`, `hz_stat`, `hz_time_get`)
  32 bits.
- **`hz_errno`** is set by every `hz_` call: 0 when it worked, else Horizon's code
  (`HZ_EINVAL` 1, `HZ_ENOMEM` 2, `HZ_ENOENT` 3, `HZ_EAGAIN` 6, `HZ_ENOSYS` 7,
  `HZ_ERUNNING` 8, `HZ_ENODEV` 9; card errors `HZ_EIO + n`: `HZ_ENOFILE` 68,
  `HZ_ENOPATH` 69, `HZ_EBADNAME`, `HZ_EDENIED`, `HZ_EEXIST`, `HZ_ENFILE`). Test it where
  -1/$FFFF is also a valid answer (`hz_input_poll`, `hz_win_popup`).
- **`errno`** (errno.h) is set by the C library only, with POSIX numbers (`ENOENT` 2,
  `ENFILE` 23 ...). Do not mix: `hz_open` sets `hz_errno`, `fopen` sets `errno`.
  `hz_errno_to_errno(code)` converts; `hz_strerror(code)` says a Horizon code in words
  (tested: `hz_open("/NO/SUCH/FILE", HZ_O_READ)` -> `hz_errno` 69, "no such folder").
- **`hz_x`, `hz_y`**: the X and Y registers after calls that return two values
  (`hz_con_size` rows, `hz_input_read`'s modifiers, `hz_mem_info` total, `hz_sys_info`
  REV, `hz_time_get`'s clock state in `hz_y`, `hz_task_single`'s id).
- **Constants** keep horizon.inc's names (`WD_FILL`, `WE_CLOSE`, `C_RED`, `SPR_EN`,
  `KEY_LEFT`, `SYS_GETPID`), except error codes and open modes, which get `HZ_`
  (`HZ_EINVAL`, `HZ_O_READ`, `HZ_O_RDWR`, `HZ_O_CREATE`, `HZ_O_APPEND`).
- **Blocks** (`hz_io`, `hz_winopen`, `hz_windraw`, `hz_event`, `hz_statblk`,
  `hz_fileinfo`, `hz_readdirblk`, `hz_renameblk`, `hz_spawnblk`, `hz_taskinfo`, `hz_msg`,
  `hz_clipblk`, `hz_rect`, `hz_mouse`, `hz_popup`, `hz_sample`, `hz_sprite`, `hz_sprmove`,
  `hz_fsenter`, `hz_fsscroll`, `hz_raster`, `hz_drawrec`, `hz_sheetnew`, `hz_sheetrec`,
  `hz_timermsg`) match ABI.md byte for byte; they may be globals or locals. A 3-byte
  pointer field (`hz_u24`) is filled with `HZ_U24(field, ptr)` (near or far pointer;
  `HZ_U24B(field, bank, off)` from numbers). Pointer arguments to `hz_` functions are
  plain C pointers: the stubs pass the bank.

```c
hz_io io;
int h = hz_open("/DATA.BIN", HZ_O_READ);       /* -> handle 0-3, or -1 */
if (h < 0) {
    printf("open: %s\n", hz_strerror(hz_errno));
    return 1;
}
io.handle = h;
HZ_U24(io.buf, buffer);                        /* the 3-byte pointer in the block */
io.len = sizeof(buffer);
n = hz_read(&io);                              /* bytes read; fewer = end of file */
hz_close(h);
```

(Tested, with `static unsigned char buffer[64];`: `hz_read` returned 8 for an 8-byte
file.) Prefer stdio for files: it buffers small reads and `exit` closes what you forgot.
`hz_open` also opens URLs (Horizon 0.22's PC link: handles 4-7; sdk/docs/reference).

## Syscalls by topic

Every one is in `hzsys.h` with its comment; `grep -n 'hz_NAME' SDK/c/include/hzsys.h`.

| Topic | Functions |
| --- | --- |
| task | `hz_exit hz_yield hz_sleep hz_getpid hz_uptime hz_vsync hz_frame hz_task_path hz_task_single hz_task_info hz_task_name hz_task_name_get hz_sys_info` |
| programs | `hz_spawn` (block) / `hz_spawn_path(path, args, prio)` (prio 0-3, `| SP_DETACH`), `hz_wait hz_kill` |
| console | `hz_putc hz_puts hz_con_size hz_getline hz_key_ascii` |
| keyboard, mouse, joystick | `hz_input_read hz_input_poll hz_input_claim hz_input_release hz_input_lend hz_joystick` |
| files | `hz_open hz_close hz_read hz_write hz_seek hz_stat` / `hz_stat_path`, `hz_readdir hz_delete hz_mkdir hz_rename hz_chdir hz_getcwd hz_sync` |
| memory | `hz_bank_alloc hz_bank_free hz_mem_info`; helpers `hz_far_alloc hz_far_free hz_far_copy hz_far_set hz_farptr` |
| clock | `hz_time_get hz_time_set` |
| messages | `hz_port_create hz_send hz_recv hz_port_close` (16-byte `hz_msg`), `hz_clip_put hz_clip_get` |
| sound | `hz_beep hz_sound_write hz_sound_chime hz_sample_play hz_sample_stop hz_sample_stat hz_sample_set hz_sample_timer hz_opl_write` |
| windows | `hz_ws_start hz_ws_stop hz_win_open hz_win_close hz_win_draw hz_win_event hz_win_timer hz_win_menu hz_win_title hz_win_move hz_win_geom hz_win_front hz_win_info hz_win_popup hz_win_mstate hz_ws_status hz_ws_term hz_ws_mouse hz_ws_pointer hz_ws_palette hz_ws_hold hz_ws_sync hz_win_twidth` ... |
| full screen and blitter | `hz_fs_enter hz_fs_leave hz_fs_scroll hz_fs_raster hz_pal_set hz_pal_alloc hz_draw_list hz_list_wait hz_win_vbl hz_sheet_new hz_sheet_draw hz_sheet_free` |
| sprites | `hz_spr_alloc hz_spr_free hz_spr_set hz_spr_move hz_spr_move_many hz_spr_show` |
| system | `hz_sysreq hz_restart hz_setting`; the classic Atari: `hz_classic_show hz_classic_mount hz_classic_boot ...` |

For windows and games use the libraries (references/hui.md, references/hgame.md); the raw
calls and their blocks are in references/abi-cheatsheet.md (assembly names: `SYS_WOPEN`
is `hz_win_open`).

**A syscall without a wrapper**: `hz_syscall(n, a, x, y)` returns A and sets `hz_errno`,
`hz_x`, `hz_y`; `SYS_*` numbers are in hzsys.h; a pointer is two arguments, `HZ_OFF(p)`
and `HZ_BANK(p)`. Tested: `hz_syscall(SYS_GETPID, 0, 0, 0)` equals `hz_getpid()`.

## Heap from C

`malloc` is first fit over the main bank between the bss and the software stack (about
46 KB in a small program, less as code and float/printf code grow: a program with float
printing, math and `long long` had 23 KB). It returns NULL (`errno` ENOMEM) when no block
is big enough: check every `malloc`. One block is at most 65,535 bytes; big buffers come
from `hz_far_alloc()`. `hz_heap_free()`, `hz_heap_largest()`, `hz_heap_peak()` and `hcc
--debug` show the use (references/c-language.md, "Stacks and heap").

## conio.h and joystick.h (cc65's APIs)

For C written against cc65. hcc links hgame by itself when either is included.

- `conio.h`: a text screen of character cells drawn by hgame, 40 x 25 cells of 8 x 10
  pixels in a window unless `conio_screen(cols, rows, full)` says otherwise before the
  first call (window up to 80 x 33; full screen 40 x 18 or 80 x 36). `clrscr gotoxy
  cputc cputs cputsxy cprintf cgetc kbhit textcolor bgcolor revers cursor chline cvline
  screensize waitvsync`. Output shows at the next `kbhit()`, `cgetc()` or `waitvsync()`.
  C64 colours (`COLOR_BLACK` .. `COLOR_GRAY3`); line characters drawn as `- | +`;
  `cgetc()` returns ASCII, `'\n'` for Enter, `CH_CURS_*` for arrows; closing the window
  ends the program. Details: `sdk/docs/c/games.md`, "From cc65".
- `joystick.h`: `joy_install(joy_static_stddrv)` (accepts anything), `joy_read(JOY_1)`,
  `JOY_UP(v)`, `JOY_FIRE(v)`, ... Do not include `horizon.h` after it (horizon.h's
  `JOY_UP` are plain bit values). The emulator's joysticks read 0.
- cc65's `<atari.h>`, `<peekpoke.h>` do not exist: programs never touch hardware
  (a POKE kills the task); use the syscalls.
