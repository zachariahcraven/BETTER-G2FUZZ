#!/bin/bash
# UNIFUZZ gdk-pixbuf (paper: gdk-pixbuf-2.31.1 from unibench; latest:2.44.8 = 0bd66153), built as
# unibench_build's afl/Dockerfile does (autotools for paper, meson for latest), three ways:
# .afl (AFL++), .cmp (CmpLog), .asan (AddressSanitizer).
# Usage (inside builder-unifuzz.sif; targets/paper/build-paper.sh runs it): build.sh paper|latest OUT
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/../../common/lib.sh"
V=${1:?paper|latest}; mkdir -p "$2"; OUT=$(cd "$2" && pwd)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
T=gdk-pixbuf-pixdata
SRC=$(paper_fetch "$T" "$V" "$W/src")

if [ "$V" = "paper" ]; then
  # 2.31.1: autotools in-source build, fresh copy per variant (clean tree)
  build() {
    local variant="$1" cc="$2" cxx="$3"; shift 3
    local B="$W/build-$variant"
    cp -a "$SRC" "$B"
    (cd "$B" && env "$@" CC="$cc" CXX="$cxx" \
      ./autogen.sh --enable-static=yes --enable-shared=no --with-included-loaders=yes \
      && make -j)
    cp "$B/gdk-pixbuf/gdk-pixbuf-pixdata" "$OUT/$T.$variant"
  }
  build afl afl-clang-fast afl-clang-fast++
  build cmp afl-clang-fast afl-clang-fast++ AFL_LLVM_CMPLOG=1
  build asan clang clang++ \
    ASAN_OPTIONS=detect_leaks=0 \
    CFLAGS="-g -O1 -fno-omit-frame-pointer -fsanitize=address" \
    CXXFLAGS="-g -O1 -fno-omit-frame-pointer -fsanitize=address" \
    LDFLAGS="-fsanitize=address"
else
  # 2.44.8: meson out-of-source build (no autotools), fresh build dir per variant
  # builder has meson 0.61.2; 2.44.8 requires >= 1.5. Use the pinned tarball.
  export PAPER_RECIPE="unifuzz-meson-equivalent"
  python3 -c "import urllib.request; urllib.request.urlretrieve('https://github.com/mesonbuild/meson/releases/download/1.5.2/meson-1.5.2.tar.gz', '$W/meson.tar.gz')"
  echo "f955e09ab0d71ef180ae85df65991d58ed8430323de7d77a37e11c9ea630910b  $W/meson.tar.gz" | sha256sum -c -
  tar xf "$W/meson.tar.gz" -C "$W"
  MESON="$W/meson-1.5.2/meson.py"
  build() {
    local variant="$1" cc="$2" cxx="$3"; shift 3
    local B="$W/build-$variant"
    env "$@" CC="$cc" CXX="$cxx" python3 "$MESON" setup "$B" "$SRC" \
      -Ddefault_library=static -Dbuiltin_loaders=all -Dothers=enabled \
      -Dpng=enabled -Djpeg=enabled -Dtiff=enabled -Dgif=enabled \
      -Dglycin=disabled -Dthumbnailer=disabled \
      -Ddocumentation=false -Dman=false -Dintrospection=disabled \
      -Dtests=false -Dinstalled_tests=false \
      -Dgio_sniffing=false
    env "$@" CC="$cc" CXX="$cxx" ninja -C "$B"
    cp "$B/gdk-pixbuf/gdk-pixbuf-pixdata" "$OUT/$T.$variant"
  }
  build afl afl-clang-fast afl-clang-fast++
  build cmp afl-clang-fast afl-clang-fast++ AFL_LLVM_CMPLOG=1
  build asan clang clang++ \
    ASAN_OPTIONS=detect_leaks=0 \
    CFLAGS="-g -O1 -fno-omit-frame-pointer -fsanitize=address" \
    CXXFLAGS="-g -O1 -fno-omit-frame-pointer -fsanitize=address" \
    LDFLAGS="-fsanitize=address"
fi

paper_finish "$OUT" "$T" "$V"
