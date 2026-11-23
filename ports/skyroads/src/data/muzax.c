#include <string.h>

#include "data/muzax.h"
#include "data/compression.h"

static MuzaxOscillator parse_oscillator(const uint8_t SR_FAR *block)
{
    const uint8_t tremolo = block[0];
    const uint8_t key_scale_level = block[1];
    const uint8_t attack_rate = block[2];
    const uint8_t sustain_level = block[3];
    const uint8_t wave_form = block[4];
    MuzaxOscillator osc;
    osc.tremolo = (tremolo & 0x80) != 0;
    osc.vibrato = (tremolo & 0x40) != 0;
    osc.sound_sustaining = (tremolo & 0x20) != 0;
    osc.key_scaling = (tremolo & 0x10) != 0;
    osc.multiplication = tremolo & 0x0F;
    osc.key_scale_level = key_scale_level >> 6;
    osc.output_level = key_scale_level & 0x3F;
    osc.attack_rate = attack_rate >> 4;
    osc.decay_rate = attack_rate & 0x0F;
    osc.sustain_level = sustain_level >> 4;
    osc.release_rate = sustain_level & 0x0F;
    osc.wave_form = wave_form & 0x07;
    return osc;
}

static const MuzaxInstrument SR_FAR *parse_instruments(const uint8_t SR_FAR *data,
                                                       uint32_t data_len, unsigned count)
{
    MuzaxInstrument SR_FAR *instruments =
        (MuzaxInstrument SR_FAR *)plat_alloc((uint32_t)SR_MAX(count, 1) * sizeof(MuzaxInstrument));
    unsigned index, b;
    for (index = 0; index < count; ++index) {
        const uint32_t start = (uint32_t)index * 16;
        MuzaxInstrument instrument;
        if (start + 16 > data_len)
            sr_fail("MUZAX instrument %u is truncated", index);
        instrument.index = index;
        for (b = 0; b < 16; ++b)
            instrument.raw[b] = data[start + b];
        instrument.operator_a = parse_oscillator(data + start);
        instrument.operator_b = parse_oscillator(data + start + 5);
        instrument.channel_config = data[start + 10];
        for (b = 0; b < 5; ++b)
            instrument.tail[b] = data[start + 11 + b];
        instruments[index] = instrument;
    }
    return instruments;
}

MuzaxArchive load_muzax_lzs_bytes(const Bytes *data)
{
    const uint16_t song_table_size = read_u16(data, 0);
    unsigned count, i, j;
    MuzaxArchive archive;

    if (song_table_size % 6 != 0)
        sr_fail("MUZAX.LZS song table size is not a multiple of 6: %u", song_table_size);
    if ((uint32_t)song_table_size > data->size)
        sr_fail("MUZAX.LZS song table size is out of range: %u", song_table_size);

    count = song_table_size / 6;
    archive.source_len = data->size;
    archive.song_table_size = song_table_size;
    archive.songs = (MuzaxSong SR_FAR *)plat_alloc((uint32_t)SR_MAX(count, 1) * sizeof(MuzaxSong));
    archive.song_count = count;

    for (i = 0; i < count; ++i) {
        MuzaxSong song;
        MuzaxSongHeader header;
        uint32_t next_song_start = data->size, start_pos, instrument_bytes;
        CompressionWidths widths;
        DecompressResult decoded;
        Bytes payload;

        header.index = i;
        header.start_pos = read_u16(data, i * 6);
        header.num_instruments = read_u16(data, i * 6 + 2);
        header.uncompressed_length = read_u16(data, i * 6 + 4);
        /* build_next_song_starts */
        for (j = i + 1; j < count; ++j) {
            const uint16_t s = read_u16(data, j * 6);
            if (s != 0) {
                next_song_start = s;
                break;
            }
        }

        memset(&song, 0, sizeof song);
        song.header = header;
        song.next_song_start = next_song_start;

        if (muzax_header_is_empty(&header)) {
            archive.songs[i] = song;
            continue;
        }

        start_pos = header.start_pos;
        if (start_pos + 3 > data->size)
            sr_fail("MUZAX song %u starts out of range", header.index);
        widths.w1 = at(data, start_pos);
        widths.w2 = at(data, start_pos + 1);
        widths.w3 = at(data, start_pos + 2);
        decoded = decompress_stream(data, start_pos + 3, true, header.uncompressed_length, widths);
        payload = decoded.output;
        instrument_bytes = (uint32_t)header.num_instruments * 16;
        if (instrument_bytes > payload.size)
            sr_fail("MUZAX song %u instrument region exceeds payload", header.index);

        song.has_widths = true;
        song.widths[0] = widths.w1;
        song.widths[1] = widths.w2;
        song.widths[2] = widths.w3;
        song.compressed_end = start_pos + 3 + decoded.consumed;
        song.compressed_size = 3 + decoded.consumed;
        song.instrument_bytes = instrument_bytes;
        song.command_bytes = payload.size - instrument_bytes;
        song.instruments = parse_instruments(payload.data, instrument_bytes, header.num_instruments);
        song.instrument_count = header.num_instruments;
        song.has_commands = true;
        /* C: the commands are the payload's tail (the C++ copied them) */
        song.commands.data = payload.data + instrument_bytes;
        song.commands.size = payload.size - instrument_bytes;
        song.payload = payload;
        archive.songs[i] = song;
    }
    return archive;
}

MuzaxArchive load_muzax_lzs_path(const char *path)
{
    Bytes data = read_file(path);
    MuzaxArchive a = load_muzax_lzs_bytes(&data);
    free_bytes(&data);
    return a;
}
