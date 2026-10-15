#!/bin/bash
# Seed controls, 2026-10-15 05:20 -> results/campaigns/seed-controls/{wad,xml}-ctl-{llmseeds,junk}-r1..5
# Is the LLM gain the generated seeds' content, or just extra small files? No LLM at all:
#   llmseeds: the stock seeds + Coder-Next's generated seeds (from {wad,xml}-codernext-r1), as fixed seeds
#   junk:     the stock seeds + random bytes of the same sizes, keeping each generated file's first 4 bytes
# Seed sets: experiments/inputs/seed-controls/ (make-controls.py rebuilds them). CPU only.
cd "$(dirname "$0")/../.." || exit 1
for tgt in wad xml; do
  for ctl in llmseeds junk; do
    for r in 1 2 3 4 5; do
      n=$tgt-ctl-$ctl-r$r
      ( export G2F_GROUP=seed-controls G2F_NO_LLM=1 G2F_SEEDS=experiments/inputs/seed-controls/$tgt-$ctl
        if [ $tgt = wad ]; then export G2F_TARGET=doom_wad G2F_TIMEOUT_MS=100; else export G2F_TARGET=xml_fuzzer; fi
        scripts/fuzz new $n >/dev/null && scripts/fuzz run $n 3600 )
    done
  done
done
