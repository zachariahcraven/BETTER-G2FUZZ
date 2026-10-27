#!/usr/bin/env python3
"""Step 3, statistics: one table per campaign, then per-program comparisons (PLAN.md "Measurements and analysis").

Reads, for every campaign in campaigns.sh order: its fuzzer_stats (execs, own-binary edges, saved crashes/hangs),
llm_calls.jsonl (calls, errors, latency), fuzz.log (in-run LLM mutation steps = "Gen-M start" lines), the
generators/gen_seeds folders, launch.txt (server; reruns), and the outputs of steps 1 and 2
(results/coverage/<c>.json, results/crashes/<c>.json). Pure Python (no scipy on Tempest).
Writes into results/:
  campaigns.tsv       one row per campaign, every metric
  by-arm.tsv          per program x arm: n, median and IQR of edges_final, unique_bugs, execs/s, edges_seeds;
                      bugs_union = distinct ASan buckets over the arm's reps
  tests.tsv           per program: G2FUZZ vs AFL++ per AFL++ version, and 4.32c vs 5.03c per fuzzer, on edges_final
                      and unique_bugs: medians, Vargha-Delaney A12 (first arm vs second), exact two-sided
                      Mann-Whitney U p-value (permutation over the 5+5 values, mid-ranks for ties)
  tests-excl-flagged.tsv  the same tests without the campaign(s) flagged fix-a (DRIFT.md 5.7), if any
  REPORT.md           the tables as markdown + the replication check against analysis/paper-table1.tsv
                      (the paper's Table 1: program, g2_gpt35_cov, g2_gpt35_bugs, g2_gpt4_cov, g2_gpt4_bugs,
                      afl_cmplog_cov, afl_cmplog_bugs; sign of G2FUZZ - AFL++(cmplog) per program, version, metric)
Usage: python3 03-stats.py [--study <folder>]   (default: the folder above this script). Safe to rerun.
"""
import argparse, collections, itertools, json, os, re, statistics, subprocess, sys

p = argparse.ArgumentParser()
p.add_argument("--study", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
a = p.parse_args()
STUDY = os.path.abspath(a.study); E = os.path.join(STUDY, "campaigns"); R = os.path.join(STUDY, "results")
PHASE = os.environ.get("G2F_PHASE", "B")           # campaigns.sh lists <PHASE>-*; phase C results go to results/phase-C/
if PHASE != "B": R = os.path.join(R, "phase-" + PHASE)
COV, CR = os.path.join(R, "coverage"), os.path.join(R, "crashes")
CRCAP = os.path.join(R, "crashes-cap1g")   # optional: triage rerun with the 1 GB allocation cap (02-crashes.sbatch, CAP=1)
ARMS = ["g2432", "afl432", "g2503", "afl503"]
PROGRAMS = ["exiv2", "gdk-pixbuf-pixdata", "imginfo", "jhead", "tiffsplit", "mp3gain", "ffmpeg", "flvmeta", "mp42aac", "pdftotext"]

def campaigns():
    out = subprocess.run(["bash", os.path.join(os.path.dirname(os.path.abspath(__file__)), "campaigns.sh"), E],
                         capture_output=True, text=True, check=True).stdout.split("\n")
    return [l.split() for l in out if l.strip()]

def kv(path):
    d = {}
    try:
        for l in open(path):
            if ":" in l: k, v = l.split(":", 1); d[k.strip()] = v.strip()
    except FileNotFoundError: pass
    return d

def jload(path):
    try: return json.load(open(path))
    except FileNotFoundError: return None

def nfiles(d):
    try: return len(os.listdir(d))
    except FileNotFoundError: return 0

def median_iqr(xs):
    xs = sorted(xs)
    if not xs: return ("NA", "NA", "NA")
    q = statistics.quantiles(xs, n=4) if len(xs) >= 2 else [xs[0], xs[0], xs[0]]
    return (statistics.median(xs), q[0], q[2])

def ranks(vals):
    """Mid-ranks (ties share the average rank)."""
    order = sorted(range(len(vals)), key=lambda i: vals[i]); r = [0.0] * len(vals); i = 0
    while i < len(order):
        j = i
        while j + 1 < len(order) and vals[order[j + 1]] == vals[order[i]]: j += 1
        for k in range(i, j + 1): r[order[k]] = (i + j) / 2 + 1
        i = j + 1
    return r

def mwu_a12(x, y):
    """Returns (A12, exact two-sided p). A12 = P(x > y) + 0.5 P(x = y); p by full enumeration of the
    C(n+m, n) label assignments of the pooled values (exact, conditional on the observed ties)."""
    n, m = len(x), len(y)
    if n == 0 or m == 0: return ("NA", "NA")
    pooled = list(x) + list(y); rk = ranks(pooled)
    def u_of(idx): return sum(rk[i] for i in idx) - n * (n + 1) / 2
    u_obs = u_of(range(n)); a12 = u_obs / (n * m); dev = abs(u_obs - n * m / 2)
    total = more = 0
    for idx in itertools.combinations(range(n + m), n):
        total += 1
        if abs(u_of(idx) - n * m / 2) >= dev - 1e-9: more += 1
    return (round(a12, 3), round(more / total, 4))

# ---- per campaign -------------------------------------------------------------------------------------------
rows = []
for name, prog, arm, rep in campaigns():
    d = os.path.join(E, name); o = os.path.join(d, prog + "_output", "default")
    fs = kv(os.path.join(o, "fuzzer_stats")); cov = jload(os.path.join(COV, name + ".json")); cr = jload(os.path.join(CR, name + ".json"))
    crc = jload(os.path.join(CRCAP, name + ".json"))
    run_time = int(fs.get("run_time", 0) or 0); execs = int(fs.get("execs_done", 0) or 0)
    try: vsecs = int((re.search(r"-V (\d+)", open(os.path.join(d, "run.sh")).read()) or [None, "21600"])[1])   # the campaign's own -V
    except (FileNotFoundError, TypeError): vsecs = 21600
    calls = []
    try: calls = [json.loads(l) for l in open(os.path.join(d, "llm_calls.jsonl")) if l.strip()]
    except FileNotFoundError: pass
    ok = sum(1 for c in calls if c.get("status") == "ok"); secs = [c["secs"] for c in calls if "secs" in c]
    start = int(fs.get("start_time", 0) or 0); first_call = min((c["ts"] for c in calls if "ts" in c), default=None)
    seedgen_min = round((start - first_call) / 60, 1) if (first_call and start and first_call < start) else "NA"
    try: steps = int(subprocess.run(["grep", "-c", "Gen-M start", os.path.join(d, "fuzz.log")], capture_output=True, text=True).stdout.strip() or 0)
    except Exception: steps = "NA"
    launch = open(os.path.join(d, "launch.txt")).read() if os.path.isfile(os.path.join(d, "launch.txt")) else ""
    server = (re.search(r"G2F_BASE_URL=(\S+)", launch) or [None, ""])[1]
    rerun = "yes" if re.search(r"rerun|reuse", launch, re.I) else "no"
    flag = "fix-a" if "AFL_IGNORE_SEED_PROBLEMS" in launch else ("rerun" if rerun == "yes" else "")
    outcomes = (cr or {}).get("outcomes", {})
    row = dict(campaign=name, program=prog, arm=arm, fuzzer="g2fuzz" if arm.startswith("g2") else "aflpp-cmplog",
               afl="4.32c" if arm.endswith("432") else "5.03c", rep=int(rep),
               # afl-fuzz checks -V between test cases, so run_time is 21600 or a little more; less = cut by the job limit
               complete="yes" if run_time >= vsecs else f"short({run_time})", secs=vsecs,
               execs_done=execs, execs_per_sec=round(execs / run_time, 1) if run_time else "NA",
               corpus_count=fs.get("corpus_count", "NA"), own_edges_found=fs.get("edges_found", "NA"),
               saved_crashes=fs.get("saved_crashes", "NA"), saved_hangs=fs.get("saved_hangs", "NA"),
               edges_final=cov["edges_final"] if cov else "NA", edges_seeds=cov["edges_seeds"] if cov else "NA",
               edges_1h=cov["edges_at"]["3600"] if cov else "NA", edges_3h=cov["edges_at"]["10800"] if cov else "NA",
               replayed=f"{cov['replayed']}/{cov['queue_files']}" if cov else "NA", over_1mb=cov["over_1mb"] if cov else "NA",
               unique_bugs=cr["unique_bugs"] if cr else "NA", unique_bugs_fn=cr.get("unique_bugs_fn", "NA") if cr else "NA",
               unique_bugs_cap=crc["unique_bugs"] if crc else "NA", asan_cap=crc["outcomes"].get("asan", 0) if crc else "NA",
               crash_files=cr["crash_files"] if cr else "NA",
               asan=outcomes.get("asan", 0) if cr else "NA", no_crash=outcomes.get("no-crash", 0) if cr else "NA",
               crash_timeout=outcomes.get("timeout", 0) if cr else "NA",
               llm_calls=len(calls), llm_ok=ok, llm_err=len(calls) - ok, llm_med_s=round(statistics.median(secs), 1) if secs else "NA",
               llm_steps=steps, generators=nfiles(os.path.join(o, "generators")), gen_seeds=nfiles(os.path.join(o, "gen_seeds")),
               seedgen_min=seedgen_min, server=server, rerun=rerun, flag=flag,
               _buckets={b["key"] for b in cr["buckets"]} if cr else set())
    rows.append(row)

os.makedirs(R, exist_ok=True)
cols = [k for k in rows[0] if not k.startswith("_")] if rows else []
with open(os.path.join(R, "campaigns.tsv"), "w") as h:
    h.write("\t".join(cols) + "\n")
    for r in rows: h.write("\t".join(str(r[c]) for c in cols) + "\n")

# ---- per program x arm ---------------------------------------------------------------------------------------
def vals(prog, arm, key):
    return [r[key] for r in rows if r["program"] == prog and r["arm"] == arm and isinstance(r[key], (int, float))]
by = []
for prog in PROGRAMS:
    for arm in ARMS:
        n = sum(1 for r in rows if r["program"] == prog and r["arm"] == arm)
        if not n: continue
        e = median_iqr(vals(prog, arm, "edges_final")); b = median_iqr(vals(prog, arm, "unique_bugs"))
        x = median_iqr(vals(prog, arm, "execs_per_sec")); s = median_iqr(vals(prog, arm, "edges_seeds"))
        union = set().union(*[r["_buckets"] for r in rows if r["program"] == prog and r["arm"] == arm])
        by.append(dict(program=prog, arm=arm, n=n, edges_med=e[0], edges_q1=e[1], edges_q3=e[2], bugs_med=b[0], bugs_q1=b[1],
                       bugs_q3=b[2], bugs_union=len(union), bugs_cap_med=median_iqr(vals(prog, arm, "unique_bugs_cap"))[0],
                       execs_s_med=x[0], edges_seeds_med=s[0],
                       llm_steps_med=median_iqr(vals(prog, arm, "llm_steps"))[0], complete=sum(1 for r in rows if r["program"] == prog and r["arm"] == arm and r["complete"] == "yes")))
with open(os.path.join(R, "by-arm.tsv"), "w") as h:
    if by: h.write("\t".join(by[0]) + "\n")
    for r in by: h.write("\t".join(str(v) for v in r.values()) + "\n")

# ---- tests ---------------------------------------------------------------------------------------------------
PAIRS = [("g2432", "afl432", "G2FUZZ vs AFL++ (4.32c)"), ("g2503", "afl503", "G2FUZZ vs AFL++ (5.03c)"),
         ("g2432", "g2503", "G2FUZZ 4.32c vs 5.03c"), ("afl432", "afl503", "AFL++ 4.32c vs 5.03c")]
def run_tests(skip_flag=None):
    """All pairwise tests; with skip_flag, campaigns whose flag equals it are left out (sensitivity check)."""
    out = []
    metrics = ("edges_final", "unique_bugs") + (("unique_bugs_cap",) if any(isinstance(r["unique_bugs_cap"], int) for r in rows) else ())
    for prog in PROGRAMS:
        for a1, a2, label in PAIRS:
            for key in metrics:
                x = [r[key] for r in rows if r["program"] == prog and r["arm"] == a1 and isinstance(r[key], (int, float)) and r["flag"] != skip_flag]
                y = [r[key] for r in rows if r["program"] == prog and r["arm"] == a2 and isinstance(r[key], (int, float)) and r["flag"] != skip_flag]
                if not x or not y: continue
                a12, pv = mwu_a12(x, y)
                out.append(dict(program=prog, comparison=label, metric=key, n=f"{len(x)}+{len(y)}", med_first=statistics.median(x),
                                med_second=statistics.median(y), A12=a12, p_exact=pv,
                                direction="first" if a12 != "NA" and a12 > 0.5 else "second" if a12 != "NA" and a12 < 0.5 else "tie"))
    return out
def write_tsv(path, table):
    with open(path, "w") as h:
        if table: h.write("\t".join(table[0]) + "\n")
        for t in table: h.write("\t".join(str(v) for v in t.values()) + "\n")
tests = run_tests(); write_tsv(os.path.join(R, "tests.tsv"), tests)
flagged = [r["campaign"] for r in rows if r["flag"] == "fix-a"]
tests_x = run_tests(skip_flag="fix-a") if flagged else []
if flagged: write_tsv(os.path.join(R, "tests-excl-flagged.tsv"), tests_x)

# ---- report --------------------------------------------------------------------------------------------------
def md(table, cols):
    if not table: return "(no data yet)\n"
    out = "| " + " | ".join(cols) + " |\n|" + "---|" * len(cols) + "\n"
    for r in table: out += "| " + " | ".join(str(r[c]) for c in cols) + " |\n"
    return out
paper = {}
pt = os.path.join(os.path.dirname(os.path.abspath(__file__)), "paper-table1.tsv")
if os.path.isfile(pt):
    hdr = None
    for l in open(pt):
        f = l.rstrip("\n").split("\t")
        if hdr is None: hdr = f; continue
        if len(f) == len(hdr): paper[f[0]] = dict(zip(hdr, f))
rep = [f"# Phase {PHASE} results (auto-generated by analysis/03-stats.py)\n",
       f"Campaigns: {len(rows)} ({sum(1 for r in rows if r['complete'] == 'yes')} complete; fuzzing time "
       f"{', '.join(sorted({str(r['secs'] // 3600) + ' h' for r in rows}))}); coverage replayed for "
       f"{sum(1 for r in rows if r['edges_final'] != 'NA')}, crashes triaged for {sum(1 for r in rows if r['unique_bugs'] != 'NA')}.\n",
       "Edges: every final queue replayed on the 4.32c `.afl` build with afl-showmap (one common binary). Bugs: crashes rerun on the "
       "`.asan` build, deduplicated by bug type + top 3 ASan frames (UNIFUZZ's rule). Reps: 5 per arm; median [Q1, Q3].\n",
       "## Per program and arm\n", md(by, ["program", "arm", "n", "complete", "edges_med", "edges_q1", "edges_q3", "edges_seeds_med",
                                          "bugs_med", "bugs_union", "bugs_cap_med", "execs_s_med", "llm_steps_med"]),
       "\n`bugs_cap_med`: the same triage with ASan's allocation cap at 1 GB (`max_allocation_size_mb=1024`), so an allocation "
       "over 1 GB is an `allocation-size-too-big` bug, the analog of `afl-fuzz -m 1024` saving those inputs as crashes; NA if "
       "that rerun has not been made (`CAP=1 bash submit.sh 02`).\n",
       "\n## Comparisons (exact Mann-Whitney U, Vargha-Delaney A12 of the first arm vs the second)\n",
       md(tests, ["program", "comparison", "metric", "med_first", "med_second", "A12", "p_exact", "direction"])]
if flagged:
    rep += [f"\n## Sensitivity: the same tests without the fix-a campaign(s) {', '.join(flagged)}\n",
            md(tests_x, ["program", "comparison", "metric", "n", "med_first", "med_second", "A12", "p_exact", "direction"])]
if paper:
    # paper-table1.tsv columns: program, then <variant>_cov / <variant>_bugs for g2_gpt35, g2_gpt4 and afl_cmplog
    chk = []
    for prog in PROGRAMS:
        t = {(x["comparison"], x["metric"]): x for x in tests if x["program"] == prog}; pp = paper.get(prog)
        if not pp: continue
        for variant, vlabel in (("g2_gpt35", "GPT-3.5"), ("g2_gpt4", "GPT-4")):
            for ver in ("4.32c", "5.03c"):
                for metric, pk in (("edges_final", "cov"), ("unique_bugs", "bugs")):
                    x = t.get((f"G2FUZZ vs AFL++ ({ver})", metric))
                    if not x: continue
                    try: ps = float(pp[f"{variant}_{pk}"].replace(",", "")) - float(pp[f"afl_cmplog_{pk}"].replace(",", ""))
                    except (KeyError, ValueError): continue
                    ours = x["direction"]; paper_dir = "first" if ps > 0 else "second" if ps < 0 else "tie"
                    name = lambda d: "G2FUZZ" if d == "first" else "AFL++" if d == "second" else "tie"
                    chk.append(dict(program=prog, paper_llm=vlabel, afl=ver, metric=metric, paper=name(paper_dir), ours=name(ours),
                                    A12=x["A12"], p=x["p_exact"], agree="yes" if ours == paper_dir else "no"))
    rep += ["\n## Replication check against the paper's Table 1 (sign of G2FUZZ - AFL++(cmplog); ties in the paper count as disagreement unless we tie too)\n",
            md(chk, ["program", "paper_llm", "afl", "metric", "paper", "ours", "A12", "p", "agree"])]
    for vlabel in ("GPT-3.5", "GPT-4"):
        sub = [c for c in chk if c["paper_llm"] == vlabel]
        if sub: rep.append(f"\nAgreement with the {vlabel} column: {sum(1 for c in sub if c['agree'] == 'yes')}/{len(sub)} (program, version, metric) cells.\n")
else:
    rep += ["\n(Replication check skipped: analysis/paper-table1.tsv not found.)\n"]
rep += ["\n## Notes\n", "- Own-binary `edges_found` from fuzzer_stats is kept in campaigns.tsv for reference only (not comparable across arms).\n",
        "- `llm_steps` = in-run LLM mutation steps (`Gen-M start` in fuzz.log); `seedgen_min` = minutes from the first LLM call to afl-fuzz start.\n",
        "- Reruns (`rerun=yes` in campaigns.tsv) started later than their siblings (DRIFT.md 5.7).\n"]
open(os.path.join(R, "REPORT.md"), "w").write("".join(rep))
print(f"{len(rows)} campaigns -> {R}/campaigns.tsv, by-arm.tsv, tests.tsv, REPORT.md")
