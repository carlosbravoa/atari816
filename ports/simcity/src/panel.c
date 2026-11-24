/* panel.c - the top of the screen (framebuffer rows 336-383, screen lines 0-47): the menu
 * bar with the date and the funds, the tools (a button each, a tile of the thing it
 * builds), the demand for residential, commercial and industrial zones, the speed, and the
 * message line with the tool's name and cost.
 * Copyright (C) 2026 the Atari816 project. GPL-3 with EA's additional terms. */
#include <stdio.h>
#include <string.h>
#include "sim.h"
#include "ui.h"

int cur_tool = dozeState;
char msg_line[96];
char date_str[32], funds_str[40], city_name[40];
int demand_r, demand_c, demand_i;
unsigned char panel_dirty = 1;

/* the toolbar, left to right */
static const unsigned char tools[] = {
    dozeState, roadState, rrState, wireState, parkState, residentialState,
    commercialState, industrialState, policeState, fireState, stadiumState, seaportState,
    powerState, nuclearState, airportState, queryState
};
#define NTOOLS (sizeof tools)
static const unsigned short tool_tile[] = {
    RUBBLE, 66, LHRAIL, LHPOWER, FOUNTAIN, FREEZ, COMCLR, INDCLR, POLICESTATION,
    FIRESTATION, STADIUM, PORT, POWERPLANT, NUCLEAR, RADAR, 0
};
const char *const tool_label[] = {
    "Bulldozer", "Road", "Rail", "Power line", "Park", "Residential zone",
    "Commercial zone", "Industrial zone", "Police station", "Fire station", "Stadium",
    "Seaport", "Coal power plant", "Nuclear power plant", "Airport", "Query"
};
static const char *const tool_key[] = {
    "D", "R", "T", "W", "K", "1", "2", "3", "P", "F", "S", "E", "O", "N", "A", "Q"
};
extern QUAD CostOf[];

static const char *const menus[] = { "File", "Speed", "Disasters", "Windows", "Options" };
static const int menu_x[] = { 4, 52, 108, 196, 268, 340 };

int tool_index(int state)
{
    unsigned i;
    for (i = 0; i < NTOOLS; i++)
        if (tools[i] == state)
            return (int)i;
    return -1;
}

static void bevel(int x, int y, int w, int h, int down)
{
    hg_fill(x, y, w, h, C_PANEL);
    hg_hline(x, y, w, down ? C_SHADOW : C_LIGHT);
    hg_vline(x, y, h, down ? C_SHADOW : C_LIGHT);
    hg_hline(x, y + h - 1, w, down ? C_LIGHT : C_SHADOW);
    hg_vline(x + w - 1, y, h, down ? C_LIGHT : C_SHADOW);
}

static const char *const speeds[] = { "Paused", "Slow", "Medium", "Fast" };

void panel_draw(void)
{
    unsigned i;
    int k, x;
    char buf[64];

    if (!panel_dirty || !img_big)
        return;
    panel_dirty = 0;
    hg_origin(0, PANEL_FB);
    hg_fill(0, 0, FB_STRIDE, PANEL_H, C_PANEL);
    /* the menu bar */
    hg_fill(0, 0, 640, 12, C_LIGHT);
    hg_hline(0, 11, 640, C_SHADOW);
    for (i = 0; i < 5; i++)
        hg_text(menu_x[i] + 4, 1, menus[i], C_TEXT);
    hg_text(352, 1, date_str, C_TEXT);
    hg_text(456, 1, funds_str, C_TEXT);
    /* the tools */
    for (i = 0; i < NTOOLS; i++) {
        x = 4 + (int)i * 26;
        bevel(x, 13, 24, 22, tools[i] == cur_tool);
        if (tools[i] == cur_tool)
            hg_rect(x, 13, 24, 22, C_SEL);
        if (tool_tile[i])
            hg_draw_part(img_big, (tool_tile[i] & 255) << 4, (tool_tile[i] >> 8) << 4, 16, 16,
                         x + 4, 16);
        else
            hg_text(x + 8, 19, "?", C_TEXT);
    }
    /* the demand: residential, commercial, industrial (upstream's valves / 100, -15..15) */
    x = 426;
    hg_fill(x, 13, 40, 22, C_WIN);
    hg_rect(x, 13, 40, 22, C_SHADOW);
    hg_hline(x + 1, 24, 38, C_SHADOW);
    for (k = 0; k < 3; k++) {
        int v = k == 0 ? demand_r : k == 1 ? demand_c : demand_i, h = v * 10 / 15;
        int c = k == 0 ? C_GREEN : k == 1 ? C_BLUE : C_YELLOW;
        if (h > 10) h = 10;
        if (h < -10) h = -10;
        if (h > 0)
            hg_fill(x + 6 + k * 11, 24 - h, 7, h, c);
        else if (h < 0)
            hg_fill(x + 6 + k * 11, 25, 7, -h, c);
    }
    /* speed, zoom, city */
    sprintf(buf, "%s%s", speeds[sim_paused ? 0 : SimMetaSpeed & 3], zoom8 ? "  1:2" : "");
    hg_text(474, 14, buf, C_TEXT);
    hg_text(474, 25, city_name, C_SHADOW);
    /* the message line */
    hg_fill(0, 36, 640, 12, C_WIN);
    hg_hline(0, 36, 640, C_SHADOW);
    hg_text(4, 37, msg_line, C_TEXT);
    k = tool_index(cur_tool);
    if (k >= 0) {
        if (CostOf[cur_tool])
            sprintf(buf, "%s ($%ld) [%s]", tool_label[k], (long)CostOf[cur_tool], tool_key[k]);
        else
            sprintf(buf, "%s [%s]", tool_label[k], tool_key[k]);
        hg_text(636 - (int)strlen(buf) * 8, 37, buf, C_SHADOW);
    }
    hg_origin(0, 0);
}

void panel_message(const char *s)
{
    strncpy(msg_line, s, sizeof msg_line - 1);
    msg_line[56] = 0;                   /* (the tool's name keeps the right side) */
    panel_dirty = 1;
}

/* a click at screen (x, y), y < 48 */
int panel_click(int x, int y)
{
    unsigned i;
    if (y < 12) {
        for (i = 0; i < 5; i++)
            if (x >= menu_x[i] && x < menu_x[i + 1] - 4) {
                menu_open((int)i);
                return 1;
            }
        return 1;
    }
    if (y >= 13 && y < 35)
        for (i = 0; i < NTOOLS; i++)
            if (x >= 4 + (int)i * 26 && x < 4 + (int)i * 26 + 24) {
                game_tool(tools[i]);
                return 1;
            }
    return 1;
}
