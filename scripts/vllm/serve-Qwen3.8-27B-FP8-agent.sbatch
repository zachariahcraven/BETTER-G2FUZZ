#!/bin/bash
# Qwen3.8-27B-FP8 for coding agents, thinking on: slower than Qwen3-Coder-Next but reasons before it
# edits, for work where time doesn't matter (overnight butler tasks). 128k-token requests (agents send
# whole files) and OpenAI tool calling (qwen3_coder parser); the hybrid attention needs --max-num-seqs.
# Start with: scripts/vllm/serve Qwen3.8-27B-FP8-agent [hours]
#SBATCH --job-name=Qwen3.8-27B-FP8-agent
#SBATCH --partition=gpufairshare
#SBATCH --account=group-csci-591-automated-vulnerability-discovery
#SBATCH --gres=gpu:h100:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=02:00:00
EXTRA_ARGS="--reasoning-parser qwen3 --enable-auto-tool-choice --tool-call-parser qwen3_coder --max-num-seqs 64" \
  NAME=Qwen3.8-27B-FP8-agent MODEL=Qwen3.8-27B-FP8 HF_REPO=Qwen/Qwen3.8-27B-FP8 TP=1 MAXLEN=131072 \
  exec bash "${VLLM_SERVE:-$SLURM_SUBMIT_DIR/scripts/vllm/vllm-serve.sh}"
