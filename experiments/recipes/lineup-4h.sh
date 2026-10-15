#!/bin/bash
# 4 h runs on XML and Doom, 2026-10-14 22:25 -> results/campaigns/lineup-4h/{xml4h,wad4h}-<model>-r1..5
# 3 models + baseline. Doom used AFL++'s automatic timeout here, so its crash counts are confounded;
# use replayed coverage (results/cov) for Doom, not AFL++'s edge counter (it inflated 4 of 20 runs).
cd "$(dirname "$0")/../.." || exit 1
GROUP=lineup-4h TAG=4h TARGETS='xml_fuzzer doom_wad' ONLY='codernext qwen36nt qwen4b baseline' \
  REPS=5 SECS=14400 HOURS=6 sbatch --export=ALL experiments/runners/run-lineup.sbatch
