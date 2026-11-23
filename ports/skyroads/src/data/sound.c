#include "data/sound.h"

Pcm8Sample load_intro_snd_bytes(const Bytes *data)
{
    /* RVSTACK: the intro player @0x4768 pushes DSP Time Constant 0x5A as an
     * immediate (no header byte in the file): rate = 1e6/(256-0x5A) = 6024 Hz.
     * The old hard-coded 8000 played the 5.3 s sample 33% fast and high. */
    Pcm8Sample s;
    s.sample_rate = 1000000u / (256u - 0x5A);
    s.samples = bytes_slice(data, 0, data->size);
    return s;
}

Pcm8Sample load_intro_snd_path(const char *path)
{
    Bytes data = read_file(path);
    Pcm8Sample s = load_intro_snd_bytes(&data);
    free_bytes(&data);
    return s;
}

SfxBank load_sfx_snd_bytes(const Bytes *data)
{
    uint32_t first_offset, offset;
    unsigned count, i, index;
    SfxEntry SR_FAR *effects;
    SfxBank bank;

    if (data->size < 2)
        sr_fail("SFX.SND is too small to contain an offset table");
    first_offset = read_u16(data, 0);
    if (first_offset % 2 != 0)
        sr_fail("SFX.SND first offset is not aligned: %lu", (unsigned long)first_offset);
    if (first_offset > data->size)
        sr_fail("SFX.SND first offset is out of range: %lu", (unsigned long)first_offset);

    count = (unsigned)(first_offset / 2);
    if (count == 0 || read_u16(data, 0) != first_offset)
        sr_fail("SFX.SND offset table does not point to its first payload");
    for (i = 0; i + 1 < count; ++i)
        if (read_u16(data, i * 2) > read_u16(data, (i + 1) * 2))
            sr_fail("SFX.SND offsets are not monotonically increasing");

    bank.source_len = data->size;
    bank.sample_rate = SAMPLE_RATE_PCM_8K;
    effects = (SfxEntry SR_FAR *)plat_alloc((uint32_t)count * sizeof(SfxEntry));
    for (index = 0; index < count; ++index) {
        const uint32_t start = read_u16(data, index * 2);
        const uint32_t end = (index + 1 < count) ? read_u16(data, (index + 1) * 2) : data->size;
        SfxEntry entry;
        (void)offset;
        if (end > data->size || start > end)
            sr_fail("SFX.SND effect %u has invalid range", index);
        entry.index = index;
        entry.start = start;
        entry.end = end;
        /* RVSTACK: each entry's FIRST byte is the Sound Blaster Time Constant
         * the DOS player feeds to DSP cmd 0x40 (@0x440-0x449 pulls it out,
         * @0x5b7e programs it): rate = 1e6/(256-TC). The shipped bank:
         * explosion TC 0x06 = 4000 Hz, bump TC 0xEC = 50000 Hz, bounce/
         * alarm/refill TC 0x83 = 8000 Hz. The old code played the TC byte as
         * a sample and everything at a flat 8000. */
        if (end - start >= 2) {
            const uint8_t tc = at(data, start);
            entry.sample.sample_rate = 1000000u / (256u - tc);
            entry.sample.samples = bytes_slice(data, start + 1, end - start - 1);
        } else {
            entry.sample.sample_rate = SAMPLE_RATE_PCM_8K;
            entry.sample.samples.data = 0;
            entry.sample.samples.size = 0;
        }
        effects[index] = entry;
    }
    bank.effects = effects;
    bank.effect_count = count;
    return bank;
}

SfxBank load_sfx_snd_path(const char *path)
{
    Bytes data = read_file(path);
    SfxBank b = load_sfx_snd_bytes(&data);
    free_bytes(&data);
    return b;
}
