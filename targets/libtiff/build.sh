#!/bin/bash
# libtiff's tiff_read_rgba_fuzzer (TIFF), its own OSS-Fuzz harness, v4.7.2
#   -> OUT/tiff_read_rgba_fuzzer.{afl,cmp,asan}, OUT/seeds/tiff_read_rgba_fuzzer/
# AFL++ links libFuzzer harnesses (-fsanitize=fuzzer) with a driver that reads the @@ file.
# Runs inside the g2fuzz image (the Dockerfile calls it). Usage: build.sh OUT
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); mkdir -p "$1"; OUT=$(cd "$1" && pwd)
COMMIT=d01a94be176f5f6a87f7ee1c0b32e65416aa2b4d
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
git clone -q https://gitlab.com/libtiff/libtiff "$W/libtiff" && cd "$W/libtiff" && git checkout -q $COMMIT
CM="-DBUILD_SHARED_LIBS=OFF -Dtiff-tools=OFF -Dtiff-tests=OFF -Dtiff-contrib=OFF -Dtiff-docs=OFF
  -Djbig=OFF -Dlerc=OFF -Dlzma=OFF -Dzstd=OFF -Dwebp=OFF -Dlibdeflate=OFF"
for v in afl cmp; do
  ( if [ $v = cmp ]; then export AFL_LLVM_CMPLOG=1; fi
    cmake -S . -B build-$v -DCMAKE_C_COMPILER=afl-clang-fast -DCMAKE_CXX_COMPILER=afl-clang-fast++ $CM > /dev/null
    cmake --build build-$v -j"$(nproc)" > /dev/null
    afl-clang-fast++ -fsanitize=fuzzer -I libtiff -I build-$v/libtiff \
      contrib/oss-fuzz/tiff_read_rgba_fuzzer.cc build-$v/libtiff/libtiffxx.a build-$v/libtiff/libtiff.a \
      -lz -ljpeg -lm -o "$OUT/tiff_read_rgba_fuzzer.$v" )
done
# ASan (crash triage): plain clang, leaks off at build and run time
export ASAN_OPTIONS=detect_leaks=0
F="-g -O1 -fno-omit-frame-pointer"
clang -c "$HERE/../common/asan_default_options.c" -o "$W/asan_default_options.o" $F
cmake -S . -B build-asan -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
  -DCMAKE_C_FLAGS="$F -fsanitize=address" -DCMAKE_CXX_FLAGS="$F -fsanitize=address" $CM > /dev/null
cmake --build build-asan -j"$(nproc)" > /dev/null
clang++ -fsanitize=fuzzer,address -I libtiff -I build-asan/libtiff $F contrib/oss-fuzz/tiff_read_rgba_fuzzer.cc \
  "$W/asan_default_options.o" build-asan/libtiff/libtiffxx.a build-asan/libtiff/libtiff.a -lz -ljpeg -lm \
  -Wl,--export-dynamic -o "$OUT/tiff_read_rgba_fuzzer.asan"
mkdir -p "$OUT/seeds/tiff_read_rgba_fuzzer" && cp "$HERE"/seeds/* "$OUT/seeds/tiff_read_rgba_fuzzer/"
afl-showmap -q -o "$W/map" -- "$OUT/tiff_read_rgba_fuzzer.afl" "$HERE/seeds/not_kitty.tiff" && test -s "$W/map"
