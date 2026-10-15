#!/bin/bash
# compare_targets.sh OLD_DIR [per-target] [targets]: after an image rebuild, checks that the image's targets
# behave exactly like reference builds in OLD_DIR (<target>.afl/.asan, e.g. targets/bin or a copy of
# an older image's /targets). On a sample of real inputs from results/campaigns (queue entries and
# crashes, plus the stock seeds), it requires identical afl-showmap output (every edge and hit count)
# and, on crash files, the same AddressSanitizer verdict and top three stack frames (function and
# file:line; build ids, offsets and build paths are ignored). Inputs on which
# either build disagrees with itself over K runs (default 5; Doom crashes write to random memory, and
# 2 runs miss about half of those) are counted as flaky, not compared.
# Runs on Tempest from anywhere:  bash tests/image/compare_targets.sh targets/bin 40   (SIF=<image>;
#   TARGETS_DIR=<folder> compares that folder, bound over /targets, instead of the image's targets)
# 2026-10-15 (reorganized image vs pre-reorg binaries): jhead, tiff, png, xml identical on every input;
# doom_wad identical on every input that is stable in both builds (~20% of Doom crash inputs are flaky).
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OLD=$(cd "${1:?usage: compare_targets.sh OLD_DIR [per-target] [targets]}" && pwd); N=${2:-40}; K=${K:-5}
ONLY=${3:-jhead tiff_read_rgba_fuzzer libpng_read_fuzzer xml_fuzzer doom_wad}
SIF=${SIF:-$ROOT/g2fuzz.sif}
T=$(mktemp -d -p "$HOME"); trap 'rm -rf "$T"' EXIT
fails=0
check() { if eval "$1"; then echo "ok    $2"; else echo "FAIL  $2"; fails=$((fails + 1)); fi; }
box() { apptainer exec -B /home/group -B "$T" -B "$OLD:/old:ro" ${TARGETS_DIR:+-B "$TARGETS_DIR:/targets:ro"} "$SIF" "$@"; }
# every k-th file of a sorted list, at most n of them
pick() { sort | awk -v n="$1" '{ a[NR] = $0 } END { k = NR > n ? NR / n : 1; for (i = 1; i <= NR && c < n; i += k) { print a[int(i)]; c++ } }'; }
C=$ROOT/results/campaigns
# inputs: up to N queue entries and N crash files, spread over the campaigns (archive/ left out)
files() { for d in $C/*/$1-*-r*/; do case "$d" in */archive/*) continue ;; esac
  ls "$d$2" 2>/dev/null | grep '^id:' | sed "s|^|$d$2/|"; done; }

# Inside the image: for each input file, K runs of the old and K of the new build; prints one line per
# input: "same", "flaky" or "diff <file> ...". $1 = coverage | asan, $2 = target, $3 = input list.
cat > "$T/cmp.sh" <<'EOF'
mode=$1 n=$2 list=$3 K=$4 T=$(dirname "$3")
cov() { afl-showmap -q -o "$T/m" -t 10000 -m none -- "$1" "$2" >/dev/null 2>&1; md5sum < "$T/m" 2>/dev/null; rm -f "$T/m"; }
sig() { ASAN_SYMBOLIZER_PATH=/usr/lib/llvm-16/bin/llvm-symbolizer \
  ASAN_OPTIONS=detect_leaks=0:allocator_may_return_null=1:max_allocation_size_mb=1024 timeout 60 "$1" "$2" 2>&1 >/dev/null |
  awk '/ERROR: AddressSanitizer/ { sub(/.*ERROR: /, ""); sub(/ on .*/, ""); k = $0 }
       /^ *#[0-9]+ / && n < 3 { sub(/ \(BuildId: [0-9a-f]+\)/, ""); f = $NF; sub(/.*\//, "", f); sub(/\+0x[0-9a-f]+/, "", f)
                                 s = s " " $4 " " f; n++ } END { print k "|" s }'; }
f=${mode%%:*}; [ "$mode" = coverage ] && f=cov || f=sig
while read -r in; do
  o=$(for i in $(seq "$K"); do $f "/old/$n.$([ $f = cov ] && echo afl || echo asan)" "$in"; done | sort -u)
  w=$(for i in $(seq "$K"); do $f "/targets/$n.$([ $f = cov ] && echo afl || echo asan)" "$in"; done | sort -u)
  if [ "$(echo "$o" | wc -l)" != 1 ] || [ "$(echo "$w" | wc -l)" != 1 ]; then echo flaky
  elif [ "$o" = "$w" ]; then echo same; else echo "diff $in $o // $w"; fi
done < "$list"
EOF

for t in jhead:lineup tiff_read_rgba_fuzzer:tiff libpng_read_fuzzer:png xml_fuzzer:xml doom_wad:wad; do
  n=${t%%:*}; p=${t#*:}; case " $ONLY " in *" $n "*) ;; *) continue ;; esac
  { files $p ${n}_output/default/queue | pick "$N"; box bash -c "ls -d /targets/seeds/$n/*"; } > "$T/$n.in"
  files $p ${n}_output/default/crashes | pick "$N" > "$T/$n.crash"
  cat "$T/$n.crash" >> "$T/$n.in"
  box bash "$T/cmp.sh" coverage $n "$T/$n.in" "$K" > "$T/$n.cov"
  total=$(wc -l < "$T/$n.cov"); same=$(grep -c '^same$' "$T/$n.cov"); fl=$(grep -c '^flaky$' "$T/$n.cov")
  check "[ $same -gt 0 ] && [ $((same + fl)) = $total ]" "$n.afl: identical coverage maps on $same of $total inputs ($fl flaky; $(grep -m1 '^diff' "$T/$n.cov" | cut -c1-120))"
  if [ -s "$T/$n.crash" ]; then
    box bash "$T/cmp.sh" asan $n "$T/$n.crash" "$K" > "$T/$n.asan"
    total=$(wc -l < "$T/$n.asan"); same=$(grep -c '^same$' "$T/$n.asan"); fl=$(grep -c '^flaky$' "$T/$n.asan")
    check "[ $same -gt 0 ] && [ $((same + fl)) = $total ]" "$n.asan: same sanitizer verdict and top frames on $same of $total crash files ($fl flaky; $(grep -m1 '^diff' "$T/$n.asan" | cut -c1-160))"
  fi
done
[ $fails = 0 ] && echo "all passed" || echo "$fails failed"
[ $fails = 0 ]
