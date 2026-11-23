/* INTRO.SND (one 8-bit sample) and SFX.SND (the effects bank). Unsigned 8-bit PCM. */
#ifndef DATA_SOUND_H
#define DATA_SOUND_H

#include "data/byteio.h"

#define SAMPLE_RATE_PCM_8K 8000u

typedef struct {
    uint32_t sample_rate;
    Bytes samples;
} Pcm8Sample;

typedef struct {
    unsigned index;
    uint32_t start;
    uint32_t end;
    Pcm8Sample sample;
} SfxEntry;

typedef struct {
    uint32_t source_len;
    uint32_t sample_rate;
    const SfxEntry SR_FAR *effects;
    unsigned effect_count;
} SfxBank;

Pcm8Sample load_intro_snd_bytes(const Bytes *data);
Pcm8Sample load_intro_snd_path(const char *path);
SfxBank load_sfx_snd_bytes(const Bytes *data);
SfxBank load_sfx_snd_path(const char *path);

#endif
