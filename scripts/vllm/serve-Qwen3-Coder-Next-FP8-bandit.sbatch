#!/bin/bash
# Qwen3-Coder-Next-FP8 for the scheduler experiments (experiments/runners/run-bandit.sbatch): same model, GPUs and
# settings as serve-Qwen3-Coder-Next-FP8.sbatch, under its own name so the lineup runner, which stops
# its servers when its campaigns end, never stops this one
# Start with: scripts/vllm/serve Qwen3-Coder-Next-FP8-bandit [hours]
#SBATCH --job-name=Qwen3-Coder-Next-FP8-bandit
#SBATCH --partition=gpufairshare
#SBATCH --account=group-csci-591-automated-vulnerability-discovery
#SBATCH --gres=gpu:h100:2
#SBATCH --cpus-per-task=16
#SBATCH --mem=128G
#SBATCH --time=02:00:00
NAME=Qwen3-Coder-Next-FP8-bandit MODEL=Qwen3-Coder-Next-FP8 HF_REPO=Qwen/Qwen3-Coder-Next-FP8 TP=2 MAXLEN=32768 \
  exec bash "${VLLM_SERVE:-$SLURM_SUBMIT_DIR/scripts/vllm/vllm-serve.sh}"
