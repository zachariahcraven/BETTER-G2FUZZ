#!/usr/bin/env python3
"""Acceptance test for replay_plot.py, written by the judge during the butler work (2026-10).
Run from anywhere, with matplotlib. Fixture: the real replay results
tests/fixtures/replay/cov-results.csv (target "wad" there has only sched-* rows).
Expected values are computed here independently.
"""
import csv, os, statistics, subprocess, sys, tempfile

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(os.path.join(ROOT, "experiments/analysis/lib"))   # the tool under test runs from its own folder
FIX = os.path.join(ROOT, "tests/fixtures/replay/cov-results.csv")
OUT = tempfile.mkdtemp(prefix="replay_")
failures = []


def check(cond, msg):
    print(("ok    " if cond else "FAIL  ") + msg)
    if not cond:
        failures.append(msg)


# fixture plus one malformed row
csvp = os.path.join(OUT, "in.csv")
with open(FIX) as f, open(csvp, "w") as g:
    g.write(f.read().rstrip("\n") + "\nxml-broken-r1,xml,broken,1,1,1,1,1,n/a\n")

groups = {}
for row in csv.DictReader(open(FIX)):
    if row["model"].startswith("sched-"):
        continue
    groups.setdefault(row["target"], {}).setdefault(row["model"], []).append(int(row["queue_edges"]))


def fmt(x):
    return str(int(x)) if x == int(x) else "%.1f" % x


want = []
for t in sorted(groups):
    med = {m: statistics.median(v) for m, v in groups[t].items()}
    b = med.get("baseline")
    order = (["baseline"] if b is not None else []) + sorted((m for m in med if m != "baseline"), key=lambda m: (-med[m], m))
    for m in order:
        gain = "" if b is None or m == "baseline" else "%.1f" % round(100 * (med[m] - b) / b, 1)
        want.append([t, m, str(len(groups[t][m])), fmt(med[m]), gain])

r = subprocess.run([sys.executable, "replay_plot.py", "--csv", csvp, "--out", OUT], capture_output=True, text=True, timeout=300)
check(r.returncode == 0 and "Traceback" not in r.stderr, "exits 0 (stderr: %s)" % r.stderr.strip()[-300:])
check("xml-broken-r1" in r.stderr, "warns about the malformed row")
p = os.path.join(OUT, "replay_gain.csv")
rows = list(csv.reader(open(p))) if os.path.exists(p) else []
check(rows[:1] == [["target", "model", "runs", "median_edges", "gain_pct"]], "replay_gain.csv header (got %s)" % rows[:1])
got = rows[1:]
check(len(got) == len(want), "one row per (target, model), sched-* and malformed rows left out (%d of %d)" % (len(got), len(want)))
bad = [w for w, g in zip(want, got) if w != g]
check(got and not bad and len(got) == len(want), "every row right and in order (first wrong, want vs got: %s)" %
      ([(w, g) for w, g in zip(want, got) if w != g][:2]))
for t in sorted(groups):
    f = os.path.join(OUT, "replay_%s.png" % t)
    ok = os.path.exists(f) and Image.open(f).size[0] >= 900
    check(ok, "replay_%s.png exists and is at least 900 px wide" % t)
check(not os.path.exists(os.path.join(OUT, "replay_wad.png")), "no figure for a target with only sched-* rows")
extra = sorted(set(os.listdir(OUT)) - {"in.csv", "replay_gain.csv"} - {"replay_%s.png" % t for t in groups})
check(not extra, "no other files (extra: %s)" % extra)

# controls are drawn in grey: a target with only the baseline and ctl-* columns gives a grey image,
# and adding an LLM model brings color back
def colored(path):
    im = Image.open(path).convert("RGB")
    return sum(1 for r, g, b in im.getdata() if max(r, g, b) - min(r, g, b) > 30)


ctl = os.path.join(OUT, "ctl.csv")
with open(ctl, "w") as g:
    g.write("campaign,target,model,rep,seed_files,seed_edges,new_edges,generators,queue_edges\n")
    for i, (m, v) in enumerate([("baseline", 2083), ("baseline", 2100), ("ctl-junk", 2064), ("ctl-junk", 2600),
                                ("ctl-llmseeds", 4477), ("ctl-llmseeds", 4500)]):
        g.write("x-%s-r%d,demo,%s,%d,1,1,1,1,%d\n" % (m, i, m, i, v))
O2 = tempfile.mkdtemp(prefix="replay_ctl_")
subprocess.run([sys.executable, "replay_plot.py", "--csv", ctl, "--out", O2], capture_output=True, timeout=120)
p = os.path.join(O2, "replay_demo.png")
n = colored(p) if os.path.exists(p) else -1
check(n == 0, "baseline + ctl-* only: the figure is all grey (%d colored pixels)" % n)
with open(ctl, "a") as g:
    g.write("x-codernext-r9,demo,codernext,9,1,1,1,1,4619\n")
O3 = tempfile.mkdtemp(prefix="replay_ctl_")
subprocess.run([sys.executable, "replay_plot.py", "--csv", ctl, "--out", O3], capture_output=True, timeout=120)
p = os.path.join(O3, "replay_demo.png")
n = colored(p) if os.path.exists(p) else -1
check(n > 50, "with an LLM model added, its column is in color (%d colored pixels)" % n)

r2 = subprocess.run([sys.executable, "replay_plot.py", "--csv", "/nonexistent.csv", "--out", tempfile.mkdtemp()],
                    capture_output=True, text=True, timeout=60)
check(r2.returncode == 0 and "Traceback" not in r2.stderr and r2.stderr.strip(), "missing --csv: message, exit 0, no traceback")

print("\noutput in", OUT)
print("%d failed" % len(failures) if failures else "all passed")
sys.exit(1 if failures else 0)
