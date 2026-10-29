#!/bin/bash
# FUZZBENCH woff2 (paper: manifest pin; latest: v1.0.2), built as FuzzBench's build.sh does,
# three ways: .afl (AFL++), .cmp (CmpLog), .asan (AddressSanitizer).
# Usage (inside builder-fuzzbench.sif; targets/paper/build-paper.sh runs it): build.sh paper|latest OUT
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/../../common/lib.sh"

V=${1:?usage: build.sh paper|latest OUT}; OUT=${2:?usage: build.sh paper|latest OUT}; mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
T=woff2_convert_woff2ttf_fuzzer
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT

SRC=$(paper_fetch "$T" "$V" "$W/src")
BROT="$SRC/../brotli"

# Clone brotli at the pinned commit (sibling to woff2, as the reference Dockerfile does)
git clone -q https://github.com/google/brotli.git "$BROT"
git -C "$BROT" checkout -q 3a9032ba8733532a6cd6727970bade7f7c0e2f52
[ "$(git -C "$BROT" rev-parse HEAD)" = "3a9032ba8733532a6cd6727970bade7f7c0e2f52" ] || \
  paper_die "brotli: expected 3a9032ba8733532a6cd6727970bade7f7c0e2f52, got $(git -C "$BROT" rev-parse HEAD)"

HARNESS="$HERE/target.cc"
[ -f "$HARNESS" ] || paper_die "harness not found: $HARNESS"

WOFF2_FILES="font.cc normalize.cc transform.cc woff2_common.cc woff2_dec.cc woff2_enc.cc glyph.cc table_tags.cc variable_length.cc woff2_out.cc"

FB_CFLAGS="-DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION -pthread -Wl,--no-as-needed -Wl,-ldl -Wl,-lm -Wno-unused-command-line-argument"

if [ "$V" = paper ]; then

build_variant() {
  local variant=$1
  local cc cxx engine
  local B="$W/build-$variant"
  mkdir -p "$B"
  cp -a "$SRC/." "$B/woff2"
  cp -a "$BROT/." "$B/brotli"

  for f in $WOFF2_FILES; do
    [ -f "$B/woff2/src/$f" ] || paper_die "woff2 source src/$f missing (variant $variant)"
  done
  [ -d "$B/brotli/dec" ] || paper_die "brotli/dec missing (variant $variant)"
  [ -d "$B/brotli/enc" ] || paper_die "brotli/enc missing (variant $variant)"

  case $variant in
    afl|cmp)
      cc=afl-clang-fast; cxx=afl-clang-fast++
      engine="-fsanitize=fuzzer"
      ;;
    asan)
      cc=clang; cxx=clang++
      engine="-fsanitize=fuzzer,address"
      ;;
    *)
      paper_die "internal: bad variant $variant"
      ;;
  esac

  (
    cd "$B/woff2"
    export CC=$cc CXX=$cxx
    if [ "$variant" = asan ]; then
      export CFLAGS="$FB_CFLAGS -g -O1 -fno-omit-frame-pointer -fsanitize=address"
      export CXXFLAGS="$FB_CFLAGS -g -O1 -fno-omit-frame-pointer -fsanitize=address"
      export LDFLAGS="-g -O1 -fno-omit-frame-pointer -fsanitize=address"
      export ASAN_OPTIONS=detect_leaks=0
    else
      export CFLAGS="$FB_CFLAGS -O3"
      export CXXFLAGS="$FB_CFLAGS -stdlib=libc++ -O3"
    fi
    if [ "$variant" = cmp ]; then export AFL_LLVM_CMPLOG=1; fi

    # Compile woff2 sources (same flags and files as the reference build.sh;
    # -I include for v1.0.2's include/woff2/ headers)
    winc="-I ../brotli/dec -I ../brotli/enc"
    [ -d include ] && winc="$winc -I include"
    for f in $WOFF2_FILES; do
      $cxx $CXXFLAGS -std=c++11 $winc -c "src/$f" || \
        paper_die "compiling woff2 src/$f failed (variant $variant)"
    done

    # Compile brotli sources (all as C++, as the reference build.sh does)
    for f in ../brotli/dec/*.c; do
      [ -f "$f" ] || paper_die "brotli source $f missing (variant $variant)"
      $cxx $CXXFLAGS -c "$f" || \
        paper_die "compiling brotli $f failed (variant $variant)"
    done
    for f in ../brotli/enc/*.cc; do
      [ -f "$f" ] || paper_die "brotli source $f missing (variant $variant)"
      $cxx $CXXFLAGS -c "$f" || \
        paper_die "compiling brotli $f failed (variant $variant)"
    done

    # Link all objects with the harness
    linkinc="-I src"
    [ -d include ] && linkinc="$linkinc -I include"
    $cxx $CXXFLAGS *.o $engine "$HARNESS" $linkinc -o "$OUT/$T.$variant" || \
      paper_die "linking $T.$variant failed"
  )
}

build_variant afl
build_variant cmp
build_variant asan

elif [ "$V" = latest ]; then
  # oss-fuzz recipe pinned to commit 284f6239d40a40e18b4468d83a191559134315c6
  BROT_COMMIT=5b4769990dc14a2bd466d2599c946c5652cba4b2
  rm -rf "$SRC/brotli"
  git clone -q https://github.com/google/brotli.git "$SRC/brotli" || \
    paper_die "latest: cloning brotli into $SRC/brotli failed"
  git -C "$SRC/brotli" checkout -q "$BROT_COMMIT" || \
    paper_die "latest: brotli checkout $BROT_COMMIT failed"
  [ "$(git -C "$SRC/brotli" rev-parse HEAD)" = "$BROT_COMMIT" ] || \
    paper_die "latest: brotli expected $BROT_COMMIT, got $(git -C "$SRC/brotli" rev-parse HEAD)"

  build_variant() {
    local variant=$1
    local cc cxx engine
    local B="$W/build-$variant"
    mkdir -p "$B"
    cp -a "$SRC/." "$B/woff2"
    # brotli is pinned in the source tree ($SRC/brotli); put the verified copy in the clean copy
    rm -rf "$B/woff2/brotli"
    cp -a "$SRC/brotli" "$B/woff2/brotli" || \
      paper_die "latest: copying brotli into the clean copy failed (variant $variant)"

    case $variant in
      afl|cmp)
        cc=afl-clang-fast; cxx=afl-clang-fast++
        engine="-fsanitize=fuzzer"
        ;;
      asan)
        cc=clang; cxx=clang++
        engine="-fsanitize=fuzzer,address"
        ;;
      *)
        paper_die "internal: bad variant $variant"
        ;;
    esac

    (
      cd "$B/woff2"
      export CC=$cc CXX=$cxx
      if [ "$variant" = asan ]; then
        export CFLAGS="$FB_CFLAGS -g -O1 -fno-omit-frame-pointer -fsanitize=address"
        export CXXFLAGS="$FB_CFLAGS -g -O1 -fno-omit-frame-pointer -fsanitize=address"
      else
        export CFLAGS="$FB_CFLAGS -O3"
        export CXXFLAGS="$FB_CFLAGS -stdlib=libc++ -O3"
      fi
      if [ "$variant" = cmp ]; then export AFL_LLVM_CMPLOG=1; fi

      # oss-fuzz: remove -no-canonical-prefixes from brotli/shared.mk (if it exists)
      if [ -f brotli/shared.mk ]; then
        cat brotli/shared.mk | sed -e "s/-no-canonical-prefixes//" > brotli/shared.mk.temp || \
          paper_die "latest: editing brotli/shared.mk failed (variant $variant)"
        mv brotli/shared.mk.temp brotli/shared.mk
      else
        echo "latest: brotli/shared.mk not present at this brotli commit; skipping -no-canonical-prefixes sed (variant $variant)"
      fi

      make clean || paper_die "latest: make clean failed (variant $variant)"
      make CC="$CC $CFLAGS" CXX="$CXX $CXXFLAGS" CANONICAL_PREFIXES= all NOISY_LOGGING= || \
        paper_die "latest: make all failed (variant $variant)"

      [ -f src/convert_woff2ttf_fuzzer.a ] || \
        paper_die "latest: src/convert_woff2ttf_fuzzer.a not found (variant $variant)"
      $CXX $CXXFLAGS $engine src/convert_woff2ttf_fuzzer.a -o "$OUT/$T.$variant" || \
        paper_die "latest: linking $T.$variant failed"
    )
  }

  build_variant afl
  build_variant cmp
  build_variant asan

else
  paper_die "internal: bad version $V"
fi

# Seeds: download each corpus file from the pinned oss-fuzz commit, verify sha256
SEED_DIR="$OUT/seeds/$T"
rm -rf "$SEED_DIR"; mkdir -p "$SEED_DIR"
CORPUS_SHA256="$HERE/corpus.sha256"
[ -f "$CORPUS_SHA256" ] || paper_die "corpus.sha256 not found at $CORPUS_SHA256"

(
  cd "$SEED_DIR"
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    name=${line##* }
    wget -q -O "$name" "https://raw.githubusercontent.com/google/oss-fuzz/e8ffee4077b59e35824a2e97aa214ee95d39ed13/projects/woff2/corpus/$name" || \
      paper_die "failed to download seed $name"
  done < "$CORPUS_SHA256"
  sha256sum -c "$CORPUS_SHA256" || paper_die "seed sha256 verification failed"
)

if [ "$V" = latest ]; then
  export PAPER_RECIPE=oss-fuzz@284f6239d40a40e18b4468d83a191559134315c6
fi

paper_finish "$OUT" "$T" "$V"
