#!/bin/bash
# Phase A model bake-off (approved 2026-10-23): seed generation + 300 s fuzzing, WORKING (4.32c), paper targets,
# 3 models x 3 targets x 2 reps. Waits for each server to answer, then launches its campaigns.
# As run on 2026-10-23 (log: launch.log). The campaigns were made in eval/ and moved to campaigns/ here; G2F_EVAL
# (added when they moved) makes a rerun write there. A rerun also needs the three servers: see README.md.
set -u
S=/home/group/csci-591-automated-vulnerability-discovery/students; cd $S/WORKING-BETTERG2FUZZ
export G2F_TARGETS=$S/g2f-targets/paper
export G2F_EVAL=$S/WORKING-BETTERG2FUZZ/experiments/01-baseline-replication/setup/model-bakeoff/campaigns
ready() { curl -s --max-time 10 -H "Authorization: Bearer $(cat $2)" "$1/models" | grep -q "\"$3\""; }
# model tag | base url | key file | served model name
LL=$(cat ~/llm/server-host-llama3 2>/dev/null); GO=$(cat ~/llm/server-host 2>/dev/null)
. ~/llm-jobs/endpoints/Qwen3.8-27B-FP8-nothink.env 2>/dev/null; QURL=$G2F_BASE_URL; QKEY=$G2F_KEY; QMOD=$G2F_MODEL; unset G2F_BASE_URL G2F_KEY G2F_MODEL
while IFS="|" read -r tag url key model; do
  for i in $(seq 1 60); do ready "$url" "$key" "$model" && break; sleep 30; done
  ready "$url" "$key" "$model" || { echo "$tag: server not ready, skipped"; continue; }
  for t in jhead mp42aac pdftotext; do for r in 1 2; do
    c=bake-$tag-$t-r$r
    G2F_TARGET=$t G2F_BASE_URL=$url G2F_KEY=$key G2F_MODEL=$model scripts/fuzz new $c >/dev/null &&
    G2F_TARGET=$t G2F_BASE_URL=$url G2F_KEY=$key G2F_MODEL=$model scripts/fuzz run $c 300 | tail -1
  done; done
done <<LIST
gptoss|http://$GO:11434/v1|$HOME/llm/dummy.key|gpt-oss:120b
llama3|http://$LL:11434/v1|$HOME/llm/dummy.key|llama3:70b-instruct-q4_K_M
qwen38nt|$QURL|$QKEY|$QMOD
LIST
