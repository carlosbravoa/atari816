#!/bin/sh
# get-toolchain.sh - download and build the vbcc 65816 toolchain into toolchain/vbcc
# (not committed). Run from sdk/c-spike/vbcc. Needs curl, unzip, gcc, make.
#
#   vbcc (compiler + vc frontend): built from the source snapshot (2026-01-10).
#   vasm6502_oldstyle, vlink, vobjdump, the 65816-sim C library (libvc/libvcs, startup,
#   headers): taken from "vbcc for 65816 Release 2" (2025-10-22): vasm/vlink sources with
#   65816 support were not downloadable (sun.hasenbraten.de was "under maintenance"; the
#   vasm.tar.gz on ibaug.de is from 2020 and has no 65816), and vclib has no public source.
# Both archives are linked from http://www.compilers.de/vbcc.html (hosted on ibaug.de).
set -e
T=toolchain
mkdir -p $T/dl
cd $T/dl
[ -f vbcc.tar.gz ]         || curl -fsSL -o vbcc.tar.gz http://www.ibaug.de/vbcc/vbcc.tar.gz
[ -f vbcc65816_r2.zip ]    || curl -fsSL -o vbcc65816_r2.zip http://www.ibaug.de/vbcc/vbcc65816_r2.zip
sha256sum -c <<'EOF'
67e221062b50fb590613487ec2948a00db80552e061bbe348e6eaed5b33f0af8  vbcc.tar.gz
e8950454d55327e50f6a5f98dc22ac020ee3d6084a17c92d37e088d3c63a922c  vbcc65816_r2.zip
EOF
cd ..
rm -rf src dist vbcc
mkdir -p src dist vbcc/bin
tar xzf dl/vbcc.tar.gz -C src
unzip -q dl/vbcc65816_r2.zip -d dist
# build the compiler; dtgen asks about the host's types: the defaults (empty answers)
mkdir -p src/vbcc/bin src/vbcc/objects/65816
(cd src/vbcc && yes '' | make TARGET=65816 bin/vbcc65816 bin/vc)
D=dist/vbcc65816/vbcc65816_linux/vbcc
cp src/vbcc/bin/vbcc65816 src/vbcc/bin/vc vbcc/bin/
cp $D/bin/vasm6502_oldstyle $D/bin/vlink $D/bin/vobjdump vbcc/bin/
cp -r $D/config $D/targets vbcc/
echo "toolchain ready: $(pwd)/vbcc (the Makefile sets VBCC and PATH itself)"
