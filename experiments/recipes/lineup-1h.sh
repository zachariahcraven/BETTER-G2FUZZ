#!/bin/bash
# 1 h model lineup on TIFF, PNG, XML and Doom -> results/campaigns/lineup-1h/
#   tiff-, png-<model>-r1..3; xml-<model>-r1..5; wad-<model>-r1..5; 5 models + baseline
# One runner at a time (a runner stops the servers it started). In the order they ran:
cd "$(dirname "$0")/../.." || exit 1
step=${1:-}
case "$step" in
  tiff-png-xml)   # 2026-10-14: TIFF, PNG and XML, 3 reps (jhead campaigns already existed)
    GROUP=lineup-1h TARGETS='tiff_read_rgba_fuzzer libpng_read_fuzzer xml_fuzzer' REPS=3 SECS=3600 HOURS=5 \
      sbatch --export=ALL experiments/runners/run-lineup.sbatch ;;
  doom)           # 2026-10-15 03:21: Doom with a fixed 100 ms timeout (the first Doom lineup used
                  # AFL++'s automatic one, 20 vs 40 ms, which confounded crashes: archive/auto20-wad-*)
    GROUP=lineup-1h G2F_TIMEOUT_MS=100 TARGETS=doom_wad REPS=5 SECS=3600 HOURS=5 \
      sbatch --export=ALL experiments/runners/run-lineup.sbatch ;;
  xml-top-up)     # 2026-10-15 07:16: XML reps 4 and 5 (the runner skips campaigns that exist)
    GROUP=lineup-1h TARGETS=xml_fuzzer REPS=5 SECS=3600 HOURS=5 \
      sbatch --export=ALL experiments/runners/run-lineup.sbatch ;;
  *) echo "usage: $0 tiff-png-xml | doom | xml-top-up"; exit 1 ;;
esac
