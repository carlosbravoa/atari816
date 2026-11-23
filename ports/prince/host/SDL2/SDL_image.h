/* host/SDL2/SDL_image.h - the part of SDL_image that SDLPoP uses, for building upstream's
 * SDLPoP on a PC without SDL2_image (the reference build of ports/prince: host/Makefile).
 * Only what SDLPoP's data needs: paletted PNGs (bit depth 1, 2, 4 or 8, not interlaced)
 * become 8-bit SDL surfaces with the file's palette, as SDL_image gives them. */
#ifndef HOST_SDL_IMAGE_H
#define HOST_SDL_IMAGE_H
#include <SDL2/SDL.h>

SDL_Surface *IMG_Load_RW(SDL_RWops *src, int freesrc);
SDL_Surface *IMG_Load(const char *file);
int IMG_SavePNG(SDL_Surface *surface, const char *file);
#define IMG_GetError SDL_GetError
#define IMG_Init(f) (f)
#define IMG_Quit() ((void)0)
#define IMG_INIT_PNG 2

#endif
