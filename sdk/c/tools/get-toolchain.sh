#!/bin/sh
# get-toolchain.sh - install the vbcc 65816 C toolchain into sdk/c/toolchain/ (not committed).
#
#   sdk/c/tools/get-toolchain.sh               download (or reuse) and install
#   sdk/c/tools/get-toolchain.sh --dl DIR      take the downloads from DIR if they are there
#                                              (e.g. a copy made on another machine)
#   sdk/c/tools/get-toolchain.sh --source      also build the compiler from the current
#                                              source snapshot (needs gcc and make)
#   sdk/c/tools/get-toolchain.sh --force       install again even if already installed
#
# What it installs: "vbcc for 65816 Release 2" (2025-10-22) by Volker Barthelmann (compiler
# vbcc65816, frontend vc, assembler vasm6502_oldstyle, linker vlink, vobjdump, the C library
# for the 65816 simulator target, its headers). The archive is used as it is: vbcc may be
# redistributed only unmodified, so the SDK downloads it instead of shipping it. vbcc is free
# for non-commercial use; see sdk/docs/c/getting-started.md and the vbcc manual (vbcc.pdf in
# toolchain/dist/).
#
# The binaries in the archive are for Linux x86-64 (statically linked) and Windows.
# Host: Linux x86-64 (or WSL), sh, curl or wget, unzip, sha256sum (or shasum).
#
# Running it again does nothing when the same version is installed (prints so). Downloads
# are kept in toolchain/dl and checked against fixed SHA-256 sums before use.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)              # sdk/c
T="$ROOT/toolchain"
VERSION="vbcc65816_r2"

R2_URL="http://www.ibaug.de/vbcc/vbcc65816_r2.zip"
R2_SUM="e8950454d55327e50f6a5f98dc22ac020ee3d6084a17c92d37e088d3c63a922c"
SRC_URL="http://www.ibaug.de/vbcc/vbcc.tar.gz"
SRC_SUM="67e221062b50fb590613487ec2948a00db80552e061bbe348e6eaed5b33f0af8"   # snapshot 2026-01-10

DL=""
SOURCE=0
FORCE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --dl) [ $# -ge 2 ] || { echo "get-toolchain: --dl needs a folder" >&2; exit 2; }
              DL="$2"; shift 2 ;;
        --source) SOURCE=1; shift ;;
        --force) FORCE=1; shift ;;
        -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
        *) echo "get-toolchain: unknown argument $1 (see --help)" >&2; exit 2 ;;
    esac
done

die() { echo "get-toolchain: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "this needs '$1' ($2)"; }

case "$(uname -s)-$(uname -m)" in
    Linux-x86_64|Linux-amd64) ;;
    *) die "the vbcc 65816 binaries are for Linux x86-64 (this is $(uname -s) $(uname -m)).
On Windows use WSL; on other systems a Linux x86-64 machine or container." ;;
esac
need unzip "apt install unzip"
if command -v sha256sum >/dev/null 2>&1; then SHA="sha256sum"
elif command -v shasum >/dev/null 2>&1; then SHA="shasum -a 256"
else die "this needs sha256sum or shasum"; fi
if command -v curl >/dev/null 2>&1; then FETCH="curl -fsSL -o"
elif command -v wget >/dev/null 2>&1; then FETCH="wget -q -O"
else die "this needs curl or wget"; fi

STAMP="$VERSION"
[ $SOURCE = 1 ] && STAMP="$VERSION+source"
if [ $FORCE = 0 ] && [ -f "$T/vbcc/.installed" ] && [ "$(cat "$T/vbcc/.installed")" = "$STAMP" ] \
   && [ -x "$T/vbcc/bin/vbcc65816" ]; then
    echo "get-toolchain: $STAMP is already installed in $T/vbcc (--force installs it again)"
    exit 0
fi

mkdir -p "$T/dl"

# fetch NAME URL SUM: toolchain/dl/NAME, from --dl, else downloaded; checked
fetch() {
    name=$1; url=$2; sum=$3; f="$T/dl/$name"
    if [ ! -f "$f" ] && [ -n "$DL" ] && [ -f "$DL/$name" ]; then
        echo "get-toolchain: taking $name from $DL"
        cp "$DL/$name" "$f.part" && mv "$f.part" "$f"
    fi
    if [ -f "$f" ]; then
        got=$($SHA "$f" | cut -d' ' -f1)
        if [ "$got" != "$sum" ]; then
            echo "get-toolchain: $f has the wrong checksum ($got); downloading it again" >&2
            rm -f "$f"
        fi
    fi
    if [ ! -f "$f" ]; then
        echo "get-toolchain: downloading $url"
        $FETCH "$f.part" "$url" || { rm -f "$f.part"; die "download failed: $url
(no network? put $name into $T/dl by hand, or use --dl DIR)"; }
        mv "$f.part" "$f"
        got=$($SHA "$f" | cut -d' ' -f1)
        if [ "$got" != "$sum" ]; then
            mv "$f" "$f.bad"
            die "$name: checksum $got, expected $sum.
The file on the server has changed (kept as $f.bad). The SDK was tested with the file of
that checksum; check the vbcc page (http://www.compilers.de/vbcc.html) and update the sum
in this script only after testing (make -C sdk/c test)."
        fi
    fi
    echo "get-toolchain: $name OK (sha256 $sum)"
}

fetch vbcc65816_r2.zip "$R2_URL" "$R2_SUM"
[ $SOURCE = 1 ] && fetch vbcc.tar.gz "$SRC_URL" "$SRC_SUM"

rm -rf "$T/dist" "$T/vbcc.new" "$T/src"
mkdir -p "$T/dist"
unzip -q "$T/dl/vbcc65816_r2.zip" -d "$T/dist" || die "unzip failed"
D="$T/dist/vbcc65816/vbcc65816_linux/vbcc"
[ -x "$D/bin/vbcc65816" ] || die "the archive has no vbcc65816_linux/vbcc/bin/vbcc65816"
mkdir -p "$T/vbcc.new"
cp -r "$D/bin" "$D/config" "$D/targets" "$T/vbcc.new/"

if [ $SOURCE = 1 ]; then
    need gcc "a C compiler for the host"
    need make "GNU make"
    mkdir -p "$T/src"
    tar xzf "$T/dl/vbcc.tar.gz" -C "$T/src" || die "cannot unpack vbcc.tar.gz"
    mkdir -p "$T/src/vbcc/bin" "$T/src/vbcc/objects/65816"
    echo "get-toolchain: building vbcc65816 and vc from source (log: $T/src/build.log)"
    # dtgen asks about the host's types: the defaults (empty answers) are right on x86-64
    (cd "$T/src/vbcc" && yes '' | make TARGET=65816 bin/vbcc65816 bin/vc) \
        >"$T/src/build.log" 2>&1 || die "the build failed: see $T/src/build.log"
    cp "$T/src/vbcc/bin/vbcc65816" "$T/src/vbcc/bin/vc" "$T/vbcc.new/bin/"
fi

"$T/vbcc.new/bin/vbcc65816" 2>&1 | grep -q "No input file" \
    || die "$T/vbcc.new/bin/vbcc65816 does not run on this machine"
"$T/vbcc.new/bin/vasm6502_oldstyle" -v 2>/dev/null | grep -q vasm \
    || die "$T/vbcc.new/bin/vasm6502_oldstyle does not run on this machine"
echo "$STAMP" > "$T/vbcc.new/.installed"
rm -rf "$T/vbcc"
mv "$T/vbcc.new" "$T/vbcc"
echo "get-toolchain: installed $STAMP in $T/vbcc"
echo "get-toolchain: hcc (sdk/c/bin/hcc) finds it there; nothing to add to PATH"
