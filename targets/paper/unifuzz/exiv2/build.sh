#!/bin/bash
# UNIFUZZ exiv2 (paper: exiv2-0.26 from unibench; latest: v0.28.9), built as unibench_build's
# afl/Dockerfile does (`cmake -DEXIV2_ENABLE_SHARED=OFF . && make`), three ways: .afl (AFL++),
# .cmp (CmpLog), .asan (AddressSanitizer).
# Usage (inside builder-unifuzz.sif; targets/paper/build-paper.sh runs it): build.sh paper|latest OUT
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/../../common/lib.sh"
V=${1:?paper|latest}; mkdir -p "$2"; OUT=$(cd "$2" && pwd)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
SRC=$(paper_fetch exiv2 "$V" "$W/src")
SRC=$(cd "$SRC" && pwd)
[ -f "$SRC/CMakeLists.txt" ] || paper_die "exiv2: $SRC has no CMakeLists.txt"

AFL_CC=$(command -v afl-clang-fast) || paper_die "exiv2: afl-clang-fast not found"
AFL_CXX=$(command -v afl-clang-fast++) || paper_die "exiv2: afl-clang-fast++ not found"
CLANG=$(command -v clang) || paper_die "exiv2: clang not found"
CLANGXX=$(command -v clang++) || paper_die "exiv2: clang++ not found"

# CMake options for the exiv2 tool.  paper follows the reference block exactly.  latest (v0.28.9)
# renamed the shared-library option and added optional features/dependencies absent from 0.26; use
# the documented equivalent and disable those options so the build keeps the 0.26 feature set.
case $V in
  # -DSTRERROR_R_CHAR_P=1: clang 16 rejects the C snippet exiv2 0.26 uses to detect the
  # char*-returning strerror_r (int-conversion error), so the check fails and futils.cpp
  # declares the wrong (int-returning) prototype.  Preset the cached result to what the
  # reference gcc produced (review1 2026-10-23: no source edits).
  paper) OPTS=(-DEXIV2_ENABLE_SHARED=OFF -DSTRERROR_R_CHAR_P=1) ;;
  latest) OPTS=(-DBUILD_SHARED_LIBS=OFF
                -DEXIV2_BUILD_TOOLS=ON
                -DEXIV2_ENABLE_XMP=ON
                -DEXIV2_ENABLE_EXIF=ON
                -DEXIV2_ENABLE_IPTC=ON
                -DEXIV2_ENABLE_COMMENT=ON
                -DEXIV2_ENABLE_MPOL=ON
                -DEXIV2_ENABLE_WEBREADY=OFF
                -DEXIV2_ENABLE_BMFF=OFF
                -DEXIV2_ENABLE_NLS=OFF
                -DEXIV2_ENABLE_INIH=OFF
                -DEXIV2_ENABLE_BROTLI=OFF
                -DEXIV2_ENABLE_CURL=OFF
                -DEXIV2_BUILD_TEST=OFF
                -DEXIV2_BUILD_SAMPLES=OFF
                -DEXIV2_BUILD_DOCS=OFF) ;;
  *) paper_die "exiv2: bad version $V" ;;
esac

# build_variant VARIANT: one clean out-of-tree build of the exiv2 tool; copies it to OUT/exiv2.VARIANT.
build_variant() {
  local variant=$1 bin
  local build="$W/build-$variant"
  case $variant in
    afl)
      cmake -S "$SRC" -B "$build" -DCMAKE_C_COMPILER="$AFL_CC" -DCMAKE_CXX_COMPILER="$AFL_CXX" "${OPTS[@]}" \
        || paper_die "exiv2 $V: cmake $variant failed"
      make -s -C "$build" -j || paper_die "exiv2 $V: make $variant failed"
      ;;
    cmp)
      env AFL_LLVM_CMPLOG=1 cmake -S "$SRC" -B "$build" -DCMAKE_C_COMPILER="$AFL_CC" -DCMAKE_CXX_COMPILER="$AFL_CXX" "${OPTS[@]}" \
        || paper_die "exiv2 $V: cmake $variant failed"
      env AFL_LLVM_CMPLOG=1 make -s -C "$build" -j || paper_die "exiv2 $V: make $variant failed"
      ;;
    asan)
      env ASAN_OPTIONS=detect_leaks=0 cmake -S "$SRC" -B "$build" -DCMAKE_C_COMPILER="$CLANG" -DCMAKE_CXX_COMPILER="$CLANGXX" \
        -DCMAKE_C_FLAGS="-g -O1 -fno-omit-frame-pointer -fsanitize=address" \
        -DCMAKE_CXX_FLAGS="-g -O1 -fno-omit-frame-pointer -fsanitize=address" \
        -DCMAKE_EXE_LINKER_FLAGS="-fsanitize=address" \
        -DCMAKE_SHARED_LINKER_FLAGS="-fsanitize=address" \
        -DCMAKE_MODULE_LINKER_FLAGS="-fsanitize=address" \
        "${OPTS[@]}" || paper_die "exiv2 $V: cmake $variant failed"
      env ASAN_OPTIONS=detect_leaks=0 make -s -C "$build" -j || paper_die "exiv2 $V: make $variant failed"
      ;;
    *) paper_die "exiv2: bad variant $variant" ;;
  esac
  if [ -x "$build/bin/exiv2" ]; then
    bin="$build/bin/exiv2"
  else
    bin=$(find "$build" -type f -name exiv2 -perm -111 -print -quit)
  fi
  [ -n "$bin" ] && [ -x "$bin" ] || paper_die "exiv2 $V: no exiv2 binary produced by $variant"
  cp "$bin" "$OUT/exiv2.$variant"
}

build_variant afl
build_variant cmp
build_variant asan

paper_finish "$OUT" exiv2 "$V"
