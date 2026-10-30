#!/bin/bash
# UNIFUZZ ffmpeg (paper: ffmpeg-4.0.1 from unibench; latest: n9.0.2), built as unibench_build's
# afl/Dockerfile does (`./configure --disable-shared --cc="$CC" --cxx="$CXX" && make`), three ways:
# .afl (AFL++), .cmp (CmpLog), .asan (AddressSanitizer).
# Usage (inside builder-unifuzz.sif; build/targets/build-paper.sh runs it): build.sh paper|latest OUT
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/../../common/lib.sh"
V=${1:?paper|latest}; mkdir -p "$2"; OUT=$(cd "$2" && pwd)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
T=ffmpeg

AFL_CC=$(command -v afl-clang-fast) || paper_die "$T: afl-clang-fast not found"
AFL_CXX=$(command -v afl-clang-fast++) || paper_die "$T: afl-clang-fast++ not found"
CLANG=$(command -v clang) || paper_die "$T: clang not found"
CLANGPP=$(command -v clang++) || paper_die "$T: clang++ not found"

SRC=$(paper_fetch "$T" "$V" "$W/src")
SRC=${SRC%/}
[ -d "$SRC" ] || paper_die "$T: paper_fetch returned no source folder for $V"
# The unibench archive may extract to a version-named folder (or the fetch may return its parent);
# locate ffmpeg's top-level configure.
if [ ! -f "$SRC/configure" ]; then
  CONF=$(find "$SRC" -maxdepth 3 -type f -name configure -print -quit)
  [ -n "$CONF" ] || paper_die "$T: no configure found under $SRC"
  SRC=$(dirname "$CONF")
fi

# n9.0.2 autodetects optional external libraries; the UNIFUZZ builder does not ship the
# specialized codecs that post-4.0.1 ffmpeg added (kvazaar, rav1e, svtav1, …), so they
# are auto-disabled by configure.  Passing --disable-<lib> for an option the target's
# configure does not recognise is a hard error, so we do not pass any here.

# build VARIANT: clean in-source copy, configure like the reference, make, copy ffmpeg_g.
# Compiler wrappers keep CFLAGS/CXXFLAGS/LDFLAGS unset while applying the variant's compiler
# and (for .asan) the required flags to every compile and link.
build() {
  local variant=$1
  local b="$W/build-$variant" bindir="$W/bin-$variant"
  local jobs=$(nproc 2>/dev/null || echo 1)
  rm -rf "$b" "$bindir"
  cp -a "$SRC" "$b"
  mkdir -p "$bindir"
  case $variant in
    asan)
      printf '%s\n' '#!/bin/sh' "exec \"$CLANG\" -g -O1 -fno-omit-frame-pointer -fsanitize=address \"\$@\"" > "$bindir/cc"
      printf '%s\n' '#!/bin/sh' "exec \"$CLANGPP\" -g -O1 -fno-omit-frame-pointer -fsanitize=address \"\$@\"" > "$bindir/cxx"
      ;;
    *)
      printf '%s\n' '#!/bin/sh' "exec \"$AFL_CC\" \"\$@\"" > "$bindir/cc"
      printf '%s\n' '#!/bin/sh' "exec \"$AFL_CXX\" \"\$@\"" > "$bindir/cxx"
      ;;
  esac
  chmod +x "$bindir/cc" "$bindir/cxx"
  (
    cd "$b"
    unset CC CXX CFLAGS CXXFLAGS LDFLAGS CPPFLAGS LD CROSS_COMPILE AFL_LLVM_CMPLOG
    extra_cfg=""
    case $variant in
      cmp) export AFL_LLVM_CMPLOG=1 ;;
      asan)
        export ASAN_OPTIONS=detect_leaks=0
        # configure compiles and *runs* test binaries for CPU-feature detection;
        # with -fsanitize=address those need the ASan runtime .so at execution time
        asan_so=$("$CLANG" -print-file-name=libclang_rt.asan-x86_64.so 2>/dev/null)
        if [ -f "$asan_so" ]; then
          export LD_LIBRARY_PATH="$(dirname "$asan_so")${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
        fi
        # Toolchain compatibility (paper 4.0.1): the ASan wrapper interferes
        # with configure's x86 feature detection, causing an inconsistent state
        # where config.h references x86-optimized functions but the corresponding
        # source files are never compiled → undefined references at link time.
        # Disable all assembly; the C fallbacks are sufficient for sanitizer
        # builds (crash triage, not performance).
        if [ "$V" = "paper" ]; then
          extra_cfg="--disable-asm"
        fi
        ;;
    esac
    ./configure --disable-shared --cc="$bindir/cc" --cxx="$bindir/cxx" $extra_cfg
    make -j"$jobs" ffmpeg_g
  ) || paper_die "$T $variant: configure or make failed"
  [ -x "$b/ffmpeg_g" ] || paper_die "$T $variant: ffmpeg_g was not built"
  cp "$b/ffmpeg_g" "$OUT/$T.$variant"
  rm -rf "$b" "$bindir"
}

build afl
build cmp
build asan
paper_finish "$OUT" "$T" "$V"
