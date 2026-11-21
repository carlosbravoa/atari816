/* joystick.h - cc65's joystick API for Horizon (Atari816): the two DB9 joystick ports.
 * No driver to load: joy_install accepts anything. hcc links it by itself.
 *
 *   #include <joystick.h>
 *   joy_install(joy_static_stddrv);
 *   unsigned char j = joy_read(JOY_1);
 *   if (JOY_UP(j)) ...
 *
 * Do not include horizon.h after this header: horizon.h's JOY_UP .. JOY_RIGHT are plain
 * numbers (the same bits), these are cc65's macros of a value. */
#ifndef JOYSTICK_H
#define JOYSTICK_H

#undef JOY_UP
#undef JOY_DOWN
#undef JOY_LEFT
#undef JOY_RIGHT

#define JOY_ERR_OK          0
#define JOY_ERR_NO_DRIVER   1
#define JOY_ERR_CANNOT_LOAD 2
#define JOY_ERR_INV_DRIVER  3
#define JOY_ERR_NO_DEVICE   4

#define JOY_1 0
#define JOY_2 1

#define JOY_UP_MASK    0x01
#define JOY_DOWN_MASK  0x02
#define JOY_LEFT_MASK  0x04
#define JOY_RIGHT_MASK 0x08
#define JOY_BTN_1_MASK 0x10
#define JOY_FIRE_MASK  JOY_BTN_1_MASK

#define JOY_UP(v)    ((v) & JOY_UP_MASK)
#define JOY_DOWN(v)  ((v) & JOY_DOWN_MASK)
#define JOY_LEFT(v)  ((v) & JOY_LEFT_MASK)
#define JOY_RIGHT(v) ((v) & JOY_RIGHT_MASK)
#define JOY_BTN_1(v) ((v) & JOY_BTN_1_MASK)
#define JOY_FIRE(v)  JOY_BTN_1(v)

/* the "drivers": accepted and ignored */
extern const unsigned char joy_static_stddrv[];
#define joy_stddrv ""

unsigned char joy_install(const void *driver);
unsigned char joy_load_driver(const char *driver);
unsigned char joy_uninstall(void);
unsigned char joy_unload(void);
unsigned char joy_count(void);
/* JOY_1 or JOY_2 -> the directions and the button (the masks above), read now */
unsigned char joy_read(unsigned char joy);

#endif
