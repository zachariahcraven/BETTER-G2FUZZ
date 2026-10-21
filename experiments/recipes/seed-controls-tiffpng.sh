#!/bin/bash
# Seed controls for TIFF and PNG (plan C1), PRE-REGISTERED 2026-10-15 before any of these runs started
#   -> results/campaigns/seed-controls/{tiff,png}-ctl-{llmseeds,junk}-r1..5
# Question: why do TIFF and PNG tie the baseline? Is there nothing in the LLM-written seeds beyond the stock seeds?
# Hypothesis: ctl-llmseeds ~ baseline on TIFF and PNG (unlike XML, where llmseeds alone gave +115%).
# Arms: baseline (lineup-1h tiff/png-baseline, topped up to 5 reps by gaps.sh topup-base), ctl-llmseeds, ctl-junk.
# Only difference between arms: the starting seed set (stock / stock + codernext-r1's generated seeds / stock +
#   random bytes of the same sizes keeping each generated file's first 4 bytes; experiments/inputs/seed-controls,
#   rebuilt by make-controls.py tiff png). No LLM at all (G2F_NO_LLM=1), 5 x 3600 s, same image, AFL++ options and
#   timeout handling as the baseline arms (AFL++'s automatic -t, as in the TIFF/PNG lineup). CPU only.
# Primary metric: replayed coverage; test: experiments/analysis/stats (comparisons 1-3). Secondary: seed coverage
#   of stock vs llmseeds (lib/seed_cov.py), descriptive.
# Exclusion: infrastructure failures only (job/node failure, campaign shorter than 3600 s), same rule for every arm.
cd "$(dirname "$0")/../.." || exit 1
for tgt in tiff png; do
  for ctl in llmseeds junk; do
    for r in 1 2 3 4 5; do
      n=$tgt-ctl-$ctl-r$r
      scripts/fuzz path "$n" >/dev/null 2>&1 && { echo "$n exists, skipped"; continue; }
      ( export G2F_GROUP=seed-controls G2F_NO_LLM=1 G2F_SEEDS=experiments/inputs/seed-controls/$tgt-$ctl
        if [ $tgt = tiff ]; then export G2F_TARGET=tiff_read_rgba_fuzzer; else export G2F_TARGET=libpng_read_fuzzer; fi
        scripts/fuzz new $n >/dev/null && scripts/fuzz run $n 3600 )
    done
  done
done
