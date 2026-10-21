#!/usr/bin/env python3
"""Judge test for tasks/execs-matched.md. Run from the workdir root (holding experiments/analysis/lib/execs_matched.py)."""
import csv, json, os, subprocess, sys, tempfile
TOOL = os.path.abspath("experiments/analysis/lib/execs_matched.py")
failures = []
def check(c, m):
    print(("ok    " if c else "FAIL  ") + m)
    if not c: failures.append(m)

root = tempfile.mkdtemp(); C = os.path.join(root, "campaigns")
def camp(group, name, execs_done, queue, out="xml_fuzzer_output", stats_fmt="execs_done        : %d\n"):
    d = os.path.join(C, group, name, out, "default"); os.makedirs(os.path.join(d, "queue", ".state", "x"))
    open(os.path.join(d, "fuzzer_stats"), "w").write("start_time        : 1\n" + stats_fmt % execs_done + "execs_per_sec : 5\n")
    for q in queue: open(os.path.join(d, "queue", q), "w").write(q)
    open(os.path.join(d, "queue", ".state", "x", "ignored"), "w").write("no")
    return d
camp("lineup-1h", "xml-baseline-r1", 1000, ["id:000000,time:0,execs:0,orig:a.xml", "id:000001,src:000000,time:5,execs:500,op:havoc",
                                            "id:000002,src:000001,time:9,execs:1000,op:havoc"])
camp("lineup-1h", "xml-codernext-r1", 3000, ["id:000000,time:0,execs:0,orig:a.xml", "id:000001,time:0,execs:999,orig:xml-1_0.xml",
                                             "id:000002,src:000001,time:9,execs:1001,op:havoc", "id:000003,src:000001,time:20,execs:2900,op:quick,+cov"])
camp("lineup-1h", "xml-baseline-r9", 50, ["id:000000,time:0,execs:0,orig:a.xml"])                       # excluded: must not set the cutoff
camp("bandit", "bandit-xml-random-r1", 700, ["id:000000,time:0,execs:0,orig:a.xml", "id:000001,src:000000,time:3,execs:700,op:havoc"],
     stats_fmt="execs_done:%d\n")
camp("bandit", "bandit-xml-bandit-r1", 900, ["id:000000,time:0,execs:0,orig:a.xml", "id:000001,src:000000,time:3,execs:701,op:havoc"])
camp("demo", "demo-baseline-r1", 400, ["id:000000,time:0,execs:0,orig:d.lmp"], out="doom_demo_output")
camp("lineup-jhead", "lineup-baseline-r1", 10, ["id:000000,time:0,execs:0,orig:j.jpg"], out="jhead_output")   # not in stats: ignored

cov = os.path.join(root, "cov.csv")
with open(cov, "w", newline="") as f:
    w = csv.writer(f); w.writerow("campaign,target,model,rep,seed_files,seed_edges,new_edges,generators,queue_edges".split(","))
    for n, q in (("xml-baseline-r1", 30), ("xml-codernext-r1", 70), ("xml-baseline-r9", 5), ("bandit-xml-random-r1", 40),
                 ("bandit-xml-bandit-r1", 41), ("demo-baseline-r1", 9), ("lineup-baseline-r1", 3)):
        w.writerow([n, "t-" + n, "m-" + n, 1, 11, 12, 13, 14, q])
st = os.path.join(root, "stats.csv")
with open(st, "w", newline="") as f:
    w = csv.writer(f); w.writerow(["experiment", "metric", "arm", "reference"])
    w.writerow(["xml", "coverage", "codernext", "baseline"]); w.writerow(["xml", "crash_sites", "codernext", "baseline"])
    w.writerow(["bandit-xml", "coverage", "bandit", "random"]); w.writerow(["demo", "coverage", "x", "baseline"])
    w.writerow(["lineup", "crash_sites", "a", "baseline"])          # not a coverage experiment
ex = os.path.join(root, "ex.csv"); open(ex, "w").write("campaign,reason\nxml-baseline-r9,short\n")
plan = os.path.join(root, "plan.csv")
def run(*a):
    return subprocess.run([sys.executable, TOOL] + list(a), capture_output=True, text=True)

p = run("plan", "--campaigns", C, "--cov", cov, "--stats", st, "--exclude", ex, "--out", plan)
check(p.returncode == 0, "plan runs (%s)" % p.stderr[-300:])
rows = list(csv.DictReader(open(plan))) if os.path.exists(plan) else []
check(rows and list(rows[0].keys()) == "experiment,campaign,arm,target,execs_done,cutoff,queue_files,files_at_cutoff".split(","), "plan columns")
R = {r["campaign"]: r for r in rows}
check(sorted(R) == sorted(["xml-baseline-r1", "xml-codernext-r1", "bandit-xml-random-r1", "bandit-xml-bandit-r1", "demo-baseline-r1"]),
      "plan campaigns: coverage experiments only, exclusions applied (got %s)" % sorted(R))
check([(r["experiment"], r["campaign"]) for r in rows] == sorted((r["experiment"], r["campaign"]) for r in rows), "plan sorted")
def row(n, *vals):
    r = R.get(n, {}); got = tuple(r.get(k) for k in ("experiment", "arm", "target", "execs_done", "cutoff", "queue_files", "files_at_cutoff"))
    check(got == vals, "plan row %s = %s (got %s)" % (n, vals, got))
row("xml-baseline-r1", "xml", "baseline", "xml_fuzzer", "1000", "1000", "3", "3")
row("xml-codernext-r1", "xml", "codernext", "xml_fuzzer", "3000", "1000", "4", "2")
row("bandit-xml-random-r1", "bandit-xml", "random", "xml_fuzzer", "700", "700", "2", "2")
row("bandit-xml-bandit-r1", "bandit-xml", "bandit", "xml_fuzzer", "900", "700", "2", "1")
row("demo-baseline-r1", "demo", "baseline", "doom_demo", "400", "400", "1", "1")

sel = os.path.join(root, "sel")
p = run("select", "--campaigns", C, "xml-codernext-r1", "1000", sel)
check(p.returncode == 0 and p.stdout.strip() == "2", "select prints the link count (%s %s)" % (p.stdout, p.stderr[-200:]))
links = sorted(os.listdir(sel)) if os.path.isdir(sel) else []
check(links == ["id:000000,time:0,execs:0,orig:a.xml", "id:000001,time:0,execs:999,orig:xml-1_0.xml"], "select links exactly execs<=cutoff (got %s)" % links)
check(all(os.path.islink(os.path.join(sel, l)) and open(os.path.join(sel, l)).read() == l for l in links), "links are symlinks to the queue files")
p = run("select", "--campaigns", C, "xml-codernext-r1", "1000", sel)
check(p.returncode == 2, "select into an existing folder -> exit 2")
# relative --campaigns (the default form) from another working directory: links must still resolve
sel2 = os.path.join(root, "sel2")
p = subprocess.run([sys.executable, TOOL, "select", "--campaigns", "campaigns", "xml-baseline-r1", "500", sel2], capture_output=True, text=True, cwd=root)
l2 = sorted(os.listdir(sel2)) if os.path.isdir(sel2) else []
check(p.returncode == 0 and len(l2) == 2 and all(os.path.isfile(os.path.join(sel2, l)) for l in l2),
      "select with a relative --campaigns makes links that resolve (got %s)" % [(l, os.path.isfile(os.path.join(sel2, l))) for l in l2])

rep = os.path.join(root, "rep"); os.makedirs(rep)
for n, e in (("xml-baseline-r1", 30), ("xml-codernext-r1", 55), ("bandit-xml-random-r1", 40), ("bandit-xml-bandit-r1", 33), ("demo-baseline-r1", 9)):
    json.dump({"files": 1, "total_edges": e, "per_file": {}}, open(os.path.join(rep, n + ".json"), "w"))
out = os.path.join(root, "em.csv"); cout = os.path.join(root, "emcov.csv")
p = run("table", "--plan", plan, "--replays", rep, "--cov", cov, "--out", out, "--cov-out", cout)
check(p.returncode == 0, "table runs (%s)" % p.stderr[-300:])
t = list(csv.DictReader(open(out))) if os.path.exists(out) else []
check(t and list(t[0].keys()) == "experiment,campaign,arm,execs_done,cutoff,files_at_cutoff,edges_at_cutoff,queue_edges".split(","), "table columns")
T = {r["campaign"]: r for r in t}
check(T.get("xml-codernext-r1", {}).get("edges_at_cutoff") == "55" and T["xml-codernext-r1"]["queue_edges"] == "70"
      and T["xml-codernext-r1"]["cutoff"] == "1000" and T["xml-codernext-r1"]["files_at_cutoff"] == "2", "table row values")
c = list(csv.DictReader(open(cout))) if os.path.exists(cout) else []
check(c and list(c[0].keys()) == "campaign,target,model,rep,seed_files,seed_edges,new_edges,generators,queue_edges".split(","), "cov-out columns")
check([r["campaign"] for r in c] == [r["campaign"] for r in rows], "cov-out rows in plan order")
C2 = {r["campaign"]: r for r in c}
check(C2.get("bandit-xml-bandit-r1") == {"campaign": "bandit-xml-bandit-r1", "target": "t-bandit-xml-bandit-r1", "model": "m-bandit-xml-bandit-r1",
      "rep": "1", "seed_files": "11", "seed_edges": "12", "new_edges": "13", "generators": "14", "queue_edges": "33"}, "cov-out copies cov columns, queue_edges = edges_at_cutoff")
check("xml" in p.stdout and "1000" in p.stdout, "stdout per experiment")
os.remove(os.path.join(rep, "demo-baseline-r1.json"))
p = run("table", "--plan", plan, "--replays", rep, "--cov", cov, "--out", out + "2", "--cov-out", cout + "2")
check(p.returncode == 2 and "demo-baseline-r1" in p.stderr, "missing replay -> exit 2 naming it")

# errors in plan
camp("lineup-1h", "xml-bad-r1", 100, ["id:000000,time:0,execs:0,orig:a.xml", "README.txt"])
with open(cov, "a", newline="") as f: csv.writer(f).writerow(["xml-bad-r1", "t", "m", 1, 1, 1, 1, 1, 1])
p = run("plan", "--campaigns", C, "--cov", cov, "--stats", st, "--exclude", ex, "--out", plan + "3")
check(p.returncode == 2 and "README.txt" in p.stderr, "queue file without execs -> exit 2 naming it")
print("%d failure(s)" % len(failures)); sys.exit(1 if failures else 0)
