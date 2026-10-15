#!/bin/bash
# Qwen3.8-27B-FP8 with thinking off, for G2Fuzz: 1x H100 (31 GB model, FP8). Answers directly (with
# thinking on, long calls risk G2Fuzz's 300 s LLM timeout); the hybrid attention needs --max-num-seqs.
# Start with: scripts/vllm/serve Qwen3.8-27B-FP8-nothink [hours]
#SBATCH --job-name=Qwen3.8-27B-FP8-nothink
#SBATCH --partition=gpufairshare
#SBATCH --account=group-csci-591-automated-vulnerability-discovery
#SBATCH --gres=gpu:h100:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=02:00:00
# no spaces in the JSON: EXTRA_ARGS is split on spaces
EXTRA_ARGS='--reasoning-parser qwen3 --default-chat-template-kwargs {"enable_thinking":false} --max-num-seqs 64' \
  NAME=Qwen3.8-27B-FP8-nothink MODEL=Qwen3.8-27B-FP8 HF_REPO=Qwen/Qwen3.8-27B-FP8 TP=1 MAXLEN=32768 \
  exec bash "${VLLM_SERVE:-$SLURM_SUBMIT_DIR/scripts/vllm/vllm-serve.sh}"
