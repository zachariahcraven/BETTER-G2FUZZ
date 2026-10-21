#!/bin/bash
# Execs-matched replay (exploratory analysis): for every row of the plan written by
#   python3 experiments/analysis/lib/execs_matched.py plan      (-> results/tables/execs-matched-plan.csv)
# replay the campaign's queue entries with execs <= the experiment's cutoff (lib/seed_cov.py, same binaries as
# cov-replay) -> results/cov-execs/<campaign>.json; then `execs_matched.py table` and the stats tool on
# results/tables/execs-matched-cov.csv. Campaigns already replayed are skipped, so delete results/cov-execs/<c>.json
# when a cutoff changes. Symlink folders stay in the job's TMPDIR. Submit from the project root:
#   sbatch experiments/runners/execs-replay.sbatch      (G2F_TARGETS=<folder> replaces the image's /targets)
#SBATCH --job-name=g2f-execs-replay
#SBATCH --partition=fairshare
#SBATCH --account=group-csci-591-automated-vulnerability-discovery
#SBATCH --cpus-per-task=32
#SBATCH --mem=48G
#SBATCH --time=08:00:00
#SBATCH --output=results/logs/execs-replay-%j.out
X=/home/group/csci-591-automated-vulnerability-discovery/students/BETTER-G2FUZZ-exp
cd "$X" || exit 1
PLAN=${PLAN:-results/tables/execs-matched-plan.csv}; OUT=${OUT:-results/cov-execs}
EM=experiments/analysis/lib/execs_matched.py
mkdir -p "$OUT"
W=${TMPDIR:-/tmp}/em-$SLURM_JOB_ID; mkdir -p "$W"
one() {
  local e=$1 n=$2 t=$3 cut=$4
  [ -s "$OUT/$n.json" ] && return 0
  python3 "$EM" select "$n" "$cut" "$W/$n" > /dev/null || { echo "FAILED select $n"; return 0; }
  apptainer exec -B /home/group -B "$W" ${G2F_TARGETS:+-B "$G2F_TARGETS:/targets"} "$X/g2fuzz.sif" \
    python3 experiments/analysis/lib/seed_cov.py /targets/$t.afl "$W/$n" > "$W/$n.json" 2> "$W/$n.err" \
    && mv "$W/$n.json" "$OUT/$n.json" && echo "ok $n" || echo "FAILED replay $n: $(tail -2 "$W/$n.err")"
}
export -f one; export W OUT EM X G2F_TARGETS
tail -n +2 "$PLAN" | awk -F, '{print $1, $2, $4, $6}' | xargs -P 30 -n 4 bash -c 'one "$@"' _
echo "done: $(ls "$OUT"/*.json | wc -l) json files"
