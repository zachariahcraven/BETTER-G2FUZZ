#!/bin/bash
# Common vLLM launcher for the serve-<model>.sbatch scripts in this folder. Start servers with
# scripts/vllm/serve, which passes VLLM_SERVE (this file) and G2F_VLLM_DIR to the job.
# Inputs from the sbatch script: MODEL (folder in shared-models), HF_REPO, TP (GPUs), MAXLEN,
# optional NAME (served model name and endpoint files; default MODEL, for variants of one model).
#
# While the job runs, $G2F_VLLM_DIR/endpoints/<model>.env holds what chat clients and
# scripts/fuzz need: G2F_BASE_URL, G2F_KEY (key file), G2F_MODEL, LLM_END, G2F_LLM_VERSIONS.
# Every start is also appended to $G2F_VLLM_DIR/VERSIONS.txt for the write-up.
set -u
HERE=$(dirname "${VLLM_SERVE:-$SLURM_SUBMIT_DIR/scripts/vllm/vllm-serve.sh}")
DIR=${G2F_VLLM_DIR:-$HOME/llm-jobs}
MODELS=${G2F_MODELS:-/home/group/csci-591-automated-vulnerability-discovery/students/shared-models}
SIF=${G2F_VLLM_SIF:-$MODELS/containers/vllm-v0.31.0.sif}
EP=$DIR/endpoints
NAME=${NAME:-$MODEL}
TP=${TP:-1}
MAXLEN=${MAXLEN:-32768}
SETTINGS="--tensor-parallel-size $TP --max-model-len $MAXLEN --gpu-memory-utilization 0.90 ${EXTRA_ARGS:-}"

# Random high port (GPU nodes are shared) and a per-job API key so other users can't use it.
PORT=$((20000 + RANDOM % 20000))
mkdir -p "$EP" && chmod 700 "$EP"
KEYFILE=$EP/$NAME.key
(umask 077; openssl rand -hex 16 > "$KEYFILE")
END=$(squeue -h -j "$SLURM_JOB_ID" -o %e)

# Exact versions, so every campaign can record which server and model it used.
REV=$(head -1 "$MODELS/$MODEL/.cache/huggingface/download/config.json.metadata" 2>/dev/null || echo unknown)
VLLM_VER=$(apptainer exec "$SIF" python3 -c 'import vllm; print(vllm.__version__)' 2>/dev/null | tail -1)
GPUS=$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader | sort | uniq -c | sed 's/^ *//' | paste -sd ';')
cat > "$EP/$NAME.versions" <<VER
vLLM server for G2Fuzz (scripts/vllm), job $SLURM_JOB_ID on $(hostname), started $(date '+%F %T')
model: $NAME = $HF_REPO @ $REV
vllm: ${VLLM_VER:-unknown} ($SIF)
gpus: $GPUS
settings: $SETTINGS
VER
{ cat "$EP/$NAME.versions"; echo; } >> "$DIR/VERSIONS.txt"

cat > "$EP/$NAME.env" <<ENV
G2F_BASE_URL=http://$(hostname):$PORT/v1
G2F_KEY=$KEYFILE
G2F_MODEL=$NAME
G2F_LLM_VERSIONS=$EP/$NAME.versions
LLM_END=$END
LLM_JOB=$SLURM_JOB_ID
ENV
# Remove the files only if they still belong to this job (a newer job may have replaced them).
trap 'grep -q "LLM_JOB=$SLURM_JOB_ID$" "$EP/$NAME.env" 2>/dev/null && rm -f "$EP/$NAME.env" "$EP/$NAME.versions" "$KEYFILE"' EXIT

# Keep everything on Tempest: no usage stats, no Hugging Face lookups.
export VLLM_NO_USAGE_STATS=1 DO_NOT_TRACK=1 HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1

cat <<INFO
=== $NAME on $(hostname), port $PORT, $TP GPU(s), job $SLURM_JOB_ID, ends $END ===
$(cat "$EP/$NAME.versions")
Endpoint file: $EP/$NAME.env   (API key in $KEYFILE)
Chat from your Mac (MSU VPN on):
  ssh -N -L 8000:$(hostname):$PORT tempest
  then base URL http://localhost:8000/v1, model $NAME, key: cat $KEYFILE
G2Fuzz: set -a; . $EP/$NAME.env; set +a   then scripts/fuzz new/run as usual.
Ready when the log shows vLLM's own "Application startup complete" line.
INFO

# patches/ holds a torchcodec stub: the v0.31.0-cu129 image ships a CUDA-13 torchcodec
# that crashes vLLM at import (OSError: libnvrtc.so.13). Text models don't need it.
apptainer exec --nv -B "$MODELS":/models \
  -B "$HERE/patches":/patches --env PYTHONPATH=/patches "$SIF" \
  vllm serve /models/$MODEL \
    --served-model-name $NAME \
    --host 0.0.0.0 --port $PORT --api-key "$(cat "$KEYFILE")" \
    $SETTINGS
