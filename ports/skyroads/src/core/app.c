#include <assert.h>
#include <string.h>

#include "core/app.h"
#include "core/dos_render_tables.h"
#include "platform.h"

/* The game's tick is the timer ISR's: PIT divisor 0x19E4 = 180.02 Hz, and the tick
 * counter ds:0x160c is bumped on 2 of every 10 interrupts (@0x3b06-0x3b14) = 36 Hz. */
#define TICKS_PER_SECOND 36u

/* ---- intro sequence (EXE routine @0x4575) ----------------------------------
 * Every value below is a literal tick count out of the disassembly. The helpers the
 * intro uses all measure in game ticks: 0x443d waits N of them, 0x4315 spreads a
 * palette fade over N of them, and both bail out the instant ds:0x54ac (the key
 * flag) is set -- which is why one keypress runs the whole remainder out at once.
 * Order: the background fades up -> pause -> intro.snd -> pause -> the anim.lzs
 * animation -> pause -> the title wipes in -> the title flashes white and settles
 * -> five credit screens -> everything fades out and the main menu takes over. */
#define INTRO_BG_FADE_TICKS 36u       /* 0x4b72(pal, 1, 0x24) @0x4749 */
#define INTRO_PRE_SOUND_TICKS 24u     /* 0x443d(0x18)         @0x4756 */
#define INTRO_POST_SOUND_TICKS 37u    /* 0x443d(0x25)         @0x477b */
#define INTRO_ANIM_GROUP_TICKS 2u     /* ds:0x160c >= 2       @0x47b1 */
#define INTRO_PRE_TITLE_TICKS 72u     /* 0x443d(0x48)         @0x4828 */
#define INTRO_TITLE_WIPE_TICKS 18u    /* the 0x12 divisor     @0x4851 */
#define INTRO_TITLE_FLASH_TICKS 5u    /* 0x4315(.., 5)        @0x4938 */
#define INTRO_TITLE_HOLD_TICKS 9u     /* 0x443d(9)            @0x4948 */
#define INTRO_TITLE_SETTLE_TICKS 70u  /* 0x4315(.., 0x46)     @0x495a */
#define CREDIT_FADE_TICKS 50u         /* 0x4315(.., 0x32)     @0x49f6 */
#define CREDIT_HOLD_TICKS 50u         /* 0x443d(0x32)         @0x49fc */
#define INTRO_OUTRO_FADE_TICKS 36u    /* 0x4b72(pal, 0, 0x24) @0x4a95 */
/* Reaching the end of a road hands over to @0xe58, which keeps drawing and moving for
 * 0x48 ticks before the completion banner. */
#define ROAD_END_FLYOFF_TICKS 72u
/* The credit loop runs i = 2..6 (@0x4989/@0x4995) over the seven (CMAP, CMAP, PICT)
 * sets loaded after the title, so it shows intro.lzs pictures 4..8. Sets 0 and 1 are
 * loaded but never displayed, and picture 9 is never even read. */
#define CREDIT_FIRST_FRAME 4u
#define CREDIT_FRAME_COUNT 5u
#define CREDIT_FRAME_TICKS (CREDIT_FADE_TICKS * 2 + CREDIT_HOLD_TICKS)

/* Linear 0 -> 1 over `span` ticks, matching 0x4315's `100 * ticks / duration`.
 * C: kept as the pair; ramp_value() is the C++'s float. */
static Ramp ramp(unsigned elapsed, unsigned span)
{
    Ramp r;
    r.elapsed = (uint16_t)elapsed;
    r.span = (uint16_t)span;
    r.down = false;
    return r;
}
static Ramp one_minus(Ramp r)
{
    r.down = !r.down;
    return r;
}
static Ramp ramp_const(bool one)
{
    return ramp(one ? 1 : 0, 1);
}

float ramp_value(Ramp r)
{
    float v;
    if (r.span == 0)
        v = 1.0f;
    else {
        v = (float)r.elapsed / (float)r.span;
        if (v > 1.0f)
            v = 1.0f;
    }
    return r.down ? 1.0f - v : v;
}

/* Song mapping, from every call to the song loader @0x57a8 (which early-returns if
 * the requested song is already playing). Each site is identified by the asset its
 * routine loads immediately afterwards:
 *   @0x207  song 0 at startup; @0x4586 song 0 then loads intro.lzs   -> INTRO
 *   @0x4e41 song 1 then loads mainmenu.lzs                           -> MAIN MENU
 *   @0x4cfc song 1 (setmenu.lzs routine)                             -> SETTINGS
 *   @0x5174 song 1 then loads gomenu.lzs                             -> LEVEL SELECT
 *   @0x2c9  song = rand()%12 + 2, stepped by one if it would repeat the previous
 *           (PRNG @0x19c, then div 12 @0x2a4)                        -> GAMEPLAY
 * So the intro has its own song, the main menu starts "the main song" (1), that
 * keeps playing through the level select, and only starting a road changes it.
 *   songs 2..13 = the twelve in-game tracks. Gameplay picks one at RANDOM
 *                 (@0x2a4-0x2c8: index = rand % 12 + 2, and if it repeats the
 *                 previous choice it steps to (prev + 1) % 12 so the same track
 *                 never plays twice running). */
#define INTRO_SONG_INDEX 0u
#define MENU_SONG_INDEX 1u
#define GAMEPLAY_SONG_FIRST 2u
#define GAMEPLAY_SONG_COUNT 12u

static void push_audio(AudioCommands *audio, AudioCommandKind kind, unsigned value)
{
    if (audio->count < APP_MAX_AUDIO_COMMANDS) {
        audio->c[audio->count].kind = (uint8_t)kind;
        audio->c[audio->count].value = (uint8_t)value;
        audio->count++;
    }
}

static MenuCursor menu_cursor_move_by(MenuCursor cursor, int delta)
{
    const int idx = (int)menu_cursor_index(cursor) + delta;
    const int clamped = SR_CLAMP(idx, 0, 2);
    switch (clamped) {
    case 0: return MenuCursor_Start;
    case 1: return MenuCursor_Config;
    default: return MenuCursor_Help;
    }
}

static unsigned world_index_for_level(unsigned level_index)
{
    return level_index == 0 ? 0 : (level_index - 1) / 3;
}

static int8_t axis(bool negative, bool positive)
{
    if (negative && !positive) return -1;
    if (!negative && positive) return 1;
    return 0;
}

static void emit_sfx_for_events(const GameplayEvents *events, AudioCommands *audio)
{
    unsigned i;
    for (i = 0; i < events->count; ++i) {
        int sfx = -1;
        switch (events->e[i]) {
        /* RVSTACK: full call-site census of the SFX player @0x3c2 --
         * every `push 0` site arms the death timer ds:0x4578 first
         * (0x1ac5, 0x22fa, 0x27c3), so 0 = EXPLOSION; the survivable
         * wall-slide sites 0x2742/0x277f/0x280c push 2 = BUMP. The
         * earlier "bump=0, explode=2" note had these inverted, which
         * played the explosion an octave up on every wall graze.
         * bounce=1 @0x247d and refill=4 @0x1af6 were already right. */
        case GameplayEvent_ShipBumpedWall: sfx = 2; break;
        case GameplayEvent_ShipExploded: sfx = 0; break;
        case GameplayEvent_ShipBounced: sfx = 1; break;
        case GameplayEvent_ShipRefilled: sfx = 4; break;
        }
        if (sfx >= 0)
            push_audio(audio, AudioCommand_PlaySfx, (unsigned)sfx);
    }
}

/* The simulation runs in integer fixed point; this is the once-per-tick
 * boundary where the renderer's double view of the ship is produced.
 * The shadow's support surface, the EXE's way (@0xc95-0xd92): the surface
 * height is re-sampled EVERY frame at x+-7.0 units (+-0x380 raw) around the
 * ship at its current z, taking the HIGHER of the two. Jumping over a raised
 * block, the support climbs to the block top and the shadow reappears on it
 * mid-jump; the previous freeze-at-launch support kept it hidden for the
 * whole arc. A column holding a cube supports at the cube top; anything else
 * at road level. */
static int32_t shadow_support_sample(const GameplaySession *session, int32_t x_128)
{
    CellRef cell = level_get_cell_128(session->level, x_128, session->ship.z_position_fp16);
    if (cell->has_cube_height)
        return (int32_t)cell->cube_height << 7;
    return GROUND_Y_128;
}

static int32_t shadow_support_128(const GameplaySession *session)
{
    const int32_t a = shadow_support_sample(session, session->ship.x_position_128 - 0x380);
    const int32_t b = shadow_support_sample(session, session->ship.x_position_128 + 0x380);
    return SR_MAX(a, b);
}

static void build_ship_render_state(const GameplaySession *session, ShipRenderState *s)
{
    s->x_position_128 = session->ship.x_position_128;
    s->y_position_128 = session->ship.y_position_128;
    s->z_position_fp16 = session->ship.z_position_fp16;
    s->y_velocity_128 = session->ship.y_velocity_128;
    s->z_velocity_fp16 =
        session->ship.z_velocity_fp16 + session->ship.jump_o_master_velocity_delta_fp16;
    s->state = session->ship.state;
    s->is_on_ground = session->ship.is_on_ground;
    s->is_going_up = session->ship.is_going_up;
    s->support_y_128 = shadow_support_128(session);
    s->turn_input = session->last_controls.turn_input;
    s->accel_input = session->last_controls.accel_input;
    s->jump_input = session->last_controls.jump_input;
    s->has_death_frame_index = session->has_death_frame_index;
    s->death_frame_index = session->death_frame_index;
}

unsigned menu_cursor_index(MenuCursor cursor)
{
    switch (cursor) {
    case MenuCursor_Start: return 0;
    case MenuCursor_Config: return 1;
    case MenuCursor_Help: return 2;
    }
    return 0;
}

ControllerState app_input_gameplay_controls(const AppInput *in)
{
    return controller_make(axis(in->left_held, in->right_held), axis(in->down_held, in->up_held),
                           in->enter_held || in->space_held);
}

void app_init(AttractModeApp *app, const Level *levels, unsigned level_count,
              const DemoRecording *demo_recording)
{
    memset(app, 0, sizeof *app);
    assert(level_count > 0 && "AttractModeApp requires at least one level");
    app->levels_ = levels;
    app->level_count_ = level_count;
    app->mode_ = AppMode_Intro;
    app->current_level_index_ = 0;
    app->demo_level_index_ = 0;
    app->demo_recording_ = demo_recording;
    gameplay_session_init(&app->demo_session_, &levels[0]);
    gameplay_session_init(&app->gameplay_session_, &levels[0]);
    app->intro_tick_ = 0;
    app->intro_anim_group_count_ = 83;
    app->menu_idle_tick_ = 0;
    app->main_menu_cursor_ = MenuCursor_Start;
    app->help_page_ = 0;
    app->selected_world_ = 0;
    app->selected_level_ = 0;
    app->was_gameover_ = false;
    app->awaiting_advance_release_ = false;
    app->intro_song_started_ = false;
    app->intro_sample_started_ = false;
    app->menu_song_started_ = false;
}

void app_set_settings(AttractModeApp *app, unsigned input_device, unsigned sound_option)
{
    app->input_device_ = SR_MIN(input_device, 2u);
    app->sound_option_ = SR_MIN(sound_option, 1u);
}

void app_set_road_completions(AttractModeApp *app, const uint16_t counts[30])
{
    memcpy(app->road_completions_, counts, sizeof app->road_completions_);
}

/* The GOMENU cursor in the original is a single flat index 0..29 (ds:0x933e), laid
 * out as two columns of 15: the left column holds worlds 0-4 and the right worlds
 * 5-9, each world contributing three roads. Grid maths from the draw loop @0x51ce
 * and the cursor placement @0x50e3: column = idx/15, world row = (idx/3)%5,
 * road = idx%3. */
#define GO_MENU_ENTRIES 30u
#define GO_MENU_COLUMN_ENTRIES 15u
/* How long the "Road Completed" banner stays up: the EXE's delay loop is called with
 * 0x1b = 27 ticks (@0x2c90 -> 0x443d), i.e. 0.75s at the 36Hz tick. */
#define COMPLETION_MESSAGE_TICKS 27u

static unsigned go_menu_flat_index(unsigned world, unsigned road)
{
    return (world / 5) * GO_MENU_COLUMN_ENTRIES + (world % 5) * 3 + road;
}
static unsigned go_menu_world_of(unsigned flat)
{
    return (flat / GO_MENU_COLUMN_ENTRIES) * 5 + (flat / 3) % 5;
}
static unsigned go_menu_road_of(unsigned flat) { return flat % 3; }

static unsigned world_count(const AttractModeApp *app)
{
    /* Road 0 is the demo level; roads 1.. are 3 levels per world. */
    const unsigned playable = app->level_count_ > 1 ? app->level_count_ - 1 : 0;
    const unsigned worlds = (playable + 2) / 3; /* ceil */
    return worlds == 0 ? 1 : worlds;
}

static unsigned selected_road_index(const AttractModeApp *app)
{
    const unsigned road = app->selected_world_ * 3 + app->selected_level_ + 1;
    return road < app->level_count_ ? road : app->level_count_ - 1;
}

static unsigned final_credit_end_tick(const AttractModeApp *app);
static void enter_main_menu(AttractModeApp *app, AudioCommands *audio);
static void enter_select(AttractModeApp *app, AudioCommands *audio, bool switch_song);
static void start_demo(AttractModeApp *app, AudioCommands *audio);
static void restart_intro(AttractModeApp *app, AudioCommands *audio);
static void start_gameplay(AttractModeApp *app, AudioCommands *audio, bool switch_song);
static void emit_empty_tank_alarm(AttractModeApp *app, AudioCommands *audio);
static void current_render_scene(const AttractModeApp *app, RenderScene *scene);

static void tick_intro(AttractModeApp *app, AppInput input, AudioCommands *audio)
{
    /* intro.snd fires once the opening fade and its 24-tick pause are done (@0x4768),
     * and only if no key has been seen yet. */
    const unsigned sample_tick = INTRO_BG_FADE_TICKS + INTRO_PRE_SOUND_TICKS;
    if (!app->intro_song_started_) {
        push_audio(audio, AudioCommand_PlaySong, INTRO_SONG_INDEX);
        app->intro_song_started_ = true;
    }
    if (!app->intro_sample_started_ && app->intro_tick_ >= sample_tick) {
        push_audio(audio, AudioCommand_PlayIntroSample, 0);
        app->intro_sample_started_ = true;
    }
    /* ds:0x54ac is cleared once at @0x4707 and then never again until the intro
     * returns, so the first key press short-circuits every remaining stage and drops
     * straight into the main menu (where the main song starts). */
    if (app_input_skip_requested(&input)) {
        enter_main_menu(app, audio);
        return;
    }

    /* Letting the intro play out returns "no key" (@0x221), and the outer loop then
     * goes to the DEMO, not the menu -- still on song 0. Only a keypress reaches the
     * main menu and its song. */
    if (app->intro_tick_ >= final_credit_end_tick(app)) {
        start_demo(app, audio);
        return;
    }

    app->intro_tick_ += 1;
}

static void tick_main_menu(AttractModeApp *app, AppInput input, AudioCommands *audio)
{
    if (!app->menu_song_started_) {
        push_audio(audio, AudioCommand_PlaySong, MENU_SONG_INDEX);
        app->menu_song_started_ = true;
    }

    if (input.up)
        app->main_menu_cursor_ = menu_cursor_move_by(app->main_menu_cursor_, -1);
    if (input.down)
        app->main_menu_cursor_ = menu_cursor_move_by(app->main_menu_cursor_, 1);

    if (input.enter) {
        app->menu_idle_tick_ = 0;
        switch (app->main_menu_cursor_) {
        case MenuCursor_Start:
            /* Original SkyRoads flow: Start opens the world/level select
             * screen; the player picks a world before launching. */
            app->selected_world_ = 0;
            app->selected_level_ = 0;
            enter_select(app, audio, false);
            break;
        case MenuCursor_Config: app->mode_ = AppMode_SettingsMenu; break;
        case MenuCursor_Help:
            app->help_page_ = 0;
            app->mode_ = AppMode_HelpMenu;
            break;
        }
        return;
    }

    /* No idle timeout here: the main menu routine @0x4e36 never reads the tick
     * counter and never starts a demo. Attract mode is only ever reached by letting
     * the intro run out, and once a key has taken you to the menu the game stays
     * there. The port used to drop into a demo after five idle seconds. */
}

static void tick_help_menu(AttractModeApp *app, AppInput input, AudioCommands *audio)
{
    (void)audio;
    if (input.escape) {
        app->mode_ = AppMode_MainMenu;
        app->menu_idle_tick_ = 0;
        return;
    }
    if (input.enter || input.space) {
        app->help_page_ += 1;
        if (app->help_page_ >= 3) {
            app->help_page_ = 0;
            app->mode_ = AppMode_MainMenu;
        }
        app->menu_idle_tick_ = 0;
    }
}

/* Settings screen (@0x4c17). Cursor 0..4: positions 0-2 pick the input device
 * (ds:0x4526) and 3-4 the sound option (ds:0x4528). Navigation is literally the
 * EXE's (@0x4d08-0x4d9c): LEFT and RIGHT walk the five positions in a line, UP goes
 * 3 -> 0 and 4 -> 1, and DOWN goes 0 -> 3 and anything already at 3 or more to 4 --
 * so DOWN from position 1 or 2 does nothing at all. ENTER applies the highlighted
 * position, ESC leaves (and the host then saves skyroads.cfg, as @0x4da5 does). */
static void tick_settings_menu(AttractModeApp *app, AppInput input, AudioCommands *audio)
{
    if (input.escape) {
        app->mode_ = AppMode_MainMenu;
        app->menu_idle_tick_ = 0;
        return;
    }
    if (input.left && app->settings_cursor_ != 0) app->settings_cursor_ -= 1;
    if (input.right && app->settings_cursor_ < 4) app->settings_cursor_ += 1;
    if (input.up) {
        if (app->settings_cursor_ == 3) app->settings_cursor_ = 0;
        else if (app->settings_cursor_ == 4) app->settings_cursor_ = 1;
    }
    if (input.down) {
        if (app->settings_cursor_ == 0) app->settings_cursor_ = 3;
        else if (app->settings_cursor_ >= 3) app->settings_cursor_ = 4;
    }
    if (input.enter) {
        if (app->settings_cursor_ <= 2) {
            app->input_device_ = app->settings_cursor_;
        } else {
            app->sound_option_ = app->settings_cursor_ - 3;
            /* @0x4ce4: a non-zero sound option stops the music and parks the loaded
             * song at 0xFFFF, after which the loader early-returns forever. Turning
             * it back on restarts song 1 straight away. */
            if (app->sound_option_ != 0) {
                push_audio(audio, AudioCommand_StopSong, 0);
                app->menu_song_started_ = false;
            } else {
                push_audio(audio, AudioCommand_PlaySong, MENU_SONG_INDEX);
                app->menu_song_started_ = true;
            }
        }
    }
}

static void tick_go_menu(AttractModeApp *app, AppInput input, AudioCommands *audio)
{
    /* Exact navigation from the EXE (@0x52cb-0x5305), operating on the flat index:
     *   Up    idx - 1, stopping at 0
     *   Down  idx + 1
     *   Left  idx - 15, or 0 when already in the left column
     *   Right idx + 15
     * followed by a single clamp to the last entry (@0x527f). Note Up/Down walk the
     * flat list continuously, so they cross between the columns (Up from the top of
     * the right column lands on the bottom of the left one) -- and Left from the left
     * column jumps to the very first entry rather than doing nothing. */
    const unsigned entries =
        SR_MIN(GO_MENU_ENTRIES, app->level_count_ > 1 ? app->level_count_ - 1 : 1u);
    unsigned flat;
    if (input.escape) {
        enter_main_menu(app, audio);
        return;
    }
    flat = go_menu_flat_index(app->selected_world_, app->selected_level_);
    if (input.up && flat > 0) flat -= 1;
    if (input.down) flat += 1;
    if (input.left)
        flat = flat >= GO_MENU_COLUMN_ENTRIES ? flat - GO_MENU_COLUMN_ENTRIES : 0;
    if (input.right) flat += GO_MENU_COLUMN_ENTRIES;
    if (flat >= entries) flat = entries - 1;
    app->selected_world_ = go_menu_world_of(flat);
    app->selected_level_ = go_menu_road_of(flat);

    if (input.enter) {
        app->current_level_index_ = selected_road_index(app);
        start_gameplay(app, audio, true);
    }
}

static void enter_select(AttractModeApp *app, AudioCommands *audio, bool switch_song)
{
    app->mode_ = AppMode_GoMenu;
    app->menu_idle_tick_ = 0;
    if (switch_song)
        push_audio(audio, AudioCommand_PlaySong, MENU_SONG_INDEX);
}

static void tick_demo(AttractModeApp *app, AppInput input, AudioCommands *audio)
{
    GameplayFrameResult result;
    /* ESC (ds:0xbaa in the watched-scancode table, tested @0x21e9) is the only key
     * that ends a road, and it returns outcome 7. In the attract loop @0x36a-0x385
     * outcome 7 is the single case that leaves for the main menu -- which is where
     * song 1 finally starts. Every other key just lets the demo run on. */
    if (input.escape) {
        enter_main_menu(app, audio);
        return;
    }
    if (sample_demo_input_for_ship(app->demo_recording_, &app->demo_session_.ship) == 0) {
        restart_intro(app, audio);
        return;
    }
    gameplay_run_demo_frame(&app->demo_session_, app->demo_recording_, &result);
}

static void tick_gameplay(AttractModeApp *app, AppInput input, AudioCommands *audio)
{
    GameplaySession *g = &app->gameplay_session_;
    GameplayFrameResult result;
    bool dying;

    if (input.escape) {
        enter_select(app, audio, true); /* Esc -> back to level select */
        return;
    }

    /* While the ship is dying, keep simulating so the death plays out on screen:
     * a crash runs its explosion animation, and a ship that fell off the road
     * keeps falling out of view. Only then show the result. */
    dying = g->ship.state != ShipState_Alive && !gameplay_death_animation_finished(g);
    if (dying && !g->did_win) {
        gameplay_run_frame(g, app_input_gameplay_controls(&input), &result);
        emit_sfx_for_events(&result.events, audio);
        emit_empty_tank_alarm(app, audio);
        return;
    }

    /* Outer flow from the EXE (@0x339-0x3b7): the level routine returns the outcome
     * code, and dying (outcomes 1-5) loops straight back into the SAME road without
     * ever showing the menu. Only completing it (outcome 0) bumps that road's
     * completion count, steps the cursor to the next entry, and returns to the menu. */
    if (g->ship.state != ShipState_Alive) {
        /* Retry the same road, keeping the track that is already playing. */
        start_gameplay(app, audio, false);
        return;
    }

    if (g->did_win) {
        unsigned entries, flat;
        bool skipped;
        /* Completing a road prints a banner and holds it for 0x1b = 27 ticks, which a
         * keypress can cut short (EXE @0x2c62-0x2c90, delay loop @0x443d). There is no
         * "press a key to continue" -- it simply times out and returns to the menu.
         * Before any of that, the EXE flies the ship on for 0x48 = 72 ticks (@0xe58,
         * entered from @0x23ff once the end of the road is reached and the ship is
         * not dying). That loop forces y_position to 0 and keeps integrating z while
         * redrawing, so the ship dives away below the dashboard and the scenery runs
         * on for two seconds. ESC cuts it short. Only then does the banner appear. */
        if (!app->was_gameover_) {
            unsigned f;
            app->was_gameover_ = true;
            app->win_message_ticks_ = 0;
            app->road_end_ticks_ = 0;
            g->ship.y_position_128 = 0;
            f = go_menu_flat_index(app->selected_world_, app->selected_level_);
            /* @0x39c is a plain `add WORD PTR [bx], 1` -- a 16-bit counter with no
             * ceiling, so it simply wraps. Nothing reads the magnitude beyond the
             * seven-marker cap in the level select. */
            if (f < 30)
                app->road_completions_[f] = (uint16_t)(app->road_completions_[f] + 1);
        }
        if (app->road_end_ticks_ < ROAD_END_FLYOFF_TICKS && !input.escape) {
            app->road_end_ticks_ += 1;
            g->ship.z_position_fp16 += g->ship.z_velocity_fp16;
            return;
        }
        app->win_message_ticks_ += 1;
        skipped = input.enter || input.space || input.escape;
        if (app->win_message_ticks_ < COMPLETION_MESSAGE_TICKS && !skipped)
            return;

        /* Then the cursor steps to the next entry and we drop back to the level
         * select (EXE @0x39f), where the new completion marker is visible. */
        entries = SR_MIN(GO_MENU_ENTRIES, app->level_count_ > 1 ? app->level_count_ - 1 : 1u);
        flat = go_menu_flat_index(app->selected_world_, app->selected_level_) + 1;
        if (flat >= entries) flat = entries - 1;
        app->selected_world_ = go_menu_world_of(flat);
        app->selected_level_ = go_menu_road_of(flat);
        enter_select(app, audio, true);
        return;
    }

    app->was_gameover_ = false;
    gameplay_run_frame(g, app_input_gameplay_controls(&input), &result);
    emit_sfx_for_events(&result.events, audio);
}

void app_tick(AttractModeApp *app, AppInput input, AppTickResult *result)
{
    AudioCommands *audio = &result->audio_commands;
    audio->count = 0;
    switch (app->mode_) {
    case AppMode_Intro: tick_intro(app, input, audio); break;
    case AppMode_MainMenu: tick_main_menu(app, input, audio); break;
    case AppMode_HelpMenu: tick_help_menu(app, input, audio); break;
    case AppMode_SettingsMenu: tick_settings_menu(app, input, audio); break;
    case AppMode_GoMenu: tick_go_menu(app, input, audio); break;
    case AppMode_DemoPlayback: tick_demo(app, input, audio); break;
    case AppMode_Gameplay: tick_gameplay(app, input, audio); break;
    case AppMode_Boot:
        app->mode_ = AppMode_MainMenu;
        break;
    }

    /* The song loader itself refuses to do anything while the sound option is set
     * (@0x57bd), so a config with music turned off stays silent everywhere. Sound
     * effects are unaffected -- that check is only in the song loader. */
    if (app->sound_option_ != 0) {
        unsigned i, n = 0;
        for (i = 0; i < audio->count; ++i)
            if (audio->c[i].kind != AudioCommand_PlaySong)
                audio->c[n++] = audio->c[i];
        audio->count = n;
    }

    result->mode = app->mode_;
    current_render_scene(app, &result->render_scene);
}

/* The empty-tank alarm. The HUD plays SFX 3 on the rising edge of the same 4 Hz blink
 * phase that flashes the label (@0x13eb for oxygen, @0x14d4 for fuel), for as long as
 * the ship is out of that resource. */
static void emit_empty_tank_alarm(AttractModeApp *app, AudioCommands *audio)
{
    const uint8_t state = app->gameplay_session_.ship.state;
    const bool empty = state == ShipState_OutOfFuel || state == ShipState_OutOfOxygen;
    const bool phase = empty && dos_warn_blink_phase(app->gameplay_session_.frame_index_);
    if (phase && !app->warn_blink_phase_)
        push_audio(audio, AudioCommand_PlaySfx, DOS_WARN_SFX);
    app->warn_blink_phase_ = phase;
}

/* Picks the next in-game track, @0x29c-0x2c9. The randomness is real: 0x19c builds a
 * byte out of four live PIT counter reads (in al,0x40 twice then in al,0x41 twice,
 * added and xored together), so there is no seed and no sequence to reproduce. That
 * byte is taken mod 12, and if the result repeats the previous pick it steps on by
 * one, which is the only guarantee the original makes.
 *
 * The `% 12` on a 0..255 byte is left exactly as the EXE has it, bias included:
 * 256 is not a multiple of 12, so tracks 2..5 come up very slightly more often than
 * 6..13. */
static unsigned next_gameplay_song(AttractModeApp *app)
{
    unsigned pick = (unsigned)plat_random_byte() % GAMEPLAY_SONG_COUNT;
    if (pick == app->gameplay_song_pick_)
        pick = (pick + 1) % GAMEPLAY_SONG_COUNT;
    app->gameplay_song_pick_ = pick;
    return GAMEPLAY_SONG_FIRST + pick;
}

/* @0x229: an intro that returns "no key" sets the input source ds:0x9602 to 3, and
 * the outer loop then skips the main menu entirely and runs road 0 straight from
 * DEMO.REC (@0x26c). Note what is NOT there: any call to the song loader. The whole
 * attract mode plays through on song 0. */
static void start_demo(AttractModeApp *app, AudioCommands *audio)
{
    (void)audio;
    app->mode_ = AppMode_DemoPlayback;
    app->menu_idle_tick_ = 0;
    gameplay_session_init(&app->demo_session_, &app->levels_[app->demo_level_index_]);
}

/* @0x385: a demo that ends any way other than ESC jumps back to 0x219, which runs
 * the intro again -- so attract mode cycles intro, demo, intro, demo, ... The intro
 * re-requests song 0 (@0x4586), but the loader early-returns because it is already
 * playing (@0x57b1), so the music never restarts. */
static void restart_intro(AttractModeApp *app, AudioCommands *audio)
{
    app->mode_ = AppMode_Intro;
    app->intro_tick_ = 0;
    app->intro_sample_started_ = false;
    app->menu_idle_tick_ = 0;
    push_audio(audio, AudioCommand_PlaySong, INTRO_SONG_INDEX);
}

/* `switch_song` mirrors where the EXE enters the road loop. Coming from the level
 * select it falls through @0x296-0x2cc, which picks a random gameplay track; a death
 * instead jumps to 0x339, which is INSIDE the loop and past that pick -- so the track
 * carries on across every retry and only changes when you go back to the level select. */
static void start_gameplay(AttractModeApp *app, AudioCommands *audio, bool switch_song)
{
    unsigned flat, completed = 0, i;
    app->mode_ = AppMode_Gameplay;
    app->menu_idle_tick_ = 0;
    app->was_gameover_ = false;
    app->awaiting_advance_release_ = false;
    app->win_message_ticks_ = 0;
    /* "The End" replaces "Road Completed" when this road is the only one still
     * uncompleted (EXE @0x30e-0x358: count the non-zero completion entries and
     * compare against 29 while this road's own entry is still zero). */
    flat = go_menu_flat_index(app->selected_world_, app->selected_level_);
    for (i = 0; i < 30; ++i)
        if (app->road_completions_[i] != 0)
            completed += 1;
    app->current_road_is_final_ =
        flat < 30 && app->road_completions_[flat] == 0 && completed == GO_MENU_ENTRIES - 1;
    gameplay_session_init(&app->gameplay_session_, &app->levels_[app->current_level_index_]);
    if (switch_song)
        push_audio(audio, AudioCommand_PlaySong, next_gameplay_song(app));
}

static void enter_main_menu(AttractModeApp *app, AudioCommands *audio)
{
    app->mode_ = AppMode_MainMenu;
    app->menu_idle_tick_ = 0;
    app->main_menu_cursor_ = MenuCursor_Start;
    app->menu_song_started_ = false;
    push_audio(audio, AudioCommand_PlaySong, MENU_SONG_INDEX);
    app->menu_song_started_ = true;
}

/* (return_to_menu of the C++ was the same as enter_main_menu and never called) */

static unsigned intro_anim_ticks(const AttractModeApp *app)
{
    return app->intro_anim_group_count_ * INTRO_ANIM_GROUP_TICKS;
}

static void current_intro_scene(const AttractModeApp *app, IntroSequenceState *state)
{
    /* Stage boundaries, in the order the routine runs them. */
    const unsigned anim_start =
        INTRO_BG_FADE_TICKS + INTRO_PRE_SOUND_TICKS + INTRO_POST_SOUND_TICKS;
    const unsigned anim_end = anim_start + intro_anim_ticks(app);
    const unsigned wipe_start = anim_end + INTRO_PRE_TITLE_TICKS;
    const unsigned flash_start = wipe_start + INTRO_TITLE_WIPE_TICKS;
    const unsigned hold_start = flash_start + INTRO_TITLE_FLASH_TICKS;
    const unsigned settle_start = hold_start + INTRO_TITLE_HOLD_TICKS;
    const unsigned credits_start = settle_start + INTRO_TITLE_SETTLE_TICKS;
    const unsigned credits_end = credits_start + CREDIT_FRAME_TICKS * CREDIT_FRAME_COUNT;
    const unsigned t = app->intro_tick_;

    memset(state, 0, sizeof *state);
    state->tick = t;

    /* The screen fades up from black at the start and back down at the very end. */
    state->background_brightness = ramp(t, INTRO_BG_FADE_TICKS);
    if (t >= credits_end)
        state->background_brightness = one_minus(ramp(t - credits_end, INTRO_OUTRO_FADE_TICKS));

    /* Groups accumulate: whatever has been painted stays painted. */
    if (t <= anim_start)
        state->anim_groups_drawn = 0;
    else
        state->anim_groups_drawn =
            SR_MIN((t - anim_start) / INTRO_ANIM_GROUP_TICKS, app->intro_anim_group_count_);

    state->title_visible = t >= wipe_start;
    state->title_wipe = ramp_const(true);
    if (t >= wipe_start)
        state->title_wipe = one_minus(ramp(t - wipe_start, INTRO_TITLE_WIPE_TICKS));
    if (t < flash_start) {
        state->title_white = ramp_const(false);
        state->title_mix = ramp_const(false);
    } else if (t < hold_start) {
        state->title_white = ramp(t - flash_start, INTRO_TITLE_FLASH_TICKS);
        state->title_mix = ramp_const(false);
    } else if (t < settle_start) {
        state->title_white = ramp_const(true);
        state->title_mix = ramp_const(false);
    } else {
        state->title_white = one_minus(ramp(t - settle_start, INTRO_TITLE_SETTLE_TICKS));
        state->title_mix = ramp_const(true);
    }

    state->credit_mix = ramp_const(false);
    if (t >= credits_start && t < credits_end) {
        const unsigned elapsed = t - credits_start;
        const unsigned index = elapsed / CREDIT_FRAME_TICKS;
        const unsigned within = elapsed % CREDIT_FRAME_TICKS;
        state->has_credit_frame_index = true;
        state->credit_frame_index = CREDIT_FIRST_FRAME + index;
        if (within < CREDIT_FADE_TICKS)
            state->credit_mix = ramp(within, CREDIT_FADE_TICKS);
        else if (within < CREDIT_FADE_TICKS + CREDIT_HOLD_TICKS)
            state->credit_mix = ramp_const(true);
        else
            state->credit_mix =
                one_minus(ramp(within - CREDIT_FADE_TICKS - CREDIT_HOLD_TICKS, CREDIT_FADE_TICKS));
    }
}

static void build_play_scene(const AttractModeApp *app, const GameplaySession *session,
                             bool is_demo, DemoPlaybackState *state)
{
    /* floor(z * 8): an arithmetic shift of the 16.16 z. */
    const int32_t row13 = session->ship.z_position_fp16 >> 13;
    const unsigned current_row = (unsigned)(row13 > 0 ? row13 : 0);
    const unsigned current_group = current_row >> 3;
    const unsigned start_row =
        current_group >= RENDER_ROWS_BEHIND ? current_group - RENDER_ROWS_BEHIND : 0;
    const unsigned end_row =
        SR_MIN(current_group + RENDER_ROWS_AHEAD + 1, session->level->length);
    unsigned row_index;

    state->row_count = 0;
    for (row_index = start_row; row_index < end_row; ++row_index) {
        if (row_index < session->level->length) {
            state->rows[state->row_count].row_index = row_index;
            state->rows[state->row_count].cells = &session->level->cells[row_index];
            state->row_count++;
        }
    }

    state->world_index = world_index_for_level(session->level->road_index);
    state->gravity = session->level->gravity;
    state->level_length = session->level->length;
    state->frame_index = session->frame_index_;
    state->current_row = current_row;
    /* z / 65536 - current_row / 8, raw */
    state->fractional_z_fp16 = session->ship.z_position_fp16 - ((int32_t)current_row << 13);
    state->did_win = session->did_win;
    state->is_demo = is_demo;
    state->death_animation_finished = gameplay_death_animation_finished(session);
    state->is_final_road = !is_demo && app->current_road_is_final_;
    state->craft_state = session->ship.state;
    state->snapshot.x_position_128 = session->ship.x_position_128;
    state->snapshot.y_position_128 = session->ship.y_position_128;
    state->snapshot.z_position_fp16 = session->ship.z_position_fp16;
    state->snapshot.z_velocity_fp16 =
        session->ship.z_velocity_fp16 + session->ship.jump_o_master_velocity_delta_fp16;
    state->snapshot.craft_state = session->ship.state;
    state->snapshot.oxygen_remaining = session->ship.oxygen_remaining;
    state->snapshot.fuel_remaining = session->ship.fuel_remaining;
    state->snapshot.jump_o_master_in_use = session->ship.jump_o_master_in_use;
    state->snapshot.jump_o_master_velocity_delta_fp16 =
        session->ship.jump_o_master_velocity_delta_fp16;
    build_ship_render_state(session, &state->ship);
    state->road_palette = session->level->palette;
    state->road_palette_count = session->level->palette_count;
}

void app_current_demo_scene(const AttractModeApp *app, DemoPlaybackState *out)
{
    build_play_scene(app, &app->demo_session_, true, out);
}

void app_current_gameplay_scene(const AttractModeApp *app, DemoPlaybackState *out)
{
    build_play_scene(app, &app->gameplay_session_, false, out);
}

void app_current_go_menu_scene(const AttractModeApp *app, GoMenuScene *scene)
{
    const unsigned road = selected_road_index(app);
    const Level *level = &app->levels_[road];
    scene->selected_world = app->selected_world_;
    scene->selected_level = app->selected_level_;
    scene->world_count = world_count(app);
    scene->road_index = road;
    memcpy(scene->completions, app->road_completions_, sizeof scene->completions);
    scene->gravity = level->gravity;
    scene->fuel = level->fuel;
    scene->oxygen = level->oxygen;
}

static void current_render_scene(const AttractModeApp *app, RenderScene *scene)
{
    switch (app->mode_) {
    case AppMode_Intro:
        scene->tag = RenderScene_Intro;
        current_intro_scene(app, &scene->intro);
        break;
    case AppMode_MainMenu:
    case AppMode_Boot:
        scene->tag = RenderScene_MainMenu;
        scene->main_menu.selected = app->main_menu_cursor_;
        break;
    case AppMode_HelpMenu:
        scene->tag = RenderScene_HelpMenu;
        scene->help_menu.page_index = app->help_page_;
        break;
    case AppMode_SettingsMenu:
        scene->tag = RenderScene_SettingsMenu;
        scene->settings_menu.cursor = app->settings_cursor_;
        scene->settings_menu.input_device = app->input_device_;
        scene->settings_menu.sound_option = app->sound_option_;
        break;
    case AppMode_GoMenu:
        scene->tag = RenderScene_GoMenu;
        app_current_go_menu_scene(app, &scene->go_menu);
        break;
    case AppMode_DemoPlayback:
        scene->tag = RenderScene_DemoPlayback;
        app_current_demo_scene(app, &scene->play);
        break;
    case AppMode_Gameplay:
        scene->tag = RenderScene_Gameplay;
        app_current_gameplay_scene(app, &scene->play);
        break;
    }
}

static unsigned final_credit_end_tick(const AttractModeApp *app)
{
    return INTRO_BG_FADE_TICKS + INTRO_PRE_SOUND_TICKS + INTRO_POST_SOUND_TICKS +
           intro_anim_ticks(app) + INTRO_PRE_TITLE_TICKS + INTRO_TITLE_WIPE_TICKS +
           INTRO_TITLE_FLASH_TICKS + INTRO_TITLE_HOLD_TICKS + INTRO_TITLE_SETTLE_TICKS +
           CREDIT_FRAME_TICKS * CREDIT_FRAME_COUNT + INTRO_OUTRO_FADE_TICKS;
}
