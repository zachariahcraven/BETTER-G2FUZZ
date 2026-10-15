#!/bin/bash
# Offline System One test: each decision model answers experiments/decision-model/data/decision-items.jsonl
# (experiments/decision-model/decision-data), then experiments/decision-model/decision-score compares them.
# One GPU; models run one after another in the vLLM container.
# Submit from the experiment workspace:  sbatch experiments/decision-model/decision-eval.sbatch   (MODELS="von" to run a subset)
#SBATCH --job-name=g2f-decision-eval
#SBATCH --partition=gpufairshare
#SBATCH --account=group-csci-591-automated-vulnerability-discovery
#SBATCH --gres=gpu:h100:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=03:00:00
#SBATCH --output=experiments/decision-model/logs/decision-eval-%j.out
X=/home/group/csci-591-automated-vulnerability-discovery/students/BETTER-G2FUZZ-exp
M=/home/group/csci-591-automated-vulnerability-discovery/students/shared-models
cd "$X" || exit 1
# Everything stays on Tempest: no Hugging Face lookups, no telemetry
export HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 HF_HUB_DISABLE_TELEMETRY=1 DO_NOT_TRACK=1
for m in ${MODELS:-von decider-2b clef-flash}; do
  apptainer exec --nv -B "$M" -B "$M/containers/patches":/patches \
    --env PYTHONPATH=/patches:$X/experiments/decision-model/pylib "$M/containers/vllm-v0.31.0.sif" \
    python3 experiments/decision-model/decision-eval "$m"
done
python3 experiments/decision-model/decision-score
