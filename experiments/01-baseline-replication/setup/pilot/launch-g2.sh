#!/bin/bash
# Phase A G2FUZZ pilot (user chose Qwen3.8-27B-FP8-nothink, 2026-10-23): 15-min --test campaigns (LLM step after
# 10 s idle) of G2-432 (WORKING, g2f-targets/paper) and G2-503 (G2FUZZ-upgradedAFL, g2f-targets/afl503/paper) on the
# AFL pilot's targets. Both versions of a target use the same server: jhead + mp42aac -> A100 server, libpng -> A40.
# As run on 2026-10-23 11:27 (from ~/scratch/bake; moved here). The campaigns were made in each repo's eval/ and moved
# to campaigns/ here; G2F_EVAL (added when they moved) makes a rerun write there. Endpoints: the runner's own servers.
set -u
S=/home/group/csci-591-automated-vulnerability-discovery/students
export G2F_EVAL=$S/WORKING-BETTERG2FUZZ/experiments/01-baseline-replication/setup/pilot/campaigns
A=$HOME/llm-jobs/endpoints/Qwen3.8-27B-FP8-nothink.env      # A100, priority-quantumcore
B=$HOME/llm-jobs/b/endpoints/Qwen3.8-27B-FP8-nothink.env    # A40, priority-quantumcore
for t in jhead:$A mp42aac:$A libpng_libpng_read_fuzzer:$B; do
  tgt=${t%%:*}; ep=${t#*:}; short=${tgt%%_*}
  for arm in 432:WORKING-BETTERG2FUZZ:g2f-targets/paper 503:G2FUZZ-upgradedAFL:g2f-targets/afl503/paper; do
    IFS=: read -r v repo tree <<< "$arm"; c=pilotA-g2$v-$short
    ( cd $S/$repo && set -a && . "$ep" && set +a && export G2F_TARGETS=$S/$tree G2F_TARGET=$tgt &&
      scripts/fuzz new $c >/dev/null && scripts/fuzz run $c 900 --test | tail -1 ) || echo "$c: launch failed"
  done
done
