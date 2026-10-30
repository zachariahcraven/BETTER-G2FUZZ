#!/usr/bin/env bash
# test_fuzz_cli.sh: regression test for scripts/fuzz. Runs every command, flag and error path (~180 cases) against
# fake Slurm commands, so nothing is ever submitted or cancelled, and compares everything the script does between
# two versions of it: exit code, output, the Slurm commands it calls, and the files it writes (with permissions).
#
# Usage (on Tempest, from the repo root; the --model cases need the real students/shared-models):
#   scripts/tests/test_fuzz_cli.sh [OLD]   OLD: the version to compare with: a file, or a git revision (default HEAD)
#   KEEP=1 scripts/tests/test_fuzz_cli.sh  keep the temp folder (its path is printed) to look at the outputs
#
# Passes when the current scripts/fuzz behaves exactly like OLD, and the contracts other scripts rely on hold:
# run.sh has "-V <secs>" (read by 01-baseline-replication/analysis), job.sbatch has "OPENAI_BASE_URL=" (read by the
# launchers), `run` prints "submitted Slurm job" last, `llm status` prints "ready:" (read by scripts/study),
# and every generated run.sh/job.sbatch passes `bash -n`. Plus fixed bugs that must stay fixed (see the last checks).
# scripts/study runs in its current version on both sides (only scripts/fuzz is compared); its checks are contracts.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OLD_SPEC="${1:-HEAD}"
T=$(mktemp -d "${TMPDIR:-/tmp}/fuzz-test.XXXXXX")
if [ "${KEEP:-0}" = 1 ]; then echo "temp folder: $T"; else trap 'rm -rf "$T"' EXIT; fi
W=$T/work   # the fake repo and home, rebuilt for every case (the same path for both versions)
E=$W/repo/experiments/practice/campaigns
G=group-csci-591-automated-vulnerability-discovery P=priority-csci-591-automated-vulnerability-discovery

# The two versions
if [ -f "$OLD_SPEC" ]; then cp "$OLD_SPEC" "$T/fuzz.old"
else git -C "$REPO" show "$OLD_SPEC:scripts/fuzz" > "$T/fuzz.old"; fi
cp "$REPO/scripts/fuzz" "$T/fuzz.new"

# --- Fake Slurm and friends: each logs its call to $STUB_LOG and answers from the scenario folder $SCEN ---------
mkdir -p "$T/bin"
for s in sbatch scancel srun; do
  cat > "$T/bin/$s" <<'EOF'
#!/bin/bash
{ printf '%s' "$(basename "$0")"; printf ' %q' "$@"; echo; } >> "$STUB_LOG"
if [ "$(basename "$0")" = sbatch ]; then
  n=$(( $(cat "$SCEN/counter" 2>/dev/null || echo 950000) + 1 )); echo "$n" > "$SCEN/counter"
  case " $* " in *" --parsable "*) echo "$n;tempest" ;; *) echo "Submitted batch job $n" ;; esac
fi
EOF
done
cat > "$T/bin/sacctmgr" <<'EOF'
#!/bin/bash
{ printf 'sacctmgr'; printf ' %q' "$@"; echo; } >> "$STUB_LOG"
cat "$SCEN/accounts" 2>/dev/null; exit 0
EOF
cat > "$T/bin/curl" <<'EOF'
#!/bin/bash
{ printf 'curl'; printf ' %q' "$@"; echo; } >> "$STUB_LOG"
[ -f "$SCEN/curl" ] && cat "$SCEN/curl" || exit 7
EOF
cat > "$T/bin/date" <<'EOF'
#!/bin/bash
# a fixed clock, except for file times (date -r)
case " $* " in *" -r "*) exec /bin/date "$@" ;; *) exec /bin/date -d @1800000000 "$@" ;; esac
EOF
# squeue: rows of $SCEN/jobs are id|user|name|state|comment|node|account|command[|time left]; supports -h -j -n -t -u
# -A -o. $SCEN/squeue_fail makes every call fail (Slurm not answering).
cat > "$T/bin/squeue" <<'EOF'
#!/usr/bin/env python3
import os, re, sys
with open(os.environ["STUB_LOG"], "a") as log:
    log.write("squeue " + " ".join(repr(a) for a in sys.argv[1:]) + "\n")
if os.path.exists(os.environ["SCEN"] + "/squeue_fail"):
    sys.stderr.write("slurm_load_jobs error: Socket timed out on send/recv operation\n"); sys.exit(1)
keys = "iujTkNAoL"
heads = {"i": "JOBID", "u": "USER", "j": "NAME", "T": "STATE", "k": "COMMENT", "N": "NODELIST", "A": "ACCOUNT",
         "o": "COMMAND", "M": "TIME", "L": "TIME_LEFT", "e": "END_TIME"}
rows = []
if os.path.exists(os.environ["SCEN"] + "/jobs"):
    for line in open(os.environ["SCEN"] + "/jobs"):
        if line.strip():
            f = dict(zip(keys, line.rstrip("\n").split("|")))
            for k, v in dict(M="1:00:00", L="1-12:00:00", e="2027-01-15T10:00:00").items(): f.setdefault(k, v)
            rows.append(f)
a = sys.argv[1:]; opt = {}; header = True; i = 0
while i < len(a):
    if a[i] == "-h": header = False; i += 1
    else: opt[a[i]] = a[i + 1]; i += 2
if "-j" in opt: rows = [r for r in rows if r["i"] in opt["-j"].split(",")]
if "-n" in opt: rows = [r for r in rows if r["j"] in opt["-n"].split(",")]
if "-t" in opt: rows = [r for r in rows if r["T"] in opt["-t"].upper().split(",")]
if "-u" in opt: rows = [r for r in rows if r["u"] == opt["-u"]]
if "-A" in opt: rows = [r for r in rows if r["A"] in opt["-A"].split(",")]
if "-j" in opt and not rows:
    sys.stderr.write("slurm_load_jobs error: Invalid job id specified\n"); sys.exit(1)
fmt = opt.get("-o", "%.18i %.9T %j")
def render(get):
    def one(m):
        width, key = m.group(1), m.group(2)
        v = get(key)
        return v.rjust(int(width[1:])) if width and width.startswith(".") else v
    return re.sub(r"%(\.?\d+)?([a-zA-Z])", one, fmt)
if header: print(render(lambda k: heads.get(k, k)))
for r in rows: print(render(lambda k: r.get(k, "")))
EOF
chmod +x "$T/bin"/*

# Safety: every Slurm command must be one of the stubs above
for c in sbatch squeue scancel sacctmgr srun curl date; do
  got=$(env -i PATH="$T/bin:/usr/bin:/bin" bash -c "command -v $c")
  [ "$got" = "$T/bin/$c" ] || { echo "abort: $c resolves to $got, not the stub" >&2; exit 2; }
done

# --- Fixtures ------------------------------------------------------------------------------------------------------
# A finished G2FUZZ campaign: seeds, generators, queue, crashes, stats, logs (fixed file times)
done_campaign() {
  local c=$1 o=$1/jhead_output/default
  mkdir -p "$c/initial_seeds" "$o/generators" "$o/queue" "$o/crashes" "$o/mutation_log"
  echo a > "$c/initial_seeds/jpg-1_0"; echo b > "$c/initial_seeds/stock.jpg"
  echo 'print(1)' > "$o/generators/jpg-1.py"; echo 'print(2)' > "$o/generators/jpg-2.py"
  echo q > "$o/queue/id:000000,time:0,execs:0,orig:jpg-1_0"; echo q > "$o/queue/id:000001,src:000000,time:5000,execs:9,op:havoc"
  echo x > "$o/crashes/id:000000,sig:11,src:000001"; echo readme > "$o/crashes/README.txt"
  printf '%s\n' "run_time          : 600" "execs_done        : 600000" "execs_per_sec     : 1000.00" "corpus_count      : 2" \
    "edges_found       : 300" "total_edges       : 1962" "saved_crashes     : 1" "stability         : 100.00%" > "$o/fuzzer_stats"
  printf '%s\n' "# relative_time, cycles_done, cur_item, corpus_count, pending_total, pending_favs, map_size, saved_crashes, saved_hangs, max_depth, execs_per_sec, total_execs, edges_found" \
    "600, 1, 0, 2, 0, 1, 15.29%, 1, 0, 2, 1000.00, 600000, 300" > "$o/plot_data"
  echo '{"jpg-1.py": ["jpg-2.py"]}' > "$o/mutation_log/relationship.json"
  printf '%s\n' "G2F: LLM step after 10s without finds (+0s per step)" "Fuzzing test case #1" "==== Gen-M start ====" "Fuzzing test case #2" > "$c/fuzz.log"
  printf '%s\n' '{"ts": 1799999000, "model": "Qwen3.8-27B-FP8-nothink", "secs": 50.0, "status": "ok", "attempt": 1}' \
    '{"ts": 1799999500, "model": "Qwen3.8-27B-FP8-nothink", "secs": 61.5, "status": "error", "attempt": 1}' > "$c/llm_calls.jsonl"
  echo 6001 > "$c/slurm.jobid"; echo ucb > "$c/generator_scheduler"; echo 1.0 > "$c/ucb_exploration"
  echo '{"model": ["Qwen3.8-27B-FP8-nothink"]}' > "$c/model_setting.json"
  find "$c" -exec touch -d @1799999900 {} +
}
# A campaign as `new` makes it, for model $2
fresh_campaign() {
  mkdir -p "$1"; cp "$REPO/g2fuzz/program_to_format.json" "$1/"; printf '{"model": ["%s"]}\n' "$2" > "$1/model_setting.json"
}

setup_work() {
  rm -rf "$W"; mkdir -p "$W/repo/scripts" "$W/repo/g2fuzz" "$W/home" "$W/scen" "$W/targets/seeds/png_t" "$E" "$W/emptyeval"
  cp "$1" "$W/repo/scripts/fuzz"; chmod +x "$W/repo/scripts/fuzz"
  cp "$REPO/scripts/llm-serve.sbatch" "$W/repo/scripts/"; cp "$REPO/g2fuzz/program_to_format.json" "$W/repo/g2fuzz/"
  mkdir -p "$W/repo/build"; : > "$W/repo/build/g2fuzz.sif"; echo "testimage built 2026-01-01 00:00" > "$W/repo/build/g2fuzz.sif.version"
  local q=Qwen3.8-27B-FP8-nothink
  done_campaign "$E/src"
  fresh_campaign "$E/fresh" $q; fresh_campaign "$E/pfresh" $q; fresh_campaign "$E/phi" phi-4
  fresh_campaign "$E/seeded" $q; mkdir -p "$E/seeded/initial_seeds" "$E/seeded/jhead_output/default/generators"
  echo s > "$E/seeded/initial_seeds/a"; echo 'print(3)' > "$E/seeded/jhead_output/default/generators/jpg-3.py"
  fresh_campaign "$E/seedsonly" $q; mkdir -p "$E/seedsonly/initial_seeds"; echo s > "$E/seedsonly/initial_seeds/a"
  fresh_campaign "$E/busy" $q; echo 7001 > "$E/busy/slurm.jobid"
  fresh_campaign "$E/queued" $q; echo 7002 > "$E/queued/slurm.jobid"
  fresh_campaign "$E/nosetting" $q; rm "$E/nosetting/model_setting.json"
  local i=0 c   # fixed folder times, oldest first: "seeded" is the newest (need_campaign names it when a name is missing)
  for c in src fresh pfresh phi seedsonly busy queued nosetting seeded; do touch -d @$((1799990000 + i)) "$E/$c"; i=$((i + 1)); done
  : > "$W/empty.key"
  echo "@@ /dev/null" > "$W/targets/png_t.args"; echo "-x;y @@" > "$W/targets/bad_t.args"; echo "@@ @@" > "$W/targets/two_t.args"
  # scripts/study and the studies it runs: 02 (its real study.conf) and five small ones for the study cases
  cp "$REPO/scripts/study" "$W/repo/scripts/"
  mkdir -p "$W/repo/experiments/02-model-sweep/launch"
  cp "$REPO/experiments/02-model-sweep/launch/targets.txt" "$REPO/experiments/02-model-sweep/launch/study.conf" \
    "$W/repo/experiments/02-model-sweep/launch/"
  local x; for x in 03-test 04-reuse 05-bad 06-badtarget 07-wait 08-trap 09-cont; do mkdir -p "$W/repo/experiments/$x/launch"; done
  printf '%s\n' "targets = jhead" "arms    = ucb: --scheduler ucb | random: --scheduler random" "        | afl: --afl" \
    "reps    = 2" "secs    = 600" "seeds   = shared   # one seed generation, reused by both G2FUZZ arms" \
    > "$W/repo/experiments/03-test/launch/study.conf"
  printf '%s\n' "targets = jhead" "arms = ucb: --scheduler ucb" "secs = 600" "seeds = reuse:../../practice/campaigns/src" \
    > "$W/repo/experiments/04-reuse/launch/study.conf"
  printf '%s\n' "targets = jhead" "arms = a: --afl" "colour = red" > "$W/repo/experiments/05-bad/launch/study.conf"
  printf '%s\n' "targets = nosuch" "arms = a: --afl" > "$W/repo/experiments/06-badtarget/launch/study.conf"
  # 07: arm g2f is done (on a Qwen server the study started), arm afl isn't launched yet
  printf '%s\n' "targets = jhead" "arms = g2f: --scheduler ucb | afl: --afl" "secs = 600" "name = {target}-{arm}-r{rep}" \
    > "$W/repo/experiments/07-wait/launch/study.conf"
  done_campaign "$W/repo/experiments/07-wait/campaigns/jhead-g2f-r1"
  echo "Qwen3.8-27B-FP8 948000" > "$W/repo/experiments/07-wait/campaigns/.study-servers"
  # 08: 03's campaigns, with the Qwen server (job 948000) started by the study and seen ready
  cp "$W/repo/experiments/03-test/launch/study.conf" "$W/repo/experiments/08-trap/launch/"
  mkdir -p "$W/repo/experiments/08-trap/campaigns"
  printf '%s\n' "Qwen3.8-27B-FP8 948000" "Qwen3.8-27B-FP8 948000 ready" > "$W/repo/experiments/08-trap/campaigns/.study-servers"
  # 09: a | line continues targets
  printf '%s\n' "targets = jhead" "        | mp42aac" "arms = a: --afl" > "$W/repo/experiments/09-cont/launch/study.conf"
}

# Scenarios: which jobs squeue shows, which accounts sacctmgr lists, whether the server answers
scenario() {
  local s=$W/scen srv="948000|tester|llm-serve|RUNNING|model=Qwen3.8-27B-FP8-nothink|gpu027|$P|$W/home/llm/llm-serve.sbatch"
  local runs="7001|tester|g2f-busy|RUNNING|(null)|cpu001|$G|$E/busy/job.sbatch
7002|tester|g2f-queued|PENDING|(null)|(None)|$G|$E/queued/job.sbatch"
  printf '%s\n' "$G" "$P" > "$s/accounts"
  echo '{"object":"list","data":[{"id":"Qwen3.8-27B-FP8-nothink"},{"id":"phi-4"}]}' > "$s/curl"
  case "$1" in
    base)     printf '%s\n' "$srv" "$runs" > "$s/jobs" ;;
    solo)     echo "$srv" > "$s/jobs" ;;
    pending)  printf '%s\n' "948000|tester|llm-serve|PENDING|model=Qwen3.8-27B-FP8-nothink|(None)|$P|x" "$runs" > "$s/jobs" ;;
    none)     : > "$s/jobs" ;;
    other)    echo "${srv/|tester|/|alice|}" > "$s/jobs" ;;
    loading)  echo "$srv" > "$s/jobs"; rm "$s/curl" ;;
    two)      printf '%s\n' "$srv" "948001|alice|llm-serve|RUNNING|model=phi-4|gpu028|$P|x" > "$s/jobs" ;;
    untagged) echo "948000|tester|llm-serve|RUNNING|(null)|gpu027|$P|x" > "$s/jobs" ;;
    noprio)   : > "$s/jobs"; echo "$G" > "$s/accounts" ;;
    noacct)   : > "$s/jobs"; : > "$s/accounts" ;;
    revelle)  : > "$s/jobs"; echo group-mattrevelle > "$s/accounts" ;;
    qcmember) : > "$s/jobs"; echo priority-quantumcore >> "$s/accounts" ;;
    qc)       echo "${srv/|$P|/|priority-quantumcore|}" > "$s/jobs" ;;   # the Qwen server on quantumcore's account
    driver)   printf '%s\n' "$srv" "948500|bob|study-03-test|RUNNING|study=$W/repo/experiments/03-test|cpu010|$G|x" > "$s/jobs" ;;
    otherdriver) printf '%s\n' "$srv" "948501|bob|study-03-test|RUNNING|study=/home/bob/copy/03-test|cpu011|$G|x" > "$s/jobs" ;;
    short)    echo "$srv|1:00:00" > "$s/jobs" ;;   # the Qwen server has 1 h left
    sqfail)   echo "$srv" > "$s/jobs"; : > "$s/squeue_fail" ;;
    allmodels)   # a ready server for each of study 02's 5 models
      local m i=0; : > "$s/jobs"; : > "$s/curl"
      for m in Qwen3.8-27B-FP8-nothink phi-4 starcoder2-15b-instruct-v0.1 DeepSeek-Coder-V2-Lite-Instruct Mistral-Small-3.1-24B-Instruct-2503; do
        echo "94800$i|tester|llm-serve|RUNNING|model=$m|gpu02$i|$P|x" >> "$s/jobs"; printf '{"id":"%s"} ' "$m" >> "$s/curl"; i=$((i + 1))
      done ;;
    *) echo "unknown scenario $1" >&2; exit 2 ;;
  esac
}

# Everything a case left behind: the file tree with modes, then every small file's contents
snapshot() {
  (cd "$W" && find . -path ./scen -prune -o -printf '%y %m %P\n' | sort)
  (cd "$W" && find repo/experiments home -type f -size -64k | sort | while read -r f; do echo "=== $f"; cat -v "$f"; done)
}

# run_case <name> <scenario> [VAR=value ...] -- <scripts/fuzz args ...>
#   args starting with @study run scripts/study; a leading @twice runs the command twice
run_case() {
  local name=$1 scen=$2 o; shift 2
  local -a vars=() cmd   # (bash 4.4+: empty arrays are fine under set -u)
  local twice=0 k
  while [ "$1" != -- ]; do vars+=("$1"); shift; done; shift
  o="$OUTDIR/$name"; mkdir -p "$o"
  setup_work "$SCRIPT"; scenario "$scen"
  if [ "${1:-}" = @twice ]; then twice=1; shift; fi
  if [ "${1:-}" = @study ]; then shift; cmd=("$W/repo/scripts/study" "$@")
  else cmd=(bash "$W/repo/scripts/fuzz" "$@"); fi
  ( set +e; cd "$W"
    for k in $(seq 0 "$twice"); do
      env -i PATH="$T/bin:/usr/bin:/bin" HOME="$W/home" USER=tester LANG=C LC_ALL=C TZ=UTC SCEN="$W/scen" \
        STUB_LOG="$o/calls" "${vars[@]}" "${cmd[@]}" >> "$o/out" 2>> "$o/err" < /dev/null
      echo $? > "$o/rc"
    done )
  touch "$o/calls"; snapshot > "$o/tree"
  # keep the generated job files for the contract checks, and check their syntax
  local f
  while read -r f; do
    mkdir -p "$o/gen/$(basename "$(dirname "$f")")"; cp "$f" "$o/gen/$(basename "$(dirname "$f")")/"
    bash -n "$f" 2>/dev/null && echo "bash -n ok: ${f#$W/}" >> "$o/syntax" || echo "bash -n FAIL: ${f#$W/}" >> "$o/syntax"
  done < <(find "$W/repo/experiments" \( -name run.sh -o -name job.sbatch \) | sort)
}

all_cases() {
  local tg="G2F_TARGETS=$W/targets"
  # new
  run_case new_named base -- new t1
  run_case new_default base -- new
  run_case new_dotname base -- new .bad
  run_case new_badchars base -- new "a b"
  run_case new_exists base -- new src
  run_case new_model base -- new t2 --model phi-4
  run_case new_model_eq base -- new t3 --model=phi-4
  run_case new_model_qwen base -- new --model Qwen3.8-27B-FP8 t4
  run_case new_model_unknown base -- new t5 --model nosuch
  run_case new_model_novalue base -- new t6 --model
  run_case new_env_model base G2F_MODEL=custom-model -- new t7
  run_case new_eval base "G2F_EVAL=$W/emptyeval" -- new t8
  # reuse
  run_case reuse_ok base -- reuse src r1
  run_case reuse_default_name base -- reuse src
  run_case reuse_missing base -- reuse nosuch r2
  run_case reuse_noseeds base -- reuse fresh r3
  run_case reuse_nogens base -- reuse seedsonly r4
  run_case reuse_noarg base -- reuse
  run_case reuse_model base -- reuse src r5 --model phi-4
  # run
  run_case run_seedgen base -- run fresh 900
  run_case run_reused_test base -- run seeded 300 --test
  run_case run_afl_stock base -- run fresh 120 --afl
  run_case run_afl_seeds none -- run seeded 120 --afl
  run_case run_test_afl base -- run fresh 60 --test --afl
  run_case run_badsecs base -- run fresh 9x
  run_case run_default_secs base -- run seeded
  run_case run_paper base "$tg" G2F_TARGET=png_t -- run pfresh 600
  run_case run_paper_afl base "$tg" G2F_TARGET=png_t -- run pfresh 600 --afl
  run_case run_paper_badargs base "$tg" G2F_TARGET=bad_t -- run pfresh 600
  run_case run_paper_twoargs base "$tg" G2F_TARGET=two_t -- run pfresh 600
  run_case run_paper_noargs base "$tg" G2F_TARGET=noargs_t -- run pfresh 600
  run_case run_seeds_env base G2F_SEEDS=/my/seeds -- run fresh 600 --afl
  run_case run_ucb base G2F_GENERATOR_SCHEDULER=ucb G2F_UCB_EXPLORATION=0.5 -- run seeded 300
  run_case run_badsched base G2F_GENERATOR_SCHEDULER=bandit -- run seeded 300
  run_case run_badexpl base G2F_GENERATOR_SCHEDULER=ucb G2F_UCB_EXPLORATION=0 -- run seeded 300
  run_case run_badexpl2 base G2F_UCB_EXPLORATION=1,2 -- run seeded 300
  run_case run_sched_random base -- run seeded 300 --scheduler random
  run_case run_sched_eq base -- run seeded 300 --scheduler=random
  run_case run_sched_novalue base -- run seeded 300 --scheduler
  run_case run_sched_bad base -- run seeded 300 --scheduler bandit
  run_case run_sched_afl base -- run fresh 120 --afl --scheduler ucb
  run_case run_sched_override base G2F_GENERATOR_SCHEDULER=random -- run seeded 300 --scheduler ucb
  run_case run_baseurl none G2F_BASE_URL=http://x:1/v1 -- run seeded 300
  run_case run_model_mismatch base -- run seeded 300 --model phi-4
  run_case run_model_match two -- run phi 300 --model phi-4
  run_case run_phi_noserver base -- run phi 300
  run_case run_pending pending -- run seeded 300
  run_case run_noserver none -- run seeded 300
  run_case run_loading loading -- run seeded 300
  run_case run_untagged untagged -- run seeded 300
  run_case run_active base -- run busy 300
  run_case run_fuzzed base -- run src 300
  run_case run_settings base G2F_BASE_URL=http://x:1/v1 G2F_SEEDGEN_MIN=300 G2F_CPUS=4 G2F_MEM=16G G2F_PARTITION= G2F_ACCOUNT=acct-x -- run fresh 600
  run_case run_nosif base "G2F_SIF=$W/nope.sif" -- run seeded 300
  run_case run_sif base "G2F_SIF=$W/repo/build/g2fuzz.sif" -- run seeded 300
  run_case run_emptykey base "G2F_KEY=$W/empty.key" -- run seeded 300
  run_case run_key base "G2F_KEY=$W/repo/build/g2fuzz.sif.version" -- run seeded 300
  run_case run_nocampaign base -- run nosuch
  run_case run_nosetting base -- run nosetting 300   # no model_setting.json: the default model
  run_case run_noname base -- run
  # shell
  run_case shell_ok base -- shell seeded
  run_case shell_test base -- shell seeded --test
  run_case shell_noserver none -- shell seeded
  run_case shell_loading loading -- shell seeded
  run_case shell_sched base -- shell seeded --scheduler random
  # llm
  run_case llm_start_default none -- llm start
  run_case llm_start_h100_phi none -- llm start 48 h100 --model phi-4
  run_case llm_start_badhours none -- llm start x
  run_case llm_start_zero none -- llm start 0
  run_case llm_start_badgpu none -- llm start 2 v100
  run_case llm_start_up solo -- llm start 2
  run_case llm_start_up_pending pending -- llm start 2
  run_case llm_start_up_other other -- llm start 2
  run_case llm_start_nopriority noprio -- llm start 2
  run_case llm_start_nopriority_h100 noprio -- llm start 2 h100
  run_case llm_start_mistral none -- llm start 2 --model Mistral-Small-3.1-24B-Instruct-2503
  run_case llm_start_qc_h100 qcmember -- llm start 24 qc-h100 --model phi-4
  run_case llm_start_qc_a40 qcmember -- llm start 2 qc-a40 --model Mistral-Small-3.1-24B-Instruct-2503
  run_case llm_start_qc_notmember none -- llm start 2 qc-h100
  run_case llm_start_qc_up qc -- llm start 2 a40
  run_case llm_status_qc qc -- llm status
  run_case run_qc_server qc -- run seeded 300
  run_case llm_status_none none -- llm status
  run_case llm_status_default solo -- llm
  run_case llm_status_pending pending -- llm status
  run_case llm_status_loading loading -- llm status
  run_case llm_status_ready solo -- llm status
  run_case llm_status_two two -- llm status
  run_case llm_status_filter two -- llm status --model phi-4
  run_case llm_status_untagged untagged -- llm status
  run_case llm_stop_none none -- llm stop
  run_case llm_stop_other other -- llm stop
  run_case llm_stop_busy base -- llm stop
  run_case llm_stop_ok solo -- llm stop
  run_case llm_stop_model two -- llm stop --model phi-4
  run_case llm_host solo -- llm host
  run_case llm_host_model two -- llm host --model phi-4
  run_case llm_host_none none -- llm host
  run_case llm_bad base -- llm frob
  # reports and the rest
  run_case status_done base -- status src
  run_case status_list base -- status
  run_case status_seeded base -- status seeded
  run_case status_running base -- status busy
  run_case status_queued base -- status queued
  run_case status_missing base -- status nosuch
  run_case results_src base -- results src
  run_case results_nostats base -- results fresh
  run_case results_noname base -- results
  run_case watch_noname base -- watch
  run_case watch_noname_none base "G2F_EVAL=$W/emptyeval" -- watch
  run_case watch_done base -- watch src
  run_case list base -- list   # includes campaigns that never ran (no <target>_output/default)
  run_case list_alias base -- ls
  run_case list_empty base "G2F_EVAL=$W/emptyeval" -- list
  run_case stop_active base -- stop busy
  run_case stop_inactive base -- stop src
  run_case stop_noarg base -- stop
  run_case account base -- account
  run_case account_env base G2F_ACCOUNT=acct-x -- account
  run_case account_none noacct -- account
  run_case account_mattrevelle revelle -- account
  run_case help base -- help
  run_case help_default base --
  run_case unknown base -- frob
  run_case completion base -- completion
  # study 02 (its real study.conf), one model
  run_case study_02_dry solo -- @study start 02-model-sweep --only arm=phi-4 --secs 600 --dry
  run_case study_02_start two -- @study start 02-model-sweep --only arm=phi-4 --secs 600 --max-seedgen 2
  run_case study_02_noserver none -- @study start 02-model-sweep --only arm=phi-4 --secs 600
  run_case study_02_status two -- @study status 02-model-sweep --only arm=phi-4
  run_case study_02_all allmodels -- @study start 02-model-sweep --max-seedgen 15   # every one of the 75, as Slurm would get them
  # scripts/study
  run_case study_help solo -- @study help
  run_case study_show solo -- @study show 03-test
  run_case study_show_02 solo -- @study show 02-model-sweep --only arm=phi-4
  run_case study_only solo -- @study show 03-test --only arm=ucb --only rep=2
  run_case study_dry solo -- @study start 03-test --dry
  run_case study_dry_noserver none -- @study start 03-test --dry
  run_case study_start solo -- @study start 03-test
  run_case study_twice solo -- @twice @study start 03-test --only arm=afl
  run_case study_reuse solo -- @study start 04-reuse
  run_case study_noserver none -- @study start 03-test
  run_case study_status solo -- @study status 03-test
  run_case study_csv solo -- @study csv 03-test
  run_case study_badconf solo -- @study show 05-bad
  run_case study_badtarget solo -- @study show 06-badtarget
  run_case study_nostudy solo -- @study show nosuch
  run_case study_badonly solo -- @study show 03-test --only colour=red
  run_case study_reuse_show solo -- @study show 04-reuse   # the reuse source is checked when settings load
  # scripts/study: servers, the driver, --wait, results
  run_case study_02_servers_dry none -- @study start 02-model-sweep --servers --dry
  run_case study_servers none -- @study start 03-test --servers
  run_case study_servers_ready solo -- @study start 03-test --servers --only arm=ucb
  run_case study_servers_qc qcmember -- @study start 02-model-sweep --only arm=phi-4 --secs 600 --servers --gpu qc-h100
  run_case study_servers_noacct none -- @study start 02-model-sweep --only arm=phi-4 --servers --gpu qc-h100
  run_case study_servers_retry none STUDY_POLL_SECS=0 STUDY_MAX_PASSES=9 -- @study start 03-test --servers --wait --only arm=ucb
  run_case study_badgpu solo -- @study show 03-test --gpu v100
  run_case study_background solo -- @study start 03-test --servers --background
  run_case study_background_dry solo -- @study start 03-test --background --dry
  run_case study_driver_running driver -- @study start 03-test
  run_case study_driver_dry driver -- @study start 03-test --dry
  run_case study_driver_status driver -- @study status 03-test
  run_case study_wait solo STUDY_POLL_SECS=0 -- @study start 07-wait --servers --wait
  run_case study_wait_noserver none STUDY_POLL_SECS=0 -- @study start 03-test --wait
  run_case study_wait_limit solo STUDY_POLL_SECS=0 STUDY_MAX_PASSES=2 -- @study start 03-test --wait --only arm=ucb
  run_case study_results solo -- @study results 07-wait
  run_case study_results_part solo -- @study results 07-wait --only target=jhead
  run_case study_status_servers solo -- @study status 07-wait
  run_case study_short short -- @study start 03-test
  run_case study_trap solo STUDY_POLL_SECS=0 STUDY_MAX_PASSES=1 -- @study start 08-trap --servers --wait --only arm=ucb
  run_case study_dry_noacct none -- @study start 02-model-sweep --only arm=phi-4 --servers --gpu qc-h100 --dry
  run_case study_sqfail_status sqfail -- @study status 07-wait
  run_case study_sqfail_wait sqfail STUDY_POLL_SECS=0 STUDY_MAX_PASSES=2 -- @study start 07-wait --wait
  run_case study_results_twice solo -- @twice @study results 07-wait
  run_case study_other_driver otherdriver -- @study start 03-test --only arm=afl
  run_case study_env solo G2F_UCB_EXPLORATION=0.5 G2F_CPUS=8 G2F_MEM=64G -- @study start 03-test --only arm=ucb
  run_case study_cont solo -- @study show 09-cont
}

for side in old new; do
  OUTDIR=$T/out/$side SCRIPT=$T/fuzz.$side
  all_cases
done
ncases=$(ls "$T/out/new" | wc -l | tr -d ' ')

fails=0
if diff -r "$T/out/old" "$T/out/new" > "$T/diff.txt"; then
  echo "same behavior as $OLD_SPEC in all $ncases cases"
else
  echo "DIFFERENT from $OLD_SPEC in: $(grep -oE "^(diff -r|Only in) $T/out/(old|new)/[^/ :]+" "$T/diff.txt" | sed 's#.*/##' | sort -u | xargs)"
  [ "${KEEP:-0}" = 1 ] && echo "details: $T/diff.txt" || head -40 "$T/diff.txt"
  fails=$((fails + 1))
fi

# Contracts (on the current version)
N=$T/out/new
contract() { if eval "$2"; then echo "ok    $1"; else echo "FAIL  $1"; fails=$((fails + 1)); fi; }
firstv() { grep -o -- '-V [0-9]*' "$1" | head -1; }
contract "run.sh carries -V <secs> (G2FUZZ run)"      '[ "$(firstv "$N/run_seedgen/gen/fresh/run.sh")" = "-V 900" ]'
contract "run.sh carries -V <secs> (--afl run)"       '[ "$(firstv "$N/run_afl_stock/gen/fresh/run.sh")" = "-V 120" ]'
contract "job.sbatch names the LLM server"            'grep -qF "OPENAI_BASE_URL=http://gpu027:28000/v1" "$N/run_seedgen/gen/fresh/job.sbatch"'
contract "--afl job.sbatch doesn't check a server"    '! grep -q curl "$N/run_afl_stock/gen/fresh/job.sbatch"'
contract "run prints \"submitted Slurm job\" last"   '[[ "$(tail -1 "$N/run_seedgen/out")" == "submitted Slurm job "* ]]'
contract "llm status prints ready:"                   'grep -q "^ready: Qwen3.8-27B-FP8-nothink on gpu027$" "$N/llm_status_ready/out"'
contract "every generated file passes bash -n"        '! cat "$N"/*/syntax 2>/dev/null | grep -q FAIL'
contract "study 02: launches 2 with --max-seedgen 2"    '[ "$(grep -c "submitted Slurm job" "$N/study_02_start/out")" = 2 ]'
# fixed 2026-10-29 (+ default names with the NetID, a hint for a missing name): list stopped at a campaign without output; run exited silently without model_setting.json;
# run submitted jobs while the server was still loading (they then failed on the node)
contract "list shows all 9 campaigns"                 '[ "$(cat "$N/list/rc")" = 0 ] && [ "$(wc -l < "$N/list/out")" = 10 ]'
contract "run works without model_setting.json"      '[[ "$(tail -1 "$N/run_nosetting/out")" == "submitted Slurm job "* ]]'
contract "run refuses while the server loads"         '[ "$(cat "$N/run_loading/rc")" = 1 ] && grep -q "still loading" "$N/run_loading/err" && ! grep -q "^sbatch" "$N/run_loading/calls"'
contract "default names start with the NetID"        'grep -q "^created experiments/practice/campaigns/tester-jhead-" "$N/new_default/out"'
contract "a missing name points to your latest"      'grep -q "missing campaign name; your latest is seeded " "$N/watch_noname/err"'
# the generator scheduler: ucb by default, --scheduler random for upstream, shown by status, ucb in study 02
contract "run defaults to ucb"                       'grep -q "^generator scheduler: ucb (exploration 1.0)$" "$N/run_seedgen/out" && grep -q "G2F_GENERATOR_SCHEDULER=ucb" "$N/run_seedgen/gen/fresh/job.sbatch"'
contract "--scheduler random picks upstream"          'grep -q "^generator scheduler: random" "$N/run_sched_random/out" && grep -q "G2F_GENERATOR_SCHEDULER=random" "$N/run_sched_random/gen/seeded/job.sbatch"'
contract "--scheduler beats G2F_GENERATOR_SCHEDULER"  'grep -q "G2F_GENERATOR_SCHEDULER=ucb" "$N/run_sched_override/gen/seeded/job.sbatch"'
contract "--afl jobs carry no scheduler"              '! grep -q G2F_GENERATOR_SCHEDULER "$N/run_afl_stock/gen/fresh/job.sbatch"'
contract "status shows the scheduler"                 'grep -q "^scheduler    ucb (exploration 1.0)$" "$N/status_done/out"'
contract "study 02 records ucb"                        'grep -q "^scheduler: ucb$" "$N/study_02_start/tree"'
# scripts/study
contract "study: show lists the seed campaign + 6"      '[ "$(grep -c jhead "$N/study_show/out")" = 7 ]'
contract "study: shared seeds start with the seed run"  'grep -q "^  seeds/Qwen3.8-27B-FP8-jhead: submitted Slurm job" "$N/study_start/out" && grep -q "waiting for seeds from seeds/Qwen3.8-27B-FP8-jhead" "$N/study_start/out"'
contract "study: --afl arms launch without a server"    '[ "$(grep -c "submitted Slurm job" "$N/study_noserver/out")" = 2 ] && grep -q "server isn.t running" "$N/study_noserver/out"'
contract "study: never launches a campaign twice"       '[ "$(grep -c "submitted Slurm job" "$N/study_twice/out")" = 2 ]'
contract "study: reuse copies the seeds"                'grep -q "04-reuse/campaigns/jhead-ucb-r1/initial_seeds/jpg-1_0" "$N/study_reuse/tree" && grep -q "^seeds: reused from ../../practice/campaigns/src$" "$N/study_reuse/tree"'
contract "study: launch.txt records arm and options"    'grep -q "^arm: afl$" "$N/study_start/tree" && grep -q "^options: --afl$" "$N/study_start/tree"'
contract "study: --dry shows the plan without a server" 'grep -q "would launch seeds/Qwen3.8-27B-FP8-jhead" "$N/study_dry_noserver/out" && grep -q "^note: no Qwen3.8-27B-FP8 server is running" "$N/study_dry_noserver/out"'
contract "study 02: all 75 campaigns submit cleanly"    '[ "$(grep -c "submitted Slurm job" "$N/study_02_all/out")" = 75 ] && ! grep -q "^fuzz:\|study:" "$N/study_02_all/out" "$N/study_02_all/err"'
contract "study 02: each fuzzes 6 h with its args"      '[ "$(grep -c "exec afl-fuzz .*-V 21600 .*/targets/[a-z0-9_.-]*.afl" "$N/study_02_all/tree")" = 75 ] && grep -q "/targets/gdk-pixbuf-pixdata.afl @@ /dev/null" "$N/study_02_all/tree" && grep -q "/targets/imginfo.afl -f @@" "$N/study_02_all/tree"'
# which server each model's campaigns check in their job.sbatch: "<count> <model folder> <url>"
servers_of() { awk '/^=== repo\/experiments\/02-model-sweep\/campaigns\/.*\/job.sbatch/ { split($2, p, "/"); m = p[5] }
  /^curl .*models/ { match($0, /http:\/\/gpu02[0-9]:[0-9]+/); print m, substr($0, RSTART, RLENGTH) }' "$1" | sort | uniq -c | awk '{ print $1, $2, $3 }'; }
contract "study 02: each model uses its own server"     '[ "$(servers_of "$N/study_02_all/tree" | xargs)" = "15 DeepSeek-Coder-V2-Lite-Instruct http://gpu023:28003 15 Mistral-Small-3.1-24B-Instruct-2503 http://gpu024:28004 15 phi-4 http://gpu021:28001 15 Qwen3.8-27B-FP8 http://gpu020:28000 15 starcoder2-15b-instruct-v0.1 http://gpu022:28002" ]'
contract "study: bad settings are refused"              '[ "$(cat "$N/study_badconf/rc")" = 1 ] && grep -q "unknown setting .colour." "$N/study_badconf/err"'
# quantumcore: llm start qc-*, and runs find a server on its account
contract "qc-h100: gpupriority H100 on priority-quantumcore" 'grep -q "^sbatch --parsable --account priority-quantumcore --gres gpu:h100:1 .*model=phi-4" "$N/llm_start_qc_h100/calls" && grep -q "^note: priority-quantumcore is the quantumcore group" "$N/llm_start_qc_h100/out"'
contract "qc-a40: the A40 on priority-quantumcore (fp8 note)" 'grep -q "^sbatch --parsable --account priority-quantumcore --time 120 " "$N/llm_start_qc_a40/calls" && grep -q "served in fp8" "$N/llm_start_qc_a40/out"'
contract "qc-*: refused without the account"            '[ "$(cat "$N/llm_start_qc_notmember/rc")" = 1 ] && grep -q "qc-h100 needs the Slurm account priority-quantumcore" "$N/llm_start_qc_notmember/err" && ! grep -q "^sbatch" "$N/llm_start_qc_notmember/calls"'
contract "a quantumcore server counts as the model's"   '[ "$(cat "$N/llm_start_qc_up/rc")" = 1 ] && grep -q "^ready: Qwen3.8-27B-FP8-nothink on gpu027$" "$N/llm_status_qc/out"'
contract "runs use a server on quantumcore"             'grep -qF "OPENAI_BASE_URL=http://gpu027:28000/v1" "$N/run_qc_server/gen/seeded/job.sbatch"'
# scripts/study: --servers, --background, --wait, results
contract "study 02 --servers --dry: 5 servers, 30 h"    '[ "$(grep -c "^  would start the .* server (a40, 30 h)$" "$N/study_02_servers_dry/out")" = 5 ] && [ "$(grep -c "would launch" "$N/study_02_servers_dry/out")" = 20 ] && ! grep -q "^sbatch" "$N/study_02_servers_dry/calls"'
contract "study --servers starts the missing server"    '[ "$(grep -c "^sbatch .*llm-serve.sbatch" "$N/study_servers/calls")" = 1 ] && grep -q "server is starting" "$N/study_servers/out" && grep -qx "Qwen3.8-27B-FP8 950001" "$N/study_servers/tree" && [ "$(grep -c "submitted Slurm job" "$N/study_servers/out")" = 2 ]'
contract "study --servers uses a ready server"          '! grep -q "llm-serve.sbatch" "$N/study_servers_ready/calls" && grep -q "seeds/Qwen3.8-27B-FP8-jhead: submitted Slurm job" "$N/study_servers_ready/out"'
contract "study --gpu qc-h100 starts it on quantumcore" 'grep -q "^sbatch --parsable --account priority-quantumcore --gres gpu:h100:1 --time 1500 .*model=phi-4" "$N/study_servers_qc/calls"'
contract "study: a server that can't start is reported" '[ "$(cat "$N/study_servers_noacct/rc")" = 1 ] && grep -q "the phi-4 server didn.t start (above); trying again" "$N/study_servers_noacct/out" && ! grep -q "^sbatch" "$N/study_servers_noacct/calls"'
contract "study: gives up on a model after 3 failures"   '[ "$(cat "$N/study_servers_retry/rc")" = 1 ] && [ "$(grep -c "llm-serve.sbatch" "$N/study_servers_retry/calls")" = 3 ] && grep -q "giving up: its server failed 3 times in a row" "$N/study_servers_retry/out" && grep -q "3 wait on a server the study gave up on" "$N/study_servers_retry/err"'
contract "study: bad --gpu refused"                      '[ "$(cat "$N/study_badgpu/rc")" = 1 ] && grep -q "gpu must be a40, h100, qc-a40 or qc-h100" "$N/study_badgpu/err"'
contract "study --background submits the driver"        'grep "^sbatch" "$N/study_background/calls" | grep -q -- "--account $G --partition fairshare --cpus-per-task 1 --mem 2G --time 7-00:00:00 --job-name study-03-test .*study.*start.*03-test.*--servers.*--wait" && [ "$(grep -c "^sbatch" "$N/study_background/calls")" = 1 ]'
contract "study: --background --dry refused"             '[ "$(cat "$N/study_background_dry/rc")" = 1 ] && ! grep -q "^sbatch" "$N/study_background_dry/calls"'
contract "study: no start while the driver runs"         '[ "$(cat "$N/study_driver_running/rc")" = 1 ] && grep -q "driver of 03-test is running (Slurm job 948500)" "$N/study_driver_running/err" && ! grep -q "^sbatch" "$N/study_driver_running/calls" && [ "$(cat "$N/study_driver_dry/rc")" = 0 ]'
contract "study status shows the driver"                 'grep -q "^driver: Slurm job 948500 is running" "$N/study_driver_status/out"'
contract "study --wait: stops the done model's server"  'grep -q "^scancel 948000$" "$N/study_wait/calls" && grep -q "jhead-afl-r1: submitted Slurm job" "$N/study_wait/out"'
contract "study --wait: writes results when done"       'grep -q "wrote results/g2f-r1.csv (1 campaigns of arm g2f)" "$N/study_wait/out" && grep -q "^=== repo/experiments/07-wait/results/campaigns.csv" "$N/study_wait/tree" && grep -q "^07-wait,jhead-g2f-r1,g2f,jhead,1,done,300,1," "$N/study_wait/tree" && grep -q "^all 2 campaigns finished" "$N/study_wait/out"'
contract "study --wait without a server stops"          '[ "$(cat "$N/study_wait_noserver/rc")" = 1 ] && grep -q "a model server isn.t running" "$N/study_wait_noserver/err"'
contract "study: STUDY_MAX_PASSES ends --wait"           'grep -q "^stopping after 2 checks" "$N/study_wait_limit/out" && [ "$(cat "$N/study_wait_limit/rc")" = 0 ]'
contract "study results: finished arms + campaigns.csv" 'grep -q "^=== repo/experiments/07-wait/results/g2f-r1.csv" "$N/study_results/tree" && ! grep -q "results/afl-r1.csv" "$N/study_results/tree" && grep -q "wrote results/campaigns.csv (2 campaigns)" "$N/study_results/out"'
contract "study results: --only target= leaves them"    '! grep -q "results/.*csv" "$N/study_results_part/tree" && grep -q "campaigns.csv left alone" "$N/study_results_part/out"'
contract "study: a server about to end isn't used"      'grep -q "the Qwen3.8-27B-FP8 server (tester.s, job 948000 on gpu027) has 1 h left, and this campaign may run 6 h" "$N/study_short/out" && [ "$(grep -c "submitted Slurm job" "$N/study_short/out")" = 2 ]'
contract "study: launch.txt records server + settings" 'grep -q "^server: Qwen3.8-27B-FP8: tester.s, job 948000 on gpu027, 36 h left at launch$" "$N/study_start/tree" && grep -q "^settings: G2F_SEEDGEN_MIN=300$" "$N/study_start/tree" && grep -q "^server: none (--afl)$" "$N/study_start/tree"'
contract "study: ending early stops its idle servers"  'grep -q "ending early: stopping the Qwen3.8-27B-FP8 server (job 948000)" "$N/study_trap/out" && grep -q "^scancel 948000$" "$N/study_trap/calls" && ! grep -q "^scancel" "$N/study_wait_limit/calls"'
contract "study --dry: checks the GPU's account"        'grep -q "note: you.re not in the Slurm account priority-quantumcore" "$N/study_dry_noacct/out" && ! grep -q "^sbatch" "$N/study_dry_noacct/calls"'
contract "study: a failed squeue isn't \"no jobs\""      '[ "$(cat "$N/study_sqfail_status/rc")" = 1 ] && grep -q "squeue failed" "$N/study_sqfail_status/err" && [ "$(grep -c "squeue failed: skipping this check" "$N/study_sqfail_wait/out")" = 2 ] && ! grep -q "^sbatch" "$N/study_sqfail_wait/calls" && ! grep -q "results/" "$N/study_sqfail_wait/tree"'
contract "study results: rewrites only what changed"   'grep -q "results/g2f-r1.csv is up to date" "$N/study_results_twice/out" && [ "$(grep -c "wrote results/g2f-r1.csv" "$N/study_results_twice/out")" = 1 ]'
contract "study: another study's driver doesn't block" '[ "$(grep -c "submitted Slurm job" "$N/study_other_driver/out")" = 2 ]'
contract "study: shell settings can't change campaigns" 'grep -q -- "--cpus-per-task 2 --mem 8G" "$N/study_env/calls" && ! grep -q -- "--cpus-per-task 8" "$N/study_env/calls" && grep -q "G2F_UCB_EXPLORATION=1.0" "$N/study_env/tree"'
contract "study: a | line continues targets"           'grep -q "^mp42aac-a-r1 " "$N/study_cont/out" && ! grep -q "|" "$N/study_cont/out"'
contract "study status shows the study's servers"       'grep -q "^server: Qwen3.8-27B-FP8, Slurm job 948000 (RUNNING), started by this study" "$N/study_status_servers/out"'
contract "shell starts while the server loads"        'grep -q "^note: .*still loading" "$N/shell_loading/out" && grep -q "^srun" "$N/shell_loading/calls"'

# Tab completion (current version): load what `completion` prints into a shell, then "press Tab" after the words
setup_work "$T/fuzz.new"; scenario base
tab() {   # tab <word> ...: what Tab offers for the last word ("" = Tab after a space)
  env -i PATH="$T/bin:/usr/bin:/bin" HOME="$W/home" USER=tester bash -c \
    'eval "$(bash "$1" completion)"; shift; COMP_WORDS=("$@"); COMP_CWORD=$(($# - 1)); _g2f_fuzz; echo "${COMPREPLY[*]}"' \
    _ "$W/repo/scripts/fuzz" "$@"
}
contract "Tab: fuzz <Tab> lists the commands"          '[[ " $(tab fuzz "") " == *" run "*" llm "*" completion "* ]]'
contract "Tab: fuzz run <Tab> lists campaigns"         '[[ " $(tab fuzz run "") " == *" seeded "*" src "* ]]'
contract "Tab: --model before the command is skipped"  '[[ " $(tab fuzz --model phi-4 run "") " == *" seeded "* ]]'
contract "Tab: fuzz run <c> 900 --<Tab> = options"     '[ "$(tab fuzz run seeded 900 --)" = "--test --afl --model --scheduler" ]'
contract "Tab: fuzz llm <Tab>"                         '[ "$(tab fuzz llm "")" = "start stop status host --model" ]'
contract "Tab: fuzz llm start 2 <Tab> = GPUs"          '[ "$(tab fuzz llm start 2 "")" = "a40 h100 qc-a40 qc-h100 --model" ]'
contract "Tab: --model <Tab> lists shared models"      '[ "$(tab fuzz new x --model phi)" = "phi-4" ]'
contract "Tab: --scheduler <Tab> = ucb random"         '[ "$(tab fuzz run seeded --scheduler "")" = "ucb random" ]'
contract "Tab: --scheduler <s> before the name"        '[[ " $(tab fuzz run --scheduler ucb "") " == *" seeded "* ]]'
contract "Tab: scripts/fuzz works too"                 '[ "$(tab scripts/fuzz wat)" = "watch" ]'

# scripts/enable-completion (in the fake home): adds its line to ~/.bashrc once; sourced, turns it on right away
cp "$REPO/scripts/enable-completion" "$W/repo/scripts/"
en() { env -i PATH="$T/bin:/usr/bin:/bin" HOME="$W/home" USER=tester bash "$@"; }
en "$W/repo/scripts/enable-completion" > /dev/null; en "$W/repo/scripts/enable-completion" > "$T/enable2.out"
contract "enable-completion adds its line once"          '[ "$(grep -c "completion)\"$" "$W/home/.bashrc")" = 1 ] && grep -q "already in" "$T/enable2.out"'
contract "sourced, it turns on alias + completion"      '[[ "$(en -ic "source $W/repo/scripts/enable-completion >/dev/null; type -t fuzz; complete -p fuzz" 2>/dev/null)" == alias*"complete -F _g2f_fuzz fuzz"* ]]'
contract "a new shell gets them from ~/.bashrc"          '[[ "$(en -ic "type -t fuzz" 2>/dev/null)" == alias ]]'

[ "$fails" = 0 ] && echo "PASS ($ncases cases)" || { echo "FAILED ($fails problems)"; exit 1; }
