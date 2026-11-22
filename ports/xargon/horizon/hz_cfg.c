/* hz_cfg.c - upstream's config.c on Horizon: there the game asked (in text mode) for the
 * Sound Blaster, its digital effects and its music, and calibrated the joystick, and kept
 * the answers in CONFIG.XRn. Here the hardware answers: Lau for the effects, the OPL2 for
 * the music (hz_snd.c sets vocflag and musicflag from them), the joystick through the
 * emulated game port (hz_frame.c), calibrated for its positions. Upstream's command line
 * options stay: /NOSB (no effects, no music), /NOSND (no sound). */
#include <string.h>
#include <ctype.h>
#include "gamectrl.h"
#include "music.h"

int nosnd = 0;

struct {
    int firstthru;
    int joyflag0, joyxl0, joyxc0, joyxr0, joyyu0, joyyc0, joyyd0;
    int x_ourmode0;
    int musicflag0;
    int vocflag0;
    char pad[64];
} cf;

void cfg_init(int argc, char *argv[])
{
    int c;
    char s[16];
    for (c = 0; c < argc; c++) {
        strncpy(s, argv[c], sizeof s - 1);
        s[sizeof s - 1] = 0;
        {
            char *p;
            for (p = s; *p; p++)
                *p = (char)toupper((unsigned char)*p);
        }
        if (!strcmp(s, "/NOSB")) {
            vocflag = 0;
            musicflag = 0;
        } else if (!strcmp(s, "/NOSND")) {
            vocflag = 0;
            musicflag = 0;
            nosnd = 1;
        }
    }
}

int doconfig(void)
{
    /* the joystick: hz_frame.c's game port gives 10, 20, 30 for left, centre, right */
    joyflag = 1;
    joyxc = 20;
    joyyc = 20;
    joyxl = -10;
    joyxr = 10;
    joyyu = -10;
    joyyd = 10;
    cf.firstthru = 0;
    cf.joyflag0 = joyflag;
    cf.joyxl0 = joyxl;
    cf.joyxc0 = joyxc;
    cf.joyxr0 = joyxr;
    cf.joyyu0 = joyyu;
    cf.joyyc0 = joyyc;
    cf.joyyd0 = joyyd;
    cf.x_ourmode0 = 4;                  /* x_vga */
    cf.musicflag0 = musicflag;
    cf.vocflag0 = vocflag;
    return 1;
}
