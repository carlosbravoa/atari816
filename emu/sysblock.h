/* System block $00:DE00: ID, interrupts, timers, uptime, watchdog, debug port. */
#ifndef SYSBLOCK_H
#define SYSBLOCK_H
#include <stdint.h>

#define SYS_REV_VAL 0x0B         /* default; --rev N reports an older board */
#define WDOG_US     2000000

enum { IRQ_VBLANK = 0x01, IRQ_LINE = 0x02, IRQ_TIMER0 = 0x04, IRQ_TIMER1 = 0x08,
       IRQ_BLITTER = 0x10, IRQ_AUDIO = 0x20, IRQ_IOP = 0x40, IRQ_SUPERVISOR = 0x80 };

typedef struct SysBlock {
    uint8_t  irq_status, irq_en, nmi_status;
    uint32_t tm_reload[2], tm_count[2];
    uint8_t  tm_run[2], tm_rep[2];
    uint32_t wd_count;
    uint8_t  wd_armed;
    uint64_t us;                /* microsecond ticks since reset (UPTIME = low 32 bits) */
    uint64_t next_tick;         /* CPU cycle of the next microsecond tick */
    uint32_t uptime_lat;
    uint8_t  kb_route;
    uint8_t  nmi_line;          /* NMI as presented to the CPU: |NMI_STATUS && !nmi_hold */
    uint64_t console_cycles;    /* --console-us in CPU cycles (0 = DBG_OUT never busy) */
    uint64_t dbg_busy_until;
    uint64_t dbg_dropped;
    uint8_t  sv_ctrl;           /* $00:DC00 SV_CTRL: only bit 2 FREEZE_REQ is kept */
    uint8_t  rev;               /* SYS_REV: $06 no sound, $07 + sound, $08 + blitter, $09 + lists, beam events, $0A + sample player, $0B + sprites and fine scrolling */
    uint8_t  snd[0x14];         /* REV $07 sound page $00:DB00-$DB13 as written */
    uint64_t snd_writes, snd_ignored;
    int      snd_log;           /* --log-sound: every accepted write on stderr */
} SysBlock;

void    sys_reset(void);
void    sys_update(uint64_t now);       /* run the microsecond ticks due by cycle now */
uint8_t sys_read(uint32_t a);
void    sys_write(uint32_t a, uint8_t v);
/* classic supervisor page ($00:DC00): SV_CTRL bit 2 FREEZE_REQ (bit 0 reads 1),
 * SV_STATUS ($DC01) bit 0 FROZEN = FREEZE_REQ (the classic machine is not modelled) */
uint8_t sv_read(uint32_t a);
/* REV $07 sound page: POKEY 2 ($DB00-$DB0F) and 4 DACs ($DB10-$DB13), write only, taken
 * only while FREEZE_REQ is set */
void    sound_write(uint32_t a, uint8_t v);
void    sv_write(uint32_t a, uint8_t v);
void    sys_raise_irq(uint8_t bits);
void    sys_raise_nmi(uint8_t bits);    /* bit 0 SYSTEM_KEY, bit 1 WATCHDOG */
void    sys_nmi_line(void);             /* re-evaluate the NMI line after a status/hold change */
uint8_t  sys_irq_now(void);             /* IRQ_STATUS as read: latched bits | live IOP level */
uint64_t sys_next_event(void);          /* CPU cycle of the next timer/watchdog event */

#endif
