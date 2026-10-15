#!/bin/bash
# gemma-4-31B-it on vLLM: 2x A40, tensor parallel (63 GB model, BF16, dense). Uses both CSCI 591 priority GPUs
# Start with: scripts/vllm/serve gemma-4-31B-it [hours]
#SBATCH --job-name=gemma-4-31B-it
#SBATCH --partition=gpupriority
#SBATCH --account=priority-csci-591-automated-vulnerability-discovery
#SBATCH --gres=gpu:a40:2
#SBATCH --cpus-per-task=16
#SBATCH --mem=128G
#SBATCH --time=02:00:00
MODEL=gemma-4-31B-it HF_REPO=google/gemma-4-31B-it TP=2 MAXLEN=32768 \
  exec bash "${VLLM_SERVE:-$SLURM_SUBMIT_DIR/scripts/vllm/vllm-serve.sh}"
