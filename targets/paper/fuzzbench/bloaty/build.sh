#!/bin/bash
# FUZZBENCH bloaty (paper: bloaty pin from the manifest; latest: HEAD 2026-09-24), built as
# FuzzBench's bloaty project's reference build does: cmake -G Ninja + ninja, with
# LIB_FUZZING_ENGINE exported so bloaty's CMakeLists builds the fuzz_target.
# Usage (inside builder-fuzzbench.sif; targets/paper/build-paper.sh runs it): build.sh paper|latest OUT
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/../../common/lib.sh"

V=${1:?usage: build.sh paper|latest OUT}
OUT=${2:?usage: build.sh paper|latest OUT}
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
T=bloaty_fuzz_target
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT

FB_CFLAGS="-DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION -pthread -Wl,--no-as-needed -Wl,-ldl -Wl,-lm -Wno-unused-command-line-argument"

SRC=$(paper_fetch "$T" "$V" "$W/src")
SRC=$(cd "$SRC" && pwd)
BLOATY_DIR=$SRC
if [ ! -f "$BLOATY_DIR/CMakeLists.txt" ]; then
  for d in "$SRC"/*/; do
    [ -d "$d" ] || continue
    if [ -f "${d}CMakeLists.txt" ]; then
      BLOATY_DIR=${d%/}
      break
    fi
  done
fi
[ -f "$BLOATY_DIR/CMakeLists.txt" ] || paper_die "cannot find bloaty's CMakeLists.txt in fetched source $SRC"

build_variant() {
  local variant=$1
  local cc cxx engine extra_cmake
  local B="$W/build-$variant"
  mkdir -p "$B"
  (
    cd "$B"
    case $variant in
      afl|cmp)
        cc=afl-clang-fast
        cxx=afl-clang-fast++
        export CFLAGS="$FB_CFLAGS -O3"
        export CXXFLAGS="$FB_CFLAGS -stdlib=libc++ -O3"
        engine="-fsanitize=fuzzer"
        ;;
      asan)
        cc=clang
        cxx=clang++
        export CFLAGS="$FB_CFLAGS -g -O1 -fno-omit-frame-pointer -fsanitize=address"
        export CXXFLAGS="$FB_CFLAGS -g -O1 -fno-omit-frame-pointer -fsanitize=address"
        engine="-fsanitize=fuzzer,address"
        export ASAN_OPTIONS=detect_leaks=0
        ;;
      *)
        paper_die "internal: bad variant $variant"
        ;;
    esac
    export CC=$cc CXX=$cxx LIB_FUZZING_ENGINE=$engine
    if [ "$variant" = cmp ]; then
      export AFL_LLVM_CMPLOG=1
    else
      unset AFL_LLVM_CMPLOG
    fi
    extra_cmake=""
    if [ "$V" = "latest" ]; then
      extra_cmake="-DBLOATY_PREFER_SYSTEM_ZSTD=OFF"
    fi
    cmake -G Ninja -DBUILD_TESTING=false $extra_cmake "$BLOATY_DIR" || paper_die "cmake failed for $variant"
    ninja -j"$(nproc)" || paper_die "ninja failed for $variant"
    cp fuzz_target "$OUT/$T.$variant" || paper_die "copying $T.$variant failed"
  )
}

build_variant afl
build_variant cmp
build_variant asan

seed_dir="$OUT/seeds/$T"
rm -rf "$seed_dir"
mkdir -p "$seed_dir"
declare -A used=()
copied=0
while IFS= read -r -d '' seed; do
  base=$(basename "$seed")
  size=$(stat -c%s "$seed")
  if [ "$size" -gt 1048576 ]; then continue; fi
  dest_base=$base
  if [ -n "${used["$dest_base"]+x}" ]; then
    n=1
    while [ -n "${used["$dest_base"]+x}" ]; do
      dest_base="${n}_${base}"
      n=$((n + 1))
    done
  fi
  cp "$seed" "$seed_dir/$dest_base"
  used["$base"]=1
  used["$dest_base"]=1
  copied=$((copied + 1))
done < <(find "$BLOATY_DIR/tests/testdata/fuzz_corpus" -type f -print0 | sort -z)
[ "$copied" -gt 0 ] || paper_die "no regular seed files were found in $BLOATY_DIR/tests/testdata/fuzz_corpus"

paper_finish "$OUT" "$T" "$V"
