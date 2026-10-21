#!/usr/bin/env python3
"""Judge test for tasks/provenance.md with a fake afl-showmap. Run from the workdir root."""
import csv, os, subprocess, sys, tempfile
TOOL = os.path.abspath("experiments/analysis/provenance")
failures = []
def check(c, m):
    print(("ok    " if c else "FAIL  ") + m)
    if not c: failures.append(m)
FAKE = r'''#!/usr/bin/env python3
import sys
a = sys.argv; out = a[a.index("-o") + 1]; body = open(a[-1]).read().split()
open(out, "w").write("".join("%s:1\n" % e for e in body))
'''
root = tempfile.mkdtemp(); camps = os.path.join(root, "campaigns"); tg = os.path.join(root, "targets"); os.makedirs(tg)
open(os.path.join(tg, "xml_fuzzer.afl"), "w").write("#!/bin/sh\n"); os.chmod(os.path.join(tg, "xml_fuzzer.afl"), 0o755)
bindir = os.path.join(root, "bin"); os.makedirs(bindir); open(os.path.join(bindir, "afl-showmap"), "w").write(FAKE); os.chmod(os.path.join(bindir, "afl-showmap"), 0o755)
def camp(name, queue, ncrash):
    o = os.path.join(camps, "g", name, "xml_fuzzer_output", "default")
    os.makedirs(os.path.join(o, "queue")); os.makedirs(os.path.join(o, "crashes"))
    for i, edges in enumerate(queue): open(os.path.join(o, "queue", "id:%06d,x" % i), "w").write(" ".join(map(str, edges)))
    for i in range(ncrash): open(os.path.join(o, "crashes", "id:%06d,sig:11" % i), "w").write("x")
    open(os.path.join(o, "crashes", "README.txt"), "w").write("not a crash")
camp("xml-a-r1", [[1, 2], [2, 3]], 2)        # 3 edges, 2 crashes
camp("xml-a-r2", [[5], [6], [7, 8]], 0)      # 4 edges
camp("xml-a-r3", [[1]], 1)                   # 1 edge
cov = os.path.join(root, "cov.csv"); cr = os.path.join(root, "cr.csv"); ex = os.path.join(root, "ex.csv"); out = os.path.join(root, "p.csv")
with open(cov, "w", newline="") as f:
    w = csv.writer(f); w.writerow("campaign,target,model,rep,seed_files,seed_edges,new_edges,generators,queue_edges".split(","))
    w.writerow(["xml-a-r1", "xml", "a", 1, 1, 1, 0, 0, 3]); w.writerow(["xml-a-r2", "xml", "a", 2, 1, 1, 0, 0, 5]); w.writerow(["xml-a-r3", "xml", "a", 3, 1, 1, 0, 0, 1])
with open(cr, "w", newline="") as f:
    w = csv.writer(f); w.writerow("campaign,target,model,rep,crash,kind,frames".split(","))
    w.writerow(["xml-a-r1", "xml", "a", 1, "id:0", "SEGV", "f"]); w.writerow(["xml-a-r1", "xml", "a", 1, "id:1", "SEGV", "f"]); w.writerow(["xml-a-r3", "xml", "a", 3, "id:0", "SEGV", "f"])
with open(ex, "w", newline="") as f:
    w = csv.writer(f); w.writerow(["campaign", "reason"]); w.writerow(["xml-a-r3", "short"])
env = dict(os.environ, PATH=bindir + os.pathsep + os.environ["PATH"])
p = subprocess.run([sys.executable, TOOL, "--n", "20", "--campaigns", camps, "--cov", cov, "--crashes", cr, "--exclusions", ex,
                    "--targets", tg, "--out", out], capture_output=True, text=True, env=env)
check(p.returncode == 0, "runs (%s)" % p.stderr[-300:])
rows = {r["campaign"]: r for r in csv.DictReader(open(out))} if os.path.exists(out) else {}
check(set(rows) == {"xml-a-r1", "xml-a-r2"}, "excluded campaign not sampled; others all sampled (got %s)" % sorted(rows))
r1, r2 = rows.get("xml-a-r1", {}), rows.get("xml-a-r2", {})
check(r1.get("rederived_queue_edges") == "3" and r1.get("queue_match") == "yes", "union of per-file maps = 3, match")
check(r2.get("rederived_queue_edges") == "4" and r2.get("queue_match") == "no", "mismatch reported (published 5, re-derived 4)")
check(r1.get("crash_files") == "2" and r1.get("published_crash_rows") == "2" and r1.get("crash_match") == "yes", "crash files counted (id:* only)")
check(r2.get("crash_files") == "0" and r2.get("crash_match") == "yes", "no crashes -> 0 = 0 rows")
check("1/2 queue_edges match" in p.stdout and "2/2 crash counts match" in p.stdout, "summary line (got %r)" % p.stdout[-200:])
src = open(TOOL).read()
check(not any(k in src for k in ("seed_cov", "crash_triage", "cov-summary", "import stats")), "independent: does not use the project tools")
print("\n%d failure(s)" % len(failures)); sys.exit(1 if failures else 0)
