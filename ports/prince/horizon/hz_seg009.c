/*
SDLPoP, a port/conversion of the DOS game Prince of Persia.
Copyright (C) 2013-2025  Dávid Nagy

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.

The authors of this program may be contacted at https://forum.princed.org
*/

/* hz_seg009.c - the part of upstream's seg009.c (the SDL layer) that does not touch SDL,
 * taken over unchanged for the Atari816 port: random numbers, parameters, the text and
 * dialog drawing (on top of method_3_blit_mono and draw_rect), rectangles, palette rows,
 * the timers' lengths. Only marked lines differ ("Horizon:"). The rest of seg009's job is
 * done by hz_video.c, hz_data.c, hz_sound.c and hz_sys.c. */

#include "common.h"
#include "hz_plat.h"

/* Horizon: no on-screen keyboard to show */
#define SDL_SetTextInputRect(r) ((void)0)
#define SDL_StartTextInput() ((void)0)
#define SDL_StopTextInput() ((void)0)
static void rect_to_sdlrect(const rect_type* rect, SDL_Rect* sdlrect) {
	sdlrect->x = rect->left;
	sdlrect->y = rect->top;
	sdlrect->w = rect->right - rect->left;
	sdlrect->h = rect->bottom - rect->top;
}

dat_type* dat_chain_ptr = NULL;

char last_text_input;

// data:3356
word chtab_palette_bits = 1;

rgb_type palette[256];

// seg009:000D
int read_key() {
	// stub
	int key = last_key_scancode;
	last_key_scancode = 0;
	return key;
}

// seg009:019A
void clear_kbd_buf() {
	// stub
	last_key_scancode = 0;
	last_text_input = 0;
}

// seg009:040A
word prandom(word max) {
	if (!seed_was_init) {
		// init from current time
		random_seed = 0x12345678; // Horizon: no clock at start (seed= or a replay sets it)
		seed_was_init = 1;
	}
#if defined(_HORIZON) // Horizon: the same product from a 16 x 16 -> 32 multiply and a 16-bit one
	{                     // (214013 = 3 * 65536 + 0x43FD; a 32 x 32 multiply cost more)
		word lo = (word)random_seed, hi = (word)(random_seed >> 16);
		random_seed = (dword)lo * 0x43FDu + ((dword)(word)(lo * 3u + hi * 0x43FDu) << 16) + 2531011UL;
	}
#else
	random_seed = random_seed * 214013 + 2531011;
#endif
#if defined(_HORIZON) // Horizon: the same value with a 16-bit modulo (a 32-bit one cost 2 ms a room drawn)
	return (word)(random_seed >> 16) % (word)(max + 1);
#else
	return (random_seed >> 16) % (max + 1);
#endif
}

// seg009:0467
int round_xpos_to_byte(int xpos,int round_direction) {
	// stub
	return xpos;
}

// seg009:0E33
int key_test_quit() {
	word key = read_key();
	if (key == (SDL_SCANCODE_Q | WITH_CTRL)) { // Ctrl+Q

		#ifdef USE_REPLAY
		if (recording) save_recorded_replay_dialog();
		#endif
		#ifdef USE_MENU
		if (is_menu_shown) menu_was_closed();
		#endif

		quit(0);
	}
	return key;
}

// seg009:0E54
const char* check_param(const char* param) {
	// stub
	for (short arg_index = 1; arg_index < g_argc; ++arg_index) {

		char* curr_arg = g_argv[arg_index];

		// Filenames (e.g. replays) should never be a valid 'normal' param so we should skip these to prevent conflicts.
		// We can lazily distinguish filenames from non-filenames by checking whether they have a dot in them.
		// (Assumption: all relevant files, e.g. replay files, have some file extension anyway)
		if (strchr(curr_arg, '.') != NULL) {
			continue;
		}

		// List of params that expect a specifier ('sub-') arg directly after it (e.g. the mod's name, after "mod" arg)
		// Such sub-args may conflict with the normal params (so, we should 'skip over' them)
		static const char params_with_one_subparam[][16] = { "mod", "validate", /*...*/ };

		bool curr_arg_has_one_subparam = false;
		for (int i = 0; i < COUNT(params_with_one_subparam); ++i) {
			if (strncasecmp(curr_arg, params_with_one_subparam[i], strlen(params_with_one_subparam[i])) == 0) {
				curr_arg_has_one_subparam = true;
				break;
			}
		}

		if (curr_arg_has_one_subparam) {
			// Found an arg that has one sub-param, so we want to:
			// 1: skip over the next arg                (if we are NOT checking for this specific param)
			// 2: return a pointer below to the SUB-arg (if we ARE checking for this specific param)
			++arg_index;
			if (!(arg_index < g_argc)) return NULL; // not enough arguments
		}

		if (/*strnicmp*/strncasecmp(curr_arg, param, strlen(param)) == 0) {
			return g_argv[arg_index];
		}
	}
	return NULL;
}

// seg009:0EDF
int pop_wait(int timer_index,int time) {
	start_timer(timer_index, time);
	return do_wait(timer_index);
}

// seg009:35C5
int get_char_width(byte character) {
	font_type* font = textstate.ptr_font;
	int width = 0;
	if (character <= font->last_char && character >= font->first_char) {
		image_type* image = font->chtab->images[character - font->first_char];
		if (image != NULL) {
			width += image->w; //char_ptrs[character - font->first_char]->width;
			if (width) width += font->space_between_chars;
		}
	}
	return width;
}

// seg009:3E99
int find_linebreak(const char* text,int length,int break_width,int x_align) {
	int curr_char_pos = 0;
	short last_break_pos = 0; // in characters
	short curr_line_width = 0; // in pixels
	const char* text_pos = text;
	while (curr_char_pos < length) {
		curr_line_width += get_char_width(*text_pos);
		if (curr_line_width <= break_width) {
			++curr_char_pos;
			char curr_char = *text_pos;
			text_pos++;
			if (curr_char == '\n') {
				return curr_char_pos;
			}
			if (curr_char == '-' ||
				(x_align <= 0 && (curr_char == ' ' || *text_pos == ' ')) ||
				(*text_pos == ' ' && curr_char == ' ')
			) {
				// May break here.
				last_break_pos = curr_char_pos;
			}
		} else {
			if (last_break_pos == 0) {
				// If the first word is wider than break_width then break it.
				return curr_char_pos;
			} else {
				// Otherwise break at the last space.
				return last_break_pos;
			}
		}
	}
	return curr_char_pos;
}

// seg009:403F
int get_line_width(const char* text,int length) {
	int width = 0;
	const char* text_pos = text;
	while (--length >= 0) {
		width += get_char_width(*text_pos);
		text_pos++;
	}
	return width;
}

// seg009:3706
int draw_text_character(byte character) {
	//printf("going to do draw_text_character...\n");
	font_type* font = textstate.ptr_font;
	int width = 0;
	if (character <= font->last_char && character >= font->first_char) {
		image_type* image = font->chtab->images[character - font->first_char]; //char_ptrs[character - font->first_char];
		if (image != NULL) {
			method_3_blit_mono(image, textstate.current_x, textstate.current_y - font->height_above_baseline, textstate.textblit, textstate.textcolor);
			width = font->space_between_chars + image->w;
		}
	}
	textstate.current_x += width;
	return width;
}

// seg009:377F
int draw_text_line(const char* text,int length) {
	//hide_cursor();
	int width = 0;
	const char* text_pos = text;
	while (--length >= 0) {
		width += draw_text_character(*text_pos);
		text_pos++;
	}
	//show_cursor();
	return width;
}

// seg009:3755
int draw_cstring(const char* string) {
	//hide_cursor();
	int width = 0;
	const char* text_pos = string;
	while ('\0' != *text_pos) {
		width += draw_text_character(*text_pos);
		text_pos++;
	}
	//show_cursor();
	return width;
}

// seg009:3F01
const rect_type* draw_text(const rect_type* rect_ptr,int x_align,int y_align,const char* text,int length) {
	//printf("going to do draw_text()...\n");
	short rect_top;
	short rect_height;
	short rect_width;
	//textinfo_type var_C;
	short num_lines;
	short font_line_distance;
	//hide_cursor();
	//get_textinfo(&var_C);
	set_clip_rect(rect_ptr);
	rect_width = rect_ptr->right - rect_ptr->left;
	rect_top = rect_ptr->top;
	rect_height = rect_ptr->bottom - rect_ptr->top;
	num_lines = 0;
	int rem_length = length;
	const char* line_start = text;
	#define MAX_LINES 100
	const char* line_starts[MAX_LINES];
	int line_lengths[MAX_LINES];
	do {
		int line_length = find_linebreak(line_start, rem_length, rect_width, x_align);
		if (line_length == 0) break;
		if (num_lines >= MAX_LINES) {
			//... ERROR!
			printf("draw_text(): Too many lines!\n");
			quit(1);
		}
		line_starts[num_lines] = line_start;
		line_lengths[num_lines] = line_length;
		++num_lines;
		line_start += line_length;
		rem_length -= line_length;
	} while(rem_length);
	font_type* font = textstate.ptr_font;
	font_line_distance = font->height_above_baseline + font->height_below_baseline + font->space_between_lines;
	int text_height = font_line_distance * num_lines - font->space_between_lines;
	int text_top = rect_top;
	if (y_align >= 0) {
		if (y_align <= 0) {
			// middle
			// The +1 is for simulating SHR + ADC/SBB.
			text_top += (rect_height+1)/2 - (text_height+1)/2;
		} else {
			// bottom
			text_top += rect_height - text_height;
		}
	}
	textstate.current_y = text_top + font->height_above_baseline;
	for (int i = 0; i < num_lines; ++i) {
		const char* line_pos = line_starts[i];
		int line_length = line_lengths[i];
		if (x_align < 0 &&
			*line_pos == ' ' &&
			i != 0 &&
			*(line_pos-1) != '\n'
		) {
			// Skip over space if it's not at the beginning of a line.
			++line_pos;
			--line_length;
			if (line_length != 0 &&
				*line_pos == ' ' &&
				*(line_pos-2) == '.'
			) {
				// Skip over second space after point.
				++line_pos;
				--line_length;
			}
		}
		int line_width = get_line_width(line_pos,line_length);
		int text_left = rect_ptr->left;
		if (x_align >= 0) {
			if (x_align <= 0) {
				// center
				text_left += rect_width/2 - line_width/2;
			} else {
				// right
				text_left += rect_width - line_width;
			}
		}
		textstate.current_x = text_left;
		//printf("going to draw text line...\n");
		draw_text_line(line_pos,line_length);
		textstate.current_y += font_line_distance;
	}
	reset_clip_rect();
	//set_textinfo(...);
	//show_cursor();
	return rect_ptr;
}

// seg009:3E4F
void show_text(const rect_type* rect_ptr,int x_align,int y_align,const char* text) {
	// stub
	//printf("show_text: %s\n",text);
	draw_text(rect_ptr, x_align, y_align, text, (int)strlen(text));
}

// seg009:04FF
void show_text_with_color(const rect_type* rect_ptr,int x_align,int y_align, const char* text,int color) {
	short saved_textcolor;
	saved_textcolor = textstate.textcolor;
	textstate.textcolor = color;
	show_text(rect_ptr, x_align, y_align, text);
	textstate.textcolor = saved_textcolor;
}

// seg009:3A91
void set_curr_pos(int xpos,int ypos) {
	textstate.current_x = xpos;
	textstate.current_y = ypos;
}

// seg009:145A
void init_copyprot_dialog() {
	copyprot_dialog = make_dialog_info(&dialog_settings, &dialog_rect_1, &dialog_rect_1, NULL);
	copyprot_dialog->peel = read_peel_from_screen(&copyprot_dialog->peel_rect);
}

// seg009:0838
int showmessage(char* text,int arg_4,void *arg_0) {
	word key;
	rect_type rect;
	//font_type* saved_font_ptr;
	//surface_type* old_target;
	//old_target = current_target_surface;
	//current_target_surface = onscreen_surface_;
	// In the disassembly there is some messing with the current_target_surface and font (?)
	// However, this does not seem to be strictly necessary
	if (NULL == offscreen_surface) offscreen_surface = make_offscreen_buffer(&screen_rect); // In case we get an error before there is an offsceen buffer
	method_1_blit_rect(offscreen_surface, onscreen_surface_, &copyprot_dialog->peel_rect, &copyprot_dialog->peel_rect, 0);
	draw_dialog_frame(copyprot_dialog);
	//saved_font_ptr = textstate.ptr_font;
	//saved_font_ptr = current_target_surface->ptr_font;
	//current_target_surface->ptr_font = ptr_font;
	shrink2_rect(&rect, &copyprot_dialog->text_rect, 2, 1);
	show_text_with_color(&rect, halign_center, valign_middle, text, color_15_brightwhite);
	//textstate.ptr_font = saved_font_ptr;
	//current_target_surface->ptr_font = saved_font_ptr;
	clear_kbd_buf();
	do {
		idle();
		key = key_test_quit(); // Press any key to continue...
	} while(key == 0);
	//restore_dialog_peel_2(copyprot_dialog->peel);
	//current_target_surface = old_target;
	need_full_redraw = 1; // lazy: instead of neatly restoring only the relevant part, just redraw the whole screen
	return key;
}

// seg009:0BE7
void calc_dialog_peel_rect(dialog_type* dialog) {
	dialog_settings_type* settings;
	settings = dialog->settings;
	dialog->peel_rect.left = dialog->text_rect.left - settings->left_border;
	dialog->peel_rect.top = dialog->text_rect.top - settings->top_border;
	dialog->peel_rect.right = dialog->text_rect.right + settings->right_border + settings->shadow_right;
	dialog->peel_rect.bottom = dialog->text_rect.bottom + settings->bottom_border + settings->shadow_bottom;
}

// seg009:0BB0
void read_dialog_peel(dialog_type* dialog) {
	if (dialog->has_peel) {
		if (dialog->peel == NULL) {
			dialog->peel = read_peel_from_screen(&dialog->peel_rect);
		}
		dialog->has_peel = 1;
		draw_dialog_frame(dialog);
	}
}

// seg009:09DE
void draw_dialog_frame(dialog_type* dialog) {
	dialog->settings->method_2_frame(dialog);
}

// seg009:096F
void add_dialog_rect(dialog_type* dialog) {
	draw_rect(&dialog->text_rect, color_0_black);
}

// seg009:09F0
void dialog_method_2_frame(dialog_type* dialog) {
	rect_type rect;
	short shadow_right = dialog->settings->shadow_right;
	short shadow_bottom = dialog->settings->shadow_bottom;
	short bottom_border = dialog->settings->bottom_border;
	short outer_border = dialog->settings->outer_border;
	short peel_top = dialog->peel_rect.top;
	short peel_left = dialog->peel_rect.left;
	short peel_bottom = dialog->peel_rect.bottom;
	short peel_right = dialog->peel_rect.right;
	short text_top = dialog->text_rect.top;
	short text_left = dialog->text_rect.left;
	short text_bottom = dialog->text_rect.bottom;
	short text_right = dialog->text_rect.right;
	// Draw outer border
	rect = (rect_type) { peel_top, peel_left, peel_bottom - shadow_bottom, peel_right - shadow_right };
	draw_rect(&rect, color_0_black);
	// Draw shadow (right)
	rect = (rect_type) { text_top, peel_right - shadow_right, peel_bottom, peel_right };
	draw_rect(&rect, get_text_color(0, color_8_darkgray /*dialog's shadow*/, 0));
	// Draw shadow (bottom)
	rect = (rect_type) { peel_bottom - shadow_bottom, text_left, peel_bottom, peel_right };
	draw_rect(&rect, get_text_color(0, color_8_darkgray /*dialog's shadow*/, 0));
	// Draw inner border (left)
	rect = (rect_type) { peel_top + outer_border, peel_left + outer_border, text_bottom, text_left };
	draw_rect(&rect, color_15_brightwhite);
	// Draw inner border (top)
	rect = (rect_type) { peel_top + outer_border, text_left, text_top, text_right + dialog->settings->right_border - outer_border };
	draw_rect(&rect, color_15_brightwhite);
	// Draw inner border (right)
	rect.top = text_top;
	rect.left =  text_right;
	rect.bottom = text_bottom + bottom_border - outer_border;           // (rect.right stays the same)
	draw_rect(&rect, color_15_brightwhite);
	// Draw inner border (bottom)
	rect = (rect_type) { text_bottom, peel_left + outer_border, text_bottom + bottom_border - outer_border, text_right };
	draw_rect(&rect, color_15_brightwhite);
}

// seg009:0C44
void show_dialog(const char* text) {
	char string[256];
	snprintf(string, sizeof(string), "%s\n\nPress any key to continue.", text);
	showmessage(string, 1, &key_test_quit);
}

// seg009:0791
int get_text_center_y(const rect_type* rect) {
	const font_type* font;
	short empty_height; // height of empty space above+below the line of text
	font = &hc_font;//current_target_surface->ptr_font;
	empty_height = rect->bottom - font->height_above_baseline - font->height_below_baseline - rect->top;
	return ((empty_height - empty_height % 2) >> 1) + font->height_above_baseline + empty_height % 2 + rect->top;
}

// seg009:3E77
int get_cstring_width(const char* text) {
	int width = 0;
	const char* text_pos = text;
	char curr_char;
	while ('\0' != (curr_char = *text_pos)) {
		text_pos++;
		width += get_char_width(curr_char);
	}
	return width;
}

// seg009:0767
void draw_text_cursor(int xpos,int ypos,int color) {
	set_curr_pos(xpos, ypos);
	/*current_target_surface->*/textstate.textcolor = color;
	draw_text_character('_');
	//restore_curr_color();
	textstate.textcolor = 15;
}

// seg009:053C
int input_str(const rect_type* rect,char* buffer,int max_length,const char *initial,int has_initial,int arg_4,int color,int bgcolor) {
	// Display the screen keyboard if supported.
	//SDL_SetHint(SDL_HINT_IME_SHOW_UI, "1");
	SDL_Rect sdlrect;
	rect_to_sdlrect(rect, &sdlrect);
	SDL_SetTextInputRect(&sdlrect);
	SDL_StartTextInput();

	word key;
	short current_xpos;
	short length = 0;
	short cursor_visible = 0;
	draw_rect(rect, bgcolor);
	short init_length = strlen(initial);
	if (has_initial) {
		strcpy(buffer, initial);
		length = init_length;
	}
	current_xpos = rect->left + arg_4;
	short ypos = get_text_center_y(rect);
	set_curr_pos(current_xpos, ypos);
	/*current_target_surface->*/textstate.textcolor = color;
	draw_cstring(initial);
	//restore_curr_pos?();
	current_xpos += get_cstring_width(initial) + (init_length != 0) * arg_4;
	do {
		key = 0;
		do {
			if (cursor_visible) {
				draw_text_cursor(current_xpos, ypos, color);
			} else {
				draw_text_cursor(current_xpos, ypos, bgcolor);
			}
			cursor_visible = !cursor_visible;
			start_timer(timer_0, 6);
			if (key) {
				if (cursor_visible) {
					draw_text_cursor(current_xpos, ypos, color);
					cursor_visible = !cursor_visible;
				}
				if (key == SDL_SCANCODE_RETURN) { // Enter
					buffer[length] = 0;
					SDL_StopTextInput();
					return length;
				} else break;
			}
			while (!has_timer_stopped(timer_0) && (key = key_test_quit()) == 0) idle();
		} while (1);
		// Only use the printable ASCII chars (UTF-8 encoding)
		char entered_char = last_text_input <= 0x7E ? last_text_input : 0;
		clear_kbd_buf();

		if (key == SDL_SCANCODE_ESCAPE) { // Esc
			draw_rect(rect, bgcolor);
			buffer[0] = 0;
			SDL_StopTextInput();
			return -1;
		}
		if (length != 0 && (key == SDL_SCANCODE_BACKSPACE ||
				key == SDL_SCANCODE_DELETE)) { // Backspace, Delete
			--length;
			draw_text_cursor(current_xpos, ypos, bgcolor);
			current_xpos -= get_char_width(buffer[length]);
			set_curr_pos(current_xpos, ypos);
			/*current_target_surface->*/textstate.textcolor = bgcolor;
			draw_text_character(buffer[length]);
			//restore_curr_pos?();
			draw_text_cursor(current_xpos, ypos, color);
		}
		else if (entered_char >= 0x20 && entered_char <= 0x7E && length < max_length) {
			// Would the new character make the cursor go past the right side of the rect?
			if (get_char_width('_') + get_char_width(entered_char) + current_xpos < rect->right) {
				draw_text_cursor(current_xpos, ypos, bgcolor);
				set_curr_pos(current_xpos, ypos);
				/*current_target_surface->*/textstate.textcolor = color;
				buffer[length] = entered_char;
				length++;
				current_xpos += draw_text_character(entered_char);
			}
		}
	} while(1);
}

// seg009:37E8
void draw_rect(const rect_type* rect,int color) {
	method_5_rect(rect, blitters_0_no_transp, color);
}

// seg009:3985
surface_type *rect_sthg(surface_type* surface,const rect_type* rect) {
	// stub
	return surface;
}

// seg009:39CE
rect_type *shrink2_rect(rect_type* target_rect,const rect_type* source_rect,int delta_x,int delta_y) {
	target_rect->top    = source_rect->top    + delta_y;
	target_rect->left   = source_rect->left   + delta_x;
	target_rect->bottom = source_rect->bottom - delta_y;
	target_rect->right  = source_rect->right  - delta_x;
	return target_rect;
}

// seg009:3D95
int intersect_rect(rect_type* output,const rect_type* input1,const rect_type* input2) {
	short left = MAX(input1->left, input2->left);
	short right = MIN(input1->right, input2->right);
	if (left < right) {
		output->left = left;
		output->right = right;
		short top = MAX(input1->top, input2->top);
		short bottom = MIN(input1->bottom, input2->bottom);
		if (top < bottom) {
			output->top = top;
			output->bottom = bottom;
			return 1;
		}
	}
	memset(output, 0, sizeof(rect_type));
	return 0;
}

// seg009:4063
rect_type* union_rect(rect_type* output,const rect_type* input1,const rect_type* input2) {
	short top = MIN(input1->top, input2->top);
	short left = MIN(input1->left, input2->left);
	short bottom = MAX(input1->bottom, input2->bottom);
	short right = MAX(input1->right, input2->right);
	output->top = top;
	output->left = left;
	output->bottom = bottom;
	output->right = right;
	return output;
}

// seg009:07EB
rect_type* offset4_rect_add(rect_type* dest,const rect_type* source,int d_left,int d_top,int d_right,int d_bottom) {
	*dest = *source;
	dest->left += d_left;
	dest->top += d_top;
	dest->right += d_right;
	dest->bottom += d_bottom;
	return dest;
}

// seg009:3AA5
rect_type* offset2_rect(rect_type* dest,const rect_type *source,int delta_x,int delta_y) {
	dest->top    = source->top    + delta_y;
	dest->left   = source->left   + delta_x;
	dest->bottom = source->bottom + delta_y;
	dest->right  = source->right  + delta_x;
	return dest;
}

// seg009:9C36
int find_first_pal_row(int which_rows_mask) {
	word which_row = 0;
	word row_mask = 1;
	do {
		if (row_mask & which_rows_mask) {
			return which_row;
		}
		++which_row;
		row_mask <<= 1;
	} while (which_row < 16);
	return 0;
}

// seg009:9C6C
int get_text_color(int cga_color,int low_half,int high_half_mask) {
	if (graphics_mode == gmCga || graphics_mode == gmHgaHerc) {
		return cga_color;
	} else if (graphics_mode == gmMcgaVga && high_half_mask != 0) {
		return (find_first_pal_row(high_half_mask) << 4) + low_half;
	} else {
		return low_half;
	}
}

// seg009:9289
void set_pal_arr(int start,int count,const rgb_type* array) {
	// stub
	for (int i = 0; i < count; ++i) {
		if (array) {
			set_pal(start + i, array[i].r, array[i].g, array[i].b);
		} else {
			set_pal(start + i, 0, 0, 0);
		}
	}
}

// seg009:969C
int add_palette_bits(byte n_colors) {
	// stub
	return 0;
}

// seg009:9CAC
void set_loaded_palette(dat_pal_type* palette_ptr) {
	int dest_row, dest_index, source_row;
	for (dest_row = dest_index = source_row = 0; dest_row < 16; ++dest_row, dest_index += 0x10) {
		if (palette_ptr->row_bits & (1 << dest_row)) {
			set_pal_arr(dest_index, 16, palette_ptr->vga + source_row*0x10);
			++source_row;
		}
	}
}

/* Horizon: the timer lengths without floating point (upstream divides 60 by the length in
 * doubles): ticks a second = fps / wait_time, so the feather fall's ticks scale by the old
 * length over the new one */
void set_timer_length(int timer_index, int length) {
	int old = wait_time[timer_index];
	if (!fixes->fix_quicksave_during_feather ||
	    is_feather_fall == 0 ||
	    old < custom->base_speed ||
	    old > custom->fight_speed) {
		wait_time[timer_index] = length;
		return;
	}
	wait_time[timer_index] = length;
	if (old != length && length > 0) {
		/* (upstream: not when the time left is under a second of either speed) */
		int tps_old = fps / old, tps_new = fps / length;
		if (is_feather_fall > MAX(tps_old, tps_new))
			is_feather_fall = (word)((long)is_feather_fall * old / length);
	}
}

dialog_type* make_dialog_info(dialog_settings_type* settings, rect_type* dialog_rect,
                                            rect_type* text_rect, peel_type* dialog_peel) {
	dialog_type* dialog_info;
	dialog_info = malloc(sizeof(dialog_type));
	dialog_info->settings = settings;
	dialog_info->has_peel = 0;
	dialog_info->peel = dialog_peel;
	if (text_rect != NULL)
		dialog_info->text_rect = *text_rect;
	calc_dialog_peel_rect(dialog_info);
	if (text_rect != NULL) {        // does not seem to be quite right; see seg009:0948 (?)
		read_dialog_peel(dialog_info);
	}
	return dialog_info;
}
