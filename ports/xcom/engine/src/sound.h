/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef SOUND_H
#define SOUND_H

/* Sound effects: digitised samples from SOUNDS.PAK on a Sound Blaster
   (8-bit DMA, one effect at a time, IRQ driven), otherwise short blocking
   PC speaker effects (PIT channel 2). Music: see music.h. */

extern int g_sound_on;          /* S key in battle: effects and music */

/* Effects, in the order of tools/sound.py EFFECTS. */
enum {
    SFX_RIFLE, SFX_CANNON, SFX_LASER, SFX_PLASMA, SFX_HIT_BULLET, SFX_HIT_BEAM,
    SFX_EXPLOSION, SFX_DIE_SECTOID, SFX_DIE_SNAKEMAN, SFX_DIE_MUTON,
    SFX_DIE_ETHEREAL, SFX_DIE_MALE, SFX_DIE_FEMALE, SFX_DOOR, SFX_STEP,
    SFX_THROW, SFX_GEO_POPUP, SFX_CRAFT_CANNON, SFX_CRAFT_MISSILE,
    SFX_UFO_FIRE, SFX_UFO_HIT, SFX_UFO_CRASH, SFX_CRAFT_EXPLODE,
    SFX_BUTTON, SFX_WINDOW1, SFX_WINDOW2,       /* the interface (snd_button, snd_window) */
    /* pack format 6: the footsteps by the MCD's footstep value (snd_footstep; 2's
       first is SFX_STEP, 3's first is silent), the battle's other samples */
    SFX_STEP1A, SFX_STEP1B, SFX_STEP2B, SFX_STEP3B, SFX_STEP5A, SFX_STEP5B,
    SFX_STEP6A, SFX_STEP6B,
    SFX_FLY, SFX_EXPLOSION_BIG, SFX_UFO_DOOR, SFX_DROP, SFX_RELOAD, SFX_DIE_MECH,
    SFX_ROCKET, SFX_BLASTER,
    N_SFX
};

#define SND_NO_SB       1       /* snd_init flags: PC speaker only */
#define SND_NO_MUSIC    2
#define SND_QUIET       4       /* no sound at all */
#define SND_NO_FMSFX    8       /* no AdLib FM effects (PC speaker) */

void snd_init(int flags);       /* after timer_init; logs what it found */
void snd_shutdown(void);        /* before timer_shutdown */

/* Upper memory blocks: startup.c umb_plan finds them (the sound's UMB, its
   top the game's when umb_game; the game's other UMBs), snd_shutdown frees
   them. */
#define UMB_MORE        3
extern unsigned umb_seg, umb_paras, umb_more[UMB_MORE];
extern int g_hma_track;                /* the battle track in the HMA (xmem.c), -1 none */
extern unsigned g_hma_lo;
extern unsigned char umb_game, umb_xms, n_more, xms_entry_ok;

/* Effect sets: the samples one screen needs, loaded within the free memory
   (call after the screen's own data is loaded). */
/* The geoscape's track (GMGEO: GMGEO1 in the first month, then GMGEO1 or
   GMGEO2 at random, GeoscapeState::init). */
void snd_set_geo(void);
void snd_dogfight(int on);      /* 1: a dogfight is on (interception track) */
void snd_set_battle(int race);  /* race pack letter: S F N M E X */
void snd_free(void);            /* frees effects and music */
/* After a battle: the debriefing's tune (OpenXcom's DEBRIEF_MUSIC_GOOD and _BAD
   are both GMMARS), with the geoscape's effects; snd_set_geo after the
   debriefing. */
void snd_result(int res);
/* The start menu's GMSTORY (once, MainMenuState); a briefing's tune
   (BriefingState: kind brief.h BRIEF_*). */
void snd_story(void);
void snd_brief(int kind);

void snd_play(int sfx);         /* sample if loaded, else a speaker effect */

/* Game events. */
void snd_fire(int weapon);      /* weapon item (IT_*) */
void snd_shot(int alien);       /* weapon unknown: rifle or plasma */
void snd_hit(void);             /* impact of the last shot / geoscape alert */
void snd_kill(int alien);       /* death scream */
void snd_death(void);
void snd_explode(void);         /* the geoscape's crash; a battle's small explosion */
/* A battle's explosion (ExplosionBState): power up to 80 the small one, else
   the large one. */
void snd_blast(int power);
void snd_door(int ufo);         /* a door opens (ufo: a UFO's sliding door) */
void snd_step(void);
/* UnitWalkBState::playMovementSound: footstep f (the MCD's, 1-6; -1 none) of a
   step's first half (second 0) or its second (1); snd_fly: a flying unit's
   step (in the air, or a floater's). */
void snd_footstep(int f, int second);
void snd_fly(void);
/* The inventory and throws (OpenXcom's ITEM_THROW, ITEM_DROP, ITEM_RELOAD). */
void snd_throw(void);
void snd_drop(void);
void snd_reload(void);
/* A unit's death (UnitDieBState): its race's, a machine's (cyberdiscs,
   sectopods, tanks), a soldier's or civilian's. */
void snd_die(int alien, int mech);

/* The interface, as OpenXcom's TextButton and Window (GEO.CAT 0 and 1-3):
   snd_button when a left click presses a button (once a click, at the
   place that takes it, not where the button is drawn), snd_window when a
   window or dialog opens over a screen (one of the three pop-up sounds).
   Digital effects only (no FM or speaker stand-in), and none in a battle
   (DOS's battlescape has its own sound set, SOUND1.CAT). */
void snd_button(void);
void snd_window(void);
void snd_off(void);             /* PC speaker off */

/* Counters for the LOG option. */
extern unsigned g_sb_port, g_sb_irq, g_sb_dma, g_sb_dsp;
extern volatile unsigned g_sb_irqs, g_sb_started;

#endif
