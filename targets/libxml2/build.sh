#!/bin/bash
# libxml2 2.15.4 (XML) with our harness xml_fuzzer.c (xmlReadMemory, then serialize)
#   -> OUT/xml_fuzzer.{afl,cmp,asan}, OUT/seeds/xml_fuzzer/
# Runs inside the g2fuzz image (the Dockerfile calls it). Usage: build.sh OUT
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); mkdir -p "$1"; OUT=$(cd "$1" && pwd)
TARBALL="$HERE/libxml2-2.15.4.tar.xz"
echo "98087fd181d9070724f3fbc65c7377db03038eb92bd882374daff44940138821  $TARBALL" | sha256sum -c --quiet - ||
  { echo "libxml2/build.sh: $TARBALL has the wrong sha256" >&2; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
tar -xf "$TARBALL" -C "$W"
SRC="$W/libxml2-2.15.4"
for v in afl cmp asan; do
  ( if [ $v = cmp ]; then export AFL_LLVM_CMPLOG=1; fi
    if [ $v = asan ]; then export AFL_USE_ASAN=1; fi
    D="$W/xml2-$v"; mkdir -p "$D"; cp -a "$SRC/." "$D/"; cd "$D"
    CC=afl-clang-fast CFLAGS=-O2 ./configure --with-pic --disable-shared --enable-static --without-python \
      --without-zlib --without-lzma --without-icu --without-http > /dev/null
    CC=afl-clang-fast CFLAGS=-O2 make -j"$(nproc)" > /dev/null
    afl-clang-fast -fsanitize=fuzzer -O2 -I "$SRC/include" -I "$D/include" "$HERE/xml_fuzzer.c" \
      "$D/.libs/libxml2.a" -lm -lpthread -o "$OUT/xml_fuzzer.$v" )
done
mkdir -p "$OUT/seeds/xml_fuzzer" && cp "$HERE"/seeds/* "$OUT/seeds/xml_fuzzer/"
afl-showmap -q -o "$W/map" -- "$OUT/xml_fuzzer.afl" "$HERE/seeds/small_document.xml" && test -s "$W/map"
