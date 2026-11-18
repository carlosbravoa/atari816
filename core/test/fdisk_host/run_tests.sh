#!/bin/bash
# SPDX-License-Identifier: CC-BY-NC-SA-4.0 OR GPL-3.0-or-later
# Copyright (c) 2026 Carlos Bravo
# The folder disk (core/firmware/fdisk.c) on the PC: the firmware's code and FatFs on a fresh
# FAT image, a model of Atari DOS 2.0S on the other side (harness.c); then fsck.fat must find
# the image clean. Needs gcc, mkfs.vfat and fsck.fat (dosfstools).
set -u
cd "$(dirname "$0")"
MKFS=${MKFS:-/usr/sbin/mkfs.vfat}
FSCK=${FSCK:-/usr/sbin/fsck.fat}
FW=../../firmware
gcc -O1 -g -Wall -Wno-unused-function -DHOST_FATFS_TEST -DFD_HOST -iquote $FW -I$FW/fatfs \
    -o fdisk_host harness.c $FW/fdisk.c diskio_host.c $FW/fatfs/ff.c $FW/fatfs/ffunicode.c || exit 1
img=fdisk_test.img
rm -f $img; truncate -s 16M $img; $MKFS $img > /dev/null || exit 1
./fdisk_host $img; rc=$?
if $FSCK -n $img > fsck.out 2>&1; then echo "PASS fsck: the image is clean"; else echo "FAIL fsck"; cat fsck.out; rc=1; fi
rm -f $img fsck.out
exit $rc
