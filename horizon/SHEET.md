# Sheet

The spreadsheet of the Atari816: `/BIN/SHEET.PRG`, written in 65816 assembly (sources
`user/sheet.s` and `user/sht_*.s`, listed at the top of `sheet.s`).

## Starting

| How | What |
| --- | --- |
| Desktop: Programs > Sheet | an empty sheet |
| Files: open a `.SHT` or `.CSV` file | Sheet with that file (a CSV is imported) |
| `sheet [FILE]` (shell) | the same; Sheet starts the window system itself when it is not running |
| `sheet -t FILE` | the self test, see "Testing" |

Two examples are on the card: `/programs/BUDGET.SHT` (a household budget: totals, a
year column, shares in percent) and `/programs/LOAN.SHT` (a loan's payment with `PMT`,
and ten years of savings with compound interest).

## The window

- **The entry line** at the top: the cursor's cell (or the selected range, `B4:C8`) and
  its content as it would be typed: a formula's text, a number in full.
- **The grid**: column letters A-Z, row numbers 1-999, a scroll bar on each side. Numbers
  are right-aligned, text left-aligned; a text wider than its column runs on into empty
  cells to its right. Errors are red and centred. A number too wide for its column shows
  `###`. The selected cells are light blue, the cursor's cell has a blue frame.
- **The title** shows the file's name and `*` when the sheet changed since it was loaded or
  saved.

## Keys

| Key | |
| --- | --- |
| Arrows, PgUp, PgDn | move the cursor (Shift: extend the selection) |
| Home / End | column A / the last used cell of the row |
| ctrl-Home / ctrl-End | A1 / the end of the used area |
| Enter, Tab | down / right (Shift: up / left) |
| typing | starts editing the cell with that character |
| F2, a double click | edits the cell's content |
| Backspace | edits from an empty field |
| Delete | clears the selection |
| Esc | (editing) cancels; otherwise the selection shrinks to the cursor |
| ctrl-X / C / V | cut, copy, paste |
| ctrl-D / R | fill down / right |
| ctrl-A | select everything |
| ctrl-N / O / S | new, open, save |

While editing, the field takes the keys (Left / Right, Home / End, Shift selections,
ctrl-C / X / V on its text); Enter, Tab, Up, Down, PgUp and PgDn take the entry and then
move. A formula that does not compile is not taken: a beep, and the field stays.

## The mouse

- A click selects a cell (Shift: extends), a drag selects a range (the view follows past
  its edges).
- A click on a column letter selects the column, on a row number the row, on the corner
  everything; dragging there extends over more columns or rows.
- Dragging the line at the right of a column letter changes that column's width.
- While a formula is being typed and its text ends with an operator, `(`, `,` or `:`, a
  click on a cell puts the cell's name into the formula.
- The wheel scrolls three rows a notch.

## Menus

- **File**: New, Open..., Save, Save as..., Export CSV..., Close. New, Open and Close ask
  before unsaved changes are lost. Open reads a `.CSV` file as CSV and anything else as a
  sheet; Save writes a sheet (a sheet that came from a CSV file asks for a name). A name
  without an extension gets `.SHT` (Export: `.CSV`).
- **Edit**: Cut, Copy, Paste, Clear, Fill down, Fill right, Insert row, Insert column,
  Delete row, Delete column. Insert and delete work on as many rows or columns as are
  selected.
- **Format** (for the selected columns): General, 0 decimals, 2 decimals, 4 decimals,
  Thousands (on / off), Percent (on / off), Column width... (16-400 pixels).

## Cells

A cell holds what is typed into it:

- **A number**: digits with an optional sign and decimal point; `1,234.5` (commas between
  the digits of the whole part) and `12.5%` (= 0.125) are numbers too.
- **A formula**: starts with `=`.
- **Text**: anything else. An apostrophe first makes the rest text: `'123`, `'=x`.

### Numbers

Numbers are decimal fixed point: four decimals, at most 922,337,203,685,477.5807 either
way. There is no binary floating point, so 0.1 + 0.2 is exactly 0.3. A number typed with
more decimals is rounded to four. Every result is rounded to four decimals, half away
from zero: `=1/3` is 0.3333, `=2/3` 0.6667, `=-2/3` -0.6667, `=1/7*7` 1.0003. A result
past the range is the error `#OVER`.

### Formats

Per column. General shows up to four decimals without trailing zeros; 0, 2 or 4 decimals
round (half away from zero) to that many; Thousands adds commas (1,234,567.5); Percent
shows the value times 100 with `%` (0.125 is 12.5%, with 2 decimals 12.50%). The format
only changes what is shown, never the value.

### Formulas

| | |
| --- | --- |
| Operators, lowest first | `=  <>  <  >  <=  >=` (1 if true, 0 if false); `+ -`; `* /`; unary `-`; `^` |
| `^` | a whole exponent (negative allowed), right-associative: `2^3^2` = 512; `-2^2` = -4 |
| References | `A1`, `$A$1`, `A$1`, `$A1`: `$` keeps that part when copied |
| Ranges | `A1:C9` (in either order), as function arguments |
| Errors as values | `#DIV/0 #REF #VALUE #CYCLE #OVER` may be typed (`#REF!` too) |

An empty cell counts as 0. Text in arithmetic is `#VALUE`, and so is a range outside a
function. Errors flow through: a formula using a cell with an error has that error.

| Function | |
| --- | --- |
| `SUM(...)` `AVERAGE(...)` `MIN(...)` `MAX(...)` `COUNT(...)` | numbers, ranges (up to 30 arguments); in ranges text and empty cells are skipped; `COUNT` counts numbers and skips errors; `AVERAGE` of nothing is `#DIV/0`, `MIN` / `MAX` of nothing 0 |
| `AND(...)` `OR(...)` `NOT(x)` | 1 / 0; `AND` / `OR` of nothing is `#VALUE` |
| `IF(c, a, b)` | `a` if `c` is not 0, else `b` (0 when left out); an error in the branch not taken does not matter |
| `ABS(x)` `INT(x)` `SQRT(x)` | `INT` rounds down (`INT(-3.2)` = -4); `SQRT` of a negative number is `#VALUE` |
| `ROUND(x, n)` | to n decimals (n from -14 to 4), half away from zero |
| `MOD(a, b)` | the remainder with the sign of b, as spreadsheets do (`MOD(-7,3)` = 2) |
| `PMT(rate, periods, amount)` | the payment per period that repays `amount` in `periods` payments at `rate` per period: `PMT(0.005,60,20000)` = 386.656 (a positive amount gives a positive payment). Computed with twelve decimals inside, so the payment is exact to its four |

Names of functions and references may be lower case. Spaces between tokens are allowed.

### Recalculation

After every change the sheet is recalculated, each formula after the cells it uses (in
any order on the sheet), and only formulas whose inputs changed are evaluated again. A
formula that uses itself, directly or through others, is `#CYCLE`, and so is every
formula using it. Emulated (the board takes about twice as long), on a sheet of 2,000
formulas: all of them computed (loading) 0.59 s; an edit that changes 504 of them 0.27 s;
an edit that changes four 0.21 s (most of it is visiting the 2,000 to see that nothing
they use changed).

### Copying, filling, moving

Copy and Cut put the cells on the program's clipboard and, as text (the values as shown,
tab-separated, one line per row), on the system clipboard, so they paste into Edit.
Paste puts the program's cells back at the cursor with relative references moved by the
distance (`$` parts stay); a reference moved off the sheet becomes `#REF`. One copied cell
pasted onto a selection fills it. When the system clipboard holds other text (copied in
Edit, or from the entry field), Paste reads it as tab-separated rows of values instead.
Cut is copy and clear: references to the cut cells are not changed.

Fill down copies the selection's top row into the rows below (Fill right: the left column
to the right), references moved as for Paste.

Inserting and deleting rows and columns moves the cells and every reference to them,
absolute or not; a reference to a deleted cell becomes `#REF`, a range loses the deleted
rows (or columns). What moves past row 999 or column Z is lost.

## Files

### .SHT

Text, one item per line (LF or CR LF):

```
SHEET 1
W A 112         column A is 112 pixels wide (only widths that are not the default 64)
F B 2T          column B: 2 decimals and thousands separators (G general, 0-4 decimals,
                then T thousands and / or P percent)
A1 Budget       a cell: its name, one space, its content exactly as it would be typed
B4 =SUM(B1:B3)
C2 '123         (text that would read as a number or a formula starts with ')
```

Lines may come in any order; lines that are not understood are skipped; cells are written
row by row. A formula that does not compile is kept, with the value `#VALUE`.

### CSV

Export writes the values (formulas as their results, errors by name), numbers in the
general format, one line per row (CR LF) up to the last used row and column; text with a
comma, a quote, a line break or spaces at its ends is quoted (`""` inside). Import (Open
of a `.CSV` file) reads fields separated by commas, quoted fields with commas and line
breaks inside, and treats each field as if typed: numbers become numbers.

## Limits

- 26 columns, 999 rows; 250 characters in a cell; formulas compile to at most 1,400 bytes
  and nest at most 40 deep; functions take at most 30 arguments.
- Formulas give numbers and errors only (no text results, no string literals).
- Numbers have four decimals in every intermediate result: a rate like 4.5% / 12 =
  0.00375 becomes 0.0038. `PMT` keeps more precision inside.
- The cell heap holds up to 16 banks (1 MB): about 3,800 cells of 250 characters, or many
  more short ones; past that, "Not enough memory" and the change is not made.
- No undo. Formats are per column, not per cell.

## Testing

`sheet -t FILE` runs a script without a window and prints to the console (and the debug
log): `PASS name` or `FAIL name` with the failed checks for each group, then `SHEET TEST
END: g groups, f failed`. The script holds `.SHT` lines (cells, widths, formats) and:

| Line | |
| --- | --- |
| `= NAME` | a group of checks starts |
| `? A1 TEXT` | the value as the general format shows it must be TEXT |
| `?f A1 TEXT` | the value as its column's format shows it |
| `?s A1 TEXT` | the content as it would be typed |
| `! COMMAND` | `copy R T`, `cut R T`, `filld R`, `fillr R`, `clear R`, `insr N`, `delr N`, `insc L`, `delc L`, `new`, `save P`, `load P`, `csvout P`, `csvin P`, `recalc`, `bench`, `memfill` |

`tests/sheet.sht` is the script `make test` runs (21 groups: input and rounding,
arithmetic, operators, overflow, every function, errors, cycles, a chain 998 deep, copy and
paste, fill, insert and delete with references, files, CSV, formats, bad input, out of
memory, and the benchmark); `tests/sheet.keys` is the picture session.
