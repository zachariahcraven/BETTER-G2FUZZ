#!/bin/bash
# Phase B of 01-baseline-replication (PLAN.md): UNIFUZZ, 10 programs x 4 arms x 5 reps, 6 h of fuzzing each.
# Runs as a small Slurm job that launches the campaigns over time:  sbatch launch/phaseB.sh   (DRY=1 bash ... : print only)
# - Order: rep 1 for all programs, then rep 2, ... All 4 arms of a (program, rep) start together.
# - At most MAX_CAMPAIGNS phase B campaigns at once, and at most MAX_SEEDGEN G2FUZZ seed generations per LLM server
#   (more queued calls push long ones past G2FUZZ's 300 s limit). Both G2FUZZ arms of a group use the same server.
# - Servers: the quantumcore A100 (always), the gpufairshare H100 only if it is up. Never the A40 (~2.5x slower).
# - Each arm runs with its own repo's scripts/fuzz and image; every campaign lands in ../campaigns/ (G2F_EVAL).
# - Resumable: an existing campaign is never launched again. Log: phaseB.log next to this file.
#SBATCH -J g2f-phaseB-driver
#SBATCH -p fairshare
#SBATCH -A group-csci-591-automated-vulnerability-discovery
#SBATCH -c 1
#SBATCH --mem 1G
#SBATCH -t 4-00:00:00
#SBATCH -o phaseB-driver-%j.out
set -u
umask 002
S=/home/group/csci-591-automated-vulnerability-discovery/students
X=$S/WORKING-BETTERG2FUZZ/experiments/01-baseline-replication; C=$X/campaigns; LOG=$X/launch/phaseB.log
PROGRAMS="exiv2 gdk-pixbuf-pixdata imginfo jhead tiffsplit mp3gain ffmpeg flvmeta mp42aac pdftotext"
REPS="1 2 3 4 5"; SECS=21600; MAX_CAMPAIGNS=60; MAX_SEEDGEN=10
SERVERS="$HOME/llm-jobs/endpoints/Qwen3.8-27B-FP8-nothink.env $HOME/llm-jobs/c/endpoints/Qwen3.8-27B-FP8-nothink.env"
# arm | repo | target tree | run options
ARMS="g2432|WORKING-BETTERG2FUZZ|g2f-targets/paper|
afl432|WORKING-BETTERG2FUZZ|g2f-targets/paper|--afl
g2503|G2FUZZ-upgradedAFL|g2f-targets/afl503/paper|
afl503|G2FUZZ-upgradedAFL|g2f-targets/afl503/paper|--afl"

[ "${DRY:-0}" = 1 ] && LOG=$(mktemp)   # a dry run doesn't touch the real log
log() { echo "$(date '+%F %T') $*" | tee -a "$LOG"; }
url_of() { (. "$1" && echo "$G2F_BASE_URL"); }
ready() {   # the server in endpoint file $1 answers with the model
  [ -f "$1" ] || return 1
  (. "$1" && curl -s --max-time 10 -H "Authorization: Bearer $(cat "$G2F_KEY")" "$G2F_BASE_URL/models" | grep -q "\"$G2F_MODEL\"")
}
active() { squeue -u "$USER" -h -o %j | grep -c '^g2f-B-'; }
seedgens() {   # G2FUZZ campaigns still generating seeds (queued/running, no initial_seeds yet) on server URL $1
  local n=0 c jobs; jobs=$(squeue -u "$USER" -h -o %j)
  for c in "$C"/B-*-g2*-r*/; do c=${c%/}
    grep -qx "g2f-$(basename "$c")" <<< "$jobs" || continue
    [ -n "$(ls -A "$c/initial_seeds" 2>/dev/null)" ] && continue
    grep -qF "OPENAI_BASE_URL=$1" "$c/job.sbatch" 2>/dev/null && n=$((n + 1))
  done; echo $n; }
pick_server() {   # the ready server with the fewest seed generations, if it has room for 2 more
  local ep best="" bn=999 n
  for ep in $SERVERS; do ready "$ep" || continue
    n=$(seedgens "$(url_of "$ep")"); [ $((n + 2)) -le $MAX_SEEDGEN ] && [ "$n" -lt "$bn" ] && { best=$ep; bn=$n; }
  done; echo "$best"; }

launch_group() {   # launch_group PROGRAM REP ENDPOINT_FILE
  local p=$1 r=$2 ep=$3 arm repo tree opt c
  while IFS="|" read -r arm repo tree opt; do
    c=B-$p-$arm-r$r
    [ -e "$C/$c" ] && { log "exists, skipped: $c"; continue; }
    if [ "${DRY:-0}" = 1 ]; then log "DRY: $repo: new $c; run $c $SECS $opt (G2F_TARGET=$p G2F_TARGETS=$S/$tree, $(url_of "$ep"))"; continue; fi
    ( cd "$S/$repo" && set -a && . "$ep" && set +a &&
      export G2F_EVAL="$C" G2F_TARGETS="$S/$tree" G2F_TARGET="$p" G2F_MEM=8G &&
      scripts/fuzz new "$c" >/dev/null && scripts/fuzz run "$c" $SECS $opt 2>&1 | grep -E 'submitted|error|fuzz:' ) | tee -a "$LOG"
    { echo "arm: $arm ($repo, AFL++ ${arm:(-3):1}.${arm:(-2)}c)  program: $p  rep: $r"
      echo "launched: $(date '+%F %T') by phaseB.sh (driver job ${SLURM_JOB_ID:-none})"
      [ -z "$opt" ] && echo "llm server: $(grep -E '^(G2F_BASE_URL|G2F_MODEL|LLM_JOB)=' "$ep" | paste -sd ' ')"
    } > "$C/$c/launch.txt" 2>/dev/null
  done <<< "$ARMS"
}

mkdir -p "$C"; log "phaseB.sh start (driver ${SLURM_JOB_ID:-interactive}, DRY=${DRY:-0})"
for r in $REPS; do for p in $PROGRAMS; do
  [ -e "$C/B-$p-afl503-r$r" ] && continue   # whole group already launched
  while :; do
    ep=""; [ "$(active)" -le $((MAX_CAMPAIGNS - 4)) ] && ep=$(pick_server)
    [ -n "$ep" ] && break
    [ "${DRY:-0}" = 1 ] && { log "DRY: would wait (active $(active), no server with room)"; ep=${SERVERS%% *}; break; }
    sleep 120
  done
  log "group $p r$r -> $(url_of "$ep")"; launch_group "$p" "$r" "$ep"
  [ "${DRY:-0}" = 1 ] || sleep 20   # let the jobs appear in squeue before counting again
done; done
log "phaseB.sh: all 50 groups launched"
