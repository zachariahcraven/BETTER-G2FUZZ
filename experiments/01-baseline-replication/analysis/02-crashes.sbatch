#!/bin/bash
# Step 2, bugs: reruns every saved crash of one campaign on the ASan build of the same target
# (g2f-targets/paper/<program>.asan, built by targets/paper/build-paper.sh; DRIFT.md 2.2) inside the WORKING image,
# and deduplicates by the top 3 frames of the ASan stack trace (UNIFUZZ's rule, as in the paper).
# One array task per campaign (analysis/campaigns.sh order); crash_triage.py does the work and writes
# results/crashes/<campaign>.tsv (one line per crash file) and results/crashes/<campaign>.json (the buckets).
# Submit from this folder:  bash submit.sh 02      (= sbatch --array=0-<N-1>%50 02-crashes.sbatch)
# Variant (user-approved 2026-10-25): CAP=1 bash submit.sh 02 ... reruns the triage with the ASan allocation cap
# max_allocation_size_mb=1024 (an allocation over 1 GB becomes an 'allocation-size-too-big' report, the analog of
# afl-fuzz's -m 1024 that saved those inputs as crashes) into results/crashes-cap1g/; 03-stats.py reports both.
#SBATCH --job-name=g2f-B-crashes
#SBATCH --partition=fairshare
#SBATCH --account=group-csci-591-automated-vulnerability-discovery
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --time=3:00:00
#SBATCH --output=logs/crashes-%A_%a.out
set -u
A=${SLURM_SUBMIT_DIR:?submit from analysis/}; STUDY=$(cd "$A/.." && pwd); E=$STUDY/campaigns
SUB=""; [ "${G2F_PHASE:-B}" = B ] || SUB=/phase-${G2F_PHASE}; R=$STUDY/results$SUB/crashes
EXTRA=""; if [ "${CAP:-0}" = 1 ]; then R=$STUDY/results$SUB/crashes-cap1g; EXTRA="max_allocation_size_mb=1024:allocator_may_return_null=0"; fi
S=/home/group/csci-591-automated-vulnerability-discovery/students
TR=$S/g2f-targets/paper; SIF=$S/WORKING-BETTERG2FUZZ/g2fuzz.sif
read -r name prog arm rep < <(bash "$A/campaigns.sh" "$E" | sed -n "$((SLURM_ARRAY_TASK_ID + 1))p")
[ -n "${name:-}" ] || { echo "no campaign for array index $SLURM_ARRAY_TASK_ID"; exit 1; }
C=$E/$name/${prog}_output/default/crashes; mkdir -p "$R"
[ -d "$C" ] || { echo "$name: no crashes folder"; exit 1; }
W=${TMPDIR:-/tmp}/g2f-crash-$SLURM_JOB_ID; mkdir -p "$W"; trap 'rm -rf "$W"' EXIT
echo "$name: $(ls "$C" | grep -vc README) crash files, start $(date +%T)"
apptainer exec --cleanenv -B /home/group -B "$W" -B "$TR:/targets:ro" "$SIF" python3 "$A/crash_triage.py" \
  --campaign "$name" --program "$prog" --arm "$arm" --rep "$rep" --crashes "$C" --args "$(cat "$TR/$prog.args")" \
  --binary "/targets/$prog.asan" --workdir "$W" --out "$R" --asan-extra "$EXTRA"
chmod -R g+rwX "$R" 2>/dev/null; echo "$name: done $(date +%T)"
