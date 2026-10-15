#!/bin/bash
# Qwen3-Coder-Next-FP8 on vLLM: 2x H100 on gpufairshare (80 GB model, FP8). Queued: shares H100s with the whole cluster
# Start with: scripts/vllm/serve Qwen3-Coder-Next-FP8 [hours]
#SBATCH --job-name=Qwen3-Coder-Next-FP8
#SBATCH --partition=gpufairshare
#SBATCH --account=group-csci-591-automated-vulnerability-discovery
#SBATCH --gres=gpu:h100:2
#SBATCH --cpus-per-task=16
#SBATCH --mem=128G
#SBATCH --time=02:00:00
MODEL=Qwen3-Coder-Next-FP8 HF_REPO=Qwen/Qwen3-Coder-Next-FP8 TP=2 MAXLEN=32768 \
  exec bash "${VLLM_SERVE:-$SLURM_SUBMIT_DIR/scripts/vllm/vllm-serve.sh}"
