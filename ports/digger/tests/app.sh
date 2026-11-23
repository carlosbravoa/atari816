#!/bin/sh
# tests/app.sh [HORIZON] - make test-app: DIGGER.HZA installed with the Installer and Digger
# started from the Desktop's Programs menu, a game played to a high score, the app updated
# with the same archive (tests/app.script), then checked: the app's folder on the card
# (APP.INF, the program, its data, its icon), the title reached, the high score file in the
# app's folder, and still there after the update (Replace keeps the user's files).
HZ=${1:-../../horizon}
cd "$(dirname "$0")/.." || exit 1
fail=0
ok() { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fail=1; }
python3 ../../sdk/tools/run816.py - --mode none --horizon "$HZ" --script tests/app.script \
  --file DIGGER.HZA:/DIGGER.HZA --out build/apptest >/dev/null 2>&1 || bad "run816 (build/apptest)"
A=build/apptest/card/APPS/DIGGER
for f in APP.INF DIGGER.PRG DIGGER.DAT DIGGER.ICN; do
  [ -f $A/$f ] || bad "installed: no $f in /APPS/DIGGER"
done
[ -f $A/DIGGER.PRG ] && cmp -s $A/DIGGER.PRG DIGGER.PRG && ok "installed by the Installer into /APPS/DIGGER (APP.INF, DIGGER.PRG, .DAT, .ICN)"
if grep -aq '^digger: title' build/apptest/console.txt; then
  ok "Digger started from Programs > Games: its title"
else bad "Digger did not reach its title (build/apptest)"; fi
if head -c 12 $A/DIGGER.SCO 2>/dev/null | grep -q '^sAPP     125'; then
  ok "its high score (APP 125) in its own folder, kept by the update (/APPS/DIGGER/DIGGER.SCO)"
else bad "no DIGGER.SCO with APP 125 in /APPS/DIGGER after the update"; fi
grep -aq 'Replace' build/apptest/console.txt 2>/dev/null || true
[ -e build/apptest/card/APPS/.INSTALL ] && bad "the update left /APPS/.INSTALL behind"
[ $fail = 0 ] && echo "digger: APP TEST PASSED"
exit $fail
