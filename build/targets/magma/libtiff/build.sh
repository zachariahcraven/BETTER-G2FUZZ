#!/bin/bash
# MAGMA libtiff (paper row only), built exactly as MAGMA v1.2's AFL++ build does, three ways:
# .afl (AFL++), .cmp (CmpLog), .asan (AddressSanitizer).
# Usage (inside builder-magma-libtiff.sif; build/targets/build-paper.sh runs it): build.sh paper|latest OUT
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/../../common/lib.sh"

V=${1:?usage: build.sh paper|latest OUT}
OUT=${2:?usage: build.sh paper|latest OUT}
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT

[ "$V" = "paper" ] || paper_die "MAGMA latest rows are not built"

BENCH=magma
LIB=libtiff
MAGMA_ROOT="$PAPER_REF/magma"
MAGMA="$MAGMA_ROOT/magma"
TGT="$MAGMA_ROOT/targets/$LIB"
MANIFEST="$HERE/../../manifest.tsv"

[ -d "$MAGMA/src" ] || paper_die "MAGMA core src not found: $MAGMA/src"
[ -d "$TGT" ] || paper_die "MAGMA target directory not found: $TGT"
[ -f "$MANIFEST" ] || paper_die "manifest not found: $MANIFEST"

mapfile -t TARGETS < <(
  awk -F'\t' -v b="$BENCH" -v p="$LIB" -v v="$V" '
    /^#/ { next }
    $2 == b && $3 == p && $4 == v { print $1 }
  ' "$MANIFEST" | sort -u
)
[ ${#TARGETS[@]} -gt 0 ] || paper_die "no $BENCH/$LIB manifest rows for version $V"

SRC=$(paper_fetch "${TARGETS[0]}" "$V" "$W/src")
for T in "${TARGETS[@]}"; do
  paper_fetch "$T" "$V" "$W/src-$T" > /dev/null
done

AUTOGEN=$(find "$SRC" -maxdepth 3 -name autogen.sh -type f -print -quit 2>/dev/null || true)
[ -n "$AUTOGEN" ] || paper_die "cannot find libtiff autogen.sh under $SRC"
SRC_ROOT=$(dirname "$AUTOGEN")

BASE="$W/base"
mkdir -p "$BASE"
cp -a "$SRC_ROOT/." "$BASE/"

shopt -s nullglob
harnesses=("$TGT/src"/*.cc)
[ ${#harnesses[@]} -gt 0 ] || paper_die "no MAGMA harness .cc sources in $TGT/src"
mkdir -p "$BASE/contrib/oss-fuzz"
cp "${harnesses[@]}" "$BASE/contrib/oss-fuzz/"

# Build GNU patch from pinned source (the builder image has no `patch`; git apply is too strict for
# MAGMA's patches which rely on fuzz). Per judge rulings 2026-10-23 01:50 and 02:20: use the vendored
# tarball from $PAPER_REF/tools when present; download only if it is missing.
PATCH_VER=2.7.6
PATCH_SHA=ac610bda97abe0d9f6b7c963255a11dcb196c25e337c61f94e4778d632f1d8fd
PATCH_NAME="patch-${PATCH_VER}.tar.xz"
PATCH_DIR="$W/patch-src"
PATCH_PREFIX="$W/patch"
mkdir -p "$PATCH_DIR"
if [ -f "$PAPER_REF/tools/$PATCH_NAME" ]; then
  cp "$PAPER_REF/tools/$PATCH_NAME" "$PATCH_DIR/$PATCH_NAME"
else
  ( wget -q -O "$PATCH_DIR/$PATCH_NAME" "https://ftp.gnu.org/gnu/patch/$PATCH_NAME" ||
    wget -q -O "$PATCH_DIR/$PATCH_NAME" "https://mirrors.kernel.org/gnu/patch/$PATCH_NAME" ) \
    || paper_die "cannot obtain patch $PATCH_VER"
fi
echo "$PATCH_SHA  $PATCH_DIR/$PATCH_NAME" | sha256sum -c - || paper_die "patch $PATCH_VER sha256 mismatch"
tar -xJf "$PATCH_DIR/$PATCH_NAME" -C "$PATCH_DIR"
(
  cd "$PATCH_DIR/patch-$PATCH_VER"
  CC=gcc ./configure --prefix="$PATCH_PREFIX" &&
  make -j"$(nproc)" &&
  make install
) || paper_die "building GNU patch $PATCH_VER failed"
[ -x "$PATCH_PREFIX/bin/patch" ] || paper_die "patch binary not found after build"

apply_patches() {
  local tree=$1
  local patches=()
  local dir patch pname
  for dir in setup bugs; do
    [ -d "$TGT/patches/$dir" ] || continue
    while IFS= read -r -d '' patch; do
      patches+=("$patch")
    done < <(find "$TGT/patches/$dir" -name '*.patch' -print0 | LC_ALL=C sort -z)
  done
  for patch in "${patches[@]}"; do
    pname=${patch##*/}
    bug=${pname%.patch}
    if ! sed "s/%MAGMA_BUG%/$bug/g" "$patch" | "$PATCH_PREFIX/bin/patch" -p1 -d "$tree"; then
      paper_die "MAGMA patch failed for $LIB: $patch"
    fi
  done
}
apply_patches "$BASE"

DRIVER=/usr/local/lib/afl/libAFLDriver.a
DRIVER_HAS_MAIN=0
if [ -f "$DRIVER" ] && nm --defined-only "$DRIVER" 2>/dev/null | awk 'NF == 3 { print $3 }' | grep -qx main; then
  DRIVER_HAS_MAIN=1
fi

is_fuzzer() {
  case $1 in
    *_fuzzer) return 0 ;;
  esac
  [ -f "$TGT/src/$1.cc" ]
}

find_include_dir() {
  local tree=$1 h
  if [ -f "$tree/libtiff/tiffio.h" ]; then echo "$tree/libtiff"; return 0; fi
  if [ -f "$tree/tiffio.h" ]; then echo "$tree"; return 0; fi
  h=$(find "$tree" -name tiffio.h -type f -print -quit 2>/dev/null || true)
  [ -n "$h" ] || return 1
  dirname "$h"
}

find_libtiff_a() {
  local work=$1 tree=$2 h
  if [ -f "$work/lib/libtiff.a" ]; then echo "$work/lib/libtiff.a"; return 0; fi
  h=$(find "$tree" -name libtiff.a -type f -print -quit 2>/dev/null || true)
  [ -n "$h" ] || return 1
  echo "$h"
}

# libtiff's C++ stream API (TIFFStreamOpen) is in libtiffxx, separate from the C API in libtiff.
find_libtiffxx_a() {
  local work=$1 tree=$2 h
  if [ -f "$work/lib/libtiffxx.a" ]; then echo "$work/lib/libtiffxx.a"; return 0; fi
  h=$(find "$tree" -name libtiffxx.a -type f -print -quit 2>/dev/null || true)
  [ -n "$h" ] || return 1
  echo "$h"
}

lib_link_arg() {
  local path=$1 base name d
  base=${path##*/}
  name=${base%%.so*}
  name=${name#lib}
  for d in /usr/lib/x86_64-linux-gnu /usr/lib /lib/x86_64-linux-gnu /lib /usr/local/lib /usr/local/lib/x86_64-linux-gnu /usr/lib64 /lib64; do
    if [ -e "$d/lib$name.so" ]; then
      printf -- '-l%s' "$name"
      return 0
    fi
  done
  printf '%s' "$path"
}

extra_link_libs() {
  local probe=$1
  local extra="" line base arg
  [ -x "$probe" ] || return 0
  while IFS= read -r line; do
    base=${line##*/}
    case $base in
      lib*.so*) ;;
      *) continue ;;
    esac
    case $base in
      libtiff*|libmagma*|libAFL*|libclang*|libgcc*|libstdc++*|libc++*|libasan*|libc.so*|ld-linux*|linux-vdso*) continue ;;
    esac
    arg=$(lib_link_arg "$line")
    case " $extra " in
      *" $arg "*) continue ;;
    esac
    extra="$extra $arg"
  done < <(ldd "$probe" 2>/dev/null | awk '{ print $1 }' | grep '\.so' || true)
  printf '%s' "$extra"
}

link_fuzzer() {
  local variant=$1 tree=$2 work=$3 cxx=$4 cxxflags=$5 libs=$6 engine=$7 harness=$8 probe=$9 target=${10}
  local inc libtiff_a libtiffxx_a extra
  inc=$(find_include_dir "$tree") || paper_die "cannot find tiffio.h in $tree ($variant)"
  libtiff_a=$(find_libtiff_a "$work" "$tree") || paper_die "libtiff.a not found ($variant)"
  libtiffxx_a=$(find_libtiffxx_a "$work" "$tree") || paper_die "libtiffxx.a not found ($variant)"
  extra=$(extra_link_libs "$probe")
  # shellcheck disable=SC2086
  $cxx $cxxflags -I "$inc" -I "$tree" -fPIC \
    "$harness" \
    -o "$OUT/$target.$variant" \
    $engine "$libtiffxx_a" "$libtiff_a" $extra $LDFLAGS $libs || paper_die "linking $target.$variant failed"
}

# Offline stand-in for libtiff's autogen.sh download of config.guess/config.sub (platform detection
# only; judge ruling 2026-10-23 02:20). It copies the builder's automake copies to the requested file
# and refuses anything else.
mkdir -p "$W/bin"
cat > "$W/bin/wget" <<'WGET_STANDIN'
#!/bin/sh
out=""
url=""
while [ $# -gt 0 ]; do
  case $1 in
    -O)
      [ $# -ge 2 ] || exit 1
      out=$2
      shift
      ;;
    -O?*)
      out=${1#-O}
      ;;
    --output-document)
      [ $# -ge 2 ] || exit 1
      out=$2
      shift
      ;;
    --output-document=*)
      out=${1#--output-document=}
      ;;
    http://*|https://*|ftp://*)
      url=$1
      ;;
    -*)
      ;;
  esac
  shift
done
[ -n "$out" ] || exit 1
src=""
case $url in
  *config.guess*)
    src=$(ls /usr/share/automake-*/config.guess 2>/dev/null | sort | tail -n1)
    [ -n "$src" ] || src=$(ls /usr/share/gnuconfig/config.guess 2>/dev/null | head -n1)
    ;;
  *config.sub*)
    src=$(ls /usr/share/automake-*/config.sub 2>/dev/null | sort | tail -n1)
    [ -n "$src" ] || src=$(ls /usr/share/gnuconfig/config.sub 2>/dev/null | head -n1)
    ;;
esac
if [ -n "$src" ]; then
  cp "$src" "$out"
  chmod +x "$out" 2>/dev/null || true
  exit 0
fi
echo "wget stand-in: refusing unsupported URL: $url" >&2
exit 1
WGET_STANDIN
chmod +x "$W/bin/wget"

build_variant() {
  local variant=$1
  local tree="$W/tree-$variant" work="$W/work-$variant" vmag="$W/magma-$variant"
  mkdir -p "$tree" "$work" "$vmag"
  cp -a "$BASE/." "$tree/"

  local cc cxx cflags cxxflags ldflags libs engine
  local magma_cflags="-include $MAGMA/src/canary.h -DMAGMA_ENABLE_CANARIES -fPIC -g"
  case $variant in
    afl|cmp)
      cc=afl-clang-fast
      cxx=afl-clang-fast++
      cflags="$magma_cflags -O0"
      cxxflags="$cflags -stdlib=libc++"
      libs="-l:magma.o -lrt -lc++ -lc++abi $DRIVER"
      ldflags="-L$vmag -g"
      if [ "$DRIVER_HAS_MAIN" -eq 1 ]; then
        engine=""
      else
        engine="-fsanitize=fuzzer"
      fi
      ;;
    asan)
      cc=clang
      cxx=clang++
      cflags="$magma_cflags -O1 -fno-omit-frame-pointer -fsanitize=address"
      cxxflags=$cflags
      libs="-l:magma.o -lrt"
      ldflags="-L$vmag -g -fsanitize=address"
      engine="-fsanitize=fuzzer,address"
      ;;
    *)
      paper_die "internal: bad variant $variant"
      ;;
  esac

  (
    cd "$vmag"
    export CC=$cc CXX=$cxx CFLAGS=$cflags CXXFLAGS=$cxxflags
    if [ "$variant" = "cmp" ]; then export AFL_LLVM_CMPLOG=1; fi
    if [ "$variant" = "asan" ]; then export ASAN_OPTIONS=detect_leaks=0; fi
    # shellcheck disable=SC2086
    $CC $CFLAGS -D"MAGMA_STORAGE=\"/magma_shared/canaries.raw\"" -c "$MAGMA/src/canary.c" -fPIC -I "$MAGMA/src" -o canary.o \
      || paper_die "building canary.o ($variant) failed"
    # shellcheck disable=SC2086
    $CC $CFLAGS -D"MAGMA_STORAGE=\"/magma_shared/canaries.raw\"" -c "$MAGMA/src/storage.c" -fPIC -I "$MAGMA/src" -o storage.o \
      || paper_die "building storage.o ($variant) failed"
    ld -r canary.o storage.o -o magma.o || paper_die "linking magma.o ($variant) failed"
  )

  (
    cd "$tree"
    export CC=$cc CXX=$cxx CFLAGS=$cflags CXXFLAGS=$cxxflags LDFLAGS=$ldflags LIBS=$libs
    if [ "$variant" = "cmp" ]; then export AFL_LLVM_CMPLOG=1; fi
    if [ "$variant" = "asan" ]; then export ASAN_OPTIONS=detect_leaks=0; fi

    # autogen.sh unchanged, but with the offline wget stand-in on PATH for its config.guess/sub fetches.
    PATH="$W/bin:$PATH" ./autogen.sh || paper_die "libtiff autogen ($variant) failed"
    ./configure --disable-shared --prefix="$work" || paper_die "libtiff configure ($variant) failed"
    make -j"$(nproc)" || paper_die "libtiff make ($variant) failed"
    make install || paper_die "libtiff make install ($variant) failed"

    probe=""
    for T in "${TARGETS[@]}"; do
      if ! is_fuzzer "$T" && [ -x "$work/bin/$T" ]; then
        probe="$work/bin/$T"
        break
      fi
    done
    if [ -z "$probe" ]; then
      probe=$(find "$work/bin" -maxdepth 1 -type f -executable -print -quit 2>/dev/null || true)
    fi

    for T in "${TARGETS[@]}"; do
      if is_fuzzer "$T"; then
        harness=""
        for ext in cc c; do
          if [ -f "$tree/contrib/oss-fuzz/$T.$ext" ]; then
            harness="$tree/contrib/oss-fuzz/$T.$ext"
            break
          fi
        done
        [ -n "$harness" ] || paper_die "harness for $T not found in $tree/contrib/oss-fuzz ($variant)"
        link_fuzzer "$variant" "$tree" "$work" "$cxx" "$cxxflags" "$libs" "$engine" "$harness" "$probe" "$T"
      else
        [ -x "$work/bin/$T" ] || paper_die "standalone program $T was not built in $work/bin ($variant)"
        cp "$work/bin/$T" "$OUT/$T.$variant"
      fi
    done
  )
}

for variant in afl cmp asan; do
  build_variant "$variant"
done

for T in "${TARGETS[@]}"; do
  for variant in afl cmp asan; do
    [ -x "$OUT/$T.$variant" ] || paper_die "missing built binary $OUT/$T.$variant"
  done
  paper_finish "$OUT" "$T" "$V"
done
