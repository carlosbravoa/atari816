#!/bin/bash
# SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
# Copyright (c) 2026 Carlos Bravo

CYAN='\033[36m'
NC='\033[0m'

# firmware is no longer separate
#echo -e "${CYAN}Flashing firmware from $(date -d "$(stat -c '%y' firmware/firmware.bin)" '+%B %d, %Y')${NC}"
#sudo openFPGALoader -b tangnano20k -f -o 0x500000 firmware/firmware.bin

# Another project's board on the same PC must never be flashed: its debugger's serial numbers
# are listed in ~/.config/atari816/not-my-boards (one a line; tools/pclink.py reads it too).
# With exactly one board connected that is not in the list, that board is flashed by its serial.
SKIP=~/.config/atari816/not-my-boards
MINE=""
for d in /sys/bus/usb/devices/*; do
    [ -f "$d/idVendor" ] && [ "$(cat "$d/idVendor")" = 0403 ] || continue
    s=$(cat "$d/serial" 2>/dev/null)
    [ -f "$SKIP" ] && grep -qx "$s" <(sed 's/#.*//; s/[[:space:]]//g' "$SKIP") && { echo "skipping board $s (not an Atari816)"; continue; }
    MINE="$MINE $s"
done
set -- $MINE
[ $# = 1 ] || { echo "flash_it: expected exactly one Atari816 board, found $#:$MINE"; exit 1; }
export OPENFPGALOADER_FTDI_SERIAL="$1"
FTDI="--ftdi-serial $1"

echo -e "${CYAN}Flashing Bitstream from $(date -d "$(stat -c '%y' impl/atari800_tn20k/impl/pnr/atari800_tn20k.fs)" '+%B %d, %Y - %T')${NC}"
# Atari816 branch: the firmware is split. The cold part lives in SPI flash at 0x500000 and
# must match the bitstream it was built with (the boot loader checks its CRC).
openFPGALoader -b tangnano20k $FTDI -f -o 0x500000 firmware/cold.bin
openFPGALoader -b tangnano20k $FTDI -f impl/atari800_tn20k/impl/pnr/atari800_tn20k.fs
