#!/bin/bash
# jhead model screen, 2026-10-10..13 -> results/campaigns/lineup-jhead/lineup-<model>-r1..3
# 15 models x 3 reps x 1 h, plus the no-LLM baseline; picked the 5 models used everywhere else.
# Run over several runner jobs while the model list in run-lineup.sbatch grew; the screened models
# that were later dropped (oss20b, oss120b, qwen36, coder30b, abl9b, devstral24b, gemma26b, qwen122b,
# dsv4flash) need their scripts/vllm/serve-*.sbatch back to rerun.
cd "$(dirname "$0")/../.." || exit 1
GROUP=lineup-jhead TARGETS=jhead REPS=3 SECS=3600 HOURS=5 \
  sbatch --export=ALL experiments/runners/run-lineup.sbatch
