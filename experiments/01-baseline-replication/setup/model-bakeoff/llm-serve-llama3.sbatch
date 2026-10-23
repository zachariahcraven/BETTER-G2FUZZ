#!/bin/bash
# Serves llama3:70b-instruct-q4_K_M with Ollama on one H100, for G2Fuzz jobs on Tempest (README.md, Tempest setup).
# Start it with `scripts/fuzz llm start [hours]`; runs then find it by themselves.
# Its log, llm-serve-<jobid>.out, goes to ~/llm. Stop: `scripts/fuzz llm stop`.
# Needs ~/llm/ollama.sif and the model in ~/llm/models (one-time setup: README.md, Tempest setup step 8).
#SBATCH -J llm-bake-llama3
#SBATCH -p gpufairshare
#SBATCH --gres=gpu:h100:1
#SBATCH -c 8
#SBATCH --mem 96G
#SBATCH -t 02:00:00
#SBATCH -o llm-bake-llama3-%j.out
LLM_DIR="${LLM_DIR:-$HOME/llm}"
cd "$LLM_DIR" || exit 1
hostname > server-host-llama3
nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
# CONTEXT_LENGTH: Ollama's default is too short for G2Fuzz prompts. KEEP_ALIVE=-1 keeps the model
# on the GPU (loading takes ~3.5 min). Settings and versions used: VERSIONS.txt
apptainer exec --nv --cleanenv \
  --env OLLAMA_MODELS="$LLM_DIR/models",OLLAMA_HOST=0.0.0.0:11434,OLLAMA_CONTEXT_LENGTH=8192,OLLAMA_KEEP_ALIVE=-1,OLLAMA_NUM_PARALLEL=4 \
  ollama.sif ollama serve &
pid=$!
# Load the model now, so the first G2Fuzz call doesn't wait for it
until curl -s -o /dev/null localhost:11434/api/tags; do sleep 5; done
curl -s localhost:11434/api/generate -d '{"model": "llama3:70b-instruct-q4_K_M", "prompt": "", "keep_alive": -1}' >/dev/null \
  && echo "llm-serve: llama3:70b-instruct-q4_K_M loaded on $(hostname) at $(date)"
wait $pid
