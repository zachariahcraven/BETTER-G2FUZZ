#!/bin/bash
# Scheduler experiment: G2Fuzz campaigns that differ only in how LLM steps pick the generator and
# the mutation type (G2F_SCHEDULER=random, the original G2Fuzz, or bandit). All campaigns of a target
# start from the same generator pool (scripts/fuzz reuse <pool>) and use the same model server and
# LLM-step trigger (G2F_PLATEAU_SEC, G2F_BACKOFF_SEC).
# Campaigns: results/campaigns/<GROUP>/bandit-<tag>-<sched>-r<N> (GROUP default bandit). Log: results/logs/bandit.log.
# Pools are campaigns whose seeds and generators every arm reuses (scripts/fuzz reuse)
# Options: POOLS="<tag>:<pool campaign> ..." (default tiff:pilot-tiff-codernext-r1 jhead:lineup-codernext-r1),
#   SCHEDS (default "random bandit"), REPS (2), SECS (3600), PLATEAU (20), BACKOFF (0),
#   MODEL (server, default Qwen3-Coder-Next-FP8-bandit), HOURS (server hours, default 4),
#   LABEL (appended to the scheduler in campaign names, e.g. LABEL=p5 -> bandit-wad-banditp5-r1)
# Submit from the project root:  sbatch experiments/runners/run-bandit.sbatch
#SBATCH --job-name=g2f-bandit-runner
#SBATCH --partition=fairshare
#SBATCH --account=group-csci-591-automated-vulnerability-discovery
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=2G
#SBATCH --time=2-00:00:00
#SBATCH --output=results/logs/bandit-runner-%j.out
set -u
X=/home/group/csci-591-automated-vulnerability-discovery/students/BETTER-G2FUZZ-exp
cd "$X" || exit 1
export G2F_VLLM_DIR=$HOME/exp-llm G2F_VLLM_EXCLUDE=gpu049
POOLS=${POOLS:-tiff:pilot-tiff-codernext-r1 jhead:lineup-codernext-r1}
SCHEDS=${SCHEDS:-random bandit}; REPS=${REPS:-2}; SECS=${SECS:-3600}
PLATEAU=${PLATEAU:-20}; BACKOFF=${BACKOFF:-0}; LABEL=${LABEL:-}; MODEL=${MODEL:-Qwen3-Coder-Next-FP8-bandit}; HOURS=${HOURS:-4}
LOG=$X/results/logs/bandit.log
export G2F_GROUP=${GROUP:-bandit}
log() { echo "$(date '+%F %T') $*" >> "$LOG"; }

j=$(squeue -h -u "$USER" -n "$MODEL" -o %i | head -1)
if [ -z "$j" ]; then
  j=$(scripts/vllm/serve "$MODEL" "$HOURS" | sed -n 's/.* as job \([0-9]*\) .*/\1/p')
  log "server $MODEL: job $j submitted"
else log "server $MODEL: reusing job $j"; fi
f=$G2F_VLLM_DIR/$MODEL-$j.out
until grep -qE 'INFO: +Application startup complete' "$f" 2>/dev/null; do
  squeue -h -j "$j" | grep -q . || { log "server $MODEL: job $j ended before it was ready ($f)"; exit 1; }
  sleep 30
done
log "server $MODEL: ready"
for p in $POOLS; do tag=${p%%:*}; pool=${p#*:}
  for s in $SCHEDS; do for r in $(seq 1 "$REPS"); do
    n=bandit-$tag-$s$LABEL-r$r
    scripts/fuzz path "$n" >/dev/null 2>&1 && { log "campaign $n exists, skipped"; continue; }
    ( set -a; . "$G2F_VLLM_DIR/endpoints/$MODEL.env"; set +a
      export G2F_SCHEDULER=$s G2F_PLATEAU_SEC=$PLATEAU G2F_BACKOFF_SEC=$BACKOFF
      scripts/fuzz reuse "$pool" "$n" >/dev/null && scripts/fuzz run "$n" "$SECS" 2>&1 | grep -E 'submitted|warning|fuzz:' ) |
      while read -r l; do log "$n: $l"; done
  done; done
done
while squeue -h -u "$USER" -o %j | grep -q '^g2f-bandit-.*-r[0-9]'; do sleep 60; done
scancel "$j"; log "server $MODEL: stopped. all campaigns done"
