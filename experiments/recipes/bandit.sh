#!/bin/bash
# Bandit (Thompson sampling over generators and mutation types) vs G2Fuzz's random choice
#   -> results/campaigns/bandit/bandit-<target>-<sched><label>-r<N>
# Every arm reuses one campaign's seeds and generators (the pool), so arms differ only in the scheduler.
# Pools: pilot-tiff-codernext-r1 and auto20-wad-codernext-r1 are in results/campaigns/archive/.
cd "$(dirname "$0")/../.." || exit 1
B=experiments/runners/run-bandit.sbatch
case "${1:-}" in
  round1)  # 2026-10-14 15:21: TIFF and jhead, plateau 20 s, 2 reps
    POOLS='tiff:pilot-tiff-codernext-r1 jhead:lineup-codernext-r1' REPS=2 SECS=3600 sbatch --export=ALL $B ;;
  round2)  # 2026-10-14 18:57: XML and Doom, plateau 20 s, 5 reps
    POOLS='xml:xml-codernext-r1 wad:auto20-wad-codernext-r1' REPS=5 SECS=3600 HOURS=4 sbatch --export=ALL $B ;;
  round3)  # 2026-10-14 20:46: plateau 5 s (more LLM steps), 5 reps
    POOLS='wad:auto20-wad-codernext-r1 xml:xml-codernext-r1' REPS=5 SECS=3600 PLATEAU=5 BACKOFF=0 LABEL=p5 HOURS=4 \
      sbatch --export=ALL $B ;;
  round4)  # 2026-10-14 22:20: Doom, random only, G2Fuzz's default 300 s plateau (dose-response control)
    POOLS='wad:auto20-wad-codernext-r1' SCHEDS=random REPS=5 SECS=3600 PLATEAU=300 BACKOFF=60 LABEL=p300 HOURS=3 \
      sbatch --export=ALL $B ;;
  *) echo "usage: $0 round1 | round2 | round3 | round4"; exit 1 ;;
esac
