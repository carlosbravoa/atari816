/* horizon/compat/SDL2/SDL.h - the names of SDL2 that SDLPoP's game files (src/) use, for
 * the Atari816 port: fixed-size types, scancodes (SDL's scancodes are USB HID usages, as
 * Horizon's keys are), rectangles, a surface that is a rectangle of the framebuffer or of
 * the image atlas (horizon/hz_video.c), memory RWops (the replay's options), and the few
 * calls the game makes itself. The rest of SDL's role is horizon/hz_*.c. */
#ifndef HZ_SDL_H
#define HZ_SDL_H

#include <stddef.h>
#include <stdint.h>

typedef unsigned char Uint8;
typedef signed char Sint8;
typedef unsigned short Uint16;
typedef short Sint16;
typedef unsigned long Uint32;
typedef long Sint32;
typedef unsigned long long Uint64;
typedef long long Sint64;
typedef enum { SDL_FALSE = 0, SDL_TRUE = 1 } SDL_bool;

#define SDL_LIL_ENDIAN 1234
#define SDL_BIG_ENDIAN 4321
#define SDL_BYTEORDER SDL_LIL_ENDIAN
#define SDL_SwapLE16(x) (x)
#define SDL_SwapLE32(x) (x)
#define SDL_SwapBE16(x) ((Uint16)(((Uint16)(x) << 8) | ((Uint16)(x) >> 8)))
#define SDL_SwapBE32(x) hz_swap32(x)
Uint32 hz_swap32(Uint32 x);
#define SDL_COMPILE_TIME_ASSERT(name, x) typedef int SDL_dummy_ ## name[(x) * 2 - 1]
#define SDL_VERSION_ATLEAST(a, b, c) 1
#define SDL_ALPHA_OPAQUE 255
#define SDL_ALPHA_TRANSPARENT 0

typedef struct SDL_Rect { int x, y, w, h; } SDL_Rect;
typedef struct SDL_Color { Uint8 r, g, b, a; } SDL_Color;

/* A surface (8 bytes: the main bank is small): w x h pixels. b = HZS_IMAGE: an image of
 * the atlas, a = its record in POP.DAT (place, mirrored copy, mask: hz_data.c); HZS_MIRROR:
 * the same image mirrored; otherwise a rectangle of the framebuffer at (a, b) (the screen,
 * the offscreen buffer, a peel). hz_video.c draws them. */
typedef struct SDL_Surface {
    int w, h;
    unsigned a, b;
} SDL_Surface;

typedef struct SDL_RWops {
    unsigned char *base;
    unsigned pos, size;
} SDL_RWops;
SDL_RWops *SDL_RWFromMem(void *mem, int size);
size_t SDL_RWread(SDL_RWops *rw, void *ptr, size_t size, size_t n);
size_t SDL_RWwrite(SDL_RWops *rw, const void *ptr, size_t size, size_t n);
Sint64 SDL_RWtell(SDL_RWops *rw);
int SDL_RWclose(SDL_RWops *rw);

typedef struct SDL_Window SDL_Window;
typedef struct SDL_Renderer SDL_Renderer;
typedef struct SDL_Texture SDL_Texture;
typedef struct SDL_GameController SDL_GameController;
typedef struct SDL_Joystick SDL_Joystick;
typedef struct SDL_Haptic SDL_Haptic;
typedef int SDL_TimerID;
typedef Uint32 (*SDL_TimerCallback)(Uint32 interval, void *param);

void SDL_Delay(Uint32 ms);
Uint64 SDL_GetPerformanceCounter(void);
Uint64 SDL_GetPerformanceFrequency(void);
Uint32 SDL_GetTicks(void);
const Uint8 *SDL_GetKeyboardState(int *n);
#define SDL_AddTimer(d, f, p) 0
#define SDL_RemoveTimer(t) 0
#define SDL_SetWindowTitle(w, t) ((void)0)
#define SDL_HapticRumblePlay(h, s, l) 0
#define SDL_GameControllerRumble(c, a, b, l) 0
#define SDL_JoystickRumble(j, a, b, l) 0
#define SDL_ShowSimpleMessageBox(f, t, m, w) (printf("%s\n", (m)), 0)
#define SDL_MESSAGEBOX_ERROR 0x10
#define SDL_FreeSurface(s) ((void)0)

/* scancodes: USB HID usages */
#define SDL_SCANCODE_A 4
#define SDL_SCANCODE_B 5
#define SDL_SCANCODE_C 6
#define SDL_SCANCODE_D 7
#define SDL_SCANCODE_E 8
#define SDL_SCANCODE_F 9
#define SDL_SCANCODE_G 10
#define SDL_SCANCODE_H 11
#define SDL_SCANCODE_I 12
#define SDL_SCANCODE_J 13
#define SDL_SCANCODE_K 14
#define SDL_SCANCODE_L 15
#define SDL_SCANCODE_M 16
#define SDL_SCANCODE_N 17
#define SDL_SCANCODE_O 18
#define SDL_SCANCODE_P 19
#define SDL_SCANCODE_Q 20
#define SDL_SCANCODE_R 21
#define SDL_SCANCODE_S 22
#define SDL_SCANCODE_T 23
#define SDL_SCANCODE_U 24
#define SDL_SCANCODE_V 25
#define SDL_SCANCODE_W 26
#define SDL_SCANCODE_X 27
#define SDL_SCANCODE_Y 28
#define SDL_SCANCODE_Z 29
#define SDL_SCANCODE_1 30
#define SDL_SCANCODE_2 31
#define SDL_SCANCODE_3 32
#define SDL_SCANCODE_4 33
#define SDL_SCANCODE_5 34
#define SDL_SCANCODE_6 35
#define SDL_SCANCODE_7 36
#define SDL_SCANCODE_8 37
#define SDL_SCANCODE_9 38
#define SDL_SCANCODE_0 39
#define SDL_SCANCODE_RETURN 40
#define SDL_SCANCODE_ESCAPE 41
#define SDL_SCANCODE_BACKSPACE 42
#define SDL_SCANCODE_TAB 43
#define SDL_SCANCODE_SPACE 44
#define SDL_SCANCODE_MINUS 45
#define SDL_SCANCODE_EQUALS 46
#define SDL_SCANCODE_LEFTBRACKET 47
#define SDL_SCANCODE_RIGHTBRACKET 48
#define SDL_SCANCODE_BACKSLASH 49
#define SDL_SCANCODE_SEMICOLON 51
#define SDL_SCANCODE_APOSTROPHE 52
#define SDL_SCANCODE_GRAVE 53
#define SDL_SCANCODE_COMMA 54
#define SDL_SCANCODE_PERIOD 55
#define SDL_SCANCODE_SLASH 56
#define SDL_SCANCODE_CAPSLOCK 57
#define SDL_SCANCODE_F1 58
#define SDL_SCANCODE_F2 59
#define SDL_SCANCODE_F3 60
#define SDL_SCANCODE_F4 61
#define SDL_SCANCODE_F5 62
#define SDL_SCANCODE_F6 63
#define SDL_SCANCODE_F7 64
#define SDL_SCANCODE_F8 65
#define SDL_SCANCODE_F9 66
#define SDL_SCANCODE_F10 67
#define SDL_SCANCODE_F11 68
#define SDL_SCANCODE_F12 69
#define SDL_SCANCODE_PRINTSCREEN 70
#define SDL_SCANCODE_SCROLLLOCK 71
#define SDL_SCANCODE_PAUSE 72
#define SDL_SCANCODE_INSERT 73
#define SDL_SCANCODE_HOME 74
#define SDL_SCANCODE_PAGEUP 75
#define SDL_SCANCODE_DELETE 76
#define SDL_SCANCODE_END 77
#define SDL_SCANCODE_PAGEDOWN 78
#define SDL_SCANCODE_RIGHT 79
#define SDL_SCANCODE_LEFT 80
#define SDL_SCANCODE_DOWN 81
#define SDL_SCANCODE_UP 82
#define SDL_SCANCODE_NUMLOCKCLEAR 83
#define SDL_SCANCODE_KP_DIVIDE 84
#define SDL_SCANCODE_KP_MULTIPLY 85
#define SDL_SCANCODE_KP_MINUS 86
#define SDL_SCANCODE_KP_PLUS 87
#define SDL_SCANCODE_KP_ENTER 88
#define SDL_SCANCODE_KP_1 89
#define SDL_SCANCODE_KP_2 90
#define SDL_SCANCODE_KP_3 91
#define SDL_SCANCODE_KP_4 92
#define SDL_SCANCODE_KP_5 93
#define SDL_SCANCODE_KP_6 94
#define SDL_SCANCODE_KP_7 95
#define SDL_SCANCODE_KP_8 96
#define SDL_SCANCODE_KP_9 97
#define SDL_SCANCODE_KP_0 98
#define SDL_SCANCODE_KP_PERIOD 99
#define SDL_SCANCODE_APPLICATION 101
#define SDL_SCANCODE_CLEAR 156
#define SDL_SCANCODE_LCTRL 224
#define SDL_SCANCODE_LSHIFT 225
#define SDL_SCANCODE_LALT 226
#define SDL_SCANCODE_LGUI 227
#define SDL_SCANCODE_RCTRL 228
#define SDL_SCANCODE_RSHIFT 229
#define SDL_SCANCODE_RALT 230
#define SDL_SCANCODE_RGUI 231
#define SDL_NUM_SCANCODES 256

#define SDL_CONTROLLER_AXIS_LEFTX 0
#define SDL_CONTROLLER_AXIS_LEFTY 1
#define SDL_CONTROLLER_AXIS_RIGHTX 2
#define SDL_CONTROLLER_AXIS_RIGHTY 3
#define SDL_CONTROLLER_AXIS_TRIGGERLEFT 4
#define SDL_CONTROLLER_AXIS_TRIGGERRIGHT 5

#endif
