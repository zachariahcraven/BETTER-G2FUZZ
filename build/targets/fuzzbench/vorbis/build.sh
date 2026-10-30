#!/bin/bash
# FUZZBENCH vorbis (paper: vorbis pin from the manifest; latest: the newest release), built as the
# FuzzBench vorbis project's reference build does: static libogg, static libvorbis, then the harness.
# Usage (inside builder-fuzzbench.sif; build/targets/build-paper.sh runs it): build.sh paper|latest OUT
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/../../common/lib.sh"

V=${1:?usage: build.sh paper|latest OUT}
OUT=${2:?usage: build.sh paper|latest OUT}
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
T=vorbis_decode_fuzzer
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT

HARNESS="$HERE/decode_fuzzer.cc"
HARNESS_SHA=a1ad08f974fb17ad41c9cfc28225cdf86d48e5df3b34a01d610baa6923b25acc
[ -f "$HARNESS" ] || paper_die "harness $HARNESS is missing"
if ! echo "$HARNESS_SHA  $HARNESS" | sha256sum -c --status; then
  paper_die "harness $HARNESS does not have the expected sha256"
fi

SRC=$(paper_fetch "$T" "$V" "$W/vorbis")
SRC=$(cd "$SRC" && pwd)
VORBIS_DIR=$SRC
if [ ! -f "$VORBIS_DIR/autogen.sh" ]; then
  for d in "$SRC"/*/; do
    [ -d "$d" ] || continue
    if [ -f "${d}autogen.sh" ]; then
      VORBIS_DIR=${d%/}
      break
    fi
  done
fi
[ -f "$VORBIS_DIR/autogen.sh" ] || paper_die "cannot find vorbis autogen.sh in fetched source $SRC"

OGG_DIR=$W/ogg
OGG_COMMIT=db5c7a49ce7ebda47b15b78471e78fb7f2483e22
git clone --quiet https://github.com/xiph/ogg.git "$OGG_DIR" || paper_die "git clone of ogg failed"
git -C "$OGG_DIR" checkout --quiet --detach "$OGG_COMMIT" || paper_die "ogg checkout $OGG_COMMIT failed"
[ "$(git -C "$OGG_DIR" rev-parse HEAD)" = "$OGG_COMMIT" ] || paper_die "ogg pinned commit check failed"

if [ -z "${PAPER_REF:-}" ]; then
  paper_die "PAPER_REF is not set; cannot copy the FuzzBench vorbis seed corpus"
fi
seed_src="$PAPER_REF/fuzzbench/benchmarks/$T/seeds"
[ -d "$seed_src" ] || paper_die "FuzzBench vorbis seed folder $seed_src is missing"

FB_CFLAGS="-DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION -pthread -Wl,--no-as-needed -Wl,-ldl -Wl,-lm -Wno-unused-command-line-argument"

build_variant() {
  local variant=$1
  local cc cxx engine prefix
  local B="$W/build-$variant"
  mkdir -p "$B/ogg" "$B/vorbis" "$B/install"
  cp -a "$OGG_DIR/." "$B/ogg/"
  cp -a "$VORBIS_DIR/." "$B/vorbis/"
  prefix="$B/install"
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
      unset AFL_LLVM_CMPLOG
    else
      export CFLAGS="$FB_CFLAGS -O3"
      export CXXFLAGS="$FB_CFLAGS -stdlib=libc++ -O3"
      if [ "$variant" = cmp ]; then
        export AFL_LLVM_CMPLOG=1
      else
        unset AFL_LLVM_CMPLOG
      fi
    fi

    (cd ogg && ./autogen.sh && ./configure --prefix="$prefix" --enable-static --disable-shared --disable-crc && make -j"$(nproc)" && make install) \
      || paper_die "building ogg failed for $variant"
    (cd vorbis && ./autogen.sh && ./configure --prefix="$prefix" --enable-static --disable-shared && make -j"$(nproc)" && make install) \
      || paper_die "building vorbis failed for $variant"

    $cxx $CXXFLAGS -std=c++11 -I"$prefix/include" "$HARNESS" -o "$OUT/$T.$variant" $engine -L"$prefix/lib" -lvorbisfile -lvorbis -logg \
      || paper_die "building $T.$variant failed"
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
done < <(find "$seed_src" -maxdepth 1 -type f -print0 | sort -z)
[ "$copied" -gt 0 ] || paper_die "no regular seed files were found in $seed_src"

paper_finish "$OUT" "$T" "$V"
