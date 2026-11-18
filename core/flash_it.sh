#!/bin/bash
# SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
# Copyright (c) 2026 Carlos Bravo

CYAN='\033[36m'
NC='\033[0m'

# firmware is no longer separate
#echo -e "${CYAN}Flashing firmware from $(date -d "$(stat -c '%y' firmware/firmware.bin)" '+%B %d, %Y')${NC}"
#sudo openFPGALoader -b tangnano20k -f -o 0x500000 firmware/firmware.bin

echo -e "${CYAN}Flashing Bitstream from $(date -d "$(stat -c '%y' impl/atari800_tn20k/impl/pnr/atari800_tn20k.fs)" '+%B %d, %Y - %T')${NC}"
# Atari816 branch: the firmware is split. The cold part lives in SPI flash at 0x500000 and
# must match the bitstream it was built with (the boot loader checks its CRC).
openFPGALoader -b tangnano20k -f -o 0x500000 firmware/cold.bin
openFPGALoader -b tangnano20k -f impl/atari800_tn20k/impl/pnr/atari800_tn20k.fs
