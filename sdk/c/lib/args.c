/* args.c - argc and argv for main() (rt/crt0.s calls __hz_mkargs before main).
 *
 * Horizon gives a program one argument string (the rest of the shell's command line, or
 * spawn's argument), zero-terminated at the top of the window. It is split here in place
 * into words at spaces; a double quote starts or ends a quoted part, in which spaces are
 * kept ("two words" is one argument, the quotes removed; a"b c"d is "ab cd"). argv[0] is
 * the task's name as the menu bar shows it (the program file's name, "Greet"), since
 * Horizon does not pass the path. At most HZ_MAXARGS arguments; argv[argc] is NULL.
 */
#include <horizon.h>

#define HZ_MAXARGS 32

int __hz_argc;
char **__hz_argv;
extern unsigned __hz_argoff, __hz_arglen;

static char *argv_[HZ_MAXARGS + 2];
static char name_[17];

int __hz_mkargs(void)
{
    char *p, *q;
    int argc = 0;
    unsigned i;

    if (hz_task_name_get(0, name_) != 0)
        name_[0] = 0;
    name_[16] = 0;
    argv_[argc++] = name_;
    /* the argument string: window offset __hz_argoff, bank 0 (in the tiny model the
     * window is the data bank, so a near pointer reaches it) */
    p = (char *)HZ_FARPTR(0, __hz_argoff);
    for (;;) {
        while (*p == ' ')
            ++p;
        if (!*p || argc > HZ_MAXARGS)
            break;
        argv_[argc++] = q = p;
        i = 0;                          /* inside quotes */
        while (*p && (i || *p != ' ')) {
            if (*p == '"')
                i ^= 1;
            else
                *q++ = *p;
            ++p;
        }
        if (*p)
            ++p;
        *q = 0;
    }
    argv_[argc] = 0;
    __hz_argv = argv_;
    __hz_argc = argc;
    return argc;
}
