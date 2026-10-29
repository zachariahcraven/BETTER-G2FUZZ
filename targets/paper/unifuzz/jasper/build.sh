#!/bin/bash
# UNIFUZZ jasper (paper: jasper-2.0.12 from unibench; latest: version-4.2.9), built as unibench_build's
# afl/Dockerfile does (cmake + make), three ways: .afl (AFL++), .cmp (CmpLog), .asan (AddressSanitizer).
# Usage (inside builder-unifuzz.sif; targets/paper/build-paper.sh runs it): build.sh paper|latest OUT
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/../../common/lib.sh"
if ! command -v paper_die >/dev/null 2>&1; then
  paper_die() { echo "FAIL: $*" >&2; exit 1; }
fi
V=${1:?paper|latest}; mkdir -p "$2"; OUT=$(cd "$2" && pwd)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
T=imginfo
SRC=$(paper_fetch "$T" "$V" "$W/src")
# paper_fetch may return an archive-expanded folder one level down; find the shallowest CMakeLists.txt
ROOT=""
while IFS= read -r cm; do
  d=$(dirname "$cm")
  if [ -z "$ROOT" ] || [ "${#d}" -lt "${#ROOT}" ]; then
    ROOT=$d
  fi
done < <(find "$SRC" -type f -name CMakeLists.txt)
[ -f "$ROOT/CMakeLists.txt" ] || paper_die "jasper: no CMakeLists.txt under $SRC"
# UNIFUZZ: keep .afl/.cmp free of inherited CFLAGS/CXXFLAGS/LDFLAGS
unset CFLAGS CXXFLAGS LDFLAGS CPPFLAGS

case $V in
  paper)
    # Reference: cmake -DJAS_ENABLE_SHARED=OFF -DALLOW_IN_SOURCE_BUILD=ON . && make
    CM=(-DJAS_ENABLE_SHARED=OFF -DALLOW_IN_SOURCE_BUILD=ON)
    ;;
  latest)
    # Jasper 4.x refuses in-source builds (rule b); disable docs/tests to avoid LaTeX/Doxygen (rule c).
    CM=(-DJAS_ENABLE_SHARED=OFF -DJAS_ENABLE_DOXYGEN=OFF -DBUILD_TESTING=OFF)
    ;;
  *) paper_die "jasper: unknown version $V" ;;
esac

# Toolchain compatibility (judge ruling 2026-10-23): clang 16 rejects old code the reference
# compiler accepted; these flags restore the old diagnostics. Placed in CC/CXX, not CFLAGS/CXXFLAGS.
WNO="-Wno-error=implicit-function-declaration -Wno-error=implicit-int -Wno-error=int-conversion"

for v in afl cmp asan; do
  S="$W/${v}-src"
  mkdir -p "$S"
  cp -a "$ROOT/." "$S/"

  if [ "$V" = paper ]; then
    # In-source build (as the reference does); fresh source copy per variant
    BD="$S"; CS="."
  else
    # Out-of-source (rule b: jasper 4.x refuses in-source)
    BD="$W/${v}-build"; mkdir -p "$BD"; CS="$S"
  fi

  (cd "$BD" && \
    case $v in
      afl)  env CC="afl-clang-fast $WNO" CXX="afl-clang-fast++ $WNO" cmake "$CS" "${CM[@]}" && \
            env CC="afl-clang-fast $WNO" CXX="afl-clang-fast++ $WNO" make -j ;;
      cmp)  env CC="afl-clang-fast $WNO" CXX="afl-clang-fast++ $WNO" AFL_LLVM_CMPLOG=1 cmake "$CS" "${CM[@]}" && \
            env CC="afl-clang-fast $WNO" CXX="afl-clang-fast++ $WNO" AFL_LLVM_CMPLOG=1 make -j ;;
      asan) env CC="clang $WNO" CXX="clang++ $WNO" \
                CFLAGS="-g -O1 -fno-omit-frame-pointer -fsanitize=address" \
                CXXFLAGS="-g -O1 -fno-omit-frame-pointer -fsanitize=address" \
                LDFLAGS="-fsanitize=address" ASAN_OPTIONS=detect_leaks=0 cmake "$CS" "${CM[@]}" && \
            env CC="clang $WNO" CXX="clang++ $WNO" ASAN_OPTIONS=detect_leaks=0 make -j ;;
    esac) || paper_die "jasper $V: $v build failed"

  bin=$(find "$BD" -type f -name "$T" -print -quit)
  [ -n "$bin" ] || paper_die "jasper $V: $v did not produce $T"
  cp -a "$bin" "$OUT/$T.$v"
done

paper_finish "$OUT" "$T" "$V"
