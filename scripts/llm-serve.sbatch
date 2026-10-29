#!/bin/bash
# Serves Qwen3.8-27B-FP8 (thinking off) with vLLM on one GPU, for G2Fuzz jobs on Tempest (README.md, Tempest setup).
# Start it with `scripts/fuzz llm start [hours] [a40|h100]`; runs then find it by themselves. Stop: `scripts/fuzz llm stop`.
# Its log, llm-serve-<jobid>.out, goes to ~/llm. Model weights and the vLLM image are shared: students/shared-models.
# Thinking off: G2Fuzz gives up on an LLM call after 300 s, and a thinking model's long answers hit that.
#SBATCH -J llm-serve
#SBATCH -p gpupriority
#SBATCH --gres=gpu:a40:1
#SBATCH -c 8
#SBATCH --mem 64G
#SBATCH -t 02:00:00
#SBATCH -o llm-serve-%j.out
MODELS=/home/group/csci-591-automated-vulnerability-discovery/students/shared-models
MODEL=Qwen3.8-27B-FP8 NAME=Qwen3.8-27B-FP8-nothink
SIF=$MODELS/containers/vllm-v0.31.0.sif
PORT=$((20000 + SLURM_JOB_ID % 20000))   # scripts/fuzz computes the same port from the job ID
LLM_DIR="${LLM_DIR:-$HOME/llm}"
cd "$LLM_DIR" || exit 1
# Versions for the write-up: model revision, vLLM, GPU
{ echo "job $SLURM_JOB_ID on $(hostname), $(date '+%F %T')"
  echo "model: $NAME = Qwen/$MODEL @ $(head -1 "$MODELS/$MODEL/.cache/huggingface/download/config.json.metadata" 2>/dev/null)"
  echo "vllm: $SIF"; nvidia-smi --query-gpu=name,memory.total --format=csv,noheader; echo; } | tee -a VERSIONS.txt
# Offline: no usage stats, no Hugging Face lookups. patches/ stubs out torchcodec, which crashes this vLLM image at
# import (text models don't need it). --max-num-seqs: Qwen3.8's hybrid attention needs a cap.
export VLLM_NO_USAGE_STATS=1 DO_NOT_TRACK=1 HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1
apptainer exec --nv -B "$MODELS":/models -B "$MODELS/containers/patches":/patches --env PYTHONPATH=/patches "$SIF" \
  vllm serve /models/$MODEL --served-model-name $NAME --host 0.0.0.0 --port $PORT \
    --max-model-len 32768 --gpu-memory-utilization 0.90 --max-num-seqs 64 \
    --reasoning-parser qwen3 --default-chat-template-kwargs '{"enable_thinking":false}'
