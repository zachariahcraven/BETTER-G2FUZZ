#!/bin/bash
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/../../common/lib.sh"

VERSION="${1:?paper or latest}"
mkdir -p "$2"
OUT=$(cd "$2" && pwd)
T=zlib_zlib_uncompress_fuzzer

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

FB_CFLAGS="-DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION -pthread -Wl,--no-as-needed -Wl,-ldl -Wl,-lm -Wno-unused-command-line-argument"

SRC=$(paper_fetch "$T" "$VERSION" "$WORK/src")
HARNESS="$HERE/zlib_uncompress_fuzzer.cc"

build_one() {
  local variant=$1
  local cc cxx cflags cxxflags harnessflags engine
  local B="$WORK/build-$variant"
  mkdir -p "$B"
  cp -a "$SRC/." "$B/"

  case $variant in
    afl|cmp)
      cc=afl-clang-fast; cxx=afl-clang-fast++
      cflags="$FB_CFLAGS -O3"
      cxxflags="$FB_CFLAGS -stdlib=libc++ -O3"
      harnessflags="-std=c++11"
      engine="-fsanitize=fuzzer"
      ;;
    asan)
      cc=clang; cxx=clang++
      cflags="$FB_CFLAGS -g -O1 -fno-omit-frame-pointer -fsanitize=address"
      cxxflags="$FB_CFLAGS -g -O1 -fno-omit-frame-pointer -fsanitize=address"
      harnessflags="-std=c++11 -fsanitize=fuzzer,address"
      engine=""
      ;;
  esac

  (
    cd "$B"
    export CC=$cc CXX=$cxx CFLAGS="$cflags" CXXFLAGS="$cxxflags"
    if [ "$variant" = cmp ]; then export AFL_LLVM_CMPLOG=1; fi
    if [ "$variant" = asan ]; then
      export ASAN_OPTIONS=detect_leaks=0
    fi
    ./configure
    make clean
    make -j"$(nproc)"
    $cxx -I. $CXXFLAGS $harnessflags "$HARNESS" -o "$OUT/$T.$variant" $engine ./libz.a
  )
}

build_one afl
build_one cmp
build_one asan

# Seeds: top-level files matching *.* in the built tree (same as FuzzBench's
# `zip $OUT/seed_corpus.zip *.*` run in the working directory after make)
mkdir -p "$OUT/seeds/$T"
(
  cd "$WORK/build-afl"
  for f in *.*; do
    if [ -f "$f" ]; then cp "$f" "$OUT/seeds/$T/"; fi
  done
)

paper_finish "$OUT" "$T" "$VERSION"
