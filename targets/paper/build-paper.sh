#!/bin/bash
# build-paper.sh paper|latest BENCH/PROJECT ...: builds the G2FUZZ paper's targets (targets/paper/manifest.tsv) on
# Tempest, one Slurm job per project, each inside its benchmark's builder image (docker/Dockerfile.targets), then
# tests them in the plain run images (tests/image/test_paper_targets.sh) and only then copies them into the
# shared tree $G2F_TARGETS_ROOT/<version>/ (a complete /targets folder for G2F_TARGETS).
#   e.g. targets/paper/build-paper.sh paper unifuzz/jhead magma/libpng
# Builds are staged in $G2F_TARGETS_ROOT/stage/<version>/<bench>-<project>/ and logged in
# $G2F_TARGETS_ROOT/logs/. A project whose test fails is not copied into the tree.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); REPO=$(cd "$HERE/../.." && pwd)
ROOT=${G2F_TARGETS_ROOT:-/home/group/csci-591-automated-vulnerability-discovery/students/g2f-targets}
G=/home/group/csci-591-automated-vulnerability-discovery/students
RUN_SIFS=${RUN_SIFS:-"$G/WORKING-BETTERG2FUZZ/g2fuzz.sif $G/BETTER-G2FUZZ-exp/g2fuzz.sif"}
V=${1:?usage: build-paper.sh paper|latest BENCH/PROJECT ...}; shift
case $V in paper|latest) ;; *) echo "version must be paper or latest" >&2; exit 2;; esac
[ $# -gt 0 ] || { echo "name at least one BENCH/PROJECT (e.g. unifuzz/jhead)" >&2; exit 2; }
mkdir -p "$ROOT/$V" "$ROOT/stage/$V" "$ROOT/logs"

# libraries present in every run image: binaries may use these, everything else is bundled into lib/
RUN_LIBS=$ROOT/run-libs.txt
if [ ! -s "$RUN_LIBS" ]; then
  n=0; for s in $RUN_SIFS; do apptainer exec "$s" ldconfig -p | awk 'NR > 1 {print $1}' | sort -u > "$ROOT/run-libs.$n"; n=$((n + 1)); done
  cp "$ROOT/run-libs.0" "$RUN_LIBS.tmp"
  for f in "$ROOT"/run-libs.[1-9]*; do [ -e "$f" ] && comm -12 "$RUN_LIBS.tmp" "$f" > "$RUN_LIBS.t2" && mv "$RUN_LIBS.t2" "$RUN_LIBS.tmp"; done
  mv "$RUN_LIBS.tmp" "$RUN_LIBS"
fi

for bp in "$@"; do
  b=${bp%%/*}; p=${bp#*/}
  [ -f "$HERE/$b/$p/build.sh" ] || { echo "no $HERE/$b/$p/build.sh" >&2; exit 2; }
  case $b in unifuzz|fuzzbench) bsif=$ROOT/builder-$b.sif ;; magma) bsif=$ROOT/builder-magma-$p.sif ;;
    *) echo "unknown benchmark $b" >&2; exit 2 ;; esac
  [ -f "$bsif" ] || { echo "builder image missing: $bsif" >&2; exit 2; }
  st=$ROOT/stage/$V/$b-$p; log=$ROOT/logs/$V-$b-$p
  # one test command per run image; all must pass before the copy into the tree
  tests=""; for s in $RUN_SIFS; do tests+="BENCH=$b SIF=$s bash $REPO/tests/image/test_paper_targets.sh $st $V $p >> $log.test 2>&1 && "; done
  sbatch --parsable -A group-csci-591-automated-vulnerability-discovery -p fairshare -c 16 --mem 32G -t 08:00:00 \
    -J "g2f-build-$V-$b-$p" -o "$log.out" --wrap "set -e
    if [ -e '$st' ]; then mv '$st' '$st'.old-\$(date +%s); fi; mkdir -p '$st'
    apptainer exec --cleanenv -B /home/group --env RUN_LIBS=$RUN_LIBS,G2F_BUILDER=$(basename "$bsif")@\$(sha256sum < '$bsif' | cut -c1-12) \
      '$bsif' bash '$HERE/$b/$p/build.sh' $V '$st'
    cat '$st'/build-info/*.tsv > '$st/BUILD-INFO.tsv'
    : > '$log.test'; ${tests} true
    cp -a '$st'/. '$ROOT/$V'/ && rm -f '$ROOT/$V/BUILD-INFO.tsv' && cat '$ROOT/$V'/build-info/*.tsv > '$ROOT/$V/BUILD-INFO.tsv'
    echo 'build-paper: $V $b/$p built, tested and copied into $ROOT/$V'"
done
