#!/bin/bash
# Qwen3.6-35B-A3B-FP8 on vLLM: 2x A40, tensor parallel (35 GB model). Uses both CSCI 591 priority GPUs
# Start with: scripts/vllm/serve Qwen3.6-35B-A3B-FP8 [hours]
#SBATCH --job-name=Qwen3.6-35B-A3B-FP8
#SBATCH --partition=gpupriority
#SBATCH --account=priority-csci-591-automated-vulnerability-discovery
#SBATCH --gres=gpu:a40:2
#SBATCH --cpus-per-task=16
#SBATCH --mem=128G
#SBATCH --time=02:00:00
# --reasoning-parser: Qwen3.6 thinks first; this keeps the thinking out of the reply text
EXTRA_ARGS="--reasoning-parser qwen3" MODEL=Qwen3.6-35B-A3B-FP8 HF_REPO=Qwen/Qwen3.6-35B-A3B-FP8 TP=2 MAXLEN=32768 \
  exec bash "${VLLM_SERVE:-$SLURM_SUBMIT_DIR/scripts/vllm/vllm-serve.sh}"
