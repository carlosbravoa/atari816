/* SUM - a console program: the arguments, a line typed at the keyboard, a file.
 *   > sum 2 40
 *   sum of 2 arguments: 42
 *   Your name? Ada
 *   saved Ada in SUM.TXT */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv)
{
    char name[32];
    long total = 0;                     /* int is 16 bits: use long for big sums */
    FILE *f;
    int i;

    for (i = 1; i < argc; i++)
        total += atol(argv[i]);
    printf("sum of %d arguments: %ld\n", argc - 1, total);

    printf("Your name? ");
    if (!fgets(name, sizeof name, stdin))
        return 1;
    name[strcspn(name, "\n")] = 0;

    f = fopen("SUM.TXT", "w");          /* in the current folder; 4 files open at most */
    if (!f)
        return 1;
    fprintf(f, "%s %ld\n", name, total);
    fclose(f);
    printf("saved %s in SUM.TXT\n", name);
    return 0;
}
