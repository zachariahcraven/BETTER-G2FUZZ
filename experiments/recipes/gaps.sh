#!/bin/bash
# Gap-closing runs (plan Workstream C), PRE-REGISTERED 2026-10-15 before any of these runs started.
# Exclusion rule for every step: only infrastructure failures (job/node failure, campaign shorter than SECS,
# server down) are rerun, under the same rule for every arm; every launched campaign is reported.
# Analysis: experiments/analysis/stats (exact two-sided Mann-Whitney U, Vargha-Delaney A12, bootstrap CI of the
# median difference, Holm within experiment and metric); primary metric replayed coverage (results/cov),
# crash sites per run for Doom.
#
# topup  (C2) jhead, TIFF, PNG to 5 reps per arm (they had 3; png qwen36nt/qwen4b had 2). Question: none new;
#        gives the existing comparisons enough reps to reach p < 0.05 at all (n=3 vs 3 cannot go below 0.1).
#        Same arms, SECS=3600, image, AFL options as the originals; deviation to report: run on a later date.
#        The CPU baseline arms run now; the LLM arms run on the same H100 server setups as the originals
#        once H100s are free (user decision 2026-10-15 ~18:25: no stand-in GPUs for LLM arms).
# wad4ht (C3) Doom 4 h with a fixed afl-fuzz -t 100 (the earlier 4 h crash counts used AFL++'s automatic
#        timeout and are confounded). Arms: baseline, codernext, qwen36nt, qwen4b; 5 x 14400 s.
#        Hypothesis: models > baseline in crash sites per run (primary) and replayed coverage (secondary).
# xml12h (C4) XML 12 h. Question: does the LLM gain persist or does AFL++ catch up (+122% at 1 h, +42% at 4 h)?
#        Arms: baseline, codernext; 5 x 43200 s. Primary: replayed coverage at 12 h; secondary: coverage over time.
cd "$(dirname "$0")/../.." || exit 1
R=experiments/runners/run-lineup.sbatch
case "${1:-}" in
  topup-base)   # CPU, 2026-10-15
    GROUP=lineup-jhead TARGETS=jhead REPS=5 SECS=3600 HOURS=5 LANES=base ONLY=baseline sbatch --export=ALL $R
    GROUP=lineup-1h TARGETS='tiff_read_rgba_fuzzer libpng_read_fuzzer' REPS=5 SECS=3600 HOURS=5 LANES=base ONLY=baseline sbatch --export=ALL $R ;;
  topup-llm)    # needs H100s: the five lineup models (codernext, qwen38 = Qwen3.8-nothink, gemma31b, qwen36nt, qwen4b)
    GROUP=lineup-jhead TARGETS=jhead REPS=5 SECS=3600 HOURS=8 LANES='h100 h100b h100c' ONLY='codernext qwen38 gemma31b qwen36nt qwen4b' sbatch --export=ALL $R
    GROUP=lineup-1h TARGETS='tiff_read_rgba_fuzzer libpng_read_fuzzer' REPS=5 SECS=3600 HOURS=8 LANES='h100 h100b h100c' ONLY='codernext qwen38 gemma31b qwen36nt qwen4b' sbatch --export=ALL $R ;;
  wad4ht-base)  # CPU, 2026-10-15
    GROUP=lineup-4h TAG=4ht G2F_TIMEOUT_MS=100 TARGETS=doom_wad REPS=5 SECS=14400 HOURS=6 LANES=base ONLY=baseline sbatch --export=ALL $R ;;
  wad4ht-llm)   # needs H100s
    GROUP=lineup-4h TAG=4ht G2F_TIMEOUT_MS=100 TARGETS=doom_wad REPS=5 SECS=14400 HOURS=6 LANES='h100 h100b h100c' ONLY='codernext qwen36nt qwen4b' sbatch --export=ALL $R ;;
  xml12h-base)  # CPU, 2026-10-15
    GROUP=lineup-12h TAG=12h TARGETS=xml_fuzzer REPS=5 SECS=43200 HOURS=14 LANES=base ONLY=baseline sbatch --export=ALL $R ;;
  xml12h-llm)   # needs H100s
    GROUP=lineup-12h TAG=12h TARGETS=xml_fuzzer REPS=5 SECS=43200 HOURS=14 LANES=h100 ONLY=codernext sbatch --export=ALL $R ;;
  *) echo "usage: $0 topup-base|topup-llm|wad4ht-base|wad4ht-llm|xml12h-base|xml12h-llm"; exit 1 ;;
esac
