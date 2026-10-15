#!/bin/bash
# Coverage measured outside the fuzzer, for every finished campaign: experiments/analysis/lib/seed_cov.py replays each file
# once in a fresh process (afl-showmap folder mode depends on file order).
#   initial_seeds/ (with --stock): what the generators' seeds reach before any fuzzing, and how much of
#     it the stock seeds don't (the generator-quality benchmark, per model)
#   the final queue: total coverage, independent of AFL++'s own edge counter
# Writes results/cov/<campaign>.json ({"seeds": ..., "queue": ...}); campaigns already done are skipped,
# and so is results/campaigns/archive/. Targets and stock seeds come from the image (/targets).
# Summary: experiments/analysis/cov-summary. Submit from the project root:  sbatch experiments/runners/cov-replay.sbatch
#SBATCH --job-name=g2f-cov-replay
#SBATCH --partition=fairshare
#SBATCH --account=group-csci-591-automated-vulnerability-discovery
#SBATCH --cpus-per-task=32
#SBATCH --mem=32G
#SBATCH --time=08:00:00
#SBATCH --output=results/logs/cov-replay-%j.out
X=/home/group/csci-591-automated-vulnerability-discovery/students/BETTER-G2FUZZ-exp
cd "$X" || exit 1
mkdir -p results/cov
# campaign -> target binary (in the image; its stock seeds are /targets/seeds/<target>)
one() {
  local d=$1 n t s; n=$(basename "$d")
  [ -s "results/cov/$n.json" ] && return 0
  [ -f "$d"/*_output/default/fuzzer_stats ] || return 0   # not finished
  squeue -h -u "$USER" -n "g2f-$n" 2>/dev/null | grep -q . && return 0   # still running
  case "$n" in
    lineup*|bandit-jhead-*) t=jhead ;;
    tiff*|bandit-tiff-*) t=tiff_read_rgba_fuzzer ;;
    png*|bandit-png-*) t=libpng_read_fuzzer ;;
    xml*|bandit-xml-*) t=xml_fuzzer ;;
    wad*|bandit-wad-*) t=doom_wad ;;
    *) return 0 ;;
  esac
  local q; q=$(ls -d "$d"/*_output/default/queue)
  apptainer exec -B /home/group "$X/g2fuzz.sif" bash -c "
    python3 experiments/analysis/lib/seed_cov.py /targets/$t.afl $d/initial_seeds --stock /targets/seeds/$t > /tmp/cs-\$\$.json &&
    python3 experiments/analysis/lib/seed_cov.py /targets/$t.afl $q > /tmp/cq-\$\$.json &&
    python3 -c 'import json,sys; json.dump({\"seeds\": json.load(open(sys.argv[1])), \"queue\": json.load(open(sys.argv[2]))}, open(sys.argv[3], \"w\"))' \
      /tmp/cs-\$\$.json /tmp/cq-\$\$.json results/cov/$n.json; rm -f /tmp/cs-\$\$.json /tmp/cq-\$\$.json" \
    && echo "done $n" || echo "FAILED $n"
}
export -f one; export X
ls -d results/campaigns/*/*-r[0-9]* | grep -v '^results/campaigns/archive/' | xargs -P 32 -I{} bash -c 'one {}'
echo "all done $(date)"
