/* hz_main.c - Xargon's start on Horizon: main() goes to the program's folder (the game's
 * data files are next to XARGON1.PRG, and CONFIG.XRn, the saved games and the high scores
 * are kept there, as upstream keeps them in the current folder under DOS), takes the full
 * screen (hz_vga.c), then runs upstream's main (xargon.c, renamed xargon_main by
 * xcompat.h). */
#undef main
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <horizon.h>
#include <hgame.h>
#include "gr.h"
#include "x_obj.h"
#include "xargon.h"
#include "hz_plat.h"

char hz_dir[128];

void xargon_main(int argc, char *argv[]);
extern char xshafile[];                 /* x_volN.c: GRAPHICS.XRn */
void shm_init(char *fname);

void hz_fatal(const char *msg)
{
    hg_close();
    printf("xargon: %s\n", msg);
    exit(1);
}

int main(int argc, char *argv[])
{
    int n = hz_prog_dir(hz_dir, sizeof hz_dir);
    if (n > 1) {
        hz_dir[n - 1] = 0;              /* (chdir: without the last '/') */
        hz_chdir(hz_dir);
        hz_dir[n - 1] = '/';
    }
    for (n = 1; n < argc; n++) {
        if (!strcmp(argv[n], "/STATS") || !strcmp(argv[n], "/stats"))
            hzf_stats = 1;
        else if (!strncmp(argv[n], "/BUSY:", 6) || !strncmp(argv[n], "/busy:", 6))
            hzf_busy = (unsigned)atoi(argv[n] + 6);
    }
    atexit(hzf_report);
    shm_init(xshafile);                 /* (the atlas: the blitter's sheets need it) */
    if (hzv_init() < 0) {
        printf("xargon: no full screen (memory: %u banks free)\n", hz_mem_info());
        return 1;
    }
    xargon_main(argc, argv);
    hg_close();
    return 0;
}
