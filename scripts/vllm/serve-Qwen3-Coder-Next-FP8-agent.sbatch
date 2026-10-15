#!/bin/bash
# Qwen3-Coder-Next-FP8 for coding agents: same model and GPUs as serve-Qwen3-Coder-Next-FP8.sbatch, but
# 128k-token requests (agents send whole files) and OpenAI tool calling (qwen3_coder parser)
# Start with: scripts/vllm/serve Qwen3-Coder-Next-FP8-agent [hours]
#SBATCH --job-name=Qwen3-Coder-Next-FP8-agent
#SBATCH --partition=gpufairshare
#SBATCH --account=group-csci-591-automated-vulnerability-discovery
#SBATCH --gres=gpu:h100:2
#SBATCH --cpus-per-task=16
#SBATCH --mem=128G
#SBATCH --time=02:00:00
EXTRA_ARGS="--enable-auto-tool-choice --tool-call-parser qwen3_coder" \
  NAME=Qwen3-Coder-Next-FP8-agent MODEL=Qwen3-Coder-Next-FP8 HF_REPO=Qwen/Qwen3-Coder-Next-FP8 TP=2 MAXLEN=131072 \
  exec bash "${VLLM_SERVE:-$SLURM_SUBMIT_DIR/scripts/vllm/vllm-serve.sh}"
