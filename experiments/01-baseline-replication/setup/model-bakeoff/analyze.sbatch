#!/bin/bash
# Bake-off analysis: per campaign LLM calls (ok/error, median and max latency, timeouts >= 290 s), generators,
# generated seeds, union of edges reached by the generated seeds alone and by all initial seeds (afl-showmap on the
# paper .afl target, AFL_MAP_SIZE), edges_found after 300 s. Output: bakeoff.tsv next to this file.
# Run from this folder: sbatch analyze.sbatch   (first run 2026-10-23, job 868548, from ~/scratch/bake; moved here)
#SBATCH --job-name=g2f-bake-analyze
#SBATCH --partition=fairshare
#SBATCH --account=group-csci-591-automated-vulnerability-discovery
#SBATCH --cpus-per-task=4
#SBATCH --mem=8G
#SBATCH --time=2:00:00
#SBATCH --output=analyze-%j.out
S=/home/group/csci-591-automated-vulnerability-discovery/students; TR=$S/g2f-targets/paper
H=$S/WORKING-BETTERG2FUZZ/experiments/01-baseline-replication/setup/model-bakeoff; E=$H/campaigns
SIF=$S/WORKING-BETTERG2FUZZ/g2fuzz.sif; O=$H/bakeoff.tsv; W=$(mktemp -d); trap 'rm -rf $W' EXIT
printf "campaign\tmodel\ttarget\tcalls\tok\terr\tmed_s\tmax_s\tge290s\tgenerators\tgen_seeds\tgen_edges\tall_seed_edges\tedges_300s\n" > $O
cov() { # cov TARGET DIR -> number of distinct edges over all files in DIR
  local t=$1 d=$2 args; args=$(cat $TR/$t.args); local all=$(mktemp -p $W); : > $all
  for f in "$d"/*; do [ -f "$f" ] || continue
    apptainer exec --cleanenv -B /home/group -B $W -B $TR:/targets:ro $SIF bash -c "cd /tmp; AFL_MAP_SIZE=2621440 afl-showmap -q -o $all.m -t 10000 -- /targets/$t.afl ${args//@@/$f} >/dev/null 2>&1; cut -d: -f1 $all.m 2>/dev/null" >> $all
  done; sort -u $all | grep -c .; rm -f $all $all.m; }
for c in $E/bake-*; do n=$(basename $c); IFS=- read -r _ m t r <<< "$n"
  out=$c/${t}_output/default
  calls=$(wc -l < $c/llm_calls.jsonl 2>/dev/null || echo 0)
  read ok err med mx slow <<< $(python3 - $c/llm_calls.jsonl <<"PY" 2>/dev/null || echo "0 0 0 0 0"
import json,sys,statistics
rs=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
ok=[r for r in rs if r.get("status")=="ok"]; s=[r["secs"] for r in rs if "secs" in r]
print(len(ok), len(rs)-len(ok), round(statistics.median(s),1) if s else 0, round(max(s),1) if s else 0, sum(1 for x in s if x>=290))
PY
)
  gens=$(ls $out/generators 2>/dev/null | wc -l); gseeds=$(ls $out/gen_seeds 2>/dev/null | wc -l)
  ge=$(cov $t $out/gen_seeds); ae=$(cov $t $c/initial_seeds)
  e300=$(awk -F: "/edges_found/ {gsub(/ /,\"\",\$2); print \$2}" $out/fuzzer_stats 2>/dev/null)
  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" $n $m $t $calls $ok $err $med $mx $slow $gens $gseeds $ge $ae "${e300:-NA}" >> $O
done
column -t $O
