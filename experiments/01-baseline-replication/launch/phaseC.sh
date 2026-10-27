#!/bin/bash
# Phase C of 01-baseline-replication (PLAN.md, scoped 2026-10-25): the paper's 24 h x 5 reps, on the programs where
# 6 h (phase B) was a tie or not significant: exiv2, gdk-pixbuf-pixdata, imginfo, jhead, mp3gain. AFL++ 4.32c arms
# only (g2432 vs afl432: the paper's comparison); the 5.03c arms answered their question in phase B; flvmeta is
# saturated; ffmpeg, mp42aac, pdftotext, tiffsplit were already significant at 6 h.
# 5 programs x 2 arms x 5 reps = 50 campaigns of 24 h (1,200 campaign-hours, like phase B).
# Runs as a small Slurm job that launches the campaigns over time:  sbatch launch/phaseC.sh   (DRY=1 bash ... : print only)
# - Both arms of a (program, rep) start together; at most MAX_CAMPAIGNS phase C campaigns at once and at most
#   MAX_SEEDGEN G2FUZZ seed generations per LLM server. Servers: the quantumcore A100 (always), the gpufairshare H100
#   only if it is up (same as phase B). Campaign CPUs: partition fairshare, class group account (scripts/fuzz default).
# - G2F_SEEDGEN_MIN=210: the job limit allows 3.5 h of seed generation (phase B: 7 of 98 took over 2 h, DRIFT.md 5.9).
# - Resumable: an existing campaign is never launched again. Names C-<program>-<arm>-r<rep>; log phaseC.log.
#SBATCH -J g2f-phaseC-driver
#SBATCH -p fairshare
#SBATCH -A group-csci-591-automated-vulnerability-discovery
#SBATCH -c 1
#SBATCH --mem 1G
#SBATCH -t 4-00:00:00
#SBATCH -o phaseC-driver-%j.out
set -u
umask 002
S=/home/group/csci-591-automated-vulnerability-discovery/students
X=$S/WORKING-BETTERG2FUZZ/experiments/01-baseline-replication; C=$X/campaigns; LOG=$X/launch/phaseC.log
PROGRAMS="exiv2 gdk-pixbuf-pixdata imginfo jhead mp3gain"
REPS="1 2 3 4 5"; SECS=86400; MAX_CAMPAIGNS=60; MAX_SEEDGEN=10
SERVERS="$HOME/llm-jobs/endpoints/Qwen3.8-27B-FP8-nothink.env $HOME/llm-jobs/c/endpoints/Qwen3.8-27B-FP8-nothink.env"
# arm | repo | target tree | run options
ARMS="g2432|WORKING-BETTERG2FUZZ|g2f-targets/paper|
afl432|WORKING-BETTERG2FUZZ|g2f-targets/paper|--afl"

[ "${DRY:-0}" = 1 ] && LOG=$(mktemp)   # a dry run doesn't touch the real log
log() { echo "$(date '+%F %T') $*" | tee -a "$LOG"; }
url_of() { (. "$1" && echo "$G2F_BASE_URL"); }
ready() {   # the server in endpoint file $1 answers with the model
  [ -f "$1" ] || return 1
  (. "$1" && curl -s --max-time 10 -H "Authorization: Bearer $(cat "$G2F_KEY")" "$G2F_BASE_URL/models" | grep -q "\"$G2F_MODEL\"")
}
active() { squeue -u "$USER" -h -o %j | grep -c '^g2f-C-'; }
seedgens() {   # G2FUZZ campaigns still generating seeds (queued/running, no initial_seeds yet) on server URL $1
  local n=0 c jobs; jobs=$(squeue -u "$USER" -h -o %j)
  for c in "$C"/C-*-g2*-r*/; do c=${c%/}
    grep -qx "g2f-$(basename "$c")" <<< "$jobs" || continue
    [ -n "$(ls -A "$c/initial_seeds" 2>/dev/null)" ] && continue
    grep -qF "OPENAI_BASE_URL=$1" "$c/job.sbatch" 2>/dev/null && n=$((n + 1))
  done; echo $n; }
pick_server() {   # the ready server with the fewest seed generations, if it has room for 1 more
  local ep best="" bn=999 n
  for ep in $SERVERS; do ready "$ep" || continue
    n=$(seedgens "$(url_of "$ep")"); [ $((n + 1)) -le $MAX_SEEDGEN ] && [ "$n" -lt "$bn" ] && { best=$ep; bn=$n; }
  done; echo "$best"; }

launch_group() {   # launch_group PROGRAM REP ENDPOINT_FILE
  local p=$1 r=$2 ep=$3 arm repo tree opt c
  while IFS="|" read -r arm repo tree opt; do
    c=C-$p-$arm-r$r
    [ -e "$C/$c" ] && { log "exists, skipped: $c"; continue; }
    if [ "${DRY:-0}" = 1 ]; then log "DRY: $repo: new $c; run $c $SECS $opt (G2F_TARGET=$p G2F_TARGETS=$S/$tree, $(url_of "$ep"))"; continue; fi
    ( cd "$S/$repo" && set -a && . "$ep" && set +a &&
      export G2F_EVAL="$C" G2F_TARGETS="$S/$tree" G2F_TARGET="$p" G2F_MEM=8G G2F_SEEDGEN_MIN=210 &&
      scripts/fuzz new "$c" >/dev/null && scripts/fuzz run "$c" $SECS $opt 2>&1 | grep -E 'submitted|error|fuzz:' ) | tee -a "$LOG"
    { echo "arm: $arm ($repo, AFL++ ${arm:(-3):1}.${arm:(-2)}c)  program: $p  rep: $r  phase: C (24 h)"
      echo "launched: $(date '+%F %T') by phaseC.sh (driver job ${SLURM_JOB_ID:-none})"
      [ -z "$opt" ] && echo "llm server: $(grep -E '^(G2F_BASE_URL|G2F_MODEL|LLM_JOB)=' "$ep" | paste -sd ' ')"
    } > "$C/$c/launch.txt" 2>/dev/null
  done <<< "$ARMS"
}

mkdir -p "$C"; log "phaseC.sh start (driver ${SLURM_JOB_ID:-interactive}, DRY=${DRY:-0})"
for r in $REPS; do for p in $PROGRAMS; do
  [ -e "$C/C-$p-afl432-r$r" ] && continue   # whole group already launched
  while :; do
    ep=""; [ "$(active)" -le $((MAX_CAMPAIGNS - 2)) ] && ep=$(pick_server)
    [ -n "$ep" ] && break
    [ "${DRY:-0}" = 1 ] && { log "DRY: would wait (active $(active), no server with room)"; ep=${SERVERS%% *}; break; }
    sleep 120
  done
  log "group $p r$r -> $(url_of "$ep")"; launch_group "$p" "$r" "$ep"
  [ "${DRY:-0}" = 1 ] || sleep 20   # let the jobs appear in squeue before counting again
done; done
log "phaseC.sh: all 25 groups launched"
