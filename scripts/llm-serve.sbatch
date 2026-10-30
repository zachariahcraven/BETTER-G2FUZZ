#!/bin/bash
# Serves one model from students/shared-models with vLLM on one GPU, for G2Fuzz jobs on Tempest (README.md, Tempest setup).
# Start it with `scripts/fuzz llm start [hours] [a40|h100] [--model <folder>]`; runs then find it by themselves.
# Stop: `scripts/fuzz llm stop`. Its log, llm-serve-<jobid>.out, goes to ~/llm. The vLLM image is shared too.
# The model is G2F_SERVE_MODEL, a folder in shared-models (default Qwen3.8-27B-FP8), served under the same name;
# Qwen keeps its old name, Qwen3.8-27B-FP8-nothink.
# Thinking off: our G2Fuzz build gives up on an LLM call after 300 s (G2F_LLM_TIMEOUT), and a thinking model's long answers hit that.
#SBATCH -J llm-serve
#SBATCH -p gpupriority
#SBATCH --gres=gpu:a40:1
#SBATCH -c 8
#SBATCH --mem 64G
#SBATCH -t 02:00:00
#SBATCH -o llm-serve-%j.out
MODELS=/home/group/csci-591-automated-vulnerability-discovery/students/shared-models
MODEL=${G2F_SERVE_MODEL:-Qwen3.8-27B-FP8} NAME=${G2F_SERVE_MODEL:-Qwen3.8-27B-FP8}
SIF=$MODELS/containers/vllm-v0.31.0.sif
TEMPLATES=${G2F_REPO:-/nonexistent}/scripts/chat-templates   # scripts/fuzz passes G2F_REPO (sbatch runs a copy of this file)
PORT=$((20000 + SLURM_JOB_ID % 20000))   # scripts/fuzz computes the same port from the job ID
LLM_DIR="${LLM_DIR:-$HOME/llm}"
cd "$LLM_DIR" || exit 1
[ -f "$MODELS/$MODEL/config.json" ] || { echo "llm-serve: no model $MODEL in $MODELS"; exit 1; }
GPU_MIB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)
# Per-model settings. --max-model-len: 32768, or the model's own limit if smaller.
ARGS=(--max-model-len 32768)
case $MODEL in
  Qwen3.8-27B-FP8)   # its hybrid attention needs a --max-num-seqs cap
    NAME=$MODEL-nothink
    ARGS+=(--max-num-seqs 64 --reasoning-parser qwen3 --default-chat-template-kwargs '{"enable_thinking":false}') ;;
  phi-4)
    ARGS=(--max-model-len 16384) ;;
  starcoder2-15b-instruct-v0.1)   # its own template refuses the system messages G2Fuzz sends
    [ -f "$TEMPLATES/starcoder2-instruct.jinja" ] || { echo "llm-serve: no $TEMPLATES/starcoder2-instruct.jinja (start it with scripts/fuzz)"; exit 1; }
    ARGS=(--max-model-len 16384 --chat-template /templates/starcoder2-instruct.jinja) ;;
  Mistral-Small-3.1-24B-Instruct-2503)   # text only; 45 GB of bf16 weights don't fit an A40, so fp8 there
    ARGS+=(--limit-mm-per-prompt '{"image":0}')
    [ "$GPU_MIB" -lt 60000 ] && ARGS+=(--quantization fp8) ;;
esac
BINDS=(-B "$MODELS":/models -B "$MODELS/containers/patches":/patches)
[ -d "$TEMPLATES" ] && BINDS+=(-B "$TEMPLATES":/templates)
# Versions for the write-up: model revision (repo @ commit, from REVISIONS.txt if scripts/fetch-models got it), serving
# settings, vLLM, GPU
REV=$(grep " [^ ]*/$MODEL @" "$MODELS/REVISIONS.txt" 2>/dev/null | tail -1 | cut -d' ' -f2-4)
[ -n "$REV" ] || REV="$MODEL @ $(head -1 "$MODELS/$MODEL/.cache/huggingface/download/config.json.metadata" 2>/dev/null)"
{ echo "job $SLURM_JOB_ID on $(hostname), $(date '+%F %T')"
  echo "model: $NAME = $REV"
  echo "serve: ${ARGS[*]}"
  echo "vllm: $SIF"; nvidia-smi --query-gpu=name,memory.total --format=csv,noheader; echo; } | tee -a VERSIONS.txt
# Offline: no usage stats, no Hugging Face lookups. patches/ stubs out torchcodec, which crashes this vLLM image at
# import (text models don't need it).
export VLLM_NO_USAGE_STATS=1 DO_NOT_TRACK=1 HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1
apptainer exec --nv "${BINDS[@]}" --env PYTHONPATH=/patches "$SIF" \
  vllm serve /models/$MODEL --served-model-name $NAME --host 0.0.0.0 --port $PORT \
    --gpu-memory-utilization 0.90 "${ARGS[@]}"
