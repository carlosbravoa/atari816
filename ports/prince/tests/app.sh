#!/bin/sh
# tests/app.sh [HORIZON] - make test-app: PRINCE.HZA installed with the Installer, the game
# started from the Desktop's Programs menu into level 1, a quicksave, the app updated with
# the same archive (tests/app.script), then checked: the app's folder on the card (APP.INF,
# the program, its data, its icon), the game reached level 1, QUICKSAVE.SAV in the app's
# folder and still there after the update (Replace keeps the user's files).
HZ=${1:-../../horizon}
cd "$(dirname "$0")/.." || exit 1
fail=0
ok() { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fail=1; }
python3 ../../sdk/tools/run816.py - --mode none --horizon "$HZ" --script tests/app.script \
  --file PRINCE.HZA:/PRINCE.HZA --out build/apptest >/dev/null 2>&1 || bad "run816 (build/apptest)"
A=build/apptest/card/APPS/PRINCE
okf=1
for f in APP.INF PRINCE.PRG POP.DAT POP.GFX POP.MSK POP.SND PRINCE.ICN; do
  [ -f $A/$f ] || { bad "installed: no $f in /APPS/PRINCE"; okf=0; }
done
[ $okf = 1 ] && cmp -s $A/PRINCE.PRG PRINCE.PRG && ok "installed by the Installer into /APPS/PRINCE (APP.INF, PRINCE.PRG, POP.*, PRINCE.ICN)"
c=build/apptest/console.txt
if grep -aq '^prince: level 1' $c && ! grep -aq '^prince: title' $c; then
  ok "Prince of Persia started from Programs > Games: Space on the first screen, level 1"
else bad "the game did not reach level 1 (build/apptest)"; fi
if grep -aq '^install: replaced /APPS/PRINCE' $c && [ -f $A/QUICKSAVE.SAV ]; then
  ok "updated with Replace; the quicksave (/APPS/PRINCE/QUICKSAVE.SAV) kept"
else bad "no update, or QUICKSAVE.SAV lost"; fi
[ -e build/apptest/card/APPS/.INSTALL ] && bad "the update left /APPS/.INSTALL behind"
[ $fail = 0 ] && echo "prince: APP TEST PASSED"
exit $fail
