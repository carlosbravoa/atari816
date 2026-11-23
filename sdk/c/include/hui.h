/* hui.h - Horizon's controls library for C programs: windows with buttons, labels, text
 * fields, lists, scroll bars, alerts, the file dialog, small dialogs, pop-up menus.
 *
 *   #include <horizon.h>
 *   #include <hui.h>
 *
 * hcc links the library (horizon/user/ui*.s and ulib, assembled by the SDK) into a
 * program that uses it, and only the routines it uses; both code models. Tutorial and
 * reference: sdk/docs/c/apps.md. The library's own documentation:
 * sdk/docs/reference/controls.md and horizon/user/ui.inc (every C name here is the
 * assembly name).
 *
 * THE RULE: what the library keeps or reads through its own 16-bit pointers must be in
 * the program's code bank: the controls, control lists, alert / dialog / ask blocks, the
 * buffers of fields and the strings they point to. Every near C object is there (globals,
 * statics, string constants, malloc'd blocks, locals): only __far data is not. Strings
 * passed straight to a function (ui_text, ui_fdset, a path) are copied for the call (at
 * most 255 chars). A control should live as long as its window: make it global or static.
 *
 * Events: read them with ui_getev(), not hz_win_event(): the library needs to see them.
 * The loop:
 *
 *     for (;;) {
 *         void *c;
 *         if (ui_getev(0))                 continue;    (0 = wait)
 *         switch (ui_event(ctls, &c)) {                 (the controls take theirs)
 *         case UA_CLICK:  if (c == &b_ok) ...           (a button)
 *         case UA_CHANGE: ...                           (a field, a list, a scroll bar)
 *         case UA_NONE:   ui_ev.type: WE_CLOSE, WE_MENU, WE_KEY, WE_RESIZE, WE_TICK ...
 *         }
 *     }
 *
 * Callbacks (a list's row function, ui_setcpcb's function) run inside a library call:
 * they may compute and draw (ui_rect, ui_text, ui_bevel, ui_copy, ui_twidth, hz_ calls,
 * printf), but must not call a control or dialog routine (ui_draw, ui_event, ui_lsset,
 * ui_alert, ui_getev, ...: those marked so stop the program with a message) and must
 * return quickly.
 */
#ifndef HUI_H
#define HUI_H

#ifndef HORIZON_H
#include <horizon.h>
#endif

#include "huigen.h"         /* the constants */

/* ---- values */

#define UI_NONE     0xFFFFu     /* no row (ui_lssel, ls.sel), no item (ui_popup) */
#define UI_NOPAPER  0xFF        /* ui_text: no paper behind the text */
/* ui_text's colors */
#define UI_INK(ink, paper)  ((unsigned)(ink) | (unsigned)(paper) << 8)
/* ui_rect's op */
#define UI_FILL(c)          ((unsigned long)(WD_FILL | (unsigned)(c) << 8))
#define UI_FRAME(c)         ((unsigned long)(WD_FRAME | (unsigned)(c) << 8))
#define UI_DITHER(c1, c2)   ((unsigned long)(WD_DITHER | (unsigned)(c1) << 8) | \
                             (unsigned long)(c2) << 16)

/* where every C list's row callback goes in: the binding's routine (ui/lib/row.s),
 * linked into the program */
void hui_rowtramp(void);
#define HUI_ROWCB   ((unsigned short)hui_rowtramp)

#define HUI_FORWARD
#include "huigen.h"         /* the structures' names: ui_ctl, ui_button, ui_list, ... */

/* a control list: static ui_ctlref name[] = { &ctl1, &ctl2, ..., 0 } (the Tab order) */
typedef void __near *ui_ctlref;

/* what a list's row function gets besides the list and the row */
typedef struct {
    unsigned short win;         /* the window */
    short x, y;                 /* the row's top left (inside the box): an icon may be
                                   drawn in the list's indent pixels from x */
    unsigned short sel;         /* 1 if the row is selected */
} ui_rowinfo;

/* a list's row function -> the text of row (any bank; the library copies it, so a static
 * buffer may be reused for every row) */
typedef const char *(*ui_rowfn)(ui_list *ls, unsigned row, const ui_rowinfo *ri);

/* ui_setcpcb's function: nonzero cancels the copy */
typedef int (*ui_cpfn)(const char *name, unsigned kdone, unsigned long size);

#define HUI_TYPES
#include "huigen.h"         /* the structures (laid out from ui.inc), the functions, the
                               library's variables */

/* static initialisers: static ui_button ok = UI_BUTTON(8, 40, 64, UF_DEFAULT, "OK"); */
#define UI_LABEL(x, y, w, flags, text) \
    { UT_LABEL, 0, (x), (y), (w), UI_LINE, (flags), (text) }
#define UI_BUTTON(x, y, w, flags, label) \
    { UT_BUTTON, 0, (x), (y), (w), UI_BTNH, (flags), (label) }
#define UI_FIELD(x, y, w, flags, buf, size) \
    { UT_FIELD, 0, (x), (y), (w), UI_FLDH, (flags), (buf), (size), 0, 0, 0, 0 }
#define UI_VSCROLL(x, y, h, max, page, step) \
    { UT_VSCROLL, 0, (x), (y), UI_SBW, (h), 0, 0, (max), (page), (step), 0, 0 }
#define UI_HSCROLL(x, y, w, max, page, step) \
    { UT_HSCROLL, 0, (x), (y), (w), UI_SBW, 0, 0, (max), (page), (step), 0, 0 }
#define UI_LIST(x, y, w, h, flags, rowfn) \
    { UT_LIST, 0, (x), (y), (w), (h), (flags), 0, UI_NONE, 0, HUI_ROWCB, 0, 0, \
      { 0 }, (rowfn) }

#endif
