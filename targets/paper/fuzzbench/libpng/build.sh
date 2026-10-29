#!/bin/bash
# FUZZBENCH libpng (paper: libpng pin from the manifest; latest: v1.6.59), built as libpng's own
# contrib/oss-fuzz/build.sh does, three ways: .afl (AFL++), .cmp (CmpLog), .asan (AddressSanitizer).
# Usage (inside builder-fuzzbench.sif; targets/paper/build-paper.sh runs it): build.sh paper|latest OUT
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/../../common/lib.sh"

V=${1:?usage: build.sh paper|latest OUT}
OUT=${2:?usage: build.sh paper|latest OUT}
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
T=libpng_libpng_read_fuzzer
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
die() { echo "FAIL  $*" >&2; exit 1; }
FB_CFLAGS="-DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION -pthread -Wl,--no-as-needed -Wl,-ldl -Wl,-lm -Wno-unused-command-line-argument"

SRC=$(paper_fetch "$T" "$V" "$W/src")
if [ -f "$SRC/scripts/pnglibconf.dfa" ]; then
  LIBPNG_DIR=$SRC
elif [ -f "$SRC/libpng/scripts/pnglibconf.dfa" ]; then
  LIBPNG_DIR=$SRC/libpng
else
  die "cannot find libpng's scripts/pnglibconf.dfa in fetched source $SRC"
fi
[ -f "$LIBPNG_DIR/contrib/oss-fuzz/libpng_read_fuzzer.cc" ] || \
  die "cannot find libpng_read_fuzzer.cc in fetched source $LIBPNG_DIR"

build_variant() {
  local variant=$1
  local cc cxx cflags cxxflags ldflags engine
  local B="$W/build-$variant"
  mkdir -p "$B"
  cp -a "$LIBPNG_DIR/." "$B/"
  (
    cd "$B"

    cat scripts/pnglibconf.dfa | \
      sed -e "s/option STDIO/option STDIO disabled/" \
          -e "s/option WARNING /option WARNING disabled/" \
          -e "s/option WRITE enables WRITE_INT_FUNCTIONS/option WRITE disabled/" \
      > scripts/pnglibconf.dfa.temp
    mv scripts/pnglibconf.dfa.temp scripts/pnglibconf.dfa

    case $variant in
      afl|cmp)
        cc=afl-clang-fast
        cxx=afl-clang-fast++
        cflags="$FB_CFLAGS -O3"
        cxxflags="$FB_CFLAGS -stdlib=libc++ -O3"
        engine="-fsanitize=fuzzer"
        ;;
      asan)
        cc=clang
        cxx=clang++
        cflags="$FB_CFLAGS -g -O1 -fno-omit-frame-pointer -fsanitize=address"
        cxxflags="$FB_CFLAGS -g -O1 -fno-omit-frame-pointer -fsanitize=address"
        ldflags="-g -O1 -fno-omit-frame-pointer -fsanitize=address"
        engine="-fsanitize=fuzzer"
        ;;
      *)
        die "internal: bad variant $variant"
        ;;
    esac
    export CC=$cc CXX=$cxx CFLAGS=$cflags CXXFLAGS=$cxxflags
    if [ "$variant" = asan ]; then
      export LDFLAGS=$ldflags
    else
      unset LDFLAGS
    fi
    if [ "$variant" = cmp ]; then export AFL_LLVM_CMPLOG=1; fi
    if [ "$variant" = asan ]; then export ASAN_OPTIONS=detect_leaks=0; fi

    autoreconf -f -i || die "autoreconf -f -i failed for $variant"
    ./configure --with-libpng-prefix=OSS_FUZZ_ || die "./configure failed for $variant"
    make -j"$(nproc)" clean || die "make clean failed for $variant"
    make -j"$(nproc)" libpng16.la || die "make libpng16.la failed for $variant"
    $cxx $CXXFLAGS -std=c++11 -I. contrib/oss-fuzz/libpng_read_fuzzer.cc \
      -o "$OUT/$T.$variant" $engine .libs/libpng16.a -lz \
      || die "building $T.$variant failed"
  )
}

build_variant afl
build_variant cmp
build_variant asan

seed_dir="$OUT/seeds/$T"
rm -rf "$seed_dir"
mkdir -p "$seed_dir"
declare -A used=()
while IFS= read -r -d '' png; do
  base=$(basename "$png")
  size=$(stat -c%s "$png")
  if [ "$size" -gt 1048576 ]; then continue; fi

  newbase=""
  if [ -n "${used[$base]+x}" ]; then
    rel=${png#"$LIBPNG_DIR"/}
    parent=$(basename "$(dirname "$rel")")
    if [ -z "$parent" ] || [ "$parent" = "." ]; then parent=root; fi
    newbase="${parent}_${base}"
    n=1
    while [ -n "${used[$newbase]+x}" ]; do
      newbase="${parent}_${n}_${base}"
      n=$((n + 1))
    done
  fi

  dest_base=$base
  if [ -n "$newbase" ]; then dest_base=$newbase; fi
  cp "$png" "$seed_dir/$dest_base"
  used[$base]=1
  if [ -n "$newbase" ]; then used[$newbase]=1; fi
done < <(
  find "$LIBPNG_DIR" -type f -name '*.png' -print0 | grep -zv crashers | sort -z
)

paper_finish "$OUT" "$T" "$V"
