/* hz_ref.c - the port's test hooks: the game's state as host/refhook.c prints it in the
 * reference build (upstream SDLPoP on a PC), at replay ticks (every=n, or the ticks of
 * shots=), and the screen held still at those ticks for a screenshot ("prince: shot N tick
 * T": run816.py --shot-on). tests/ compares both with the PC's. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <hgame.h>
#include "common.h"
#include "hz_plat.h"

char *hz_ref_shots;
int hz_ref_every;
static int shot_n;

static int in_list(const char *s, int tick)
{
    while (s && *s) {
        if (atoi(s) == tick)
            return 1;
        s = strchr(s, ',');
        if (s)
            ++s;
    }
    return 0;
}


/* every variable of the savestate (quick_process), in hex: dump=a,b (host/refhook.c's too) */
char *hz_ref_dump;
static int dump_n;
static int dump_func(void *data, size_t size)
{
    size_t i;
    printf("dump %d %u:", dump_n++, (unsigned)size);
    for (i = 0; i < size; i++)
        printf("%02x", ((unsigned char *)data)[i]);
    printf("\n");
    return 1;
}
extern int quick_process(int (*f)(void *, size_t));

void ref_print_state(void)
{
    printf("ref: tick %ld level %d room %d kid %d %d %d %d %d alive %d hp %d/%d "
           "guard %d %d %d %d alive %d hp %d/%d seed %lu time %d %d\n",
           (long)curr_tick, current_level, drawn_room,
           Kid.room, Kid.x, Kid.y, Kid.frame, Kid.direction, Kid.alive, hitp_curr, hitp_max,
           Guard.room, Guard.x, Guard.y, Guard.frame, Guard.alive, guardhp_curr, guardhp_max,
           (unsigned long)random_seed, rem_min, rem_tick);
}

void ref_hook(void)
{
    static long last = -1;
    long tick = (long)curr_tick;
    int shot;
    if (!(replaying || recording) || tick == last)
        return;
    last = tick;
    shot = in_list(hz_ref_shots, (int)tick);
    if (hz_ref_every > 0 && tick % hz_ref_every == 0)
        ref_print_state();
    if (in_list(hz_ref_dump, (int)tick)) {
        dump_n = 0;
        printf("dump tick %ld\n", tick);
        quick_process(dump_func);
    }
    if (shot) {
        hzv_snap = 1;
        hzv_sync();
        update_screen();
        hzt_wait_frames(2);
        printf("prince: shot %d tick %ld view %d %d\n", ++shot_n, tick, hzv_view_y, hzv_view_game);
        hzt_wait_frames(6);
        hzv_snap = 0;
    }
}
