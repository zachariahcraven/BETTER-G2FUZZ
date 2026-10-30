#!/bin/bash
# MAGMA libpng (paper only; latest rows are out of scope, 2026-10-22):
# libpng_read_fuzzer built three ways (.afl, .cmp, .asan) with MAGMA canaries,
# following MAGMA v1.2's targets/libpng/build.sh.
# Usage (inside builder-magma-libpng.sif; build/targets/build-paper.sh runs it): build.sh paper OUT
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/../../common/lib.sh"

V=${1:?usage: build.sh paper|latest OUT}
OUT=${2:?usage: build.sh paper|latest OUT}
[ "$V" = paper ] || paper_die "MAGMA latest rows are not built"
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)

T=libpng_read_fuzzer
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
MAGMA="$PAPER_REF/magma/magma"
LIB="$PAPER_REF/magma/targets/libpng"

SRC=$(paper_fetch "$T" "$V" "$W/src")
if [ -f "$SRC/scripts/pnglibconf.dfa" ]; then
  LIBPNG_DIR=$SRC
elif [ -f "$SRC/libpng/scripts/pnglibconf.dfa" ]; then
  LIBPNG_DIR=$SRC/libpng
else
  paper_die "cannot find libpng's scripts/pnglibconf.dfa in fetched source $SRC"
fi

# Build GNU patch 2.7.6 (git apply is too strict for MAGMA's patches that rely on patch's fuzz).
# Use the locally vendored copy first (judge ruling 2026-10-23 02:20); download only if missing.
PATCH_SHA256="ac610bda97abe0d9f6b7c963255a11dcb196c25e337c61f94e4778d632f1d8fd"
PATCH_TAR="$PAPER_REF/tools/patch-2.7.6.tar.xz"
if [ -f "$PATCH_TAR" ]; then
  echo "$PATCH_SHA256  $PATCH_TAR" | (cd "$W" && sha256sum -c -) \
    || paper_die "vendored patch-2.7.6.tar.xz sha256 mismatch"
  cp "$PATCH_TAR" "$W/patch-2.7.6.tar.xz"
else
  PATCH_URLS=(
    "https://ftp.gnu.org/gnu/patch/patch-2.7.6.tar.xz"
    "https://mirrors.kernel.org/gnu/patch/patch-2.7.6.tar.xz"
  )
  patch_ok=""
  for PATCH_URL in "${PATCH_URLS[@]}"; do
    if command -v curl >/dev/null 2>&1; then
      curl -fsSL -o "$W/patch-2.7.6.tar.xz" "$PATCH_URL" && { patch_ok=1; break; }
    elif command -v wget >/dev/null 2>&1; then
      wget -q -O "$W/patch-2.7.6.tar.xz" "$PATCH_URL" && { patch_ok=1; break; }
    elif command -v python3 >/dev/null 2>&1; then
      python3 -c "import urllib.request,sys; urllib.request.urlretrieve(sys.argv[1],sys.argv[2])" "$PATCH_URL" "$W/patch-2.7.6.tar.xz" && { patch_ok=1; break; }
    fi
  done
  [ -n "$patch_ok" ] || paper_die "patch-2.7.6.tar.xz not found locally and download failed"
  echo "$PATCH_SHA256  $W/patch-2.7.6.tar.xz" | sha256sum -c - \
    || paper_die "downloaded patch-2.7.6.tar.xz sha256 mismatch"
fi
(cd "$W" && tar xf patch-2.7.6.tar.xz) \
  || paper_die "patch-2.7.6.tar.xz extract failed"
(cd "$W/patch-2.7.6" && ./configure --prefix="$W/patch" && make -j"$(nproc)" && make install) \
  || paper_die "GNU patch 2.7.6 build failed"

# %MAGMA_BUG% = patch name without .patch (the canary bug ID); setup/ then bugs/, each sorted
apply_patches() {
  local tree=$1
  local patch
  while IFS= read -r patch; do
    sed "s/%MAGMA_BUG%/$(basename "$patch" .patch)/g" "$patch" \
      | "$W/patch/bin/patch" -p1 -d "$tree" \
      || paper_die "MAGMA patch failed: $(basename "$patch")"
  done < <(
    find "$LIB/patches/setup" -name '*.patch' | sort
    find "$LIB/patches/bugs" -name '*.patch' | sort
  )
}

build_variant() {
  local variant=$1
  local B="$W/build-$variant"
  mkdir -p "$B"
  cp -a "$LIBPNG_DIR/." "$B/"
  apply_patches "$B"

  local cc cxx cflags cxxflags ldflags libs
  case $variant in
    afl|cmp)
      cc=afl-clang-fast
      cxx=afl-clang-fast++
      cflags="-include $MAGMA/src/canary.h -DMAGMA_ENABLE_CANARIES -g -O0"
      cxxflags="-include $MAGMA/src/canary.h -DMAGMA_ENABLE_CANARIES -g -O0 -stdlib=libc++"
      ldflags="-g"
      libs="-lrt -lc++ -lc++abi /usr/local/lib/afl/libAFLDriver.a"
      ;;
    asan)
      cc=clang
      cxx=clang++
      cflags="-include $MAGMA/src/canary.h -DMAGMA_ENABLE_CANARIES -g -O1 -fno-omit-frame-pointer -fsanitize=address"
      cxxflags="-include $MAGMA/src/canary.h -DMAGMA_ENABLE_CANARIES -g -O1 -fno-omit-frame-pointer -fsanitize=address"
      ldflags="-g -fsanitize=address"
      libs="-lrt -fsanitize=fuzzer,address"
      ;;
    *)
      paper_die "internal: bad variant $variant"
      ;;
  esac
  export CC=$cc CXX=$cxx CFLAGS=$cflags CXXFLAGS=$cxxflags LDFLAGS=$ldflags
  [ "$variant" = cmp ] && export AFL_LLVM_CMPLOG=1
  [ "$variant" = asan ] && export ASAN_OPTIONS=detect_leaks=0

  (
    cd "$B"
    autoreconf -f -i || paper_die "autoreconf failed for $variant"
    ./configure --with-libpng-prefix=MAGMA_ --disable-shared || paper_die "configure failed for $variant"
    make -j"$(nproc)" clean 2>/dev/null || true
    # Build magma.o after make clean so it is not removed before the final link
    $cc $cflags -D"MAGMA_STORAGE=\"/magma_shared/canaries.raw\"" \
      -c "$MAGMA/src/canary.c" -fPIC -I "$MAGMA/src" -o canary.o \
      || paper_die "building canary.o failed for $variant"
    $cc $cflags -D"MAGMA_STORAGE=\"/magma_shared/canaries.raw\"" \
      -c "$MAGMA/src/storage.c" -fPIC -I "$MAGMA/src" -o storage.o \
      || paper_die "building storage.o failed for $variant"
    ld -r canary.o storage.o -o magma.o \
      || paper_die "linking magma.o failed for $variant"
    make -j"$(nproc)" libpng16.la || paper_die "make libpng16.la failed for $variant"
    $cxx $cxxflags -std=c++11 -I. contrib/oss-fuzz/libpng_read_fuzzer.cc \
      -o "$OUT/$T.$variant" $ldflags .libs/libpng16.a magma.o $libs -lz \
      || paper_die "linking $T.$variant failed"
  )

  unset AFL_LLVM_CMPLOG ASAN_OPTIONS
}

build_variant afl
build_variant cmp
build_variant asan

paper_finish "$OUT" "$T" "$V"
