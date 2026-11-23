#!/bin/sh
# emu816 acceptance tests (run by `make test` from the emu directory).
cd "$(dirname "$0")/.." || exit 1
# EMUFLAGS="--rev 7" (or 8): the same tests on an older board; tests of missing hardware are skipped
EMU="./emu816 --headless $EMUFLAGS"
REVN=$(printf '%s\n' "$EMUFLAGS" | sed -n 's/.*--rev *\([0-9xXa-fA-F]*\).*/\1/p')
[ -n "$REVN" ] || REVN=$(sed -n 's/^#define SYS_REV_VAL *\(0x[0-9A-Fa-f]*\).*/\1/p' sysblock.h)
REVN=$((REVN))
REV=$(printf '%02X' $REVN)
skip() { echo "SKIP  $1"; }
T=tests
pass=0
fail=0
ok()  { echo "PASS  $1"; pass=$((pass + 1)); }
bad() { echo "FAIL  $1"; [ -n "$2" ] && printf '%s\n' "$2" | sed 's/^/      /'; fail=$((fail + 1)); }
# the self tests come from core/sw/a816 when built there, else from the copies in tests/
SW=../core/sw/a816
A816=$T/A816.BIN; [ -f $SW/A816.BIN ] && A816=$SW/A816.BIN
BRINGUP1=$T/BRINGUP1.BIN; [ -f $SW/BRINGUP1.BIN ] && BRINGUP1=$SW/BRINGUP1.BIN
NVTEST=$T/NVTEST.BIN; [ -f $SW/NVTEST.BIN ] && NVTEST=$SW/NVTEST.BIN
BLITTEST=$T/BLITTEST.BIN; [ -f $SW/BLITTEST.BIN ] && BLITTEST=$SW/BLITTEST.BIN
BLITLIST=$T/BLITLIST.BIN; [ -f $SW/BLITLIST.BIN ] && BLITLIST=$SW/BLITLIST.BIN
SAMPLER=$T/SAMPLER.BIN; [ -f $SW/SAMPLER.BIN ] && SAMPLER=$SW/SAMPLER.BIN
SPRTEST=$T/SPRTEST.BIN; [ -f $SW/SPRTEST.BIN ] && SPRTEST=$SW/SPRTEST.BIN
OPLTEST=$T/OPLTEST.BIN; [ -f $SW/OPLTEST.BIN ] && OPLTEST=$SW/OPLTEST.BIN
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ── 1. self test (FREDDIE II, system block, mailbox). The SD directory holds A816.BIN. ──
mkdir "$TMP/sd"
cp $A816 "$TMP/sd/A816.BIN"
out=$($EMU --sd "$TMP/sd" --max-seconds 10 $A816)
rc=$?
exp="ATARI816 SELF TEST
REV $REV BANKS-1 7F
WPVEC OK
MODE OK
FAULTS OK
MEMORY OK
WINDOW OK
TIMER OK
REPEAT OK
PREEMPT OK
WDOG US 001E84xx OK
MAILBOX OK FILES 01
DONE"
got=$(printf '%s\n' "$out" | sed 's/^WDOG US 001E84[0-9A-F][0-9A-F] OK$/WDOG US 001E84xx OK/')
if [ $rc -eq 0 ] && [ "$got" = "$exp" ]; then ok "A816.BIN self test"; else bad "A816.BIN self test (rc $rc)" "$out"; fi
[ -e "$TMP/sd/A816TEST.TMP" ] && bad "A816.BIN left A816TEST.TMP behind"
# the same with a slow console (90 us per byte, DBG_STAT polled by the program)
out2=$($EMU --sd "$TMP/sd" --max-seconds 10 --console-us 90 $A816)
got2=$(printf '%s\n' "$out2" | sed 's/^WDOG US 001E84[0-9A-F][0-9A-F] OK$/WDOG US 001E84xx OK/')
[ "$got2" = "$got" ] && ok "A816.BIN self test with --console-us 90" || bad "A816.BIN with --console-us 90" "$out2"

# ── 2. bring-up 1: RAM test and cycle-exact benchmarks ──
out=$($EMU --max-seconds 12 $BRINGUP1)
line() { printf '%s\n' "$out" | grep "^$1" ; }
hexv() { printf '%d' "0x$(line "$1" | awk '{print $NF}')"; }
if [ "$(line ID)" = "ID 81 REV $REV BANKS-1 7F" ] && [ "$(line RAM)" = "RAM ERRORS 0000" ] && line DONE >/dev/null; then
    ok "BRINGUP1.BIN identity and RAM test"; else bad "BRINGUP1.BIN identity / RAM" "$out"; fi
# LOOP: 327,771 CPU cycles between the latches (identical to the RTL cycle by cycle) plus the
# memory model's SDRAM write stalls: $5948; the board printed $5947 (2026-11-17, REV $0B),
# the ideal count is $5943. READ and MVN (the classic machine running, Marga off): within 3 %
# of the board's $860F and $75D3 (ideal $7CF6 and $3E7B, with --ideal-timing).
[ "$(line LOOP)" = "LOOP US 00005948" ] && ok "LOOP US 00005948 (board 5947)" || bad "LOOP" "$(line LOOP)"
r=$(hexv READ); m=$(hexv MVN)
[ "$r" -ge $((0x860F * 97 / 100)) ] && [ "$r" -le $((0x860F * 103 / 100)) ] && ok "$(line READ) (board 860F)" || bad "READ" "$(line READ)"
[ "$m" -ge $((0x75D3 * 97 / 100)) ] && [ "$m" -le $((0x75D3 * 103 / 100)) ] && ok "$(line MVN) (board 75D3)" || bad "MVN" "$(line MVN)"

# ── 3. emulator test programs ──
cp -r $T/sdfix "$TMP/fix"
out=$($EMU --sd "$TMP/fix" --max-seconds 5 $T/asm/mbdemo.bin)
[ "$out" = "$(cat $T/expected/mbdemo.txt)" ] && ok "mbdemo (mailbox: open/read/load/readdir/stat/write/delete/errors)" || bad "mbdemo" "$out"
out=$($EMU --max-seconds 5 $T/asm/cpuirq.bin)
[ "$out" = "$(cat $T/expected/cpuirq.txt)" ] && ok "cpuirq (COP, BRK, MVN+IRQ, WAI, NMI edge)" || bad "cpuirq" "$out"
out=$($EMU --max-seconds 5 --shot "$TMP/nvc.ppm" $T/asm/nvcdemo.bin)
sum=$(md5sum < "$TMP/nvc.ppm" | cut -d' ' -f1)
# 3 frames = 49,976 us (60.03 Hz); the polling loop that reads it lands 1-3 us either side
[ "$(printf '%s\n' "$out" | sed 's/^3 FRAMES US C33[3-9] OK$/3 FRAMES US C33x OK/')" = "$(cat $T/expected/nvcdemo.txt)" ] && ok "nvcdemo (VBLANK timing)" || bad "nvcdemo" "$out"
if [ $REVN -lt 8 ]; then skip "nvcdemo picture (needs the blitter)"
else [ "$sum" = "$(cat $T/expected/nvcdemo.ppm.md5)" ] && ok "nvcdemo picture (palette, blitter, pointer)" || bad "nvcdemo picture md5 $sum"; fi
for m in 1 2; do
    out=$($EMU --max-seconds 5 --shot "$TMP/m$m.ppm" $T/asm/nvcmode$m.bin)
    sum=$(md5sum < "$TMP/m$m.ppm" | cut -d' ' -f1)
    [ $REVN -lt 8 ] && sum=$(cat $T/expected/nvcmode$m.ppm.md5)       # (pictures need the blitter)
    if [ "$out" = "$(cat $T/expected/nvcmodes.txt)" ] && [ "$sum" = "$(cat $T/expected/nvcmode$m.ppm.md5)" ]; then
        ok "nvcmode$m (mode $m picture, LINE interrupt, BASE_PENDING)"; else bad "nvcmode$m md5 $sum" "$out"; fi
done

# NVTEST.BIN (core/sw/a816, the hardware test of Marga): pictures in mode 0 with the pointer,
# mode 1 (4 bpp) and mode 2 (264x180); see tests/pictures/nvtest_*.png
# (--ideal-timing: the pictures are Marga's, taken at fixed times while the CPU sets them up)
out=$($EMU --ideal-timing --max-seconds 40 --shot "$TMP/na.ppm" --shot-at 1.5 --shot "$TMP/nb.ppm" --shot-at 24 \
      --shot "$TMP/nc.ppm" --shot-at 29 $NVTEST)
pics=ok
for f in a b c; do
    [ "$(md5sum < "$TMP/n$f.ppm" | cut -d' ' -f1)" = "$(cat $T/expected/nvtest_$f.ppm.md5)" ] || pics="picture $f differs"
done
[ "$out" = "$(cat $T/expected/nvtest.txt)" ] && [ "$pics" = ok ] && ok "NVTEST.BIN (3 modes, pointer, LATE 00)" || bad "NVTEST.BIN: $pics" "$out"

# ── blitter (REV $08): every op against a 65C816 reference; command lists and raster events (REV $09) ──
if [ $REVN -ge 8 ]; then
    out=$($EMU --max-seconds 30 $BLITTEST 2>/dev/null)
    printf '%s\n' "$out" | grep -qx "BLITTER PASS" && ok "BLITTEST.BIN (every blitter op)" || bad "BLITTEST.BIN" "$out"
else skip "BLITTEST.BIN (no blitter)"; fi
if [ $REVN -ge 9 ]; then
    out=$($EMU --max-seconds 20 $BLITLIST 2>/dev/null)
    if printf '%s\n' "$out" | grep -qx "BLITLIST PASS" && printf '%s\n' "$out" | grep -qx "FRAMES 3C US 000F4050"; then
        ok "BLITLIST.BIN (lists, abort, WAIT_VBL, raster events: 60 frames 999,504 us)"; else bad "BLITLIST.BIN" "$out"; fi
else skip "BLITLIST.BIN (REV 09)"; fi
if [ $REVN -ge 10 ]; then
    out=$($EMU --max-seconds 20 $SAMPLER 2>/dev/null)
    printf '%s\n' "$out" | grep -qx "SAMPLER PASS" && ok "SAMPLER.BIN (sample player: rate, end interrupt, loop, mix, AU_LATE 0)" || bad "SAMPLER.BIN" "$out"
else skip "SAMPLER.BIN (REV 0A)"; fi

# ── Marga REV $0B: sprites and fine scrolling. SPRTEST is the hardware self test; the scenes
# (core/sw/a816/sprscene.s, SEED 1-10: all modes, scrolling, wrap, split, pointer, 16 random
# sprites) must give exactly the frame the RTL simulation gave (expected/sprsceneN.ppm.md5) ──
if [ $REVN -ge 11 ]; then
    out=$($EMU --max-seconds 30 $SPRTEST 2>/dev/null)
    printf '%s\n' "$out" | grep -qx "SPRTEST PASS" && ok "SPRTEST.BIN (registers, PEEK, COMMIT latching, line limit, load)" || bad "SPRTEST.BIN" "$out"
    bad_sc=""
    for n in 1 2 3 4 5 6 7 8 9 10; do
        $EMU --max-seconds 5 --shot "$TMP/sc.ppm" $T/sprscene$n.bin >/dev/null 2>&1
        [ "$(md5sum < "$TMP/sc.ppm" | cut -d' ' -f1)" = "$(cat $T/expected/sprscene$n.ppm.md5)" ] || bad_sc="$bad_sc $n"
    done
    [ -z "$bad_sc" ] && ok "sprscene 1-10 (sprites, scrolling, split: identical to the RTL's frames)" || bad "sprscene pictures differ:$bad_sc"
else skip "SPRTEST.BIN and the sprite scenes (REV 0B)"; fi

# ── OPL2 REV $0C. OPLTEST is the hardware self test: STAT, TIMER and TONE (OPL_OUT, $DB32/$DB33,
# swings both ways while a note plays: the sound of Nuked OPL3, nuked-opl3/) must pass.
# tests/asm/opltimer: the timers' periods (A 1,285 us and B 5,140 us at
# $F0), a masked flag, IRQ_STATUS bit 5 waking WAI, a new value at the next overflow, a
# stopped timer; with --log-sound only $DB00 of its two frozen writes is taken (no DACs).
# tests/asm/opltone: a 440 Hz sine keyed on for 1 s and released, recorded with --wav
# (tests/oplwav.py: pitch, level, length, the release to silence), twice: the same bytes.
# Before REV $0C the same program records silence ──
if [ $REVN -ge 12 ]; then
    out=$($EMU --max-seconds 5 $OPLTEST 2>/dev/null)
    [ "$out" = "$(printf 'OPL2 TEST REV %s\nSTAT OK\nTIMER OK\nTONE OK\nOPL2 PASS\nDONE' "$REV")" ] \
        && ok "OPLTEST.BIN (status \$06, AdLib timer detection, AUDIO IRQ, a tone on OPL_OUT)" || bad "OPLTEST.BIN" "$out"
    out=$($EMU --max-seconds 5 --log-sound $T/asm/opltimer.bin 2>"$TMP/opl.err")
    if [ "$out" = "$(sed "s/REV 0C/REV $REV/" $T/expected/opltimer.txt)" ] && [ "$(cat "$TMP/opl.err")" = 'sound $DB00 = $12' ]; then
        ok "opltimer (timer periods, masks, AUDIO IRQ and WAI, reload, stop; no DACs)"; else bad "opltimer" "$out
$(cat "$TMP/opl.err")"; fi
    if command -v python3 >/dev/null 2>&1; then
        $EMU --max-seconds 5 --wav "$TMP/tone1.wav" $T/asm/opltone.bin >/dev/null 2>&1
        $EMU --max-seconds 5 --wav "$TMP/tone2.wav" $T/asm/opltone.bin >/dev/null 2>&1
        out=$(python3 $T/oplwav.py "$TMP/tone1.wav") && cmp -s "$TMP/tone1.wav" "$TMP/tone2.wav" \
            && ok "opltone (--wav: 440 Hz on the OPL2, its level, key-off to silence; the same bytes twice: $out)" \
            || bad "opltone" "$out"
    else skip "opltone (no python3)"; fi
else
    out=$($EMU --max-seconds 5 $OPLTEST 2>/dev/null)
    printf '%s\n' "$out" | grep -qx "STAT FAIL 00" && ok "OPLTEST.BIN before REV 0C: no OPL2 (status reads 00)" || bad "OPLTEST.BIN (no OPL2)" "$out"
    $EMU --max-seconds 5 --wav "$TMP/tone1.wav" $T/asm/opltone.bin >/dev/null 2>&1
    [ "$(tail -c +45 "$TMP/tone1.wav" | tr -d '\000' | wc -c)" -eq 0 ] && [ "$(stat -c %s "$TMP/tone1.wav")" -gt 300000 ] \
        && ok "opltone before REV 0C: --wav records silence" || bad "opltone before REV 0C: not silent"
fi

# ── fixed RTL issues (see README): the aborted COP stays in user mode, E-mode IRQ pushes B=0 ──
out=$($EMU --max-seconds 5 $T/asm/copabort.bin)
[ "$out" = "$(cat $T/expected/copabort.txt)" ] && ok "copabort (aborted COP: no supervisor entry, kernel memory intact)" || bad "copabort" "$out"
out=$($EMU --max-seconds 5 $T/asm/eirq.bin)
[ "$out" = "$(cat $T/expected/eirq.txt)" ] && ok "eirq (emulation-mode IRQ pushes B=0)" || bad "eirq" "$out"

out=$($EMU --max-seconds 5 $T/asm/nmihold.bin)
[ "$out" = "$(cat $T/expected/nmihold.txt)" ] && ok "nmihold (NMI held after a user-mode entry until FR_CTRL is written)" || bad "nmihold" "$out"

# ── mouse events (firmware algorithm): clamping with remainder, key events first, KB_ROUTE;
# (0.21) a click and a key tap within one poll are never merged: motion then press then release ──
out=$($EMU --max-seconds 5 --mouse "100:5:-3:0:0,150:300:-200:0:1,200:0:0:2:1,250:0:0:-1:0,400:4:0:0:0,400:0:0:0:1,400:0:0:0:0,600:50:50:0:3,800:1:1:0:0" \
      --keys "150:04:1,170:04:0,450:05:1,450:05:0" $T/asm/mousetest.bin)
[ "$out" = "$(cat $T/expected/mousetest.txt)" ] && ok "mousetest (MOUSE events, clamp, KB_ROUTE, a quick click and tap kept)" || bad "mousetest" "$out"

# ── keyboard events (firmware algorithm), F12 = KEY event + SYSTEM_KEY NMI ──
out=$($EMU --max-seconds 20 --keys "0:1E:1,100:04:1,150:04:0,200:E1:1,220:05:1,260:05:0,300:E1:0,400:45:1,450:45:0,500:04:1,501:05:1,502:06:1,503:07:1,504:08:1,600:04:0,600:05:0,600:06:0,600:07:0,600:08:0,700:1E:0" $T/asm/kbtest.bin)
[ "$out" = "$(cat $T/expected/kbtest.txt)" ] && ok "kbtest (KEY events, modifiers, 4-key limit, F12 NMI)" || bad "kbtest" "$out"

# ── script waits (--keys t:W:HEX, step marks t:M:): kbtest and mousetest print a line at
# once for each event. A line printed since the last mark counts for a wait, even when key
# events came after it (the key's release); a mark forgets the lines before it; one line
# ends one wait ──
hx() { printf '%s' "$1" | od -An -tx1 | tr -d ' \n'; }
W04=$(hx "KEY 04 00 01")
out=$($EMU --max-seconds 2 --keys "100:M:,100:04:1,150:04:0,151:W:$W04,300:05:1,350:05:0" $T/asm/kbtest.bin 2>"$TMP/w.err")
if printf '%s\n' "$out" | grep -q '^KEY 05 00 01$' && ! grep -q 'still waits' "$TMP/w.err"; then
    ok "wait met by a line printed before a later key event of its step (the key's release)"
else bad "wait after a key release" "$out$(cat "$TMP/w.err")"; fi
out=$($EMU --max-seconds 2 --keys "100:M:,100:04:1,150:04:0,151:W:$W04,152:W:$W04,300:05:1,350:05:0" $T/asm/kbtest.bin 2>"$TMP/w.err")
out2=$($EMU --max-seconds 2 --keys "100:M:,100:04:1,150:04:0,200:M:,201:W:$W04,300:05:1,350:05:0" $T/asm/kbtest.bin 2>"$TMP/w2.err")
if ! printf '%s\n' "$out$out2" | grep -q '^KEY 05' && grep -q 'still waits for "KEY 04 00 01"' "$TMP/w.err" && grep -q 'still waits' "$TMP/w2.err"; then
    ok "wait: one line ends one wait; a step mark forgets the lines before it"
else bad "wait: used-up line / step mark" "$out / $out2"; fi
# the same through the SDK's input scripts (sdk/tools/inputscript.py): "a" then "+0 wait"
# (the program answered while the key was still held); a click then "+0 wait" for the
# line of the button's release (the wait must not hold back the release, 80 ms later)
IS=../sdk/tools/inputscript.py
if [ -f $IS ] && command -v python3 >/dev/null; then
    printf '100 a\n+0 wait KEY 04 00 01\n+100 b\n' > "$TMP/a.script"
    out=$($EMU --max-seconds 2 --keys "$(python3 $IS "$TMP/a.script" --keys)" $T/asm/kbtest.bin 2>"$TMP/w.err")
    if printf '%s\n' "$out" | grep -q '^KEY 05 00 01$' && ! grep -q 'still waits' "$TMP/w.err"; then
        ok "inputscript: typed text, then +0 wait for the program's answer to it"
    else bad "inputscript: wait after typed text" "$out$(cat "$TMP/w.err")"; fi
    printf '100 click\n+0 wait MOUSE 00 00 00 00\n+50 a\n' > "$TMP/c.script"
    out=$($EMU --max-seconds 2 --keys "$(python3 $IS "$TMP/c.script" --keys)" \
          --mouse "$(python3 $IS "$TMP/c.script" --mouse)" $T/asm/mousetest.bin 2>"$TMP/w.err")
    if printf '%s\n' "$out" | grep -q '^MOUSE 00 00 00 00$' && printf '%s\n' "$out" | grep -q '^KEY 04 00 01$' && ! grep -q 'still waits' "$TMP/w.err"; then
        ok "inputscript: click, then +0 wait for the line of its release (the release is not held back)"
    else bad "inputscript: wait after a click" "$out$(cat "$TMP/w.err")"; fi
else skip "inputscript waits (no ../sdk/tools/inputscript.py or python3)"; fi

# ── the PC link's screenshot (core/tools/a816_screen.py, atari.py shot816) read from the
# RAM at exit (--dump-ram) must be emu816's own picture: the Desktop (with the pointer) and
# the text console, on Horizon's card when it is built (a full-screen program's scroll
# and split: shot816.py's example with Xargon) ──
HSD=../horizon/build/sd
if [ -f $HSD/SYSTEM/HORIZON.SYS ] && command -v python3 >/dev/null; then
    cp -r $HSD "$TMP/hsd"
    $EMU --sd "$TMP/hsd" --max-seconds 7 --mouse "6000:30:20:0:0" --dump-ram "$TMP/d.ram" \
         --shot "$TMP/d.ppm" "$TMP/hsd/SYSTEM/HORIZON.SYS" >/dev/null 2>&1
    out=$(python3 $T/shot816.py "$TMP/d.ram" "$TMP/d.ppm")
    touch "$TMP/hsd/SYSTEM/NODESK"
    $EMU --sd "$TMP/hsd" --max-seconds 5 --dump-ram "$TMP/t.ram" --shot "$TMP/t.ppm" \
         "$TMP/hsd/SYSTEM/HORIZON.SYS" >/dev/null 2>&1
    out2=$(python3 $T/shot816.py "$TMP/t.ram" "$TMP/t.ppm")
    case "$out$out2" in
        PASS*PASS*) ok "shot816: the PC tool's pictures of the Desktop and the text console are emu816's" ;;
        *) bad "shot816 (the PC tool's screenshot)" "$out
$out2" ;;
    esac
else skip "shot816 (no Horizon card in $HSD)"; fi

# ── the PC volume (PC link step 1, --pc-folder): /PC: paths, the "PC:" entry at the end of the
# card's root, STAT /PC: = the PC's clock (--pc-time), a file round trip, $89 for a RENAME
# between the volumes, confinement (.., a symlink out); absent: $87; a drop: $88 ──
pcfix() {
    rm -rf "$TMP/pc" "$TMP/outside"
    mkdir -p "$TMP/pc/sub" "$TMP/outside"
    printf 'Notes kept on the PC.\n' > "$TMP/pc/Notes.txt"
    printf 'deep data' > "$TMP/pc/sub/Deep.bin"
    echo hidden > "$TMP/pc/.hidden"
    ln -s ../outside "$TMP/pc/out"
}
PCT="--sd $TMP/fix --card-date 2025-12-25T10:30 --pc-time 2026-03-04T05:06 --max-seconds 15"
pcfix
out=$($EMU $PCT --pc-folder "$TMP/pc" $T/asm/pctest.bin 2>/dev/null)
if [ "$out" = "$(cat $T/expected/pctest.txt)" ] && [ "$(cat "$TMP/pc/Made/Moved.txt")" = "Written by pctest into the PC folder." ] \
   && [ -z "$(ls -A "$TMP/outside")" ]; then
    ok "pctest (the PC volume: root entry, clock, round trip, \$89, confinement)"; else bad "pctest" "$out"; fi
pcfix
out=$($EMU $PCT $T/asm/pctest.bin 2>/dev/null)
[ "$out" = "$(cat $T/expected/pctest-absent.txt)" ] && ok "pctest without --pc-folder (\$87, the root unchanged)" || bad "pctest absent" "$out"
pcfix
out=$($EMU $PCT --pc-folder "$TMP/pc" --pc-drop-at 1 --pc-back-at 1.5 $T/asm/pctest.bin 2>/dev/null)
[ "$out" = "$(cat $T/expected/pctest-drop.txt)" ] && ok "pctest with --pc-drop-at, --pc-back-at (\$88, a new session)" || bad "pctest drop" "$out"

# ── (0.21) slow transfers (--card-kbps, --pc-kbps): each answer after its time; KEY and MOUSE
# events keep coming while a request is in progress; a PC file opened with mode 2 appears only
# at CLOSE, and one cut off by --pc-drop-at ($88) leaves no trace (the older file as it was) ──
rm -rf "$TMP/ssd" "$TMP/spc"; mkdir -p "$TMP/ssd" "$TMP/spc"
head -c 32768 /dev/urandom > "$TMP/ssd/BIG.BIN"
printf 'old\n' > "$TMP/spc/Old.txt"
out=$($EMU --sd "$TMP/ssd" --pc-folder "$TMP/spc" --card-kbps 64:32 --pc-kbps 100:8 --pc-drop-at 3 --max-seconds 10 \
      --keys "300:04:1,320:04:0,400:05:1,400:05:0,2000:06:1,2000:06:0" \
      --mouse "450:10:-2:0:0,450:0:0:0:1,450:0:0:0:0,2100:3:3:0:0" $T/asm/slowtest.bin 2>/dev/null)
if [ "$out" = "$(cat $T/expected/slowtest.txt)" ] && [ "$(cat "$TMP/spc/Old.txt")" = "old" ] \
   && [ "$(cat "$TMP/spc/New.bin")" = "$(printf 'Sixteen bytes!\r')" ] && [ -z "$(ls -A "$TMP/spc/.atari816-partial")" ] \
   && [ "$(ls "$TMP/spc")" = "$(printf 'New.bin\nOld.txt')" ]; then
    ok "slowtest (slow card and PC, events during a request, mode 2 files: at CLOSE, none after a drop)"; else bad "slowtest" "$out"; fi

# ── the internet (PC link step 2): URL paths, stream handles 4-7, requests put aside (TAG),
# $E4 NET, link drops. Loopback only: tests/netserver.py runs an echo server on 127.0.0.1 at a
# free port (and names a closed one); the connection URLs are loaded at $0D:6000 / $0D:6080 ──
rm -rf "$TMP/w" "$TMP/nfix"; mkdir -p "$TMP/w/example.test/docs/sub"; cp -r $T/sdfix "$TMP/nfix"
printf 'Hello from the net root.\n' > "$TMP/w/example.test/hello.txt"
echo a > "$TMP/w/example.test/docs/a.txt"; echo b > "$TMP/w/example.test/docs/b.txt"
echo h > "$TMP/w/example.test/docs/.hidden"
head -c 8192 /dev/zero > "$TMP/w/example.test/big.bin"
out=$($EMU --sd "$TMP/nfix" --net-root "$TMP/w" --pc-kbps 16:16 --max-seconds 10 $T/asm/nettest1.bin 2>/dev/null)
[ "$out" = "$(cat $T/expected/nettest1.txt)" ] && ok "nettest 1 (Fetch: STAT then OPEN, READ to the end, 404, listing, \$8A/\$8B/\$87, a READ put aside, 18)" || bad "nettest 1" "$out"
if command -v python3 >/dev/null 2>&1; then
    python3 $T/netserver.py "$TMP/ports" </dev/null >/dev/null 2>&1 &
    SRV=$!
    trap 'kill $SRV 2>/dev/null; rm -rf "$TMP"' EXIT
    i=0; while [ ! -s "$TMP/ports" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
    read PORT CLOSED < "$TMP/ports"
    { printf 'tcp://127.0.0.1:%s' "$PORT"; head -c $((128 - ${#PORT} - 16)) /dev/zero
      printf 'tcp://127.0.0.1:%s' "$CLOSED"; head -c $((128 - ${#CLOSED} - 16)) /dev/zero; } > "$TMP/urls.bin"
    out=$($EMU --sd "$TMP/nfix" --net --max-seconds 10 --load "$TMP/urls.bin@0D:6000" $T/asm/nettest2.bin 2>/dev/null)
    [ "$out" = "$(cat $T/expected/nettest2.txt)" ] && ok "nettest 2 (Net: echo, \$E4, refused \$8D, TLS \$91, the end \$90)" || bad "nettest 2" "$out"
    out=$($EMU --sd "$TMP/nfix" --net --net-root "$TMP/w" --pc-kbps 1:1 --pc-drop-at 1.5 --max-seconds 10 \
          --load "$TMP/urls.bin@0D:6000" $T/asm/nettest3.bin 2>/dev/null)
    [ "$out" = "$(cat $T/expected/nettest3.txt)" ] && ok "nettest 3 (a link drop: \$E4, \$88 on streams and a READ put aside, \$87 after)" || bad "nettest 3" "$out"
    kill $SRV 2>/dev/null
else
    skip "nettest 2 and 3 (no python3 for the loopback server)"
fi

# ── 4. CPU: SingleStepTests/65816 sample (tests/fetch_sst.py downloads it) ──
if ls $T/sst/*.txt >/dev/null 2>&1; then
    res=$($T/cputest $T/sst/*.txt | tail -1)
    case "$res" in *" 0 failed"*" 0 with bus"*) ok "$res" ;; *) bad "$res" ;; esac
else
    echo "SKIP  SingleStepTests (run tests/fetch_sst.py first)"
fi

echo "$pass passed, $fail failed"
[ $fail -eq 0 ]
