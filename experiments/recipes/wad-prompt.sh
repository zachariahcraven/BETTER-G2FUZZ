#!/bin/bash
# Doom WAD prompt test (plan D), PRE-REGISTERED 2026-10-15 before any run of it started
#   -> results/campaigns/wad-prompt/wadp-{bare,name,spec}-<model>-r1..5
# Question: is the missing WAD format understanding (0 of ~1400 generated WADs valid; random bytes did as well as
#   LLM seeds) a prompting problem? G2Fuzz tells the LLM only "'wad' files".
# Arms (only factor that differs: the format text in the LLM prompts, experiments/inputs/format-desc/, reviewed):
#   bare = the token "wad" (G2Fuzz as is); name = doom_wad-name.txt; spec = doom_wad-spec.txt (layout, no file content).
# Fixed for every arm: target doom_wad (image), G2F_TIMEOUT_MS=100, 5 x 3600 s, default plateau/backoff (300/60 s),
#   random scheduler, the same model server per model, all arms of a model started together.
# Models: codernext = Qwen3-Coder-Next-FP8-agent (2xH100, 128k context; user decision 2026-10-15 18:40: this server
#   for new experiments) now; qwen4b on an H100 server when one is free (step qwen4b).
# Primary metrics: generated-seed WAD validity (experiments/analysis/lib/wad_map.py: a map draws) and replayed
#   coverage; secondary: crash sites per run. Test: experiments/analysis/stats comparison 5 (name and spec vs bare,
#   same model), Holm within experiment and metric.
# Follow-up rule (fixed now): if name or spec beats bare on coverage (Holm p < 0.05), run seed-only controls
#   (llmseeds/junk) from that arm's r1 as for XML/Doom.
# Exclusion: infrastructure failures only (job/node failure, server down, campaign shorter than 3600 s), same rule
#   for every arm.
# DEVIATION 2026-10-15 23:30: both name and spec met the follow-up rule, which did not say which arm to use when
#   both do; chosen after the results: the arm with the higher median coverage (spec 2497 vs name 2492).
cd "$(dirname "$0")/../.." || exit 1
D=experiments/inputs/format-desc
run_arms() {   # model endpoint file
  local m=$1 ep=$2
  for arm in bare name spec; do for r in 1 2 3 4 5; do
    n=wadp-$arm-$m-r$r
    scripts/fuzz path "$n" >/dev/null 2>&1 && { echo "$n exists, skipped"; continue; }
    ( set -a; . "$ep"; set +a
      export G2F_GROUP=wad-prompt G2F_TARGET=doom_wad G2F_TIMEOUT_MS=100
      unset G2F_FORMAT_DESC_FILE
      [ $arm = name ] && export G2F_FORMAT_DESC_FILE=$D/doom_wad-name.txt
      [ $arm = spec ] && export G2F_FORMAT_DESC_FILE=$D/doom_wad-spec.txt
      scripts/fuzz new "$n" >/dev/null && scripts/fuzz run "$n" 3600 )
  done; done
}
case "${1:-}" in
  codernext) run_arms codernext ~/llm-jobs/endpoints/Qwen3-Coder-Next-FP8-agent.env ;;
  qwen4b)    run_arms qwen4b "${QWEN4B_ENDPOINT:?set QWEN4B_ENDPOINT to the Qwen3.5-4B server endpoint file}" ;;
  controls)  # FOLLOW-UP fixed by the rule above (added 2026-10-15 after the codernext arms: spec 2497 and name 2492 vs
             # bare 2332, Holm p 0.016 / 0.032): seed-only controls from the best arm by median coverage (spec) r1,
             # built by: python3 experiments/inputs/seed-controls/make-controls.py wadp. No LLM, doom_wad, -t 100, 5 x 3600 s.
             # Primary comparison: ctl-llmseeds vs ctl-junk (stats rule 2): does the LLM content matter on WAD after all?
    for c in llmseeds junk; do for r in 1 2 3 4 5; do
      n=wadp-ctl-$c-r$r
      scripts/fuzz path "$n" >/dev/null 2>&1 && { echo "$n exists, skipped"; continue; }
      ( export G2F_GROUP=wad-prompt G2F_TARGET=doom_wad G2F_TIMEOUT_MS=100 G2F_NO_LLM=1 \
          G2F_SEEDS=experiments/inputs/seed-controls/wadp-$c
        unset G2F_FORMAT_DESC_FILE
        scripts/fuzz new "$n" >/dev/null && scripts/fuzz run "$n" 3600 )
    done; done ;;
  *) echo "usage: $0 codernext | qwen4b | controls"; exit 1 ;;
esac
