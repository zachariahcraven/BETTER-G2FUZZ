#!/usr/bin/env bash
# test_map_guard.sh: regression test for ALF-1 (docs/KNOWN_BUGS.md). afl-compiler-rt must attach AFL's shared maps
# between PROT_NONE guard regions, so a heap overflow in the target faults (a crash, as it should be) instead of
# writing into the coverage map (thousands of fake edges; afl-fuzz 5.03c then stops: "Incorrect fuzzing setup").
#
# Usage (on Tempest from the repo root; needs apptainer and an image with AFL++, no GPU, about a minute):
#   scripts/tests/test_map_guard.sh [SIF]          SIF: default build/g2fuzz.sif (a builder image works too)
#   RT=installed scripts/tests/test_map_guard.sh   test the image's installed runtime instead of this repo's source
#   KEEP=1 scripts/tests/test_map_guard.sh         keep the temp folder (its path is printed)
# Inside an image (afl-clang-fast on PATH) it runs directly.
#
# It compiles afl/instrumentation/afl-compiler-rt.o.c the way the image's AFL++ build does (RT=repo, the default)
# into a copy of the image's AFL_PATH, and builds a small target with it: main() mallocs 20 MB (glibc mmap()s it,
# so it lands right below the newest mapping, which is AFL's map) and, for an input starting with "OVF", writes
# 64 KB past its end. Checks:
#   1. a normal input runs (afl-showmap exit 0); the OVF input crashes (exit 2) instead of filling the map
#   2. AFL_NO_MAP_GUARD=1 brings the bug back: the OVF input exits 0 with every map entry set (so the test would
#      notice a runtime without the guard)
#   3. a normal input gives the same map with and without the guard; AFL_DEBUG reports the guard
#   4. /proc/self/maps of the target: the coverage map sits between ---p regions of >= 1 MB, and in afl-fuzz -c
#      the CmpLog child's CmpLog map too (also shows the forkserver and CmpLog still work)
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RT=${RT:-repo}

# Outside an image: run this script inside one, with a private /tmp
if ! command -v afl-clang-fast >/dev/null 2>&1; then
  SIF=${1:-$REPO/build/g2fuzz.sif}
  [ -f "$SIF" ] || { echo "no image: $SIF" >&2; exit 2; }
  H=$(mktemp -d "${TMPDIR:-/tmp}/map-guard-test.XXXXXX")
  apptainer exec --cleanenv --no-mount home,cwd,tmp --bind "$H":/tmp --bind "$REPO":/repo:ro \
    --env RT="$RT",KEEP="${KEEP:-0}" "$SIF" bash /repo/scripts/tests/test_map_guard.sh 2>&1 | grep -v '^WARNING: Error changing'
  rc=${PIPESTATUS[0]}
  if [ "${KEEP:-0}" = 1 ]; then echo "temp folder (outside the image): $H"; else rm -rf "$H"; fi
  exit "$rc"
fi

T=$(mktemp -d /tmp/map-guard.XXXXXX)
if [ "${KEEP:-0}" = 1 ]; then echo "temp folder: $T"; else trap 'rm -rf "$T"' EXIT; fi
export AFL_SKIP_CPUFREQ=1 AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1 AFL_NO_AFFINITY=1 AFL_QUIET=1
unset AFL_NO_MAP_GUARD AFL_DEBUG
FAILS=0
ok() { echo "ok:   $*"; }
bad() { echo "FAIL: $*"; FAILS=$((FAILS + 1)); }

# --- the runtime ---------------------------------------------------------------------------------------------
LIB=${AFL_LIB:-/usr/local/lib/afl}
[ -f "$LIB/afl-compiler-rt.o" ] || { echo "no AFL++ runtime in $LIB (set AFL_LIB)" >&2; exit 2; }
P=$T/afl-path; mkdir -p "$P"; cp -a "$LIB"/. "$P"/
if [ "$RT" = repo ]; then
  # the flags of the image's own build (GNUmakefile.llvm; recorded in the installed object's debug info)
  CL=$(command -v clang-18 || command -v clang)
  mkdir -p "$T/rt"; cp -a "$REPO/afl/include" "$REPO/afl/instrumentation" "$T/rt"/
  (cd "$T/rt" && "$CL" -I ./include/ -I ./instrumentation/ -Wall -Wno-cast-qual -Wno-variadic-macros \
    -Wno-pointer-sign -Wno-unused-function -Wno-deprecated -Wno-unused-result -D AFL_PATH=\"/usr/local/lib/afl\" \
    -D BIN_PATH=\"/usr/local/bin\" -D VERSION=\"++5.03c\" -D USE_BINDIR=1 -O3 -fPIC \
    -c instrumentation/afl-compiler-rt.o.c -o "$P/afl-compiler-rt.o") || { echo "runtime build failed" >&2; exit 2; }
  cp "$P/afl-compiler-rt.o" "$P/afl-compiler-rt-64.o"
  echo "runtime: built from $REPO/afl/instrumentation/afl-compiler-rt.o.c"
else
  echo "runtime: installed ($LIB)"
fi

# --- the target ----------------------------------------------------------------------------------------------
cat > "$T/t.c" <<'EOF'
#define _GNU_SOURCE
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* ALF1_MAPS=<dir>: the first process of each program name writes /proc/self/maps to <dir>/maps-<name>. */
static void dump_maps(const char *name) {
  const char *dir = getenv("ALF1_MAPS");
  char path[4096], b[4096];
  ssize_t n;
  if (!dir) return;
  snprintf(path, sizeof path, "%s/maps-%s", dir, name);
  int out = open(path, O_WRONLY | O_CREAT | O_EXCL, 0644);
  if (out < 0) return;
  int in = open("/proc/self/maps", O_RDONLY);
  while (in >= 0 && (n = read(in, b, sizeof b)) > 0) {
    if (write(out, b, n) != n) break;
  }
  if (in >= 0) close(in);
  close(out);
}

__attribute__((noinline)) static void overflow(volatile unsigned char *end, size_t n) {
  for (size_t i = 0; i < n; i++) end[i] = 0xff;
}

int main(int argc, char **argv) {
  char hdr[4] = {0};
  const char *name = strrchr(argv[0], '/') ? strrchr(argv[0], '/') + 1 : argv[0];
  dump_maps(name);
  FILE *f = argc > 1 ? fopen(argv[1], "rb") : stdin;
  if (!f) return 1;
  size_t got = fread(hdr, 1, 3, f);
  if (f != stdin) fclose(f);
  size_t len = (size_t)20 << 20;          /* big enough for malloc() to mmap() it */
  unsigned char *buf = malloc(len);
  if (!buf) return 1;
  buf[0] = 1;
  if (got == 3 && hdr[0] == 'O' && hdr[1] == 'V' && hdr[2] == 'F') overflow(buf + len, (size_t)64 << 10);
  else if (got >= 1 && hdr[0] == 'A') puts("a");
  else if (got >= 1 && hdr[0] == 'B') puts("b");
  free(buf);
  return 0;
}
EOF
( cd "$T" && AFL_PATH=$P afl-clang-fast -O1 -o t t.c && AFL_PATH=$P AFL_LLVM_CMPLOG=1 afl-clang-fast -O1 -o t.cmp t.c ) \
  > "$T/build.log" 2>&1 || { cat "$T/build.log"; echo "target build failed" >&2; exit 2; }
if [ "$RT" = repo ]; then
  if nm "$T/t" | grep -q __alf_guard_reserve; then ok "the target links this repo's runtime (with the guard)"
  else bad "the target does not have the guard code (did afl-cc pick another afl-compiler-rt.o?)"; fi
fi
mkdir -p "$T/in"; printf 'AAAA' > "$T/in/a"; printf 'BBBB' > "$T/in/b"; printf 'OVF!' > "$T/ovf"

showmap() {  # showmap OUT INPUT [ENV=VAL ...]: afl-showmap exit code
  local o=$1 i=$2; shift 2
  env "$@" afl-showmap -q -o "$o" -t 5000 -m 1024 -- "$T/t" "$i" > /dev/null 2> "$o.err"
}

# 1. guard on
showmap "$T/m.a" "$T/in/a"; rc=$?
[ $rc = 0 ] && ok "normal input: exit 0, $(wc -l < "$T/m.a") map entries" || bad "normal input: afl-showmap exit $rc"
showmap "$T/m.ovf" "$T/ovf"; rc=$?
[ $rc = 2 ] && ok "OVF input: crash (afl-showmap exit 2), $(wc -l < "$T/m.ovf") map entries" \
  || bad "OVF input: afl-showmap exit $rc (want 2, a crash), $(wc -l < "$T/m.ovf") map entries"

# 2. guard off: the overflow writes into the map
showmap "$T/m.ovf0" "$T/ovf" AFL_NO_MAP_GUARD=1; rc=$?
na=$(wc -l < "$T/m.a"); no=$(wc -l < "$T/m.ovf0")
if [ $rc = 0 ] && [ "$no" -gt $((na * 4)) ]; then ok "AFL_NO_MAP_GUARD=1, OVF input: exit 0 and $no map entries (the old corruption)"
else bad "AFL_NO_MAP_GUARD=1, OVF input: exit $rc, $no map entries (want exit 0 and the map filled)"; fi

# 3. the map itself is unchanged by the guard
showmap "$T/m.a0" "$T/in/a" AFL_NO_MAP_GUARD=1
cmp -s "$T/m.a" "$T/m.a0" && ok "normal input: same map with and without the guard" || bad "normal input: the map differs with AFL_NO_MAP_GUARD=1"
showmap "$T/m.dbg" "$T/in/a" AFL_DEBUG=1
if grep -q "map guard: coverage map at" "$T/m.dbg.err"; then ok "AFL_DEBUG: $(grep -m1 'map guard: coverage map' "$T/m.dbg.err" | sed 's/^DEBUG: //')"
else bad "AFL_DEBUG does not report a coverage map guard"; fi

# 4. the layout: every writable SysV map between >= 1 MB of ---p
guarded() {  # guarded MAPSFILE: prints "guarded <bytes>" or "unguarded <bytes>" per rw-s SYSV mapping
  local -a S E P N; local n=0 j lo hi range perms rest
  while read -r range perms rest; do
    S[n]=$((16#${range%-*})); E[n]=$((16#${range#*-})); P[n]=$perms; N[n]=$rest; n=$((n + 1))
  done < "$1"
  for ((j = 0; j < n; j++)); do
    [[ ${N[j]} == *SYSV* && ${P[j]} == rw-s ]] || continue
    lo=0; hi=0
    if ((j > 0)) && [[ ${P[j-1]} == ---p ]] && ((E[j-1] == S[j] && E[j-1] - S[j-1] >= 1048576)); then lo=1; fi
    if ((j + 1 < n)) && [[ ${P[j+1]} == ---p ]] && ((S[j+1] == E[j] && E[j+1] - S[j+1] >= 1048576)); then hi=1; fi
    if ((lo && hi)); then echo "guarded $((E[j] - S[j]))"; else echo "unguarded $((E[j] - S[j]))"; fi
  done
}
mkdir -p "$T/maps1"; showmap "$T/m.l" "$T/in/a" ALF1_MAPS="$T/maps1"
g=$(guarded "$T/maps1/maps-t")
[ -n "$g" ] && ! grep -q unguarded <<< "$g" && ok "afl-showmap: shared maps $(tr '\n' ' ' <<< "$g")" \
  || bad "afl-showmap: shared maps not all guarded: $(tr '\n' ' ' <<< "${g:-none found}")"

mkdir -p "$T/maps2"
ALF1_MAPS="$T/maps2" AFL_NO_UI=1 timeout 60 afl-fuzz -i "$T/in" -o "$T/out" -c "$T/t.cmp" -m 1024 -V 5 -- "$T/t" @@ \
  > "$T/fuzz.log" 2>&1; rc=$?
execs=$(awk '/^execs_done/ {print $3}' "$T/out/default/fuzzer_stats" 2>/dev/null)
[ $rc = 0 ] && [ "${execs:-0}" -gt 0 ] && ok "afl-fuzz -c: ran $execs execs" || { bad "afl-fuzz -c: exit $rc, ${execs:-no} execs"; tail -5 "$T/fuzz.log"; }
g=$(guarded "$T/maps2/maps-t" 2>/dev/null)
[ -n "$g" ] && ! grep -q unguarded <<< "$g" && ok "afl-fuzz, main target: shared maps $(tr '\n' ' ' <<< "$g")" \
  || bad "afl-fuzz, main target: shared maps not all guarded: $(tr '\n' ' ' <<< "${g:-none found}")"
g=$(guarded "$T/maps2/maps-t.cmp" 2>/dev/null)
[ "$(grep -c '^guarded' <<< "$g")" -ge 2 ] && ! grep -q unguarded <<< "$g" \
  && ok "afl-fuzz, CmpLog target: shared maps $(tr '\n' ' ' <<< "$g")" \
  || bad "afl-fuzz, CmpLog target: want the coverage and CmpLog maps guarded: $(tr '\n' ' ' <<< "${g:-none found}")"

echo
if [ "$FAILS" = 0 ]; then echo "PASS: the shared maps are guarded"; else echo "FAILED: $FAILS check(s)"; fi
[ "$FAILS" = 0 ]
