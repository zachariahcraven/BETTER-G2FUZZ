#!/bin/bash
# test_paper_targets.sh TREE VERSION [project ...]: checks targets built by targets/paper/<project>/build.sh into TREE
# (a /targets tree, e.g. .../students/g2f-targets/paper) against targets/paper/manifest.tsv, inside the plain run
# image (SIF, default this repo's g2fuzz.sif) with TREE bound over /targets. VERSION: paper or latest.
# Per target of the selected projects (default: every project in the manifest):
#   - <t>.afl/.cmp/.asan exist and are executable; .cmp has CmpLog and .asan AddressSanitizer
#   - <t>.args is the manifest's arguments (one line, exactly one @@); seeds/<t>/ has files
#   - BUILD-INFO.tsv records the manifest's pin for <t> and the sha256 of each of its three builds
#   - no shared library is missing in the run image (ldd), for each build
#   - stock seeds run (afl-showmap with the arguments, @@ = a private copy of the seed: some programs write
#     to their input or to the working folder): >= 1 seed exits 0 under .asan, the union of edges is > FLOOR
#     (default 50), two seeds reach different edges when there are two, and one seed gives the same edges twice
#   - MAGMA paper builds carry MAGMA's canaries (the magma_log symbol)
# Run on Tempest:  bash tests/image/test_paper_targets.sh <tree> paper [jhead ...]   (SIF=<image> FLOOR=<n>
#   BENCH=unifuzz|fuzzbench|magma: only that benchmark's rows, e.g. for libpng, which is in two)
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
TREE=$(cd "${1:?usage: test_paper_targets.sh TREE paper|latest [project ...]}" && pwd); VER=${2:?paper|latest}; shift 2
MAN=${MANIFEST:-$ROOT/targets/paper/manifest.tsv}
SIF=${SIF:-$ROOT/g2fuzz.sif}; FLOOR=${FLOOR:-50}
T=$(mktemp -d -p "$HOME"); trap 'rm -rf "$T"' EXIT
fails=0
check() { if eval "$1"; then echo "ok    $2"; else echo "FAIL  $2"; fails=$((fails + 1)); fi; }
box() { apptainer exec --cleanenv -B /home/group -B "$T" -B "$TREE:/targets:ro" --pwd "$T/w" "$SIF" "$@"; }
mkdir -p "$T/w"
# showmap T ARGS FILE OUTMAP: one run, @@ replaced by a private copy of FILE (same base name: some programs
# look at the extension). AFL_MAP_SIZE (FuzzBench's value): afl-showmap 4.32c aborts (FS_ERROR_MAP_SIZE) on
# maps > 64K without it, e.g. bloaty; a larger map does not change the edges reported
showmap() {
  local c="$T/in/$(basename "$3")"; mkdir -p "$T/in"; cp "$3" "$c"
  local a=${2//@@/$c}
  box bash -c "AFL_MAP_SIZE=2621440 ${PRE:-} afl-showmap -q -o '$4' -t 10000 -- /targets/$1.afl $a >/dev/null 2>&1; true"
  rm -f "$c"
}
rows=$(grep -v '^#' "$MAN" | awk -F'\t' -v v="$VER" -v b="${BENCH:-}" '($4 == v || index($4, v ":") == 1) && (b == "" || $2 == b)')
[ -n "$rows" ] || { echo "no manifest rows for version $VER"; exit 2; }
if [ $# -gt 0 ]; then
  sel=$(printf '%s\n' "$@"); rows=$(awk -F'\t' 'NR==FNR{p[$1]=1; next} p[$3]' <(echo "$sel") <(echo "$rows"))
  [ -n "$rows" ] || { echo "no manifest rows for projects: $*"; exit 2; }
fi
while IFS=$'\t' read -r t bench proj ver src pin args seeds fmts; do
  echo "== $t ($bench $proj $ver)"
  for v in afl cmp asan; do check "[ -x '$TREE/$t.$v' ]" "$t.$v exists and is executable"; done
  check "strings '$TREE/$t.cmp' | grep -q __cmplog" "$t.cmp has CmpLog instrumentation"
  check "strings '$TREE/$t.asan' | grep -q AddressSanitizer" "$t.asan has AddressSanitizer"
  check "[ \"\$(cat '$TREE/$t.args' 2>/dev/null)\" = '$args' ]" "$t.args is the manifest's arguments ($args)"
  n=$(ls "$TREE/seeds/$t" 2>/dev/null | wc -l)
  check "[ $n -gt 0 ]" "$t has stock seeds ($n in seeds/$t/)"
  info=$(awk -F'\t' -v t="$t" '$1 == t' "$TREE/BUILD-INFO.tsv" 2>/dev/null)
  check "[ \"\$(echo '$info' | cut -f2)\" = '$pin' ]" "BUILD-INFO.tsv records the manifest pin for $t"
  for v in afl cmp asan; do
    h=$(sha256sum < "$TREE/$t.$v" 2>/dev/null | cut -c1-64)
    check "echo '$info' | grep -q '$v=$h'" "BUILD-INFO.tsv has the sha256 of $t.$v"
    miss=$(box bash -c "ldd /targets/$t.$v 2>&1 | grep -c 'not found'")
    check "[ '${miss:-1}' = 0 ]" "$t.$v: no missing shared library in the run image"
  done
  case "$bench:$ver" in magma:paper)
    check "nm '$TREE/$t.afl' 2>/dev/null | grep -q magma_log" "$t.afl has MAGMA's canaries (magma_log)" ;;
  esac
  [ "$n" -gt 0 ] || continue
  ok=0; all="$T/all"; : > "$all"; first=""; second=""
  for s in "$TREE/seeds/$t"/*; do
    showmap "$t" "$args" "$s" "$T/m"; cut -d: -f1 "$T/m" 2>/dev/null >> "$all"
    if [ -z "$first" ]; then first=$s; cp "$T/m" "$T/m1" 2>/dev/null
    elif [ -z "$second" ] && ! cmp -s <(cut -d: -f1 "$T/m") <(cut -d: -f1 "$T/m1"); then second=$s; fi
    rm -f "$T/m"
    if [ $ok = 0 ]; then
      c="$T/in/$(basename "$s")"; mkdir -p "$T/in"; cp "$s" "$c"
      # Documented exception: gdk-pixbuf-pixdata (UNIFUZZ args `@@ /dev/null`) saves with g_file_set_contents, which
      # writes a temp file next to /dev/null: allowed as root in UNIFUZZ's Docker, refused in our non-root sandbox,
      # so every run exits 1 after parsing (2026-10-23). For it, exit 1 counts as a clean run (an ASan report exits 1
      # too, so the run's stderr must not contain one).
      # exiv2 (UNIFUZZ args `@@`): UNIFUZZ's jpg seeds carry no Exif, so exiv2 reports "No Exif data found" and
      # exits 253 on every one (20 of 20 seeds, 2026-10-23); 253 counts as clean for it, likewise without an ASan report.
      okrc=""; case $t in gdk-pixbuf-pixdata) okrc=1 ;; exiv2) okrc=253 ;; esac
      if [ -n "$okrc" ]; then
        box env ASAN_OPTIONS=detect_leaks=0 timeout 60 /targets/$t.asan ${args//@@/$c} >/dev/null 2>"$T/asan.err"; rc=$?
        { [ $rc = 0 ] || [ $rc = "$okrc" ]; } && ! grep -q "ERROR: AddressSanitizer" "$T/asan.err" && ok=1
      else
        box env ASAN_OPTIONS=detect_leaks=0 timeout 60 /targets/$t.asan ${args//@@/$c} >/dev/null 2>&1 && ok=1
      fi
      rm -f "$c"
    fi
  done
  e=$(sort -u "$all" | grep -c .)
  check "[ $ok = 1 ]" "$t.asan runs at least one stock seed and exits 0"
  # Documented exceptions: targets whose benchmark seed corpus is not in the target's input format, so the seeds
  # reach few edges and mostly the same ones. zlib: FuzzBench zips the zlib source/build folder's *.* files, none
  # of them zlib streams (2026-10-22). lcms: FuzzBench's seed folder is one ICC profile reaching 49 edges.
  # libpcap fuzz_both: FuzzBench has no corpus for it, so AFL starts from one file 'hi', which reaches 3 edges (floor 2).
  # flvmeta (UNIFUZZ args `@@`): all stock seeds are valid FLV files that take the same content-independent path
  # (20 of 20 seeds: exit 0, one identical 95-edge map, 2026-10-22), so the seeds-differ check is skipped.
  # exiv2 paper: its jpg seeds have no Exif, so all take one path (20 of 20: exit 253, one identical 527-edge map).
  fl=$FLOOR; sd=1
  case $t in zlib_zlib_uncompress_fuzzer) fl=30; sd=0 ;; lcms_cms_transform_fuzzer) fl=40 ;; libpcap_fuzz_both) fl=2 ;; flvmeta|exiv2) sd=0 ;; esac
  check "[ $e -gt $fl ]" "$t: stock seeds reach more than $fl edges (got $e)"
  [ "$n" -gt 1 ] && [ $sd = 1 ] && check "[ -n '$second' ]" "$t: two stock seeds reach different edges"
  # Documented exception: freetype's and bloaty's (latest) edges depend on heap addresses (ASLR): 1-3 edges between
  # runs of a PIE build, identical with ASLR off (checked 2026-10-22). FuzzBench builds them PIE too, so the
  # determinism check runs them with ASLR disabled instead of changing the build. Same for MAGMA poppler's pdftoppm and
  # pdf_fuzzer (paper): 5/6 seeds differ by 1 edge with ASLR, 6/6 identical with ASLR off; pdfimages 6/6 either way
  # (jobs 868369, 868530, 2026-10-23).
  PRE=""; case $t in freetype2_ftfuzzer|bloaty_fuzz_target|pdftoppm|pdf_fuzzer) PRE="setarch x86_64 -R" ;; esac
  PRE=$PRE showmap "$t" "$args" "$first" "$T/a"; PRE=$PRE showmap "$t" "$args" "$first" "$T/b"
  check "[ -s '$T/a' ] && cmp -s <(cut -d: -f1 '$T/a') <(cut -d: -f1 '$T/b')" "$t: the same input reaches the same edges twice"
  rm -f "$T/a" "$T/b" "$T/m1"
done <<< "$rows"
echo; echo "$fails failure(s)"; [ $fails = 0 ]
