#!/bin/bash
# FUZZBENCH libjpeg-turbo (paper: libjpeg-turbo pin from the manifest; latest: 3.2.0), built as the
# FuzzBench libjpeg-turbo benchmark builds it, three ways: .afl (AFL++), .cmp (CmpLog), .asan
# (AddressSanitizer).
# Usage (inside builder-fuzzbench.sif; build/targets/build-paper.sh runs it): build.sh paper|latest OUT
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/../../common/lib.sh"

V=${1:?usage: build.sh paper|latest OUT}
OUT=${2:?usage: build.sh paper|latest OUT}
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
T=libjpeg-turbo_libjpeg_turbo_fuzzer
BIN=libjpeg_turbo_fuzzer
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
die() { echo "FAIL  $*" >&2; exit 1; }
FB_CFLAGS="-DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION -pthread -Wl,--no-as-needed -Wl,-ldl -Wl,-lm -Wno-unused-command-line-argument"

SRC=$(paper_fetch "$T" "$V" "$W/src")
LJ_DIR=$SRC
if [ ! -f "$LJ_DIR/CMakeLists.txt" ] || [ ! -d "$LJ_DIR/fuzz" ]; then
  for d in "$SRC"/*/; do
    [ -d "$d" ] || continue
    if [ -f "${d}CMakeLists.txt" ] && [ -d "${d}fuzz" ]; then
      LJ_DIR=${d%/}
      break
    fi
  done
fi
[ -f "$LJ_DIR/CMakeLists.txt" ] && [ -d "$LJ_DIR/fuzz" ] || \
  die "cannot find libjpeg-turbo CMakeLists.txt and fuzz/ in fetched source $SRC"

SEED_DIR=$W/seed-corpora
SEED_COMMIT=7c9ea5ffaac76ef618657978c9fdfa845d310b93
git clone --quiet https://github.com/libjpeg-turbo/seed-corpora.git "$SEED_DIR" || \
  die "git clone of seed-corpora failed"
git -C "$SEED_DIR" checkout --quiet --detach "$SEED_COMMIT" || \
  die "seed-corpora checkout $SEED_COMMIT failed"
[ "$(git -C "$SEED_DIR" rev-parse HEAD)" = "$SEED_COMMIT" ] || \
  die "seed-corpora pinned commit check failed"

build_variant() {
  local variant=$1
  local cc cxx cflags cxxflags ldflags engine
  local B="$W/build-$variant"
  local prefix="$B/install"
  local bindir="$B/fuzz-bin"
  mkdir -p "$B"
  cp -a "$LJ_DIR/." "$B/"
  (
    cd "$B"
    unset LDFLAGS ASAN_OPTIONS AFL_LLVM_CMPLOG LIB_FUZZING_ENGINE

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
        engine="-fsanitize=fuzzer,address"
        ;;
      *)
        die "internal: bad variant $variant"
        ;;
    esac
    export CC=$cc CXX=$cxx CFLAGS=$cflags CXXFLAGS=$cxxflags LIB_FUZZING_ENGINE=$engine
    if [ "$variant" = asan ]; then
      export LDFLAGS=$ldflags
      export ASAN_OPTIONS=detect_leaks=0
    fi
    if [ "$variant" = cmp ]; then
      export AFL_LLVM_CMPLOG=1
    fi

    mkdir -p "$prefix" "$bindir"
    cmake . \
      -DCMAKE_BUILD_TYPE=RelWithDebInfo \
      -DENABLE_STATIC=1 \
      -DENABLE_SHARED=0 \
      "-DCMAKE_C_FLAGS_RELWITHDEBINFO=-g -DNDEBUG" \
      "-DCMAKE_CXX_FLAGS_RELWITHDEBINFO=-g -DNDEBUG" \
      -DCMAKE_INSTALL_PREFIX="$prefix" \
      -DWITH_FUZZ=1 \
      -DFUZZ_BINDIR="$bindir" \
      -DFUZZ_LIBRARY="$engine" \
      -DFUZZER_SUFFIX="" || die "cmake configure failed for $variant"
    make -j"$(nproc)" || die "make failed for $variant"
    make install || die "make install failed for $variant"

    if [ ! -f "$bindir/$BIN" ] && [ -f "$prefix/bin/$BIN" ]; then
      cp -a "$prefix/bin/$BIN" "$bindir/$BIN"
    fi
    [ -f "$bindir/$BIN" ] || die "fuzzer binary $BIN was not found in $bindir for $variant"
    install -m 0755 -- "$bindir/$BIN" "$OUT/$T.$variant" || \
      die "installing $OUT/$T.$variant failed"
  )
}

build_variant afl
build_variant cmp
build_variant asan

seed_files() {
  local d
  if [ -d "$SEED_DIR/afl-testcases" ]; then
    find "$SEED_DIR/afl-testcases" -maxdepth 1 -type d -name 'jpeg*' -print0 |
      while IFS= read -r -d '' d; do
        find "$d" -type f -print0
      done
  fi
  if [ -d "$SEED_DIR/bugs" ]; then
    find "$SEED_DIR/bugs" -maxdepth 1 -type d -name 'decompress*' -print0 |
      while IFS= read -r -d '' d; do
        find "$d" -type f -print0
      done
  fi
}

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

  cp -- "$seed" "$seed_dir/$dest_base"
  used["$base"]=1
  used["$dest_base"]=1
  copied=$((copied + 1))
done < <(seed_files | sort -z)

echo "INFO  copied $copied seed files for $T"
if [ "$copied" -eq 0 ]; then
  printf 'hi' > "$seed_dir/default_seed"
fi

paper_finish "$OUT" "$T" "$V"
