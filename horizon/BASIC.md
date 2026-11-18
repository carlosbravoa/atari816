# Horizon BASIC

A line-numbered BASIC for the 65C816, written in 65816 assembly: `/BIN/BASIC.PRG`
(sources `user/basic.s` and `user/bas_*.s`), version 2.0: integers and decimal floating
point; 1.2 added the joystick (STICK, STRIG) and VSYNC; 2.0 the Atari816's games hardware:
sprites, a full screen that scrolls with a fixed panel and raster colours, the blitter for
blocks of pixels, and the sample player (see "Games" and "Samples" below). It runs as a
window program: a console window, and a graphics window when a program draws.

The rule of 2.0: the hardware does the work, so a program in BASIC only does the rules. A
sprite moves with one short statement and costs nothing while it stays; the blitter copies
blocks while the program goes on; a sample plays to its end by itself. A game of a page of
BASIC runs at 60 frames a second (DRIFT.BAS, below: about 5.5 ms of BASIC a frame in the
emulator, so about 11 ms on the board).

## Starting

| How | What |
| --- | --- |
| Desktop: Programs > BASIC | an empty console |
| Files: open a `.BAS` file | BASIC with that program loaded |
| `basic [FILE]` (shell) | the console; FILE loaded (`.BAS` is added when the name has no extension) |
| `basic -r FILE` | load and run |
| `basic -t FILE` | test mode, see "Testing" |

From the text shell, BASIC starts the window system itself (as Edit does) and stops it
when it ends.

## The console

- **Window.** Black 8x12 text on white, 64 x 22 characters. It can be resized; the width
  is used for new output.
- **Scrollback.** 512 lines: the scroll bar, the wheel, PgUp / PgDn. Typing goes back to
  the bottom.
- **Line editing.** Left / Right, Home / End, Backspace, Delete; Up / Down recall the last
  8 lines. Esc or ctrl-C clears the line. Lines are at most 240 characters.
- **Menus.**
  - File: New, Load..., Save, Save as..., Close (the file dialog; New, Load and Close ask
    before unsaved changes are lost).
  - Program: Run, Stop, List.
- **The title** shows the file name and `*` when the program changed since it was loaded
  or saved.
- **Stopping.** Esc, ctrl-C or Program > Stop stop a running program: `Break in 120`.
  CONT goes on from there. The graphics window's close box also stops it.

A line typed with a number is stored in the program (a number alone deletes that line).
Any other line runs at once (direct mode); "Ready" follows. Editing the program clears
the variables (and CONT is no longer possible).

## Values

- **Numbers.** Real numbers: `7/2` is 3.5, `0.1+0.2` is exactly 0.3, `2^0.5` is
  1.414213562. See "Numbers" below for how they are kept.
- **Number literals.** Decimal (`42`, `-0.5`, `.25`, `1.5E-3`, `6E23`), or hexadecimal as
  `$1F` or `&H1F` (integers only).
- **Strings.** 0 to 255 characters, any bytes. Literals in double quotes. Strings live in
  a heap with a garbage collector; there is nothing to DIM.
- **Truth.** Comparisons give -1 (true) or 0 (false). IF and WHILE take any non-zero number
  as true (0.5 too). AND, OR, XOR and NOT work on all 32 bits, so they are logical
  operators on comparisons and bit operators on numbers (a number with a fraction is
  rounded first).

## Numbers

A number is kept in one of two forms; which one is invisible to a program, except in
speed:

- **An integer** of 32 bits (-2147483648 to 2147483647), as in BASIC 1.0. Integer
  arithmetic is as fast as before.
- **A decimal floating point number** of 12 significant digits, 1E-99 to 9.99999999999E+99
  (and the negatives). It is decimal, like Atari BASIC's BCD: 0.1, 0.01 and 19.99 are
  exact, `0.1+0.2` is 0.3 exactly, `FOR X=0 TO 1 STEP 0.1` runs 11 times. Every `+ - * /`
  and SQR is correctly rounded to 12 digits (halves to the even digit); PRINT shows 10.

The rules:

- `+ - *`, `^` and unary `-` on integers give an integer when the result fits in 32 bits;
  when it does not, the same operation is done in floating point (`2147483647+1` is
  2147483648, `100000*100000` is 1E+10): there is no integer overflow.
- `/` gives the exact quotient: an integer when the division is exact (`6/2`), else a
  float (`7/2` is 3.5). `\` divides integers and truncates toward zero (`7\2` is 3, `-7\2`
  is -3); MOD is the remainder with the sign of the dividend, as before.
- An integer meeting a float in an operation or a comparison becomes a float.
- A result that is 0, or below 1E-99, is the integer 0. A result of 1E+100 or more is
  "Overflow"; a division by 0 "Division by zero".
- Where an integer is needed (`\`, MOD, AND, OR, XOR, NOT, subscripts, DIM, CHR$, the
  graphics and sound statements, PEEK, POKE, TAB ...) a float is rounded to the nearest
  integer, halves away from zero (2.5 is 3, -2.5 is -3); beyond 32 bits that is
  "Overflow". Coordinates of the graphics statements are clamped instead.
- A literal, VAL, INPUT and READ give an integer for a whole number of 32 bits (`2.0`,
  `1E3`, `2147483647`), else a float (`2.5`, `1E10`, `99999999999`); more than 12 digits
  are rounded.
- Variables and array elements hold either form. A name ending in `%` (`N%`, `A%(10)`) is
  an integer variable: a float stored in it is rounded (Overflow beyond 32 bits). `N`,
  `N%`, `N$` are three different variables.
- **Printing** (PRINT, STR$): integers in full; floats with up to 10 significant digits,
  trailing zeros dropped, in plain form from 0.0001 to 9999999999 (`3.5`, `-0.0025`,
  `0.3333333333`) and as d.dddE+nn beyond (`1E+10`, `1.5E-05`, `-2.5E+30`). LIST shows a
  literal with all its 12 digits, so a saved program reads back the same numbers.

Accuracy: `+ - * /` and SQR are exact to the 12th digit (correctly rounded); SIN, COS,
TAN, ATN, EXP, LOG and LOG10 are within about one unit of the 12th digit (a relative error
below 1E-11), `x ^ y` within 6E-11 for a y with a fraction. SIN, COS and TAN keep 10
digits up to |x| = 1E8. `1/3*3` is 0.999999999999, as on every decimal machine; PRINT's
10 digits show 1.

## Names and arrays

- **Names.** A letter, then letters, digits and `_`, up to 32 characters, all significant;
  case does not matter. `$` at the end: a string; `%`: an integer. `A`, `A%`, `A$`,
  `A(...)`, `A%(...)` and `A$(...)` are six different variables.
- **Keywords are whole words.** `FORI=1TO9` is not `FOR I=1 TO 9`: separate keywords from
  names with spaces. A name cannot be a keyword (`TO`, `ON`), but it may contain one
  (`TOTAL`, `ONE`).
- **Arrays.** `DIM A(10)` has the elements 0 to 10; up to 4 dimensions (`DIM M(3,4)`),
  numbers or strings. An array used without DIM gets 0 to 10 in each dimension used.
  One array is at most 64 KB: 16,000 integers or 10,800 strings. A number array starts
  with 4-byte integers; the first number stored in it that is not a 32-bit integer (2.5,
  1E10) turns it into one of 8-byte elements (once; the old block is freed by RUN or
  CLR). So an array of more than 8,000 numbers holds only integers: storing 2.5 in it is
  "Out of memory" (a `%` array is always of integers and rounds). A subscript outside
  the range is an error.

## Operators

From the lowest precedence to the highest:

| | Operators |
| --- | --- |
| 1 | `OR` `XOR` |
| 2 | `AND` |
| 3 | `NOT` (unary) |
| 4 | `=` `<>` `<` `>` `<=` `>=` (numbers or strings) |
| 5 | `+` `-` (`+` also joins strings) |
| 6 | `*` `/` `\` (integer division) `MOD` |
| 7 | `-` (unary) |
| 8 | `^` (power, right associative: `2^3^2` is 512) |

`a ^ b`: a whole b (below 100 in size) multiplies (`2^10` is 1024 exactly, `2^-1` is 0.5,
`(-2)^3` is -8); else e^(b LOG(a)), for a > 0 only ("Illegal function call" for
`(-8)^(1/3)`); `0^b` is 0 for b > 0, "Division by zero" for b < 0.

## Statements

Several statements on one line are separated by `:`.

| Statement | Meaning |
| --- | --- |
| `[LET] v = e` | assignment; LET is optional |
| `PRINT [items]` (or `?`) | items: expressions, `;` (nothing between), `,` (to the next column of 10), `TAB(n)` (to column n, the first is 0), `SPC(n)` (n spaces). A trailing `;` or `,` keeps the line open. Numbers print with no spaces around them |
| `INPUT ["prompt";] v [, v ...]` | reads a line; `;` after the prompt adds `? `, `,` does not. Items are separated by commas, strings may be quoted. A bad number: `?Redo from start`; too few items: `?? ` asks for more |
| `IF e THEN statements [ELSE statements]` | on one line; `THEN 100` and `ELSE 200` are GOTOs, `IF e GOTO 100` too. An IF after THEN takes the first ELSE that follows |
| `GOTO n`, `GOSUB n`, `RETURN` | n is a line number (not an expression) |
| `ON e GOTO n1, n2, ...`, `ON e GOSUB ...` | the e-th line; e outside 1..count: the next statement |
| `FOR v = a TO b [STEP s]` ... `NEXT [v [, v]]` | a number variable (`%` too: a, b, s rounded); the body runs at least once; NEXT without a name ends the innermost loop. a, b, s may be floats (`STEP 0.1`: decimal steps add up exactly); with an integer a and s the loop stays an integer one (b is rounded down, up for a negative step) |
| `WHILE e` ... `WEND` | repeats while e is true (tested before each pass) |
| `DIM a(n [, ...]) [, ...]` | arrays |
| `DATA items`, `READ v [, ...]`, `RESTORE [n]` | items: numbers, quoted strings, or plain text up to the next `,` or `:` |
| `REM text`, `' text` | comments |
| `END`, `STOP`, `CONT` | stop; STOP says `Stopped in N`, CONT goes on after it (or after a break) |
| `RUN [n]`, `RUN "file"` | clears the variables and runs (from line n, or loads the file first: see below) |
| `LIST [n]`, `LIST [n]-[m]` | the program, or a part of it |
| `NEW`, `CLR` | NEW: no program; CLR: no variables |
| `LOAD "file"`, `SAVE ["file"]` | the program as plain text (`.BAS` is added when the name has no extension; SAVE alone uses the program's name) |
| `DIR ["folder"]` | the names in a folder (folders end in `/`) |
| `POKE a, b` | stores byte b (0-255) at a (0-65535) of BASIC's own 64 KB memory (see PEEK) |
| `CLS` | clears the console (and its scrollback) |
| `PAUSE ms` | waits; the windows are drawn first, Esc still stops |
| `RANDOMIZE [n]` | seeds RND (no n: from the clock) |
| `DEG`, `RAD` | SIN, COS, TAN and ATN in degrees, in radians (RUN sets RAD). In degrees the multiples of 30 and 45 are exact: `SIN(30)` is 0.5, `SIN(180)` is 0 |
| `SPRITE`, `SHAPE`, `GET`, `PUT`, `COPY`, `SCROLL`, `PANEL`, `RASTER`, `WAVE`, `PLAY` | (2.0) see "Graphics", "Games" and "Samples" |
| `VSYNC` | (1.2) waits for the next vertical blank (60 a second): a game that moves its objects and then waits with VSYNC moves them once a frame, evenly. (2.0) The frame's changes go to the hardware first, all together: the graphics window's pixels, the sprites (SPRITE), the scroll and panel (SCROLL, PANEL), the raster table (RASTER) and the blitter's list (PUT, COPY, FRECT, GCLS in full screen), which starts in the vertical blank; VSYNC returns when the blitter is done. Without VSYNC they go every 40 ms |

The file name of RUN, LOAD, SAVE and DIR is a string expression (`"name"`, `A$`, ...), or
typed without quotes: `RUN /programs/sieve.bas`, `LOAD demo`. Without quotes, everything up
to `:` or the end of the line is the name (trailing spaces dropped), unless the argument
could start a string expression (a quote, a parenthesis, a name ending in `$`) or, after
RUN, is a line number; LIST shows such a name in quotes. `RUN` with any other argument is
an error, never a silent run of the program in memory.

## Functions

| Function | Value |
| --- | --- |
| `ABS(n)`, `SGN(n)` | absolute value, sign (-1, 0, 1) |
| `MIN(a, b)`, `MAX(a, b)` | the smaller, the larger |
| `INT(x)`, `FIX(x)` | the largest whole number not above x (`INT(-2.5)` is -3), x without its fraction (`FIX(-2.5)` is -2) |
| `ROUND(x [, n])` | x rounded to n decimals (default 0; n < 0: to tens, hundreds ...), halves away from zero: `ROUND(2.5)` is 3, `ROUND(1.005, 2)` is 1.01, `ROUND(1234, -2)` is 1200 |
| `SQR(x)` | the square root (correctly rounded); "Illegal function call" for x < 0 |
| `SIN(x)`, `COS(x)`, `TAN(x)` | x in radians (or degrees after DEG); \|x\| below 1E9 |
| `ATN(x)` | the arc tangent, -PI/2 to PI/2 (or -90 to 90 after DEG) |
| `EXP(x)` | e^x; "Overflow" above 230.25, 0 below -227.9 |
| `LOG(x)`, `LOG10(x)` | the natural logarithm, the logarithm to base 10 (`LOG10(1000)` is 3 exactly); "Illegal function call" for x <= 0 |
| `PI` | 3.14159265359 |
| `RND`, `RND(1)` | a random float, 0 <= x < 1 (12 random digits) |
| `RND(n)` | n >= 2: a random integer from 0 to n-1 (as in BASIC 1.0) |
| `LEN(s$)` | length |
| `LEFT$(s$, n)`, `RIGHT$(s$, n)`, `MID$(s$, i [, n])` | parts; i counts from 1 |
| `CHR$(n)`, `ASC(s$)` | the character of code n (0-255), the code of the first character |
| `STR$(n)`, `VAL(s$)` | number to text (as PRINT shows it), text to number (VAL reads a leading number such as `-1.5E3`, else 0) |
| `HEX$(n)` | hexadecimal, no leading zeros (32 bits: `HEX$(-1)` is `FFFFFFFF`) |
| `INSTR([i,] s$, t$)` | where t$ starts in s$ (from position i), 0 if nowhere |
| `PEEK(a)` | the byte at a (0-65535) of BASIC's own memory |
| `TIME` | milliseconds since the machine started |
| `FRE` | free memory in bytes (free 64 KB banks) |
| `INKEY$` | the next key typed in either window, or `""`. The arrows give `CHR$(128)` right, 129 left, 130 down, 131 up; Home 132, PgUp 133, Delete 134, End 135, PgDn 136 |
| `MOUSEX`, `MOUSEY`, `MOUSEB` | where the pointer is now, relative to the graphics window's top left (to the console window's without a graphics window; negative or beyond the size outside it), and the buttons held now (bit 0 left, 1 right, 2 middle); also without a press |
| `POINT(x, y)` | the colour of a pixel of the graphics window; -1 outside it or without one |
| `STICK(n)`, `STRIG(n)` | (1.2) joystick port n + 1 (n = 0 or 1), as in Atari BASIC: STICK is 15 centred, 14 up, 13 down, 11 left, 7 right, and the diagonals 10 (up left), 6 (up right), 9 (down left), 5 (down right); STRIG is 0 while the trigger is pressed, else 1. The ports are read when the function runs (the kernel's SYS_JOY). (2.0) Port 0 also follows the keyboard: the arrow keys held count as its directions, Space held as its trigger (in either window), so a game works with the keys and the joystick alike: `IF (STICK(0) AND 4)=0 THEN X=X-1` moves left while Left is held |
| `FRAME` | (2.0) the frame counter: + 1 at every vertical blank (60.03 a second), 0-65535, then 0 again; `(FRAME-F) AND 65535` is the frames since F |
| `HIT(a)`, `HIT(a, b)`, `HIT(a, x, y, w, h)` | (2.0) collisions of sprites (see "Sprites") |
| `NOTE(s$)` | (2.0) the note s$ in semitones from C4: `NOTE("C4")` 0, `NOTE("A4")` 9, `NOTE("C#5")` 13, `NOTE("Bb3")` -2 (see "Samples") |

## Graphics

`SCREEN w, h` opens a graphics window of w x h pixels (16-636 x 16-324) in 256 colours, at
the bottom right of the screen; a second SCREEN of another size reopens it in its place,
of the same size clears it (2.0: and brings it to the front, so that its sprites show).
`SCREEN 0` closes it. Any drawing statement without a window opens a 320 x 200 one.
Coordinates start at the top left (0, 0); everything is clipped to the window. (2.0)
`SCREEN 1` and `SCREEN 2` are full screen: see "Full screen".

| Statement | Draws |
| --- | --- |
| `COLOR c` | the colour of what follows (0-255; 1 at the start) |
| `PLOT x, y` | a pixel |
| `LINE x1, y1, x2, y2` | a line |
| `RECT x, y, w, h`, `FRECT x, y, w, h` | a frame, a filled box |
| `CIRCLE x, y, r` | a circle |
| `TEXT x, y, s$` | text in the 8x12 console font (no background) |
| `GCLS [c]` | the whole window in c (default 0, black) |
| `PALETTE i, r, g, b` | colour i (16-255) as red, green, blue 0-255. (2.0: Horizon 0.18) The entry becomes BASIC's own: it shows that colour while one of BASIC's windows has the focus, the system's colour otherwise. RUN and the end of BASIC give it back. In full screen all 256 (0-255) are the program's own, and they last while the full screen does |
| `GET p, x, y, w, h` | (2.0) picture p (0-63) from the rectangle x, y, w, h (each 1-64) of the drawing; what lies outside is colour 0. See "Pictures" |
| `PUT p, x, y [, c]` | (2.0) picture p drawn with its top left at x, y; with c (0-255), the pixels of colour c are left out (the picture is seen through there). Clipped |
| `COPY x, y, w, h TO x2, y2` | (2.0) the rectangle moved to x2, y2 (overlapping is fine: a scroll); what lies outside on either side is left out of both |

The colours are the system palette: 0-15 the desktop's (0 black, 1 white, 11 red, 12
yellow, 13 green, 14 orange, ...), 16-231 a 6 x 6 x 6 cube (16 + 36 R + 6 G + B, each
0-5), 232-255 greys from dark to light.

The program draws into a copy of the window in memory (so POINT can read it). The window
shows it at the next PAUSE, INPUT, INKEY$ wait, VSYNC or end, and every 40 ms while the program
runs. FRECT, RECT and GCLS also go to the window at once through win_draw (blitter fills on
REV $08 boards). In a window PUT and COPY are done by the CPU in that copy (a 16 x 16 PUT
takes about 0.7 ms), then shown the same way; in full screen the blitter does them.

## Sound

POKEY 2 (four voices) through the kernel; REV $07 boards and later.

| Statement | Plays |
| --- | --- |
| `SOUND v, f, vol` | voice v (0-3) at f Hz (125-15980), volume 0-15 (0 or f 0: silent). The tone lasts until changed |
| `SOUND v, pitch, distortion, vol` | Atari BASIC's form: POKEY's AUDF = pitch (0-255), AUDC = distortion * 16 + vol |
| `SOUND` | all voices silent |
| `BEEP [f, ms]` | a short tone on voice 0 (1000 Hz, 100 ms) |

END, STOP, a break, an error and RUN silence all voices.

## Games (2.0)

What the hardware needs (on an older board the statement says "Not available on this
machine", and the rest of BASIC works as before):

| | needs |
| --- | --- |
| SHAPE, GET, PUT, COPY, HIT, FRAME, NOTE, WAVE, full screen (`SCREEN 1`, `SCREEN 2`) | every board (without the blitter, REV $07, the CPU copies) |
| RASTER | REV $09 (Marga's raster events) |
| PLAY | REV $0A (Lau, the sample player) |
| SPRITE, SCROLL, PANEL | REV $0B (Marga's sprites and fine scrolling; the emulator's default) |

### Pictures

A picture is a small image kept by BASIC, up to 64 x 64 pixels; there are 64 (0-63). It is
drawn with PUT (by the blitter in full screen) and shown by sprites. Two ways to make one:

- `SHAPE p, row, a$ [, a$ ...]`: text art, one string a row, one character a pixel: `.`,
  space or `0` clear, `1`-`9` and `A`-`F` the colours 1-15 (in a sprite: of its palette
  bank, at first the UI colours: 1 white, 7 dark grey, 8 grey, 9 light grey, A blue, B red,
  C yellow, D green, E orange, F almost black). The strings give rows `row`, `row + 1`, ...;
  `row` 0 starts a new picture. The picture is as wide as its longest row and as tall as its
  last row. A 16-colour picture.
- `GET p, x, y, w, h`: the pixels of the drawing (anything drawn with the statements above,
  in the window or the full screen). A 256-colour picture.

PUT draws a 16-colour picture in the colours 0-15 (its clear pixels are colour 0: `PUT p, x,
y, 0` leaves them out). RUN and NEW forget the pictures (a program makes its own); after END
they stay, for trying things in direct mode.

```
10 SHAPE 0,0,"..CC..",".CCCC.","CC11CC",".CCCC.","..CC.."
20 FOR R=0 TO 7:READ A$:SHAPE 1,R,A$:NEXT
30 COLOR 40:FRECT 0,0,16,16:COLOR 1:CIRCLE 8,8,5:GET 2,0,0,16,16
```

### Sprites

Sixteen sprites (0-15) are pictures the video chip shows over the graphics window (or the
full screen) by itself: moving one is a write of its place, nothing is drawn or erased.
Sprite 0 is in front of 1, and so on; the mouse pointer is in front of all.

| Statement | |
| --- | --- |
| `SPRITE n, x, y, p [, f]` | sprite n shows picture p with its top left at x, y (the window's content, or the screen in full screen). f (0-255, default 0) adds up: 1 mirrored left to right, 2 upside down, 4 twice the size, 8 behind the drawing (seen only where the drawing has colour 0), + 16 x b: palette bank b for a 16-colour picture (its colour c shows entry 16 x b + c; bank 0: the UI colours) |
| `SPRITE n, x, y` | moved (and shown again), the same picture and flags |
| `SPRITE n OFF`, `SPRITE OFF` | hidden: one, all |

```
10 SCREEN 320,200:SHAPE 0,0,"BBBB","B11B","BBBB"
20 FOR X=0 TO 300:SPRITE 0,X,100,0,4:VSYNC:NEXT
```

- **Sizes.** A sprite is 16 or 32 pixels wide and tall: a picture larger than 32 x 32 cannot
  be one ("Bad argument"). A 16-colour picture is shown with 4 bits a pixel; a 256-colour one
  up to 16 wide with 8 bits; one wider than 16 only if all its colours lie in one block of 16
  (16 x b to 16 x b + 15), as 4 bits in palette bank b. A picture changed (SHAPE, GET) changes
  the sprites showing it.
- **All together.** SPRITE changes BASIC's table; VSYNC (or, without VSYNC, the periodic
  update every 40 ms) gives all sixteen to the hardware in one call, so the changes of one
  frame show together. 16 SPRITE statements cost about 2 ms (0.12 ms each, emulated).
- **In a window**, by the kernel's rule for sprites: they show while the graphics window has
  the keyboard focus and nothing lies over it, and only those wholly inside it: the whole
  image, 16 or 32 pixels square (twice with flag 4), not only the picture's pixels. A
  picture 6 rows tall at y = 190 of a 200-row window is not shown (its 16 rows reach 205):
  keep sprites 16 (or 32) from the bottom and right edges. SCREEN brings the window to the
  front. In full screen they show at screen coordinates (320 x 180 in
  `SCREEN 1`), partly off the edges too.
- **END, STOP, a break, an error** hide them; CONT shows them again; RUN and NEW forget them.

**Collisions** (the hardware has none: BASIC compares boxes, in assembly):

| Function | Value |
| --- | --- |
| `HIT(a, b)` | -1 if sprites a and b are shown and their boxes overlap, else 0 |
| `HIT(a)` | the first sprite (lowest number) whose box overlaps sprite a's, -1 for none |
| `HIT(a, x, y, w, h)` | -1 if sprite a's box overlaps the rectangle x, y, w, h, else 0 |

A sprite's box is its picture's size (twice with flag 4), where the picture shows (a mirrored
narrow picture lies at the other side of its 16 or 32 pixels). Hidden sprites touch nothing.
HIT looks at BASIC's table: after a break it still sees the sprites CONT will show.

### Full screen

| Statement | |
| --- | --- |
| `SCREEN 1 [, w, h]` | full screen: 320 x 180 pixels in 256 colours (each pixel 4 x 4 on the monitor), the drawing area w x h (default 320 x 180, w 320-2048, h 180-960) |
| `SCREEN 2 [, w, h]` | full screen: 640 x 360 in 256 colours, w x h at least 640 x 360; the mouse pointer shows |
| `SCROLL x, y` | the screen shows the drawing area from x, y (REV $0B). The area is a ring both ways: x and y are taken modulo w and h, so a world drawn once scrolls on for ever |
| `PANEL n` | the bottom n rows of the screen (n < 0: the top -n), 1-64, show a panel that does not scroll: rows h to h + n - 1 of the drawing area (below its h rows; draw the score there with TEXT). `PANEL 0`: none (REV $0B) |
| `RASTER row, i, r, g, b` | from that row of the screen on (1-179 / 1-359), colour i is r, g, b: every frame starts with the palette's colours, then the raster table changes them line by line (a sky in bands: 16 changes, one colour each). The same row and colour again: replaced. At most 16; with a panel, only rows from the split on (a panel at the top: below it; at the bottom: in it). `RASTER OFF`: none (REV $09) |

```
10 SCREEN 1,640,360:REM a world of 640 x 360 seen 320 x 180 at a time
20 GCLS 20:FOR I=1 TO 99:COLOR 236:PLOT RND(640),RND(360):NEXT
30 COLOR 16:FRECT 0,360,320,12:COLOR 1:TEXT 2,360,"SCORE 0":PANEL -12
40 FOR I=1 TO 15:RASTER 12+I*10,20,0,0,I*15:NEXT
50 X=X+1:SCROLL X,0:VSYNC:GOTO 50
```

- Every drawing statement works in it (the drawing area is BASIC's framebuffer: w is rounded
  up to a multiple of 16; there are 64 more rows for the panel below it). PUT, COPY, FRECT and
  GCLS go to the blitter as a list that starts at the next VSYNC; PLOT, LINE, RECT, CIRCLE,
  TEXT, GET and POINT first wait for it. PALETTE sets all 256 colours (0-15 too). (Horizon
  0.19) Each bank of pictures is a sheet for the kernel, so PUT, FRECT and GCLS are sheet_draw
  records, which the kernel checks for a quarter of a draw_list record's time; COPY stays a
  draw_list record (a COPY between PUTs sends the list so far, as a full list does).
- The way back is always open (the kernel's): Alt+Tab or Alt+Esc show the desktop, F12 the
  classic machine; the graphics window, as a normal window, shows the top left of the
  drawing area; Alt+Tab (or a click on it) brings the full screen back. Esc stops the
  program as usual.
- PRINT goes to the console window, seen when the full screen is not: use TEXT on the screen.
  INPUT shows the desktop for the answer, then the full screen again.
- END, STOP, an error, a break and "Ready" show the desktop: the graphics window has the last
  picture; CONT goes back to the full screen. RUN, NEW and `SCREEN 0` end it (another
  SCREEN too).
- MOUSEX and MOUSEY give the pointer's place on the screen (320 x 180: halved).

## Samples (2.0)

Lau, the sample player (REV $0A), plays eight voices of sound from memory by itself. BASIC
keeps 32 samples (0-31), made by WAVE (on every board) and played by PLAY.

| Statement | |
| --- | --- |
| `WAVE s, shape [, ms [, half]]` | a sound made: shape 0 sine, 1 square, 2 triangle, 3 saw, 4 noise; ms long (default 400, at most 4000; 0: one that loops until stopped); the sound halves every `half` ms (0 or none: no decay). Note C4 (261.6 Hz) at 16,000 samples a second, a short rise and fall at its ends |
| `WAVE s, "file"` | a sound file from the card: a .WAV (PCM, mono, 8 or 16 bits, any rate) or else raw signed 8-bit samples at 16,000 a second; at most 65,534 bytes of sound (longer: cut) |
| `PLAY s [, note [, vol [, pan [, voice]]]]` | sample s on a free voice (when all eight play, BASIC's oldest one). note: semitones above the sample's own pitch (0, default; -96 to 96, as high as about 43 above a WAVE), or a note's name: `"C4"` is 0, `"A4"` 9, `"F#3"` -6, `"Bb5"` 22 (a letter A-G, then `#` or `b`, then an octave 0-8, default 4); vol 0-15 (default 15); pan -15 (left) to 15 (right), default 0 (both); voice 0-7: that one (a new PLAY on it replaces what it plays: a melody on one voice) |
| `PLAY OFF [voice]` | BASIC's voices stopped (or one) |

```
10 WAVE 0,2,600,150:REM a plucked triangle, 0.6 s, halving every 150 ms
20 FOR I=1 TO 8:READ N$:PLAY 0,N$,12,0,1:PAUSE 200:NEXT
30 DATA C4,D4,E4,F4,G4,A4,B4,C5
```

- A file's sound plays at its own rate as note 0: `PLAY s, 12` an octave higher.
- END, STOP, a break, an error and RUN stop the voices, as SOUND's; RUN and NEW forget the
  samples. PLAY without Lau: "Not available on this machine" (WAVE works; SOUND still plays
  POKEY 2's tones).
- WAVE takes about 0.13 s for a second of sound (0.5 s with a decay; emulated): make the
  samples at the start.
- SOUND (POKEY 2) is unchanged and plays at the same time.

## Errors

An error stops the program with a message and the line: `Type mismatch in 120`.

Syntax error · Type mismatch · Out of memory · Undefined line N · Division by zero ·
Overflow · Subscript out of range · Array already dimensioned · NEXT without FOR · RETURN
without GOSUB · WEND without WHILE · WHILE without WEND · Out of DATA · Bad argument ·
String too long · Too many variables · Nesting too deep (FOR, GOSUB, WHILE: 256) ·
Expression too complex · Cannot continue · File error · File not found · Line too long ·
Too many lines · Number too large (a line number) · Name too long · Line number missing
(LOAD of a line without a number: `... in file line N`) · Illegal function call (SQR of a
negative number, LOG of 0, `(-8)^(1/3)`, SIN of 1E9 or more) · (2.0) Not available on this
machine (the hardware is not there: see "Games") · Full screen only (SCROLL, PANEL, RASTER
without `SCREEN 1` / `SCREEN 2`) · In use by another program (sprites, the full screen or
Lau's voices held by another program) · Undefined picture · Undefined sample.

A program cannot crash BASIC: subscripts, string lengths, nesting, the expression depth
and memory are checked, and POKE only reaches BASIC's own memory.

## Limits

| | |
| --- | --- |
| Lines | 8,000, numbered 0-65535; 240 characters typed, 500 bytes tokenized |
| Program | 8 banks (512 KB) of tokenized lines |
| Variables | 2,048 names (numbers, strings and arrays together) |
| Numbers | integers of 32 bits; floats of 12 decimal digits, 1E-99 to 9.99999999999E+99 |
| Strings | 255 characters; the heap grows to 16 banks (1 MB) |
| Arrays | 4 dimensions, 64 KB each, 32 banks (2 MB) in all |
| Nesting | 256 FOR / GOSUB / WHILE; parentheses and functions nest hundreds deep; 48 strings or floats waiting in one expression |
| Pictures | 64, up to 64 x 64 pixels each (as sprites up to 32 x 32) |
| Sprites | 16 (the hardware's), boxes for HIT |
| Full screen | a drawing area up to 2048 x 960 (and 64 rows of panel), in consecutive banks: 2 MB at most |
| Raster | 16 changes a frame |
| Samples | 32, up to 65,534 bytes each (a WAVE: 4 s); 16 banks (1 MB) in all; a sample made again keeps its place when the new one fits there |
| Draw list | 128 blits a list (PUT, COPY, fills in full screen; more: a list is sent and the next one starts) |

## Testing

`basic -t FILE` reads FILE as if it were typed: numbered lines go into the program, the
other lines run (they are shown on the console, errors are reported and the next line
follows), and INPUT takes its answer from the next line of the file. If the file had only
numbered lines, it is RUN at the end. Then BASIC exits (exit code 1 if an error was
reported). The console is copied to the kernel console (DBG_OUT), so the emulator's
output holds the whole session.

`make test` runs `tests/basic.bas` this way: it RUNs `/programs/TESTS.BAS` (PASS or FAIL
for each group of statements and functions), then error messages, LIST, INPUT, CONT,
SAVE / LOAD and the benchmarks; the output must match `tests/basic.txt`. TESTS.BAS is on
the card, so the same checks run on the board. Its float groups check the arithmetic and
its rounding, the integer / float rules, PRINT / STR$ / VAL, FOR with a float step, and
each function against a table of true values computed on the PC
(`python3 tests/basic_fp.py table`, with mpmath): every result must be within 1E-10 of
it. `tests/basic_fp.py consts` makes the constants and polynomials of `user/bas_fn.s`.

`make test` (and `make basic2-test` alone) also runs `tests/basic2.bas` the same way: every
2.0 statement and function with its errors, LIST and SAVE / LOAD of the new words, a 1.x
program loaded, drawing in the window and in full screen, sprites and HIT, SCROLL, PANEL and
RASTER and their checks, WAVE (made and from files: `tests/mkwav.py` puts a .WAV of 8 and of
16 bits, a stereo one and a raw file on the card), PLAY and NOTE, and the cleanup after STOP,
CONT, an error, RUN and NEW. Its output must match `tests/basic2.txt`, on older boards
`basic2-r10.txt`, `-r9`, `-r8` (only the "Not available on this machine" lines differ), its
writes to Lau `tests/basic2.err`. On REV $0B a picture session (`tests/basic2s.keys`) runs
SPRITES.BAS, DRIFT.BAS and SCROLLER.BAS with Break, Alt+Tab and CONT
(`tests/pictures/basic2s*.png`). TESTS.BAS has a 2.0 group too (pictures in a window, NOTE,
FRAME: the parts every board has).

## Examples

In `/programs` on the card (from `sdfiles/programs`):

| Program | Shows |
| --- | --- |
| `DEMO.BAS` | lines, circles, colours, PALETTE: a sunset |
| `SNAKE.BAS` | a game: INKEY$ and the arrow keys (or joystick 1: STICK), arrays, sound |
| `SOUND.BAS` | a scale, a chord, a tune from DATA, a siren |
| `SIEVE.BAS` | the BYTE prime sieve benchmark |
| `PLOT.BAS` | a function plotter: SIN, COS and a damped wave over a grid, with axes and labels |
| `MANDEL.BAS` | the Mandelbrot set in 256 colours (PALETTE), in floating point: 160 x 120 in under two minutes |
| `LOAN.BAS` | a loan: the monthly payment and a table year by year, to the cent (decimal floats, ROUND) |
| `TESTS.BAS` | the self test |
| `SPRITES.BAS` | (2.0) bouncing balls: pictures from text (SHAPE), sprites, a sound at each bounce (WAVE, PLAY), VSYNC; about 30 lines |
| `DRIFT.BAS` | (2.0) a small complete game in full screen: steer a boat, pick up lanterns, miss the logs; sprites, HIT, the arrows or a joystick (STICK), samples, score and best score |
| `SCROLLER.BAS` | (2.0) full screen over a 640 x 360 world that wraps around (SCROLL), a panel (PANEL), a sky of raster bands (RASTER), houses copied by the blitter (GET, PUT), a sprite |
| `MUSIC.BAS` | (2.0) a short tune of its own in two voices and a tick: WAVE instruments, PLAY with note names, timing by FRAME |

## Speed

Emulated time (14.3 MHz; the board's CPU paths run about 2.3 times slower, see README.md):

| Program | Time |
| --- | --- |
| `FOR I=1 TO 100000:NEXT I` | 2.4 s (24 us an iteration; 1.0: 2.37 s) |
| `FOR I=1 TO 100000:A(I MOD 1000)=I*3+7:NEXT I` | 21.7 s (217 us; 1.0: 21.6 s) |
| SIEVE.BAS (10 passes over 8191 flags, 1899 primes) | 45.3 s (4.5 s a pass; 1.0: 44.8 s) |
| `FOR I=1 TO 10000:Y=SIN(I):NEXT` | 28.5 s (2.9 ms a SIN) |
| `FOR I=1 TO 10000:Y=SQR(I):NEXT` | 10.0 s (1.0 ms a SQR) |
| `S=S*0.5+X*1.25`, 10,000 times | 4.5 s (0.45 ms) |
| Mandelbrot iterations `C=A*A-B*B+X:B=2*A*B+Y:A=C`, 6983 of them | 13.6 s (1.9 ms each) |
| MANDEL.BAS (160 x 120, 32 colours of escape) | 106 s |

A float `+` or `-` takes about 60 us, `*` 170 us, `/` 430 us, SQR 0.8 ms, SIN, COS,
EXP, LOG and ATN 2.5 to 2.9 ms, against 5 to 10 us for an integer `+`.

(2.0) The games statements, emulated, each with its arguments (the board: about twice):

| | |
| --- | --- |
| `SPRITE n, x, y` | 0.12 ms |
| `H=HIT(0)` | 0.16 ms |
| `S=STICK(0)` | 0.2 ms (it reads the events first) |
| `PUT p, x, y` of 16 x 16, full screen (queued for the blitter) | 0.27 ms |
| the same with the kernel's part of the list (2,400 PUT, lists sent when full; Horizon 0.19) | 0.375 ms (0.446 ms on Horizon 0.18) |
| `PUT p, x, y` of 16 x 16 in a window (the CPU) | 0.7 ms |
| `PLAY s, n` | 0.4 ms |
| status line of two numbers (FRECT, TEXT of 5 characters) | 2.9 ms |
| DRIFT.BAS, a frame of play (the boat, six things in the river, HIT) | 5.2-5.7 ms: 60 frames a second, none missed in 1200 |

2.0 moved the control stack and the line editor's history into the window bank (long
addressing): an empty FOR loop is 1 % slower (2.46 s for 100,000, was 2.43 s); the other
benchmarks did not change.

Lines are tokenized when entered: keywords become one byte, numbers are binary, and every
variable is resolved to its slot then, so running never looks up a name. GOTO and GOSUB
cache the target line's index in the line itself.

## Differences from Atari BASIC

- Numbers are 32-bit integers or decimal floats of 12 digits (Atari: 6-byte BCD floats
  of 9 to 10 digits); the integers make loops and arrays fast.
- Strings need no DIM and can be up to 255 characters; parts are taken with LEFT$, RIGHT$
  and MID$ instead of `A$(i, j)`; there are string arrays.
- Arrays have up to 4 dimensions and start at 0.
- IF ... THEN ... ELSE, WHILE / WEND, ON ... GOSUB, MOD, XOR, `^` on integers, HEX$,
  INSTR, MIN / MAX.
- Keywords must be separate words and are not abbreviated (`PR.` is not PRINT; `?` is).
- GOTO, GOSUB and RESTORE take line numbers, not expressions.
- True is -1, not 1.
- Graphics are a window of their own (SCREEN, COLOR, PLOT, LINE ...) instead of GRAPHICS,
  SETCOLOR, PLOT, DRAWTO; colours come from a 256-colour palette.
- SOUND takes Hz (Atari's 4-argument form also works).
- STICK and STRIG read the two joystick ports as Atari BASIC does (ports 0 and 1; PTRIG
  and PADDLE are not there).
- PEEK and POKE reach a private 64 KB block, not the hardware: the hardware belongs to
  the kernel.
- No TRAP, no files from programs (OPEN, PRINT #, INPUT #) yet, no PRINT USING, no USR
  or machine code.
- (2.0) No player-missile graphics: 16 sprites of up to 32 x 32 in 16 or 256 colours
  instead (SPRITE), with collisions by boxes (HIT) rather than by pixels; no GRAPHICS modes
  and display lists: a window of any size, or the full screen (`SCREEN 1`, `SCREEN 2`) with
  fine scrolling, a split panel and raster colours (SCROLL, PANEL, RASTER); samples (WAVE,
  PLAY) as well as POKEY's tones.

## Changes in 2.0

- Pictures (SHAPE, GET, PUT, COPY), sprites (SPRITE, HIT), full screen (`SCREEN 1`,
  `SCREEN 2`, SCROLL, PANEL, RASTER), samples (WAVE, PLAY, NOTE), FRAME; VSYNC sends the
  frame's changes first; STICK(0) and STRIG(0) follow the arrow keys and Space too.
- **Reserved words**: SPRITE, SHAPE, GET, PUT, COPY, WAVE, PLAY, SCROLL, PANEL, RASTER, OFF,
  HIT, FRAME, NOTE are keywords now and cannot be variable names (a 1.x program using one of
  them as a name says "Syntax error" there: rename it). Names that contain them (`HITS`,
  `FRAMES`) are fine. None of the shipped 1.x examples uses one; programs are kept as text,
  so every 1.x program loads.
- PALETTE: the entry is BASIC's own (Horizon 0.18's rule), given back at RUN and the end.
- SCREEN of the same size brings the window to the front (sprites show only there).
- The keys typed for a program (a game's arrows) no longer reach the command line after it
  stops.
- New errors: Not available on this machine, Full screen only, In use by another program,
  Undefined picture, Undefined sample.
- Inside: the extended statements are two-byte tokens (`$FC`, then the statement), so new
  ones need no free single-byte token; the window bank holds the control stack, the
  history, the row table and the sprite and draw-list records (the code bank has about
  3 KB left); BASIC.PRG is built with `tools/o65strip.py`, which drops the relocation
  entries that add 0 (the program is linked and loaded at $0100), or the file would be over
  the loader's 64 KB (71 KB -> 52 KB).

## Changes in 1.2

- `STICK(n)`, `STRIG(n)`: the joystick ports, with Atari BASIC's values.
- `VSYNC`: waits for the next vertical blank.
- STICK, STRIG and VSYNC are keywords now and cannot be variable names.
- The error "Can't continue" reads "Cannot continue".

## Changes in 1.1 (floating point)

What a BASIC 1.0 program may notice:

- `/` no longer truncates: `7/2` is 3.5 (it was 3). Use `\` (or INT) for the old integer
  division: `7\2` is 3. MOD is unchanged.
- An integer result beyond 32 bits is a float instead of "Overflow": `2147483647+1` is
  2147483648, and a literal like `99999999999` is a float, no longer "Number too large".
- `^` with a negative exponent is a float: `2^-1` is 0.5 (it was 0).
- `RND` and `RND(1)` give a float from 0 to below 1 (`RND(1)` was always 0); `RND(n)`
  for n >= 2 is unchanged (0 to n-1).
- SQR, SIN, COS, TAN, ATN, EXP, LOG, LOG10, INT, FIX, ROUND, PI, DEG and RAD are
  keywords now, and cannot be variable names.
- Integer programs run as before: integers stay integers, at most 2 % slower (see Speed).
