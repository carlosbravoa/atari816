/* tools/midi2imf.c - one of Prince of Persia's MIDI sounds (MIDISND1/2.DAT) as an IMF stream
 * of OPL2 register writes for hgame's hg_opl_play (the port plays the game's AdLib music on
 * the Atari816's real OPL2 instead of SDLPoP's OPL3 emulator).
 *
 * The MIDI interpretation is SDLPoP's own (src/midi.c: parse_midi, process_midi_event,
 * midi_note_on/off, opl_write_instrument; GPL-3, by Falcury and NagyD), unchanged in what it
 * writes; only the clock differs: SDLPoP advances it by audio buffers, here by the exact
 * time of each event (microseconds), then rounded to IMF ticks. OPL3-only writes are left
 * out (register 0x105; the left/right bits 0x30 of 0xC0-0xC8), and the carriers can be made
 * quieter (-a STEPS of 0.75 dB) because the board mixes the OPL2 loud.
 *
 *   midi2imf INSTRUMENTS.BIN SOUND.BIN OUT.IMF [-h HZ] [-t TEMPO%] [-a STEPS] [-l LOG]
 *     INSTRUMENTS.BIN  PRINCE.DAT's resource 1 (u8 count, then 16-byte instruments)
 *     SOUND.BIN        the sound resource (u8 type = 2 midi, then the MIDI file)
 *     -h HZ            IMF ticks a second (default 700)
 *     -t TEMPO         tempo modifier in per cent (SDLPoP: -3 for "Jaffar comes", 3 intro)
 *     -l LOG           also write "us reg value" lines (as host/refhook.c's ref_opl), before
 *                      the OPL2 changes and the attenuation: to compare with upstream
 * It prints the length in milliseconds. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <math.h>

typedef uint8_t byte;
typedef int8_t sbyte;
typedef uint16_t word;
typedef uint32_t dword;

#define NUM_OPL_VOICES 9
#define MAX_MIDI_CHANNELS 16

typedef struct { byte mul, ksl_tl, a_d, s_r, waveform; } operator_type;
typedef struct {                /* as SDLPoP's types.h: 16 bytes */
    byte blocknum_low;
    byte blocknum_high;
    byte FB_conn;
    operator_type operators[2];
    byte percussion;
    byte unknown[2];
} instrument_type;

typedef struct {
    dword delta_time;
    byte event_type;
    byte channel, param1, param2;
    dword length;
    byte *data;
    byte meta_type;
} midi_event_type;

typedef struct {
    int num_events;
    midi_event_type *events;
    int event_index;
    int64_t next_pause_tick;
} midi_track_type;

static instrument_type *instruments;
static int num_instruments;
static instrument_type hardcoded_instrument = {
    0x13, 0x09, 0x04, {{0x02, 0x8D, 0xD7, 0x37, 0x00}, {0x03, 0x03, 0xF5, 0x18, 0x00}}, 0x00, {0x00, 0x00},
};
static byte voice_note[NUM_OPL_VOICES];
static int voice_instrument[NUM_OPL_VOICES];
static int voice_channel[NUM_OPL_VOICES];
static int channel_instrument[MAX_MIDI_CHANNELS];
static int last_used_voice;
static sbyte midi_semitones_higher;
static dword us_per_beat;
static float tempo_modifier;
static byte opl_cached_regs[512];

/* output */
static FILE *imf, *logf_;
static double now_us, last_us;
static long imf_hz = 700;
static int att;
static long records;
static int pend_reg = -1, pend_val;

static void imf_record(int reg, int val, unsigned delay)
{
    fputc(reg, imf);
    fputc(val, imf);
    fputc(delay & 0xFF, imf);
    fputc(delay >> 8, imf);
    ++records;
}

/* each write waits for its successor's time: the delay is stored with the record before */
static void emit(int reg, int val)
{
    if (pend_reg >= 0) {
        double d = (now_us - last_us) * imf_hz / 1e6;
        long ticks = (long)(d + 0.5);
        while (ticks > 0xFFFF) {
            imf_record(pend_reg, pend_val, 0xFFFF);
            pend_reg = 0;               /* a harmless write (register 0) to wait longer */
            pend_val = 0;
            ticks -= 0xFFFF;
        }
        imf_record(pend_reg, pend_val, (unsigned)ticks);
        last_us += ticks * 1e6 / imf_hz;
    } else {
        last_us = now_us;
    }
    pend_reg = reg;
    pend_val = val;
}

static void opl_write_reg(word reg, byte value)
{
    if (logf_)
        fprintf(logf_, "%.0f %03x %02x\n", now_us, reg, value);
    opl_cached_regs[reg] = value;
    if (reg >= 0x100)
        return;                         /* OPL3 only */
    if (reg >= 0xC0 && reg <= 0xC8)
        value &= 0x0F;                  /* OPL3's speaker bits */
    emit(reg, value);
}

static void opl_write_reg_masked(word reg, byte value, byte mask)
{
    byte cached = opl_cached_regs[reg] & ~mask;
    opl_write_reg(reg, cached | (value & mask));
}

static const byte sbpro_op[] = {0, 1, 2, 6, 7, 8, 12, 13, 14, 18, 19, 20, 24, 25, 26, 30, 31, 32};
static const word reg_pair_offsets[] = {0x000, 0x001, 0x002, 0x003, 0x004, 0x005,
                                        0x008, 0x009, 0x00A, 0x00B, 0x00C, 0x00D,
                                        0x010, 0x011, 0x012, 0x013, 0x014, 0x015};
static const word reg_single_offsets[] = {0, 1, 2, 3, 4, 5, 6, 7, 8};

static word opl_reg_pair_offset(byte voice, byte op)
{
    word reg_offset = reg_pair_offsets[sbpro_op[voice]];
    if (op == 1)
        reg_offset += 3;
    return reg_offset;
}

/* the carrier's level, made quieter by att steps */
static byte carrier_att(byte ksl_tl)
{
    int tl = (ksl_tl & 0x3F) + att;
    return (byte)((ksl_tl & 0xC0) | (tl > 63 ? 63 : tl));
}

static void opl_write_instrument(instrument_type *instrument, byte voice)
{
    byte op_index;
    opl_write_reg(0xC0 + reg_single_offsets[voice], instrument->FB_conn | 0x30);
    for (op_index = 0; op_index < 2; ++op_index) {
        operator_type *op = &instrument->operators[op_index];
        word op_reg = opl_reg_pair_offset(voice, op_index);
        opl_write_reg(0x20 + op_reg, op->mul);
        /* (logged as SDLPoP writes it; the stream gets the attenuated carrier) */
        if (op_index == 1 && att) {
            if (logf_)
                fprintf(logf_, "%.0f %03x %02x\n", now_us, 0x40 + op_reg, op->ksl_tl);
            opl_cached_regs[0x40 + op_reg] = op->ksl_tl;
            emit(0x40 + op_reg, carrier_att(op->ksl_tl));
        } else {
            opl_write_reg(0x40 + op_reg, op->ksl_tl);
        }
        opl_write_reg(0x60 + op_reg, op->a_d);
        opl_write_reg(0x80 + op_reg, op->s_r);
        opl_write_reg(0xE0 + op_reg, op->waveform);
    }
}

static instrument_type *get_instrument(int id)
{
    if (id >= 0 && id < num_instruments)
        return &instruments[id];
    return &instruments[0];
}

static void midi_note_off(midi_event_type *event)
{
    int voice;
    for (voice = 0; voice < NUM_OPL_VOICES; ++voice) {
        if (voice_channel[voice] == event->channel && voice_note[voice] == event->param1) {
            opl_write_reg_masked(0xB0 + reg_single_offsets[voice], 0, 0x20);
            voice_note[voice] = 0;
            break;
        }
    }
}

static void midi_note_on(midi_event_type *event)
{
    byte note = event->param1, velocity = event->param2, channel = event->channel;
    int instrument_id = channel_instrument[channel];
    instrument_type *instrument = get_instrument(instrument_id);
    if (velocity == 0) {
        midi_note_off(event);
    } else {
        int voice = -1, test_voice = last_used_voice, i;
        for (i = 0; i < NUM_OPL_VOICES; ++i) {
            ++test_voice;
            test_voice %= NUM_OPL_VOICES;
            if (voice_note[test_voice] == 0) {
                voice = test_voice;
                break;
            }
        }
        last_used_voice = voice;
        if (voice >= 0) {
            float octaves_from_A4, frequency, f_number_float;
            int block, f, instr_volume, carrier_volume;
            word reg_offset;
            if (voice_instrument[voice] != instrument_id) {
                opl_write_instrument(instrument, voice);
                voice_instrument[voice] = instrument_id;
            }
            voice_note[voice] = note;
            voice_channel[voice] = channel;
            octaves_from_A4 = ((int)note - 69 - 12 + midi_semitones_higher) / 12.0f;
            frequency = powf(2.0f, octaves_from_A4) * 440.0f;
            f_number_float = frequency * (float)(1 << 20) / 49716.0f;
            block = (int)(log2f(f_number_float) - 9) & 7;
            f = ((int)f_number_float >> block) & 1023;
            reg_offset = reg_single_offsets[voice];
            opl_write_reg(0xA0 + reg_offset, f & 0xFF);
            opl_write_reg(0xB0 + reg_offset, 0x20 | (block << 2) | (f >> 8));
            opl_write_reg_masked(0x40 + opl_reg_pair_offset(voice, 0), instrument->operators[0].ksl_tl, 0x3F);
            instr_volume = instrument->operators[1].ksl_tl & 0x3F;
            carrier_volume = ((instr_volume + 64) * 225) / (velocity + 161);
            if (carrier_volume < 64) carrier_volume = 64;
            if (carrier_volume > 127) carrier_volume = 127;
            carrier_volume -= 64;
            {
                word reg = 0x40 + opl_reg_pair_offset(voice, 1);
                byte v = (opl_cached_regs[reg] & ~0x3F) | (carrier_volume & 0x3F);
                if (logf_)
                    fprintf(logf_, "%.0f %03x %02x\n", now_us, reg, v);
                opl_cached_regs[reg] = v;
                emit(reg, att ? carrier_att(v) : v);
            }
        } else {
            fprintf(stderr, "midi2imf: skipping a note, not enough OPL voices\n");
        }
    }
}

static void process_midi_event(midi_event_type *event)
{
    switch (event->event_type) {
    case 0x80: midi_note_off(event); break;
    case 0x90: midi_note_on(event); break;
    case 0xC0: channel_instrument[event->channel] = event->param1; break;
    case 0xF0:
        if (event->length == 7) {
            byte *data = event->data;
            if (data[2] == 0x34 && (data[3] == 0 || data[3] == 1) && data[4] == 0)
                midi_semitones_higher = (sbyte)data[5];
        }
        break;
    case 0xFF:
        if (event->meta_type == 0x51) {
            byte *data = event->data;
            int new_tempo = (data[0] << 16) | (data[1] << 8) | data[2];
            new_tempo *= (1.0f + tempo_modifier);
            us_per_beat = (dword)new_tempo;
        }
        break;
    }
}

static dword be32(const byte *p) { return (dword)p[0] << 24 | (dword)p[1] << 16 | (dword)p[2] << 8 | p[3]; }
static word be16(const byte *p) { return (word)(p[0] << 8 | p[1]); }

static dword read_var(byte **pos)
{
    dword r = 0;
    int i;
    byte *p = *pos;
    for (i = 0; i < 4; ++i) {
        r = (r << 7) | (p[i] & 0x7F);
        if ((p[i] & 0x80) == 0)
            break;
    }
    *pos += i + 1;
    return r;
}

static byte *slurp(const char *path, long *n)
{
    FILE *f = fopen(path, "rb");
    byte *b;
    if (!f) { perror(path); exit(1); }
    fseek(f, 0, SEEK_END);
    *n = ftell(f);
    fseek(f, 0, SEEK_SET);
    b = malloc(*n + 16);
    if (fread(b, 1, *n, f) != (size_t)*n) { perror(path); exit(1); }
    fclose(f);
    return b;
}

int main(int argc, char **argv)
{
    long ninst, nsnd;
    byte *inst, *snd, *midi, *chunk;
    int i, num_tracks, division;
    midi_track_type *tracks;
    int64_t pos = 0;
    float fract = 0;
    dword ticks_per_beat;

    if (argc < 4) {
        fprintf(stderr, "usage: midi2imf INSTRUMENTS.BIN SOUND.BIN OUT.IMF [-h HZ] [-t TEMPO%%] [-a STEPS] [-l LOG]\n");
        return 2;
    }
    for (i = 4; i + 1 < argc; i += 2) {
        if (!strcmp(argv[i], "-h")) imf_hz = atol(argv[i + 1]);
        else if (!strcmp(argv[i], "-t")) tempo_modifier = (float)atof(argv[i + 1]) / 100.0f;
        else if (!strcmp(argv[i], "-a")) att = atoi(argv[i + 1]);
        else if (!strcmp(argv[i], "-l")) logf_ = fopen(argv[i + 1], "w");
    }
    inst = slurp(argv[1], &ninst);
    num_instruments = inst[0];
    if (ninst == 1 + num_instruments * (long)sizeof(instrument_type)) {
        instruments = (instrument_type *)(inst + 1);
    } else {
        instruments = &hardcoded_instrument;
        num_instruments = 1;
    }
    snd = slurp(argv[2], &nsnd);
    if ((snd[0] & 7) != 2) {
        fprintf(stderr, "midi2imf: %s is not a MIDI sound (type %d)\n", argv[2], snd[0]);
        return 1;
    }
    midi = snd + 1;
    if (memcmp(midi, "MThd", 4) || be32(midi + 4) != 6 || be16(midi + 8) >= 2) {
        fprintf(stderr, "midi2imf: not a MIDI file of type 0 or 1\n");
        return 1;
    }
    num_tracks = be16(midi + 10);
    division = (int16_t)be16(midi + 12);
    if (division < 0)
        division = (-(division / 256)) * (division & 0xFF);
    ticks_per_beat = (dword)division;
    tracks = calloc(num_tracks, sizeof *tracks);
    chunk = midi + 14;
    for (i = 0; i < num_tracks; ++i) {
        byte *p = chunk + 8, *end, last = 0;
        midi_track_type *t = &tracks[i];
        if (memcmp(chunk, "MTrk", 4)) {
            fprintf(stderr, "midi2imf: no MTrk\n");
            return 1;
        }
        end = chunk + 8 + be32(chunk + 4);
        for (;;) {
            midi_event_type *e;
            t->events = realloc(t->events, (t->num_events + 1) * sizeof *e);
            e = &t->events[t->num_events++];
            memset(e, 0, sizeof *e);
            e->delta_time = read_var(&p);
            e->event_type = *p;
            if (e->event_type & 0x80) {
                if (e->event_type < 0xF8) last = e->event_type;
                ++p;
            } else {
                e->event_type = last;
            }
            switch (e->event_type & 0xF0) {
            case 0x80: case 0x90: case 0xA0: case 0xB0: case 0xE0:
                e->channel = e->event_type & 0x0F;
                e->event_type &= 0xF0;
                e->param1 = *p++;
                e->param2 = *p++;
                break;
            case 0xC0: case 0xD0:
                e->channel = e->event_type & 0x0F;
                e->event_type &= 0xF0;
                e->param1 = *p++;
                break;
            default:
                if (e->event_type == 0xF0 || e->event_type == 0xF7) {
                    e->length = read_var(&p);
                    e->data = p;
                    p += e->length;
                } else if (e->event_type == 0xFF) {
                    e->meta_type = *p++;
                    e->length = read_var(&p);
                    e->data = p;
                    p += e->length;
                } else {
                    fprintf(stderr, "midi2imf: unknown event 0x%02x\n", e->event_type);
                    return 1;
                }
            }
            if (e->event_type == 0xFF && e->meta_type == 0x2F)
                break;
            if (p >= end) {
                fprintf(stderr, "midi2imf: a track runs past its end\n");
                return 1;
            }
        }
        chunk = end;
    }

    imf = fopen(argv[3], "wb");
    if (!imf) { perror(argv[3]); return 1; }
    /* play_midi_sound: OPL3 on (not for the OPL2: logged only), every voice instrument 0 */
    memset(opl_cached_regs, 0, sizeof opl_cached_regs);
    opl_write_reg(0x105, 0x01);
    for (i = 0; i < NUM_OPL_VOICES; ++i) {
        opl_write_instrument(&instruments[0], (byte)i);
        voice_instrument[i] = 0;
        voice_note[i] = 0;
    }
    for (i = 0; i < MAX_MIDI_CHANNELS; i++)
        channel_instrument[i] = i;
    us_per_beat = 500000;

    /* midi_callback's event loop, with an exact clock */
    for (;;) {
        int finished = 0;
        int64_t first = INT64_MAX;
        for (i = 0; i < num_tracks; ++i) {
            midi_track_type *t = &tracks[i];
            while (pos >= t->next_pause_tick) {
                int left = t->num_events - t->event_index;
                if (left > 0) {
                    midi_event_type *e = &t->events[t->event_index++];
                    process_midi_event(e);
                    if (left > 1) {
                        midi_event_type *n = &t->events[t->event_index];
                        if (n->delta_time != 0)
                            t->next_pause_tick += n->delta_time;
                    }
                } else {
                    ++finished;
                    break;
                }
            }
        }
        if (finished >= num_tracks)
            break;
        for (i = 0; i < num_tracks; ++i) {
            midi_track_type *t = &tracks[i];
            if (t->event_index >= t->num_events || pos >= t->next_pause_tick)
                continue;
            if (t->next_pause_tick < first)
                first = t->next_pause_tick;
        }
        if (first == INT64_MAX) {
            fprintf(stderr, "midi2imf: no next event\n");
            return 1;
        }
        {
            int64_t ticks = first - pos;
            now_us += (double)ticks * us_per_beat / ticks_per_beat;
            pos = first;
            (void)fract;
        }
    }
    /* the end: every voice off, the last record waits until the song's end */
    for (i = 0; i < NUM_OPL_VOICES; ++i)
        emit(0xB0 + i, opl_cached_regs[0xB0 + i] & ~0x20);
    emit(0, 0);
    imf_record(pend_reg, pend_val, 0);
    fclose(imf);
    if (logf_)
        fclose(logf_);
    printf("%.0f\n", now_us / 1000.0);
    return 0;
}
