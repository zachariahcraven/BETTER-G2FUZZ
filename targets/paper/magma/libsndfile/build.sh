#!/bin/bash
# MAGMA libsndfile (paper), built three ways: .afl (AFL++), .cmp (CmpLog), .asan (AddressSanitizer).
# Usage (inside builder-magma-libsndfile.sif; targets/paper/build-paper.sh runs it): build.sh paper OUT
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/../../common/lib.sh"

V=${1:?usage: build.sh paper|latest OUT}
OUT=${2:?usage: build.sh paper|latest OUT}
[ "$V" = latest ] && paper_die "MAGMA latest rows are not built"

mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
T=sndfile_fuzzer
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
die() { echo "FAIL  $*" >&2; exit 1; }

MAGMA="$PAPER_REF/magma/magma"

SRC=$(paper_fetch "$T" "$V" "$W/src")

# Build GNU patch 2.7.6 (no patch in the builder image; MAGMA patches rely on patch's fuzz)
PATCH_VER=2.7.6
PATCH_SHA=ac610bda97abe0d9f6b7c963255a11dcb196c25e337c61f94e4778d632f1d8fd
wget -q "https://ftp.gnu.org/gnu/patch/patch-${PATCH_VER}.tar.xz" -O "$W/patch.tar.xz" \
  || wget -q "https://mirrors.kernel.org/gnu/patch/patch-${PATCH_VER}.tar.xz" -O "$W/patch.tar.xz" \
  || die "cannot download patch-${PATCH_VER}.tar.xz"
echo "$PATCH_SHA  $W/patch.tar.xz" | sha256sum -c - || die "patch tarball sha256 mismatch"
tar -xf "$W/patch.tar.xz" -C "$W"
(
  cd "$W/patch-${PATCH_VER}"
  ./configure --prefix="$W/patch" >/dev/null 2>&1 || die "patch configure failed"
  make -j"$(nproc)" >/dev/null 2>&1 || die "patch make failed"
  make install >/dev/null 2>&1 || die "patch make install failed"
)

# Apply MAGMA patches (setup then bugs, exactly as magma/apply_patches.sh does)
# setup/ first, then bugs/ (each sorted); %MAGMA_BUG% = the patch name without .patch (the canary's bug ID)
for d in setup bugs; do
  for p in $(find "$PAPER_REF/magma/targets/libsndfile/patches/$d" -name "*.patch" 2>/dev/null | sort); do
    pname=$(basename "$p" .patch)
    sed "s/%MAGMA_BUG%/$pname/g" "$p" | "$W/patch/bin/patch" -p1 -d "$SRC" || die "patch $pname failed"
  done
done

build_variant() {
  local variant=$1
  local cc cxx cflags cxxflags ldflags libs
  local B="$W/build-$variant"
  mkdir -p "$B"
  cp -a "$SRC/." "$B/"

  case $variant in
    afl|cmp)
      cc=afl-clang-fast
      cxx=afl-clang-fast++
      cflags="-include $MAGMA/src/canary.h -DMAGMA_ENABLE_CANARIES -g -O0"
      cxxflags="-include $MAGMA/src/canary.h -DMAGMA_ENABLE_CANARIES -g -O0 -stdlib=libc++"
      libs="-l:magma.o -lrt -lc++ -lc++abi /usr/local/lib/afl/libAFLDriver.a"
      ldflags="-L$B -g"
      ;;
    asan)
      cc=clang
      cxx=clang++
      cflags="-include $MAGMA/src/canary.h -DMAGMA_ENABLE_CANARIES -g -O1 -fno-omit-frame-pointer -fsanitize=address"
      cxxflags="-include $MAGMA/src/canary.h -DMAGMA_ENABLE_CANARIES -g -O1 -fno-omit-frame-pointer -fsanitize=address"
      libs="-l:magma.o -lrt"
      ldflags="-L$B -g -fsanitize=address"
      ;;
    *)
      die "internal: bad variant $variant"
      ;;
  esac

  # Build magma.o for this variant
  $cc $cflags -D"MAGMA_STORAGE=\"/magma_shared/canaries.raw\"" -c "$MAGMA/src/canary.c" -fPIC -I "$MAGMA/src" -o "$B/canary.o" \
    || die "compiling canary.c failed for $variant"
  $cc $cflags -D"MAGMA_STORAGE=\"/magma_shared/canaries.raw\"" -c "$MAGMA/src/storage.c" -fPIC -I "$MAGMA/src" -o "$B/storage.o" \
    || die "compiling storage.c failed for $variant"
  ld -r "$B/canary.o" "$B/storage.o" -o "$B/magma.o" \
    || die "linking magma.o failed for $variant"

  (
    cd "$B"
    export CC=$cc CXX=$cxx CFLAGS=$cflags CXXFLAGS=$cxxflags
    export LIBS="$libs"
    export LDFLAGS="$ldflags"
    if [ "$variant" = asan ]; then
      export LIB_FUZZING_ENGINE="-fsanitize=fuzzer,address"
      export ASAN_OPTIONS=detect_leaks=0
    fi
    if [ "$variant" = cmp ]; then
      export AFL_LLVM_CMPLOG=1
    fi

    ./autogen.sh || die "./autogen.sh failed for $variant"
    ./configure --disable-shared --enable-ossfuzzers || die "configure failed for $variant"
    make -j"$(nproc)" ossfuzz/sndfile_fuzzer || die "make ossfuzz/sndfile_fuzzer failed for $variant"
  )

  cp "$B/ossfuzz/sndfile_fuzzer" "$OUT/$T.$variant"
}

build_variant afl
build_variant cmp
build_variant asan

paper_finish "$OUT" "$T" "$V"
