#!/bin/bash
# FUZZBENCH libpcap (paper: 17ff63e88ea99112a905eefc6f862dac20de09e1; latest: libpcap-1.11.0), built as the
# FuzzBench libpcap project's reference build does: cmake -DDISABLE_DBUS=1, make, then the fuzz_both harness.
# Usage (inside builder-fuzzbench.sif; targets/paper/build-paper.sh runs it): build.sh paper|latest OUT
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/../../common/lib.sh"

V=${1:?usage: build.sh paper|latest OUT}
OUT=${2:?usage: build.sh paper|latest OUT}
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
T=libpcap_fuzz_both
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
FB_CFLAGS="-DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION -pthread -Wl,--no-as-needed -Wl,-ldl -Wl,-lm -Wno-unused-command-line-argument"

SRC=$(paper_fetch "$T" "$V" "$W/libpcap")
SRC=$(cd "$SRC" && pwd)
[ -f "$SRC/testprogs/fuzz/fuzz_both.c" ] || paper_die "testprogs/fuzz/fuzz_both.c not found in $SRC"

build_variant() {
  local variant=$1
  local cc cxx engine
  local B="$W/build-$variant"
  mkdir -p "$B"
  cp -a "$SRC/." "$B/"
  (
    cd "$B"
    case $variant in
      afl|cmp)
        cc=afl-clang-fast
        cxx=afl-clang-fast++
        engine="-fsanitize=fuzzer"
        ;;
      asan)
        cc=clang
        cxx=clang++
        engine="-fsanitize=fuzzer,address"
        ;;
      *)
        paper_die "internal: bad variant $variant"
        ;;
    esac
    export CC=$cc CXX=$cxx
    if [ "$variant" = asan ]; then
      export CFLAGS="$FB_CFLAGS -g -O1 -fno-omit-frame-pointer -fsanitize=address"
      export CXXFLAGS="$FB_CFLAGS -g -O1 -fno-omit-frame-pointer -fsanitize=address"
      export LDFLAGS="-g -O1 -fno-omit-frame-pointer -fsanitize=address"
      export ASAN_OPTIONS=detect_leaks=0
    else
      export CFLAGS="$FB_CFLAGS -O3"
      export CXXFLAGS="$FB_CFLAGS -stdlib=libc++ -O3"
      unset LDFLAGS
      if [ "$variant" = cmp ]; then
        export AFL_LLVM_CMPLOG=1
      else
        unset AFL_LLVM_CMPLOG
      fi
    fi

    mkdir -p build
    cd build
    cmake -DCMAKE_C_COMPILER="$cc" -DCMAKE_CXX_COMPILER="$cxx" -DDISABLE_DBUS=1 .. \
      || paper_die "cmake failed for $variant"
    make -j"$(nproc)" || paper_die "make failed for $variant"

    $CC $CFLAGS -I.. -c ../testprogs/fuzz/fuzz_both.c -o fuzz_both.o \
      || paper_die "compiling fuzz_both.c failed for $variant"
    $CXX $CXXFLAGS fuzz_both.o -o "$OUT/$T.$variant" libpcap.a $engine \
      || paper_die "linking $T.$variant failed"
  )
}

build_variant afl
build_variant cmp
build_variant asan

# Seeds: the reference only zips fuzz_pcap_ and fuzz_filter_ corpora; FuzzBench looks for
# fuzz_both_seed_corpus.zip (absent) and /seeds is not filled, so the trial corpus is empty and
# AFL-family fuzzers start from one file default_seed containing "hi" (no newline).
seed_dir="$OUT/seeds/$T"
rm -rf "$seed_dir"
mkdir -p "$seed_dir"
printf 'hi' > "$seed_dir/default_seed"

paper_finish "$OUT" "$T" "$V"
