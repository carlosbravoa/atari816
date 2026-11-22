#!/usr/bin/env python3
"""run816.py - run a Horizon program in the emulator, with scripted input and screenshots.

    run816.py PROG.PRG [options]

It copies Horizon's SD card (HORIZON/build/sd) to OUT/card, puts the program on it,
boots emu816 (headless), starts the program, feeds the input script, and writes:

    OUT/console.txt   everything printed on the kernel console (DBG_OUT), escapes removed
    OUT/emu.err       emu816's own log (blitter rule reports, --log-sound writes, ...)
    OUT/shotN.png     the screenshots (1280 x 720, as on the monitor; .ppm without PIL)
    OUT/card/         the card after the run (files the program wrote are there)

How the program is started:
  --mode desktop  (default) the Desktop boots; the program is put first in its Programs
                  menu (/SYSTEM/PROGRAMS) and chosen with the keyboard (F10, Right, Enter).
                  For window programs. No argument string.
  --mode shell    the text shell (/SYSTEM/NODESK on the card); the path and --args are
                  typed at the prompt. For console programs (their output is on the screen
                  and in console.txt) and for window programs that take arguments.

Time 0 of the input script and of --shot is the moment the program is started (the
Desktop takes 5 s to boot and launch it, the shell about 4 s).

Options:
  --horizon DIR   Horizon tree with a built card (default: $HORIZON, else ../horizon next
                  to the SDK). Build it with `make -C DIR`.
  --emu FILE      emu816 (default: $EMU, else DIR/../emu/emu816)
  --dest PATH     where the program goes on the card (default /APPS/NAME.PRG)
  --args TEXT     argument string (shell mode)
  --cd DIR        (shell mode) type "cd DIR" first; the program's path is then typed
                  relative to DIR when it lies in it (--dest /GAMES/MINE/X.PRG --cd /GAMES
                  types "MINE/X.PRG")
  --script FILE   input script (see inputscript.py; 'T shot' lines add screenshots)
  --shot SECONDS  a screenshot at that time (repeatable; at most 16 in all)
  --seconds N     how long to run after the start (default: the last event + 2 s)
  --out DIR       output folder (default: run-NAME)
  --file SRC[:DEST]  copy a file onto the card too (DEST default /SRC-NAME; repeatable)
  --rev N         hardware revision to emulate (default: emu816's, REV $0B: the blitter
                  with command lists, Lau, sprites, fine scrolling); 10 no sprites or
                  scrolling, 9 no Lau, 8 no command lists / raster / NV_FRAME, 7 no blitter
  --log-sound     log every write to POKEY 2 / the DACs in emu.err
  --log-sound-us  the same with the emulated time in microseconds ("sound US $DBxx = $yy")
  --log-lau       log every write to Lau, the sample player, in emu.err ("lau $DBxx = $yy")
  --kbd-release MS  release the keys held when no key changed for MS ms: the board's
                  firmware before 2026-11 did so after 1000 ms (a held key went up)
  --wav FILE      (Horizon 0.26) record Lau's output (48 kHz stereo WAV): listen on the PC;
                  (0.27) with the OPL2's, mixed as on the board (no POKEY)
  --net           (Horizon 0.22) the internet through an emulated PC link: tcp:// URLs
                  become real connections of the PC running the emulator
  --net-root DIR  (Horizon 0.22) http://, https://, ftp:// URLs are served from the
                  files DIR/host/path (a missing file is HTTP status 404)
  --prof FILE     a profile: emu816's cycles by instruction address, syscall, kernel
                  and idle in FILE (sdk/c/game/tests/tools/prof816.py makes it a table of
                  the program's functions); --prof-from S --prof-to S: only from S to S
                  seconds after the program's start (as --shot's times)
  --expect TEXT   fail unless console.txt contains TEXT (repeatable)
  --window        open the emulator's SDL window instead (needs emu816 built with SDL=1;
                  real time; type and click yourself)
Exit code 0 when the run went as expected; 1 when the program was killed by the kernel
("[kill]" on the console), an --expect text is missing, or emu816 reported a blitter
rule broken (only the kernel drives the blitter, so that would be a kernel bug).
"""
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import inputscript  # noqa: E402

DESK_BOOT_MS = 4000      # F10 at 4.0 s (the Desktop and Files are up by then)
SHELL_ESC_MS = 1500      # the shell starts in the file browser: Esc
SHELL_TYPE_MS = 2500


def die(msg):
    sys.exit(f'run816: {msg}')


def strip_escapes(b):
    s = b.decode('latin-1')
    s = re.sub(r'\x1bY..', '', s, flags=re.S)       # ESC Y r c
    s = re.sub(r'\x1b.', '', s, flags=re.S)         # ESC x
    s = s.replace('\x0c', '\n')
    return s


def main():
    a = sys.argv[1:]
    if not a or a[0] in ('-h', '--help'):
        print(__doc__)
        return 0
    opt = {'mode': 'desktop', 'shots': [], 'files': [], 'expect': [], 'args': ''}
    prog = None
    i = 0
    while i < len(a):
        w = a[i]
        def val():
            if i + 1 >= len(a):
                die(f'{w} needs a value')
            return a[i + 1]
        if w in ('--horizon', '--emu', '--dest', '--args', '--script', '--seconds', '--out',
                 '--rev', '--mode', '--net-root', '--wav', '--cd', '--prof', '--prof-from',
                 '--prof-to', '--kbd-release'):
            opt[w[2:]] = val(); i += 2
        elif w == '--shot':
            opt['shots'].append(float(val())); i += 2
        elif w == '--file':
            opt['files'].append(val()); i += 2
        elif w == '--expect':
            opt['expect'].append(val()); i += 2
        elif w in ('--log-sound', '--log-sound-us', '--log-lau', '--window', '--net'):
            opt[w[2:]] = True; i += 1
        elif w.startswith('--'):
            die(f'unknown option {w}')
        else:
            prog = w; i += 1
    if not prog:
        die('no program given')
    if opt['mode'] not in ('desktop', 'shell'):
        die('--mode is desktop or shell')

    hz = opt.get('horizon') or os.environ.get('HORIZON') or os.path.join(HERE, '..', '..', 'horizon')
    hz = os.path.abspath(hz)
    card0 = os.path.join(hz, 'build', 'sd')
    if not os.path.exists(os.path.join(card0, 'SYSTEM', 'HORIZON.SYS')):
        die(f'no built card in {card0}: run make -C {hz}')
    emu = opt.get('emu') or os.environ.get('EMU') or os.path.join(hz, '..', 'emu', 'emu816')
    if not os.path.exists(emu):
        die(f'no emulator at {emu}: run make -C {os.path.dirname(os.path.abspath(emu))}')

    name = os.path.splitext(os.path.basename(prog))[0].upper()
    dest = opt.get('dest') or f'/APPS/{name}.PRG'
    if len(dest) > 100:
        die('--dest too long')
    out = os.path.abspath(opt.get('out') or f'run-{name.lower()}')
    card = os.path.join(out, 'card')
    if os.path.exists(card):
        shutil.rmtree(card)
    os.makedirs(out, exist_ok=True)
    for f in os.listdir(out):
        if re.fullmatch(r'shot\d+\.(png|ppm)', f):
            os.remove(os.path.join(out, f))
    shutil.copytree(card0, card)

    def put(src, dst):
        p = os.path.join(card, dst.lstrip('/'))
        os.makedirs(os.path.dirname(p), exist_ok=True)
        shutil.copy(src, p)
    put(prog, dest)
    for f in opt['files']:
        src, _, d = f.partition(':')
        put(src, d or '/' + os.path.basename(src).upper())

    if opt['mode'] == 'desktop':
        if opt['args']:
            die('--args needs --mode shell (the Programs menu passes no argument)')
        pfile = os.path.join(card, 'SYSTEM', 'PROGRAMS')
        old = open(pfile).read() if os.path.exists(pfile) else ''
        title = name.capitalize()
        open(pfile, 'w').write(f'{title}={dest}\n' + old)
        boot = [f'{DESK_BOOT_MS} {{f10}}', f'{DESK_BOOT_MS + 400} {{right}}',
                f'{DESK_BOOT_MS + 800} \\n']
        t0 = DESK_BOOT_MS + 1000
    else:
        open(os.path.join(card, 'SYSTEM', 'NODESK'), 'w').write('')
        run, cd = dest, opt.get('cd')
        if cd:
            cd = '/' + cd.strip('/')
            if dest.upper().startswith(cd.upper().rstrip('/') + '/'):
                run = dest[len(cd.rstrip('/')) + 1:]
        cmd = run + (' ' + opt['args'] if opt['args'] else '')
        if any(c in cmd + (cd or '') for c in '{}^') or '\\' in cmd + (cd or ''):
            die('the command line may not contain { } ^ or backslashes')
        boot = [f'{SHELL_ESC_MS} {{esc}}']
        t = SHELL_TYPE_MS
        if cd:
            boot.append(f'{t} cd {cd}\\n')
            t += 50 * (len(inputscript.strokes('cd ' + cd)) + 1) + 600
        boot.append(f'{t} {cmd}\\n')
        t0 = t + 50 * (len(inputscript.strokes(cmd)) + 1) + 100

    try:
        bk, bm, _ = inputscript.parse(boot)
        lines = open(opt['script']).readlines() if opt.get('script') else []
        uk, um, us = inputscript.parse(lines, t0)
    except inputscript.ScriptError as e:
        die(f'{opt.get("script")}: {e}')
    except OSError as e:
        die(str(e))
    keys, mouse = bk + uk, bm + um
    keys.sort(key=lambda s: float(s.split(':')[0]))
    shots = sorted(us + [t0 / 1000.0 + s for s in opt['shots']])
    if len(shots) > 16:
        die('at most 16 screenshots per run (an emu816 limit)')
    if 'seconds' in opt:
        secs = t0 / 1000.0 + float(opt['seconds'])
    else:
        secs = inputscript.end_time(uk, um, shots) / 1000.0 + 2.0
        secs = max(secs, t0 / 1000.0 + 3.0)

    cmdl = [emu, '--sd', card, '--max-seconds', f'{secs:g}']
    if not opt.get('window'):
        cmdl.append('--headless')
    if opt.get('rev'):
        cmdl += ['--rev', opt['rev']]
    if opt.get('log-sound'):
        cmdl.append('--log-sound')
    if opt.get('log-sound-us'):
        cmdl.append('--log-sound-us')
    if opt.get('kbd-release'):
        cmdl += ['--kbd-release', opt['kbd-release']]
    if opt.get('log-lau'):
        cmdl.append('--log-lau')
    if opt.get('wav'):
        os.makedirs(os.path.dirname(os.path.abspath(opt['wav'])), exist_ok=True)
        cmdl += ['--wav', os.path.abspath(opt['wav'])]
    if opt.get('net'):
        cmdl.append('--net')
    if opt.get('prof'):
        cmdl += ['--prof', os.path.abspath(opt['prof'])]
        if opt.get('prof-from'):
            cmdl += ['--prof-from', f"{t0 / 1000.0 + float(opt['prof-from']):g}"]
        if opt.get('prof-to'):
            cmdl += ['--prof-to', f"{t0 / 1000.0 + float(opt['prof-to']):g}"]
    if opt.get('net-root'):
        if not os.path.isdir(opt['net-root']):
            die(f'--net-root {opt["net-root"]}: not a folder')
        cmdl += ['--net-root', os.path.abspath(opt['net-root'])]
    if keys:
        cmdl += ['--keys', ','.join(keys)]
    if mouse:
        cmdl += ['--mouse', ','.join(mouse)]
    ppms = []
    for n, s in enumerate(shots, 1):
        p = os.path.join(out, f'shot{n}.ppm')
        ppms.append(p)
        cmdl += ['--shot', p, '--shot-at', f'{s:g}']
    cmdl.append(os.path.join(card, 'SYSTEM', 'HORIZON.SYS'))
    with open(os.path.join(out, 'console.raw'), 'wb') as so, \
            open(os.path.join(out, 'emu.err'), 'wb') as se:
        r = subprocess.run(cmdl, stdout=so, stderr=se)
    raw = open(os.path.join(out, 'console.raw'), 'rb').read()
    con = strip_escapes(raw)
    open(os.path.join(out, 'console.txt'), 'w', encoding='latin-1').write(con)
    os.remove(os.path.join(out, 'console.raw'))

    pngs = []
    try:
        from PIL import Image
        for p in ppms:
            if os.path.exists(p):
                q = p[:-4] + '.png'
                Image.open(p).save(q)
                os.remove(p)
                pngs.append(q)
    except ImportError:
        pngs = [p for p in ppms if os.path.exists(p)]

    ok = True
    print(f'run816: {name} at {dest}, started at {t0 / 1000:g} s, ran to {secs:g} s '
          f'(emu816 exit {r.returncode}; 3 = time limit, the normal end)')
    for p in pngs:
        print(f'  {p}')
    print(f'  {os.path.join(out, "console.txt")}')
    if r.returncode not in (0, 3):
        print('run816: emu816 failed:', open(os.path.join(out, 'emu.err')).read()[-500:])
        ok = False
    for ln in con.splitlines():
        if '[kill]' in ln:
            print(f'run816: CRASH: {ln.strip()}  (ABI.md, "Faults"; docs/reference/program.md)')
            ok = False
    err = open(os.path.join(out, 'emu.err'), encoding='latin-1').read()
    if 'emu816: blitter:' in err:
        print('run816: emu816 reported a blitter rule broken (see emu.err)')
        ok = False
    for e in opt['expect']:
        if e not in con:
            print(f'run816: expected text not on the console: {e!r}')
            ok = False
    if ok and opt['expect']:
        print(f'run816: PASS ({len(opt["expect"])} expected texts found)')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
