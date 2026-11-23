/* hz_sound.c - Prince of Persia's sounds on the Atari816 (upstream's seg009 sound calls):
 * POP.SND (tools/mkdata.py) in far memory; the digital effects (DIGISND*.DAT) on Lau, the
 * AdLib music (MIDISND*.DAT, as IMF streams made with SDLPoP's own MIDI interpretation:
 * tools/midi2imf.c) on the OPL2 by hgame's hg_opl_play, the PC speaker's few sounds on
 * POKEY's 16-bit voice.
 *
 * check_sound_playing() steers the game (level ends, cut scenes, gates): whether a sound
 * still plays is counted in vertical blanks from its known length, the same with the sound
 * on or off, with or without the chip. */
#include <string.h>
#include <stdio.h>
#include <hgame.h>
#include <fcntl.h>
#include <unistd.h>
#include "common.h"
#include "hz_plat.h"

#define NSOUNDS 58
#define T_SPEAKER 0x10

static unsigned long snd;               /* POP.SND's address */
static hg_sound *digi[NSOUNDS];
static unsigned char has_lau, has_opl;
static unsigned end_frame;              /* the sound playing until this frame */
static unsigned char playing;           /* 1 digi, 2 midi, 3 speaker */
static int voice = -1;
/* the PC speaker */
static unsigned long spk;               /* its notes */
static unsigned spk_tempo, spk_note_end;

short speaker_playing, digi_playing, midi_playing, ogg_playing;

static const unsigned char __far *entry(unsigned id)
{
    return (const unsigned char __far *)(snd + 6 + 16UL * id);
}

int hzs_init(void)
{
    char path[160];
    hz_fileinfo st;
    unsigned nb, b, i;
    long n;
    int fd;
    has_lau = (unsigned char)hg_has_lau();
    has_opl = (unsigned char)hg_has_opl();
    strcpy(path, hz_prog);
    strcat(path, "POP.SND");
    if (hz_stat_path(path, &st) < 0)
        return -1;
    nb = (unsigned)((st.size + 0xFFFF) >> 16);
    b = hg_banks(nb);
    if (!b)
        return -1;
    snd = (unsigned long)b << 16;
    fd = open(path, O_RDONLY);
    if (fd < 0)
        return -1;
    for (n = 0; n < (long)st.size;) {
        unsigned char *buf = hzd_buf;
        int k = read(fd, buf, sizeof hzd_buf);
        unsigned long a = snd + (unsigned long)n;
        unsigned room = (unsigned)(0x10000UL - (a & 0xFFFF));
        if (k <= 0)
            break;
        if ((unsigned)k <= room) {
            hz_far_copy((void __far *)a, buf, (unsigned)k);
        } else {
            hz_far_copy((void __far *)a, buf, room);
            hz_far_copy((void __far *)(a + room), buf + room, (unsigned)k - room);
        }
        n += k;
    }
    close(fd);
    if (has_lau) {
        for (i = 0; i < NSOUNDS; i++) {
            const unsigned char __far *e = entry(i);
            if (e[0] == 1) {
                unsigned long off = *(const unsigned long __far *)(e + 4);
                unsigned long len = *(const unsigned long __far *)(e + 8);
                digi[i] = hg_sound_from((const void __far *)(snd + off), len,
                                        *(const unsigned __far *)(e + 2), 8);
            }
        }
    }
    return 0;
}

static unsigned frames_of_ms(unsigned long ms)
{
    return (unsigned)((ms * 60UL + 999) / 1000);
}

void hzs_stop(void)
{
    if (voice >= 0)
        hg_stop(voice);
    voice = -1;
    if (has_opl && playing == 2)
        hg_opl_stop();
    if (playing == 3)
        hg_note(0, 0, 0);
    playing = 0;
    speaker_playing = digi_playing = midi_playing = 0;
}

void hzs_play(int id)
{
    const unsigned char __far *e;
    unsigned long off, len, ms;
    if (id < 0 || id >= NSOUNDS || !snd)
        return;
    e = entry((unsigned)id);
    off = *(const unsigned long __far *)(e + 4);
    len = *(const unsigned long __far *)(e + 8);
    ms = *(const unsigned long __far *)(e + 12);
    switch (e[0]) {
    case 1:                             /* digital: replaces the effect playing */
        if (voice >= 0)
            hg_stop(voice);
        voice = -1;
        if (is_sound_on && digi[id])
            voice = hg_play(digi[id], 255);
        end_frame = hz_frame() + frames_of_ms(ms);
        playing = 1;
        digi_playing = 1;
        break;
    case 2:                             /* the music */
        if (has_opl) {
            hg_opl_stop();
            if (is_sound_on && enable_music) {
                hg_opl_reset();
                hg_opl_play((const void __far *)(snd + off), len,
                            *(const unsigned __far *)(e + 2), 0);
            }
        }
        end_frame = hz_frame() + frames_of_ms(ms);
        playing = 2;
        midi_playing = 1;
        break;
    case T_SPEAKER:
        hzs_stop();
        spk = snd + off;
        spk_tempo = *(const unsigned __far *)spk;
        spk += 2;
        spk_note_end = hz_frame();
        playing = 3;
        speaker_playing = 1;
        break;
    }
}

/* once a frame: what has ended; the speaker's next note */
void hzs_poll(void)
{
    unsigned f = hz_frame();
    if (playing == 3) {
        while ((int)(f - spk_note_end) >= 0) {
            unsigned freq = *(const unsigned __far *)spk;
            unsigned char l = *(const unsigned char __far *)(spk + 2);
            if (freq == 0x12 || !spk_tempo) {
                hg_note(0, 0, 0);
                playing = 0;
                speaker_playing = 0;
                return;
            }
            hg_note(0, freq > 1 && is_sound_on ? freq : 0, freq > 1 && is_sound_on ? 8 : 0);
            spk_note_end += (unsigned)(((unsigned long)l * 60UL + spk_tempo - 1) / spk_tempo);
            spk += 3;
        }
        return;
    }
    if (playing && (int)(f - end_frame) >= 0) {
        playing = 0;
        digi_playing = midi_playing = 0;
        voice = -1;
    }
}

int hzs_playing(void)
{
    hzs_poll();
    return playing != 0;
}

/* ---------------------------------------------------------------- upstream's calls */

void init_digi(void) {}

/* a sound: its type and number (the game only passes it to play_sound_from_buffer) */
sound_buffer_type *load_sound(int index)
{
    byte *b;
    const unsigned char __far *e;
    if (!snd || index < 0 || index >= NSOUNDS)
        return NULL;
    e = entry((unsigned)index);
    if (!e[0])
        return NULL;
    b = malloc(2);
    if (!b)
        return NULL;
    b[0] = e[0] == T_SPEAKER ? sound_speaker : e[0];
    b[1] = (byte)index;
    return (sound_buffer_type *)b;
}

void free_sound(sound_buffer_type *buffer)
{
    free(buffer);
}

/* nosound: no sound starts at all (as the reference build's POP_REF_SILENT: the test
 * replays were recorded so; with sound, a replay's end of the level-1 music can fall
 * before the music starts) */
unsigned char hz_nosound;

void play_sound_from_buffer(sound_buffer_type *buffer)
{
    if (hz_nosound)
        return;
#ifdef USE_REPLAY
    if (replaying && skipping_replay)
        return;
#endif
    if (buffer == NULL)
        return;
    hzs_play(((byte *)buffer)[1]);
}

void stop_sounds(void)
{
    hzs_stop();
}

int check_sound_playing(void)
{
    return hzs_playing();
}

void turn_music_on_off(byte new_state)
{
    enable_music = new_state;
    turn_sound_on_off(is_sound_on);
}

void turn_sound_on_off(byte new_state)
{
    is_sound_on = new_state;
    if (!is_sound_on) {
        if (voice >= 0)
            hg_stop(voice);
        voice = -1;
        if (has_opl)
            hg_opl_stop();
        hg_note(0, 0, 0);
    }
}



/* the OGG music's names (data/music/names.txt): no OGG music here */
void load_sound_names(void) {}
char *sound_name(int index)
{
    (void)index;
    return NULL;
}
