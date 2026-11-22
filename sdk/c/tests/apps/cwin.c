/* CWIN - (Horizon 0.29) the apps test's C window program (tests/run.py "apps"): built with
 * hcc --needs, packed with sdk/tools/hzapp.py into CWIN.HZA, installed with the
 * Installer, started. It prints where it runs (its folder: hz_prog_dir, its current
 * folder) and what hz_sys_info says, opens a window with a label, waits about a second
 * (the window timer) and ends. */
#include <stdio.h>
#include <horizon.h>
#include <hui.h>

static ui_label l_hello = UI_LABEL(UI_GAP, 12, 200, 0, "Hello from an app.");
static ui_ctlref ctls[] = { &l_hello, 0 };

int main(void)
{
    hz_winopen wo;
    char dir[128], cwd[128];
    unsigned own, v, ticks = 0;
    int w;

    hz_prog_dir(dir, sizeof dir);
    hz_getcwd(cwd, sizeof cwd);
    v = hz_sys_info();
    printf("cwin: in %s, current folder %s, Horizon %u.%u, REV %u\n", dir, cwd, v >> 8,
           v & 0xFF, hz_x);
    own = hz_ws_start();
    if (own > 1)                        /* (no window system: the console only) */
        return 0;
    ui_init();
    wo.x = 200;
    wo.y = 100;
    wo.w = 216;
    wo.h = 40;
    HZ_U24(wo.title, "C app");
    wo.flags = 0;
    w = hz_win_open(&wo);
    if (w < 0)
        return 1;
    ui_setwin(ctls, (unsigned)w);
    ui_drawall(ctls);
    hz_win_timer((unsigned)w, 100);     /* a tick a second */
    while (ticks < 2) {
        if (ui_getev(0))
            continue;
        if (ui_ev.type == WE_TICK)
            ticks++;
        else if (ui_ev.type == WE_CLOSE)
            break;
    }
    printf("cwin: done\n");
    hz_win_close((unsigned)w);
    if (own == 1)
        hz_ws_stop();
    return 0;
}
