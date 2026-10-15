#!/usr/bin/env python3
"""Acceptance test for cov_summary.py, written by the judge during the butler work (2026-10).
Run from anywhere. Fixture: real replay results in
tests/fixtures/cov (one JSON per campaign), plus a malformed file and a stray name.
Expected values are computed here independently.
"""
import csv, glob, json, os, re, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(os.path.join(ROOT, "experiments/analysis"))   # the tool under test runs from its own folder
FIX = os.path.join(ROOT, "tests/fixtures/cov")
OUT = os.path.join(tempfile.mkdtemp(prefix="covsum_"), "cov-results.csv")
failures = []


def check(cond, msg):
    print(("ok    " if cond else "FAIL  ") + msg)
    if not cond:
        failures.append(msg)


def parse(name):
    m = re.match(r"(lineup|tiff|png|xml|wad)(\d+h)?-(.+)-r(\d+)$", name)
    b = re.match(r"bandit-([a-z]+)-(\w+)-r(\d+)$", name)
    if b:
        return b.group(1), "sched-" + b.group(2), int(b.group(3))
    if m:
        t = "jhead" if m.group(1) == "lineup" else m.group(1)
        return t + ("-" + m.group(2) if m.group(2) else ""), m.group(3), int(m.group(4))
    return None


def median(v):
    v = sorted(v)
    n = len(v)
    return v[n // 2] if n % 2 else (v[n // 2 - 1] + v[n // 2]) // 2


def ranks(v):
    order = sorted(range(len(v)), key=lambda i: v[i])
    r = [0.0] * len(v)
    i = 0
    while i < len(v):
        j = i
        while j + 1 < len(v) and v[order[j + 1]] == v[order[i]]:
            j += 1
        for k in range(i, j + 1):
            r[order[k]] = (i + j) / 2 + 1
        i = j + 1
    return r


def spearman(x, y):
    rx, ry = ranks(x), ranks(y)
    mx, my = sum(rx) / len(rx), sum(ry) / len(ry)
    num = sum((a - mx) * (b - my) for a, b in zip(rx, ry))
    den = (sum((a - mx) ** 2 for a in rx) * sum((b - my) ** 2 for b in ry)) ** 0.5
    return num / den if den else 0.0


want = {}
for p in glob.glob(FIX + "/*.json"):
    name = os.path.basename(p)[:-5]
    k = parse(name)
    try:
        d = json.load(open(p))
        s, q = d["seeds"], d["queue"]
    except Exception:
        continue
    if not k:
        continue
    want[name] = {"target": k[0], "model": k[1], "rep": k[2], "seed_files": s["files"], "seed_edges": s["total_edges"],
                  "new_edges": s["new_edges"], "generators": len([g for g in s["per_generator"] if g != "stock"]),
                  "queue_edges": q["total_edges"]}

r = subprocess.run([sys.executable, "cov-summary", "--cov", FIX, "--out", OUT], capture_output=True, text=True, timeout=120)
check(r.returncode == 0 and "Traceback" not in r.stderr, "exits 0 (stderr: %s)" % r.stderr.strip()[-300:])
check("not-a-campaign" in r.stderr and "broken-r1" in r.stderr, "warns about the stray and the malformed file")
rows = list(csv.DictReader(open(OUT))) if os.path.exists(OUT) else []
check([x["campaign"] for x in rows] == sorted(want), "one CSV row per valid campaign, sorted (%d of %d)" % (len(rows), len(want)))
bad = [x["campaign"] for x in rows if x["campaign"] in want and any(
    str(want[x["campaign"]][c]) != x[c] for c in ("target", "model", "rep", "seed_files", "seed_edges", "new_edges", "generators", "queue_edges"))]
check(rows and not bad, "every CSV value is right (wrong: %s)" % bad[:5])

lines = r.stdout.splitlines()
groups = {}
for v in want.values():
    groups.setdefault((v["target"], v["model"]), []).append(v)
okg = 0
for (t, mo), vs in groups.items():
    exp = [str(median([v[c] for v in vs])) for c in ("seed_edges", "new_edges", "queue_edges")]
    if any(l.split()[:2] == [t, mo] and l.split()[2] == str(len(vs)) and l.split()[3:6] == exp for l in lines if len(l.split()) >= 6):
        okg += 1
check(okg == len(groups), "table: runs and the three medians right for every (target, model) (%d of %d)" % (okg, len(groups)))
order = [tuple(l.split()[:2]) for l in lines if len(l.split()) >= 6 and (l.split()[0], l.split()[1]) in groups]
by_t = {}
for t, mo in order:
    by_t.setdefault(t, []).append(median([v["queue_edges"] for v in groups[(t, mo)]]))
check(order and [t for t, _ in order] == sorted(t for t, _ in order) and all(v == sorted(v, reverse=True) for v in by_t.values()),
      "table sorted by target, then median queue edges descending")
for t in sorted({v["target"] for v in want.values()}):
    vs = [v for v in want.values() if v["target"] == t and v["model"] != "baseline" and not v["model"].startswith("sched-")]
    line = [l for l in lines if l.startswith("spearman %s:" % t)]
    if len(vs) < 4:
        check(not line, "spearman %s: skipped (only %d campaigns)" % (t, len(vs)))
        continue
    rho = spearman([v["seed_edges"] for v in vs], [v["queue_edges"] for v in vs])
    check(line and line[0].strip() == "spearman %s: rho=%.2f n=%d" % (t, rho, len(vs)), "spearman %s: rho=%.2f n=%d (got %s)" % (t, rho, len(vs), line))

print("\n%d failed" % len(failures) if failures else "\nall passed")
sys.exit(1 if failures else 0)
