/* gt_sound.c - hgame's test: POKEY tones and envelopes (logged by the emulator: no sound
 * from POKEY there), samples on Lau (made here, from an array, from a WAV file on the
 * card; panned, pitched, looped, stopped), music by the engine (a MOD on Lau, a MIDI file
 * on the OPL2): the emulator records Lau and the OPL2 into a WAV file, checked by run.py. */
#include <stdio.h>
#include <string.h>
#include <hgame.h>

static unsigned fails;

static void check(const char *what, int ok)
{
    printf("%s sound: %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        ++fails;
}

static void wait(unsigned ms)
{
    unsigned long t = hg_ms();
    while (hg_ms() - t < ms && hg_frame())
        ;
}

static signed char saw[800];

int main(void)
{
    hg_sound *s, *a, *w;
    int v, v2;
    unsigned i, st;

    if (hg_window(200, 60, "gt_sound") < 0) {
        printf("FAIL sound: hg_window\n");
        return 1;
    }
    hg_clear(C_BODY);
    hg_text(8, 8, "sound", C_BLACK);
    hg_frame();
    /* POKEY */
    check("hg_pitch(440)", hg_pitch(440) == 71);
    hg_tone(1, hg_pitch(440), 8, 10);
    hg_sfx(2, 60, -3, 12, 1, 20, HG_TONE);
    hg_sfx(3, 40, 2, 15, 1, 15, HG_NOISE);
    wait(500);
    printf("gt_sound: POKEY done\n");
    /* Lau */
    check("Lau there (REV $0A and later)", hg_has_lau());
    s = hg_sound_make(HG_SQUARE, 440, 300, 50);
    check("a sound made (16 kHz, 300 ms)", s && s->len == 4800 && s->rate == 16000 &&
          s->bits == 8);
    v = hg_play(s, 200);
    check("played on a voice", v >= 0 && v <= 7);
    st = hz_sample_stat();
    check("the voice plays", (st >> v) & 1);
    wait(400);
    st = hz_sample_stat();
    check("... and ends by itself", !((st >> v) & 1));
    for (i = 0; i < sizeof saw; i++)
        saw[i] = (signed char)((int)(i % 40) * 6 - 120);
    a = hg_sound_from(saw, sizeof saw, 16000, 8);
    a->loop = 1;
    v = hg_play_ex(a, 180, -100, 12);               /* left, an octave up, looping */
    v2 = hg_play_ex(s, 180, 100, -5);               /* right, a fourth down */
    check("two voices at once", v >= 0 && v2 >= 0 && v != v2);
    wait(500);
    st = hz_sample_stat();
    check("the loop goes on", (st >> v) & 1);
    hg_stop(v);
    wait(50);
    st = hz_sample_stat();
    check("hg_stop", !((st >> v) & 1));
    w = hg_sound_load("/BEEP.WAV");
    check("a WAV file loaded (8 bits, 16 kHz, 4000 samples)", w && w->len == 4000 &&
          w->rate == 16000 && w->bits == 8);
    if (w)
        check("... and played", hg_play(w, 255) >= 0);
    wait(400);
    w = hg_sound_load("/BEEP16.WAV");
    check("a 16-bit WAV file (22,050 Hz, 2205 samples)", w && w->len == 2205 &&
          w->rate == 22050 && w->bits == 16 && (w->addr & 1) == 0);
    if (w)
        check("... and played", hg_play(w, 255) >= 0);
    wait(200);
    check("a missing file: NULL and a message", hg_sound_load("/NOPE.WAV") == 0);
    /* music */
    check("a module (MOD) by the music engine", hg_music_play("/Music/LAU.MOD", 1) == 0 &&
          hg_music_state() == HG_MUSIC_PLAYING);
    wait(1200);
    hg_music_pause(1);
    wait(200);
    check("paused", hg_music_state() == HG_MUSIC_PAUSED);
    hg_music_stop();
    wait(200);
    check("stopped", hg_music_state() == HG_MUSIC_STOPPED);
    check("a MIDI file on the OPL2", hg_music_play("/Music/ELISE.MID", 0) == 0 &&
          hg_music_state() == HG_MUSIC_PLAYING);
    wait(1500);
    hg_music_volume(20);
    wait(300);
    hg_sound_off();
    hg_music_stop();
    wait(200);
    printf("gt_sound: %u failed\n", fails);
    return 0;
}
