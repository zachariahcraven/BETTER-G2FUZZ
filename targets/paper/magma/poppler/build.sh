#!/bin/bash
# MAGMA poppler (paper), built as MAGMA's targets/poppler/build.sh does, three ways: .afl (AFL++), .cmp (CmpLog), .asan (AddressSanitizer).
# Usage (inside builder-magma-poppler.sif; targets/paper/build-paper.sh runs it): build.sh paper OUT
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/../../common/lib.sh"

V=${1:?usage: build.sh paper OUT}
OUT=${2:?usage: build.sh paper OUT}
[ "$V" = "latest" ] && paper_die "MAGMA latest rows are not built"
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
MAGMA="$PAPER_REF/magma/magma"
LIB=poppler
FT_COMMIT=50d0033f7ee600c5f5831b28877353769d1f7d48

# --- Fetch sources ---
SRC=$(paper_fetch pdf_fuzzer "$V" "$W/src")

# Freetype: MAGMA's fetch.sh pins it at FT_COMMIT; fetch if not already present from paper_fetch
FT_SRC=""
for d in "$SRC/freetype" "$W/src/freetype" "$W/freetype"; do
  if [ -f "$d/builds/unix/configure.ac" ] || [ -f "$d/configure.ac" ]; then
    FT_SRC=$d; break
  fi
done
if [ -z "$FT_SRC" ]; then
  FT_SRC="$W/freetype-orig"
  git clone --quiet "https://github.com/freetype/freetype.git" "$FT_SRC" \
    || paper_die "cannot clone freetype"
  git -C "$FT_SRC" checkout --quiet "$FT_COMMIT" \
    || paper_die "cannot checkout freetype at $FT_COMMIT"
fi

# --- Build GNU patch 2.7.6 (judge ruling 2026-10-23 01:50: git apply is too strict;
#     MAGMA's patches rely on patch's fuzz. Build with plain gcc — it is a tool, not the target) ---
PATCH_SHA256="ac610bda97abe0d9f6b7c963255a11dcb196c25e337c61f94e4778d632f1d8fd"
PATCH_TAR="$PAPER_REF/tools/patch-2.7.6.tar.xz"
if [ ! -f "$PATCH_TAR" ]; then
  PATCH_TAR="$W/patch-2.7.6.tar.xz"
  curl -fsSL -o "$PATCH_TAR" "https://ftp.gnu.org/gnu/patch/patch-2.7.6.tar.xz" 2>/dev/null || \
    curl -fsSL -o "$PATCH_TAR" "https://mirrors.kernel.org/gnu/patch/patch-2.7.6.tar.xz" 2>/dev/null || \
    paper_die "cannot download patch-2.7.6"
fi
echo "$PATCH_SHA256  $PATCH_TAR" | sha256sum -c - || paper_die "patch-2.7.6 sha256 mismatch"
tar -xf "$PATCH_TAR" -C "$W"
(
  cd "$W/patch-2.7.6"
  ./configure --prefix="$W/patch" && make -j"$(nproc)" && make install
) || paper_die "building GNU patch 2.7.6 failed"

# --- wget stand-in (judge ruling 02:20): autogen.sh may download config.guess/config.sub
#     from the network (unpinned, fails offline). Copy the builder's automake copies
#     instead. Platform detection only. ---
mkdir -p "$W/bin"
cat > "$W/bin/wget" <<'WGETEOF'
#!/bin/bash
out=""
i=1
while [ "$i" -le "$#" ]; do
  arg="${!i}"
  if [ "$arg" = "-O" ]; then
    i=$((i+1)); out="${!i}"
  fi
  i=$((i+1))
done
[ -n "$out" ] || { echo "wget stand-in: no -O argument" >&2; exit 1; }
case "$(basename "$out")" in
  config.guess) src=$(ls /usr/share/automake-*/config.guess 2>/dev/null | head -1) ;;
  config.sub)   src=$(ls /usr/share/automake-*/config.sub 2>/dev/null | head -1) ;;
  *) echo "wget stand-in: only config.guess/config.sub supported" >&2; exit 1 ;;
esac
[ -n "$src" ] && [ -f "$src" ] || { echo "wget stand-in: no automake copy" >&2; exit 1; }
cp "$src" "$out"
WGETEOF
chmod +x "$W/bin/wget"

# --- Apply MAGMA patches to a base tree (setup patches, then bug patches) ---
BASE="$W/base"
cp -a "$SRC" "$BASE"
apply_magma_patches() {
  local tree=$1
  local p
  # judge ruling 2026-10-23 01:50: use GNU patch (fuzz-tolerant) as magma/apply_patches.sh does
  for p in $(find "$PAPER_REF/magma/targets/$LIB/patches/setup" -name '*.patch' 2>/dev/null | sort); do
    pname=$(basename "$p" .patch)
    sed "s/%MAGMA_BUG%/$pname/g" "$p" | "$W/patch/bin/patch" -p1 -d "$tree" \
      || paper_die "MAGMA setup patch failed: $p"
  done
  for p in $(find "$PAPER_REF/magma/targets/$LIB/patches/bugs" -name '*.patch' 2>/dev/null | sort); do
    pname=$(basename "$p" .patch)
    sed "s/%MAGMA_BUG%/$pname/g" "$p" | "$W/patch/bin/patch" -p1 -d "$tree" \
      || paper_die "MAGMA bug patch failed: $p"
  done
}
apply_magma_patches "$BASE"

# --- Build one variant (afl | cmp | asan) ---
build_variant() {
  local variant=$1
  local B="$W/build-$variant"
  cp -a "$BASE" "$B"
  (
    cd "$B"

    local CC CXX CFLAGS CXXFLAGS LDFLAGS LIBS MAGMA_LIBS
    local FT_INSTALL="$W/ft-install-$variant"
    local FT_BUILD="$W/ft-build-$variant"

    case $variant in
      afl|cmp)
        CC=afl-clang-fast
        CXX=afl-clang-fast++
        CFLAGS="-include $MAGMA/src/canary.h -DMAGMA_ENABLE_CANARIES -g -O0"
        CXXFLAGS="$CFLAGS -stdlib=libc++"
        MAGMA_LIBS="-l:magma.o -lrt"
        LIBS="$MAGMA_LIBS -lc++ -lc++abi /usr/local/lib/afl/libAFLDriver.a"
        LDFLAGS="-L$B -g"
        ;;
      asan)
        CC=clang
        CXX=clang++
        CFLAGS="-include $MAGMA/src/canary.h -DMAGMA_ENABLE_CANARIES -g -O1 -fno-omit-frame-pointer -fsanitize=address"
        CXXFLAGS="$CFLAGS"
        MAGMA_LIBS="-l:magma.o -lrt"
        LIBS="$MAGMA_LIBS"
        LDFLAGS="-L$B -g -fsanitize=address"
        ;;
      *)
        paper_die "internal: bad variant $variant"
        ;;
    esac

    # CmpLog for .cmp (applies to magma.o compilation too)
    if [ "$variant" = cmp ]; then export AFL_LLVM_CMPLOG=1; else unset AFL_LLVM_CMPLOG; fi
    export ASAN_OPTIONS=detect_leaks=0
    export CC CXX CFLAGS CXXFLAGS LDFLAGS

    # --- Build magma.o into the variant dir ---
    local CT="$W/canary-tmp-$variant"
    mkdir -p "$CT"
    $CC $CFLAGS -D'MAGMA_STORAGE="/magma_shared/canaries.raw"' \
      -c "$MAGMA/src/canary.c" -fPIC -I "$MAGMA/src" -o "$CT/canary.o" \
      || paper_die "magma canary.c compile failed ($variant)"
    $CC $CFLAGS -D'MAGMA_STORAGE="/magma_shared/canaries.raw"' \
      -c "$MAGMA/src/storage.c" -fPIC -I "$MAGMA/src" -o "$CT/storage.o" \
      || paper_die "magma storage.c compile failed ($variant)"
    ld -r "$CT/canary.o" "$CT/storage.o" -o "$B/magma.o" \
      || paper_die "magma.o link failed ($variant)"

    # --- Build freetype (static, as MAGMA's targets/poppler/build.sh does) ---
    rm -rf "$FT_BUILD" "$FT_INSTALL"
    cp -a "$FT_SRC" "$FT_BUILD"
    mkdir -p "$FT_INSTALL"
    (
      cd "$FT_BUILD"
      PATH="$W/bin:$PATH" ./autogen.sh || paper_die "freetype autogen.sh failed ($variant)"
      # --with-brotli=no (rule c, 2026-10-23): MAGMA's older-Ubuntu poppler image had no libbrotli; our builder's
      # libcairo2-dev pulls it in, so freetype would add WOFF2/Brotli and poppler's links would miss -lbrotlidec.
      ./configure --prefix="$FT_INSTALL" --disable-shared --with-brotli=no \
        PKG_CONFIG_PATH="$FT_INSTALL/lib/pkgconfig" \
        || paper_die "freetype configure failed ($variant)"
      make -j"$(nproc)" || paper_die "freetype make failed ($variant)"
      make install || paper_die "freetype install failed ($variant)"
    )

    # --- Build poppler with cmake (MAGMA's options verbatim, paths adapted) ---
    local PB="$B/build"
    mkdir -p "$PB"
    # -L$B is added to CMAKE_EXE_LINKER_FLAGS_INIT because CMake's INIT overrides
    # the environment LDFLAGS; without it, every link-based check (strtok_r, dirent,
    # iconv, ...) fails to find magma.o and poppler falls back to its own stubs.
    (
      cd "$PB"
      # Toolchain compatibility (judge, 2026-10-23): AFL++ 4.32c/5.03c libAFLDriver.a has a main that needs
      # LLVMFuzzerTestOneInput, so in CMAKE_EXE_LINKER_FLAGS_INIT it breaks every CMake link check (HAVE_DIRENT_H
      # came out false). It stays out of the check/link flags here and is linked into pdf_fuzzer below ($LIBS).
      cmake "$B" \
        -DCMAKE_BUILD_TYPE=debug \
        -DBUILD_SHARED_LIBS=OFF \
        -DFONT_CONFIGURATION=generic \
        -DBUILD_GTK_TESTS=OFF \
        -DBUILD_QT5_TESTS=OFF \
        -DBUILD_CPP_TESTS=OFF \
        -DENABLE_LIBPNG=ON \
        -DENABLE_LIBTIFF=ON \
        -DENABLE_LIBJPEG=ON \
        -DENABLE_SPLASH=ON \
        -DENABLE_UTILS=ON \
        -DWITH_Cairo=ON \
        -DENABLE_CMS=none \
        -DENABLE_LIBCURL=OFF \
        -DENABLE_GLIB=OFF \
        -DENABLE_GOBJECT_INTROSPECTION=OFF \
        -DENABLE_QT5=OFF \
        -DWITH_NSS3=OFF \
        -DFREETYPE_INCLUDE_DIRS="$FT_INSTALL/include/freetype2" \
        -DFREETYPE_LIBRARY="$FT_INSTALL/lib/libfreetype.a" \
        -DICONV_LIBRARIES="/usr/lib/x86_64-linux-gnu/libc.so" \
        -DCMAKE_EXE_LINKER_FLAGS_INIT="-L$B ${LIBS//\/usr\/local\/lib\/afl\/libAFLDriver.a/}" \
        || paper_die "poppler cmake failed ($variant)"
      make -j"$(nproc)" poppler poppler-cpp pdfimages pdftoppm \
        || paper_die "poppler make failed ($variant)"
    )

    # --- Build pdf_fuzzer (MAGMA's link order: static libs by path, $LDFLAGS $LIBS, system libs) ---
    local FZ_SRC="$PAPER_REF/magma/targets/$LIB/src/pdf_fuzzer.cc"
    local FZ_EXTRA=""
    if [ "$variant" = asan ]; then FZ_EXTRA="-fsanitize=fuzzer,address"; fi
    $CXX $CXXFLAGS -std=c++11 \
      -I"$PB/cpp" -I"$B/cpp" -I"$B" -I"$PB" -I"$FT_INSTALL/include" -I"$FT_INSTALL/include/freetype2" \
      "$FZ_SRC" -o "$B/pdf_fuzzer" \
      "$PB/cpp/libpoppler-cpp.a" "$PB/libpoppler.a" "$FT_INSTALL/lib/libfreetype.a" \
      $LDFLAGS $LIBS -ljpeg -lz -lopenjp2 -lpng -ltiff -llcms2 -lm -lpthread -pthread \
      $FZ_EXTRA \
      || paper_die "pdf_fuzzer link failed ($variant)"

    # --- Copy targets to OUT ---
    cp "$B/pdf_fuzzer" "$OUT/pdf_fuzzer.$variant"
    cp "$PB/utils/pdfimages" "$OUT/pdfimages.$variant"
    cp "$PB/utils/pdftoppm" "$OUT/pdftoppm.$variant"
  )
}

build_variant afl
build_variant cmp
build_variant asan

# --- paper_finish (writes .args, seeds, bundles libs, records BUILD-INFO) ---
paper_finish "$OUT" pdf_fuzzer "$V"
paper_finish "$OUT" pdfimages "$V"
paper_finish "$OUT" pdftoppm "$V"
