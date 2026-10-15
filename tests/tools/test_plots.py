#!/usr/bin/env python3
"""Acceptance test for plots.py, written by the judge during the butler work (2026-10).
Run from anywhere:
    uv run -q --python 3.10 --with matplotlib==3.9.2 python <this file>
Uses real G2Fuzz campaign stats in tests/fixtures/plots/campaigns/fixture/.
"""
import csv, glob, os, struct, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(os.path.join(ROOT, "experiments/analysis/lib"))   # the tool under test runs from its own folder
FIX = os.path.join(ROOT, "tests/fixtures/plots/campaigns/fixture")   # one experiment folder
OUT = tempfile.mkdtemp(prefix="plots_test_")
failures = []


def check(cond, msg):
    print(("ok    " if cond else "FAIL  ") + msg)
    if not cond:
        failures.append(msg)


def png_size(path):
    with open(path, "rb") as f:
        head = f.read(24)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    return struct.unpack(">II", head[16:24])


def expected_edges(plot_data, minute):
    """Edges of the last plot_data row at or before minute*60 s; 0 before the first row."""
    best = 0
    for line in open(plot_data):
        if line.startswith("#") or not line.strip():
            continue
        f = [x.strip() for x in line.split(",")]
        if int(f[0]) <= minute * 60:
            best = int(f[12])
    return best


r = subprocess.run([sys.executable, "plots.py", "--eval", os.path.dirname(FIX), "--out", OUT], capture_output=True, text=True, timeout=300)
check(r.returncode == 0, "plots.py exits 0 (stderr: %s)" % r.stderr.strip()[-400:])

rows = []
p = os.path.join(OUT, "coverage.csv")
if os.path.exists(p):
    rows = list(csv.DictReader(open(p)))
check(rows and set(rows[0]) >= {"target", "model", "rep", "minute", "edges"}, "coverage.csv has target, model, rep, minute, edges")
key = {(r["target"], r["model"], int(r["rep"]), int(r["minute"])): int(r["edges"]) for r in rows} if rows else {}
camps = {(r["target"], r["model"], int(r["rep"])) for r in rows}
check(camps == {("jhead", "codernext", 1), ("jhead", "codernext", 2), ("jhead", "gemma31b", 1), ("jhead", "gemma31b", 2),
                ("jhead", "baseline", 1), ("jhead", "baseline", 2), ("tiff", "baseline", 1),
                ("tiff", "sched-bandit", 1), ("tiff", "sched-random", 1)},
      "campaigns found: lineup/tiff ones plus bandit-<tag>-<sched> as model sched-<sched>; smoke-*, empty ones skipped (got %s)" % sorted(camps))
for name, target, model, rep in (("lineup-codernext-r1", "jhead", "codernext", 1), ("lineup-baseline-r2", "jhead", "baseline", 2),
                                 ("tiff-baseline-r1", "tiff", "baseline", 1)):
    pd = glob.glob(os.path.join(FIX, name, "*_output", "default", "plot_data"))[0]
    ok = all(key.get((target, model, rep, m)) == expected_edges(pd, m) for m in (0, 1, 2, 5, 30, 60) if (target, model, rep, m) in key)
    check(ok and (target, model, rep, 1) in key, "%s: edges per minute match plot_data" % name)
last = max((m for (t, mo, re_, m) in key if (t, mo, re_) == ("jhead", "codernext", 1)), default=None)
check(last == 60 and key.get(("jhead", "codernext", 1, 60)) == 734, "lineup-codernext-r1 runs to minute 60 with 734 edges")

for name in ("coverage_jhead.png", "coverage_tiff.png", "final_edges.png", "bandit_tiff.png", "scheduler_tiff.png"):
    path = os.path.join(OUT, name)
    size = png_size(path) if os.path.exists(path) else None
    check(size is not None and size[0] >= 800 and os.path.getsize(path) > 10000,
          "%s is a PNG at least 800 px wide (got %s)" % (name, size))
check(not os.path.exists(os.path.join(OUT, "bandit_jhead.png")), "no bandit plot without bandit campaigns for that target")

r2 = subprocess.run([sys.executable, "plots.py", "--eval", tempfile.mkdtemp(), "--out", tempfile.mkdtemp()],
                    capture_output=True, text=True, timeout=120)
check(r2.returncode == 0 and "Traceback" not in r2.stderr, "an empty eval folder: exits 0, no traceback")

print("\noutput in", OUT)
print("%d failed" % len(failures) if failures else "all passed")
sys.exit(1 if failures else 0)
