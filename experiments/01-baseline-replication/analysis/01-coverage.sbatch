#!/bin/bash
# Step 1, coverage: replays every file of one campaign's final queue on ONE common binary, the 4.32c tree's
# <program>.afl (g2f-targets/paper) with the WORKING image's afl-showmap (4.32c), AFL_MAP_SIZE=2621440 (DRIFT.md 3.2).
# Edge ids differ between AFL++ versions and builds, so each arm's own edges_found is NOT comparable; this is.
# One array task per campaign (analysis/campaigns.sh order). Per task: afl-showmap -i queue -o <node-local maps>,
# then coverage_aggregate.py turns the per-file maps into results/coverage/<campaign>.json (edges at the end,
# edges of the initial seeds alone, edges every 15 min from the queue's time: stamps) and
# results/coverage/edges/<campaign>.txt.gz (the sorted edge ids, for later set comparisons).
# Submit from this folder:  bash submit.sh 01      (= sbatch --array=0-<N-1>%50 01-coverage.sbatch)
# Rerun one campaign:       sbatch --array=<index> 01-coverage.sbatch   (index = line number in campaigns.sh - 1)
#SBATCH --job-name=g2f-B-coverage
#SBATCH --partition=fairshare
#SBATCH --account=group-csci-591-automated-vulnerability-discovery
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --time=3:00:00
#SBATCH --output=logs/coverage-%A_%a.out
set -u
A=${SLURM_SUBMIT_DIR:?submit from analysis/}; STUDY=$(cd "$A/.." && pwd); E=$STUDY/campaigns
SUB=""; [ "${G2F_PHASE:-B}" = B ] || SUB=/phase-${G2F_PHASE}; R=$STUDY/results$SUB/coverage
S=/home/group/csci-591-automated-vulnerability-discovery/students
TR=$S/g2f-targets/paper                      # the common binaries: 4.32c tree, paper versions
SIF=$S/WORKING-BETTERG2FUZZ/g2fuzz.sif       # afl-showmap 4.32c + python3
read -r name prog arm rep < <(bash "$A/campaigns.sh" "$E" | sed -n "$((SLURM_ARRAY_TASK_ID + 1))p")
[ -n "${name:-}" ] || { echo "no campaign for array index $SLURM_ARRAY_TASK_ID"; exit 1; }
Q=$E/$name/${prog}_output/default/queue
[ -d "$Q" ] || { echo "$name: no queue folder ($Q)"; exit 1; }
rt=$(awk -F: '/^run_time/ {gsub(/ /, "", $2); print $2}' "$E/$name/${prog}_output/default/fuzzer_stats" 2>/dev/null)
secs=$(grep -o -- '-V [0-9]*' "$E/$name/run.sh" 2>/dev/null | head -1 | awk '{print $2}'); secs=${secs:-21600}   # the campaign's own -V
[ "${rt:-0}" -ge "$secs" ] || echo "$name: WARNING run_time ${rt:-missing} < $secs (campaign cut short?)"
args=$(cat "$TR/$prog.args"); mkdir -p "$R/edges"
W=${TMPDIR:-/tmp}/g2f-cov-$SLURM_JOB_ID; mkdir -p "$W/maps"; trap 'rm -rf "$W"' EXIT
echo "$name: $(ls "$Q" | wc -l) queue files, replay on /targets/$prog.afl $args, start $(date +%T)"
# -m 1024: the SAME memory limit the campaigns used (afl-fuzz -m 1024), so every input behaves as it did during
#   fuzzing. (First run 2026-10-24 used -m none: imginfo and gdk-pixbuf inputs then allocated up to the task's 4 GB
#   cgroup and were killed, leaving partial traces; redone with -m 1024.)
# -t 10000: 10 s per input; inputs that hang are skipped by afl-showmap and counted as not replayed.
apptainer exec --cleanenv -B /home/group -B "$W" -B "$TR:/targets:ro" "$SIF" bash -c \
  "cd '$W' && AFL_MAP_SIZE=2621440 afl-showmap -q -i '$Q' -o '$W/maps' -m 1024 -t 10000 -- /targets/$prog.afl $args" \
  > "$W/showmap.log" 2>&1 || echo "$name: afl-showmap exit $? (see tail below)"
tail -n 3 "$W/showmap.log"
apptainer exec --cleanenv -B /home/group -B "$W" "$SIF" python3 "$A/coverage_aggregate.py" \
  --campaign "$name" --program "$prog" --arm "$arm" --rep "$rep" --queue "$Q" --maps "$W/maps" --out "$R" --secs "$secs"
chmod -R g+rwX "$R" 2>/dev/null; echo "$name: done $(date +%T)"
