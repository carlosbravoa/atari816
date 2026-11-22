/* hz_snd.c - Digger's sound for Horizon: upstream's PC speaker on POKEY.
 *
 * Upstream's sound.c plays everything on the PC's speaker through the PIT's timer 2 (the
 * effects: a square wave of 1193181 / t2 Hz) and timer 0 (the music: a square wave of
 * 1193181 / t0 Hz whose loudness is a pulse width), one at a time (spkrmode), changed by
 * soundint() 72.8 times a second. newsnd.c turns that into samples (soundgen.c); here each
 * timer is one of hgame's 16-bit POKEY voices (hg_note: channels joined in pairs at
 * 1.79 MHz), a square wave like the speaker's at the very same pitch: voice 0 the effects
 * (timer 2), voice 1 the music (timer 0, its pulse width as the volume). soundint() is
 * called from the frame loop (hzs_tick) as often as 72.8 Hz makes due. */
#include <hgame.h>
#include "def.h"
#include "device.h"
#include "hardware.h"
#include "sound.h"
#include "newsnd.h"
#include "hz_plat.h"

#define PIT_FREQ 0x1234ddUL

static unsigned hz0, hz2;               /* the timers' pitches, 0: off */
static unsigned vol0;                   /* the music's volume 0-15 */
static bool mute0 = true, mute2 = true, mod2;
static bool paused, enabled;
/* (upstream's SDL back end: no sound device, as with /Q: the level's end does not wait
 * for its jingle) */
bool wave_device_available;
static unsigned out0 = 0xFFFF, out1 = 0xFFFF, outv1 = 0xFFFF;

static void update(void)
{
    unsigned f0 = 0, f1 = 0, v1 = 0;
    if (enabled && !paused) {
        if (!mute2 && !mod2 && hz2)
            f0 = hz2;
        if (!mute0 && hz0 && vol0) {
            f1 = hz0;
            v1 = vol0;
        }
    }
    if (f0 != out0) {
        hg_note(0, f0, f0 ? 10 : 0);
        out0 = f0;
    }
    if (f1 != out1 || v1 != outv1) {
        hg_note(1, f1, v1);
        out1 = f1;
        outv1 = v1;
    }
}

static unsigned pitch(uint16_t t)
{
    return (t > 40 && t < 0x4000) ? (unsigned)(PIT_FREQ / t) : 0;
}

void soundinitglob(uint16_t bufsize, uint16_t samprate)
{
    (void)bufsize;
    (void)samprate;
    enabled = true;
    wave_device_available = true;
}

void s1setupsound(void)
{
    inittimer();
    soundint();
    initsounddevice();
}

void s1killsound(void)
{
    setsoundt2();
    timer2(40, false);
    pausesounddevice(true);
}

void s1timer2(uint16_t t2, bool mode)
{
    hz2 = pitch(t2);
    mod2 = mode;
    if (mode)
        mute2 = false;
    update();
}

void s1soundoff(void)
{
    mute0 = mute2 = true;
    update();
}

void s1setspkrt2(void)
{
    mute0 = spkrmode != 1;
    mute2 = spkrmode != 0;
    update();
}

void s1timer0(uint16_t t0)
{
    unsigned pw = pulsewidth > 1 ? (unsigned)pulsewidth : 1;
    hz0 = pitch(t0);
    vol0 = pw <= 1 ? 0 : (pw * 15 + 25) / 50;
    if (vol0 > 15)
        vol0 = 15;
    update();
}

void s1settimer0(uint16_t t0) { s1timer0(t0); }
void s1settimer2(uint16_t t2, bool mode) { s1timer2(t2, mode); }

bool setsounddevice(uint16_t samprate, uint16_t bufsize)
{
    (void)samprate;
    (void)bufsize;
    return true;
}

bool initsounddevice(void)
{
    pausesounddevice(false);
    return true;
}

void pausesounddevice(bool p)
{
    paused = p;
    update();
}

/* the sound's interrupt, 72.8 a second (upstream: every samprate / 72.8 samples) */
static unsigned long due_us;
static unsigned lastf;
static bool started;

void hzs_reset_clock(void)
{
    started = false;
}

void hzs_tick(void)
{
    unsigned f = hz_frame(), n = 0;
    if (!started) {
        started = true;
        lastf = f;
        due_us = 0;
    }
    due_us += (unsigned long)(unsigned)(f - lastf) * 16658UL;   /* 60.03 frames a second */
    lastf = f;
    while (due_us >= 13736UL && n < 4) {        /* 1 / 72.8 s */
        due_us -= 13736UL;
        ++n;
        soundint();
    }
    if (due_us >= 13736UL)
        due_us = 0;
}

/* upstream's "no sound card" stubs (hardware.h) */
void s0soundoff(void) {}
void s0setspkrt2(void) {}
void s0settimer0(uint16_t t0v) { (void)t0v; }
void s0timer0(uint16_t t0v) { (void)t0v; }
void s0settimer2(uint16_t t2v, bool mode) { (void)t2v; (void)mode; }
void s0timer2(uint16_t t2v, bool mode) { (void)t2v; (void)mode; }
void s0soundinitglob(void) {}
void s0soundkillglob(void) {}
