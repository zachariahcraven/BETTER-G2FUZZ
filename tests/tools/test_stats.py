#!/usr/bin/env python3
"""Judge's acceptance test for experiments/analysis/stats (task: tasks/stats.md).

Run from the workdir root (the folder holding experiments/analysis/stats):
    uv run -q --python 3.10 --with scipy==1.14.1 python <this file>
Independent routes: hand-computed cases, scipy's exact permutation test, and a brute-force U here.
"""
import csv, io, itertools, json, math, os, random, shutil, subprocess, sys, tempfile

TOOL = os.path.abspath("experiments/analysis/stats")
failures = []


def check(cond, msg):
    print(("ok    " if cond else "FAIL  ") + msg)
    if not cond:
        failures.append(msg)


def run(cov_rows, crash_rows=(), extra=(), excl=None):
    d = tempfile.mkdtemp(prefix="stats_test_")
    cov, cr, out = (os.path.join(d, n) for n in ("cov.csv", "crashes.csv", "stats.csv"))
    with open(cov, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow("campaign,target,model,rep,seed_files,seed_edges,new_edges,generators,queue_edges".split(","))
        for name, v in cov_rows:
            w.writerow([name, "t", "m", name.rsplit("-r", 1)[-1], 1, 1, 0, 0, v])
    with open(cr, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow("campaign,target,model,rep,crash,kind,frames".split(","))
        for name, kind, frames in crash_rows:
            w.writerow([name, "t", "m", name.rsplit("-r", 1)[-1], "id:0", kind, frames])
    if excl is not None:
        ex = os.path.join(d, "excl.csv")
        with open(ex, "w", newline="") as f:
            w = csv.writer(f); w.writerow(["campaign", "reason"]); w.writerows(excl)
        extra = list(extra) + ["--exclude", ex]
    p = subprocess.run([sys.executable, TOOL, "--cov", cov, "--crashes", cr, "--out", out, *extra],
                       capture_output=True, text=True, cwd=d)   # own cwd: no default exclusions file is picked up
    rows = list(csv.DictReader(open(out))) if os.path.exists(out) else []
    raw = open(out, "rb").read() if os.path.exists(out) else b""
    shutil.rmtree(d)
    return p, rows, raw


def find(rows, exp, metric, arm, ref):
    r = [x for x in rows if (x["experiment"], x["metric"], x["arm"], x["reference"]) == (exp, metric, arm, ref)]
    return r[0] if len(r) == 1 else None


def brute(x, y):
    u = sum((a > b) + 0.5 * (a == b) for a in x for b in y)
    pooled, nx, ny = x + y, len(x), len(y)
    c = nx * ny / 2
    hits = tot = 0
    for idx in itertools.combinations(range(nx + ny), nx):
        s = set(idx)
        xs = [pooled[i] for i in idx]
        ys = [pooled[i] for i in range(nx + ny) if i not in s]
        uu = sum((a > b) + 0.5 * (a == b) for a in xs for b in ys)
        tot += 1
        hits += abs(uu - c) >= abs(u - c) - 1e-9
    return u, hits / tot


def close(a, b, tol=1e-6):
    return a not in ("", None) and abs(float(a) - b) <= tol * max(1, abs(b))


def runs(prefix, arm, vals):
    return [("%s-%s-r%d" % (prefix, arm, i + 1), v) for i, v in enumerate(vals)]


# 1. hand-computed: complete separation, n=3 vs 3: U=0 or 9, p = 2/20 = 0.1
p, rows, _ = run(runs("xml", "baseline", [1, 2, 3]) + runs("xml", "codernext", [4, 5, 6]))
check(p.returncode == 0, "runs on a minimal table (rc=%d, %s)" % (p.returncode, p.stderr.strip()[:200]))
r = find(rows, "xml", "coverage", "codernext", "baseline")
check(r is not None, "row xml/coverage/codernext vs baseline exists")
if r:
    check(close(r["U"], 9) and close(r["A12"], 1.0), "U=9, A12=1 for complete separation (got %s, %s)" % (r["U"], r["A12"]))
    check(close(r["p_exact"], 0.1), "exact two-sided p = 0.1 for 3 vs 3 separation (got %s)" % r["p_exact"])
    check(close(r["median_diff"], 3), "median_diff = 5 - 2 = 3 (got %s)" % r["median_diff"])
    check("min attainable p = 0.1" in r["note"], "note gives the min attainable p for n=3 (got %r)" % r["note"])

# 2. ties and unequal sizes vs brute force
x, y = [5, 5, 7, 9, 9], [5, 6, 7, 7, 8, 9]
p, rows, _ = run(runs("wad", "baseline", y) + runs("wad", "qwen4b", x))
r = find(rows, "wad", "coverage", "qwen4b", "baseline")
u, pp = brute(x, y)
check(r is not None and close(r["U"], u) and close(r["p_exact"], pp),
      "ties: U and exact p match brute force (want %s %.6g, got %s %s)" % (u, pp, r and r["U"], r and r["p_exact"]))

# 3. scipy's exact permutation test agrees on random data with ties
try:
    from scipy import stats as ss
    rng = random.Random(7)
    ok = True
    for trial in range(8):
        nx, ny = rng.randint(2, 6), rng.randint(2, 6)
        x = [rng.randint(0, 6) for _ in range(nx)]
        y = [rng.randint(0, 6) for _ in range(ny)]
        p, rows, _ = run(runs("png", "baseline", y) + runs("png", "gemma31b", x))
        r = find(rows, "png", "coverage", "gemma31b", "baseline")
        stat = lambda a, b, axis=0: sum((ai > bi) + 0.5 * (ai == bi) for ai in a for bi in b) - len(a) * len(b) / 2
        res = ss.permutation_test((x, y), lambda a, b: abs(stat(a, b)), permutation_type="independent",
                                  n_resamples=math.inf, alternative="greater", vectorized=False)
        if not (r and close(r["p_exact"], res.pvalue, 1e-6)):
            ok = False
            print("   mismatch", x, y, r and r["p_exact"], res.pvalue)
    check(ok, "exact p agrees with scipy.stats.permutation_test on 8 random tied samples")
except ImportError:
    check(False, "scipy available for the independent check")

# 4. comparison list: baseline arms, ctl pairs, bandit pairs; nothing extra
cov = (runs("xml", "baseline", [1, 2, 3, 4]) + runs("xml", "codernext", [5, 6, 7, 8]) +
       runs("xml", "ctl-junk", [1, 2, 2, 3]) + runs("xml", "ctl-llmseeds", [5, 5, 6, 7]) +
       [("bandit-xml-%s-r%d" % (a, i + 1), v) for a, vals in
        (("bandit", [3, 4, 5]), ("random", [3, 3, 4]), ("banditp5", [1, 2, 3]), ("randomp5", [2, 2, 2]),
         ("oraclep5", [9, 9, 9])) for i, v in enumerate(vals)])
p, rows, raw = run(cov)
pairs = sorted((r["experiment"], r["metric"], r["arm"], r["reference"]) for r in rows)
want = sorted([("xml", "coverage", a, "baseline") for a in ("codernext", "ctl-junk", "ctl-llmseeds")] +
              [("xml", "coverage", "ctl-llmseeds", "ctl-junk"), ("xml", "coverage", "codernext", "ctl-llmseeds"),
               ("bandit-xml", "coverage", "bandit", "random"), ("bandit-xml", "coverage", "banditp5", "randomp5"),
               ("bandit-xml", "coverage", "oraclep5", "randomp5"), ("bandit-xml", "coverage", "oraclep5", "banditp5")])
check(pairs == want, "exactly the fixed comparison list (extra: %s, missing: %s)" % (
    sorted(set(pairs) - set(want)), sorted(set(want) - set(pairs))))
check(not any(r["metric"] == "crash_sites" for r in rows), "no crash_sites metric outside wad/demo experiments")

# 5. Holm within the xml/coverage family (5 comparisons)
fam = [r for r in rows if r["experiment"] == "xml" and r["metric"] == "coverage"]
ps = sorted(((float(r["p_exact"]), r) for r in fam), key=lambda t: t[0])
m, run_max, ok = len(ps), 0.0, True
for j, (pv, r) in enumerate(ps):
    run_max = max(run_max, min(1.0, (m - j) * pv))
    ok &= close(r["p_holm"], run_max) and r["family_size"] == str(m)
check(ok and m == 5, "Holm adjustment and family_size within (experiment, metric)")

# 6. determinism and format
_, _, raw2 = run(cov)
check(raw == raw2 and raw, "two runs give byte-identical output")
hdr = raw.decode().splitlines()[0] if raw else ""
check(hdr == "experiment,metric,arm,reference,n_arm,n_ref,median_arm,median_ref,median_diff,ci_low,ci_high,U,p_exact,p_holm,A12,family_size,note",
      "header and column order")

# 7. crash sites: per run, distinct (kind, top frame); zero-crash runs count as 0
cov = runs("wad", "baseline", [10, 11, 12]) + runs("wad", "codernext", [13, 14, 15])
crashes = [("wad-codernext-r1", "SEGV", "f a.c:1 | g b.c:2"), ("wad-codernext-r1", "SEGV", "f a.c:1 | h c.c:3"),
           ("wad-codernext-r1", "heap-overflow", "f a.c:1"), ("wad-codernext-r2", "SEGV", "z q.c:9"),
           ("wad-baseline-r1", "SEGV", "f a.c:1"), ("wad-baseline-r2", "no-repro", ""),
           ("wad-baseline-r3", "hang", ""), ("wad-codernext-r3", "no-repro", "")]
p, rows, _ = run(cov, crashes)
r = find(rows, "wad", "crash_sites", "codernext", "baseline")
# codernext sites per run: r1 = {(SEGV,f a.c:1),(heap-overflow,f a.c:1)} = 2, r2 = 1, r3 = 0 -> median 1
# baseline: r1 = 1, r2 = 0 (no-repro is not a crash), r3 = 0 (hang) -> median 0
check(r is not None and close(r["median_arm"], 1) and close(r["median_ref"], 0) and r["n_ref"] == "3",
      "crash sites per run with zero-crash runs counted (got %s)" % ((r and (r["median_arm"], r["median_ref"], r["n_ref"])),))

# 8. n too small, bad names, orphan crash rows
p, rows, _ = run(runs("tiff", "baseline", [1, 2]) + runs("tiff", "qwen4b", [3]))
r = find(rows, "tiff", "coverage", "qwen4b", "baseline")
check(r is not None and r["p_exact"] == "" and r["note"] == "n too small", "n<2 -> no test, note 'n too small'")
p, _, _ = run([("weird_name", 5)])
check(p.returncode == 2, "unparseable campaign name -> exit 2")
p, _, _ = run(runs("wad", "baseline", [1, 2]), [("wad-ghost-r1", "SEGV", "f")])
check(p.returncode == 2, "crash rows for a campaign missing from cov-results -> exit 2")

# 9. bootstrap CI contains the median difference and is ordered
p, rows, _ = run(runs("xml", "baseline", [10, 12, 11, 13, 9]) + runs("xml", "qwen38", [20, 22, 19, 25, 21]))
r = find(rows, "xml", "coverage", "qwen38", "baseline")
check(r is not None and float(r["ci_low"]) <= float(r["median_diff"]) <= float(r["ci_high"]),
      "bootstrap CI brackets the median difference")

# 10. anti-gaming: the tool really reads its inputs (changing a value changes the output)
_, a, _ = run(runs("xml", "baseline", [1, 2, 3, 4]) + runs("xml", "codernext", [5, 6, 7, 8]))
_, b, _ = run(runs("xml", "baseline", [1, 2, 3, 4]) + runs("xml", "codernext", [5, 6, 7, 0]))
check(a != b, "output depends on the input values")

# 11. (added after the N-version comparison) comparison 3 is codernext ONLY; crash_sites only for Doom experiments
cov = (runs("wad", "baseline", [1, 2, 3, 4]) + runs("wad", "codernext", [5, 6, 7, 8]) + runs("wad", "gemma31b", [5, 5, 6, 6]) +
       runs("wad", "ctl-junk", [1, 2, 2, 3]) + runs("wad", "ctl-llmseeds", [5, 5, 6, 7]) +
       runs("lineup", "baseline", [1, 2, 3, 4]) + runs("lineup", "qwen4b", [2, 3, 4, 5]) +
       [("bandit-wad-%s-r%d" % (a, i + 1), v) for a, vals in (("bandit", [3, 4, 5, 6]), ("random", [3, 3, 4, 4])) for i, v in enumerate(vals)] +
       [("bandit-jhead-%s-r%d" % (a, i + 1), v) for a, vals in (("bandit", [3, 4, 5, 6]), ("random", [3, 3, 4, 4])) for i, v in enumerate(vals)])
crashes = [("lineup-qwen4b-r1", "SEGV", "f a.c:1"), ("bandit-jhead-bandit-r1", "SEGV", "f a.c:1"),
           ("bandit-wad-bandit-r1", "SEGV", "f a.c:1"), ("wad-codernext-r1", "SEGV", "f a.c:1")]
p, rows, raw = run(cov, crashes)
keys = {(r["experiment"], r["metric"], r["arm"], r["reference"]) for r in rows}
check(("wad", "coverage", "gemma31b", "ctl-llmseeds") not in keys and ("wad", "coverage", "codernext", "ctl-llmseeds") in keys,
      "comparison 3 only for codernext vs ctl-llmseeds")
check(not any(k[1] == "crash_sites" and k[0] in ("lineup", "bandit-jhead") for k in keys), "no crash_sites for lineup / bandit-jhead")
check(("bandit-wad", "crash_sites", "bandit", "random") in keys and ("wad", "crash_sites", "codernext", "baseline") in keys,
      "crash_sites for wad and bandit-wad")
r = find(rows, "wad", "coverage", "codernext", "baseline")
check(r is not None and r["note"] == "", "no note when both n >= 4 (got %r)" % (r and r["note"],))
import re as _re
badfmt = [v for line in raw.decode().splitlines()[1:] for v in line.split(",")[4:16]
          if v and not _re.fullmatch(r"-?\d+", v) and v != ("%.6g" % float(v))]
check(not badfmt, "every non-integer number formatted with %%.6g (bad: %s)" % badfmt[:5])
check(not any(_re.fullmatch(r"-?\d+\.0", v) for line in raw.decode().splitlines()[1:] for v in line.split(",")),
      "integer-valued numbers written as integers")

# 12. (added 2026-10-15 19:20, before any prompt-experiment data) comparison 5: prompt arms vs bare, same model
cov = (runs("wadp", "bare-codernext", [1, 2, 3, 4]) + runs("wadp", "name-codernext", [2, 3, 4, 5]) +
       runs("wadp", "spec-codernext", [3, 4, 5, 6]) + runs("wadp", "bare-qwen4b", [1, 1, 2, 2]) + runs("wadp", "spec-qwen4b", [2, 2, 3, 3]))
p, rows, raw = run(cov)
keys = sorted((r["experiment"], r["metric"], r["arm"], r["reference"]) for r in rows if r["metric"] == "coverage")
want = sorted([("wadp", "coverage", "name-codernext", "bare-codernext"), ("wadp", "coverage", "spec-codernext", "bare-codernext"),
               ("wadp", "coverage", "spec-qwen4b", "bare-qwen4b")])
check(keys == want, "comparison 5: prompt arms vs bare of the same model only (got %s)" % keys)
check(any(r["metric"] == "crash_sites" for r in rows), "wadp is a Doom experiment (crash_sites present)")

# 13. a missing input file is an error, never an empty result
pm = subprocess.run([sys.executable, TOOL, "--cov", "/nonexistent/cov.csv", "--crashes", "/nonexistent/c.csv",
                     "--out", os.path.join(tempfile.mkdtemp(), "o.csv")], capture_output=True, text=True)
check(pm.returncode == 2, "missing --cov file -> exit 2 (got %d)" % pm.returncode)

# 14. (from N-version round 2) note for 2 vs 2; empty / missing frames still form a site (kind, "")
p, rows, _ = run(runs("bandit-xml", "x", []) if False else (
        [("bandit-xml-bandit-r%d" % i, v) for i, v in enumerate([3, 1], 1)] + [("bandit-xml-random-r%d" % i, v) for i, v in enumerate([2, 4], 1)]))
r = find(rows, "bandit-xml", "coverage", "bandit", "random")
check(r is not None and r["note"] == "min attainable p = 0.333333", "2 vs 2 gets the note 'min attainable p = 0.333333' (got %r)" % ((r and r["note"]),))
cov = runs("wad", "baseline", [1, 2, 3]) + runs("wad", "codernext", [1, 2, 3])
crashes = [("wad-codernext-r%d" % i, k, fr) for i in (1, 2, 3) for k, fr in
           (("signal-4", ""), ("SEGV", ""), ("SEGV", "(no frames in the target's code)"), ("SEGV", "f a.c:1"), ("SEGV", "f a.c:1 | g b.c:2"))]
p, rows, _ = run(cov, crashes)
r = find(rows, "wad", "crash_sites", "codernext", "baseline")
# every codernext run: sites (signal-4,""), (SEGV,""), (SEGV,"(no frames...)"), (SEGV,"f a.c:1") = 4 -> median 4
check(r is not None and close(r["median_arm"], 4), "empty frames count as a site (kind, ''): 4 sites per run (got median %s)" % ((r and r["median_arm"]),))

# 15. (N-version round 3) min attainable p for unequal sizes; Holm from unrounded p values
p, rows, _ = run(runs("png", "baseline", [1, 5, 9]) + runs("png", "qwen4b", [4, 6]))
r = find(rows, "png", "coverage", "qwen4b", "baseline")
check(r is not None and r["note"] == "min attainable p = 0.2", "2 vs 3: min attainable p = 2/C(5,2) = 0.2 (got %r)" % ((r and r["note"]),))
# Holm: family of two equal comparisons -> both adjusted = min(1, 2 * p) from the EXACT p
x, y = [6, 3, 15, 0, 12], [13, 19, 0, 14, 8]   # exact p = 29/63; 2p rounds to 0.920635, 2*round(p) to 0.920634
pexact = brute(x, y)[1]
cov = runs("wad4ht", "baseline", y) + runs("wad4ht", "codernext", x) + runs("wad4ht", "qwen4b", x)
p, rows, _ = run(cov)
r = find(rows, "wad4ht", "coverage", "codernext", "baseline")
want = "%.6g" % min(1.0, 2 * pexact)
check(r is not None and r["family_size"] == "2" and r["p_holm"] == want and "%.6g" % (2 * float("%.6g" % pexact)) != want,
      "Holm adjusted from the unrounded p: want %s (exact p %r) got %s" % (want, pexact, (r and (r["p_exact"], r["p_holm"], r["family_size"]))))

# 16. (gauntlet a1-stats F1) an orphan campaign in crashes.csv is an error even if all its rows are no-repro/hang
p, _, _ = run(runs("wad", "baseline", [1, 2]), [("wad-ghost-r1", "no-repro", ""), ("wad-ghost-r1", "hang", "")])
check(p.returncode == 2, "orphan crash campaign with only no-repro/hang rows -> exit 2 (got %d)" % p.returncode)

# 17. exclusions: removed from cov and crash data; unknown campaign -> exit 2; reported on stderr
cov = runs("wad", "baseline", [10, 11, 12, 13]) + runs("wad", "codernext", [20, 21, 22, 23]) + [("wad-baseline-r5", 1)]
crashes = [("wad-baseline-r5", "SEGV", "f a.c:1"), ("wad-codernext-r1", "SEGV", "f a.c:1")]
p, rows, _ = run(cov, crashes, excl=[("wad-baseline-r5", "aborted early")])
r = find(rows, "wad", "coverage", "codernext", "baseline")
check(p.returncode == 0 and r is not None and r["n_ref"] == "4" and close(r["median_ref"], 11.5), "excluded campaign removed from coverage (n_ref 4, median 11.5; got %s)" % ((r and (r["n_ref"], r["median_ref"])),))
r = find(rows, "wad", "crash_sites", "codernext", "baseline")
check(r is not None and r["n_ref"] == "4" and close(r["median_ref"], 0), "excluded campaign removed from crash data")
check("excluded wad-baseline-r5: aborted early" in p.stderr, "exclusion reported on stderr")
cdir = tempfile.mkdtemp(); os.makedirs(os.path.join(cdir, "lineup-1h", "wad-aborted-r2"))
p, _, _ = run(cov, crashes, excl=[("wad-typo-r9", "x")], extra=["--campaigns", cdir])
check(p.returncode == 2 and "wad-typo-r9" in p.stderr, "unknown excluded campaign -> exit 2 naming it")
p, rows, _ = run(cov, crashes, excl=[("wad-aborted-r2", "never fuzzed"), ("wad-baseline-r5", "short")], extra=["--campaigns", cdir])
check(p.returncode == 0 and "excluded wad-aborted-r2: never fuzzed" in p.stderr and find(rows, "wad", "coverage", "codernext", "baseline") is not None,
      "excluded campaign with a folder but in no input is accepted and reported (rc %d %s)" % (p.returncode, p.stderr[-200:]))

# 18. (review finding) an excluded campaign with crash rows but no cov row is removed, not an orphan error
cdir2 = tempfile.mkdtemp(); os.makedirs(os.path.join(cdir2, "g", "wad-gone-r7"))
p, rows, _ = run(runs("wad", "baseline", [1, 2, 3, 4]) + runs("wad", "codernext", [5, 6, 7, 8]),
                 [("wad-gone-r7", "SEGV", "f a.c:1")], excl=[("wad-gone-r7", "aborted")], extra=["--campaigns", cdir2])
check(p.returncode == 0, "excluded campaign present only in crashes.csv is removed, not an error (rc %d)" % p.returncode)

print("\n%d failure(s)" % len(failures))
sys.exit(1 if failures else 0)
