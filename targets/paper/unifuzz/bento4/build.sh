#!/bin/bash
# UNIFUZZ bento4 (paper: Bento4-1.5.1-628; latest: v1.6.0-641), built as unibench_build's
# afl/Dockerfile does (`cmake . && make`), three ways: .afl (AFL++), .cmp (CmpLog), .asan (AddressSanitizer).
# Usage (inside builder-unifuzz.sif; targets/paper/build-paper.sh runs it): build.sh paper|latest OUT
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/../../common/lib.sh"
V=${1:?paper|latest}; mkdir -p "$2"; OUT=$(cd "$2" && pwd)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
SRC=$(paper_fetch mp42aac "$V" "$W/src")
# the unibench archive may nest the source one level down
if [ ! -f "$SRC/CMakeLists.txt" ]; then
    for d in "$SRC"/*/; do
        if [ -f "${d}CMakeLists.txt" ]; then SRC="${d%/}"; break; fi
    done
fi
[ -f "$SRC/CMakeLists.txt" ] || paper_die "bento4: no CMakeLists.txt found under $SRC"

# build VARIANT TARGETS...: fresh copy of source, in-source cmake+make (as the reference), copy binaries to OUT
build() {
    local variant=$1; shift
    local targets=("$@")
    local src="$W/b-$variant"
    cp -r "$SRC" "$src"
    case $variant in
        asan)
            (cd "$src" && env CC=clang CXX=clang++ \
                CFLAGS="-g -O1 -fno-omit-frame-pointer -fsanitize=address" \
                CXXFLAGS="-g -O1 -fno-omit-frame-pointer -fsanitize=address" \
                cmake . && make -j)
            ;;
        cmp)
            (cd "$src" && env CC=afl-clang-fast CXX=afl-clang-fast++ AFL_LLVM_CMPLOG=1 \
                cmake . && make -j)
            ;;
        *)
            (cd "$src" && env CC=afl-clang-fast CXX=afl-clang-fast++ \
                cmake . && make -j)
            ;;
    esac
    for t in "${targets[@]}"; do
        local bin
        bin=$(find "$src" -name "$t" -type f -executable | head -1)
        [ -n "$bin" ] || paper_die "bento4: $t binary not found after $variant build in $src"
        cp "$bin" "$OUT/$t.$variant"
    done
}

if [ "$V" = "paper" ]; then
    build afl mp42aac
    build cmp mp42aac
    build asan mp42aac
    paper_finish "$OUT" mp42aac "$V"
else
    build afl mp42aac mp42avc mp42hevc
    build cmp mp42aac mp42avc mp42hevc
    build asan mp42aac mp42avc mp42hevc
    paper_finish "$OUT" mp42aac "$V"
    paper_finish "$OUT" mp42avc "$V"
    paper_finish "$OUT" mp42hevc "$V"
fi
