#!/bin/bash
# FUZZBENCH harfbuzz (paper: pin from manifest; latest: 14.6.0), built as the FuzzBench harfbuzz
# project's reference build does: meson static harfbuzz, then the hb-shape-fuzzer harness.
# Usage (inside builder-fuzzbench.sif; build/targets/build-paper.sh runs it): build.sh paper|latest OUT
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/../../common/lib.sh"

VERSION="${1:?usage: build.sh paper|latest OUT}"
OUT="${2:?usage: build.sh paper|latest OUT}"
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
T=harfbuzz_hb-shape-fuzzer

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

SRC=$(paper_fetch "$T" "$VERSION" "$WORK/harfbuzz")

# Find the meson options file (name differs between meson versions).
OPTS_FILE=""
for f in "$SRC/meson_options.txt" "$SRC/meson.options"; do
  [ -f "$f" ] && { OPTS_FILE="$f"; break; }
done
[ -n "$OPTS_FILE" ] || paper_die "cannot find meson_options.txt or meson.options in $SRC"

# Disable optional features the reference image did not have.
WANT_DISABLED=()
DISABLE_ARGS=()
for opt in freetype glib gobject cairo icu graphite graphite2 chafa; do
  if grep -qw "$opt" "$OPTS_FILE"; then
    WANT_DISABLED+=("$opt")
    DISABLE_ARGS+=("-D${opt}=disabled")
  fi
done

FB_CFLAGS="-DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION -pthread -Wl,--no-as-needed -Wl,-ldl -Wl,-lm -Wno-unused-command-line-argument"

build_variant() {
  variant=$1
  B="$WORK/build-$variant"
  mkdir -p "$B"
  (
    cd "$SRC"
    case $variant in
      afl|cmp)
        export CC=afl-clang-fast CXX=afl-clang-fast++
        export CFLAGS="$FB_CFLAGS -O3 -DHB_NO_VISIBILITY"
        export CXXFLAGS="$FB_CFLAGS -stdlib=libc++ -O3 -DHB_NO_VISIBILITY"
        unset LDFLAGS
        engine="-fsanitize=fuzzer"
        ;;
      asan)
        export CC=clang CXX=clang++
        export CFLAGS="$FB_CFLAGS -g -O1 -fno-omit-frame-pointer -fsanitize=address -DHB_NO_VISIBILITY"
        export CXXFLAGS="$FB_CFLAGS -g -O1 -fno-omit-frame-pointer -fsanitize=address -DHB_NO_VISIBILITY"
        export LDFLAGS="-g -O1 -fno-omit-frame-pointer -fsanitize=address"
        export ASAN_OPTIONS=detect_leaks=0
        engine="-fsanitize=fuzzer,address"
        ;;
      *)
        paper_die "internal: bad variant $variant"
        ;;
    esac
    if [ "$variant" = cmp ]; then
      export AFL_LLVM_CMPLOG=1
    else
      unset AFL_LLVM_CMPLOG
    fi

    meson_out=$(meson setup "${DISABLE_ARGS[@]}" \
      --default-library=static --wrap-mode=nodownload \
      -Dexperimental_api=true \
      -Dfuzzer_ldflags="$engine" \
      "$B" 2>&1) || { echo "$meson_out" >&2; paper_die "meson setup failed for $variant"; }

    # Verify no optional feature slipped through as enabled. Meson prints a dependency
    # it is not building as "NO", a feature option as "disabled"/"not found"; a version
    # string, "YES" or "enabled" means it is actually on, in which case we must stop.
    for opt in "${WANT_DISABLED[@]}"; do
      line=$(echo "$meson_out" | grep -iE "^[[:space:]]*${opt}[[:space:]]*:" | head -1 || true)
      [ -n "$line" ] || continue
      val=$(echo "$line" | sed 's/^[^:]*:[[:space:]]*//' | sed 's/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')
      case $val in
        ''|no|disabled|false|'not found')
          ;;
        *)
          paper_die "meson summary reports $opt as enabled for $variant: $line"
          ;;
      esac
    done

    ninja -v -j"$(nproc)" -C "$B" test/fuzzing/hb-shape-fuzzer \
      || paper_die "ninja build of test/fuzzing/hb-shape-fuzzer failed for $variant"
    cp "$B/test/fuzzing/hb-shape-fuzzer" "$OUT/$T.$variant"
  )
}

build_variant afl
build_variant cmp
build_variant asan

# Seeds: copy top-level files from the reference's font directories.
seed_dir="$OUT/seeds/$T"
rm -rf "$seed_dir"
mkdir -p "$seed_dir"
for d in \
    test/shape/data/in-house/fonts \
    test/shape/data/aots/fonts \
    test/shape/data/text-rendering-tests/fonts \
    test/api/fonts \
    test/fuzzing/fonts \
    perf/fonts \
    ; do
  [ -d "$SRC/$d" ] || paper_die "seed folder not found: $SRC/$d"
  for f in "$SRC/$d"/*; do
    [ -f "$f" ] || continue
    [ "$(stat -c%s "$f")" -le 1048576 ] || continue
    cp "$f" "$seed_dir/"
  done
done
if [ -z "$(ls -A "$seed_dir" 2>/dev/null)" ]; then
  paper_die "no seed files copied from: test/shape/data/in-house/fonts test/shape/data/aots/fonts test/shape/data/text-rendering-tests/fonts test/api/fonts test/fuzzing/fonts perf/fonts"
fi

paper_finish "$OUT" "$T" "$VERSION"
