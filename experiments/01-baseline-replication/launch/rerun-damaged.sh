#!/bin/bash
# Phase B fix (c), user-approved 2026-10-24: rerun the 2 damaged campaigns, fuzzing only (6 h), with their OWN
# generated seeds and generators. The damaged folders are renamed (mv), never deleted. Same settings as phaseB.sh.
set -u
umask 002
S=/home/group/csci-591-automated-vulnerability-discovery/students
X=$S/WORKING-BETTERG2FUZZ/experiments/01-baseline-replication; C=$X/campaigns; LOG=$X/launch/phaseB.log
EP=$HOME/llm-jobs/endpoints/Qwen3.8-27B-FP8-nothink.env
# name | repo | target tree | program | reason
while IFS="|" read -r c repo tree p why; do
  old=$C/$c.damaged-$why
  [ -e "$old" ] && { echo "already renamed: $old"; continue; }
  mv "$C/$c" "$old" || continue
  ( cd "$S/$repo" && set -a && . "$EP" && set +a &&
    export G2F_EVAL="$C" G2F_TARGETS="$S/$tree" G2F_TARGET="$p" G2F_MEM=8G &&
    scripts/fuzz reuse "$(basename "$old")" "$c" && scripts/fuzz run "$c" 21600 2>&1 | grep -E 'submitted|reusing|error|fuzz:' )
  arm=$(sed -E 's/.*-(g2[0-9]+|afl[0-9]+)-r[0-9]+$/\1/' <<< "$c")
  { echo "arm: $arm  rerun of a damaged campaign (fix c, user-approved 2026-10-24)"
    echo "program: $p  repo: $repo"
    echo "launched: $(date '+%F %T') by rerun-damaged.sh; fuzzing only, seeds+generators reused from $(basename "$old")"
    echo "note: the other 3 arms of this (program, rep) ran earlier; this arm started later"
    echo "llm server: $(grep -E '^(G2F_BASE_URL|G2F_MODEL|LLM_JOB)=' "$EP" | paste -sd ' ')"
  } > "$C/$c/launch.txt"
  echo "$(date '+%F %T') rerun $c (fix c) from $(basename "$old")" >> "$LOG"
done <<'EOF'
B-ffmpeg-g2432-r3|WORKING-BETTERG2FUZZ|g2f-targets/paper|ffmpeg|timeout-5.5h
B-mp42aac-g2503-r3|G2FUZZ-upgradedAFL|g2f-targets/afl503/paper|mp42aac|dryrun-seed-timeout
EOF
