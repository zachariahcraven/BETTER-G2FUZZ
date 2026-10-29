#!/bin/bash
# UNIFUZZ jhead (paper: jhead-3.00 from unibench; latest: the newest release tag), built as unibench_build's
# afl/Dockerfile does (`make`), three ways: .afl (AFL++), .cmp (CmpLog), .asan (AddressSanitizer).
# Usage (inside builder-unifuzz.sif; targets/paper/build-paper.sh runs it): build.sh paper|latest OUT
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/../../common/lib.sh"
V=${1:?paper|latest}; mkdir -p "$2"; OUT=$(cd "$2" && pwd)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
SRC=$(paper_fetch jhead "$V" "$W/src")
# build CC [VAR=value ...]: a clean jhead binary in $SRC. CC carries any extra flags, because jhead's
# Makefile sets CFLAGS itself.
build() { make -s -C "$SRC" clean >/dev/null 2>&1 || true; env "${@:2}" make -s -C "$SRC" CC="$1" >/dev/null; }
build afl-clang-fast && cp "$SRC/jhead" "$OUT/jhead.afl"
build afl-clang-fast AFL_LLVM_CMPLOG=1 && cp "$SRC/jhead" "$OUT/jhead.cmp"
# ASan (crash triage): plain clang with symbols and frame pointers, as the repo's other .asan builds
build "clang -g -O1 -fno-omit-frame-pointer -fsanitize=address" && cp "$SRC/jhead" "$OUT/jhead.asan"
paper_finish "$OUT" jhead "$V"
