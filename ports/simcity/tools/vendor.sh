#!/bin/sh
# tools/vendor.sh UPSTREAM OUT - upstream's files the port takes, copied as they are (the
# pristine base of engine/, engine/FORK.md): UPSTREAM is a clone of
# https://github.com/SimHacker/micropolis at commit c98f6b08519887b450d9be198bfca5237aab6d0c
# (git -C UPSTREAM checkout c98f6b08519887b450d9be198bfca5237aab6d0c); OUT a new folder.
# Only files are copied: nothing of upstream's is built or run.
set -e
U=$1/micropolis-activity
O=$2
mkdir -p "$O/src/sim/headers" "$O/cities" "$O/res/sounds" "$O/images"
cp "$U/README" "$U/COPYING" "$O/"
cp "$1/MicropolisPublicNameLicense.md" "$O/"
for f in s_alloc s_disast s_eval s_fileio s_gen s_init s_msg s_power s_scan s_sim s_traf \
         s_zone rand g_ani g_smmaps w_sprite w_tool w_budget w_graph w_update w_util w_eval \
         w_con; do
  cp "$U/src/sim/$f.c" "$O/src/sim/"
done
for f in sim mac macros view animtab; do
  cp "$U/src/sim/headers/$f.h" "$O/src/sim/headers/"
done
cp "$U"/cities/*.cty "$O/cities/"
cp "$U"/res/snro.* "$U"/res/stri.* "$O/res/"
cp "$U"/res/sounds/*.wav "$O/res/sounds/"
cp "$U/images/tiles.xpm" "$U/images/tilessm.xpm" "$U"/images/obj*.xpm "$O/images/"
echo c98f6b08519887b450d9be198bfca5237aab6d0c > "$O/COMMIT"
