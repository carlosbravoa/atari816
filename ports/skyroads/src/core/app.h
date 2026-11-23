/* The attract-mode state machine: intro -> menu -> gameplay/demo, plus the
 * audio-command emission and render-scene construction. `RenderScene` is a
 * payload-carrying the reference design enum; here it is a tagged struct holding the possible
 * scene payloads (DemoPlayback and Gameplay share DemoPlaybackState).
 *
 * C translation: AttractModeApp's methods are app_*() functions; its vector of levels is
 * a pointer to an array; the play scene's rows are pointers to the level's rows (the C++
 * copied them, every tick); std::optional fields have a has_ flag; the audio commands of
 * a tick are a small fixed array; the gameplay track is picked from plat_random_byte()
 * (the C++ used std::mt19937 seeded from std::random_device: the original read the PIT). */
#ifndef CORE_APP_H
#define CORE_APP_H

#include "core/gameplay.h"
#include "data/demo.h"
#include "data/level.h"
#include "data/roads.h"

typedef enum {
    AppMode_Boot,
    AppMode_Intro,
    AppMode_MainMenu,
    AppMode_HelpMenu,
    AppMode_SettingsMenu,
    AppMode_GoMenu,
    AppMode_DemoPlayback,
    AppMode_Gameplay,
} AppMode;

typedef enum {
    MenuCursor_Start,
    MenuCursor_Config,
    MenuCursor_Help,
} MenuCursor;

unsigned menu_cursor_index(MenuCursor cursor);

typedef struct {
    bool up;
    bool down;
    bool left;
    bool right;
    bool enter;
    bool escape;
    bool space;
    bool up_held;
    bool down_held;
    bool left_held;
    bool right_held;
    bool enter_held;
    bool space_held;
} AppInput;

static inline bool app_input_skip_requested(const AppInput *in)
{
    return in->enter || in->space || in->escape;
}
ControllerState app_input_gameplay_controls(const AppInput *in);

typedef enum {
    AudioCommand_PlaySong,
    AudioCommand_StopSong,
    AudioCommand_PlayIntroSample,
    AudioCommand_PlaySfx,
    AudioCommand_StopAllSamples,
} AudioCommandKind;

typedef struct {
    uint8_t kind;               /* AudioCommandKind */
    uint8_t value;              /* song/sfx index when relevant */
} AudioCommand;

#define APP_MAX_AUDIO_COMMANDS 12
typedef struct {
    AudioCommand c[APP_MAX_AUDIO_COMMANDS];
    unsigned count;
} AudioCommands;

/* The attract intro, decoded from the EXE's intro routine @0x4575. Every stage is
 * driven by the 36 Hz tick counter and every stage aborts the moment a key is seen,
 * so a keypress runs the whole remainder out in a few ticks.
 * C: each fade is kept as the ramp it is (elapsed ticks of span ticks, `ramp()` of the
 * C++, and whether it counts down: 1 - ramp) rather than as its float: the renderer
 * turns it into colours with integers that give the C++'s float results exactly. */
typedef struct {
    uint16_t elapsed;
    uint16_t span;
    bool down;                  /* the value is 1 - ramp(elapsed, span) */
} Ramp;

typedef struct {
    unsigned tick;
    /* Whole-screen palette fade (@0x4749 in, @0x4a95 out). */
    Ramp background_brightness;
    /* Animation groups painted so far. The EXE blits each group's fragments over
     * whatever is already on screen and leaves them there, so the picture builds up
     * rather than being redrawn from the background each frame. */
    unsigned anim_groups_drawn;
    bool title_visible;
    /* Fraction of each row still showing the background during the interlaced wipe
     * (@0x4844): 1 at the start, 0 once the title is fully revealed. */
    Ramp title_wipe;
    /* The title's palette pulse: white flash (@0x4938) then a slow settle onto the
     * second CMAP (@0x495a). */
    Ramp title_white;
    Ramp title_mix;
    bool has_credit_frame_index;
    unsigned credit_frame_index;
    /* Credit screens pulse between their two CMAPs the same way (@0x49f6/@0x4a2e). */
    Ramp credit_mix;
} IntroSequenceState;

typedef struct {
    int32_t x_position_128;     /* the C++ doubles, raw (gameplay.h) */
    int32_t y_position_128;
    int32_t z_position_fp16;
    int32_t y_velocity_128;
    int32_t z_velocity_fp16;
    uint8_t state;              /* ShipState */
    bool is_on_ground;
    bool is_going_up;
    /* Height of the surface under the ship (road level, or a raised block's top). */
    int32_t support_y_128;
    int8_t turn_input;
    int8_t accel_input;
    bool jump_input;
    bool has_death_frame_index;
    unsigned death_frame_index;
} ShipRenderState;

typedef struct {
    unsigned row_index;
    const LevelRow SR_FAR *cells;   /* C: the level's row (the C++ copied it) */
} RoadRenderRow;

#define RENDER_ROWS_BEHIND 3u
#define RENDER_ROWS_AHEAD 7u
#define RENDER_ROWS_MAX (RENDER_ROWS_BEHIND + RENDER_ROWS_AHEAD + 1)

typedef struct {
    unsigned world_index;
    uint16_t gravity;
    unsigned level_length;
    unsigned frame_index;
    unsigned current_row;
    int32_t fractional_z_fp16;  /* the C++'s fractional_z, raw */
    RoadRenderRow rows[RENDER_ROWS_MAX];
    unsigned row_count;
    bool did_win;
    bool is_demo;
    /* Result text waits on this so it never covers the explosion / the ship falling. */
    bool death_animation_finished;
    /* True when the completed road was the last uncompleted one: the banner then
     * reads "The End" rather than "Road Completed". */
    bool is_final_road;
    uint8_t craft_state;
    GameSnapshot snapshot;
    ShipRenderState ship;
    const RgbColor SR_FAR *road_palette; /* this road's VGA palette */
    unsigned road_palette_count;
} DemoPlaybackState;

typedef struct {
    MenuCursor selected;
} MainMenuScene;
typedef struct {
    unsigned page_index;
} HelpMenuScene;
/* The settings screen (@0x4c17). Five positions laid out as three across the top
 * (the input device) and two below (sound on/off). setmenu.lzs holds the background
 * as picture 0, the five cursor outlines as pictures 1..5, and the five "this one is
 * active" fills as pictures 6..10. */
typedef struct {
    unsigned cursor;            /* 0..4 */
    unsigned input_device;      /* ds:0x4526, 0..2 */
    unsigned sound_option;      /* ds:0x4528, 0 = music on, 1 = off */
} SettingsMenuScene;

/* World/level select shown before gameplay (uses GOMENU art + a text overlay). */
typedef struct {
    unsigned selected_world;    /* 0..9 */
    unsigned selected_level;    /* 0..2 within the world */
    unsigned world_count;
    unsigned road_index;        /* resolved road (1..30) */
    /* Times each of the 30 roads has been completed, indexed by the menu's flat
     * index (column * 15 + world_row * 3 + road). ds:0x452a is a 30-WORD array, and
     * the level select draws min(count, 7) markers. */
    uint16_t completions[30];
    uint16_t gravity;
    uint16_t fuel;
    uint16_t oxygen;
} GoMenuScene;

typedef enum {
    RenderScene_Intro,
    RenderScene_MainMenu,
    RenderScene_HelpMenu,
    RenderScene_SettingsMenu,
    RenderScene_GoMenu,
    RenderScene_DemoPlayback,
    RenderScene_Gameplay,
} RenderSceneTag;

typedef struct {
    RenderSceneTag tag;
    IntroSequenceState intro;
    MainMenuScene main_menu;
    HelpMenuScene help_menu;
    SettingsMenuScene settings_menu;
    GoMenuScene go_menu;
    DemoPlaybackState play;     /* DemoPlayback or Gameplay payload */
} RenderScene;

typedef struct {
    AppMode mode;
    RenderScene render_scene;
    AudioCommands audio_commands;
} AppTickResult;

typedef struct {
    const Level *levels_;
    unsigned level_count_;
    AppMode mode_;
    unsigned current_level_index_;
    unsigned demo_level_index_;
    const DemoRecording *demo_recording_;
    GameplaySession demo_session_;
    GameplaySession gameplay_session_;
    unsigned intro_tick_;
    unsigned intro_anim_group_count_;
    unsigned menu_idle_tick_;
    MenuCursor main_menu_cursor_;
    unsigned help_page_;
    unsigned selected_world_;
    unsigned selected_level_;
    /* Per-road completion counts (the EXE's ds:0x452a, 30 words), shown in the level
     * select as a row of small markers next to each road. */
    uint16_t road_completions_[30];
    bool was_gameover_;
    bool awaiting_advance_release_;
    /* Previous track index, so a pick can be stepped when it would repeat. */
    unsigned gameplay_song_pick_;
    unsigned win_message_ticks_;
    unsigned road_end_ticks_;
    bool current_road_is_final_;
    bool intro_song_started_;
    bool intro_sample_started_;
    bool menu_song_started_;
    unsigned settings_cursor_;
    unsigned input_device_;
    unsigned sound_option_;
    bool warn_blink_phase_;
} AttractModeApp;

void app_init(AttractModeApp *app, const Level *levels, unsigned level_count,
              const DemoRecording *demo_recording);
static inline AppMode app_mode(const AttractModeApp *app) { return app->mode_; }
void app_tick(AttractModeApp *app, AppInput input, AppTickResult *result);

void app_current_gameplay_scene(const AttractModeApp *app, DemoPlaybackState *out);
void app_current_demo_scene(const AttractModeApp *app, DemoPlaybackState *out);
void app_current_go_menu_scene(const AttractModeApp *app, GoMenuScene *out);
/* The two settings words the original keeps in skyroads.cfg: ds:0x4526 is the
 * input device and ds:0x4528 the sound option (non-zero silences the music). */
void app_set_settings(AttractModeApp *app, unsigned input_device, unsigned sound_option);
/* Number of non-empty groups in anim.lzs. The intro spends two ticks on each, so
 * the sequence length depends on the asset; the host sets this once it has loaded
 * the archive. The default is the shipped file's count. */
static inline void app_set_intro_anim_group_count(AttractModeApp *app, unsigned count)
{
    app->intro_anim_group_count_ = count;
}
void app_set_road_completions(AttractModeApp *app, const uint16_t counts[30]);

/* the fades' values, as the C++ computed them: ramp(elapsed, span) or 1 - that, a float */
float ramp_value(Ramp r);

#endif
