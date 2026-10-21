#!/usr/bin/env python3
"""Judge test for tasks/bandit-budget.md. Run from the workdir root (holding experiments/ and g2fuzz/)."""
import csv, json, os, subprocess, sys, tempfile
failures = []
def check(c, m):
    print(("ok    " if c else "FAIL  ") + m)
    if not c: failures.append(m)
root = tempfile.mkdtemp(prefix="bb_")
camps = os.path.join(root, "bandit")
def mk(name, finished=True, outname="xml_fuzzer_output"):
    d = os.path.join(camps, name); o = os.path.join(d, outname, "default")
    for sub in ("queue", "generators", "mutation_log"): os.makedirs(os.path.join(o, sub))
    open(os.path.join(o, "fuzzer_stats"), "w").write("execs_done : 1\n")   # exists while running too
    open(os.path.join(d, "slurm.jobid"), "w").write("4242\n")
    open(os.path.join(d, "slurm-4242.out"), "w").write("start\n" + ("job.sbatch: output copied back (cp exit 0)\n" if finished else ""))
    open(os.path.join(d, "fuzz.log"), "w").write("")
    for f in ("gen_seeds_energy_log", "mutate_log"): open(os.path.join(o, f), "w").write("")
    return d, o
d, o = mk("bandit-xml-bandit-r1")
open(os.path.join(d, "fuzz.log"), "w").write("a\n==== Gen-M start ====\nb\n==== Gen-M start ====\n==== Gen-M start ====\n")
open(os.path.join(o, "gen_seeds_energy_log"), "w").write("\n\ncnt:2\ncost_time:10000\n\n\ncnt:0\ncost_time:25000\n\n\ncnt:1\ncost_time:31000\n")
json.dump({"mutations": [{"mutator": "feature", "child": "xml-6.py", "time": 1}, {"mutator": "feature", "child": None, "time": 2},
                         {"mutator": "structure", "child": "xml-7.py", "time": 3}]}, open(os.path.join(o, "mutation_log", "scheduler.json"), "w"))
open(os.path.join(o, "mutate_log"), "w").write("model: m\n/x/out/generators/xml-1.py\nmutators: [..]\n/x/out/generators/xml-3.py\nnoise generators/xml-9.pyc\n/x/out/generators/xml-4.py\n")
for i in range(1, 8): open(os.path.join(o, "generators", "xml-%d.py" % i), "w").write("pass\n")
q = ["id:%06d,time:0,execs:0,orig:xml-%d_1.xml" % (i, i + 1) for i in range(7)]
q += ["id:000007,src:000000,op:havoc", "id:000008,src:000007,op:havoc", "id:000009,src:000000,op:havoc",
      "id:000010,src:000003,op:havoc", "id:000011,src:000010,op:havoc", "id:000012,src:000001,op:havoc",
      "id:000013,src:000005,op:havoc", "id:000014,src:000006,op:havoc"]
for n in q: open(os.path.join(o, "queue", n), "w").write("x")
mk("bandit-xml-random-r1", finished=False)
d2, o2 = mk("bandit-tiff-random-r1", outname="tiff_read_rgba_fuzzer_output")   # finished, target binary folder name
os.makedirs(os.path.join(camps, "pilot-something"))
out = os.path.join(root, "bb.csv")
p = subprocess.run([sys.executable, "experiments/analysis/bandit-budget", "--campaigns", camps, "--out", out], capture_output=True, text=True)
check(p.returncode == 0, "runs (rc %d: %s)" % (p.returncode, p.stderr[-300:]))
check("bandit-xml-random-r1" in p.stderr, "unfinished campaign reported on stderr")
rows = list(csv.DictReader(open(out))) if os.path.exists(out) else []
check([r["campaign"] for r in rows] == ["bandit-tiff-random-r1", "bandit-xml-bandit-r1"], "rows for finished campaigns only, sorted (got %s)" % [r["campaign"] for r in rows])
check("unfinished: bandit-xml-random-r1" in p.stderr, "running campaign (fuzzer_stats but no copy-back line) reported as unfinished")
r = next((x for x in rows if x["campaign"] == "bandit-xml-bandit-r1"), {})
check(r.get("target") == "xml" and r.get("arm") == "bandit" and r.get("rep") == "1", "target/arm/rep parsed")
check(r.get("steps") == "3", "steps = 3 Gen-M starts (got %s)" % r.get("steps"))
check(r.get("step_seconds_median") == "10", "median step seconds from cumulative cost_time = median(10,15,6) = 10 (got %s)" % r.get("step_seconds_median"))
check(r.get("mutations") == "3" and r.get("failed") == "1", "mutations 3, failed 1 (got %s %s)" % (r.get("mutations"), r.get("failed")))
check(r.get("picks") == "3", "picks = 3 generator paths in mutate_log (got %s)" % r.get("picks"))
check(r.get("generators_end") == "7", "generators_end 7 (got %s)" % r.get("generators_end"))
# credit finds: xml-1 3, xml-4 2, xml-2 1, xml-6 1, xml-7 1, xml-3 0, xml-5 0 -> top5 {1,4,2,6,7}; picks 1,3,4 -> 2/3
check(r.get("top5_share") == "%.6g" % (2 / 3), "top5_share = 2/3 (got %s)" % r.get("top5_share"))
# c_k: 7 - successes at/after k: k0 -> 7-2=5, k1 -> 7-1=6, k2 -> 7-1=6 -> mean(1, 5/6, 5/6)
check(r.get("top5_random_expected") == "%.6g" % ((1 + 5 / 6 + 5 / 6) / 3), "top5_random_expected = 0.888889 (got %s)" % r.get("top5_random_expected"))
src = open("experiments/analysis/bandit-budget").read()
check("scheduler" in src and "credit" in src, "uses scheduler.credit")
print("\n%d failure(s)" % len(failures)); sys.exit(1 if failures else 0)
