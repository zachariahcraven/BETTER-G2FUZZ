#!/bin/bash
# UNIFUZZ flvmeta (paper: flvmeta-1.2.1 from unibench; latest: v1.3.1), built as unibench_build's
# afl/Dockerfile does (`cmake . && make`), three ways: .afl (AFL++), .cmp (CmpLog), .asan (ASan).
# Usage (inside builder-unifuzz.sif; targets/paper/build-paper.sh runs it): build.sh paper|latest OUT
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/../../common/lib.sh"
V=${1:?paper|latest}; mkdir -p "$2"; OUT=$(cd "$2" && pwd)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT

AFL_CC=afl-clang-fast
AFL_CXX=afl-clang-fast++
ASAN_FLAGS="-g -O1 -fno-omit-frame-pointer -fsanitize=address"

FETCHED=$(paper_fetch flvmeta "$V" "$W/src")
SRC=$FETCHED
[ -d "$SRC" ] || paper_die "flvmeta: paper_fetch returned a non-directory: $SRC"

# The unibench archive may extract one level down, or the folder may be renamed; find the CMake project.
if [ ! -f "$SRC/CMakeLists.txt" ]; then
  for d in "$SRC"/*/; do
    if [ -f "${d}CMakeLists.txt" ]; then SRC=${d%/}; break; fi
  done
fi
if [ ! -f "$SRC/CMakeLists.txt" ]; then
  CAND=$(find "$SRC" -maxdepth 4 -type f -name CMakeLists.txt 2>/dev/null | sed -n 1p || true)
  [ -n "$CAND" ] && SRC=$(dirname "$CAND")
fi
[ -f "$SRC/CMakeLists.txt" ] || paper_die "flvmeta: no CMakeLists.txt under $FETCHED"

build_variant() {
  local variant=$1 sdir bdir bin
  local -a cmake_args env_cmds
  sdir=$(mktemp -d "$W/src-$variant-XXXX")
  bdir=$(mktemp -d "$W/build-$variant-XXXX")
  cp -a "$SRC/." "$sdir/"

  # The reference block uses `cmake . && make`; build out of tree with the same options so every
  # variant starts from a clean tree and latest releases that refuse in-source builds still work.
  case $variant in
    afl)
      cmake_args=(-G "Unix Makefiles" -DCMAKE_C_COMPILER="$AFL_CC" -DCMAKE_CXX_COMPILER="$AFL_CXX")
      env_cmds=(-u CFLAGS -u CXXFLAGS -u LDFLAGS)
      ;;
    cmp)
      cmake_args=(-G "Unix Makefiles" -DCMAKE_C_COMPILER="$AFL_CC" -DCMAKE_CXX_COMPILER="$AFL_CXX")
      env_cmds=(-u CFLAGS -u CXXFLAGS -u LDFLAGS AFL_LLVM_CMPLOG=1)
      ;;
    asan)
      cmake_args=(-G "Unix Makefiles" -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++
                 -DCMAKE_C_FLAGS="$ASAN_FLAGS" -DCMAKE_CXX_FLAGS="$ASAN_FLAGS")
      env_cmds=(-u LDFLAGS CFLAGS="$ASAN_FLAGS" CXXFLAGS="$ASAN_FLAGS" ASAN_OPTIONS=detect_leaks=0)
      ;;
    *)
      paper_die "flvmeta: unknown variant $variant"
      exit 1
      ;;
  esac

  if ! (cd "$bdir" && env "${env_cmds[@]}" cmake "${cmake_args[@]}" "$sdir" \
        > "$W/$variant.cmake.log" 2>&1); then
    tail -40 "$W/$variant.cmake.log" >&2 || true
    paper_die "flvmeta: cmake failed for $variant"
  fi
  if ! env "${env_cmds[@]}" make -C "$bdir" -j > "$W/$variant.make.log" 2>&1; then
    tail -40 "$W/$variant.make.log" >&2 || true
    paper_die "flvmeta: make failed for $variant"
  fi

  bin=$(find "$bdir" -type f -name flvmeta -perm -u+x 2>/dev/null | sed -n 1p || true)
  [ -n "$bin" ] || paper_die "flvmeta: could not find the built flvmeta binary for $variant"
  cp "$bin" "$OUT/flvmeta.$variant"
}

build_variant afl
build_variant cmp
build_variant asan

paper_finish "$OUT" flvmeta "$V"
