#!/bin/sh
# tests/app.sh [HORIZON] - make test-app: MICROPOLIS.HZA installed with the Installer, the
# game started from the Desktop's Programs menu, a city saved in the app's folder, the app
# installed again (tests/app.script); then the card: the app's files, the saved city kept.
HZ=${1:-../../horizon}
cd "$(dirname "$0")/.." || exit 1
fail=0
ok() { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fail=1; }
python3 ../../sdk/tools/run816.py - --mode none --horizon "$HZ" --script tests/app.script \
  --file MICROPOLIS.HZA:/MICROPOLIS.HZA --seconds 200 --out build/apptest > build/apptest.log 2>&1 ||
  bad "run816 (build/apptest.log)"
A=build/apptest/card/APPS/MICROPOLIS
for f in APP.INF MICROPOL.PRG MICROPOL.GFX MICROPOL.ICN SNRO.555 CITIES/KOBE.CTY SND/EXPHI.WAV; do
  [ -f $A/$f ] || bad "installed: no $f in /APPS/MICROPOLIS"
done
cmp -s $A/MICROPOL.PRG MICROPOL.PRG && ok "installed by the Installer into /APPS/MICROPOLIS ($(ls $A | wc -l) entries)"
if grep -aq '^micropolis: ready' build/apptest/console.txt; then
  ok "Micropolis started from Programs > Games"
else bad "Micropolis did not start from the Desktop (build/apptest)"; fi
if [ -f $A/MYTOWN.CTY ] && [ "$(wc -c < $A/MYTOWN.CTY)" = 27120 ]; then
  ok "a city saved in the app's folder (MYTOWN.CTY, 27,120 bytes), kept by the update"
else bad "no MYTOWN.CTY in /APPS/MICROPOLIS after the update"; fi
grep -aq 'install: replaced' build/apptest/console.txt || bad "the second install did not replace the app"
[ -e build/apptest/card/APPS/.INSTALL ] && bad "the update left /APPS/.INSTALL behind"
[ $fail = 0 ] && echo "micropolis: APP TEST PASSED"
exit $fail
