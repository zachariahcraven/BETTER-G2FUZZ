#!/bin/bash
# Submits step 01 (coverage) or 02 (crashes) as a Slurm array with one task per campaign in campaigns.sh.
# Usage, from analysis/:  bash submit.sh 01 [extra sbatch options, e.g. --partition=priority --account=...]
#                         CAP=1 bash submit.sh 02 ...   (crash triage with the 1 GB allocation cap -> results/crashes-cap1g/)
set -eu; cd "$(dirname "$0")"
step=${1:?usage: submit.sh 01|02 [sbatch options]}; shift
case $step in 01) f=01-coverage.sbatch;; 02) f=02-crashes.sbatch;; *) echo "step must be 01 or 02" >&2; exit 1;; esac
n=$(bash campaigns.sh | wc -l); [ "$n" -gt 0 ] || { echo "no campaigns" >&2; exit 1; }
name=""; [ "$step" = 02 ] && [ "${CAP:-0}" = 1 ] && name="--job-name=g2f-B-crashes-cap1g"
mkdir -p logs; echo "$n campaigns (phase ${G2F_PHASE:-B}) -> CAP=${CAP:-0} sbatch --array=0-$((n - 1))%50 $name $* $f"
sbatch --export=ALL,CAP=${CAP:-0},G2F_PHASE=${G2F_PHASE:-B} --array=0-$((n - 1))%50 $name "$@" "$f"
