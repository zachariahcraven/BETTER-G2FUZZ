#!/bin/bash
# build-uncovered.sh QUEUES TARGET ...: makes <targets root>/paper/<target>.uncovered.json, the data of the
# `uncovered` stall mutator (g2fuzz/py_utils/uncovered.py): the target's functions that the campaigns in QUEUES
# entered but never finished, with their source and the lines no queue file reached marked.
#   QUEUES: a folder of campaign folders; every <QUEUES>/<target>-r*/<target>_output/default/queue is replayed
#           (A01 and A03 warm-start from A00's control arm: experiments/A00-baseline-6h/campaigns/control)
#   e.g. build/targets/build-uncovered.sh experiments/A00-baseline-6h/campaigns/control jhead mp3gain
# One Slurm job per target, inside its benchmark's builder image:
#   1. a source-coverage build: the target's own build.sh, unchanged, with afl-clang-fast and afl-clang-fast++
#      replaced on PATH by clang with -fprofile-instr-generate -fcoverage-mapping (so <target>.afl of this build
#      is the coverage binary), and its source folder kept;
#   2. every queue file run once through it (the target's .args, 10 s limit), profiles merged;
#   3. llvm-cov export, then uncovered.py's build_entries.
# Work and logs: <targets root>/uncovered/<target>/ (build/, src/, prof/, cov.json, log). Nothing in paper/ but the
# .uncovered.json is touched.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); REPO=$(cd "$HERE/../.." && pwd)
ROOT=${G2F_TARGETS_ROOT:-/home/group/csci-591-automated-vulnerability-discovery/students/g2f-targets-alfred}
Q=${1:?usage: build-uncovered.sh QUEUES TARGET ...}; shift
Q=$(cd "$Q" && pwd)
[ $# -gt 0 ] || { echo "name at least one target (e.g. jhead)" >&2; exit 2; }
ACCOUNT=${G2F_ACCOUNT:-group-csci-591-automated-vulnerability-discovery}; PARTITION=${G2F_PARTITION:-fairshare}

for t in "$@"; do
  row=$(grep -v '^#' "$HERE/manifest.tsv" | awk -F'\t' -v t="$t" '$1 == t && $4 == "paper"')
  [ -n "$row" ] || { echo "no paper row for $t in manifest.tsv" >&2; exit 2; }
  b=$(echo "$row" | cut -f2); p=$(echo "$row" | cut -f3)
  case $b in unifuzz|fuzzbench) bsif=$ROOT/builder-$b.sif ;; magma) bsif=$ROOT/builder-magma-$p.sif ;; esac
  [ -f "$bsif" ] || { echo "builder image missing: $bsif" >&2; exit 2; }
  ls -d "$Q/$t"-r*/"${t}_output/default/queue" >/dev/null 2>&1 || { echo "no queues for $t under $Q" >&2; exit 2; }
  U=$ROOT/uncovered/$t
  mkdir -p "$U"
  cat > "$U/inside.sh" <<'EOS'
set -euo pipefail
# inside the builder image. Given: U (work folder), T (target), BUILD (its build.sh), Q (campaigns), UNCOVERED_PY
rm -rf "$U/build" "$U/src" "$U/prof" "$U/bin"; mkdir -p "$U/build" "$U/src" "$U/prof" "$U/bin"
COV="-fprofile-instr-generate -fcoverage-mapping -g"
# libFuzzer harnesses (FuzzBench, MAGMA): -fsanitize=fuzzer and libAFLDriver.a become a main() that runs each file named on the
# command line once (libFuzzer's own runtime doesn't link with -stdlib=libc++ builds)
cat > "$U/bin/standalone.c" <<'EOC'
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
extern int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size);
__attribute__((weak)) extern int LLVMFuzzerInitialize(int *argc, char ***argv);
int main(int argc, char **argv) {
  if (LLVMFuzzerInitialize) LLVMFuzzerInitialize(&argc, &argv);
  for (int i = 1; i < argc; i++) {
    FILE *f = fopen(argv[i], "rb"); if (!f) continue;
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    uint8_t *buf = malloc(n ? n : 1); size_t got = fread(buf, 1, n, f); fclose(f);
    LLVMFuzzerTestOneInput(buf, got); free(buf);
  }
  return 0;
}
EOC
clang -O1 -c "$U/bin/standalone.c" -o "$U/bin/standalone.o"
# libAFLDriver.a is replaced by an archive, as it is one: MAGMA's libtiff has it in LIBS for every link, also of
# configure's test programs and of tiffcp, which have a main() of their own (an object would define main twice)
ar rcs "$U/bin/standalone.a" "$U/bin/standalone.o"
for cc in clang clang++; do
  w="$U/bin/afl-clang-fast"; [ $cc = clang ] || w="$w++"
  cat > "$w" <<EOF
#!/bin/bash
args=(); compile=0
for a in "\$@"; do case \$a in -c|-E|-S) compile=1 ;; esac; done
for a in "\$@"; do
  case \$a in
    -fsanitize=fuzzer) [ \$compile = 1 ] || args+=("$U/bin/standalone.o") ;;
    */libAFLDriver.a) [ \$compile = 1 ] || args+=("$U/bin/standalone.a") ;;
    -fsanitize=fuzzer-no-link) ;;
    *) args+=("\$a") ;;
  esac
done
exec $cc $COV "\${args[@]}"
EOF
done
# build.sh removes its work folder (mktemp -d under TMPDIR) when it ends: keep everything under $U/src
cat > "$U/bin/rm" <<EOF
#!/bin/bash
for a in "\$@"; do case \$a in "$U/src"/*/*) ;; "$U/src"/*) exit 0 ;; esac; done
exec /bin/rm "\$@"
EOF
chmod +x "$U/bin/afl-clang-fast" "$U/bin/afl-clang-fast++" "$U/bin/rm"
echo "== coverage build of $T ($(date '+%F %T'))"
TMPDIR="$U/src" PATH="$U/bin:$PATH" LLVM_PROFILE_FILE=/dev/null bash "$BUILD" paper "$U/build" > "$U/build.log" 2>&1 ||
  { tail -20 "$U/build.log"; echo "build failed: $U/build.log"; exit 1; }
BIN="$U/build/$T.afl"; ARGS=$(cat "$U/build/$T.args")
echo "== replay ($(date '+%F %T'))"
n=0
for q in "$Q/$T"-r*/"${T}_output/default/queue"; do
  for f in "$q"/id:*; do
    n=$((n + 1)); echo "$f"
  done
done > "$U/files.txt"
echo "$(wc -l < "$U/files.txt") queue files"
export BIN ARGS U
run_one() {   # one queue file through the binary; %m: profiles merge in place, 1 file per worker pool slot
  local w; w=$(mktemp -d -p /tmp); cd "$w"
  ulimit -v 4194304   # 4 GB: imginfo (jasper) otherwise takes the job's memory with 16 runs at once
  cp "$1" "$w/input"   # not the queue file itself: tiffcp reads the commas in "id:000001,src:..." as "file,image number"
  LLVM_PROFILE_FILE="$U/prof/%8m.profraw" timeout 10 "$BIN" ${ARGS//@@/"$w/input"} > /dev/null 2>&1 < /dev/null || true
  cd /; /bin/rm -rf "$w"
}
export -f run_one
xargs -a "$U/files.txt" -d '\n' -P "$(nproc)" -n 1 bash -c 'run_one "$0"'
llvm-profdata-18 merge -sparse "$U"/prof/*.profraw -o "$U/all.profdata"
llvm-cov-18 report "$BIN" -instr-profile="$U/all.profdata" 2>/dev/null | tail -1
llvm-cov-18 export "$BIN" -instr-profile="$U/all.profdata" -format=text > "$U/cov.json" 2>/dev/null
python3 - "$U" "$T" "$UNCOVERED_PY" <<'PY'
import glob, importlib.util, json, re, sys, time
u, target, path = sys.argv[1:4]
spec = importlib.util.spec_from_file_location("uncovered", path); mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
def read_source(p):
    # an out-of-tree build (ffmpeg: <work>/build-afl, removed when build.sh ends) names its sources in the build
    # folder: they are in <work>/src or <work>/src/<project folder>
    m = re.match(r"(.*)/build-[^/]+/(.*)", p)
    more = [m.group(1) + "/src/" + m.group(2)] + glob.glob(m.group(1) + "/src/*/" + m.group(2)) if m else []
    for q in [p] + more:
        try:
            with open(q, errors="replace") as f:
                return f.read().split("\n")
        except OSError:
            pass
    return None
entries = mod.build_entries(json.load(open(u + "/cov.json")), read_source)
json.dump({"target": target, "made": time.strftime("%Y-%m-%d %H:%M"), "files": sum(1 for _ in open(u + "/files.txt")),
           "entries": entries}, open(u + "/%s.uncovered.json" % target, "w"), indent=1)
print("%s: %d functions entered but not finished, %d lines never executed" % (
    target, len(entries), sum(e["missed"] for e in entries)))
PY
EOS
  sbatch --parsable -A "$ACCOUNT" -p "$PARTITION" -c 16 --mem 32G -t 08:00:00 --no-requeue \
    -J "alfred-uncovered-$t" -o "$U/log" --wrap "set -e
    apptainer exec --cleanenv -B /home/group -B '$REPO' --env U=$U,T=$t,BUILD=$HERE/$b/$p/build.sh,Q=$Q,UNCOVERED_PY=$REPO/g2fuzz/py_utils/uncovered.py,RUN_LIBS=$ROOT/run-libs.txt,G2F_BUILDER=uncovered \
      '$bsif' bash '$U/inside.sh'
    mkdir -p '$ROOT/paper' && cp '$U/$t.uncovered.json' '$ROOT/paper/$t.uncovered.json'
    echo 'build-uncovered: $t done: $ROOT/paper/$t.uncovered.json'"
done
