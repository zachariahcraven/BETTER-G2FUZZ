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
  round5)  # CEILING EXPERIMENT (plan B4), PRE-REGISTERED 2026-10-15 before it started.
    # Question: can ANY generator scheduler beat random at this LLM-step rate? oracle = always the pool's best
    #   generators (ranking from the POOL campaign's own final queue via experiments/analysis/lib/oracle_ranking.py,
    #   never from the evaluated runs), vs bandit vs random. If oracle ties random, scheduling cannot matter here.
    # Arms differ only in G2F_SCHEDULER (oracle | bandit | random); same pool, server, plateau 5 s, backoff 0,
    #   14400 s, 5 reps, all arms of a pool started together. Server: Qwen3-Coder-Next-FP8-agent (2xH100, 128k
    #   context, user decision 2026-10-15 18:40), reused and never stopped by the runner.
    # Doom pool with a fixed afl-fuzz -t 100 for all its arms (earlier rounds used AFL++'s automatic timeout);
    #   XML pool unchanged (automatic -t, as its pool campaign).
    # Primary metric: replayed coverage at 4 h; test: experiments/analysis/stats rule 4 (oracle vs random,
    #   bandit vs random, oracle vs bandit). Secondary: decisions per run and picks on the top generators (B2 table).
    # Exclusion: infrastructure failures only, same rule for every arm.
    COMMON="SCHEDS='oracle bandit random' REPS=5 SECS=14400 PLATEAU=5 BACKOFF=0 LABEL=o4 HOURS=13 MODEL=Qwen3-Coder-Next-FP8-agent G2F_VLLM_DIR=$HOME/llm-jobs"
    eval "POOLS='xml:xml-codernext-r1' $COMMON sbatch --export=ALL $B"
    eval "POOLS='wad:auto20-wad-codernext-r1' G2F_TIMEOUT_MS=100 $COMMON sbatch --export=ALL $B" ;;
  *) echo "usage: $0 round1 | round2 | round3 | round4 | round5"; exit 1 ;;
esac
