#!/bin/bash
# Qwen3.6-35B-A3B-FP8 with thinking off: same model and GPUs as serve-Qwen3.6-35B-A3B-FP8.sbatch,
# but answers directly (with thinking on, long calls hit G2Fuzz's 300 s LLM timeout)
# Start with: scripts/vllm/serve Qwen3.6-35B-A3B-FP8-nothink [hours]
#SBATCH --job-name=Qwen3.6-35B-A3B-FP8-nothink
#SBATCH --partition=gpupriority
#SBATCH --account=priority-csci-591-automated-vulnerability-discovery
#SBATCH --gres=gpu:a40:2
#SBATCH --cpus-per-task=16
#SBATCH --mem=128G
#SBATCH --time=02:00:00
# no spaces in the JSON: EXTRA_ARGS is split on spaces
EXTRA_ARGS='--reasoning-parser qwen3 --default-chat-template-kwargs {"enable_thinking":false}' \
  NAME=Qwen3.6-35B-A3B-FP8-nothink MODEL=Qwen3.6-35B-A3B-FP8 HF_REPO=Qwen/Qwen3.6-35B-A3B-FP8 TP=2 MAXLEN=32768 \
  exec bash "${VLLM_SERVE:-$SLURM_SUBMIT_DIR/scripts/vllm/vllm-serve.sh}"
