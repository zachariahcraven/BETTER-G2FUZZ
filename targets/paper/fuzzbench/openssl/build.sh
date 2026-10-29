#!/bin/bash
# FUZZBENCH openssl (paper: b0593c08 from benchmark.yaml; latest: openssl-4.0.3), built as the
# FuzzBench openssl project's reference build does (read/build.sh), three ways: .afl (AFL++),
# .cmp (CmpLog), .asan (AddressSanitizer).
# Usage (inside builder-fuzzbench.sif; targets/paper/build-paper.sh runs it): build.sh paper|latest OUT
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/../../common/lib.sh"

V=${1:?usage: build.sh paper|latest OUT}
OUT=${2:?usage: build.sh paper|latest OUT}
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
T=openssl_x509
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT

SRC=$(paper_fetch "$T" "$V" "$W/src")
SRC=$(cd "$SRC" && pwd)

# latest:openssl-4.0.3: fuzz/corpora is a git submodule the reference recipe never initialises.
# Take the corpus from its new home, pinned to the gitlink commit openssl-4.0.3 records.
CORPUS_RECIPE=""
if [ "$V" = latest ]; then
  CORPUS_COMMIT=e79bbce6dc62e794eab651d4be29b3d499d6df5c
  if [ -d "$SRC/.git" ]; then
    recorded=$(git -C "$SRC" ls-tree HEAD fuzz/corpora 2>/dev/null | awk '{print $3}')
    [ "$recorded" = "$CORPUS_COMMIT" ] || \
      paper_die "fuzz/corpora gitlink is ${recorded:-<none>}, expected $CORPUS_COMMIT"
  fi
  rm -rf "$SRC/fuzz/corpora"
  git clone --quiet https://github.com/openssl/fuzz-corpora "$SRC/fuzz/corpora" \
    || paper_die "git clone of fuzz-corpora failed"
  git -C "$SRC/fuzz/corpora" checkout --quiet --detach "$CORPUS_COMMIT" \
    || paper_die "fuzz-corpora checkout $CORPUS_COMMIT failed"
  actual=$(git -C "$SRC/fuzz/corpora" rev-parse HEAD)
  [ "$actual" = "$CORPUS_COMMIT" ] || paper_die "fuzz-corpora is at $actual, expected $CORPUS_COMMIT"
  CORPUS_RECIPE="fuzzbench-no-ssl3+corpus:fuzz-corpora@$CORPUS_COMMIT"
fi

FB_CFLAGS="-DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION -pthread -Wl,--no-as-needed -Wl,-ldl -Wl,-lm -Wno-unused-command-line-argument"

AFL_DRIVER=/usr/local/lib/afl/libAFLDriver.a
ASAN_FUZZER=/usr/lib/llvm-16/lib/clang/16/lib/linux/libclang_rt.fuzzer-x86_64.a
[ -f "$AFL_DRIVER" ]   || paper_die "AFL++ driver not found: $AFL_DRIVER"
[ -f "$ASAN_FUZZER" ]  || paper_die "clang libFuzzer not found: $ASAN_FUZZER"

build_variant() {
  local variant=$1
  local cc cxx cflags cxxflags lib
  local B="$W/build-$variant"
  mkdir -p "$B"
  cp -a "$SRC/." "$B/"
  (
    cd "$B"
    case $variant in
      afl|cmp)
        cc=afl-clang-fast
        cxx=afl-clang-fast++
        cflags="$FB_CFLAGS -O3"
        cxxflags="$FB_CFLAGS -stdlib=libc++ -O3"
        lib="$AFL_DRIVER"
        ;;
      asan)
        cc=clang
        cxx=clang++
        cflags="$FB_CFLAGS -g -O1 -fno-omit-frame-pointer -fsanitize=address"
        cxxflags="$FB_CFLAGS -g -O1 -fno-omit-frame-pointer -fsanitize=address"
        lib="$ASAN_FUZZER"
        ;;
      *)
        paper_die "internal: bad variant $variant"
        ;;
    esac
    export CC=$cc CXX=$cxx CFLAGS=$cflags CXXFLAGS=$cxxflags
    if [ "$variant" = cmp ]; then export AFL_LLVM_CMPLOG=1; fi
    if [ "$variant" = asan ]; then export ASAN_OPTIONS=detect_leaks=0; fi

    local conf_opts=(--debug enable-fuzz-libfuzzer -DPEDANTIC -DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION \
      no-shared enable-tls1_3 enable-rc5 enable-md2 enable-ec_nistp_64_gcc_128 \
      enable-nextprotoneg enable-weak-ssl-ciphers)
    # latest: openssl 4.0 removed SSLv3 ("Unsupported options: enable-ssl3-method, enable-ssl3"); user decision
    # 2026-10-22: paper recipe minus those two (OSS-Fuzz's current build drops the same two)
    if [ "$V" != latest ]; then
      conf_opts+=(enable-ssl3 enable-ssl3-method)
    fi
    ./config "${conf_opts[@]}" --with-fuzzer-lib="$lib" $CFLAGS -fno-sanitize=alignment \
      || paper_die "./config failed for $variant"
    make -j"$(nproc)" LDCMD="$CXX $CXXFLAGS" || paper_die "make failed for $variant"
    [ -x "$B/fuzz/x509" ] || paper_die "fuzz/x509 was not built for $variant"
    cp "$B/fuzz/x509" "$OUT/$T.$variant"
  )
}

build_variant afl
build_variant cmp
build_variant asan

# Seeds: regular files of fuzz/corpora/x509/ (same selection as the reference's
# `zip -j ... fuzz/corpora/x509/*`), files over 1 MiB skipped.
seed_dir="$OUT/seeds/$T"
rm -rf "$seed_dir"
mkdir -p "$seed_dir"
declare -A used=()
copied=0
while IFS= read -r -d '' f; do
  base=$(basename "$f")
  size=$(stat -c%s "$f")
  if [ "$size" -gt 1048576 ]; then continue; fi
  dest_base=$base
  if [ -n "${used[$dest_base]+x}" ]; then
    n=1
    while [ -n "${used[$dest_base]+x}" ]; do
      dest_base="${n}_${base}"
      n=$((n + 1))
    done
  fi
  cp "$f" "$seed_dir/$dest_base"
  used[$base]=1
  used[$dest_base]=1
  copied=$((copied + 1))
done < <(find "$SRC/fuzz/corpora/x509" -maxdepth 1 -type f -print0 | sort -z)
[ "$copied" -gt 0 ] || paper_die "no seed files found in $SRC/fuzz/corpora/x509"

if [ -n "$CORPUS_RECIPE" ]; then
  export PAPER_RECIPE="$CORPUS_RECIPE"
fi
paper_finish "$OUT" "$T" "$V"
