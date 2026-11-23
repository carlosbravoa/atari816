/* dos_font.h (C translation of core/dos_font.hpp)
   
   The 8x8 text font the game prints its two in-game strings with.
   
   SkyRoads does not ship a font: at startup it asks the BIOS for the VGA ROM
   character sets (INT 10h AX=1130 with BH=3 and BH=4, @0x22-0x3d) and keeps the
   8x8 and 8x16 pointers in ds:0x3194 and ds:0x3198. The string printer @0x450a
   then walks a string calling 0x44a2 per character and advances x by exactly 8,
   and 0x4547 computes the glyph offset as `character * 8` -- i.e. the 8-bytes-per
   -glyph 8x8 set. Strings are centred as `160 - length * 8 / 2`, which is where the
   original's x = 104 for "Road Completed" and x = 132 for "The End" come from.
   
   A modern host has no such ROM to ask, so the glyphs are baked in here. This is the
   standard IBM VGA 8x8 bitmap (code page 437 for the ASCII range), taken from the
   kbd project's Lat15-VGA8 console font and spot-checked glyph by glyph against the
   familiar shapes. Only 0x20..0x7E is included; the game prints nothing else.
 */
#ifndef CORE_DOS_FONT_H
#define CORE_DOS_FONT_H

#include "sr.h"

#define DOS_FONT_HEIGHT 8u
#define DOS_FONT_ADVANCE 8
#define DOS_FONT_FIRST_CHAR 0x20u
#define DOS_FONT_LAST_CHAR 0x7Eu

/* One byte per row, most significant bit leftmost. */
extern const uint8_t DOS_FONT_8X8[DOS_FONT_LAST_CHAR - DOS_FONT_FIRST_CHAR + 1][DOS_FONT_HEIGHT];

/* The glyph for a character, or the space glyph for anything out of range. */
static inline const uint8_t *dos_font_glyph(char ch)
{
    const uint8_t c = (uint8_t)ch;
    if (c < DOS_FONT_FIRST_CHAR || c > DOS_FONT_LAST_CHAR)
        return DOS_FONT_8X8[0];
    return DOS_FONT_8X8[c - DOS_FONT_FIRST_CHAR];
}

/* Centred x for a string, exactly as the original computes it (@0x2c65-0x2c8a). */
static inline int32_t dos_text_centered_x(unsigned length)
{
    return 160 - (int32_t)(length * DOS_FONT_ADVANCE / 2);
}

#endif
