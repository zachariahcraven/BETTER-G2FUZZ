#!/bin/bash
# jhead (JPEG/EXIF), from the G2Fuzz paper's target list -> OUT/jhead.{afl,cmp,asan}, OUT/seeds/jhead/
# Runs inside the g2fuzz image (the Dockerfile calls it). Usage: build.sh OUT
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); mkdir -p "$1"; OUT=$(cd "$1" && pwd)
COMMIT=5007491cdc8c727c16ea6a27734535cfd0ed4349
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
git clone -q https://github.com/Matthias-Wandel/jhead "$W/jhead" && cd "$W/jhead" && git checkout -q $COMMIT
make CC=afl-clang-fast && cp jhead "$OUT/jhead.afl"
make clean && AFL_LLVM_CMPLOG=1 make CC=afl-clang-fast && cp jhead "$OUT/jhead.cmp"
# ASan: -O0 on every file (command-line CFLAGS override the Makefile's)
make -s clean || true; rm -f ./*.o jhead
make -s CC=clang CFLAGS="-g -O0 -fno-omit-frame-pointer -fsanitize=address" LDFLAGS="-fsanitize=address"
cp jhead "$OUT/jhead.asan"
mkdir -p "$OUT/seeds/jhead" && cp "$HERE"/seeds/* "$OUT/seeds/jhead/"
afl-showmap -q -o "$W/map" -- "$OUT/jhead.afl" "$HERE/seeds/not_kitty.jpg" && test -s "$W/map"
