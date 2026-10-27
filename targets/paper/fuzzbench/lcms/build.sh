#!/bin/bash
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/../../common/lib.sh"

VERSION="${1:?paper or latest}"
mkdir -p "$2"
OUT=$(cd "$2" && pwd)
T=lcms_cms_transform_fuzzer
FB_CFLAGS="-DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION -pthread -Wl,--no-as-needed -Wl,-ldl -Wl,-lm -Wno-unused-command-line-argument"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

SRC=$(paper_fetch "$T" "$VERSION" "$WORK/src")
HARNESS="$HERE/cms_transform_fuzzer.cc"

build_one() {
  local variant=$1
  local cc cxx cxxflags engine
  local B="$WORK/build-$variant"
  mkdir -p "$B"
  cp -a "$SRC/." "$B/"

  case $variant in
    afl)
      cc=afl-clang-fast; cxx=afl-clang-fast++
      cxxflags="-std=c++11"
      engine="-fsanitize=fuzzer"
      ;;
    cmp)
      cc=afl-clang-fast; cxx=afl-clang-fast++
      cxxflags="-std=c++11"
      engine="-fsanitize=fuzzer"
      ;;
    asan)
      cc=clang; cxx=clang++
      cxxflags="-std=c++11 -fsanitize=fuzzer,address"
      engine=""
      ;;
  esac

  (
    cd "$B"
    export CC=$cc CXX=$cxx
    if [ "$variant" = cmp ]; then export AFL_LLVM_CMPLOG=1; fi
    if [ "$variant" = asan ]; then
      export CFLAGS="$FB_CFLAGS -g -O1 -fno-omit-frame-pointer -fsanitize=address"
      export CXXFLAGS="$FB_CFLAGS -g -O1 -fno-omit-frame-pointer -fsanitize=address"
      export ASAN_OPTIONS=detect_leaks=0
    else
      export CFLAGS="$FB_CFLAGS -O3"
      export CXXFLAGS="$FB_CFLAGS -stdlib=libc++ -O3"
      unset LDFLAGS
    fi
    ./autogen.sh
    ./configure
    make clean
    make -j"$(nproc)"
    $cxx -I include/ $CXXFLAGS $cxxflags "$HARNESS" -o "$OUT/$T.$variant" $engine src/.libs/liblcms2.a
  )
}

build_one afl
build_one cmp
build_one asan

# Seeds: exactly the benchmark's seed folder
SEEDS_SRC="$PAPER_REF/fuzzbench/benchmarks/lcms_cms_transform_fuzzer/seeds"
[ -d "$SEEDS_SRC" ] || paper_die "seeds folder missing: $SEEDS_SRC"
mkdir -p "$OUT/seeds/$T"
count=0
for f in "$SEEDS_SRC"/*; do
  [ -f "$f" ] || continue
  cp "$f" "$OUT/seeds/$T/"
  count=$((count+1))
done
[ "$count" -gt 0 ] || paper_die "no seeds found in $SEEDS_SRC"

paper_finish "$OUT" "$T" "$VERSION"
