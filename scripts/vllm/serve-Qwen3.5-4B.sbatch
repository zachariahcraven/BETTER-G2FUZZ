#!/bin/bash
# Qwen3.5-4B on vLLM: 1x A40 (9 GB model, BF16). Small, cheap model
# Start with: scripts/vllm/serve Qwen3.5-4B [hours]
#SBATCH --job-name=Qwen3.5-4B
#SBATCH --partition=gpupriority
#SBATCH --account=priority-csci-591-automated-vulnerability-discovery
#SBATCH --gres=gpu:a40:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=02:00:00
# Thinking off by default (small Qwen3.5 models reason for thousands of tokens before short
# answers). A client can send chat_template_kwargs={"enable_thinking": true}.
EXTRA_ARGS='--reasoning-parser qwen3 --default-chat-template-kwargs {"enable_thinking":false}' MODEL=Qwen3.5-4B HF_REPO=Qwen/Qwen3.5-4B TP=1 MAXLEN=32768 \
  exec bash "${VLLM_SERVE:-$SLURM_SUBMIT_DIR/scripts/vllm/vllm-serve.sh}"
