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
[ "$out2" = "$out" ] && ok "A816.BIN self test with --console-us 90" || bad "A816.BIN with --console-us 90" "$out2"

# ── 2. bring-up 1: RAM test and cycle-exact benchmarks ──
out=$($EMU --max-seconds 12 $BRINGUP1)
line() { printf '%s\n' "$out" | grep "^$1" ; }
hexv() { printf '%d' "0x$(line "$1" | awk '{print $NF}')"; }
if [ "$(line ID)" = "ID 81 REV $REV BANKS-1 7F" ] && [ "$(line RAM)" = "RAM ERRORS 0000" ] && line DONE >/dev/null; then
    ok "BRINGUP1.BIN identity and RAM test"; else bad "BRINGUP1.BIN identity / RAM" "$out"; fi
# LOOP: the ideal cycle count gives $5943 (327,771 cycles between the latches, identical to
# the RTL cycle by cycle); hardware and the RTL testbench print $5948 because of 8 SDRAM
# write-through stalls inside the measured window, which the emulator does not model.
[ "$(line LOOP)" = "LOOP US 00005943" ] && ok "LOOP US 00005943 (ideal cycles)" || bad "LOOP" "$(line LOOP)"
r=$(hexv READ); m=$(hexv MVN)
[ "$r" -ge $((0x7CF6 * 99 / 100)) ] && [ "$r" -le $((0x7CF6 * 101 / 100)) ] && ok "$(line READ) (ideal ~7CF6)" || bad "READ" "$(line READ)"
[ "$m" -ge $((0x3E7B * 99 / 100)) ] && [ "$m" -le $((0x3E7B * 101 / 100)) ] && ok "$(line MVN) (ideal ~3E7B)" || bad "MVN" "$(line MVN)"

# ── 3. emulator test programs ──
cp -r $T/sdfix "$TMP/fix"
out=$($EMU --sd "$TMP/fix" --max-seconds 5 $T/asm/mbdemo.bin)
[ "$out" = "$(cat $T/expected/mbdemo.txt)" ] && ok "mbdemo (mailbox: open/read/load/readdir/stat/write/delete/errors)" || bad "mbdemo" "$out"
out=$($EMU --max-seconds 5 $T/asm/cpuirq.bin)
[ "$out" = "$(cat $T/expected/cpuirq.txt)" ] && ok "cpuirq (COP, BRK, MVN+IRQ, WAI, NMI edge)" || bad "cpuirq" "$out"
out=$($EMU --max-seconds 5 --shot "$TMP/nvc.ppm" $T/asm/nvcdemo.bin)
sum=$(md5sum < "$TMP/nvc.ppm" | cut -d' ' -f1)
[ "$out" = "$(cat $T/expected/nvcdemo.txt)" ] && ok "nvcdemo (VBLANK timing)" || bad "nvcdemo" "$out"
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
out=$($EMU --max-seconds 40 --shot "$TMP/na.ppm" --shot-at 1.5 --shot "$TMP/nb.ppm" --shot-at 24 \
      --shot "$TMP/nc.ppm" --shot-at 29 $NVTEST)
pics=ok
for f in a b c; do
    [ "$(md5sum < "$TMP/n$f.ppm" | cut -d' ' -f1)" = "$(cat $T/expected/nvtest_$f.ppm.md5)" ] || pics="picture $f differs"
done
[ "$out" = "$(cat $T/expected/nvtest.txt)" ] && [ $pics = ok ] && ok "NVTEST.BIN (3 modes, pointer, LATE 00)" || bad "NVTEST.BIN: $pics" "$out"

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

# ── fixed RTL issues (see README): the aborted COP stays in user mode, E-mode IRQ pushes B=0 ──
out=$($EMU --max-seconds 5 $T/asm/copabort.bin)
[ "$out" = "$(cat $T/expected/copabort.txt)" ] && ok "copabort (aborted COP: no supervisor entry, kernel memory intact)" || bad "copabort" "$out"
out=$($EMU --max-seconds 5 $T/asm/eirq.bin)
[ "$out" = "$(cat $T/expected/eirq.txt)" ] && ok "eirq (emulation-mode IRQ pushes B=0)" || bad "eirq" "$out"

out=$($EMU --max-seconds 5 $T/asm/nmihold.bin)
[ "$out" = "$(cat $T/expected/nmihold.txt)" ] && ok "nmihold (NMI held after a user-mode entry until FR_CTRL is written)" || bad "nmihold" "$out"

# ── mouse events (firmware algorithm): clamping with remainder, key events first, KB_ROUTE ──
out=$($EMU --max-seconds 5 --mouse "100:5:-3:0:0,150:300:-200:0:1,200:0:0:2:1,250:0:0:-1:0,600:50:50:0:3,800:1:1:0:0" --keys "150:04:1,170:04:0" $T/asm/mousetest.bin)
[ "$out" = "$(cat $T/expected/mousetest.txt)" ] && ok "mousetest (MOUSE events, clamp, KB_ROUTE)" || bad "mousetest" "$out"

# ── keyboard events (firmware algorithm), F12 = KEY event + SYSTEM_KEY NMI ──
out=$($EMU --max-seconds 20 --keys "0:1E:1,100:04:1,150:04:0,200:E1:1,220:05:1,260:05:0,300:E1:0,400:45:1,450:45:0,500:04:1,501:05:1,502:06:1,503:07:1,504:08:1,600:04:0,600:05:0,600:06:0,600:07:0,600:08:0,700:1E:0" $T/asm/kbtest.bin)
[ "$out" = "$(cat $T/expected/kbtest.txt)" ] && ok "kbtest (KEY events, modifiers, 4-key limit, F12 NMI)" || bad "kbtest" "$out"

# ── 4. CPU: SingleStepTests/65816 sample (tests/fetch_sst.py downloads it) ──
if ls $T/sst/*.txt >/dev/null 2>&1; then
    res=$($T/cputest $T/sst/*.txt | tail -1)
    case "$res" in *" 0 failed"*" 0 with bus"*) ok "$res" ;; *) bad "$res" ;; esac
else
    echo "SKIP  SingleStepTests (run tests/fetch_sst.py first)"
fi

echo "$pass passed, $fail failed"
[ $fail -eq 0 ]
