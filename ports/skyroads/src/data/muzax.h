/* MUZAX.LZS: the songs, each its instruments (16 bytes) and its command stream.
 * C translation: the command summary (counts for the CLI) is left out. */
#ifndef DATA_MUZAX_H
#define DATA_MUZAX_H

#include "data/byteio.h"

typedef struct {
    unsigned index;
    uint16_t start_pos;
    uint16_t num_instruments;
    uint16_t uncompressed_length;
} MuzaxSongHeader;

static inline bool muzax_header_is_empty(const MuzaxSongHeader *h)
{
    return h->start_pos == 0 && h->num_instruments == 0 && h->uncompressed_length == 0;
}

typedef struct {
    bool tremolo;
    bool vibrato;
    bool sound_sustaining;
    bool key_scaling;
    uint8_t multiplication;
    uint8_t key_scale_level;
    uint8_t output_level;
    uint8_t attack_rate;
    uint8_t decay_rate;
    uint8_t sustain_level;
    uint8_t release_rate;
    uint8_t wave_form;
} MuzaxOscillator;

typedef struct {
    unsigned index;
    uint8_t raw[16];
    MuzaxOscillator operator_a;
    MuzaxOscillator operator_b;
    uint8_t channel_config;
    uint8_t tail[5];
} MuzaxInstrument;

typedef struct {
    MuzaxSongHeader header;
    uint32_t next_song_start;
    bool has_widths;            /* std::optional<std::array<uint8_t, 3>> widths ... */
    uint8_t widths[3];
    uint32_t compressed_end;
    uint32_t compressed_size;
    Bytes payload;
    uint32_t instrument_bytes;
    uint32_t command_bytes;
    const MuzaxInstrument SR_FAR *instruments;
    unsigned instrument_count;
    bool has_commands;
    Bytes commands;
} MuzaxSong;

typedef struct {
    uint32_t source_len;
    uint16_t song_table_size;
    MuzaxSong SR_FAR *songs;
    unsigned song_count;
} MuzaxArchive;

MuzaxArchive load_muzax_lzs_bytes(const Bytes *data);
MuzaxArchive load_muzax_lzs_path(const char *path);

#endif
