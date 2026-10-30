#!/bin/bash
# UNIFUZZ libtiff (paper: libtiff-3.9.7 from unibench; latest: v4.7.2), built as unibench_build's
# afl/Dockerfile does (`./autogen.sh && ./configure --disable-shared && make`), three ways:
# .afl (AFL++), .cmp (CmpLog), .asan (AddressSanitizer).
# Usage (inside builder-unifuzz.sif; build/targets/build-paper.sh runs it): build.sh paper|latest OUT
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/../../common/lib.sh"
V=${1:?paper|latest}; mkdir -p "$2"; OUT=$(cd "$2" && pwd)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
T=tiffsplit
unset CFLAGS CXXFLAGS LDFLAGS

SRC=$(paper_fetch "$T" "$V" "$W/src")
# The unibench archive may be extracted one level down (the Dockerfile renames libtiff-Release-v3-9-7).
if [ ! -f "$SRC/autogen.sh" ]; then
  A=$(find "$SRC" -maxdepth 3 -type f -name autogen.sh | head -n 1) || true
  if [ -n "$A" ]; then
    SRC=$(cd "$(dirname "$A")" && pwd)
  else
    paper_die "libtiff: autogen.sh not found under $SRC"
  fi
fi

CONF_OPTS=(--disable-shared)
case $V in
  latest)
    # libtiff 4.7.2 auto-detects codecs that libtiff 3.9.7 did not have. Keep only the codecs the
    # reference image provided (zlib and JPEG via libtiff-dev's dependencies) by disabling the rest.
    CONF_OPTS+=(--disable-zstd --disable-webp --disable-lerc --disable-libdeflate)
    ;;
esac
CONF_OPTS_STR=${CONF_OPTS[*]}
JOBS=$(nproc 2>/dev/null || echo 2)
export CONF_OPTS_STR JOBS

build_variant() {
  local variant=$1; shift
  local dir="$W/build-$variant"
  rm -rf "$dir"
  cp -a "$SRC" "$dir"
  if ! env "$@" bash -c '
    set -euo pipefail
    cd "$0"
    if [ -x ./autogen.sh ]; then
      ./autogen.sh
    elif [ -x ./configure ]; then
      :
    else
      echo "libtiff $1: autogen.sh or configure not found" >&2
      exit 1
    fi
    ./configure $CONF_OPTS_STR
    make -s -j"$JOBS"
  ' "$dir" "$variant"; then
    paper_die "libtiff $variant: build failed in $dir"
  fi
  [ -f "$dir/tools/tiffsplit" ] || paper_die "libtiff $variant: tools/tiffsplit was not built"
  cp "$dir/tools/tiffsplit" "$OUT/$T.$variant"
}

build_variant afl   -u CFLAGS -u CXXFLAGS -u LDFLAGS CC=afl-clang-fast CXX=afl-clang-fast++
build_variant cmp   -u CFLAGS -u CXXFLAGS -u LDFLAGS CC=afl-clang-fast CXX=afl-clang-fast++ AFL_LLVM_CMPLOG=1
ASAN_FLAGS="-g -O1 -fno-omit-frame-pointer -fsanitize=address"
build_variant asan  -u LDFLAGS CC=clang CXX=clang++ CFLAGS="$ASAN_FLAGS" CXXFLAGS="$ASAN_FLAGS" ASAN_OPTIONS=detect_leaks=0

paper_finish "$OUT" "$T" "$V"
