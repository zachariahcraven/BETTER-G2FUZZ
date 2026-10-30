#!/bin/bash
# UNIFUZZ mp3gain (paper: mp3gain-1.5.2 from unibench; latest: mp3gain-1.6.2), built as
# unibench_build's afl/Dockerfile does (`sed -i 's/CC=/CC?=/' Makefile && make`), three ways:
# .afl (AFL++), .cmp (CmpLog), .asan (AddressSanitizer).
# Usage (inside builder-unifuzz.sif; build/targets/build-paper.sh runs it): build.sh paper|latest OUT
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/../../common/lib.sh"
V=${1:?paper or latest}; mkdir -p "$2"; OUT=$(cd "$2" && pwd)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT

SRC=$(paper_fetch mp3gain "$V" "$W/src")
# The unibench archive may unpack one level down or under another name; find the mp3gain source folder.
if [ ! -f "$SRC/Makefile" ]; then
  MAKEFILE=$(find "$SRC" -mindepth 1 -maxdepth 4 -type f -name Makefile -print -quit || true)
  [ -n "$MAKEFILE" ] || paper_die "mp3gain: no Makefile found under $SRC"
  SRC=$(dirname "$MAKEFILE")
fi
SRC=$(cd "$SRC" && pwd -P)
[ -f "$SRC/Makefile" ] || paper_die "mp3gain: no Makefile found under $SRC"

MPG123_NAME=mpg123-1.32.10.tar.bz2
MPG123_SHA=87b2c17fe0c979d3ef38eeceff6362b35b28ac8589fbf1854b5be75c9ab6557c
prepare_mpg123_tarball() {
  local dest=$W/$MPG123_NAME
  if [ -f "$dest" ]; then
    local h=$(sha256sum "$dest" | cut -c1-64)
    [ "$h" = "$MPG123_SHA" ] || paper_die "mpg123: sha256 mismatch for existing $dest"
    return 0
  fi
  local -a dirs=()
  if [ -n "${PAPER_REF:-}" ]; then
    dirs+=("$PAPER_REF/tools" "$PAPER_REF")
  fi
  local d
  if d=$(cd "$HERE/../.." 2>/dev/null && pwd); then dirs+=("$d/tools"); fi
  if d=$(cd "$HERE/../../../" 2>/dev/null && pwd); then dirs+=("$d/tools"); fi
  if d=$(cd "$HERE/../../../.." 2>/dev/null && pwd); then dirs+=("$d/tools"); fi
  local dir found=
  for dir in ${dirs[@]+"${dirs[@]}"}; do
    if [ -f "$dir/$MPG123_NAME" ]; then
      local h=$(sha256sum "$dir/$MPG123_NAME" | cut -c1-64)
      if [ "$h" = "$MPG123_SHA" ]; then found=$dir/$MPG123_NAME; break; fi
    fi
  done
  if [ -n "$found" ]; then
    cp "$found" "$dest"
  else
    # The pinned tarball is normally vendored under $PAPER_REF/tools; download only if it is missing.
    wget -q -O "$dest" "https://www.mpg123.de/download/$MPG123_NAME" ||
    wget -q -O "$dest" "https://downloads.sourceforge.net/project/mpg123/mpg123/1.32.10/$MPG123_NAME" ||
    paper_die "mpg123: cannot obtain pinned tarball $MPG123_NAME (no vendored copy found in: ${dirs[*]:-none})"
  fi
  local h=$(sha256sum "$dest" | cut -c1-64)
  [ "$h" = "$MPG123_SHA" ] || paper_die "mpg123: sha256 mismatch for $MPG123_NAME"
}

build_mpg123() {
  local variant=$1 cc=$2 cxx=$3
  shift 3
  prepare_mpg123_tarball
  local prefix=$W/mpg123-$variant srcdir=$W/mpg123-src-$variant
  rm -rf "$prefix" "$srcdir"; mkdir -p "$prefix/lib" "$prefix/include" "$srcdir"
  tar -xf "$W/$MPG123_NAME" -C "$srcdir"
  local d=$srcdir/${MPG123_NAME%.tar.bz2}
  [ -d "$d" ] || paper_die "mpg123: tarball did not unpack to $d"
  local asan_flags="-g -O1 -fno-omit-frame-pointer -fsanitize=address"
  # The static library is linked into a PIE mp3gain; build it with -fPIC as part of the compiler
  # command so mp3gain's Makefile and CFLAGS/CXXFLAGS/LDFLAGS stay untouched.
  local cc_build="$cc -fPIC" cxx_build="$cxx -fPIC"
  if [ "$variant" = asan ]; then
    if ! (cd "$d" &&
          env -u LDFLAGS -u CPPFLAGS CC="$cc_build" CXX="$cxx_build" CFLAGS="$asan_flags" CXXFLAGS="$asan_flags" ASAN_OPTIONS=detect_leaks=0 ./configure --prefix="$prefix" --disable-shared --enable-static &&
          env -u LDFLAGS -u CPPFLAGS CC="$cc_build" CXX="$cxx_build" CFLAGS="$asan_flags" CXXFLAGS="$asan_flags" ASAN_OPTIONS=detect_leaks=0 make -s -j &&
          env -u LDFLAGS -u CPPFLAGS CC="$cc_build" CXX="$cxx_build" CFLAGS="$asan_flags" CXXFLAGS="$asan_flags" ASAN_OPTIONS=detect_leaks=0 make install); then
      paper_die "mpg123: configure/make/install failed for $variant"
    fi
  else
    if ! (cd "$d" &&
          env -u CFLAGS -u CXXFLAGS -u LDFLAGS -u CPPFLAGS CC="$cc_build" CXX="$cxx_build" "$@" ./configure --prefix="$prefix" --disable-shared --enable-static &&
          env -u CFLAGS -u CXXFLAGS -u LDFLAGS -u CPPFLAGS CC="$cc_build" CXX="$cxx_build" "$@" make -s -j &&
          env -u CFLAGS -u CXXFLAGS -u LDFLAGS -u CPPFLAGS CC="$cc_build" CXX="$cxx_build" "$@" make install); then
      paper_die "mpg123: configure/make/install failed for $variant"
    fi
  fi
  [ -f "$prefix/lib/libmpg123.a" ] || paper_die "mpg123: libmpg123.a not found in $prefix/lib after install"
  [ -f "$prefix/include/mpg123.h" ] || paper_die "mpg123: mpg123.h not found in $prefix/include after install"
}

NEED_MPG123=0
if grep -Rq 'mpg123\.h' "$SRC" 2>/dev/null; then
  NEED_MPG123=1
fi

# build VARIANT CC CXX [ENV=VALUE ...]: build a clean copy of the source. CC/CXX and LDLIBS
# are passed on make's command line (overrides the Makefile's assignments, same effect as the
# reference's `sed -i 's/CC=/CC?=/' Makefile` but without modifying the file).
build() {
  local variant=$1 cc=$2 cxx=$3
  shift 3
  local dir=$W/build-$variant
  rm -rf "$dir"
  cp -a "$SRC" "$dir"
  local -a extra_env=("$@")
  local -a make_vars=()
  if [ "$NEED_MPG123" = 1 ]; then
    # Latest mp3gain needs libmpg123. Build a per-variant static mpg123, then point the
    # compiler at its headers via CC and the linker at the archive via LDLIBS (make
    # command-line overrides; exported CFLAGS/CXXFLAGS/LDFLAGS stay unset).
    build_mpg123 "$variant" "$cc" "$cxx" "$@"
    local prefix=$W/mpg123-$variant
    cc="$cc -I$prefix/include"
    cxx="$cxx -I$prefix/include"
    extra_env+=("PKG_CONFIG_PATH=$prefix/lib/pkgconfig")
    # mp3gain's Makefile uses LIBS for link libraries (not LDLIBS); override both to be safe.
    make_vars+=("LIBS=-L$prefix/lib -lmpg123 -lm" "LDLIBS=-L$prefix/lib -lmpg123 -lm")
  fi
  if ! env -u CFLAGS -u CXXFLAGS -u LDFLAGS -u CPPFLAGS ${extra_env[@]+"${extra_env[@]}"} \
       make -s -j -C "$dir" CC="$cc" CXX="$cxx" ${make_vars[@]+"${make_vars[@]}"}; then
    paper_die "mp3gain: make failed for $variant"
  fi
  [ -f "$dir/mp3gain" ] || paper_die "mp3gain: build did not produce $dir/mp3gain ($variant)"
  cp "$dir/mp3gain" "$OUT/mp3gain.$variant"
}

build afl afl-clang-fast afl-clang-fast++
build cmp afl-clang-fast afl-clang-fast++ AFL_LLVM_CMPLOG=1
# ASan (crash triage): plain clang/clang++ with symbols and frame pointers; leaks disabled.
build asan "clang -g -O1 -fno-omit-frame-pointer -fsanitize=address" \
          "clang++ -g -O1 -fno-omit-frame-pointer -fsanitize=address" \
          ASAN_OPTIONS=detect_leaks=0

paper_finish "$OUT" mp3gain "$V"
