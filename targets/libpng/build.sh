#!/bin/bash
# libpng's libpng_read_fuzzer (PNG), its own OSS-Fuzz harness, v1.6.59, built as libpng's
# contrib/oss-fuzz/build.sh does (the harness ignores CRC and Adler-32 checksums)
#   -> OUT/libpng_read_fuzzer.{afl,cmp,asan}, OUT/seeds/libpng_read_fuzzer/
# Runs inside the g2fuzz image (the Dockerfile calls it). Usage: build.sh OUT
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); mkdir -p "$1"; OUT=$(cd "$1" && pwd)
COMMIT=cd952f49f95bb27154ae77dbb103032d95f6e580
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
git clone -q https://github.com/pnggroup/libpng "$W/libpng" && cd "$W/libpng" && git checkout -q $COMMIT
sed -i -e "s/option STDIO/option STDIO disabled/" -e "s/option WARNING /option WARNING disabled/" \
  -e "s/option WRITE enables WRITE_INT_FUNCTIONS/option WRITE disabled/" scripts/pnglibconf.dfa
autoreconf -f -i > /dev/null 2>&1
for v in afl cmp; do
  ( if [ $v = cmp ]; then export AFL_LLVM_CMPLOG=1; fi
    ./configure -q CC=afl-clang-fast --with-libpng-prefix=OSS_FUZZ_
    make -s clean && make -s -j"$(nproc)" libpng16.la > /dev/null
    afl-clang-fast++ -fsanitize=fuzzer -std=c++11 -I. contrib/oss-fuzz/libpng_read_fuzzer.cc \
      .libs/libpng16.a -lz -o "$OUT/libpng_read_fuzzer.$v" )
done
# ASan (crash triage): plain clang, leaks off at build and run time
export ASAN_OPTIONS=detect_leaks=0
F="-g -O1 -fno-omit-frame-pointer"
clang -c "$HERE/../common/asan_default_options.c" -o "$W/asan_default_options.o" $F
CFLAGS="$F -fsanitize=address" CXXFLAGS="$F -fsanitize=address" ./configure -q CC=clang --with-libpng-prefix=OSS_FUZZ_
make -s clean || true; rm -rf .libs ./*.o ./*.a ./*.la
make -s -j"$(nproc)" libpng16.la > /dev/null
clang++ -fsanitize=fuzzer,address -std=c++11 -I. $F contrib/oss-fuzz/libpng_read_fuzzer.cc \
  "$W/asan_default_options.o" .libs/libpng16.a -lz -Wl,--export-dynamic -o "$OUT/libpng_read_fuzzer.asan"
mkdir -p "$OUT/seeds/libpng_read_fuzzer" && cp "$HERE"/seeds/* "$OUT/seeds/libpng_read_fuzzer/"
afl-showmap -q -o "$W/map" -- "$OUT/libpng_read_fuzzer.afl" "$HERE/seeds/not_kitty.png" && test -s "$W/map"
