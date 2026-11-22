/* hz_kbd.c - Digger's keyboard and joysticks for Horizon (upstream's sdl_kbd.c): the keys
 * are HID usages, which are SDL's scancodes, so upstream's key table stays as it is; a
 * queue of the keys pressed (getkey, kbhit) from hgame's hg_key_next. */
#include <string.h>
#include <hgame.h>
#include "def.h"
#include "hardware.h"
#include "input.h"
#include "hz_kbd.h"
#include "hz_plat.h"

/* upstream's defaults (sdl_kbd.c), as HID usages; Exit: F10 or Esc (F10 alone in the
 * original; Esc is what leaves a program here); Pause: Space or P */
int keycodes[NKEYS][5] = {
    {0x4F, -2, -2, -2, -2},         /* 1 Right: cursor right */
    {0x52, -2, -2, -2, -2},         /* 1 Up */
    {0x50, -2, -2, -2, -2},         /* 1 Left */
    {0x51, -2, -2, -2, -2},         /* 1 Down */
    {0x3A, -2, -2, -2, -2},         /* 1 Fire: F1 */
    {0x16, -2, -2, -2, -2},         /* 2 Right: S */
    {0x1A, -2, -2, -2, -2},         /* 2 Up: W */
    {0x04, -2, -2, -2, -2},         /* 2 Left: A */
    {0x1D, -2, -2, -2, -2},         /* 2 Down: Z */
    {0x2B, -2, -2, -2, -2},         /* 2 Fire: Tab */
    {0x17, -2, -2, -2, -2},         /* Cheat: T */
    {0x57, -2, -2, -2, -2},         /* Accelerate: keypad + */
    {0x56, -2, -2, -2, -2},         /* Brake: keypad - */
    {0x40, -2, -2, -2, -2},         /* Music: F7 */
    {0x42, -2, -2, -2, -2},         /* Sound: F9 */
    {0x43, 0x29, -2, -2, -2},       /* Exit: F10, Esc */
    {0x2C, 0x13, -2, -2, -2},       /* Pause: Space, P */
    {0x11, -2, -2, -2, -2},         /* Change mode: N */
    {0x41, -2, -2, -2, -2}};        /* Save DRF: F8 */

#define KBLEN 30
static unsigned kbuf[KBLEN];
static int klen;

/* after each hgame frame: the keys pressed into the queue (upstream's SDL event filter) */
void hzk_poll(void)
{
    unsigned k;
    while ((k = hg_key_next()) != 0) {
        if (klen == KBLEN) {
            --klen;
            memmove(kbuf, kbuf + 1, klen * sizeof kbuf[0]);
        }
        kbuf[klen++] = k;
    }
}

bool kbd_async_key_state(int key)
{
    return key > 0 && hg_key((unsigned)key);
}

bool kbd_joy(int port, unsigned bit)
{
    return (hg_joy((unsigned)port) & bit) != 0;
}

void initkeyb(void)
{
}

void restorekeyb(void)
{
}

/* the next key: its HID usage (scancode) or its character (sym, for the initials) */
int16_t getkey(bool scancode)
{
    unsigned k;
    while (!kbhit())
        gethrt(true, 1);
    k = kbuf[0];
    --klen;
    memmove(kbuf, kbuf + 1, klen * sizeof kbuf[0]);
    if (scancode)
        return (int16_t)(k & 0xFF);
    return (int16_t)(k >> 8);
}

bool kbhit(void)
{
    hzk_poll();
    return klen > 0;
}
