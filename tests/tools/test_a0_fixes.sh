#!/bin/bash
# judge test for the two small A0 fixes; run from the workdir root (copy of the project files; no Tempest needed)
fail=0; ck(){ if eval "$2"; then echo "ok    $1"; else echo "FAIL  $1"; fail=$((fail+1)); fi; }
T=$(mktemp -d); mkdir -p $T/cov
for n in xml-baseline-r1:2000 xml-baseline-r2:2003 xml-codernext-r1:4000 xml-codernext-r2:4001 xml-codernext-r3:4005; do
  c=${n%%:*}; v=${n#*:}; printf '{"seeds": {"files": 1, "total_edges": 10, "new_edges": 0, "per_generator": {}}, "queue": {"total_edges": %s}}' $v > $T/cov/$c.json; done
python3 experiments/analysis/cov-summary --cov $T/cov --out $T/out.csv > $T/print.txt 2>&1
ck "cov-summary even-n median printed as 2001.5" "grep -qE '^xml baseline 2 [0-9.]+ [0-9.]+ 2001.5' $T/print.txt"
ck "cov-summary odd-n median printed as 4001" "grep -qE '^xml codernext 3 [0-9.]+ [0-9.]+ 4001$' $T/print.txt"
ck "cov-summary CSV unchanged format" "head -1 $T/out.csv | grep -q '^campaign,target,model,rep,seed_files,seed_edges,new_edges,generators,queue_edges' && grep -q '^xml-baseline-r2,xml,baseline,2,1,10,0,0,2003' $T/out.csv"
grep -n 'continue' experiments/analysis/lib/crash_triage.py | head -3 > /dev/null
ck "crash_triage reports skipped names" "grep -q 'skipped' experiments/analysis/lib/crash_triage.py && grep -q 'unrecognized campaign name' experiments/analysis/lib/crash_triage.py && grep -q 'sys.stderr' experiments/analysis/lib/crash_triage.py"
ck "crash_triage exits 1 for an explicit unrecognized name" "grep -qE 'sys.exit\(1\)|exit\(1\)' experiments/analysis/lib/crash_triage.py"
echo; echo "$fail failure(s)"; exit $fail
