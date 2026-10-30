#!/bin/bash
# FUZZBENCH freetype2 (paper: freetype2 pin from the manifest; latest: VER-2-15-0), built as
# fuzzbench's freetype2 build.sh does, three ways: .afl (AFL++), .cmp (CmpLog), .asan (AddressSanitizer).
# Usage (inside builder-fuzzbench.sif; build/targets/build-paper.sh runs it): build.sh paper|latest OUT
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/../../common/lib.sh"

V=${1:?usage: build.sh paper|latest OUT}
OUT=${2:?usage: build.sh paper|latest OUT}
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
T=freetype2_ftfuzzer
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
FB_CFLAGS="-DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION -pthread -Wl,--no-as-needed -Wl,-ldl -Wl,-lm -Wno-unused-command-line-argument"

# --- Fetch freetype2 source ---
SRC=$(paper_fetch "$T" "$V" "$W/src")
if [ "$V" = "latest" ]; then
  FT_LATEST_HARNESS="$HERE/ftfuzzer-latest.cc"
  [ -f "$FT_LATEST_HARNESS" ] || paper_die "freetype2 latest: $FT_LATEST_HARNESS not found"
  echo "f7ff85c427a34caf4d244f45e0df152a764727fac9972b5b07529f105d620947  $FT_LATEST_HARNESS" | sha256sum -c - || paper_die "freetype2 latest: ftfuzzer-latest.cc sha256 mismatch"
  HARNESS_SRC="$FT_LATEST_HARNESS"
  FT_DIR=$(find "$SRC" -name autogen.sh -print -quit 2>/dev/null)
  FT_DIR=$(cd "$(dirname "$FT_DIR")" && pwd)
else
  HARNESS_SRC="src/tools/ftfuzzer/ftfuzzer.cc"
  FT_HARNESS=$(find "$SRC" -path "*/src/tools/ftfuzzer/ftfuzzer.cc" -print -quit 2>/dev/null)
  [ -n "$FT_HARNESS" ] || paper_die "freetype2: cannot find src/tools/ftfuzzer/ftfuzzer.cc under $SRC"
  FT_DIR=$(cd "$(dirname "$FT_HARNESS")/../../.." && pwd)
fi
[ -x "$FT_DIR/autogen.sh" ] || paper_die "freetype2 $FT_DIR: missing autogen.sh"

# --- Fetch and verify libarchive 3.4.3 ---
LIBARCHIVE_URL="https://github.com/libarchive/libarchive/releases/download/v3.4.3/libarchive-3.4.3.tar.xz"
LIBARCHIVE_SHA="0bfc3fd40491768a88af8d9b86bf04a9e95b6d41a94f9292dbc0ec342288c05f"
wget -q "$LIBARCHIVE_URL" -O "$W/libarchive-3.4.3.tar.xz"
echo "$LIBARCHIVE_SHA  $W/libarchive-3.4.3.tar.xz" | sha256sum -c - || paper_die "libarchive-3.4.3 sha256 mismatch"
tar xf "$W/libarchive-3.4.3.tar.xz" -C "$W"

# --- Fetch and verify TRT (text-rendering-tests) ---
TRT_COMMIT="9b451da98971b0042f6c28d5a96d623f8a3c853b"
git clone -q https://github.com/unicode-org/text-rendering-tests.git "$W/TRT"
git -C "$W/TRT" checkout -q "$TRT_COMMIT"
[ "$(git -C "$W/TRT" rev-parse HEAD)" = "$TRT_COMMIT" ] || paper_die "TRT commit mismatch"

build_variant() {
  local variant=$1
  local cc cxx cflags cxxflags engine
  local B="$W/build-$variant"
  local LA_SRC="$W/libarchive-src-$variant"
  local LA_PREFIX="$W/libarchive-prefix-$variant"
  mkdir -p "$B" "$LA_PREFIX"

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
      engine="-fsanitize=fuzzer,address"
      ;;
    *)
      paper_die "internal: bad variant $variant"
      ;;
  esac

  # --- Build libarchive (static, per-variant prefix) ---
  cp -a "$W/libarchive-3.4.3/." "$LA_SRC/"
  (
    cd "$LA_SRC"
    export CC=$cc CXX=$cxx
    export CFLAGS=$cflags CXXFLAGS=$cxxflags
    if [ "$variant" = asan ]; then
      export LDFLAGS="-g -O1 -fno-omit-frame-pointer -fsanitize=address"
    else
      unset LDFLAGS
    fi
    if [ "$variant" = cmp ]; then export AFL_LLVM_CMPLOG=1; fi
    if [ "$variant" = asan ]; then export ASAN_OPTIONS=detect_leaks=0; fi
    ./configure --disable-shared --prefix="$LA_PREFIX" || paper_die "libarchive configure failed for $variant"
    make clean || paper_die "libarchive make clean failed for $variant"
    make -j"$(nproc)" || paper_die "libarchive make failed for $variant"
    make install || paper_die "libarchive make install failed for $variant"
  )

  local la_static_libs
  la_static_libs=$(PKG_CONFIG_PATH="$LA_PREFIX/lib/pkgconfig" pkg-config --static --libs libarchive)

  # --- Build freetype2 and the harness ---
  cp -a "$FT_DIR/." "$B/"
  (
    cd "$B"
    export CC=$cc CXX=$cxx
    export CFLAGS=$cflags CXXFLAGS=$cxxflags
    if [ "$variant" = asan ]; then
      export LDFLAGS="-g -O1 -fno-omit-frame-pointer -fsanitize=address"
    else
      unset LDFLAGS
    fi
    if [ "$variant" = cmp ]; then export AFL_LLVM_CMPLOG=1; fi
    if [ "$variant" = asan ]; then export ASAN_OPTIONS=detect_leaks=0; fi
    ./autogen.sh || paper_die "freetype2 autogen.sh failed for $variant"
    ./configure --with-harfbuzz=no --with-bzip2=no --with-png=no --without-zlib || paper_die "freetype2 configure failed for $variant"
    make clean || paper_die "freetype2 make clean failed for $variant"
    make all -j"$(nproc)" || paper_die "freetype2 make all failed for $variant"
    $cxx $cxxflags -std=c++11 -I include -I . -I "$LA_PREFIX/include" "$HARNESS_SRC" \
      objs/.libs/libfreetype.a \
      $la_static_libs \
      $engine \
      -o "$OUT/$T.$variant" || paper_die "linking $T.$variant failed"
  )
}

build_variant afl
build_variant cmp
build_variant asan

# --- Seeds ---
seed_dir="$OUT/seeds/$T"
rm -rf "$seed_dir"
mkdir -p "$seed_dir"
cp "$W/TRT/fonts/TestKERNOne.otf" "$seed_dir/"
cp "$W/TRT/fonts/TestGLYFOne.ttf" "$seed_dir/"

if [ "$V" = "latest" ]; then
  export PAPER_RECIPE="fuzzbench+harness:freetype2-testing@db8ae87fead2ede5487e242dd9f5a129ca5e9fd2"
fi
paper_finish "$OUT" "$T" "$V"
