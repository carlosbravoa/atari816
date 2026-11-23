/* The CPU reference renderer: composes intro/menu/help/settings art, world
 * backdrops, the DOS TREKDAT road pass, ship sprites, dashboard, and gauges
 * into a 320x200 8-bit indexed framebuffer plus a 256-entry palette per frame,
 * exactly as the DOS build renders into mode 13h over the VGA DAC. All palette
 * animation (the intro's CMAP slide, the white flash, brightness fades) happens
 * on the palette entries, never per pixel.
 *
 * The road is drawn by the decoded DOS TREKDAT span pipeline (scene_draw @0x2d03):
 * pre-baked run-length spans out of the eight scroll-phase snapshots, dispatched per
 * road cell, with the right half produced by the reverse rasterizer.
 *
 * C translation (the changes that are not one-to-one; PORTING-NOTES.md has them all):
 *  - ReferenceRenderer's methods are renderer_*() functions on a Renderer.
 *  - No shade plane. The C++ kept, beside the pixels, the road shade under each pixel
 *    for the ship's shadow to read back. The road band of the palette starts at 0, so a
 *    road pixel IS its shade, and every other pixel the shadow can meet (sky 0, backdrop
 *    0x8E+, ship 0x49+, dashboard 0x5C+) is one dos_shadow_shade() leaves alone: the
 *    shadow reads the pixels, as the DOS blit did (@0x3437). Proved by comparing every
 *    demo frame with the C++'s.
 *  - The debug views (Tab) and the projected fallback road (drawn only without
 *    TREKDAT.LZS) are not translated: development tools of the C++, all float.
 *  - The fades are integers that give the C++'s float results exactly (see the intro).
 *  - The hot loops go through `FbOps` (fills of spans, row and rectangle copies, a
 *    fragment's blit): plain C here, a platform may give faster ones (the Atari816's
 *    blitter and assembly); the pixels are the same.
 *  - Spans are clipped once at load (TREKDAT is fixed data) instead of every frame. */
#ifndef RENDERER_RENDERER_H
#define RENDERER_RENDERER_H

#include "core/app.h"
#include "data/dashboard.h"
#include "data/image.h"
#include "data/level.h"
#include "data/trekdat.h"

#define FRAMEBUFFER_WIDTH 320u
#define FRAMEBUFFER_HEIGHT 200u

/* The per-frame VGA DAC state: 256 RGB entries, assembled from the scene's
 * source CMAPs (road palette, archive CMAPs, dashboard) by the render_* methods. */
typedef struct {
    RgbColor colors[256];
} Palette256;

/* One palette index per pixel, as in mode 13h: 320 x 200, rows of 320 bytes (C: the
 * pixels are the caller's, in far memory on the Atari816: the page being drawn) */
typedef struct {
    uint16_t width;
    uint16_t height;
    uint8_t SR_FAR *pixels;
} FrameBuffer320x200;

void fb_clear(FrameBuffer320x200 *f, uint8_t index);
void fb_fill_rect(FrameBuffer320x200 *f, int32_t x, int32_t y, int32_t width, int32_t height,
                  uint8_t index);
void fb_set_pixel(FrameBuffer320x200 *f, unsigned x, unsigned y, uint8_t index);
uint8_t fb_pixel_at(const FrameBuffer320x200 *f, unsigned x, unsigned y);

/* A rendered frame: the index buffer plus the palette it must be shown through. */
typedef struct {
    FrameBuffer320x200 frame;
    Palette256 palette;
} RenderedFrame;

/* RVSTACK: state for the incremental play-scene path (the console port).
 * render_play_scene rebuilds all 64000 pixels every frame -- a pure function,
 * which is what the equivalence tests need, and also exactly what the DOS
 * game did NOT do on a 386: it drew backdrop + dashboard once per road and
 * per frame rewrote only the road viewport, the ship and the gauges. This
 * cache restores that structure: `underlay` holds clear+backdrop+dashboard
 * for the current road, and the incremental renderer copies back only the
 * bands the previous frame dirtied. Output is byte-identical to the pure
 * path (verified by the twin's SKY_VERIFY dual-render compare).
 * C: `frame_primed` is per framebuffer: a platform that draws into two or three pages in
 * turn passes the page's own `PagePrime` (what that page last showed). */
typedef struct {
    bool primed;                /* the page holds a frame of this road */
    int32_t ship_x0, ship_y0, ship_x1, ship_y1;
} PagePrime;

typedef struct {
    FrameBuffer320x200 underlay;
    Palette256 palette;
    const RgbColor SR_FAR *road_palette;  /* road-change detection */
    unsigned world_index;
    bool valid;                 /* underlay/palette match the current road */
    unsigned generation;        /* C: bumped when the underlay is rebuilt */
    /* C: the dashboard band, rows DASHBOARD_TOP..199, as the incremental path draws it
     * each frame (the underlay's rows, the dashboard art, the gauges, the empty-tank
     * label, the gravity readout), kept up to date by drawing only what changed: the
     * gauge segments whose state changed (as the DOS HUD did), the label's swap. Then a
     * frame copies the band (one blit on the Atari816) and draws the art's rows above it.
     * The C++ redrew it all every frame: 4,000 pixels of gauges, 22,000 of art. The
     * caller gives the pixels (dash.pixels; NULL: no cache, the C++'s way). */
    FrameBuffer320x200 dash;
    bool dash_valid;
    unsigned dash_level[3];
    unsigned dash_warn;         /* 0, or 1 + which label is swapped (oxygen, fuel) */
    uint16_t dash_gravity;
    unsigned dash_generation;
} PlaySceneCache;

/* the ship's 77 sprites, turned (C: CarAtlas holds pointers into one array) */
typedef struct {
    bool keyed_ok;              /* C: every pixel of every sprite is in the palette (FbOps.sprite) */
    ImageFrame explosion_frames[14];
    unsigned explosion_count;
    ImageFrame exact_ship_frames[63];
    unsigned exact_count;
    ImageFrame destroyed;
    bool valid;
} CarAtlas;

typedef struct {
    ImageArchive intro;
    ImageArchive anim;
    ImageArchive main_menu;
    ImageArchive help_menu;
    ImageArchive settings_menu;
    ImageArchive go_menu;
    ImageArchive cars;
    ImageArchive worlds[10];
    unsigned world_count;
    ImageArchive dashboard;
    TrekdatArchive trekdat;
    HudFragmentPack oxygen_gauge;
    HudFragmentPack fuel_gauge;
    HudFragmentPack speed_gauge;
} AttractModeAssets;

/* source_root: the folder of the game's files (plat_asset_path finds each) */
void attract_mode_assets_load_from_root(AttractModeAssets *a, const char *source_root);

/* ---- ship visual derivation (public so the placement helpers can share it) -- */

typedef enum { ShipSpriteKind_Alive, ShipSpriteKind_Exploding, ShipSpriteKind_Destroyed } ShipSpriteKind;
typedef enum { ShipBank_Left, ShipBank_Center, ShipBank_Right } ShipBank;

typedef struct {
    ShipSpriteKind sprite_kind;
    ShipBank bank;
    bool thrust_on;
    bool jumping;
    unsigned explosion_frame;
    bool has_exact_ship_frame_index;
    unsigned exact_ship_frame_index;
    int32_t ship_screen_bias_x;
    int32_t vertical_offset_y;
    /* Height of the surface currently supporting the ship (the road, or the top of
     * a raised block), so the shadow can sit on it instead of a fixed row. */
    int32_t support_y_128;
    bool on_surface;
    /* False once the ship is dead: a crashed ship has no shadow, and a ship that
     * fell off the road has no road left under it to cast one on. */
    bool casts_shadow;
    /* Altitude above that surface in whole world units -- ds:0xe40, the value
     * scene_draw uses to pick which of the five shadow silhouettes to draw. */
    int32_t hover_units;
} DerivedShipVisualState;

typedef struct {
    int32_t sprite_center_x;
    int32_t sprite_center_y;
    int32_t shadow_center_x;
    int32_t shadow_center_y;
    /* The exact DOS blit corner: left column = x - 110, top row = 157 - y
     * (@0x324e-0x325a). The shadow is placed relative to these, not to the centre. */
    int32_t sprite_left_x;
    int32_t sprite_top_y;
} ShipScreenPlacement;

/* a span of a TREKDAT shape, clipped to the road band and the screen at load: the
 * offsets of its first pixel drawn on the left and on the mirrored right, its width */
typedef struct {
    uint16_t left;
    uint16_t right;
    uint8_t width;
} PreparedSpan;

typedef struct {
    const PreparedSpan SR_FAR *spans;
    uint16_t count;
    uint8_t color;              /* the shape's own colour code */
} PreparedShape;

/* one shape to draw: the road pass collects them in order and has them drawn together
 * (FbOps.span_jobs) */
typedef struct {
    const PreparedShape SR_FAR *shape;
    uint8_t index;              /* the palette index */
    uint8_t right;              /* 1: the mirrored offsets */
} SpanJob;

/* the platform's fast paths (FbOps): defaults are plain C */
typedef struct {
    /* `count` spans of `shape`: fb[(side ? right : left) .. + width) = index */
    void (*spans)(FrameBuffer320x200 *f, const PreparedSpan SR_FAR *spans, unsigned count,
                  bool right, uint8_t index);
    /* n jobs, in order (each its shape's spans, as spans() draws them) */
    void (*span_jobs)(FrameBuffer320x200 *f, const SpanJob *jobs, unsigned n);
    /* rows y0 .. y1 - 1 of u into f */
    void (*copy_rows)(FrameBuffer320x200 *f, const FrameBuffer320x200 *u, unsigned y0,
                      unsigned y1);
    /* the rectangle x0 .. x1 - 1, y0 .. y1 - 1 of u into f */
    void (*copy_rect)(FrameBuffer320x200 *f, const FrameBuffer320x200 *u, unsigned x0,
                      unsigned y0, unsigned x1, unsigned y1);
    /* draw_fragment (horizontal_fraction 1): returns false to have the C do it */
    bool (*fragment)(FrameBuffer320x200 *f, const ImageFrame SR_FAR *fragment, unsigned palette_base);
    /* about to draw by the CPU into f (what the ops sent must be done) */
    void (*sync)(FrameBuffer320x200 *f);
    /* draw_sprite at scale 1 of a sprite whose pixels are all in its palette: pixel p != 0
     * drawn as p + add, clipped to the frame; false to have the C do it */
    bool (*sprite)(FrameBuffer320x200 *f, const uint8_t SR_FAR *pixels, unsigned w, unsigned h,
                   int32_t x, int32_t y, uint8_t add);
    /* draw_ship_shadow's loop: the mask's rows at (left, top) over f, rows 24..137 and
     * columns 0..319, each pixel under a bit through dos_shadow_shade; NULL: the C */
    void (*shadow)(FrameBuffer320x200 *f, const uint32_t *mask, int32_t left, int32_t top);
    /* draw_dos_pointer_row's cells (both sides, the four slots): the jobs they add, in
     * order, written to jobs (at most 96) -> how many; NULL: the C below */
    unsigned (*road_row)(const uint16_t SR_FAR *ptr24, const uint16_t *current_row,
                         const uint16_t *nearer_row, const PreparedShape SR_FAR *prepared,
                         unsigned shape_count, SpanJob *jobs);
} FbOps;

extern FbOps fb_ops;

typedef struct {
    AttractModeAssets assets_;
    CarAtlas car_atlas_;
    /* the TREKDAT shapes clipped, per record: [record][shape] */
    PreparedShape SR_FAR *prepared[16];
    /* C: the dashboard art's rows above DASHBOARD_TOP (drawn over the road each frame) and
     * whether the band cache can be used (the gauges, the labels and the readout do not
     * overlap: then drawing only what changed gives the same pixels) */
    ImageFrame dash_top;
    bool dash_cache_ok;
} Renderer;

void renderer_init(Renderer *r);   /* after its assets_ are loaded */
void renderer_render_scene(const Renderer *r, RenderedFrame *out, const RenderScene *scene);
/* RVSTACK: byte-identical to render_play_scene, at the DOS write budget.
 * `out.frame` must persist across calls (it carries the previous frame);
 * reset prime->primed after rendering anything else into it. */
void renderer_render_play_scene_incremental(const Renderer *r, RenderedFrame *out,
                                            PlaySceneCache *cache, PagePrime *prime,
                                            const DemoPlaybackState *scene);

DerivedShipVisualState derive_ship_visual_state(const DemoPlaybackState *scene);

/* statistics of the last frame (C: for the measurements) */
extern unsigned long renderer_span_count, renderer_span_pixels;

#endif
