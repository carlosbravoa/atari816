/* hz_kbd.h - Digger's keys held now, for Horizon (upstream's sdl_kbd.h, with the
 * joystick added: port 1 moves player 1, port 2 player 2; the trigger fires) */
#ifndef HZ_KBD_H
#define HZ_KBD_H

bool kbd_async_key_state(int key);
bool kbd_joy(int port, unsigned bit);

#define rightpressed  (kbd_async_key_state(keycodes[0][0]) || kbd_joy(1, 8))
#define uppressed     (kbd_async_key_state(keycodes[1][0]) || kbd_joy(1, 1))
#define leftpressed   (kbd_async_key_state(keycodes[2][0]) || kbd_joy(1, 4))
#define downpressed   (kbd_async_key_state(keycodes[3][0]) || kbd_joy(1, 2))
#define f1pressed     (kbd_async_key_state(keycodes[4][0]) || kbd_joy(1, 16))
#define right2pressed (kbd_async_key_state(keycodes[5][0]) || kbd_joy(2, 8))
#define up2pressed    (kbd_async_key_state(keycodes[6][0]) || kbd_joy(2, 1))
#define left2pressed  (kbd_async_key_state(keycodes[7][0]) || kbd_joy(2, 4))
#define down2pressed  (kbd_async_key_state(keycodes[8][0]) || kbd_joy(2, 2))
#define f12pressed    (kbd_async_key_state(keycodes[9][0]) || kbd_joy(2, 16))

#endif
