/* ui.h - Micropolis's front end on the Atari816 (hgame, full screen 640 x 360): the
 * shared state of game.c (the loop, input, tools), view.c (the map: a ring of tiles that
 * Marga scrolls, the moving things as hardware sprites), panel.c (menus, toolbar, status,
 * messages) and dialogs.c (the windows: budget, evaluation, graphs, overview map, files,
 * new city, scenarios), data.c (the art and the sounds).
 * Copyright (C) 2026 the Atari816 project. GPL-3 with EA's additional terms. */
#ifndef MICROPOLIS_UI_H
#define MICROPOLIS_UI_H

#include <hgame.h>

/* ---------------------------------------------------------------- the framebuffer
 * 656 bytes a row (41 tiles of 16, 82 of 8): rows 0-335 the ring of map tiles (21 rows of
 * 16 or 40 of 8), 336-383 the panel (screen lines 0-47), 384-695 the window page (shown
 * instead of the map from screen line 48 while a menu or window is open) */
#define FB_STRIDE   656
#define FB_ROWS     696
#define PANEL_FB    336
#define PANEL_H     48
#define PAGE_FB     384
#define VIEW_W      640
#define VIEW_H      312

/* ---------------------------------------------------------------- colours (palette
 * entries the game sets; 0-15 stay the system's, the pointer uses them; 16-29 the tiles',
 * 128-255 the sprites' banks) */
#define C_BLACK     32
#define C_WHITE     33
#define C_PANEL     34      /* light grey */
#define C_SHADOW    35      /* dark grey */
#define C_LIGHT     36      /* white-ish edge */
#define C_TEXT      37      /* near black */
#define C_SEL       38      /* selection: blue */
#define C_SELTEXT   39
#define C_WIN       40      /* a window's paper */
#define C_TITLE     41      /* a window's title bar */
#define C_RED       42
#define C_GREEN     43
#define C_BLUE      44
#define C_YELLOW    45
#define C_CURSOR    46      /* the tool's frame */
#define C_DIM       47
#define C_GRAPH     48      /* 48-53: the graphs' six lines */
#define C_RAMP      56      /* 56-71: the overlays' scale, low to high */

/* ---------------------------------------------------------------- data.c */
extern hg_image *img_big, *img_small;   /* the tiles: 16 and 8 pixels */
extern unsigned char __far *mini_tiles; /* 960 x 9: the overview's 3 x 3 tiles */
int data_load(void);                    /* MICROPOL.GFX and the sounds; -1 failed */
/* a sprite image: type 1-8, frame 0.., part 0-3 (full size) or 4 (half): its 24-bit
 * address (0: none) */
unsigned long data_sprite(unsigned type, unsigned frame, unsigned part);
unsigned data_sprite_size(unsigned type);       /* 32 or 48 */
void snd_play(const char *name, int semis);     /* upstream's names, "Explosion-High" */
extern unsigned char sound_on;

/* ---------------------------------------------------------------- view.c */
extern int cam_x, cam_y;                /* the view's top left, in pixels of its zoom */
extern unsigned char zoom8;             /* 1: tiles of 8 pixels */
extern unsigned tile_px;                /* 16 or 8 */
void view_init(void);
void view_zoom(int z8);                 /* change the zoom, keeping the middle */
void view_center(int tx, int ty);       /* a tile in the middle */
void view_scroll(int dx, int dy);       /* pixels */
void view_update(void);                 /* the tiles that changed, the sprites */
void view_send(void);                   /* the scroll registers (each frame) */
void view_page(int on);                 /* the window page instead of the map */
void view_invalidate(void);             /* redraw every slot */
void view_cursor(int tx, int ty, int size, int on);   /* the tool's frame */
void view_shake(void);
void view_copy_to_page(void);
extern unsigned char scratch[1080];     /* (view.c: a buffer the windows share) */
void view_resend(void);
extern unsigned char page_on;
extern unsigned long view_draws;        /* tiles drawn (statistics) */

/* ---------------------------------------------------------------- panel.c */
extern int cur_tool;                    /* a tool state of upstream (sim.h) */
extern char msg_line[96];
extern char date_str[32], funds_str[40], city_name[40];
extern int demand_r, demand_c, demand_i;
extern unsigned char panel_dirty;
void panel_draw(void);                  /* when panel_dirty */
int panel_click(int x, int y);          /* 1 if the panel took it */
void panel_message(const char *s);
int tool_index(int state);
extern const char *const tool_label[];

/* ---------------------------------------------------------------- dialogs.c */
enum { DLG_NONE, DLG_MENU, DLG_BUDGET, DLG_EVAL, DLG_GRAPH, DLG_MAP, DLG_LOAD, DLG_SAVE,
       DLG_NEW, DLG_SCEN, DLG_QUERY, DLG_MSG, DLG_QUIT };
extern int dlg;                         /* the window open */
void dlg_open(int which, int arg);
void dlg_close(void);
void dlg_click(int x, int y, int button);   /* page coordinates */
void dlg_key(unsigned key, unsigned ch, unsigned mods);
void dlg_tick(void);                    /* each frame while open (refreshes) */
void menu_open(int m);                  /* the menu bar's menu m */
extern char query_text[6][48];
extern char eval_strs[18][40];
extern unsigned char eval_valid;

/* ---------------------------------------------------------------- game.c */
extern unsigned char quit_game;
extern char app_dir[128];
void game_new_city(unsigned seed, int level);
int game_load(const char *path);
int game_save(const char *path);
void game_scenario(int n);
void game_speed(int s);
void game_tool(int state);
void game_disaster(int d);
extern unsigned last_seed;
extern long frames_late;

#endif
