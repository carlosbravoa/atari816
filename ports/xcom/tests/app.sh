#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# tests/app.sh [HORIZON] - make test-app: XCOM.HZA (make app: no game data in it)
# installed with the Installer from the Desktop and started from Programs > Games, as a
# player would (tests/app1.script, app2.script):
#   1. without the game's data: the program's message on the screen, its end at a key;
#   2. with the packs (and an old save) already in /APPS/XCOM: the install keeps them, the
#      game starts from the menu (loading screen, start menu), a new game, a base, a save
#      in slot 2: XCOMXT2.SAV in the app's folder.
HZ=${1:-../../horizon}
cd "$(dirname "$0")/.." || exit 1
fail=0
ok() { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fail=1; }
O=build/apptest
rm -rf $O && mkdir -p $O

python3 ../../sdk/tools/run816.py - --mode none --horizon "$HZ" --script tests/app1.script \
  --file XCOM.HZA:/XCOM.HZA --out $O/nodata --seconds 120 >/dev/null 2>&1
A=$O/nodata/card/APPS/XCOM
okf=1
for f in APP.INF XCOM.PRG MUSD.PRG XCOM.ICN README.TXT; do
  [ -f $A/$f ] || { bad "installed: no $f in /APPS/XCOM"; okf=0; }
done
[ $okf = 1 ] && cmp -s $A/XCOM.PRG XCOM.PRG && ok "XCOM.HZA installed by the Installer into /APPS/XCOM (APP.INF, XCOM.PRG, MUSD.PRG, XCOM.ICN, README.TXT; $(ls $A | wc -l) files, no game data)"
c=$O/nodata/console.txt
if grep -aq "xcom: message: X-COM: the game's data is missing" $c && grep -aq "xcom: message: Press a key" $c; then
  ok "started from Programs > Games without the data: \"X-COM: the game's data is missing\" on its screen"
else bad "no data: no message (build/apptest/nodata)"; fi
grep -aq '\[kill\]' $c && bad "no data: $(grep -a '\[kill\]' $c)"

F=
for f in data/packs/*.PAK data/packs/PACKS.VER; do F="$F --file $f:/APPS/XCOM/$(basename $f)"; done
for f in data/packs/VGA/*; do F="$F --file $f:/APPS/XCOM/VGA/$(basename $f)"; done
printf 'an old save\n' > $O/OLD.SAV
python3 ../../sdk/tools/run816.py - --mode none --horizon "$HZ" --script tests/app2.script \
  --file XCOM.HZA:/XCOM.HZA $F --file $O/OLD.SAV:/APPS/XCOM/XCOMXT9.SAV --out $O/play \
  --seconds 200 >/dev/null 2>&1
A=$O/play/card/APPS/XCOM
c=$O/play/console.txt
if [ -f $A/XCOM.PRG ] && [ -f $A/VGA/UIV.PAK ] && [ -f $A/PACKS.VER ] && cmp -s $A/XCOMXT9.SAV $O/OLD.SAV; then
  ok "installed over the player's files: the packs and an old save kept"
else bad "install with the data: files lost (build/apptest/play/card/APPS/XCOM)"; fi
if grep -aq "xcom: ready for input" $c; then
  ok "the game started from the menu: $(grep -a 'xcom: ready for input' $c | head -1 | sed 's/^xcom: //')"
else bad "the game did not reach its start menu (build/apptest/play)"; fi
if [ -f $A/XCOMXT2.SAV ] && [ $(wc -c < $A/XCOMXT2.SAV) -gt 10000 ]; then
  ok "a new game, a base, saved in slot 2: /APPS/XCOM/XCOMXT2.SAV ($(wc -c < $A/XCOMXT2.SAV) bytes)"
else bad "no save in the app's folder (build/apptest/play)"; fi
grep -aq '\[kill\]' $c && bad "play: $(grep -a '\[kill\]' $c)"
[ -e $O/play/card/APPS/.INSTALL ] && bad "the install left /APPS/.INSTALL behind"
[ $fail = 0 ] && echo "xcom: APP TEST PASSED"
exit $fail
