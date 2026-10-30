#!/usr/bin/env bash
# test_fuzz_cli.sh: regression test for scripts/fuzz. Runs every command, flag and error path (~80 cases) against
# fake Slurm commands, so nothing is ever submitted or cancelled, and compares everything the script does between
# two versions of it: exit code, output, the Slurm commands it calls, and the files it writes (with permissions).
#
# Usage (on Tempest, from the repo root; the --model cases need the real students/shared-models):
#   scripts/tests/test_fuzz_cli.sh [OLD]   OLD: the version to compare with: a file, or a git revision (default HEAD)
#   KEEP=1 scripts/tests/test_fuzz_cli.sh  keep the temp folder (its path is printed) to look at the outputs
#
# Passes when the current scripts/fuzz behaves exactly like OLD, and the contracts other scripts rely on hold:
# run.sh has "-V <secs>" (read by 01-baseline-replication/analysis), job.sbatch has "OPENAI_BASE_URL=" (read by the
# launchers), `run` prints "submitted Slurm job" last, `llm status` prints "ready:" (read by 02-model-sweep's sweep),
# and every generated run.sh/job.sbatch passes `bash -n`. Plus fixed bugs that must stay fixed (see the last checks).
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
# squeue: rows of $SCEN/jobs are id|user|name|state|comment|node|account|command; supports -h -j -n -t -u -A -o
cat > "$T/bin/squeue" <<'EOF'
#!/usr/bin/env python3
import os, re, sys
with open(os.environ["STUB_LOG"], "a") as log:
    log.write("squeue " + " ".join(repr(a) for a in sys.argv[1:]) + "\n")
keys = "iujTkNAo"
heads = {"i": "JOBID", "u": "USER", "j": "NAME", "T": "STATE", "k": "COMMENT", "N": "NODELIST", "A": "ACCOUNT",
         "o": "COMMAND", "M": "TIME", "L": "TIME_LEFT", "e": "END_TIME"}
rows = []
if os.path.exists(os.environ["SCEN"] + "/jobs"):
    for line in open(os.environ["SCEN"] + "/jobs"):
        if line.strip():
            f = dict(zip(keys, line.rstrip("\n").split("|")))
            f.update(M="1:00:00", L="2:00:00", e="2027-01-15T10:00:00")
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
  # the sweep launcher, for the end-to-end cases
  mkdir -p "$W/repo/experiments/02-model-sweep/launch"
  cp "$REPO/experiments/02-model-sweep/launch/sweep" "$REPO/experiments/02-model-sweep/launch/targets.txt" \
    "$W/repo/experiments/02-model-sweep/launch/"
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
    *) echo "unknown scenario $1" >&2; exit 2 ;;
  esac
}

# Everything a case left behind: the file tree with modes, then every small file's contents
snapshot() {
  (cd "$W" && find . -path ./scen -prune -o -printf '%y %m %P\n' | sort)
  (cd "$W" && find repo/experiments home -type f -size -64k | sort | while read -r f; do echo "=== $f"; cat -v "$f"; done)
}

# run_case <name> <scenario> [VAR=value ...] -- <scripts/fuzz args ...>   (args starting with @sweep run the launcher)
run_case() {
  local name=$1 scen=$2 o; shift 2
  local -a vars=() cmd   # (bash 4.4+: empty arrays are fine under set -u)
  while [ "$1" != -- ]; do vars+=("$1"); shift; done; shift
  o="$OUTDIR/$name"; mkdir -p "$o"
  setup_work "$SCRIPT"; scenario "$scen"
  if [ "${1:-}" = @sweep ]; then shift; cmd=("$W/repo/experiments/02-model-sweep/launch/sweep" "$@")
  else cmd=(bash "$W/repo/scripts/fuzz" "$@"); fi
  ( set +e; cd "$W"
    env -i PATH="$T/bin:/usr/bin:/bin" HOME="$W/home" USER=tester LANG=C LC_ALL=C TZ=UTC SCEN="$W/scen" \
      STUB_LOG="$o/calls" "${vars[@]}" "${cmd[@]}" > "$o/out" 2> "$o/err" < /dev/null
    echo $? > "$o/rc" )
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
  # the 02-model-sweep launcher, end to end
  run_case sweep_dry solo DRY=1 -- @sweep start phi-4 600
  run_case sweep_start two MAX_SEEDGEN=2 -- @sweep start phi-4 600
  run_case sweep_noserver none -- @sweep start phi-4 600
  run_case sweep_status two -- @sweep status phi-4
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
contract "sweep launched 2 campaigns"                 '[ "$(grep -c "submitted Slurm job" "$N/sweep_start/out")" = 2 ]'
# fixed 2026-10-29 (+ default names with the NetID, a hint for a missing name): list stopped at a campaign without output; run exited silently without model_setting.json;
# run submitted jobs while the server was still loading (they then failed on the node)
contract "list shows all 9 campaigns"                 '[ "$(cat "$N/list/rc")" = 0 ] && [ "$(wc -l < "$N/list/out")" = 10 ]'
contract "run works without model_setting.json"      '[[ "$(tail -1 "$N/run_nosetting/out")" == "submitted Slurm job "* ]]'
contract "run refuses while the server loads"         '[ "$(cat "$N/run_loading/rc")" = 1 ] && grep -q "still loading" "$N/run_loading/err" && ! grep -q "^sbatch" "$N/run_loading/calls"'
contract "default names start with the NetID"        'grep -q "^created experiments/practice/campaigns/tester-jhead-" "$N/new_default/out"'
contract "a missing name points to your latest"      'grep -q "missing campaign name; your latest is seeded " "$N/watch_noname/err"'
# the generator scheduler: ucb by default, --scheduler random for upstream, shown by status, ucb in the sweep
contract "run defaults to ucb"                       'grep -q "^generator scheduler: ucb (exploration 1.0)$" "$N/run_seedgen/out" && grep -q "G2F_GENERATOR_SCHEDULER=ucb" "$N/run_seedgen/gen/fresh/job.sbatch"'
contract "--scheduler random picks upstream"          'grep -q "^generator scheduler: random" "$N/run_sched_random/out" && grep -q "G2F_GENERATOR_SCHEDULER=random" "$N/run_sched_random/gen/seeded/job.sbatch"'
contract "--scheduler beats G2F_GENERATOR_SCHEDULER"  'grep -q "G2F_GENERATOR_SCHEDULER=ucb" "$N/run_sched_override/gen/seeded/job.sbatch"'
contract "--afl jobs carry no scheduler"              '! grep -q G2F_GENERATOR_SCHEDULER "$N/run_afl_stock/gen/fresh/job.sbatch"'
contract "status shows the scheduler"                 'grep -q "^scheduler    ucb (exploration 1.0)$" "$N/status_done/out"'
contract "the sweep records ucb"                      'grep -q "^scheduler: ucb$" "$N/sweep_start/tree"'
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
contract "Tab: fuzz llm start 2 <Tab> = GPUs"          '[ "$(tab fuzz llm start 2 "")" = "a40 h100 --model" ]'
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
