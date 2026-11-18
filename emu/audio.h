/* Lau, the sample player, $00:DB20-$DB2A, $00:DB80-$DBFF (REV $0A): a bit-exact model of
 * core/src/a816/a816_snd.sv, one step per 48 kHz output sample. */
#ifndef AUDIO_H
#define AUDIO_H
#include <stdint.h>
#include <stdio.h>

typedef struct AVoice {
    uint32_t pos, tag;
    uint16_t frac;
    int16_t  s_cur;
    uint8_t  blk[8];                /* the voice's last 8-byte block */
} AVoice;

typedef struct Audio {
    uint8_t  pram[128];             /* voice registers as written */
    AVoice   v[8];
    uint8_t  playing, keyon, end, irq_en, master, late, sel;
    uint32_t pos_live;
    uint64_t k;                     /* next output sample number */
    uint64_t next;                  /* its CPU cycle (UINT64_MAX: idle) */
    int16_t  out_l, out_r;
    FILE    *wav;                   /* --wav: the sample player's output */
    uint64_t wav_n;
    uint64_t n_samples, n_keyon;
} Audio;

void    audio_reset(void);
void    audio_update(uint64_t now);
uint64_t audio_next_event(void);
uint8_t audio_read(uint32_t a);
void    audio_write(uint32_t a, uint8_t v);
int     audio_irq(void);
int     audio_wav_open(const char *path);
void    audio_wav_close(void);

#endif
