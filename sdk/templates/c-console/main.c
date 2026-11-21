/* GREET - the console program template, in C (the twin of sdk/templates/console).
 *
 * Shows: the arguments, printing text and numbers, reading a line from the keyboard, a
 * file written and read back, the exit code.
 *
 *   > greet one "two words" three
 *   Hello from task 5. Up for 3 s.
 *   argument 1: one
 *   ...
 *   What is your name? Ada
 *   Hello, Ada! Your name has 3 letters.
 *   GREET.LOG now has 1 line(s).
 *
 * Run it from the text shell (or in the Desktop's Terminal). Build: make; run: make run.
 */
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <horizon.h>                    /* the syscalls: hz_getpid, hz_uptime, ... */

int main(int argc, char **argv)
{
    char name[40];
    FILE *f;
    int i, c, lines;

    /* ---- who and when */
    printf("Hello from task %u. Up for %lu s.\n", hz_getpid(), (unsigned long)hz_uptime() / 1000);

    /* ---- the arguments, one per line ("quoted text" is one argument); argv[0] is the
     * program's name as the menu bar shows it */
    for (i = 1; i < argc; i++)
        printf("argument %d: %s\n", i, argv[i]);

    /* ---- a line from the keyboard (echo, Backspace, arrows; ctrl-C or ctrl-D: end) */
    printf("What is your name? ");
    if (!fgets(name, sizeof(name), stdin))
        return 1;
    name[strcspn(name, "\n")] = 0;      /* fgets keeps the newline */
    printf("Hello, %s! Your name has %u letters.\n", name, (unsigned)strlen(name));

    /* ---- a file: append the name to GREET.LOG (in the current directory), count its
     * lines. Horizon has 4 file handles for the whole system: close files soon. */
    f = fopen("GREET.LOG", "a");
    if (!f) {
        printf("cannot open GREET.LOG: %s\n", strerror(errno));
        return 1;
    }
    fprintf(f, "%s\n", name);
    fclose(f);

    f = fopen("GREET.LOG", "r");
    if (!f) {
        printf("cannot read GREET.LOG: %s\n", strerror(errno));
        return 1;
    }
    lines = 0;
    while ((c = getc(f)) != EOF)
        if (c == '\n')
            ++lines;
    fclose(f);
    printf("GREET.LOG now has %d line(s).\n", lines);
    return 0;                           /* the exit code (the shell shows it if not 0) */
}
