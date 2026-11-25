#!/usr/bin/env python3
"""gltest.py OUT EXPECTED - (0.31) the line editor's test (tests/gltest.keys): OUT is the
console of the run (GLTEST's lines, the shell's, and the echo of each typed line), EXPECTED
the lines GLTEST, HELLO and the shell must have printed (tests/gltest.txt, compared as
tests/compare.py does: the lines starting with "gltest:", "Hello from" or "sh: ").

The echo is checked on a simulated screen line: each prompt line ("? " GLTEST's, "> " the
shell's) is replayed (a printable character is written at the cursor, which moves right;
BS moves it left), and
  - no BS comes at column 0 (the console's BS stops there: the editor would lose its place)
  - nothing is written into the last column (the cursor stays left of it: no wrap); a
    closing ^C may be (it is written where the cursor is)
  - for GLTEST's lines: what the screen line shows right of the prompt at Enter is a piece
    of the line GLTEST received: as much of it as fits from the view's start (the room: the
    columns less the prompt less one)
  - one shell line ends with ^C (ctrl-C on a long line)
Exit status 0 when all holds; else the problems on stdout."""
import subprocess
import sys

out = open(sys.argv[1], encoding='latin-1').read().replace('\r', '').split('\n')
bad = []
cols = None
for ln in out:
    if ln.startswith('gltest: type lines ('):
        cols = int(ln.split('(')[1].split()[0])
if not cols:
    sys.exit('gltest.py: no "gltest: type lines" line in %s' % sys.argv[1])
room = cols - 2 - 1                             # (both prompts are 2 characters)
checked = breaks = 0
for i, ln in enumerate(out):
    if not (ln.startswith('? ') or ln.startswith('> ')):
        continue
    if ln.endswith('^C'):                       # (written where the cursor is)
        ln = ln[:-2]
        breaks += 1
    row = [' '] * cols
    col = 0
    err = None
    for ch in ln:
        if ch == '\b':
            if col == 0:
                err = 'a backspace at column 0'
                break
            col -= 1
        elif ' ' <= ch < '\x7f':
            if col >= cols - 1:
                err = 'a character written into the last column (%d)' % col
                break
            row[col] = ch
            col += 1
    if err:
        bad.append('line %d: %s' % (i + 1, err))
        continue
    if not ln.startswith('? '):
        continue
    nxt = next((l for l in out[i + 1:] if l.startswith('gltest:')), '')
    if not nxt.startswith('gltest: ') or nxt.count(':') < 2 or nxt == 'gltest: done':
        continue
    text = nxt.split(': ', 2)[2]
    shown = ''.join(row[2:]).rstrip()
    vs = text.find(shown)
    if vs < 0 or len(shown) != min(room, len(text) - vs):
        bad.append('line %d: the screen shows %r, not a view of %r (room %d)' % (i + 1, shown, text, room))
    checked += 1
if checked != 7:
    bad.append('%d of GLTEST\'s typed lines checked (7 expected)' % checked)
if breaks != 1:
    bad.append('%d lines ended by ctrl-C (1 expected)' % breaks)
got = '\n'.join(l for l in out if l.startswith(('gltest:', 'Hello from', 'sh: '))) + '\n'
tmp = sys.argv[1] + '.lines'
open(tmp, 'w', encoding='latin-1').write(got)
r = subprocess.run([sys.executable, sys.argv[0].replace('gltest.py', 'compare.py'), sys.argv[2], tmp])
if r.returncode:
    bad.append('the lines printed differ from %s (%s)' % (sys.argv[2], tmp))
print('\n'.join(bad))
sys.exit(1 if bad else 0)
