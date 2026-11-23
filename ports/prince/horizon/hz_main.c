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
    unsigned char sndtest = 0;
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
        } else if (!strcasecmp(argv[i], "levelsum")) {
            extern unsigned char hz_ref_level;
            hz_ref_level = 1;
        } else if (!strcasecmp(argv[i], "sndtest")) {
            sndtest = 1;
        } else if (!strncasecmp(argv[i], "every=", 6))
            hz_ref_every = atoi(argv[i] + 6);
    }
    /* the screen at once: the loading takes seconds on the board's card */
    if (hzv_screen() < 0) {
        printf("prince: no full screen (%u banks free)\n", hz_mem_info());
        return 1;
    }
    printf("prince: loading\n");
    if (hzd_init() < 0)
        return 1;
    if (hzs_init() < 0)
        printf("prince: no POP.SND: no sound\n");
    if (sndtest) {
        /* every sound once, one after the other ("prince: sound N" as it starts; the
         * songs' first 4 s): their levels in a recording (tests/sndlevel.py) */
        for (i = 0; i < 58; i++) {
            unsigned f = hz_frame();
            hzs_play(i);
            if (!hzs_playing())
                continue;
            printf("prince: sound %d\n", i);
            while (hzs_playing() && (unsigned)(hz_frame() - f) < 240)
                hzt_wait_frames(1);
            hzs_stop();
            hzt_wait_frames(30);
        }
        printf("prince: sound end\n");
        return 0;
    }
    g_argc = argc;
    g_argv = argv;
    printf("prince: start (%lu bytes loaded)\n", hzd_loaded);
    pop_main();
    quit(0);
    return 0;
}
