#!/bin/bash
# Checks the fuzz targets inside the image (/targets, built by targets/<folder>/build.sh): every target
# has its three builds and stock seeds, runs cleanly and deterministically, and the instrumentation is
# real. Merges the acceptance tests the butler's build scripts had to pass (2026-10).
# Runs on Tempest:  bash tests/image/test_targets.sh   (SIF=<image> to test another image;
#   TARGETS_DIR=<folder> tests that folder bound over /targets, e.g. the output of targets/build-all.sh)
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SIF=${SIF:-$ROOT/g2fuzz.sif}
T=$(mktemp -d -p "$HOME"); trap 'rm -rf "$T"' EXIT
fails=0
check() { if eval "$1"; then echo "ok    $2"; else echo "FAIL  $2"; fails=$((fails + 1)); fi; }
box() { apptainer exec -B /home/group -B "$T" ${TARGETS_DIR:+-B "$TARGETS_DIR:/targets:ro"} "$SIF" "$@"; }
edges() { box bash -c "afl-showmap -q -o '$T/m' -t 10000 -- $1 '$2' >/dev/null 2>&1; wc -l < '$T/m' 2>/dev/null || echo 0; rm -f '$T/m'"; }
union() {   # target -> edges of its stock seeds, one run per file
  box bash -c "for f in /targets/seeds/$1/*; do afl-showmap -q -o '$T/m' -t 10000 -- /targets/$1.afl \"\$f\" >/dev/null 2>&1; cut -d: -f1 '$T/m' 2>/dev/null; rm -f '$T/m'; done | sort -u | wc -l"
}

# every target: three builds, real instrumentation, stock seeds that run cleanly, deterministic coverage
for t in jhead:50 tiff_read_rgba_fuzzer:50 libpng_read_fuzzer:50 xml_fuzzer:300 doom_wad:500; do
  n=${t%%:*}; floor=${t#*:}
  for v in afl cmp asan; do check "box test -x /targets/$n.$v" "$n.$v exists and is executable"; done
  s=$(box bash -c "ls -d /targets/seeds/$n/* | head -1")
  check "[ -n '$s' ]" "$n has stock seeds in /targets/seeds/$n/"
  check "box bash -c 'strings /targets/$n.cmp | grep -q __cmplog'" "$n.cmp has CmpLog instrumentation"
  check "box bash -c 'ASAN_OPTIONS=help=1 /targets/$n.asan $s 2>&1 | grep -q AddressSanitizer'" "$n.asan has AddressSanitizer"
  check "box env ASAN_OPTIONS=detect_leaks=0 timeout 60 /targets/$n.asan $s > /dev/null 2>&1" "$n.asan runs a stock seed and exits 0"
  e=$(union $n)
  check "[ ${e:-0} -gt $floor ]" "$n: stock seeds reach more than $floor edges (got $e)"
  a=$(box bash -c "afl-showmap -q -o '$T/a' -t 10000 -- /targets/$n.afl '$s' >/dev/null 2>&1; afl-showmap -q -o '$T/b' -t 10000 -- /targets/$n.afl '$s' >/dev/null 2>&1; diff -q <(cut -d: -f1 '$T/a') <(cut -d: -f1 '$T/b') >/dev/null && echo same || echo different")
  check "[ '$a' = same ]" "$n: the same input reaches the same edges on two runs"
done

# jhead.asan finds a real jhead bug from fuzzing, with symbolized source lines
cp "$ROOT/tests/fixtures/asan/jhead-crash-1" "$T/"
box bash -c "ASAN_SYMBOLIZER_PATH=/usr/lib/llvm-16/bin/llvm-symbolizer ASAN_OPTIONS=detect_leaks=0:allocator_may_return_null=1:max_allocation_size_mb=1024 /targets/jhead.asan '$T/jhead-crash-1'" > "$T/crash.txt" 2>&1
check "grep -q 'ERROR: AddressSanitizer' '$T/crash.txt'" "jhead.asan reports the jhead crash ($(grep -m1 'ERROR: AddressSanitizer' "$T/crash.txt" | cut -c1-100))"
check "grep -qE '#[0-9]+ .* in .*[a-z]+\.c:[0-9]+' '$T/crash.txt'" "the report has symbolized frames with source lines"

# xml_fuzzer: a DTD with an entity, and garbage, both parse cleanly
printf '<?xml version="1.0"?>\n<!DOCTYPE a [<!ENTITY e "x">]>\n<a b="1"><c>&e;</c><![CDATA[z]]></a>\n' > "$T/ok.xml"
head -c 4096 /dev/urandom > "$T/garbage.xml"
for f in ok.xml garbage.xml; do check "box /targets/xml_fuzzer.afl '$T/$f' >/dev/null 2>&1" "xml_fuzzer.afl runs $f and exits 0"; done
e=$(edges /targets/xml_fuzzer.afl "$T/ok.xml")
check "[ ${e:-0} -gt 100 ]" "a small XML file with a DTD and an entity reaches more than 100 edges (got $e)"

# doom_wad: the add-on's own map is what gets played, whatever its marker is called
python3 - "$ROOT/targets/doom/freedoom2.wad" "$T" <<'PY'
import struct, sys
iwad, out = sys.argv[1], sys.argv[2]
d = open(iwad, "rb").read()
n, off = struct.unpack("<ii", d[4:12])
ents = [struct.unpack("<ii8s", d[off + 16 * i: off + 16 * i + 16]) for i in range(n)]
names = [e[2].rstrip(b"\0") for e in ents]
def pwad(lumps):
    body, dirs, pos = b"", b"", 12
    for name, data in lumps:
        dirs += struct.pack("<ii8s", pos, len(data), name)
        body += data; pos += len(data)
    return b"PWAD" + struct.pack("<ii", len(lumps), 12 + len(body)) + body + dirs
for src, marker, fname in ((b"MAP01", b"MAP01", "map01.wad"), (b"MAP02", b"MAP01", "map02_as_map01.wad"),
                           (b"MAP02", b"MAP07", "map02_as_map07.wad"), (b"MAP02", b"E1M1", "map02_as_e1m1.wad")):
    i = names.index(src)
    lumps = [(marker, b"")] + [(names[j], d[ents[j][0]: ents[j][0] + ents[j][1]]) for j in range(i + 1, i + 11)]
    open("%s/%s" % (out, fname), "wb").write(pwad(lumps))
open(out + "/empty.wad", "wb").write(pwad([]))
open(out + "/badmagic.wad", "wb").write(b"JUNK" + bytes(4092))
open(out + "/zero.wad", "wb").write(b"")
PY
box env -u DISPLAY timeout 20 /targets/doom_wad.afl "$T/map01.wad" > "$T/run.log" 2>&1; rc=$?
check "[ $rc = 0 ]" "doom_wad: a Freedoom MAP01 add-on runs headless and exits 0 (rc $rc)"
for f in badmagic.wad zero.wad; do
  box timeout 20 /targets/doom_wad.afl "$T/$f" > /dev/null 2>&1; rc=$?
  check "[ $rc != 124 ] && ! { [ $rc -gt 128 ] && [ $rc -lt 160 ]; }" "doom_wad: $f ends by itself without a signal or timeout (rc $rc; I_Error exits 255)"
done
e1=$(edges /targets/doom_wad.afl "$T/map01.wad"); e0=$(edges /targets/doom_wad.afl "$T/empty.wad")
check "[ ${e1:-0} -gt ${e0:-0} ]" "doom_wad: a MAP01 add-on reaches more edges than an empty one ($e1 vs $e0)"
sec2=$(python3 -c "
import struct
d=open('$T/map02_as_e1m1.wad','rb').read(); n,o=struct.unpack('<ii',d[4:12])
for i in range(n):
    p,l,nm=struct.unpack('<ii8s',d[o+16*i:o+16*i+16])
    if nm.rstrip(b'\\0')==b'SECTORS': print(l//26)")
for f in map02_as_map07.wad map02_as_e1m1.wad; do
  dbg=$(box env G2F_DOOM_DEBUG=1 timeout 20 /targets/doom_wad.afl "$T/$f" 2>&1 | grep '^g2f:' | tr '\n' ' ')
  check "echo '$dbg' | grep -q 'sectors $sec2,' && echo '$dbg' | grep -q 'leveltime 35'" "doom_wad: $f plays the add-on's map ($sec2 sectors) for 35 tics ($dbg)"
done
check "box bash -c 'nm /targets/doom_wad.afl | grep -qE \" T P_SetupLevel\$\" && nm /targets/doom_wad.afl | grep -qE \" T R_RenderPlayerView\$\"'" \
  "doom_wad.afl contains Doom's engine (P_SetupLevel, R_RenderPlayerView)"
m1=$(box bash -c "afl-showmap -q -o '$T/a' -t 10000 -- /targets/doom_wad.afl '$T/map01.wad' >/dev/null 2>&1; afl-showmap -q -o '$T/b' -t 10000 -- /targets/doom_wad.afl '$T/map02_as_map01.wad' >/dev/null 2>&1; diff -q '$T/a' '$T/b' >/dev/null && echo same || echo different")
check "[ '$m1' = different ]" "doom_wad: two different maps give different coverage"

# speed: 30 s of AFL++ each on XML and Doom
for t in xml_fuzzer:300 doom_wad:20; do
  n=${t%%:*}; floor=${t#*:}; mkdir -p "$T/in-$n"; box bash -c "cp /targets/seeds/$n/* '$T/in-$n/'"
  box bash -c "cd '$T' && AFL_NO_UI=1 AFL_NO_AFFINITY=1 AFL_SKIP_CPUFREQ=1 AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1 \
    timeout 150 afl-fuzz -i in-$n -o out-$n -t 10000 -V 30 -- /targets/$n.afl @@ > fuzz-$n.log 2>&1"
  eps=$(sed -n 's/^execs_per_sec *: *\([0-9]*\).*/\1/p' "$T/out-$n/default/fuzzer_stats" 2>/dev/null)
  check "[ ${eps:-0} -ge $floor ]" "AFL++ runs $n at $floor or more execs/s (got ${eps:-none})"
done
[ $fails = 0 ] && echo "all passed" || echo "$fails failed"
[ $fails = 0 ]
