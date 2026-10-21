#!/usr/bin/env python3
"""Judge test for tasks/bandit-sim.md. Run from the workdir root (holding experiments/ and g2fuzz/)."""
import csv, os, subprocess, sys, tempfile
failures = []
def check(c, m):
    print(("ok    " if c else "FAIL  ") + m)
    if not c: failures.append(m)
def pool(name, spec):
    """spec: {gen: [seed_productive_bools]} -> campaign/<t>_output/default with a queue."""
    root = tempfile.mkdtemp(); o = os.path.join(root, name, "xml_fuzzer_output", "default"); q = os.path.join(o, "queue"); os.makedirs(q)
    i = 0
    for g, seeds in spec.items():
        for k, prod in enumerate(seeds):
            sid = i; open(os.path.join(q, "id:%06d,time:0,execs:0,orig:%s_%d.xml" % (sid, g, k + 1)), "w").write("x"); i += 1
            if prod:
                open(os.path.join(q, "id:%06d,src:%06d,op:havoc" % (i, sid)), "w").write("x"); i += 1
    return o
TOOL = os.path.abspath("experiments/analysis/lib/bandit_sim.py")
def run(pools, budgets, reps=3000, seed=591):
    out = os.path.join(tempfile.mkdtemp(), "s.csv")
    args = [sys.executable, TOOL]
    for p in pools: args += ["--pool", p]
    args += ["--budgets"] + [str(b) for b in budgets] + ["--reps", str(reps), "--seed", str(seed), "--out", out]
    p = subprocess.run(args, capture_output=True, text=True)
    return p, (list(csv.DictReader(open(out))) if os.path.exists(out) else []), (open(out).read() if os.path.exists(out) else "")
# arms: xml-1 p=1 (1/1), xml-2 p=0 (0/2), xml-3 p=0.5 (1/2), xml-4 p=0 (0/1)
P = pool("pool-a", {"xml-1": [True], "xml-2": [False, False], "xml-3": [True, False], "xml-4": [False]})
p, rows, raw = run([P], [5, 200])
check(p.returncode == 0, "runs (%s)" % p.stderr[-300:])
get = lambda b, pol: next((r for r in rows if r["budget"] == str(b) and r["policy"] == pol), None)
check(len(rows) == 6 and [r["policy"] for r in rows[:3]] == ["random", "thompson", "oracle"], "6 rows, policy order random/thompson/oracle")
check(all(r["pool"] == "pool-a" and r["arms"] == "4" for r in rows), "pool name and 4 arms")
o = get(200, "oracle"); r = get(200, "random"); t = get(200, "thompson")
check(o is not None and o["mean_rate"] == "1" and o["sd_rate"] == "0", "oracle always picks p=1 arm: rate exactly 1, sd 0 (got %s)" % ((o and (o["mean_rate"], o["sd_rate"])),))
check(r is not None and abs(float(r["mean_rate"]) - 0.375) < 0.01, "random rate ~ mean p = 0.375 (got %s)" % (r and r["mean_rate"]))
check(t is not None and 0.8 < float(t["mean_rate"]) < 1.0, "thompson learns at T=200 (0.8 < rate < 1, got %s)" % (t and t["mean_rate"]))
check(r is not None and r["ratio_to_random"] == "1" and abs(float(o["ratio_to_random"]) - 1 / float(r["mean_rate"])) < 1e-3,
      "ratio_to_random relative to random's rate")
t5 = get(5, "thompson"); r5 = get(5, "random")
check(t5 is not None and float(t5["mean_rate"]) < float(t["mean_rate"]), "thompson gains less at T=5 than at T=200")
_, _, raw2 = run([P], [5, 200])
check(raw == raw2 and raw, "deterministic output")
_, _, raw3 = run([P], [5, 200], seed=7)
check(raw3 != raw, "seed changes the random draws")
E = pool("pool-empty", {}); p2, _, _ = run([E], [5])
check(p2.returncode == 2, "pool without arms -> exit 2")
src = open(TOOL).read()
check("credit" in src and "scheduler" in src, "uses scheduler.credit")
Z = pool("pool-zero", {"xml-1": [False], "xml-2": [False, False]})   # every arm p = 0
p3, zrows, _ = run([Z], [5], reps=50)
check(p3.returncode == 0 and zrows and all(r["ratio_to_random"] == "" for r in zrows), "ratio_to_random empty when random's rate is 0 (got %s)" % [r["ratio_to_random"] for r in zrows])

print("\n%d failure(s)" % len(failures)); sys.exit(1 if failures else 0)
