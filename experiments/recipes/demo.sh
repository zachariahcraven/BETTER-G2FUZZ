#!/bin/bash
# Doom demo target (plan E), PRE-REGISTERED 2026-10-15 before any run of it started
#   -> results/campaigns/demo/demo-<arm>-r1..5
# Question: the LLM did not understand the WAD format; does knowing how to PLAY Doom help when the input is a demo
#   (the players' recorded inputs, played on the fixed base game; harness targets/doom/g2f_demo.c)?
# Arms: baseline (G2F_NO_LLM=1: plain AFL++ on the 4 Freedoom demos cut to 105 tics); codernext (G2Fuzz with the
#   demo format description experiments/inputs/format-desc/doom_demo.txt); ctl-llmseeds (no LLM, codernext-r1's
#   initial seeds as fixed seeds); ctl-junk (no LLM, the same files with each generated demo's 13-byte header kept and
#   its tic commands randomized, same length; make-controls.py demo); later qwen38/gemma31b/qwen4b on H100 servers.
# Fixed for every arm (chosen in the pilot with stock demos only, before any LLM data): binary doom_demo from
#   ~/g2f-targets-demo (G2F_TARGETS; image targets byte-identical + doom_demo), 105 tics per input (user decision
#   2026-10-15 ~16:30), G2F_TIMEOUT_MS=200, 5 x 3600 s, default plateau/backoff, random scheduler.
# Primary metric: replayed coverage; secondary: crash sites per run, play metrics of the generated seeds
#   (G2F_DOOM_DEBUG). Test: experiments/analysis/stats comparisons 1-3. Hypothesis: codernext > ctl-junk and
#   ctl-llmseeds > ctl-junk (play content matters), unlike the WAD target.
# Exclusion: infrastructure failures only, same rule for every arm.
cd "$(dirname "$0")/../.." || exit 1
export G2F_GROUP=demo G2F_TARGET=doom_demo G2F_TARGETS=$HOME/g2f-targets-demo G2F_TIMEOUT_MS=200
one() {   # name, then env assignments
  local n=$1; shift
  scripts/fuzz path "$n" >/dev/null 2>&1 && { echo "$n exists, skipped"; return; }
  ( export "$@"; scripts/fuzz new "$n" >/dev/null && scripts/fuzz run "$n" 3600 )
}
case "${1:-}" in
  llm)       # baseline + codernext, started together
    for r in 1 2 3 4 5; do one demo-baseline-r$r G2F_NO_LLM=1; done
    for r in 1 2 3 4 5; do ( set -a; . ~/llm-jobs/endpoints/Qwen3-Coder-Next-FP8-agent.env; set +a
      one demo-codernext-r$r G2F_FORMAT_DESC_FILE=experiments/inputs/format-desc/doom_demo.txt ); done ;;
  controls)  # after demo-codernext-r1 finished: python3 experiments/inputs/seed-controls/make-controls.py demo
    for c in llmseeds junk; do for r in 1 2 3 4 5; do
      one demo-ctl-$c-r$r G2F_NO_LLM=1 G2F_SEEDS=experiments/inputs/seed-controls/demo-$c; done; done ;;
  model)     # the other LLM arms named in the header, each on its exact lineup server (H100), when one is free:
             # demo.sh model <alias> <endpoint .env>   (aliases qwen38 = Qwen3.8-27B-FP8-nothink, gemma31b, qwen4b)
    a=${2:?alias}; ep=${3:?endpoint file}
    for r in 1 2 3 4 5; do ( set -a; . "$ep"; set +a
      one demo-$a-r$r G2F_FORMAT_DESC_FILE=experiments/inputs/format-desc/doom_demo.txt ); done ;;
  *) echo "usage: $0 llm | controls | model <alias> <endpoint.env>"; exit 1 ;;
esac
