#include <stdio.h>
#include <string.h>

#include "renderer/renderer.h"
#include "core/dos_font.h"
#include "core/dos_render_tables.h"
#include "platform.h"

#define DASHBOARD_TOP 138u
#define HORIZON_Y 24u
#define VIEW_BOTTOM_Y DASHBOARD_TOP
#define SHIP_SCALE 1u
/* intro.lzs picture 1 is the SKYROADS title (320x54 at y = 32). */
#define INTRO_TITLE_FRAME 1u

/* setmenu.lzs layout: 0 = background, 1..5 = cursor outlines, 6..10 = active markers. */
#define SETTINGS_POSITIONS 5u
#define SETTINGS_CURSOR_FIRST_FRAME 1u
#define SETTINGS_MARKER_FIRST_FRAME 6u

unsigned long renderer_span_count, renderer_span_pixels;

/* Gauge levels, straight out of the HUD update.
 * Fuel and oxygen: a full tank is 0x7530 and the bar has ten segments, so the level
 * is `(remaining + 0xBB7) / 0xBB8` capped at ten (@0x130a-0x1323, @0x13f3-0x140c) --
 * any non-empty fraction of a segment lights it.
 * C: from the raw tank (the C++ took remaining / 0x7530 as a double and multiplied it
 * back: lround of it is the raw value again). */
static unsigned tank_gauge_level(int32_t remaining_raw)
{
    const int32_t remaining = SR_CLAMP(remaining_raw, 0, 0x7530);
    return SR_MIN((unsigned)(remaining + 0xBB7) / 0xBB8u, 10u); /* (16 bits) */
}

/* Speed: the 34-segment ring is `z_velocity / 0x141` capped at 34 (@0x127d-0x1296),
 * computed on the raw 1/65536 velocity. (C: given raw.) */
static unsigned speed_gauge_level(int32_t raw)
{
    if (raw <= 0)
        return 0;
    if (raw <= 0xFFFF)
        return SR_MIN((unsigned)raw / 0x141u, 34u); /* (16 bits) */
    return (unsigned)SR_MIN(raw / 0x141, 34);
}

#define SHIP_SCREEN_X 160
#define SHIP_SCREEN_Y 84

static const unsigned DOS_LEFT_CELL_COLUMNS[4] = {0, 1, 2, 3};
static const unsigned DOS_RIGHT_CELL_COLUMNS[4] = {6, 5, 4, 3};

static unsigned sat_sub(unsigned a, unsigned b) { return a > b ? a - b : 0; }
static uint8_t sat_add_u8(uint8_t a, uint8_t b)
{
    const unsigned s = (unsigned)a + b;
    return s > 255 ? 255 : (uint8_t)s;
}

/* round half away from zero of value / denominator (denominator > 0): std::lround of the
 * C++'s exact doubles. C: by 128 a shift, by 5888 = 128 * 46 a shift and a 16-bit
 * divide (nested floors): no 32-bit divide (a call of 1,000 cycles) in the frame. */
static int32_t round_div128(int32_t value)
{
    return value >= 0 ? (value + 64) >> 7 : -((-value + 64) >> 7);
}

static int32_t round_div5888(int32_t value)
{
    const int32_t m = value >= 0 ? value : -value;
    const uint32_t v = (uint32_t)m + 2944;
    int32_t q;
    if (v < ((uint32_t)65535 << 7))
        q = (int32_t)((uint16_t)(v >> 7) / 46u);
    else
        q = (int32_t)(v / 5888);
    return value >= 0 ? q : -q;
}

/* ---- the fades: the C++'s float arithmetic, in integers --------------------------
 * scale_brightness(v, b) = clamp(round(v * b)) and lerp_color's lround(a + (b - a) * t)
 * with b or t = ramp(e, s) = e / s (or 1 - e / s) in floats. The exact value is N / s for
 * an integer N; when it is not a half (k + 1/2), it is at least 1 / (2s) from one, far
 * more than the floats' error (about 255 * 2^-23), so rounding N / s as integers gives
 * the float's answer. At an exact half the float may land either side: there the C++'s
 * float expression itself is evaluated (IEEE single precision, as on a PC). Checked for
 * every argument the game uses against the float code (host test `fadecheck`). */
static float ramp_f(Ramp r) { return ramp_value(r); }

/* the ramp as a fraction num / den (0 <= num <= den) */
static void ramp_frac(Ramp r, int32_t *num, int32_t *den)
{
    int32_t n, d;
    if (r.span == 0) {
        n = 1;
        d = 1;
    } else {
        n = r.elapsed > r.span ? r.span : r.elapsed;
        d = r.span;
    }
    if (r.down)
        n = d - n;
    *num = n;
    *den = d;
}

static float roundf_away(float x)
{
    /* std::round on a float: half away from zero (x >= 0 here) */
    float f = (float)(int32_t)x;
    if (x - f >= 0.5f)
        f += 1.0f;
    return f;
}

static uint8_t scale_brightness_ch(uint8_t v, Ramp brightness)
{
    int32_t num, den, n2;
    ramp_frac(brightness, &num, &den);
    n2 = 2 * (int32_t)v * num;                  /* 2 * v * b, over den */
    if (n2 % (2 * den) == den) {                /* an exact half: the C++'s floats */
        float b = SR_CLAMP(ramp_f(brightness), 0.0f, 1.35f);
        float s = SR_CLAMP(roundf_away((float)v * b), 0.0f, 255.0f);
        return (uint8_t)s;
    }
    return (uint8_t)SR_CLAMP((n2 + den) / (2 * den), 0, 255);
}

static RgbColor scale_brightness(RgbColor color, Ramp brightness)
{
    return rgb(scale_brightness_ch(color.r, brightness), scale_brightness_ch(color.g, brightness),
               scale_brightness_ch(color.b, brightness));
}

/* Straight linear interpolation between two palette entries, as the intro's palette
 * fader does byte-wise (@0x43d8-@0x440f). */
static uint8_t lerp_ch(uint8_t a, uint8_t b, Ramp t)
{
    int32_t num, den, n2;
    ramp_frac(t, &num, &den);
    n2 = 2 * ((int32_t)a * den + ((int32_t)b - a) * num);   /* 2 * (a + (b - a) t), over den */
    if (n2 % (2 * den) == den) {
        float tf = SR_CLAMP(ramp_f(t), 0.0f, 1.0f);
        float fa = (float)a, fb = (float)b;
        float x = fa + (fb - fa) * tf;
        return (uint8_t)(int32_t)roundf_away(x);
    }
    return (uint8_t)((n2 + den) / (2 * den));
}

static RgbColor lerp_color(RgbColor from, RgbColor to, Ramp t)
{
    return rgb(lerp_ch(from.r, to.r, t), lerp_ch(from.g, to.g, t), lerp_ch(from.b, to.b, t));
}

/* ---- internal geometry structs (referenced by ReferenceRenderer methods) --- */

typedef enum { DosRenderSide_Left, DosRenderSide_Right } DosRenderSide;

typedef struct {
    uint8_t byte0;
    uint8_t byte1;
} RoadCellBytes;

/* (C: the cells' bytes come from the row's descriptors, copied near once a pass) */
#define SET_CELL_BYTES(b, raw) ((b).byte0 = (uint8_t)(raw), (b).byte1 = (uint8_t)((raw) >> 8))
#define low_nibble(b) ((uint8_t)((b).byte0 & 0x0F))
#define high_nibble(b) ((uint8_t)((b).byte0 >> 4))
#define dispatch_kind(b) ((unsigned)((b).byte1 & 0x0F))

typedef enum { DosRoadPhase_BeforeShip, DosRoadPhase_AfterShip } DosRoadPhase;

typedef struct {
    RoadCellBytes current;
    RoadCellBytes inward;
    RoadCellBytes nearer;
} DosCellContext;

/* the record a pass draws from, with its clipped spans, and the shapes it drew so far
 * (C: drawn together, in order, by FbOps.span_jobs; the pointer row's entries copied
 * near) */
#define PASS_JOBS 256     /* (C, round 2: was 512; a pass flushes when full; the main bank is tight) */
typedef struct {
    const TrekdatRecord SR_FAR *record;
    const PreparedShape SR_FAR *prepared;
    unsigned shape_count;
    uint16_t ptr[TREKDAT_POINTER_COLUMNS];  /* the pointer row's shapes */
    FrameBuffer320x200 *frame;
    SpanJob jobs[PASS_JOBS];
    unsigned njobs;
} PassRecord;

static void pass_flush(PassRecord *rec)
{
    if (rec->njobs) {
        /* (C, round 2: no wait here for the frame's restores: span_jobs waits for them if it
         * draws by the CPU; a blitter's list keeps the order by itself) */
        fb_ops.span_jobs(rec->frame, rec->jobs, rec->njobs);
        rec->njobs = 0;
    }
}

/* PrimitiveCursor { std::optional<uint16_t> next_offset; }: a shape index. C: its
 * methods are macros over a local `cursor` (a call each was most of the pass's time on
 * the 65816). The next shape is the next index (the shapes are consecutive) until the
 * record's last (trekdat_next_shape). */
#define CURSOR_AT(k) (cursor = rec->ptr[cell_pointers + (k)])
#define CURSOR_NEXT(i) ((unsigned)(i) + 1 < rec->shape_count ? (uint16_t)((i) + 1) : TREKDAT_NO_SHAPE)
#define CURSOR_SKIP() do { if (cursor != TREKDAT_NO_SHAPE) cursor = CURSOR_NEXT(cursor); } while (0)
#define EMIT(has_override, color) do { if (cursor != TREKDAT_NO_SHAPE) { \
        const uint16_t idx_ = cursor; cursor = CURSOR_NEXT(idx_); \
        emit(rec, idx_, side, (has_override), (color)); } } while (0)

static uint8_t nonzero_or(uint8_t value, uint8_t fallback)
{
    return value == 0 ? fallback : value;
}

/* ---- gameplay DAC layout ---------------------------------------------------
 * The gameplay palette is a perfect 256-slot partition, recovered from the CMAP
 * sizes and the base the EXE loads DASHBRD.LZS at (0x5C, @0x5589): ROADS.LZS
 * ships 72 road colours per level, CARS.LZS 20, DASHBRD.LZS 50, and every
 * WORLDn.LZS backdrop 114 -- 72 + 20 + 50 + 114 = 256 exactly. The road band
 * starting at 0 means a road pixel's framebuffer byte IS its shade code, which
 * is what lets the ship-shadow blit remap indices in place (@0x3437). */
#define PAL_ROAD_BASE 0x00u  /* 0x00..0x47 road palette */
#define PAL_CARS_BASE 0x48u  /* 0x48..0x5B ship sprites */
#define PAL_DASH_BASE 0x5Cu  /* 0x5C..0x8D dashboard */
#define PAL_WORLD_BASE 0x8Eu /* 0x8E..0xFF world backdrop */

/* ---- intro / menu DAC layout -----------------------------------------------
 * Each screen's art keeps its CMAP in its own band, so the intro's palette
 * animation on the title band can never touch backdrop or anim pixels. */
#define PAL_INTRO_BACKDROP_BASE 0x00u /* intro.lzs pic 0 (38) */
#define PAL_INTRO_ANIM_BASE 0x26u     /* anim.lzs shared CMAP (102) */
#define PAL_INTRO_TITLE_BASE 0x8Cu    /* intro.lzs pic 1 (80) */
#define PAL_INTRO_CREDIT_BASE 0xDCu   /* current credit pic (<= 12) */
#define PAL_MENU_ART_BASE 0xDCu       /* mainmenu.lzs cursor art (3) */
/* setmenu.lzs pics 1..10 are 3-colour overlays; 3 slots each after the 34-colour
 * background band. */
#define PAL_SETTINGS_OVERLAY_BASE 0x22u
#define PAL_GOMENU_MARK_BASE 0xD4u /* gomenu pic 1 (10), after pic 0 (212) */
#define PAL_GOMENU_CURSOR 0xDEu    /* our selection outline colour */

/* ---- palette band assembly ------------------------------------------------- */

static unsigned pal_band_capacity(unsigned base, unsigned want)
{
    return SR_MIN(want, 256u - base);
}

static void pal_band_fill(Palette256 *pal, unsigned base, const RgbColor SR_FAR *colors,
                          unsigned n)
{
    const unsigned count = pal_band_capacity(base, n);
    unsigned i;
    for (i = 0; i < count; ++i)
        pal->colors[base + i] = colors[i];
}

static void pal_band_brightness(Palette256 *pal, unsigned base, const RgbColor SR_FAR *colors,
                                unsigned n, Ramp brightness)
{
    const unsigned count = pal_band_capacity(base, n);
    unsigned i;
    for (i = 0; i < count; ++i)
        pal->colors[base + i] = scale_brightness(colors[i], brightness);
}

/* The intro picture's palette animation, applied to its band exactly as the DOS
 * build reprograms the DAC over the fixed screen: `mix` slides from the frame's
 * first CMAP to its second (@0x43d8-@0x440f), `white` flashes the result out to
 * full intensity (@0x4938), and the whole band then rides the master brightness
 * fade. Same float ops, same order, as the RGBA-era per-pixel path. */
static void pal_band_intro(Palette256 *pal, unsigned base, const ImageFrame SR_FAR *fragment,
                           Ramp mix, Ramp white, Ramp brightness)
{
    const unsigned count = pal_band_capacity(base, fragment->palette.color_count);
    unsigned i;
    for (i = 0; i < count; ++i) {
        RgbColor color = fragment->palette.colors[i];
        if (i < fragment->palette_start.color_count)
            color = lerp_color(fragment->palette_start.colors[i], color, mix);
        color = lerp_color(color, rgb(252, 252, 252), white);
        pal->colors[base + i] = scale_brightness(color, brightness);
    }
}

/* Both rasterizers translate the strip's shade byte through DS:0x0322 before it ever
 * reaches the palette, and they read different bytes of the entry: the forward pass
 * that draws the left half takes byte 0, the reverse pass that mirrors it onto the
 * right half takes byte 1. Byte 1 lifts the wall shades 0x1F..0x2D into a separate
 * 0x2E..0x3C band, so the two halves of a wall or tube are genuinely different
 * colours -- the shade the port used to be missing. */
static uint8_t dos_shade_to_palette(uint8_t shade, DosRenderSide side)
{
    if (shade >= DOS_SHADE_LUT_SIZE)
        return shade;
    return side == DosRenderSide_Left ? DOS_SHADE_LUT_FORWARD[shade] : DOS_SHADE_LUT_REVERSE[shade];
}

/* draw_dos_shape + draw_trekdat_span: the shape's spans, clipped at load (PreparedSpan).
 * The road band starts at slot 0, so the written byte doubles as the shade
 * the ship's shadow reads back and remaps.
 * PrimitiveCursor::emit: the shape's colour (or the override), through the side's
 * shade table. (C: the shape goes on the pass's list.) */
static void emit(PassRecord *rec, uint16_t idx, DosRenderSide side, bool has_override,
                 uint8_t override_color_code)
{
    const PreparedShape SR_FAR *shape = &rec->prepared[idx];
    uint8_t shade;
    SpanJob *job;
    /* RVSTACK: decode-once lookup -- this used to parse the raw shape stream
     * (twice) for every shape of every frame; see TrekdatRecord::shape_ref.
     * (C: a shape without spans, or with none left in the road band, draws nothing) */
    if (shape->count == 0)
        return;
    shade = has_override ? override_color_code : shape->color;
    if (rec->njobs == PASS_JOBS)
        pass_flush(rec);
    job = &rec->jobs[rec->njobs++];
    job->shape = shape;
    job->index = (uint8_t)(PAL_ROAD_BASE + dos_shade_to_palette(shade, side));
    job->right = side == DosRenderSide_Right;
    renderer_span_count += shape->count;
}

/* ---- the scene's rows ---- */

static const LevelRow EMPTY_ROW; /* empty_row(): seven LevelCell::empty() */

static const LevelRow SR_FAR *scene_row(const DemoPlaybackState *scene, int32_t row_index)
{
    unsigned i;
    if (row_index < 0)
        return &EMPTY_ROW;
    for (i = 0; i < scene->row_count; ++i)
        if (scene->rows[i].row_index == (unsigned)row_index)
            return scene->rows[i].cells;
    return &EMPTY_ROW;
}

/* ---- ship visual helpers ---------------------------------------------------
 * C: from the raw ship (the C++'s doubles were these / 128 exactly; each floor, round
 * and compare below is the same on the integers) */

static int32_t dos_ship_lane_index(int32_t x_128)
{
    const int32_t coarse_x = x_128 >> 7; /* floor(x) */
    /* (C: a 16-bit divide when it fits: the same truncation) */
    const int32_t d = coarse_x - 95;
    const int32_t q = d >= -32768 && d <= 32767 ? (int32_t)((int)d / 46) : d / 46;
    return SR_CLAMP(q, 0, 6);
}

static int32_t dos_ship_vertical_state(const DemoPlaybackState *scene)
{
    const int32_t SHIP_RISE_THRESHOLD_128 = 0x163;
    if (scene->ship.y_position_128 < GROUND_Y_128 || scene->ship.z_position_fp16 < 0)
        return 2;
    if (scene->ship.y_velocity_128 <= -SHIP_RISE_THRESHOLD_128)
        return 2;
    if (scene->ship.y_velocity_128 >= SHIP_RISE_THRESHOLD_128)
        return 1;
    return 0;
}

DerivedShipVisualState derive_ship_visual_state(const DemoPlaybackState *scene)
{
    static const int thrust_cycle[4] = {0, 1, 2, 1};
    const int32_t lane_index = dos_ship_lane_index(scene->ship.x_position_128);
    DerivedShipVisualState v;
    int32_t vertical_state, ship_lane_bias;

    memset(&v, 0, sizeof v);
    if (lane_index < 3)
        v.bank = ShipBank_Left;
    else if (lane_index == 3)
        v.bank = ShipBank_Center;
    else
        v.bank = ShipBank_Right;

    /* Death animations (EXE @0xc02, re/NOTES.md Update 9): only a CRASH runs the
     * explosion counter ds:0x4578. Falling off the road / running out of fuel or
     * oxygen leave it at 0, so the normal flight pose keeps being drawn while the
     * ship falls away -- there is no explosion for those. */
    v.sprite_kind = scene->ship.state == ShipState_Exploded ? ShipSpriteKind_Exploding
                                                            : ShipSpriteKind_Alive;

    /* y > GROUND_Y + 0.5 */
    v.jumping = scene->ship.y_position_128 > GROUND_Y_128 + 64 || scene->ship.is_going_up ||
                !scene->ship.is_on_ground || scene->ship.jump_input;
    vertical_state = dos_ship_vertical_state(scene);
    /* lane_bias = (x - LEVEL_CENTER_X) / LEVEL_TILE_STRIDE_X, rounded * 30:
     * round((x_128 - 0x8000) * 30 / (128 * 46)) */
    ship_lane_bias = round_div5888((scene->ship.x_position_128 - LEVEL_CENTER_X_128) * 30);
    v.ship_screen_bias_x = SR_CLAMP(ship_lane_bias, -96, 96);
    /* Altitude maps 1:1 to screen pixels, with no scaling and no clamp. The EXE
     * passes the ship's height to the renderer as ds:0xe38 = y_raw/0x80 (i.e. y in
     * world units, @0xd3a/0xdc5) and the ship blit puts the sprite's top row at
     * 0x9D - ds:0xe38 = 157 - y (@0x324e-0x325a). A scaled/clamped offset makes the
     * ship sink into raised roads and understates jump height. */
    v.vertical_offset_y = round_div128(-(scene->ship.y_position_128 - GROUND_Y_128));

    v.explosion_frame = 0;
    if (scene->ship.has_death_frame_index)
        v.explosion_frame = sat_sub(scene->frame_index, scene->ship.death_frame_index) / 3;

    /* Exact DOS pose formula (re/NOTES.md, wrapper @0xbe3/0xc93):
     *   sprite = (lane*3 + vstate)*3 + 14 + thrust ; our exact_ship_frames array
     *   is based at sprite 14, so the array index drops the +14. thrust is the
     *   engine-flicker animation (added later); 0 gives the static pose. */
    if (v.sprite_kind == ShipSpriteKind_Alive) {
        const int32_t vs = SR_CLAMP(vertical_state, 0, 2);
        /* Thrust flicker: table ds:0xea = {0,1,2,1}, cycled by (frame/2)%4. With
         * no fuel the EXE forces the thrust value to 0 (engine flame off, @0xc26). */
        const int thrust = scene->ship.state == ShipState_OutOfFuel
                               ? 0
                               : thrust_cycle[(scene->frame_index / 2) % 4];
        v.has_exact_ship_frame_index = true;
        v.exact_ship_frame_index = (unsigned)((lane_index * 3 + vs) * 3 + thrust);
    }

    v.thrust_on = scene->ship.accel_input > 0 && scene->ship.state == ShipState_Alive;
    v.support_y_128 = scene->ship.support_y_128;
    v.on_surface = scene->ship.is_on_ground && scene->ship.state == ShipState_Alive;
    v.casts_shadow = scene->ship.state == ShipState_Alive;
    /* ds:0xe40 (@0xd71-0xda4): the ship's height above the surface holding it up, in
     * whole world units. scene_draw divides it by five to choose the silhouette. */
    v.hover_units = (scene->ship.y_position_128 - scene->ship.support_y_128) >> 7;
    return v;
}

/* Exact DOS screen-X (re/NOTES.md, wrapper @0xe01 + blit @0x325c): the sprite's
 * left edge = x_position - 110 + lane_adj, a 1:1 world->screen mapping (1 px per
 * world unit, no compression, no clamp). Our sprite is 30 wide, so the centre is
 * (x_position - 110 + adj) + 15 = x_position - 95 + adj. This makes the ship's
 * visual position match the simulation exactly, so collisions line up and it can
 * travel the full lane range. */
static ShipScreenPlacement ship_screen_placement(const DemoPlaybackState *scene,
                                                 const DerivedShipVisualState *visual)
{
    static const int lane_adj[7] = {-1, -1, -1, 0, 1, 2, 4};
    const int32_t lane = dos_ship_lane_index(scene->ship.x_position_128);
    const int32_t x_rounded = round_div128(scene->ship.x_position_128);
    const int32_t center_x = x_rounded - 95 + lane_adj[lane];
    /* Exact DOS screen-Y: sprite top row = 157 - y (blit @0x324e), and our sprite
     * is 24 tall, so centre = 157 - y + 12 = 169 - y. At ground level (y = 80) that
     * is 89 = SHIP_SCREEN_Y + 5, and vertical_offset_y carries the exact 1:1
     * altitude delta from there. */
    const int32_t sprite_center_y = SHIP_SCREEN_Y + 5 + visual->vertical_offset_y;
    /* The shadow stays on whatever surface is holding the ship up, using the same
     * 1:1 mapping, so it does not detach on roads made of raised blocks. */
    const int32_t surface_offset_y = round_div128(-(visual->support_y_128 - GROUND_Y_128));
    ShipScreenPlacement p;
    p.sprite_center_x = center_x;
    p.sprite_center_y = sprite_center_y;
    p.shadow_center_x = center_x;
    p.shadow_center_y = SHIP_SCREEN_Y + 18 + surface_offset_y;
    /* Blit corner, exactly as the DOS ship blit computes it. */
    p.sprite_left_x = x_rounded + lane_adj[lane] - 110;
    p.sprite_top_y = sprite_center_y - 12;
    return p;
}

static void stroke_rect(FrameBuffer320x200 *frame, int32_t x, int32_t y, int32_t w, int32_t h,
                        uint8_t index)
{
    if (w <= 0 || h <= 0)
        return;
    fb_fill_rect(frame, x, y, w, 1, index);
    fb_fill_rect(frame, x, y + h - 1, w, 1, index);
    fb_fill_rect(frame, x, y, 1, h, index);
    fb_fill_rect(frame, x + w - 1, y, 1, h, index);
}

/* ---- DOS TREKDAT road pass ------------------------------------------------- */

/* cell_pointers: the cell's first entry in the pointer row (cell_pointers.pointers[k] of
 * the C++ is rec->ptr[cell_pointers + k]) */
#define DRAW_ARGS PassRecord *rec, unsigned cell_pointers, const DosCellContext *context, \
                  DosRenderSide side

static void draw_dos_type_0(DRAW_ARGS)
{
    const uint8_t base_color = low_nibble(context->current);
    uint16_t cursor;
    if (base_color == 0)
        return;

    CURSOR_AT(0);
    EMIT(true, base_color);
    if (low_nibble(context->inward) == 0)
        EMIT(true, sat_add_u8(base_color, 0x1E));
    else
        CURSOR_SKIP();
    if (low_nibble(context->nearer) == 0)
        EMIT(true, sat_add_u8(base_color, 0x0F));
}

static void draw_dos_type_1(DRAW_ARGS)
{
    uint16_t cursor;
    int i;
    draw_dos_type_0(rec, cell_pointers, context, side);
    if (context->nearer.byte1 < 1) {
        CURSOR_AT(1);
        EMIT(true, 0x43);
    }
    CURSOR_AT(4);
    for (i = 0; i < 6; ++i)
        EMIT(false, 0);
    if (context->nearer.byte1 < 1)
        for (i = 0; i < 2; ++i)
            EMIT(false, 0);
}

static void draw_dos_type_2(DRAW_ARGS)
{
    uint16_t cursor;
    uint8_t override_color;
    draw_dos_type_0(rec, cell_pointers, context, side);
    if (context->nearer.byte1 < 2) {
        CURSOR_AT(3);
        EMIT(false, 0);
    }
    override_color = nonzero_or(high_nibble(context->current), 0x3D);
    CURSOR_AT(2);
    EMIT(true, override_color);
    if (context->inward.byte1 < 2)
        EMIT(false, 0);
}

static void draw_dos_type_3(DRAW_ARGS)
{
    uint16_t cursor;
    uint8_t override_color;
    draw_dos_type_0(rec, cell_pointers, context, side);
    if (context->nearer.byte1 < 2) {
        CURSOR_AT(1);
        EMIT(true, 0x41);
    }
    override_color = nonzero_or(high_nibble(context->current), 0x3D);
    CURSOR_AT(2);
    EMIT(true, override_color);
    if (context->inward.byte1 < 2)
        EMIT(false, 0);
    if (context->nearer.byte1 < 2) {
        CURSOR_AT(3);
        CURSOR_SKIP();
        EMIT(false, 0);
        EMIT(false, 0);
    }
}

static void draw_dos_type_4(DRAW_ARGS)
{
    uint16_t cursor;
    uint8_t override_color;
    draw_dos_type_0(rec, cell_pointers, context, side);
    if (context->nearer.byte1 < 2) {
        CURSOR_AT(3);
        EMIT(false, 0);
    }
    CURSOR_AT(2);
    CURSOR_SKIP();
    if (context->inward.byte1 < 2)
        EMIT(false, 0);
    override_color = nonzero_or(high_nibble(context->current), 0x3D);
    CURSOR_AT(5);
    EMIT(true, override_color);
    if (context->inward.byte1 < 4)
        EMIT(false, 0);
    else
        CURSOR_SKIP();
    if (context->nearer.byte1 < 4)
        EMIT(false, 0);
}

static void draw_dos_type_5(DRAW_ARGS)
{
    uint16_t cursor;
    uint8_t override_color;
    draw_dos_type_0(rec, cell_pointers, context, side);
    if (context->nearer.byte1 < 2) {
        CURSOR_AT(1);
        EMIT(true, 0x41);
    }
    CURSOR_AT(2);
    CURSOR_SKIP();
    if (context->inward.byte1 < 2)
        EMIT(false, 0);
    if (context->nearer.byte1 < 2) {
        CURSOR_AT(3);
        CURSOR_SKIP();
        EMIT(false, 0);
        EMIT(false, 0);
    }
    override_color = nonzero_or(high_nibble(context->current), 0x3D);
    CURSOR_AT(5);
    EMIT(true, override_color);
    if (context->inward.byte1 < 4)
        EMIT(false, 0);
    else
        CURSOR_SKIP();
    if (context->nearer.byte1 < 4)
        EMIT(false, 0);
}

static void draw_dos_cell(DRAW_ARGS)
{
    switch (dispatch_kind(context->current)) {
    case 0: draw_dos_type_0(rec, cell_pointers, context, side); break;
    case 1: draw_dos_type_1(rec, cell_pointers, context, side); break;
    case 2: draw_dos_type_2(rec, cell_pointers, context, side); break;
    case 3: draw_dos_type_3(rec, cell_pointers, context, side); break;
    case 4: draw_dos_type_4(rec, cell_pointers, context, side); break;
    case 5: draw_dos_type_5(rec, cell_pointers, context, side); break;
    default: break;
    }
}

/* pointer_row: the pointer table's row (TrekdatDosPointerLayout's rows[i]: its cell s
 * is entries row * 24 + s * 6 .. + 5); the rows' descriptors (C: copied near) */
static void draw_dos_pointer_row(PassRecord *rec, unsigned pointer_row,
                                 const uint16_t SR_FAR *current_row,
                                 const uint16_t SR_FAR *nearer_row)
{
    unsigned side_i, k;
    const uint16_t SR_FAR *row = &rec->record->pointer_shape[pointer_row * TREKDAT_POINTER_COLUMNS];
    if (fb_ops.road_row) {
        /* (a platform's own version of the loop below: the same jobs) */
        if (rec->njobs + 96 > PASS_JOBS)
            pass_flush(rec);
        rec->njobs += fb_ops.road_row(row, current_row, nearer_row, rec->prepared,
                                      rec->shape_count, &rec->jobs[rec->njobs]);
        return;
    }
    for (k = 0; k < TREKDAT_POINTER_COLUMNS; ++k)
        rec->ptr[k] = row[k];
    for (side_i = 0; side_i < 2; ++side_i) {
        const DosRenderSide side = side_i == 0 ? DosRenderSide_Left : DosRenderSide_Right;
        const unsigned *columns = side_i == 0 ? DOS_LEFT_CELL_COLUMNS : DOS_RIGHT_CELL_COLUMNS;
        unsigned slot_index;
        for (slot_index = 0; slot_index < 4; ++slot_index) {
            const unsigned column_index = columns[slot_index];
            unsigned inward_index;
            DosCellContext context;
            if (side == DosRenderSide_Left)
                inward_index = SR_MIN(column_index + 1, ROAD_COLUMNS - 1);
            else
                inward_index = sat_sub(column_index, 1);
            SET_CELL_BYTES(context.current, current_row[column_index]);
            if (dispatch_kind(context.current) > 5 || (low_nibble(context.current) == 0 &&
                                                      dispatch_kind(context.current) == 0))
                continue;               /* (draws nothing: no-op kind, or type 0 without a tile) */
            SET_CELL_BYTES(context.inward, current_row[inward_index]);
            SET_CELL_BYTES(context.nearer, nearer_row[column_index]);
            draw_dos_cell(rec, slot_index * TREKDAT_DOS_POINTERS_PER_CELL, &context, side);
        }
    }
}

typedef struct {
    unsigned pointer_row_index;
    int32_t row_offset;
} RowStep;

/* the row's descriptors (an empty row: zeros, LevelCell::empty()): the level's own (C, round 2:
 * the road's rows, DemoPlaybackState.raw_rows, read where they are; a row not among the
 * scene's rows, scene_row's EMPTY_ROW) */
static const uint16_t ZERO_ROW[ROAD_COLUMNS];

static const uint16_t SR_FAR *row_raw(const DemoPlaybackState *scene, int32_t row_index)
{
    if (scene->row_count && row_index >= (int32_t)scene->rows[0].row_index &&
        row_index < (int32_t)scene->rows[0].row_index + (int32_t)scene->row_count) {
        const unsigned k = (unsigned)(row_index - (int32_t)scene->rows[0].row_index);
        if (scene->rows[k].row_index == (unsigned)row_index)    /* (always: consecutive) */
            return scene->raw_rows[(unsigned)row_index].c;
    }
    if (scene_row(scene, row_index) != &EMPTY_ROW)               /* (never) */
        return scene->raw_rows[(unsigned)row_index].c;
    return ZERO_ROW;
}

static PassRecord pass_rec;

/* C (round 2): the pass as a RoadPass (FbOps.road_prepare): its pointer rows and their level
 * rows, the record's shapes; false where draw_demo_rows would draw nothing or fail (no
 * record for the slot, a scene without rows) */
static bool make_road_pass(const Renderer *r, const DemoPlaybackState *scene, DosRoadPhase phase,
                           RoadPass *rp)
{
    static const RowStep before_seq[] = {{0, 7}, {1, 6}, {2, 5}, {3, 4},
                                         {4, 3}, {5, 2}, {6, 1}, {11, 0}};
    static const RowStep after_seq[] = {{12, 0}, {8, -1}, {9, -2}, {10, -3}};
    const unsigned slot = scene->current_row & 7;
    const int32_t current_group = (int32_t)(scene->current_row >> 3);
    const RowStep *seq = phase == DosRoadPhase_BeforeShip ? before_seq : after_seq;
    const unsigned seq_len = phase == DosRoadPhase_BeforeShip ? 8 : 4;
    const TrekdatRecord SR_FAR *record;
    unsigned i;
    if (slot >= r->assets_.trekdat.record_count || scene->row_count == 0)
        return false;
    record = &r->assets_.trekdat.records[slot];
    rp->prepared = r->prepared[slot];
    rp->pointer_shape = record->pointer_shape;
    rp->raw_rows = scene->raw_rows;
    rp->shape_count = (uint16_t)record->shape_count;
    rp->r0 = (int16_t)scene->rows[0].row_index;
    rp->rn = (int16_t)scene->row_count;
    rp->zero_row = ZERO_ROW;
    rp->n = (uint16_t)seq_len;
    rp->center = r->center[slot];
    for (i = 0; i < seq_len; ++i) {
        rp->seq[i].prow = (uint16_t)seq[i].pointer_row_index;
        rp->seq[i].row = (int16_t)(current_group + seq[i].row_offset);
    }
    return true;
}

static bool draw_dos_trekdat_pass(FrameBuffer320x200 *frame, const DemoPlaybackState *scene,
                                  const TrekdatRecord SR_FAR *record,
                                  const PreparedShape SR_FAR *prepared, DosRoadPhase phase)
{
    static const RowStep before_seq[] = {{0, 7}, {1, 6}, {2, 5}, {3, 4},
                                         {4, 3}, {5, 2}, {6, 1}, {11, 0}};
    static const RowStep after_seq[] = {{12, 0}, {8, -1}, {9, -2}, {10, -3}};
    const int32_t current_group = (int32_t)(scene->current_row >> 3);
    const RowStep *seq = phase == DosRoadPhase_BeforeShip ? before_seq : after_seq;
    const unsigned seq_len = phase == DosRoadPhase_BeforeShip ? 8 : 4;
    PassRecord *rec = &pass_rec;
    unsigned i;

    if (scene->row_count == 0)
        return false;

    rec->record = record;
    rec->prepared = prepared;
    rec->shape_count = record->shape_count;
    rec->frame = frame;
    rec->njobs = 0;
    for (i = 0; i < seq_len; ++i) {
        const int32_t row_index = current_group + seq[i].row_offset;
        draw_dos_pointer_row(rec, seq[i].pointer_row_index, row_raw(scene, row_index),
                             row_raw(scene, row_index - 1));
    }
    pass_flush(rec);
    return true;
}

/* ---- sprite atlas helpers --------------------------------------------------
 * The DOS blit reads the 24-wide sprite row-major and writes each row down a
 * screen column, i.e. sprite(row r, col c) -> screen(x = r, y = c). That is a
 * transpose (a 90deg rotation plus a horizontal flip), so the on-screen sprite
 * is `height` wide by `width` tall. Using a plain rotation instead mirrors the
 * ship and reverses its bank direction. */
static ImageFrame transpose_sprite(const ImageFrame *sprite)
{
    const unsigned width = sprite->width;   /* 24 (columns) */
    const unsigned height = sprite->height; /* 30 (rows) */
    ImageFrame out;
    unsigned r, c;
    memset(&out, 0, sizeof out);
    out.offset = sprite->offset;
    out.width = (uint16_t)height;
    out.height = (uint16_t)width;
    out.palette = sprite->palette;
    out.transparent_zero = sprite->transparent_zero;
    out.pixels = bytes_new((uint32_t)width * height);
    for (r = 0; r < height; ++r)
        for (c = 0; c < width; ++c)
            out.pixels.data[c * height + r] = sprite->pixels.data[r * width + c];
    return out;
}

/* ---- FrameBuffer ----------------------------------------------------------- */

void fb_clear(FrameBuffer320x200 *f, uint8_t index)
{
    unsigned y;
    if (fb_ops.sync)
        fb_ops.sync(f);
    for (y = 0; y < FRAMEBUFFER_HEIGHT; ++y)
        plat_fill(f->pixels + y * FRAMEBUFFER_WIDTH, index, FRAMEBUFFER_WIDTH);
}

void fb_fill_rect(FrameBuffer320x200 *f, int32_t x, int32_t y, int32_t w, int32_t h, uint8_t index)
{
    const int32_t x0 = SR_MAX(x, 0);
    const int32_t y0 = SR_MAX(y, 0);
    const int32_t x1 = SR_MAX(SR_MIN(x + w, (int32_t)FRAMEBUFFER_WIDTH), 0);
    const int32_t y1 = SR_MAX(SR_MIN(y + h, (int32_t)FRAMEBUFFER_HEIGHT), 0);
    int32_t yy;
    for (yy = y0; yy < y1; ++yy)
        if (x1 > x0)
            plat_fill(f->pixels + (unsigned)yy * FRAMEBUFFER_WIDTH + (unsigned)x0, index,
                      (unsigned)(x1 - x0));
}

void fb_set_pixel(FrameBuffer320x200 *f, unsigned x, unsigned y, uint8_t index)
{
    if (x >= FRAMEBUFFER_WIDTH || y >= FRAMEBUFFER_HEIGHT)
        return;
    f->pixels[y * FRAMEBUFFER_WIDTH + x] = index;
}

uint8_t fb_pixel_at(const FrameBuffer320x200 *f, unsigned x, unsigned y)
{
    if (x >= FRAMEBUFFER_WIDTH || y >= FRAMEBUFFER_HEIGHT)
        return 0;
    return f->pixels[y * FRAMEBUFFER_WIDTH + x];
}

/* ---- the default FbOps ---- */

static void c_spans(FrameBuffer320x200 *f, const PreparedSpan SR_FAR *spans, unsigned count,
                    bool right, uint8_t index)
{
    unsigned i;
    for (i = 0; i < count; ++i) {
        renderer_span_pixels += spans[i].width;
        plat_fill(f->pixels + (right ? spans[i].right : spans[i].left), index, spans[i].width);
    }
}

static void c_copy_rows(FrameBuffer320x200 *f, const FrameBuffer320x200 *u, unsigned y0,
                        unsigned y1)
{
    unsigned y;
    for (y = y0; y < y1; ++y)
        plat_copy(f->pixels + y * FRAMEBUFFER_WIDTH, u->pixels + y * FRAMEBUFFER_WIDTH,
                  FRAMEBUFFER_WIDTH);
}

static void c_copy_rect(FrameBuffer320x200 *f, const FrameBuffer320x200 *u, unsigned x0,
                        unsigned y0, unsigned x1, unsigned y1)
{
    unsigned y;
    for (y = y0; y < y1 && x0 < x1; ++y)
        plat_copy(f->pixels + y * FRAMEBUFFER_WIDTH + x0, u->pixels + y * FRAMEBUFFER_WIDTH + x0,
                  x1 - x0);
}

static void c_span_jobs(FrameBuffer320x200 *f, const SpanJob *jobs, unsigned n)
{
    unsigned i;
    for (i = 0; i < n; ++i)
        fb_ops.spans(f, jobs[i].shape->spans, jobs[i].shape->count, jobs[i].right != 0,
                     jobs[i].index);
}

FbOps fb_ops = {c_spans, c_span_jobs, c_copy_rows, c_copy_rect, 0, 0, 0, 0, 0, 0, 0};

static void sync_cpu(FrameBuffer320x200 *f)
{
    if (fb_ops.sync)
        fb_ops.sync(f);
}

/* ---- assets / atlas -------------------------------------------------------- */

void attract_mode_assets_load_from_root(AttractModeAssets *a, const char *source_root)
{
    attract_mode_assets_load(a, source_root, true);
}

void attract_mode_assets_load(AttractModeAssets *a, const char *source_root, bool with_trekdat)
{
    char name[16];
    unsigned index;
    memset(a, 0, sizeof *a);
#define P(n) plat_asset_path(source_root, n)
    for (index = 0; index <= 9; ++index) {
        sprintf(name, "WORLD%u.LZS", index);
        a->worlds[index] = load_image_archive_path(P(name));
    }
    a->world_count = 10;
    a->intro = load_image_archive_path(P("INTRO.LZS"));
    a->anim = load_image_archive_path(P("ANIM.LZS"));
    a->main_menu = load_image_archive_path(P("MAINMENU.LZS"));
    a->help_menu = load_image_archive_path(P("HELPMENU.LZS"));
    a->settings_menu = load_image_archive_path(P("SETMENU.LZS"));
    a->go_menu = load_image_archive_path(P("GOMENU.LZS"));
    a->cars = load_image_archive_path(P("CARS.LZS"));
    a->dashboard = load_image_archive_path(P("DASHBRD.LZS"));
    if (with_trekdat)
        a->trekdat = load_trekdat_lzs_path(P("TREKDAT.LZS"));
    a->oxygen_gauge = load_dashboard_dat_path(P("OXY_DISP.DAT"));
    a->fuel_gauge = load_dashboard_dat_path(P("FUL_DISP.DAT"));
    a->speed_gauge = load_dashboard_dat_path(P("SPEED.DAT"));
#undef P
}

/* The DOS renderer treats CARS as a flat array of fixed 24x30 (720-byte) sprites
 * indexed by pose number (block n = rows [n*30, n*30+30)). The old code split on
 * blank rows, which produced a different sprite count/boundaries and misaligned
 * every index. Extract fixed blocks to match the executable exactly. */
#define CARS_W 24u
#define CARS_H 30u

static ImageFrame cars_block(const ImageFrame SR_FAR *sheet, unsigned n)
{
    ImageFrame out;
    const uint32_t base = (uint32_t)n * CARS_H * CARS_W;
    unsigned i;
    memset(&out, 0, sizeof out);
    out.width = CARS_W;
    out.height = CARS_H;
    out.palette = sheet->palette;
    out.transparent_zero = sheet->transparent_zero;
    out.pixels = bytes_new(CARS_W * CARS_H);
    for (i = 0; i < CARS_W * CARS_H; ++i)
        out.pixels.data[i] = base + i < sheet->pixels.size ? sheet->pixels.data[base + i] : 0;
    return out;
}

/* (C: into *atlas, which the C++ returned as an optional: 3.7 KB, too much for the
 * Atari816's software stack) */
static void car_atlas_from_archive(const ImageArchive *archive, CarAtlas *atlas_out)
{
#define atlas (*atlas_out)
    const ImageFrame SR_FAR *frame;
    unsigned block_count, i;
    memset(&atlas, 0, sizeof atlas);
    if (!archive_has_frame(archive, 0))
        return;
    frame = archive_front(archive, 0);
    if (frame->width != CARS_W)
        return;
    block_count = frame->height / CARS_H; /* 77 in the shipped set */
    if (block_count < 77)
        return;
    /* Sprites 0..13 are the explosion/destroyed set (death pose = timer/3). */
    for (i = 0; i < 14; ++i) {
        ImageFrame b = cars_block(frame, i);
        atlas.explosion_frames[i] = transpose_sprite(&b);
    }
    atlas.explosion_count = 14;
    /* Sprites 14..76 are the flight poses: pose = (lane*3 + vstate)*3 + thrust,
     * with this array based at sprite 14. (C: the 63 of the shipped set) */
    for (i = 14; i < 77; ++i) {
        ImageFrame b = cars_block(frame, i);
        atlas.exact_ship_frames[i - 14] = transpose_sprite(&b);
    }
    atlas.exact_count = 63;
    atlas.destroyed = atlas.explosion_frames[13];
    atlas.valid = true;
#undef atlas
}

static const ImageFrame *car_atlas_select_sprite(const CarAtlas *atlas,
                                                 const DerivedShipVisualState *visual)
{
    switch (visual->sprite_kind) {
    case ShipSpriteKind_Exploding: {
        const unsigned index = SR_MIN(visual->explosion_frame, sat_sub(atlas->explosion_count, 1));
        return &atlas->explosion_frames[index];
    }
    case ShipSpriteKind_Destroyed:
        return &atlas->destroyed;
    case ShipSpriteKind_Alive: {
        unsigned index = visual->has_exact_ship_frame_index ? visual->exact_ship_frame_index : 0;
        index = SR_MIN(index, sat_sub(atlas->exact_count, 1));
        return &atlas->exact_ship_frames[index];
    }
    }
    return &atlas->destroyed;
}

/* ---- ReferenceRenderer ----------------------------------------------------- */

/* C: the TREKDAT spans clipped as draw_trekdat_span clips them, once */
static void prepare_record(Renderer *r, unsigned ri)
{
    const TrekdatRecord SR_FAR *record = &r->assets_.trekdat.records[ri];
    PreparedShape SR_FAR *prepared =
        (PreparedShape SR_FAR *)plat_alloc((uint32_t)SR_MAX(record->shape_count, 1) *
                                           sizeof(PreparedShape));
    unsigned s;
    for (s = 0; s < record->shape_count; ++s) {
        const TrekdatShape SR_FAR *shape = &record->shapes[s];
        PreparedSpan SR_FAR *out = 0;
        unsigned pass, n = 0, k;
        for (pass = 0; pass < 2; ++pass) {
            n = 0;
            for (k = 0; k < shape->span_count; ++k) {
                const TrekdatSpan SR_FAR *span = &shape->spans[k];
                /* (16-bit: x < 320, width < 256) */
                const int w = span->width;
                const unsigned y = span->y;
                int x, x0, x1, lx0, lx1, rx;
                if (w == 0)
                    continue;
                if (y < HORIZON_Y || y >= VIEW_BOTTOM_Y)
                    continue;
                x = (int)span->x;
                x0 = SR_MAX(x, 0);
                x1 = SR_MIN(x + w, (int)SCREEN_WIDTH);
                if (x1 <= x0)
                    continue;
                /* the mirrored span: x = 320 - x - width, clipped the same way */
                rx = (int)SCREEN_WIDTH - x - w;
                lx0 = SR_MAX(rx, 0);
                lx1 = SR_MIN(rx + w, (int)SCREEN_WIDTH);
                if (lx1 - lx0 != x1 - x0)
                    sr_fail("TREKDAT span clips differently mirrored");
                if (pass == 1) {
                    out[n].left = (uint16_t)(y * FRAMEBUFFER_WIDTH + (unsigned)x0);
                    out[n].right = (uint16_t)(y * FRAMEBUFFER_WIDTH + (unsigned)lx0);
                    out[n].width = (uint8_t)(x1 - x0);
                }
                n++;
            }
            if (pass == 0 && n)
                out = (PreparedSpan SR_FAR *)plat_alloc((uint32_t)n * sizeof(PreparedSpan));
        }
        prepared[s].spans = out;
        prepared[s].count = (uint16_t)n;
        prepared[s].color = shape->color;
    }
    r->prepared[ri] = prepared;
}

typedef struct {
    int32_t x0, y0, x1, y1;
} Box;

static Box box_of(int32_t x, int32_t y, int32_t w, int32_t h)
{
    Box b;
    b.x0 = x;
    b.y0 = y;
    b.x1 = x + w;
    b.y1 = y + h;
    return b;
}

/* C: may the dashboard band be kept (PlaySceneCache.dash)? Yes when no two gauge
 * segments draw the same pixel, and none draws inside an empty-tank label or the gravity
 * readout, all in the band: then repainting one segment, or swapping a label again, gives
 * what the C++'s full redraw gives. (The segments' boxes overlap; their pixels do not.) */
static bool mark_box(uint8_t SR_FAR *own, Box b)
{
    int32_t x, y;
    if (b.y0 < (int32_t)DASHBOARD_TOP || b.y1 > (int32_t)FRAMEBUFFER_HEIGHT || b.x0 < 0 ||
        b.x1 > (int32_t)FRAMEBUFFER_WIDTH)
        return false;
    for (y = b.y0; y < b.y1; ++y)
        for (x = b.x0; x < b.x1; ++x) {
            uint8_t SR_FAR *o = own + (unsigned)(y - (int32_t)DASHBOARD_TOP) * FRAMEBUFFER_WIDTH + (unsigned)x;
            if (*o)
                return false;
            *o = 1;
        }
    return true;
}

static bool dash_cache_possible(const Renderer *r)
{
    const AttractModeAssets *a = &r->assets_;
    const HudFragmentPack *packs[3];
    const unsigned band = (FRAMEBUFFER_HEIGHT - DASHBOARD_TOP) * FRAMEBUFFER_WIDTH;
    uint8_t SR_FAR *own = (uint8_t SR_FAR *)plat_alloc_big(band);
    bool ok = true;
    unsigned p, i, x, y;
    plat_fill(own, 0, band);
    packs[0] = &a->oxygen_gauge;
    packs[1] = &a->fuel_gauge;
    packs[2] = &a->speed_gauge;
    ok = mark_box(own, box_of(DOS_OXYGEN_WARN_X, DOS_OXYGEN_WARN_Y, DOS_OXYGEN_WARN_W,
                              DOS_OXYGEN_WARN_H)) &&
         mark_box(own, box_of(DOS_FUEL_WARN_X, DOS_FUEL_WARN_Y, DOS_FUEL_WARN_W, DOS_FUEL_WARN_H)) &&
         mark_box(own, box_of(DOS_GRAVITY_READOUT_X, DOS_GRAVITY_READOUT_Y,
                              (int32_t)DOS_GRAVITY_READOUT_DIGITS * DOS_DIGIT_ADVANCE,
                              DOS_DIGIT_HEIGHT));
    for (p = 0; p < 3 && ok; ++p)
        for (i = 0; i < packs[p]->fragment_count && ok; ++i) {
            const HudFragment SR_FAR *f = &packs[p]->fragments[i];
            for (y = 0; y < f->height && ok; ++y)
                for (x = 0; x < f->width && ok; ++x) {
                    const unsigned px = f->x + x, py = f->y + y;
                    if (f->pixels.data[y * f->width + x] == 0)
                        continue;
                    if (py < DASHBOARD_TOP || py >= FRAMEBUFFER_HEIGHT || px >= FRAMEBUFFER_WIDTH ||
                        own[(py - DASHBOARD_TOP) * FRAMEBUFFER_WIDTH + px])
                        ok = false;
                    else
                        own[(py - DASHBOARD_TOP) * FRAMEBUFFER_WIDTH + px] = 1;
                }
        }
    plat_free_big(own);
    return ok;
}

/* the dashboard's band cache (both inits) */
static void renderer_init_dash(Renderer *r)
{
    /* the art's rows above the band */
    memset(&r->dash_top, 0, sizeof r->dash_top);
    r->dash_cache_ok = false;
    if (archive_has_frame(&r->assets_.dashboard, 0) && r->assets_.dashboard.frames[0].count == 1) {
        const ImageFrame SR_FAR *d = archive_front(&r->assets_.dashboard, 0);
        if (d->y_offset < DASHBOARD_TOP && d->y_offset + d->height == FRAMEBUFFER_HEIGHT &&
            d->x_offset == 0 && d->width == FRAMEBUFFER_WIDTH) {
            r->dash_top = *d;
            r->dash_top.height = (uint16_t)(DASHBOARD_TOP - d->y_offset);
            r->dash_cache_ok = dash_cache_possible(r);
        }
    }
}

void renderer_init(Renderer *r)
{
    unsigned i, k;
    car_atlas_from_archive(&r->assets_.cars, &r->car_atlas_);
    /* C: FbOps.sprite needs every pixel inside the palette */
    r->car_atlas_.keyed_ok = r->car_atlas_.valid;
    for (i = 0; i < 77 && r->car_atlas_.keyed_ok; ++i) {
        const ImageFrame *f = i < 14 ? &r->car_atlas_.explosion_frames[i]
                                     : &r->car_atlas_.exact_ship_frames[i - 14];
        if (!f->transparent_zero)
            r->car_atlas_.keyed_ok = false;
        for (k = 0; k < f->pixels.size; ++k)
            if (f->pixels.data[k] >= f->palette.color_count ||
                PAL_CARS_BASE + f->palette.color_count > 0x100)
                r->car_atlas_.keyed_ok = false;
    }
    for (i = 0; i < r->assets_.trekdat.record_count && i < 16; ++i)
        prepare_record(r, i);
    renderer_init_dash(r);
}

/* ---- C (round 2): what renderer_init makes, made once on the PC (srtool prepare, written
 * by host/cli_main.c's write_prepared) and read here: TREKDAT's clipped spans and the ship's
 * turned sprites (16.4 s and 4.3 s at the start on the Atari816). The file, little-endian:
 *   "SKP2", u16 records; a record: u16 shape_count, u16 pointer_shape[312];
 *   u16 chunks; a chunk: u32 size (<= 65,280), its PreparedSpan bytes (5 each);
 *   a record's shapes: u16 count, u8 colour, u8 chunk, u16 index of its first span there;
 *   u8 keyed_ok, u8 valid, u16 frames (77: 14 explosion, 63 flight); a frame: u16 width,
 *   u16 height, its pixels;
 *   a record's 13 pointer rows' centre merges (see Renderer.center): u16 count (0: none),
 *   u8 0, u8 chunk, u16 index.
 * The sprites' palette and transparency are the CARS archive's (loaded as before). */
static uint16_t prep_u16(const Bytes *b, uint32_t off)
{
    return (uint16_t)(SR_BYTE(b->data, off) | ((uint16_t)SR_BYTE(b->data, off + 1) << 8));
}

bool renderer_init_prepared(Renderer *r, const Bytes *prep)
{
    TrekdatArchive *t = &r->assets_.trekdat;
    uint32_t off = 6;
    unsigned ri, s, nchunks, c;
    PreparedSpan SR_FAR *chunk[16];
    const ImageFrame SR_FAR *sheet;
    if (prep->size < 6 || SR_BYTE(prep->data, 0) != 'S' || SR_BYTE(prep->data, 1) != 'K' ||
        SR_BYTE(prep->data, 2) != 'P' || SR_BYTE(prep->data, 3) != '2')
        return false;
    t->record_count = prep_u16(prep, 4);
    if (t->record_count > 16)
        return false;
    t->records = (TrekdatRecord SR_FAR *)plat_alloc((uint32_t)t->record_count * sizeof(TrekdatRecord));
    for (ri = 0; ri < t->record_count; ++ri) {
        TrekdatRecord SR_FAR *rec = &t->records[ri];
        rec->index = ri;
        rec->shape_count = prep_u16(prep, off);
        sr_copy_from(rec->pointer_shape, prep, off + 2, TREKDAT_POINTER_COUNT * 2u);
        off += 2 + TREKDAT_POINTER_COUNT * 2u;
    }
    nchunks = prep_u16(prep, off);
    off += 2;
    if (nchunks > 16)
        return false;
    for (c = 0; c < nchunks; ++c) {
        const uint32_t size = prep_u16(prep, off) | ((uint32_t)prep_u16(prep, off + 2) << 16);
        const unsigned n = (unsigned)(size / 5u);
        chunk[c] = (PreparedSpan SR_FAR *)plat_alloc((uint32_t)n * sizeof(PreparedSpan));
        if (sizeof(PreparedSpan) == 5) {        /* (the Atari816: the bytes as they are) */
            sr_copy_from(chunk[c], prep, off + 4, size);
        } else {                                /* (a PC pads the structure) */
            unsigned k;
            for (k = 0; k < n; ++k) {
                const uint32_t o = off + 4 + (uint32_t)k * 5u;
                chunk[c][k].left = prep_u16(prep, o);
                chunk[c][k].right = prep_u16(prep, o + 2);
                chunk[c][k].width = SR_BYTE(prep->data, o + 4);
            }
        }
        off += 4 + size;
    }
    for (ri = 0; ri < t->record_count; ++ri) {
        const unsigned n = t->records[ri].shape_count;
        PreparedShape SR_FAR *prepared =
            (PreparedShape SR_FAR *)plat_alloc((uint32_t)SR_MAX(n, 1) * sizeof(PreparedShape));
        /* (the table through a near copy, 64 shapes at a time) */
        uint8_t tb[64 * 6];
        for (s = 0; s < n; ++s, off += 6) {
            const uint8_t *e = &tb[(s & 63u) * 6u];
            unsigned count, ch;
            if ((s & 63u) == 0)
                sr_copy_from(tb, prep, off, SR_MIN(64u, n - s) * 6u);
            count = e[0] | (unsigned)e[1] << 8;
            ch = e[3];
            prepared[s].count = (uint16_t)count;
            prepared[s].color = e[2];
            prepared[s].spans = count && ch < nchunks ? chunk[ch] + (e[4] | (unsigned)e[5] << 8) : 0;
        }
        r->prepared[ri] = prepared;
    }
    /* the ship's sprites */
    memset(&r->car_atlas_, 0, sizeof r->car_atlas_);
    r->car_atlas_.keyed_ok = SR_BYTE(prep->data, off) != 0;
    r->car_atlas_.valid = SR_BYTE(prep->data, off + 1) != 0;
    off += 2;
    if (prep_u16(prep, off) != 77 || !archive_has_frame(&r->assets_.cars, 0)) {
        r->car_atlas_.valid = r->car_atlas_.keyed_ok = false;
    } else {
        off += 2;
        sheet = archive_front(&r->assets_.cars, 0);
        for (s = 0; s < 77; ++s) {
            ImageFrame *f = s < 14 ? &r->car_atlas_.explosion_frames[s]
                                   : &r->car_atlas_.exact_ship_frames[s - 14];
            f->width = prep_u16(prep, off);
            f->height = prep_u16(prep, off + 2);
            f->palette = sheet->palette;
            f->transparent_zero = sheet->transparent_zero;
            f->pixels = bytes_slice(prep, off + 4, (uint32_t)f->width * f->height);
            off += 4 + (uint32_t)f->width * f->height;
        }
        r->car_atlas_.explosion_count = 14;
        r->car_atlas_.exact_count = 63;
        r->car_atlas_.destroyed = r->car_atlas_.explosion_frames[13];
    }
    /* the centre merges */
    for (ri = 0; ri < t->record_count; ++ri) {
        PreparedShape SR_FAR *cm =
            (PreparedShape SR_FAR *)plat_alloc(TREKDAT_POINTER_ROWS * sizeof(PreparedShape));
        for (s = 0; s < TREKDAT_POINTER_ROWS; ++s, off += 6) {
            const unsigned count = prep_u16(prep, off);
            const unsigned ch = SR_BYTE(prep->data, off + 3);
            cm[s].count = (uint16_t)(ch < nchunks ? count : 0);
            cm[s].color = 0;
            cm[s].spans = cm[s].count ? chunk[ch] + prep_u16(prep, off + 4) : 0;
        }
        r->center[ri] = cm;
    }
    if (off > prep->size)
        sr_fail("SKYPREP.DAT is short");
    renderer_init_dash(r);
    return true;
}

static void draw_fragment(const Renderer *r, FrameBuffer320x200 *frame,
                          const ImageFrame SR_FAR *fragment, unsigned palette_base);
static void draw_archive_frame(const Renderer *r, FrameBuffer320x200 *frame,
                               const ImageArchive *archive, unsigned frame_index,
                               unsigned palette_base);
static void draw_intro_picture(FrameBuffer320x200 *frame, const ImageFrame SR_FAR *fragment,
                               unsigned palette_base, float wipe);
static void draw_sprite(FrameBuffer320x200 *frame, const ImageFrame *sprite, int32_t dest_x,
                        int32_t dest_y, unsigned scale, unsigned palette_base);
static void draw_sprite_far(FrameBuffer320x200 *frame, const ImageFrame SR_FAR *sprite,
                            int32_t dest_x, int32_t dest_y, unsigned palette_base);

static void render_intro(const Renderer *r, RenderedFrame *out, const IntroSequenceState *scene)
{
    const AttractModeAssets *a = &r->assets_;
    FrameBuffer320x200 *frame = &out->frame;
    Palette256 *pal = &out->palette;
    unsigned g, groups_drawn = 0;
    /* The master fade rides on every band -- it is the whole-DAC brightness fade
     * the intro runs at @0x43d8. */
    if (archive_has_frame(&a->intro, 0))
        pal_band_brightness(pal, PAL_INTRO_BACKDROP_BASE, archive_front(&a->intro, 0)->palette.colors,
                            archive_front(&a->intro, 0)->palette.color_count,
                            scene->background_brightness);
    for (g = 0; g < a->anim.frame_count; ++g) {
        const ImageFrameList SR_FAR *group = &a->anim.frames[g];
        if (group->count == 0)
            continue;
        pal_band_brightness(pal, PAL_INTRO_ANIM_BASE, group->fragments[0].palette.colors,
                            group->fragments[0].palette.color_count, scene->background_brightness);
        break;
    }
    /* Slot 0 is the clear colour; the art never blits its local index 0
     * (transparent), so the backdrop band cannot claim it. */
    pal->colors[0] = rgb(0, 0, 0);
    fb_clear(frame, 0);
    /* intro.lzs picture 0 is the backdrop the whole sequence is painted onto. */
    draw_archive_frame(r, frame, &a->intro, 0, PAL_INTRO_BACKDROP_BASE);

    /* The animation is cumulative: the EXE blits each group's fragments straight to
     * the screen and never repaints the backdrop, so replay every group up to the
     * current one. Groups with no fragments never make it into the flattened table
     * at ds:0x45c4, so they cost no time and are skipped here too. */
    for (g = 0; g < a->anim.frame_count; ++g) {
        const ImageFrameList SR_FAR *group = &a->anim.frames[g];
        unsigned k;
        if (group->count == 0)
            continue;
        if (groups_drawn >= scene->anim_groups_drawn)
            break;
        for (k = 0; k < group->count; ++k)
            draw_fragment(r, frame, &group->fragments[k], PAL_INTRO_ANIM_BASE);
        groups_drawn += 1;
    }

    if (scene->title_visible && archive_has_frame(&a->intro, INTRO_TITLE_FRAME)) {
        const ImageFrameList SR_FAR *fragments = &a->intro.frames[INTRO_TITLE_FRAME];
        const float wipe = ramp_f(scene->title_wipe);
        unsigned k;
        pal_band_intro(pal, PAL_INTRO_TITLE_BASE, &fragments->fragments[0], scene->title_mix,
                       scene->title_white, scene->background_brightness);
        for (k = 0; k < fragments->count; ++k)
            draw_intro_picture(frame, &fragments->fragments[k], PAL_INTRO_TITLE_BASE, wipe);
    }

    if (scene->has_credit_frame_index && archive_has_frame(&a->intro, scene->credit_frame_index)) {
        const ImageFrameList SR_FAR *fragments = &a->intro.frames[scene->credit_frame_index];
        Ramp zero;
        unsigned k;
        zero.elapsed = 0;
        zero.span = 1;
        zero.down = false;
        pal_band_intro(pal, PAL_INTRO_CREDIT_BASE, &fragments->fragments[0], scene->credit_mix, zero,
                       scene->background_brightness);
        for (k = 0; k < fragments->count; ++k)
            draw_intro_picture(frame, &fragments->fragments[k], PAL_INTRO_CREDIT_BASE, 0.0f);
    }
}

static void render_main_menu(const Renderer *r, RenderedFrame *out, const MainMenuScene *scene)
{
    const AttractModeAssets *a = &r->assets_;
    FrameBuffer320x200 *frame = &out->frame;
    Palette256 *pal = &out->palette;
    if (archive_has_frame(&a->intro, 0))
        pal_band_fill(pal, PAL_INTRO_BACKDROP_BASE, archive_front(&a->intro, 0)->palette.colors,
                      archive_front(&a->intro, 0)->palette.color_count);
    if (archive_has_frame(&a->intro, 1))
        pal_band_fill(pal, PAL_INTRO_TITLE_BASE, archive_front(&a->intro, 1)->palette.colors,
                      archive_front(&a->intro, 1)->palette.color_count);
    if (archive_has_frame(&a->main_menu, 0))
        pal_band_fill(pal, PAL_MENU_ART_BASE, archive_front(&a->main_menu, 0)->palette.colors,
                      archive_front(&a->main_menu, 0)->palette.color_count);
    pal->colors[0] = rgb(0, 0, 0);
    fb_clear(frame, 0);
    draw_archive_frame(r, frame, &a->intro, 0, PAL_INTRO_BACKDROP_BASE);
    draw_archive_frame(r, frame, &a->intro, 1, PAL_INTRO_TITLE_BASE);
    draw_archive_frame(r, frame, &a->main_menu, menu_cursor_index(scene->selected), PAL_MENU_ART_BASE);
}

static void render_help_menu(const Renderer *r, RenderedFrame *out, const HelpMenuScene *scene)
{
    const AttractModeAssets *a = &r->assets_;
    FrameBuffer320x200 *frame = &out->frame;
    const unsigned page_index = SR_MIN(scene->page_index, sat_sub(a->help_menu.frame_count, 1));
    /* Full-screen pages, each with its own CMAP, shown one at a time at base 0. */
    if (archive_has_frame(&a->help_menu, page_index))
        pal_band_fill(&out->palette, 0, archive_front(&a->help_menu, page_index)->palette.colors,
                      archive_front(&a->help_menu, page_index)->palette.color_count);
    out->palette.colors[0] = rgb(0, 0, 0);
    fb_clear(frame, 0);
    draw_archive_frame(r, frame, &a->help_menu, page_index, 0);
}

/* setmenu.lzs pics 1..10 are 3-colour overlays with per-picture CMAPs; give each
 * a fixed 3-slot band after the background's. */
static unsigned settings_overlay_base(unsigned frame_index)
{
    return PAL_SETTINGS_OVERLAY_BASE + (frame_index - 1) * 3;
}

static void render_settings_menu(const Renderer *r, RenderedFrame *out,
                                 const SettingsMenuScene *scene)
{
    const AttractModeAssets *a = &r->assets_;
    FrameBuffer320x200 *frame = &out->frame;
    Palette256 *pal = &out->palette;
    unsigned f, position, cursor, cursor_frame;
    for (f = 0; f < a->settings_menu.frame_count && f < 11; ++f) {
        unsigned base;
        if (a->settings_menu.frames[f].count == 0)
            continue;
        base = f == 0 ? 0 : settings_overlay_base(f);
        pal_band_fill(pal, base, archive_front(&a->settings_menu, f)->palette.colors,
                      archive_front(&a->settings_menu, f)->palette.color_count);
    }
    pal->colors[0] = rgb(0, 0, 0);
    fb_clear(frame, 0);
    /* setmenu.lzs: picture 0 is the background, 1..5 are the cursor outlines for the
     * five positions and 6..10 the "this option is active" fills. @0x4ae2 walks all
     * five positions and draws the fill only where the position matches the current
     * setting; @0x4c9a draws the outline for wherever the cursor is. */
    draw_archive_frame(r, frame, &a->settings_menu, 0, 0);
    for (position = 0; position < SETTINGS_POSITIONS; ++position) {
        const bool active = position <= 2 ? position == scene->input_device
                                          : position - 3 == scene->sound_option;
        unsigned marker;
        if (!active)
            continue;
        marker = SETTINGS_MARKER_FIRST_FRAME + position;
        draw_archive_frame(r, frame, &a->settings_menu, marker, settings_overlay_base(marker));
    }
    cursor = SR_MIN(scene->cursor, SETTINGS_POSITIONS - 1);
    cursor_frame = SETTINGS_CURSOR_FIRST_FRAME + cursor;
    draw_archive_frame(r, frame, &a->settings_menu, cursor_frame, settings_overlay_base(cursor_frame));
}

static void render_go_menu(const Renderer *r, RenderedFrame *out, const GoMenuScene *scene)
{
    const AttractModeAssets *a = &r->assets_;
    FrameBuffer320x200 *frame = &out->frame;
    Palette256 *pal = &out->palette;
    unsigned flat, world;
    int row, road, cursor_x, cursor_y;
    if (archive_has_frame(&a->go_menu, 0))
        pal_band_fill(pal, 0, archive_front(&a->go_menu, 0)->palette.colors,
                      archive_front(&a->go_menu, 0)->palette.color_count);
    if (archive_has_frame(&a->go_menu, 1))
        pal_band_fill(pal, PAL_GOMENU_MARK_BASE, archive_front(&a->go_menu, 1)->palette.colors,
                      archive_front(&a->go_menu, 1)->palette.color_count);
    pal->colors[PAL_GOMENU_CURSOR] = rgb(232, 232, 245);
    pal->colors[0] = rgb(0, 0, 0);
    /* Frame 0 of GOMENU is the full stage-selector grid (10 worlds x 3 roads,
     * names and planet thumbnails baked in). We just overlay a cursor on the
     * selected entry. Grid geometry measured from the art: two columns
     * (worlds 0-4 left, 5-9 right), rows step 39px, roads step 9px, first road
     * text at y=13; road text spans x59-92 (left) / x219-252 (right). */
    fb_clear(frame, 0);
    draw_archive_frame(r, frame, &a->go_menu, 0, 0);
    sync_cpu(frame);

    /* Each road shows a row of small markers counting how many times it has been
     * completed (EXE @0x51ce-0x525a): GOMENU frame 1 is the 6x5 marker sprite, drawn
     * at most 7 times, stepping 7px, from base offset 0x11f0 = (x 112, y 14) with
     * +160 for the right-hand column. */
    for (flat = 0; flat < 30; ++flat) {
        const int count = SR_MIN((int)scene->completions[flat], 7);
        int mark_x, mark_y, i;
        if (count == 0)
            continue;
        mark_x = 112 + (flat >= 15 ? 160 : 0);
        mark_y = 14 + (int)((flat / 3) % 5) * 39 + (int)(flat % 3) * 9;
        if (!archive_has_frame(&a->go_menu, 1))
            continue;
        for (i = 0; i < count; ++i)
            draw_sprite_far(frame, archive_front(&a->go_menu, 1), mark_x + i * 7, mark_y,
                            PAL_GOMENU_MARK_BASE);
    }

    /* Cursor placement (EXE @0x50e3-0x512d): base offset 0xf3e = (x 62, y 12), rows
     * step 39px per world and 9px per road, +160 for the right-hand column. */
    world = scene->selected_world;
    row = (int)(world % 5);
    road = (int)scene->selected_level;
    cursor_x = 62 + (world >= 5 ? 160 : 0);
    cursor_y = 12 + row * 39 + road * 9;

    /* The original highlights the selected road by redrawing its text; we outline it. */
    stroke_rect(frame, cursor_x - 3, cursor_y - 1, 37, 9, PAL_GOMENU_CURSOR);
}

static const ImageArchive *play_world(const Renderer *r, const DemoPlaybackState *scene)
{
    if (scene->world_index < r->assets_.world_count)
        return &r->assets_.worlds[scene->world_index];
    if (r->assets_.world_count)
        return &r->assets_.worlds[0];
    return 0;
}

/* RVSTACK: palette assembly + world pick, shared with the incremental path. */
static void assemble_play_palette(const Renderer *r, Palette256 *pal, const DemoPlaybackState *scene)
{
    const AttractModeAssets *a = &r->assets_;
    const ImageArchive *world;
    /* Assemble the gameplay DAC. Every shipped road palette has a black entry 0,
     * which doubles as the clear/sky colour behind the backdrop's holes. */
    pal_band_fill(pal, PAL_ROAD_BASE, scene->road_palette, scene->road_palette_count);
    if (archive_has_frame(&a->cars, 0))
        pal_band_fill(pal, PAL_CARS_BASE, archive_front(&a->cars, 0)->palette.colors,
                      archive_front(&a->cars, 0)->palette.color_count);
    if (archive_has_frame(&a->dashboard, 0)) {
        pal_band_fill(pal, PAL_DASH_BASE, archive_front(&a->dashboard, 0)->palette.colors,
                      archive_front(&a->dashboard, 0)->palette.color_count);
    } else {
        /* No dashboard art: keep at least the HUD's two purple shades usable. */
        unsigned i;
        for (i = 0; i < 3; ++i)
            pal->colors[PAL_DASH_BASE + i] = DASHBOARD_COLORS[i];
    }
    world = play_world(r, scene);
    if (world && archive_has_frame(world, 0))
        pal_band_fill(pal, PAL_WORLD_BASE, archive_front(world, 0)->palette.colors,
                      archive_front(world, 0)->palette.color_count);
}

static bool draw_demo_rows(const Renderer *r, FrameBuffer320x200 *frame,
                           const DemoPlaybackState *scene, DosRoadPhase phase)
{
    const unsigned slot = scene->current_row & 7;
    if (slot >= r->assets_.trekdat.record_count)
        return false;
    return draw_dos_trekdat_pass(frame, scene, &r->assets_.trekdat.records[slot], r->prepared[slot],
                                 phase);
}

static void draw_ship_sprite(const Renderer *r, FrameBuffer320x200 *frame,
                             const DerivedShipVisualState *visual, ShipScreenPlacement placement)
{
    const ImageFrame *sprite;
    int32_t x, y, explode_offset;
    unsigned draw_width, draw_height;
    if (!r->car_atlas_.valid)
        return;
    /* EXE @0xc18: once the explosion counter passes the 14th frame the sprite
     * index becomes -1, i.e. the wreck stops being drawn at all. */
    if (visual->sprite_kind == ShipSpriteKind_Exploding &&
        visual->explosion_frame >= r->car_atlas_.explosion_count)
        return;
    sprite = car_atlas_select_sprite(&r->car_atlas_, visual);
    draw_width = sprite->width * SHIP_SCALE;
    draw_height = sprite->height * SHIP_SCALE;
    x = placement.sprite_center_x - (int32_t)(draw_width / 2);
    explode_offset = visual->sprite_kind == ShipSpriteKind_Exploding ? -2 : 0;
    y = placement.sprite_center_y + explode_offset - (int32_t)(draw_height / 2);
    if (r->car_atlas_.keyed_ok && fb_ops.sprite &&
        fb_ops.sprite(frame, sprite->pixels.data, sprite->width, sprite->height, x, y, PAL_CARS_BASE))
        return;
    draw_sprite(frame, sprite, x, y, SHIP_SCALE, PAL_CARS_BASE);
}

/* The gauges are SEGMENTED BARS, not one picture that changes shape: each *_DISP.DAT
 * fragment is a single segment, and the game paints segments below the current level
 * in the "lit" colour pair and the rest in the "unlit" pair (@0x1341-0x138e, pairs
 * chosen at @0xeef-0xf15). It only redraws the segments between the old and new
 * level, which over a full redraw comes out as painting them all.
 *
 * The colours are palette indices 0x5C..0x5F, and dashbrd.lzs is loaded at palette
 * base 0x5C (@0x5589), so they are just the first four colours of its own CMAP:
 * 0/1 unlit, 2/3 lit. A mask byte of 1 selects the first of a pair, anything else
 * the second. */
static void draw_gauge_segment(FrameBuffer320x200 *frame, const HudFragment SR_FAR *fragment,
                               bool lit)
{
    unsigned y, x;
    for (y = 0; y < fragment->height; ++y)
        for (x = 0; x < fragment->width; ++x) {
            const uint8_t mask_value = fragment->pixels.data[y * fragment->width + x];
            if (mask_value == 0)
                continue;
            fb_set_pixel(frame, fragment->x + x, fragment->y + y,
                         (uint8_t)(PAL_DASH_BASE + (lit ? 2u : 0u) + (mask_value == 1 ? 0u : 1u)));
        }
}

static void draw_gauge(FrameBuffer320x200 *frame, const HudFragmentPack *pack, unsigned level)
{
    unsigned segment;
    for (segment = 0; segment < pack->fragment_count; ++segment)
        draw_gauge_segment(frame, &pack->fragments[segment], segment < level);
}

/* The GRAV-O-METER readout (@0x1067). Digits are emitted from the units upward and
 * the loop stops as soon as the remaining value is zero, so leading zeros are simply
 * never drawn; digit `i` from the right sits at x + (count - 1 - i) * 5. */
static void draw_dashboard_number(FrameBuffer320x200 *frame, int32_t x, int32_t y, int32_t value,
                                  unsigned digits)
{
    int32_t remaining = value, divisor = 1;
    unsigned i;
    if (value < 0)
        return;
    for (i = 0; i < digits; ++i) {
        const int32_t digit = (remaining / divisor) % 10;
        const uint8_t *glyph;
        int32_t gx;
        unsigned row, col;
        if (remaining == 0 && i != 0)
            break;
        glyph = DOS_DIGIT_GLYPHS[digit];
        gx = x + (int32_t)(digits - 1 - i) * DOS_DIGIT_ADVANCE;
        for (row = 0; row < DOS_DIGIT_HEIGHT; ++row)
            for (col = 0; col < DOS_DIGIT_WIDTH; ++col) {
                /* Glyph byte 0 is the digit stroke (palette index 0), 1 and 2 the two tan
                 * shades of the readout window (dashbrd CMAP entries 5 and 6). */
                const uint8_t v = glyph[row * DOS_DIGIT_WIDTH + col];
                const int32_t px = gx + (int32_t)col;
                const int32_t py = y + (int32_t)row;
                if (px < 0 || py < 0)
                    continue;
                fb_set_pixel(frame, (unsigned)px, (unsigned)py,
                             (uint8_t)(PAL_DASH_BASE + (v == 0 ? 0u : (v == 1 ? 5u : 6u))));
            }
        remaining -= digit * divisor;
        divisor *= 10;
    }
}

/* The BIOS 8x8 ROM font printer (@0x450a): one glyph per character, x advancing by
 * exactly 8, and glyph bit 0x80 >> column. Background pixels are left alone. */
static void draw_rom_text(FrameBuffer320x200 *frame, int32_t x, int32_t y, const char *text,
                          uint8_t color_index)
{
    int32_t pen = x;
    for (; *text; ++text) {
        const uint8_t *glyph = dos_font_glyph(*text);
        unsigned row, col;
        for (row = 0; row < DOS_FONT_HEIGHT; ++row) {
            const uint8_t bits = glyph[row];
            for (col = 0; col < 8; ++col) {
                const int32_t px = pen + (int32_t)col;
                const int32_t py = y + (int32_t)row;
                if ((bits & (0x80u >> col)) == 0)
                    continue;
                if (px < 0 || py < 0)
                    continue;
                fb_set_pixel(frame, (unsigned)px, (unsigned)py, color_index);
            }
        }
        pen += DOS_FONT_ADVANCE;
    }
}

/* The flashing label over an empty tank. The original swaps two palette entries in
 * place on each edge of the 4 Hz blink phase, and never repaints the dashboard, so the
 * label sits swapped for the whole high phase. This renderer redraws the dashboard
 * every frame, so the equivalent is to swap the two indices across the label's
 * rectangle while the phase is high -- the same in-place index exchange the DOS
 * build achieves by reprogramming the two DAC entries. */
static void draw_empty_tank_warning(FrameBuffer320x200 *frame, const DemoPlaybackState *scene)
{
    int32_t x, y, w, h, px, py;
    const uint8_t a = (uint8_t)(PAL_DASH_BASE + DOS_WARN_PALETTE_A);
    const uint8_t b = (uint8_t)(PAL_DASH_BASE + DOS_WARN_PALETTE_B);
    if (!dos_warn_blink_phase(scene->frame_index))
        return;
    if (scene->ship.state == ShipState_OutOfOxygen) {
        x = DOS_OXYGEN_WARN_X; y = DOS_OXYGEN_WARN_Y; w = DOS_OXYGEN_WARN_W; h = DOS_OXYGEN_WARN_H;
    } else if (scene->ship.state == ShipState_OutOfFuel) {
        x = DOS_FUEL_WARN_X; y = DOS_FUEL_WARN_Y; w = DOS_FUEL_WARN_W; h = DOS_FUEL_WARN_H;
    } else {
        return;
    }
    for (py = y; py < y + h; ++py)
        for (px = x; px < x + w; ++px) {
            uint8_t current;
            if (px < 0 || py < 0)
                continue;
            current = fb_pixel_at(frame, (unsigned)px, (unsigned)py);
            if (current == a)
                fb_set_pixel(frame, (unsigned)px, (unsigned)py, b);
            else if (current == b)
                fb_set_pixel(frame, (unsigned)px, (unsigned)py, a);
        }
}

/* the dashboard band's drawing after the art: shared by both play paths */
static void draw_dashboard_readouts(const Renderer *r, FrameBuffer320x200 *f,
                                    const DemoPlaybackState *scene)
{
    const AttractModeAssets *a = &r->assets_;
    sync_cpu(f);
    draw_gauge(f, &a->oxygen_gauge, tank_gauge_level(scene->snapshot.oxygen_remaining));
    draw_gauge(f, &a->fuel_gauge, tank_gauge_level(scene->snapshot.fuel_remaining));
    draw_gauge(f, &a->speed_gauge, speed_gauge_level(scene->snapshot.z_velocity_fp16));
    draw_empty_tank_warning(f, scene);
    draw_dashboard_number(f, DOS_GRAVITY_READOUT_X, DOS_GRAVITY_READOUT_Y,
                          dos_gravity_readout((int32_t)scene->gravity), DOS_GRAVITY_READOUT_DIGITS);
    /* Completing a road is the ONLY outcome the original puts a message up for
     * (EXE @0x2c5a skips the whole banner unless the outcome is 0): it prints "Road
     * Completed", or "The End" on the last remaining road, at y=80. Dying shows
     * nothing at all -- the road simply restarts. */
    if (!scene->is_demo && scene->did_win) {
        /* The original prints these with the BIOS 8x8 ROM font, centred as
         * 160 - len*8/2 at y = 80, in palette index 0x63 -- dashbrd.lzs CMAP entry 7,
         * since it loads at base 0x5C (@0x2c62-0x2c8a). */
        const char *text = scene->is_final_road ? "The End" : "Road Completed";
        draw_rom_text(f, dos_text_centered_x((unsigned)strlen(text)), 80, text,
                      (uint8_t)(PAL_DASH_BASE + 7));
    }
}

static void draw_ship_shadow(FrameBuffer320x200 *frame, const DerivedShipVisualState *visual,
                             ShipScreenPlacement placement);

static void render_play_scene(const Renderer *r, RenderedFrame *out, const DemoPlaybackState *scene)
{
    out->palette_stamp = 0;     /* (this palette is no cache generation's) */
    FrameBuffer320x200 *frame = &out->frame;
    const DerivedShipVisualState ship_visual = derive_ship_visual_state(scene);
    const ShipScreenPlacement ship_placement = ship_screen_placement(scene, &ship_visual);
    const ImageArchive *world = play_world(r, scene);
    bool drew_dos_road;

    assemble_play_palette(r, &out->palette, scene);
    fb_clear(frame, 0);
    if (world)
        draw_archive_frame(r, frame, world, 0, PAL_WORLD_BASE);
    sync_cpu(frame);

    drew_dos_road = draw_demo_rows(r, frame, scene, DosRoadPhase_BeforeShip);
    /* (no TREKDAT: the C++ drew its projected fallback road; not translated) */
    /* The shadow is blitted straight AFTER the ship (@0x329d), not before it. */
    draw_ship_sprite(r, frame, &ship_visual, ship_placement);
    draw_ship_shadow(frame, &ship_visual, ship_placement);
    if (drew_dos_road)
        draw_demo_rows(r, frame, scene, DosRoadPhase_AfterShip);
    draw_archive_frame(r, frame, &r->assets_.dashboard, 0, PAL_DASH_BASE);
    draw_dashboard_readouts(r, frame, scene);
}

/* the empty-tank label that draw_empty_tank_warning swaps now: 0 none, 1 oxygen, 2 fuel */
static unsigned warn_state(const DemoPlaybackState *scene)
{
    if (!dos_warn_blink_phase(scene->frame_index))
        return 0;
    if (scene->ship.state == ShipState_OutOfOxygen)
        return 1;
    if (scene->ship.state == ShipState_OutOfFuel)
        return 2;
    return 0;
}

/* swap the two label colours over label w (1 oxygen, 2 fuel): draw_empty_tank_warning's
 * loop (an involution: twice is nothing) */
static void swap_label(FrameBuffer320x200 *frame, unsigned w)
{
    int32_t x, y, ww, h, px, py;
    const uint8_t a = (uint8_t)(PAL_DASH_BASE + DOS_WARN_PALETTE_A);
    const uint8_t b = (uint8_t)(PAL_DASH_BASE + DOS_WARN_PALETTE_B);
    if (w == 1) {
        x = DOS_OXYGEN_WARN_X; y = DOS_OXYGEN_WARN_Y; ww = DOS_OXYGEN_WARN_W; h = DOS_OXYGEN_WARN_H;
    } else {
        x = DOS_FUEL_WARN_X; y = DOS_FUEL_WARN_Y; ww = DOS_FUEL_WARN_W; h = DOS_FUEL_WARN_H;
    }
    for (py = y; py < y + h; ++py)
        for (px = x; px < x + ww; ++px) {
            const uint8_t current = fb_pixel_at(frame, (unsigned)px, (unsigned)py);
            if (current == a)
                fb_set_pixel(frame, (unsigned)px, (unsigned)py, b);
            else if (current == b)
                fb_set_pixel(frame, (unsigned)px, (unsigned)py, a);
        }
}

/* C: the dashboard band cache (PlaySceneCache.dash) brought up to the scene */
static void update_dash(const Renderer *r, PlaySceneCache *c, const DemoPlaybackState *scene)
{
    const AttractModeAssets *a = &r->assets_;
    const HudFragmentPack *packs[3];
    unsigned level[3], g, w;
    packs[0] = &a->oxygen_gauge;
    packs[1] = &a->fuel_gauge;
    packs[2] = &a->speed_gauge;
    level[0] = tank_gauge_level(scene->snapshot.oxygen_remaining);
    level[1] = tank_gauge_level(scene->snapshot.fuel_remaining);
    level[2] = speed_gauge_level(scene->snapshot.z_velocity_fp16);
    w = warn_state(scene);
    if (!c->dash_valid || c->dash_generation != c->generation || c->dash_gravity != scene->gravity) {
        /* all of it, as the C++ drew it */
        fb_ops.copy_rows(&c->dash, &c->underlay, VIEW_BOTTOM_Y, FRAMEBUFFER_HEIGHT);
        draw_archive_frame(r, &c->dash, &a->dashboard, 0, PAL_DASH_BASE);
        sync_cpu(&c->dash);
        for (g = 0; g < 3; ++g)
            draw_gauge(&c->dash, packs[g], level[g]);
        if (w)
            swap_label(&c->dash, w);
        draw_dashboard_number(&c->dash, DOS_GRAVITY_READOUT_X, DOS_GRAVITY_READOUT_Y,
                              dos_gravity_readout((int32_t)scene->gravity), DOS_GRAVITY_READOUT_DIGITS);
        for (g = 0; g < 3; ++g)
            c->dash_level[g] = level[g];
        c->dash_warn = w;
        c->dash_gravity = scene->gravity;
        c->dash_generation = c->generation;
        c->dash_valid = true;
        return;
    }
    sync_cpu(&c->dash);
    for (g = 0; g < 3; ++g) {
        /* the segments between the old and the new level (the DOS HUD's way) */
        unsigned s;
        const unsigned lo = SR_MIN(c->dash_level[g], level[g]);
        const unsigned hi = SR_MAX(c->dash_level[g], level[g]);
        for (s = lo; s < hi && s < packs[g]->fragment_count; ++s)
            draw_gauge_segment(&c->dash, &packs[g]->fragments[s], s < level[g]);
        c->dash_level[g] = level[g];
    }
    if (w != c->dash_warn) {
        if (c->dash_warn)
            swap_label(&c->dash, c->dash_warn);
        if (w)
            swap_label(&c->dash, w);
        c->dash_warn = w;
    }
}

/* RVSTACK: the console play path -- see PlaySceneCache in the header. Every
 * draw call below is the pure path's, in the pure path's order; the only
 * difference is what the frame starts from: instead of clear+backdrop+
 * dashboard (128 KB of writes plus two full blits, every frame), the bands
 * the previous frame dirtied are copied back from the cached underlay.
 * Dirt inventory (each item's restore): spans + shadow + banner are clipped
 * to the road band rows [HORIZON_Y, VIEW_BOTTOM_Y) -> band copy; gauges,
 * warn label, gravity digits live in the dashboard band -> band copy (done
 * AFTER the ship draw, which is also what hides ship-sprite spill exactly
 * like the pure path's dashboard redraw does); the ship sprite alone can
 * rise above the horizon -> its previous rect is restored explicitly. */
void renderer_render_play_scene_incremental(const Renderer *r, RenderedFrame *out,
                                            PlaySceneCache *c, PagePrime *prime,
                                            const DemoPlaybackState *scene)
{
    const bool road_changed = !c->valid || c->world_index != scene->world_index ||
                              c->road_palette != scene->road_palette;
    FrameBuffer320x200 *f = &out->frame;
    const FrameBuffer320x200 *u = &c->underlay;
    DerivedShipVisualState ship_visual;
    ShipScreenPlacement ship_placement;
    bool prepared[2];

    if (road_changed) {
        const ImageArchive *world = play_world(r, scene);
        assemble_play_palette(r, &c->palette, scene);
        /* Underlay = clear + backdrop ONLY. The dashboard art is NOT baked
         * in: its cockpit frame rises above DASHBOARD_TOP, and the pure path
         * draws it AFTER the ship -- over an exploding ship's low pixels. It
         * is re-blitted per frame below, at the same point in the order. */
        fb_clear(&c->underlay, 0);
        if (world)
            draw_archive_frame(r, &c->underlay, world, 0, PAL_WORLD_BASE);
        sync_cpu(&c->underlay);
        c->world_index = scene->world_index;
        c->road_palette = scene->road_palette;
        c->valid = true;
        c->generation++;
        prime->primed = false;
    }
    /* (C, round 2: the palette copied only when it changed: RenderedFrame.palette_stamp) */
    if (out->palette_stamp != c->generation) {
        out->palette = c->palette;
        out->palette_stamp = c->generation;
    }

    if (!prime->primed) {
        fb_ops.copy_rows(f, u, 0, FRAMEBUFFER_HEIGHT);
        prime->primed = true;
    } else {
        /* Previous ship sprite, wherever it was (it may sit above the band).
         * BOTH ends clamp into the frame: a ship falling off at the far right
         * of the screen puts ship_x0 past 320, and max()-only clamping made
         * sx1 - sx0 negative -> a wild memcpy (the field freeze with amber
         * trap bars; reproduced under ASan as negative-size-param). */
        const unsigned sy0 = (unsigned)SR_CLAMP(prime->ship_y0, 0, (int32_t)FRAMEBUFFER_HEIGHT);
        const unsigned sy1 = (unsigned)SR_CLAMP(prime->ship_y1, 0, (int32_t)FRAMEBUFFER_HEIGHT);
        const unsigned sx0 = (unsigned)SR_CLAMP(prime->ship_x0, 0, (int32_t)FRAMEBUFFER_WIDTH);
        const unsigned sx1 = (unsigned)SR_CLAMP(prime->ship_x1, 0, (int32_t)FRAMEBUFFER_WIDTH);
        if (sx0 < sx1 && sy0 < sy1)
            fb_ops.copy_rect(f, u, sx0, sy0, sx1, sy1);
        fb_ops.copy_rows(f, u, HORIZON_Y, VIEW_BOTTOM_Y);
    }

    ship_visual = derive_ship_visual_state(scene);
    ship_placement = ship_screen_placement(scene, &ship_visual);

    /* (C: the pass collects its shapes first and waits for the copies above only to draw
     * them: Ali restores the band while the CPU works out what goes on it. Round 2: both
     * passes, when the platform prepares passes) */
    prepared[0] = prepared[1] = false;
    if (fb_ops.road_prepare) {
        static RoadPass rp[2];
        prepared[0] = make_road_pass(r, scene, DosRoadPhase_BeforeShip, &rp[0]) &&
                      fb_ops.road_prepare(&rp[0], 0);
        prepared[1] = prepared[0] && make_road_pass(r, scene, DosRoadPhase_AfterShip, &rp[1]) &&
                      fb_ops.road_prepare(&rp[1], 1);
    }
    if (prepared[0])
        fb_ops.road_send(f, 0);
    else if (!draw_demo_rows(r, f, scene, DosRoadPhase_BeforeShip)) {
        /* No TREKDAT (never with shipped data): the fallback repaints
         * arbitrary pixels, so hand the frame to the pure path outright. */
        prime->primed = false;
        render_play_scene(r, out, scene);
        return;
    }
    draw_ship_sprite(r, f, &ship_visual, ship_placement);
    sync_cpu(f);
    draw_ship_shadow(f, &ship_visual, ship_placement);
    if (prepared[1])
        fb_ops.road_send(f, 1);
    else
        draw_demo_rows(r, f, scene, DosRoadPhase_AfterShip);
    if (c->dash.pixels && r->dash_cache_ok) {
        /* C: the band from the cache (see PlaySceneCache), the art's rows above it, the
         * banner (in the road band) */
        update_dash(r, c, scene);
        fb_ops.copy_rows(f, &c->dash, VIEW_BOTTOM_Y, FRAMEBUFFER_HEIGHT);
        draw_fragment(r, f, &r->dash_top, PAL_DASH_BASE);
        if (!scene->is_demo && scene->did_win) {
            const char *text = scene->is_final_road ? "The End" : "Road Completed";
            sync_cpu(f);
            draw_rom_text(f, dos_text_centered_x((unsigned)strlen(text)), 80, text,
                          (uint8_t)(PAL_DASH_BASE + 7));
        }
    } else {
    /* Dashboard band back to backdrop (clears last frame's gauges/digits and
     * any ship spill), then the art blit -- the pure path's exact order, so an
     * exploding ship's low pixels end up under the cockpit frame identically. */
    fb_ops.copy_rows(f, u, VIEW_BOTTOM_Y, FRAMEBUFFER_HEIGHT);
    draw_archive_frame(r, f, &r->assets_.dashboard, 0, PAL_DASH_BASE);
    draw_dashboard_readouts(r, f, scene);
    }

    /* Ship rect for the next frame's restore: sprites are 24x30 cars blocks;
     * generous margins cost a few KB and make the bound unarguable. */
    prime->ship_x0 = ship_placement.sprite_left_x - 8;
    prime->ship_y0 = ship_placement.sprite_top_y - 8;
    prime->ship_x1 = ship_placement.sprite_left_x + 24 + 8;
    prime->ship_y1 = ship_placement.sprite_top_y + 30 + 8;
}

void renderer_render_scene(const Renderer *r, RenderedFrame *out, const RenderScene *scene)
{
    out->palette_stamp = 0;
    switch (scene->tag) {
    case RenderScene_Intro: render_intro(r, out, &scene->intro); break;
    case RenderScene_MainMenu: render_main_menu(r, out, &scene->main_menu); break;
    case RenderScene_HelpMenu: render_help_menu(r, out, &scene->help_menu); break;
    case RenderScene_SettingsMenu: render_settings_menu(r, out, &scene->settings_menu); break;
    case RenderScene_GoMenu: render_go_menu(r, out, &scene->go_menu); break;
    case RenderScene_DemoPlayback:
    case RenderScene_Gameplay:
        render_play_scene(r, out, &scene->play);
        break;
    }
    sync_cpu(&out->frame);
}

static void draw_archive_frame(const Renderer *r, FrameBuffer320x200 *frame,
                               const ImageArchive *archive, unsigned frame_index,
                               unsigned palette_base)
{
    unsigned k;
    if (frame_index >= archive->frame_count)
        return;
    for (k = 0; k < archive->frames[frame_index].count; ++k)
        draw_fragment(r, frame, &archive->frames[frame_index].fragments[k], palette_base);
}

static void draw_intro_picture(FrameBuffer320x200 *frame, const ImageFrame SR_FAR *fragment,
                               unsigned palette_base, float wipe)
{
    /* The wipe edge counts down 319 -> 0 (@0x484a). A row keeps showing background
     * for that many pixels: from the left on even rows, from the right on odd ones.
     * (C: lround(clamp(wipe) * 319): the wipe is e / 18 off 1; the float is kept) */
    const float w = SR_CLAMP(wipe, 0.0f, 1.0f);
    const int32_t edge = (int32_t)roundf_away(w * (float)(SCREEN_WIDTH - 1));
    unsigned y, x;
    sync_cpu(frame);
    for (y = 0; y < fragment->height; ++y) {
        const int32_t screen_y = (int32_t)fragment->y_offset + (int32_t)y;
        const bool background_at_left = (screen_y % 2) == 0;
        for (x = 0; x < fragment->width; ++x) {
            const int32_t screen_x = (int32_t)fragment->x_offset + (int32_t)x;
            uint8_t pixel_index;
            unsigned slot;
            if (background_at_left ? screen_x < edge
                                   : screen_x >= (int32_t)SCREEN_WIDTH - edge)
                continue;
            pixel_index = fragment->pixels.data[(uint32_t)y * fragment->width + x];
            if (fragment->transparent_zero && pixel_index == 0)
                continue;
            if (pixel_index >= fragment->palette.color_count)
                continue;
            slot = palette_base + pixel_index;
            if (slot > 0xFF)
                continue;
            fb_set_pixel(frame, (unsigned)screen_x, (unsigned)screen_y, (uint8_t)slot);
        }
    }
}

/* RVSTACK: this is the backdrop/dashboard blit -- the biggest per-frame
 * pixel loop after the road pass. Hoist the invariants (palette size and
 * the 0xFF slot ceiling fold into one bound; row pointers replace the
 * bounds-checked set_pixel) -- behaviour is identical, the console frame
 * cost is not.
 * C: the horizontal_fraction parameter (always 1 outside the debug views) is gone. */
static void draw_fragment(const Renderer *r, FrameBuffer320x200 *frame,
                          const ImageFrame SR_FAR *fragment, unsigned palette_base)
{
    const unsigned draw_width = fragment->width;
    const unsigned max_index =
        SR_MIN(fragment->palette.color_count, palette_base <= 0xFF ? 0x100 - palette_base : 0);
    unsigned y, x;
    (void)r;
    if (fb_ops.fragment && fb_ops.fragment(frame, fragment, palette_base))
        return;
    sync_cpu(frame);
    for (y = 0; y < fragment->height; ++y) {
        const unsigned sy = fragment->y_offset + y;
        const unsigned sx0 = fragment->x_offset;
        unsigned run;
        const uint8_t SR_FAR *src;
        uint8_t SR_FAR *dst;
        if (sy >= FRAMEBUFFER_HEIGHT)
            continue;
        if (sx0 >= FRAMEBUFFER_WIDTH)
            continue;
        run = SR_MIN(draw_width, FRAMEBUFFER_WIDTH - sx0);
        src = fragment->pixels.data + (uint32_t)y * fragment->width;
        dst = frame->pixels + sy * FRAMEBUFFER_WIDTH + sx0;
        if (fragment->transparent_zero) {
            for (x = 0; x < run; ++x) {
                const uint8_t p = src[x];
                if (p != 0 && p < max_index)
                    dst[x] = (uint8_t)(palette_base + p);
            }
        } else {
            for (x = 0; x < run; ++x) {
                const uint8_t p = src[x];
                if (p < max_index)
                    dst[x] = (uint8_t)(palette_base + p);
            }
        }
    }
}

static void draw_sprite_px(FrameBuffer320x200 *frame, uint8_t pixel_index, unsigned color_count,
                           bool transparent_zero, int32_t px, int32_t py, unsigned palette_base)
{
    unsigned slot;
    if (transparent_zero && pixel_index == 0)
        return;
    if (pixel_index >= color_count)
        return;
    slot = palette_base + pixel_index;
    if (slot > 0xFF)
        return;
    if (px < 0 || py < 0)
        return;
    /* Sprites live outside the road's shade range, so mark them as
     * "not road" and the shadow will leave them alone. (C: no shade plane: the
     * sprite's own index is one the shadow leaves alone) */
    fb_set_pixel(frame, (unsigned)px, (unsigned)py, (uint8_t)slot);
}

static void draw_sprite(FrameBuffer320x200 *frame, const ImageFrame *sprite, int32_t dest_x,
                        int32_t dest_y, unsigned scale, unsigned palette_base)
{
    unsigned y, x, sy, sx;
    sync_cpu(frame);
    for (y = 0; y < sprite->height; ++y)
        for (x = 0; x < sprite->width; ++x) {
            const uint8_t pixel_index = sprite->pixels.data[y * sprite->width + x];
            for (sy = 0; sy < scale; ++sy)
                for (sx = 0; sx < scale; ++sx)
                    draw_sprite_px(frame, pixel_index, sprite->palette.color_count,
                                   sprite->transparent_zero, dest_x + (int32_t)(x * scale + sx),
                                   dest_y + (int32_t)(y * scale + sy), palette_base);
        }
}

static void draw_sprite_far(FrameBuffer320x200 *frame, const ImageFrame SR_FAR *sprite,
                            int32_t dest_x, int32_t dest_y, unsigned palette_base)
{
    ImageFrame copy = *sprite;
    draw_sprite(frame, &copy, dest_x, dest_y, 1, palette_base);
}

static void draw_ship_shadow(FrameBuffer320x200 *frame, const DerivedShipVisualState *visual,
                             ShipScreenPlacement placement)
{
    /* EXE @0x33e1, called straight after the ship blit @0x329d. Five pre-drawn 29x9
     * silhouettes, one per five units of altitude, and none at all above 25. The
     * blit reads the paletted screen back and remaps the shade it finds rather than
     * blending anything, so the shadow only ever darkens the road surface. */
    const int32_t hover = visual->hover_units;
    const int32_t level = hover >= -32767 && hover <= 32767 ? (int32_t)((int)hover / DOS_SHADOW_STEP)
                                                            : hover / DOS_SHADOW_STEP;
    const uint32_t *mask;
    int32_t left, top;
    unsigned row, col;
    if (!visual->casts_shadow)
        return;
    if (level < 0 || level >= (int32_t)DOS_SHADOW_LEVELS)
        return;
    mask = DOS_SHIP_SHADOW_MASKS[level];
    /* Top-left corner: the same column as the ship sprite, and a row pinned to the
     * surface underneath it (@0x33fe-0x3417). */
    left = placement.sprite_left_x;
    top = placement.sprite_top_y + DOS_SHADOW_Y_OFFSET + hover;
    if (fb_ops.shadow && left > -400 && left < 400 && top > -400 && top < 400) {
        fb_ops.shadow(frame, mask, left, top);
        return;
    }

    for (row = 0; row < DOS_SHADOW_ROWS; ++row) {
        const int32_t py = top + (int32_t)row;
        /* (C: the mask's bits taken one by one from its two 16-bit halves, the row's pixels
         * through a pointer: the C++'s `1u << col` and the per-pixel calls were most of the
         * frame's C time on the 65816) */
        uint16_t bits = (uint16_t)mask[row];
        const uint16_t high = (uint16_t)(mask[row] >> 16);
        uint8_t SR_FAR *line;
        if (py < (int32_t)HORIZON_Y || py >= (int32_t)VIEW_BOTTOM_Y)
            continue;
        line = frame->pixels + (unsigned)py * FRAMEBUFFER_WIDTH;
        for (col = 0; col < DOS_SHADOW_COLUMNS; ++col) {
            const int32_t px = left + (int32_t)col;
            uint8_t shade, shaded;
            const bool bit = (bits & 1) != 0;
            bits >>= 1;
            if (col == 15)
                bits = high;
            if (!bit)
                continue;
            if ((uint32_t)px >= SCREEN_WIDTH) /* (px < 0 || px >= 320) */
                continue;
            /* C: the pixel is the shade (see the header) */
            shade = line[(unsigned)px];
            shaded = dos_shadow_shade(shade);
            if (shaded == shade)
                continue; /* sky, sprite or an already-dark band */
            /* Pure index remap, exactly the @0x3437 read-modify-write: the remapped
             * shade IS the new framebuffer byte (the road band starts at slot 0). */
            line[(unsigned)px] = (uint8_t)(PAL_ROAD_BASE + shaded);
        }
    }
}
