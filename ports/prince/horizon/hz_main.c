/* hz_main.c - the start of the Prince of Persia port: main() goes to the program's own
 * folder (the data files are next to PRINCE.PRG; saves, the hall of fame and replays are
 * kept there), loads the data (hz_data.c, hz_sound.c), then runs upstream's pop_main with
 * the arguments (SDLPoP's command line: "validate FILE.P1R", "megahit 3", "seed=n", a .P1R
 * file to replay; the port's own: /BUSY:ms, shots=a,b,c, every=n: hz_ref.c). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <horizon.h>
#include <hgame.h>
#include "common.h"
#include "hz_plat.h"

extern char *hz_ref_shots;
extern int hz_ref_every;
extern char *hz_ref_dump;

int main(int argc, char *argv[])
{
    int n = hz_prog_dir(hz_prog, sizeof hz_prog), i;
    if (n > 1) {
        hz_prog[n - 1] = 0;             /* (chdir: without the last '/') */
        hz_chdir(hz_prog);
        hz_prog[n - 1] = '/';
    } else {
        hz_prog[0] = 0;
    }
    for (i = 1; i < argc; i++) {
        if (!strncasecmp(argv[i], "/BUSY:", 6))
            hz_busy_ms = (unsigned char)atoi(argv[i] + 6);
        else if (!strncasecmp(argv[i], "shots=", 6))
            hz_ref_shots = argv[i] + 6;
        else if (!strncasecmp(argv[i], "dump=", 5)) {
            hz_ref_dump = argv[i] + 5;
        } else if (!strncasecmp(argv[i], "stats=", 6)) {
            extern unsigned hz_stats_every;
            extern void hz_stats_end(void);
            hz_stats_every = (unsigned)atoi(argv[i] + 6);
            atexit(hz_stats_end);
        } else if (!strcasecmp(argv[i], "nosound")) {
            extern unsigned char hz_nosound;
            hz_nosound = 1;
        } else if (!strncasecmp(argv[i], "every=", 6))
            hz_ref_every = atoi(argv[i] + 6);
    }
    if (hzd_init() < 0)
        return 1;
    if (hzs_init() < 0)
        printf("prince: no POP.SND: no sound\n");
    g_argc = argc;
    g_argv = argv;
    printf("prince: start\n");
    pop_main();
    quit(0);
    return 0;
}
