#!/bin/bash
# Queue runner: G2Fuzz on the targets with every local model, REPS campaigns of SECS fuzzing each.
# Lanes run in parallel, all on H100s (group-csci-591 on gpufairshare, queued; the class's 2-A40
# priority cap is shared with classmates). Models whose sbatch file asks for N A40s get N H100s.
#   LANES="h100 h100b h100c base" (default all): which lanes this runner runs
#   base: the no-LLM baseline (plain AFL++ on the stock seeds, G2F_NO_LLM=1), alias "baseline"
# Per group: start the vLLM servers, wait until ready, start the campaigns, wait for them,
# stop the servers. Campaigns: results/campaigns/<GROUP>/<prefix>-<alias>-r<N>, prefix lineup (jhead),
# tiff, png, xml, wad. Log: results/logs/lineup.log
# Options: TARGETS="jhead tiff_read_rgba_fuzzer libpng_read_fuzzer xml_fuzzer doom_wad" (default
#   jhead), ONLY="<aliases>" (default all models), REPS, SECS, GROUP (the experiment folder, default
#   lineup-1h), plus LANES above. The exact commands behind each result: experiments/recipes/
# Submit from the project root:  sbatch experiments/runners/run-lineup.sbatch
# Stop everything:  scancel -u $USER   (campaigns copy their output back first)
# Resubmitting is safe: it reuses running servers and skips campaigns (and models) already done.
# A runner stops only the servers it started itself (once its own campaigns end); servers it reused keep
# running. Still prefer one runner per server: a runner that started a server stops it even if another runner
# reused it meanwhile (2026-10-14: Gemma lost that way). Start shared servers by hand to avoid that.
#SBATCH --job-name=g2f-lineup-runner
#SBATCH --partition=fairshare
#SBATCH --account=group-csci-591-automated-vulnerability-discovery
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=2G
#SBATCH --time=2-00:00:00
#SBATCH --output=results/logs/runner-%j.out
set -u
X=/home/group/csci-591-automated-vulnerability-discovery/students/BETTER-G2FUZZ-exp
cd "$X" || exit 1
export G2F_VLLM_DIR=$HOME/exp-llm
# gpu049 hung at NCCL init for every 2-GPU server it got (2026-10-10, 2026-10-11)
export G2F_VLLM_EXCLUDE=gpu049
REPS=${REPS:-3}; SECS=${SECS:-3600}; HOURS=${HOURS:-5}
TARGETS=${TARGETS:-jhead}; ONLY=${ONLY:-}
# TAG: run tag after the prefix (e.g. TAG=4h -> xml4h-codernext-r1), for runs kept apart from the 1 h lineup
TAG=${TAG:-}
export G2F_GROUP=${GROUP:-lineup-1h}
declare -A PREFIX=([jhead]=lineup [tiff_read_rgba_fuzzer]=tiff [libpng_read_fuzzer]=png [xml_fuzzer]=xml [doom_wad]=wad [doom_demo]=demo)
LOG=$X/results/logs/lineup.log
log() { echo "$(date '+%F %T') [$LANE] $*" >> "$LOG"; }
# Creates and runs one campaign (args: name, then the command that creates it). Logs scripts/fuzz's
# "submitted"/"warning"/"fuzz:" lines; a failure to create or start it is logged with its exit status.
start_campaign() {
  local n=$1 out rc; shift
  out=$("$@" 2>&1 >/dev/null && scripts/fuzz run "$n" "$SECS" 2>&1); rc=$?
  grep -E 'submitted|warning|fuzz:' <<< "$out" | while read -r l; do log "$n: $l"; done
  [ "$rc" = 0 ] || log "$n: FAILED to start (exit $rc): $(tail -2 <<< "$out" | tr '\n' ' ')"
}

declare -A ALIAS=(
  [gpt-oss-20b]=oss20b [gpt-oss-120b]=oss120b [Qwen3.6-35B-A3B-FP8]=qwen36
  [Qwen3-Coder-30B-A3B-Instruct-FP8]=coder30b [Huihui-Qwen3.5-9B-abliterated]=abl9b
  [Qwen3.5-4B]=qwen4b [Devstral-Small-2-24B-Instruct-2512]=devstral24b
  [gemma-4-26B-A4B-it]=gemma26b [Qwen3-Coder-Next-FP8]=codernext
  [Qwen3.6-35B-A3B-FP8-nothink]=qwen36nt [gemma-4-31B-it]=gemma31b
  [Qwen3.5-122B-A10B-FP8]=qwen122b [DeepSeek-V4-Flash-0731]=dsv4flash
  [Qwen3.8-27B-FP8-nothink]=qwen38 )

# Waits for a server job: 0 when vLLM says it's ready, 1 if the job ended or wasn't ready within
# 40 min of starting. (Don't grep for "Traceback": vLLM logs harmless compile-cache warnings with one.)
wait_ready() {
  local m=$1 j=$2 f=$G2F_VLLM_DIR/$1-$2.out n=0 st
  while :; do
    st=$(squeue -h -j "$j" -o %T 2>/dev/null)
    # an empty answer can be a slurmctld hiccup: ask again before calling the job ended
    [ -n "$st" ] || { sleep 20; st=$(squeue -h -j "$j" -o %T 2>/dev/null); }
    [ -n "$st" ] || return 1
    grep -qE "INFO: +Application startup complete" "$f" 2>/dev/null && return 0
    [ "$st" = RUNNING ] && n=$((n + 1)) && [ $n -gt 80 ] && return 1
    sleep 30
  done
}

# Runs one group of models that share the lane's GPUs.
run_group() {
  local m j a r n t fin g; declare -A JOB=() STARTED=()
  for m in "$@"; do
    [ -z "$ONLY" ] || [[ " $ONLY " == *" ${ALIAS[$m]} "* ]] || continue
    # Skip models whose campaigns all exist, so no server starts for nothing.
    fin=1
    for t in $TARGETS; do for r in $(seq 1 "$REPS"); do
      scripts/fuzz path "${PREFIX[$t]}$TAG-${ALIAS[$m]}-r$r" >/dev/null 2>&1 || fin=0
    done; done
    [ $fin = 1 ] && { log "server $m: all campaigns exist, skipped"; continue; }
    # Resume: reuse a server for this model that is already queued or running.
    j=$(squeue -h -u "$USER" -n "$m" -o %i | head -1)
    if [ -n "$j" ]; then JOB[$m]=$j; log "server $m: reusing job $j"; continue; fi
    # an A40 model gets the same number of H100s (same tensor parallel size)
    g=$(sed -n 's/^#SBATCH --gres=gpu:a40:\([0-9]\)$/\1/p' "scripts/vllm/serve-$m.sbatch")
    j=$(if [ -n "$g" ]; then export G2F_VLLM_ACCOUNT=group-csci-591-automated-vulnerability-discovery \
          G2F_VLLM_PARTITION=gpufairshare G2F_VLLM_GRES=gpu:h100:$g; fi
        scripts/vllm/serve "$m" "$HOURS" | sed -n 's/.* as job \([0-9]*\) .*/\1/p')
    [ -n "$j" ] && JOB[$m]=$j && STARTED[$m]=1 && log "server $m: job $j submitted" || log "server $m: submit FAILED"
  done
  for m in "${!JOB[@]}"; do
    if ! wait_ready "$m" "${JOB[$m]}"; then log "server $m: FAILED to start (see $G2F_VLLM_DIR/$m-${JOB[$m]}.out)"; scancel "${JOB[$m]}"; continue; fi
    log "server $m: ready"
    a=${ALIAS[$m]}
    for t in $TARGETS; do for r in $(seq 1 "$REPS"); do
      n=${PREFIX[$t]}$TAG-$a-r$r
      scripts/fuzz path "$n" >/dev/null 2>&1 && { log "campaign $n exists, skipped"; continue; }
      ( set -a; . "$G2F_VLLM_DIR/endpoints/$m.env"; set +a; export G2F_TARGET=$t
        start_campaign "$n" scripts/fuzz new "$n" )
    done; done
  done
  # Wait for this group's campaigns, then stop its servers.
  while squeue -h -u "$USER" -o %j | grep -qE "^g2f-($(IFS='|'; echo "${PREFIX[*]}"))$TAG-($(for m in "${!JOB[@]}"; do printf '%s|' "${ALIAS[$m]}"; done)NONE)-r"; do sleep 60; done
  # stop only servers this runner started; reused ones (another runner's, or started by hand) keep running
  for m in "${!JOB[@]}"; do
    if [ -n "${STARTED[$m]:-}" ]; then scancel "${JOB[$m]}"; log "server $m: stopped"
    else log "server $m: reused, left running"; fi
  done
}

LANES=${LANES:-h100 h100b h100c base}
lane() { [[ " $LANES " == *" $1 "* ]]; }
LANE=h100; lane $LANE && (
  log "lane start"; run_group Qwen3-Coder-Next-FP8 Qwen3.8-27B-FP8-nothink; log "lane done" ) &
LANE=h100b; lane $LANE && (
  log "lane start"; run_group gemma-4-31B-it Qwen3.6-35B-A3B-FP8-nothink; log "lane done" ) &
LANE=h100c; lane $LANE && (
  log "lane start"; run_group Qwen3.5-4B; log "lane done" ) &
LANE=base; lane $LANE && (
  log "lane start"
  [ -z "$ONLY" ] || [[ " $ONLY " == *" baseline "* ]] || exit 0
  for t in $TARGETS; do for r in $(seq 1 "$REPS"); do
    n=${PREFIX[$t]}$TAG-baseline-r$r
    scripts/fuzz path "$n" >/dev/null 2>&1 && { log "campaign $n exists, skipped"; continue; }
    ( export G2F_TARGET=$t G2F_NO_LLM=1
      start_campaign "$n" scripts/fuzz new "$n" )
  done; done
  log "lane done" ) &
wait
LANE=all; log "all lanes done. Summary: experiments/analysis/summarize"
