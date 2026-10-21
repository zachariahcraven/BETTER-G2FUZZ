#!/usr/bin/env python3
"""Judge test for tasks/seedcov-fix.md. Run from the workdir root. Uses a fake afl-showmap on PATH."""
import json, os, stat, subprocess, sys, tempfile
TOOL = os.path.abspath("experiments/analysis/lib/seed_cov.py")
failures = []
def check(c, m):
    print(("ok    " if c else "FAIL  ") + m)
    if not c: failures.append(m)
FAKE = r'''#!/usr/bin/env python3
# fake afl-showmap: -o OUT ... -- target FILE ; behaviour chosen by the input file's content
import sys, time, os
a = sys.argv; out = a[a.index("-o") + 1]; inp = a[-1]; body = open(inp).read()
if "SLEEP" in body: time.sleep(60)
if "NOMAP" in body: sys.exit(1)
lines = {"A": "1:1\n2:1\n", "B": "2:1\n3:4\n", "S": "1:1\n9:1\n", "BADLINE": "1:1\ngarbage\n5:1\n"}
key = body.strip().split()[0]
open(out, "w").write(lines.get(key, "7:1\n"))
sys.exit(2 if "CRASH" in body else 0)   # afl-showmap exits non-zero for crashes; not an error
'''
def run(files, stock=None, timeout_ms=1000):
    d = tempfile.mkdtemp(); bindir = os.path.join(d, "bin"); os.makedirs(bindir)
    f = os.path.join(bindir, "afl-showmap"); open(f, "w").write(FAKE); os.chmod(f, 0o755)
    tgt = os.path.join(d, "target"); open(tgt, "w").write("#!/bin/sh\n"); os.chmod(tgt, 0o755)
    sd = os.path.join(d, "seeds"); os.makedirs(sd)
    for n, c in files.items(): open(os.path.join(sd, n), "w").write(c)
    args = [sys.executable, TOOL, tgt, sd, "-t", str(timeout_ms)]
    if stock is not None:
        st = os.path.join(d, "stock"); os.makedirs(st)
        for n, c in stock.items(): open(os.path.join(st, n), "w").write(c)
        args += ["--stock", st]
    env = dict(os.environ, PATH=bindir + os.pathsep + os.environ["PATH"])
    return subprocess.run(args, capture_output=True, text=True, env=env, timeout=200)

p = run({"x-1_1.xml": "A", "x-1_2.xml": "B", "s.xml": "S"}, stock={"s.xml": "S"})
check(p.returncode == 0, "normal run exits 0 (%s)" % p.stderr[-200:])
if p.returncode == 0:
    j = json.loads(p.stdout)
    check(j["total_edges"] == 4 and j["stock_edges"] == 2 and j["new_edges"] == 2, "values unchanged (total 4, stock 2, new 2): %s" % j)
    check(j["per_generator"]["x-1"] == {"files": 2, "edges": 3, "unique": 2}, "per-generator union/unique unchanged: %s" % j["per_generator"])
p = run({"a_1.xml": "A CRASH", "b_1.xml": "B"})
check(p.returncode == 0 and json.loads(p.stdout)["total_edges"] == 3, "afl-showmap non-zero exit (crash) still counts its edges")
p = run({"a_1.xml": "A", "n_1.xml": "NOMAP", "c_1.xml": "BADLINE"})
check(p.returncode == 2 and p.stdout.strip() == "", "missing map / unparseable map -> exit 2, no JSON")
check("n_1.xml" in p.stderr and "c_1.xml" in p.stderr, "every failed input is named on stderr (got %r)" % p.stderr[-300:])
p = run({"a_1.xml": "A", "z_1.xml": "SLEEP"}, timeout_ms=1)
check(p.returncode == 2 and "z_1.xml" in p.stderr and p.stdout.strip() == "", "Python-level timeout -> exit 2 naming the input")
p = run({"a_1.xml": "A"}, stock={})
check(p.returncode == 2, "empty --stock folder -> exit 2")
print("\n%d failure(s)" % len(failures)); sys.exit(1 if failures else 0)
